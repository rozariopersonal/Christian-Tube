import { HttpErrorResponse } from '@angular/common/http';
import { Injectable, effect, inject, signal, untracked } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { ApiService } from '../api/api.service';
import { AuthService } from '../auth/auth.service';

export type SyncWatchItemType =
  | 'watch_later'
  | 'video_history'
  | 'video_playhead'
  | 'audio_playback'
  | 'liked_video'
  | 'liked_short';

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
    defaultPage?: string;
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
  likedVideos?: Array<{ video: Record<string, unknown>; likedAt: number }>;
  likedVideoTombstones?: Record<string, number>;
  likedShorts?: Array<{ video: Record<string, unknown>; likedAt: number }>;
  likedShortTombstones?: Record<string, number>;
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
  private wasExpired = false;
  private operationSequence = 0;
  private acknowledgedWrites = 0;

  get acknowledgementVersion(): number {
    return this.acknowledgedWrites;
  }
  private syncAllowed = false;
  private lastPullAt = 0;
  private inFlightSync: Promise<void> | null = null;
  private retryTimer: ReturnType<typeof setTimeout> | null = null;
  private retryDelayMs = 2000;

  constructor() {
    effect(() => {
      const user = this.auth.currentUser();
      const expired = this.auth.sessionExpired();
      const needsSignIn = this.auth.sessionNeedsSignIn();
      untracked(() => {
        const recovered = this.wasExpired && !expired;
        this.wasExpired = expired;

        if (user) {
          if (needsSignIn || !this.auth.canSync()) {
            if (this.activeUserId !== user.id) {
              this.activeUserId = user.id;
              this.pendingOps.set(this.readPendingMap(user.id));
              this.remoteState.set(null);
            }
            this.syncAllowed = false;
            return;
          }
          const prevUserId = this.activeUserId;
          const wasPaused = this.authPaused;
          const resumed = !this.syncAllowed;
          this.syncAllowed = true;
          this.activeUserId = user.id;
          if (!expired) {
            this.authPaused = false;
          }

          if (user.id.startsWith('guest_')) {
            this.writeStorage(KEY_LAST_GUEST_ID, user.id);
          } else {
            this.handoffGuestPendingOps(user.id);
          }

          if (prevUserId !== user.id) {
            this.pendingOps.set(this.readPendingMap(user.id));
            this.remoteState.set(null);
          }
          if (prevUserId !== user.id || wasPaused || resumed || recovered) {
            void this.pullAndFlush(true);
          }
        } else if (this.activeUserId !== null) {
          this.activeUserId = null;
          this.syncAllowed = false;
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
      opId: `${key}:${Date.now()}:${this.operationSequence++}`,
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
      opId: `${key}:${Date.now()}:${this.operationSequence++}`,
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

  likedItems(itemType: 'liked_video' | 'liked_short'): Array<Record<string, unknown>> {
    const state = this.remoteState();
    const items = itemType === 'liked_video' ? state?.likedVideos : state?.likedShorts;
    const tombstones = itemType === 'liked_video' ? state?.likedVideoTombstones : state?.likedShortTombstones;
    const byId = new Map<string, Record<string, unknown>>();
    for (const item of items ?? []) {
      const id = item.video['id'];
      if (typeof id === 'string' && id) byId.set(id, { ...item.video, id });
    }
    for (const id of Object.keys(tombstones ?? {})) byId.delete(id);
    for (const op of Object.values(this.pendingOps())) {
      if (op.kind !== 'watch_item' || op.itemType !== itemType) continue;
      if (op.isDeleted) byId.delete(op.itemId);
      else byId.set(op.itemId, byId.get(op.itemId) ?? { id: op.itemId });
    }
    return [...byId.values()];
  }

  likedIds(itemType: 'liked_video' | 'liked_short'): Set<string> {
    return new Set(this.likedItems(itemType).map((item) => item['id']).filter((id): id is string => typeof id === 'string' && !!id));
  }

  isLiked(itemType: 'liked_video' | 'liked_short', itemId: string): boolean {
    return !!itemId && this.likedIds(itemType).has(itemId);
  }

  setLiked(input: { itemType: 'liked_video' | 'liked_short'; itemId: string; liked: boolean }): void {
    this.remoteState.update((state) => {
      if (!state) return state;
      const isVideo = input.itemType === 'liked_video';
      const itemsKey = isVideo ? 'likedVideos' : 'likedShorts';
      const tombstonesKey = isVideo ? 'likedVideoTombstones' : 'likedShortTombstones';
      const items = (state[itemsKey] ?? []).filter((item) => String(item.video['id'] ?? '') !== input.itemId);
      const tombstones = { ...(state[tombstonesKey] ?? {}) };
      if (input.liked) {
        delete tombstones[input.itemId];
        items.unshift({ video: { id: input.itemId }, likedAt: this.nowServerAligned() });
      } else tombstones[input.itemId] = this.nowServerAligned();
      return { ...state, [itemsKey]: items, [tombstonesKey]: tombstones };
    });
    this.enqueueWatchItem({ itemType: input.itemType, itemId: input.itemId, isDeleted: !input.liked });
    void this.pullAndFlush(true);
  }

  async pullAndFlush(force = false): Promise<void> {
    const userId = this.auth.currentUser()?.id;
    if (!userId || !this.auth.canSync()) return;
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
        const version = this.acknowledgementVersion;
        const state = await firstValueFrom(
          this.api.get<RemoteSyncState>('/api/user/state'),
        );
        if (state && typeof state.serverTime === 'number') {
          this.clockOffsetMs = state.serverTime - Date.now();
          this.writeStorage(KEY_CLOCK_OFFSET, String(this.clockOffsetMs));
        }
        if (this.auth.currentUser()?.id === userId &&
            version === this.acknowledgementVersion && state) {
          this.remoteState.set(state);
        }
        this.retryDelayMs = 2000;
      } catch (err) {
        if (this.isAuthError(err)) {
          this.authPaused = true;
          this.auth.markSessionRejected();
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
    if (!userId || this.authPaused || !this.auth.canSync()) return;

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
    const acknowledgedSubscriptions: Array<[string, SyncOp]> = [];
    let acknowledgedPreferences: RemoteSyncState['preferences'];
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
          this.auth.markSessionRejected();
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
    if (this.auth.currentUser()?.id !== userId) return;
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
        acknowledgedPreferences = await firstValueFrom(
          this.api.patch<RemoteSyncState['preferences']>('/api/user/preferences', body),
        );
        for (const [key] of prefOps) keysToRemove.add(key);
      } catch (err) {
        if (this.isAuthError(err)) {
          this.authPaused = true;
          this.auth.markSessionRejected();
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
      if (this.auth.currentUser()?.id !== userId) return;
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
        acknowledgedSubscriptions.push([key, op]);
        keysToRemove.add(key);
      } catch (err) {
        if (this.isAuthError(err)) {
          this.authPaused = true;
          this.auth.markSessionRejected();
          return;
        }
        if (this.isPermanentClientError(err)) {
          keysToRemove.add(key);
        } else {
          shouldRetry = true;
        }
      }
    }

    if (this.auth.currentUser()?.id !== userId) return;
    if (keysToRemove.size > 0) {
      const latestMap = this.readPendingMap(userId);
      const completedSubscriptions = acknowledgedSubscriptions
        .filter(([key, op]) => latestMap[key]?.opId === op.opId);
      const preferencesAreCurrent = prefOps.some(([key, op]) =>
        latestMap[key]?.opId === op.opId,
      );
      for (const key of keysToRemove) {
        const sentOp = currentMap[key];
        const latestOp = latestMap[key];
        if (!latestOp || (sentOp && latestOp.opId === sentOp.opId)) {
          delete latestMap[key];
        }
      }
      this.writePendingMap(userId, latestMap);
      if (completedSubscriptions.length > 0 ||
          (acknowledgedPreferences && preferencesAreCurrent)) {
        this.acknowledgedWrites++;
        this.remoteState.update((state) => {
          if (!state) return state;
          const subscriptions = new Set(state.subscriptions);
          for (const [, op] of completedSubscriptions) {
            if (op.isActive) subscriptions.add(op.itemId);
            else subscriptions.delete(op.itemId);
          }
          return {
            ...state,
            subscriptions: state.subscriptions ? [...subscriptions] : undefined,
            preferences: preferencesAreCurrent
              ? acknowledgedPreferences ?? state.preferences
              : state.preferences,
          };
        });
      }
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
