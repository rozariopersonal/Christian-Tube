import { HttpErrorResponse } from '@angular/common/http';
import { Injectable, effect, inject, signal, untracked } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { ApiService } from '../api/api.service';
import { AuthService } from '../auth/auth.service';
import { UserSyncService } from './user-sync.service';

export interface SyncUserItem {
  id: string;
  userId?: string;
  itemType: 'highlight' | 'bookmark' | 'note' | 'text_range';
  feature: 'bible' | 'book' | 'article';
  targetId: string;
  versionId?: string;
  book?: string;
  chapter?: number;
  verseStart?: number;
  verseEnd?: number;
  startOffset?: number;
  endOffset?: number;
  color?: string | null;
  colorIndex?: number | null;
  text?: string;
  contextText?: string | null;
  payloadJson?: string | null;
  deleted: boolean;
  updatedAt: string;
  createdAt?: string;
}

const KEY_PENDING_PREFIX = 'ct_web_user_items_pending_v1_';

@Injectable({ providedIn: 'root' })
export class UserItemsSyncService {
  private readonly api = inject(ApiService);
  private readonly auth = inject(AuthService);
  private readonly userSync = inject(UserSyncService);

  readonly remoteItems = signal<SyncUserItem[]>([]);
  readonly pendingItems = signal<Record<string, SyncUserItem>>({});

  private activeUserId: string | null = null;
  private authPaused = false;
  private wasExpired = false;
  private lastPullAt = 0;
  private inFlightSync: Promise<void> | null = null;
  private retryTimer: ReturnType<typeof setTimeout> | null = null;
  private retryDelayMs = 2000;

  constructor() {
    effect(() => {
      const user = this.auth.currentUser();
      const expired = this.auth.sessionExpired();
      untracked(() => {
        const recovered = this.wasExpired && !expired;
        this.wasExpired = expired;

        if (user) {
          const changed = this.activeUserId !== user.id;
          this.activeUserId = user.id;
          if (!expired) {
            this.authPaused = false;
          }
          if (changed) {
            this.pendingItems.set(this.readPendingMap(user.id));
            this.remoteItems.set([]);
            if (!expired) {
              void this.pullAndFlush(true);
            }
          } else if (recovered) {
            void this.pullAndFlush(true);
          }
        } else if (this.activeUserId !== null) {
          this.activeUserId = null;
          this.authPaused = false;
          this.pendingItems.set({});
          this.remoteItems.set([]);
        }
      });
    });

    if (typeof window !== 'undefined') {
      window.addEventListener('online', () => {
        if (this.activeUserId) void this.pullAndFlush(true);
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
    }
  }

  userCacheKey(baseKey: string): string {
    return this.userSync.userCacheKey(baseKey);
  }

  enqueueItem(
    input: Omit<SyncUserItem, 'updatedAt' | 'userId'> & { updatedAt?: string },
  ): void {
    const userId = this.auth.currentUser()?.id;
    if (!userId || !input.id) return;
    const item: SyncUserItem = {
      ...input,
      userId,
      updatedAt:
        input.updatedAt ??
        new Date(this.userSync.nowServerAligned()).toISOString(),
    };
    const map = this.readPendingMap(userId);
    map[item.id] = item;
    this.writePendingMap(userId, map);
    void this.flushOutbox();
  }

  async pullAndFlush(force = false): Promise<void> {
    const userId = this.auth.currentUser()?.id;
    if (!userId || !this.auth.canSync()) return;
    const now = Date.now();
    if (!force && now - this.lastPullAt < 15_000) return;
    if (this.inFlightSync) return this.inFlightSync;

    this.lastPullAt = now;
    this.inFlightSync = (async () => {
      try {
        await this.flushOutbox();
        if (this.authPaused) return;
        const res = await firstValueFrom(
          this.api.get<{ serverTime?: number; items?: SyncUserItem[] }>(
            '/api/user/items',
          ),
        );
        if (this.auth.currentUser()?.id === userId && Array.isArray(res?.items)) {
          this.remoteItems.set(res.items);
        }
        this.retryDelayMs = 2000;
      } catch (err) {
        if (err instanceof HttpErrorResponse && err.status === 401) {
          this.authPaused = true;
        }
      } finally {
        this.inFlightSync = null;
      }
    })();

    return this.inFlightSync;
  }

  async flushOutbox(): Promise<void> {
    const userId = this.auth.currentUser()?.id;
    if (!userId || this.authPaused || !this.auth.canSync()) return;

    const currentMap = this.readPendingMap(userId);
    const entries = Object.entries(currentMap).filter(
      ([, v]) => v.userId === userId,
    );
    if (entries.length === 0) return;

    const toRemove = new Set<string>();
    let shouldRetry = false;

    try {
      const res = await firstValueFrom(
        this.api.post<{
          results?: Array<{ id: string; status: 'ok' | 'rejected' | 'retry' }>;
        }>('/api/user/items', {
          items: entries.map(([, item]) => item),
        }),
      );
      const statusMap = new Map(
        (res?.results || []).map((r) => [r.id, r.status]),
      );
      for (const [id] of entries) {
        const st = statusMap.get(id);
        if (st === 'ok' || st === 'rejected') {
          toRemove.add(id);
        } else {
          shouldRetry = true;
        }
      }
    } catch (err) {
      if (err instanceof HttpErrorResponse && err.status === 401) {
        this.authPaused = true;
        return;
      }
      if (
        err instanceof HttpErrorResponse &&
        (err.status === 400 || err.status === 404 || err.status === 422)
      ) {
        for (const [id] of entries) toRemove.add(id);
      } else {
        shouldRetry = true;
      }
    }

    if (toRemove.size > 0) {
      const latestMap = this.readPendingMap(userId);
      for (const id of toRemove) {
        const sent = currentMap[id];
        const latest = latestMap[id];
        if (!latest || (sent && latest.updatedAt === sent.updatedAt)) {
          delete latestMap[id];
        }
      }
      this.writePendingMap(userId, latestMap);
    }

    if (shouldRetry) {
      this.scheduleRetry();
    }
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

  private pendingKey(userId: string): string {
    return `${KEY_PENDING_PREFIX}${userId}`;
  }

  private readPendingMap(userId: string): Record<string, SyncUserItem> {
    try {
      const raw = localStorage.getItem(this.pendingKey(userId));
      const parsed = raw ? (JSON.parse(raw) as unknown) : {};
      return parsed && typeof parsed === 'object' && !Array.isArray(parsed)
        ? (parsed as Record<string, SyncUserItem>)
        : {};
    } catch {
      return {};
    }
  }

  private writePendingMap(
    userId: string,
    map: Record<string, SyncUserItem>,
  ): void {
    if (this.activeUserId === userId) {
      this.pendingItems.set({ ...map });
    }
    try {
      localStorage.setItem(this.pendingKey(userId), JSON.stringify(map));
    } catch {
      // ignore
    }
  }
}
