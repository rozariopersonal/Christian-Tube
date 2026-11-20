import { HttpErrorResponse } from '@angular/common/http';
import { Injectable, effect, inject, signal, untracked } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { ApiService } from '../api/api.service';
import { AuthService } from '../auth/auth.service';

export type SyncWatchItemType =
  | 'watch_later'
  | 'video_history'
  | 'video_playhead'
  | 'audio_playback';

export interface SyncOp {
  opId: string;
  userId: string;
  kind: 'watch_item' | 'subscription' | 'preference';
  itemType?: SyncWatchItemType;
  itemId: string;
  positionSeconds?: number;
  durationSeconds?: number;
  payloadJson?: string | null;
  isDeleted?: boolean;
  isActive?: boolean;
  prefField?: string;
  prefValue?: unknown;
  clientUpdatedAt: number;
}

export interface RemoteSyncState {
  serverTime: number;
  preferences?: {
    languages?: string[];
    primaryBibleVersionId?: string;
    themeMode?: string;
    accentColor?: string;
    hasCompletedOnboarding?: boolean;
    fieldTimestamps?: Record<string, number>;
  };
  subscriptions?: string[];
  subscriptionTombstones?: Record<string, number>;
  watchLater?: Array<{ video: Record<string, unknown>; updatedAt: number }>;
  watchLaterTombstones?: Record<string, number>;
  videoHistory?: Array<{
    video: Record<string, unknown>;
    progressSeconds: number;
    durationSeconds: number;
    watchedAt: number;
  }>;
  videoHistoryTombstones?: Record<string, number>;
  videoPlayheads?: Record<string, { positionSeconds: number; updatedAt: number }>;
  audioPlayback?: {
    trackId?: string;
    positionSeconds: number;
    durationSeconds: number;
    payloadJson?: string;
    updatedAt: number;
  } | null;
}

const KEY_CLOCK_OFFSET = 'ct_web_clock_offset_v1';
const KEY_PENDING_PREFIX = 'ct_web_sync_pending_v2_';
const KEY_LAST_GUEST_ID = 'ct_web_last_guest_id_v1';

@Injectable({ providedIn: 'root' })
export class UserSyncService {
  private readonly api = inject(ApiService);
  private readonly auth = inject(AuthService);

  readonly remoteState = signal<RemoteSyncState | null>(null);
  readonly pendingOps = signal<Record<string, SyncOp>>({});
  readonly isSyncing = signal<boolean>(false);

  private clockOffsetMs = this.readClockOffset();
  private activeUserId: string | null = null;
  private authPaused = false;
  private lastPullAt = 0;
  private inFlightSync: Promise<void> | null = null;
  private retryTimer: ReturnType<typeof setTimeout> | null = null;
  private retryDelayMs = 2000;

  constructor() {
    effect(() => {
      const user = this.auth.currentUser();
      untracked(() => {
        if (user) {
          const prevUserId = this.activeUserId;
          this.activeUserId = user.id;
          this.authPaused = false;

          if (user.id.startsWith('guest_')) {
            this.writeStorage(KEY_LAST_GUEST_ID, user.id);
          } else {
            this.handoffGuestPendingOps(user.id);
          }

          if (prevUserId !== user.id) {
            this.pendingOps.set(this.readPendingMap(user.id));
            this.remoteState.set(null);
            void this.pullAndFlush(true);
          }
        } else if (this.activeUserId !== null) {
          this.activeUserId = null;
          this.authPaused = false;
          this.pendingOps.set({});
          this.remoteState.set(null);
        }
      });
    });

    if (typeof window !== 'undefined') {
      window.addEventListener('online', () => {
        if (this.activeUserId) {
          void this.pullAndFlush(true);
        }
      });
      window.addEventListener('visibilitychange', () => {
        if (
          typeof document !== 'undefined' &&
          document.visibilityState === 'visible' &&
          this.activeUserId
        ) {
          void this.pullAndFlush(false);
        }
      });
      window.addEventListener('storage', (ev) => {
        if (
          this.activeUserId &&
          ev.key === this.pendingKey(this.activeUserId)
        ) {
          this.pendingOps.set(this.readPendingMap(this.activeUserId));
        }
      });
    }
  }

  nowServerAligned(): number {
    return Date.now() + this.clockOffsetMs;
  }

  userCacheKey(baseKey: string, userIdOverride?: string | null): string {
    const uid = userIdOverride ?? this.auth.currentUser()?.id ?? 'anon';
    return `${baseKey}_${uid}`;
  }

  enqueueSubscription(channelId: string, isActive: boolean): void {
    const userId = this.auth.currentUser()?.id;
    if (!userId || !channelId) return;
    const key = `sub:${channelId}`;
    const op: SyncOp = {
      opId: `${key}:${Date.now()}`,
      userId,
      kind: 'subscription',
      itemId: channelId,
      isActive,
      clientUpdatedAt: this.nowServerAligned(),
    };
    this.saveOp(userId, key, op);
    void this.flushOutbox();
  }

  enqueuePreference(field: string, value: unknown): void {
    const userId = this.auth.currentUser()?.id;
    if (!userId || !field) return;
    const key = `pref:${field}`;
    const op: SyncOp = {
      opId: `${key}:${Date.now()}`,
      userId,
      kind: 'preference',
      itemId: field,
      prefField: field,
      prefValue: value,
      clientUpdatedAt: this.nowServerAligned(),
    };
    this.saveOp(userId, key, op);
    void this.flushOutbox();
  }

  enqueueWatchItem(input: {
    itemType: SyncWatchItemType;
    itemId: string;
    positionSeconds?: number;
    durationSeconds?: number;
    payloadJson?: string | null;
    isDeleted?: boolean;
  }): void {
    const userId = this.auth.currentUser()?.id;
    if (!userId || !input.itemId) return;
    const key = `${input.itemType}:${input.itemId}`;
    const op: SyncOp = {
      opId: `${key}:${Date.now()}`,
      userId,
      kind: 'watch_item',
      itemType: input.itemType,
      itemId: input.itemId,
      positionSeconds: input.positionSeconds,
      durationSeconds: input.durationSeconds,
      payloadJson: input.payloadJson,
      isDeleted: Boolean(input.isDeleted),
      clientUpdatedAt: this.nowServerAligned(),
    };
    this.saveOp(userId, key, op);
    void this.flushOutbox();
  }

  async pullAndFlush(force = false): Promise<void> {
    const userId = this.auth.currentUser()?.id;
    if (!userId) return;
    const now = Date.now();
    if (!force && now - this.lastPullAt < 15_000) {
      return;
    }
    if (this.inFlightSync) {
      return this.inFlightSync;
    }

    this.lastPullAt = now;
    this.inFlightSync = (async () => {
      this.isSyncing.set(true);
      try {
        await this.flushOutbox();
        if (this.authPaused) return;
        const state = await firstValueFrom(
          this.api.get<RemoteSyncState>('/api/user/state'),
        );
        if (state && typeof state.serverTime === 'number') {
          this.clockOffsetMs = state.serverTime - Date.now();
          this.writeStorage(KEY_CLOCK_OFFSET, String(this.clockOffsetMs));
        }
        if (this.auth.currentUser()?.id === userId && state) {
          this.remoteState.set(state);
        }
        this.retryDelayMs = 2000;
      } catch (err) {
        if (this.isAuthError(err)) {
          this.authPaused = true;
        }
      } finally {
        this.isSyncing.set(false);
        this.inFlightSync = null;
      }
    })();

    return this.inFlightSync;
  }

  async flushOutbox(): Promise<void> {
    const userId = this.auth.currentUser()?.id;
    if (!userId || this.authPaused) return;

    const currentMap = this.readPendingMap(userId);
    const entries = Object.entries(currentMap);
    if (entries.length === 0) return;

    const watchOps: Array<[string, SyncOp]> = [];
    const prefOps: Array<[string, SyncOp]> = [];
    const subOps: Array<[string, SyncOp]> = [];

    for (const entry of entries) {
      if (entry[1].userId !== userId) continue;
      if (entry[1].kind === 'watch_item') watchOps.push(entry);
      else if (entry[1].kind === 'preference') prefOps.push(entry);
      else if (entry[1].kind === 'subscription') subOps.push(entry);
    }

    const keysToRemove = new Set<string>();
    let shouldRetry = false;

    // 1. Batch watch items
    if (watchOps.length > 0) {
      try {
        const res = await firstValueFrom(
          this.api.post<{
            serverTime?: number;
            results?: Array<{ opId: string; status: 'ok' | 'rejected' | 'retry' }>;
          }>('/api/user/watch-items/batch', {
            items: watchOps.map(([, op]) => ({
              opId: op.opId,
              itemType: op.itemType,
              itemId: op.itemId,
              positionSeconds: op.positionSeconds ?? 0,
              durationSeconds: op.durationSeconds ?? 0,
              payloadJson: op.payloadJson ?? null,
              isDeleted: Boolean(op.isDeleted),
              clientUpdatedAt: op.clientUpdatedAt,
            })),
          }),
        );
        const statusByOpId = new Map(
          (res?.results || []).map((r) => [r.opId, r.status]),
        );
        for (const [key, op] of watchOps) {
          const st = statusByOpId.get(op.opId);
          if (st === 'ok' || st === 'rejected') {
            keysToRemove.add(key);
          } else {
            shouldRetry = true;
          }
        }
      } catch (err) {
        if (this.isAuthError(err)) {
          this.authPaused = true;
          return;
        }
        if (this.isPermanentClientError(err)) {
          for (const [key] of watchOps) keysToRemove.add(key);
        } else {
          shouldRetry = true;
        }
      }
    }

    // 2. Coalesced preferences delta
    if (prefOps.length > 0) {
      const body: Record<string, unknown> = {};
      const fieldTimestamps: Record<string, number> = {};
      for (const [, op] of prefOps) {
        if (op.prefField) {
          body[op.prefField] = op.prefValue;
          fieldTimestamps[op.prefField] = op.clientUpdatedAt;
        }
      }
      body['fieldTimestamps'] = fieldTimestamps;

      try {
        await firstValueFrom(this.api.patch('/api/user/preferences', body));
        for (const [key] of prefOps) keysToRemove.add(key);
      } catch (err) {
        if (this.isAuthError(err)) {
          this.authPaused = true;
          return;
        }
        if (this.isPermanentClientError(err)) {
          for (const [key] of prefOps) keysToRemove.add(key);
        } else {
          shouldRetry = true;
        }
      }
    }

    // 3. Subscriptions
    for (const [key, op] of subOps) {
      try {
        if (op.isActive) {
          await firstValueFrom(
            this.api.post(`/api/channels/${op.itemId}/subscribe`, {
              clientUpdatedAt: op.clientUpdatedAt,
            }),
          );
        } else {
          await firstValueFrom(
            this.api.delete(
              `/api/channels/${op.itemId}/subscribe?clientUpdatedAt=${op.clientUpdatedAt}`,
            ),
          );
        }
        keysToRemove.add(key);
      } catch (err) {
        if (this.isAuthError(err)) {
          this.authPaused = true;
          return;
        }
        if (this.isPermanentClientError(err)) {
          keysToRemove.add(key);
        } else {
          shouldRetry = true;
        }
      }
    }

    if (keysToRemove.size > 0) {
      const latestMap = this.readPendingMap(userId);
      for (const key of keysToRemove) {
        const sentOp = currentMap[key];
        const latestOp = latestMap[key];
        if (!latestOp || (sentOp && latestOp.opId === sentOp.opId)) {
          delete latestMap[key];
        }
      }
      this.writePendingMap(userId, latestMap);
    }

    if (shouldRetry) {
      this.scheduleRetry();
    }
  }

  private handoffGuestPendingOps(newUserId: string): void {
    const guestId = this.readStorage(KEY_LAST_GUEST_ID);
    if (!guestId || guestId === newUserId) return;

    const guestOps = this.readPendingMap(guestId);
    const targetOps = this.readPendingMap(newUserId);
    for (const [key, op] of Object.entries(guestOps)) {
      if (!targetOps[key]) {
        targetOps[key] = { ...op, userId: newUserId };
      }
    }
    this.writePendingMap(newUserId, targetOps);
    this.removeStorage(this.pendingKey(guestId));
    this.removeStorage(KEY_LAST_GUEST_ID);
  }

  private saveOp(userId: string, key: string, op: SyncOp): void {
    const map = this.readPendingMap(userId);
    map[key] = op;
    this.writePendingMap(userId, map);
  }

  private scheduleRetry(): void {
    if (this.retryTimer || this.authPaused) return;
    const delay = this.retryDelayMs;
    this.retryDelayMs = Math.min(this.retryDelayMs * 2, 60_000);
    this.retryTimer = setTimeout(() => {
      this.retryTimer = null;
      void this.flushOutbox();
    }, delay);
  }

  private isAuthError(err: unknown): boolean {
    return err instanceof HttpErrorResponse && err.status === 401;
  }

  private isPermanentClientError(err: unknown): boolean {
    if (!(err instanceof HttpErrorResponse)) return false;
    return err.status === 400 || err.status === 404 || err.status === 422;
  }

  private pendingKey(userId: string): string {
    return `${KEY_PENDING_PREFIX}${userId}`;
  }

  private readPendingMap(userId: string): Record<string, SyncOp> {
    try {
      const raw = localStorage.getItem(this.pendingKey(userId));
      const parsed = raw ? (JSON.parse(raw) as unknown) : {};
      return parsed && typeof parsed === 'object' && !Array.isArray(parsed)
        ? (parsed as Record<string, SyncOp>)
        : {};
    } catch {
      return {};
    }
  }

  private writePendingMap(userId: string, map: Record<string, SyncOp>): void {
    if (this.activeUserId === userId) {
      this.pendingOps.set({ ...map });
    }
    try {
      localStorage.setItem(this.pendingKey(userId), JSON.stringify(map));
    } catch {
      // ignore storage quota errors
    }
  }

  private readClockOffset(): number {
    try {
      const raw = localStorage.getItem(KEY_CLOCK_OFFSET);
      const n = raw ? Number(raw) : 0;
      return Number.isFinite(n) ? n : 0;
    } catch {
      return 0;
    }
  }

  private readStorage(key: string): string | null {
    try {
      return localStorage.getItem(key);
    } catch {
      return null;
    }
  }

  private writeStorage(key: string, value: string): void {
    try {
      localStorage.setItem(key, value);
    } catch {
      // ignore
    }
  }

  private removeStorage(key: string): void {
    try {
      localStorage.removeItem(key);
    } catch {
      // ignore
    }
  }
}
