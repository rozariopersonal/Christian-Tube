import { Injectable, computed, effect, inject, signal, untracked } from '@angular/core';
import { AuthService } from '../../../core/auth/auth.service';
import { UserSyncService } from '../../../core/services/user-sync.service';
import { Video, normalizeVideo } from '../models/video.model';

export interface WatchHistoryEntry {
  video: Video;
  progressSeconds: number;
  durationSeconds: number;
  watchedAt: number;
}

const HISTORY_STORAGE_KEY = 'ct_web_watch_history_v1';
const WATCH_LATER_STORAGE_KEY = 'ct_web_watch_later_v1';
const PLAYHEADS_STORAGE_KEY = 'ct_web_video_playheads_v1';
const AUTOPLAY_STORAGE_KEY = 'ct_web_autoplay_v1';
const RECENT_SEARCHES_KEY = 'ct_web_recent_searches_v1';

export interface VideoPlayheadEntry {
  positionSeconds: number;
  updatedAt: number;
}

@Injectable({ providedIn: 'root' })
export class VideoLibraryService {
  private readonly auth = inject(AuthService);
  private readonly userSync = inject(UserSyncService);

  readonly history = signal<WatchHistoryEntry[]>([]);
  readonly watchLater = signal<Video[]>([]);
  readonly playheads = signal<Record<string, VideoPlayheadEntry>>({});
  readonly queue = signal<Video[]>([]);
  readonly autoplay = signal<boolean>(this.readBool(AUTOPLAY_STORAGE_KEY, true));
  readonly recentSearches = signal<string[]>(this.readJson(RECENT_SEARCHES_KEY, []));

  readonly watchLaterIds = computed(
    () => new Set(this.watchLater().map((v) => v.id)),
  );

  private syncedForUserId: string | null | undefined = undefined;

  constructor() {
    this.reloadFromUserCache();

    effect(() => {
      const user = this.auth.currentUser();
      const nextUid = user?.id ?? null;
      if (nextUid !== this.syncedForUserId) {
        this.syncedForUserId = nextUid;
        untracked(() => this.reloadFromUserCache());
      }
    });

    effect(() => {
      const remote = this.userSync.remoteState();
      if (!remote) return;
      untracked(() => this.applyRemoteState(remote));
    });
  }

  private reloadFromUserCache(): void {
    this.history.set(this.readUserJson(HISTORY_STORAGE_KEY, []));
    this.watchLater.set(this.readUserJson(WATCH_LATER_STORAGE_KEY, []));
    this.playheads.set(this.readUserJson(PLAYHEADS_STORAGE_KEY, {}));
  }

  isWatchLater(videoId: string): boolean {
    return this.watchLaterIds().has(videoId);
  }

  toggleWatchLater(video: Video): boolean {
    const exists = this.isWatchLater(video.id);
    const next = exists
      ? this.watchLater().filter((v) => v.id !== video.id)
      : [video, ...this.watchLater()];
    this.watchLater.set(next);
    this.writeUserJson(WATCH_LATER_STORAGE_KEY, next);
    this.userSync.enqueueWatchItem({
      itemType: 'watch_later',
      itemId: video.id,
      isDeleted: exists,
    });
    return !exists;
  }

  removeFromWatchLater(videoId: string): void {
    const next = this.watchLater().filter((v) => v.id !== videoId);
    this.watchLater.set(next);
    this.writeUserJson(WATCH_LATER_STORAGE_KEY, next);
    this.userSync.enqueueWatchItem({
      itemType: 'watch_later',
      itemId: videoId,
      isDeleted: true,
    });
  }

  recordProgress(
    video: Video,
    progressSeconds: number,
    durationSeconds: number,
  ): void {
    const cleanPos = Math.max(0, Math.floor(progressSeconds));
    const cleanDur = Math.max(0, Math.floor(durationSeconds));
    const current = this.history().filter((e) => e.video.id !== video.id);
    const entry: WatchHistoryEntry = {
      video,
      progressSeconds: cleanPos,
      durationSeconds: cleanDur,
      watchedAt: this.userSync.nowServerAligned(),
    };
    const next = [entry, ...current].slice(0, 100);
    this.history.set(next);
    this.writeUserJson(HISTORY_STORAGE_KEY, next);
    this.userSync.enqueueWatchItem({
      itemType: 'video_history',
      itemId: video.id,
      positionSeconds: cleanPos,
      durationSeconds: cleanDur,
      isDeleted: false,
    });
    this.saveVideoPosition(video.id, cleanPos);
  }

  removeFromHistory(videoId: string): void {
    const next = this.history().filter((e) => e.video.id !== videoId);
    this.history.set(next);
    this.writeUserJson(HISTORY_STORAGE_KEY, next);
    this.userSync.enqueueWatchItem({
      itemType: 'video_history',
      itemId: videoId,
      isDeleted: true,
    });
  }

  clearHistory(): void {
    const currentIds = this.history().map((e) => e.video.id);
    this.history.set([]);
    this.writeUserJson(HISTORY_STORAGE_KEY, []);
    for (const id of currentIds) {
      this.userSync.enqueueWatchItem({
        itemType: 'video_history',
        itemId: id,
        isDeleted: true,
      });
    }
  }

  progressFraction(videoId: string): number {
    const entry = this.history().find((e) => e.video.id === videoId);
    if (!entry || entry.durationSeconds <= 0) return 0;
    const ratio = entry.progressSeconds / entry.durationSeconds;
    if (ratio < 0.03) return 0;
    return Math.min(1, ratio);
  }

  resumeSeconds(videoId: string): number {
    const entry = this.history().find((e) => e.video.id === videoId);
    if (!entry) return 0;
    if (
      entry.durationSeconds > 0 &&
      entry.progressSeconds >= entry.durationSeconds - 10
    ) {
      return 0;
    }
    return entry.progressSeconds;
  }

  addToQueue(video: Video): void {
    if (this.queue().some((v) => v.id === video.id)) return;
    this.queue.set([...this.queue(), video]);
  }

  removeFromQueue(videoId: string): void {
    this.queue.set(this.queue().filter((v) => v.id !== videoId));
  }

  clearQueue(): void {
    this.queue.set([]);
  }

  consumeNextInQueue(): Video | null {
    const [next, ...rest] = this.queue();
    if (!next) return null;
    this.queue.set(rest);
    return next;
  }

  setAutoplay(enabled: boolean): void {
    this.autoplay.set(enabled);
    try {
      localStorage.setItem(AUTOPLAY_STORAGE_KEY, String(enabled));
    } catch {
      // ignore storage errors
    }
  }

  addRecentSearch(query: string): void {
    const trimmed = query.trim();
    if (!trimmed) return;
    const next = [
      trimmed,
      ...this.recentSearches().filter(
        (q) => q.toLowerCase() !== trimmed.toLowerCase(),
      ),
    ].slice(0, 10);
    this.recentSearches.set(next);
    this.writeJson(RECENT_SEARCHES_KEY, next);
  }

  removeRecentSearch(query: string): void {
    const next = this.recentSearches().filter((q) => q !== query);
    this.recentSearches.set(next);
    this.writeJson(RECENT_SEARCHES_KEY, next);
  }

  getVideoPosition(videoId: string): number {
    return this.playheads()[videoId]?.positionSeconds ?? 0;
  }

  saveVideoPosition(videoId: string, positionSeconds: number): void {
    if (!videoId) return;
    const cleanPos = Math.max(0, Math.round(positionSeconds));
    const next = {
      ...this.playheads(),
      [videoId]: {
        positionSeconds: cleanPos,
        updatedAt: this.userSync.nowServerAligned(),
      },
    };
    const trimmed = this.capPlayheads(next);
    this.playheads.set(trimmed);
    this.writeUserJson(PLAYHEADS_STORAGE_KEY, trimmed);
    this.userSync.enqueueWatchItem({
      itemType: 'video_playhead',
      itemId: videoId,
      positionSeconds: cleanPos,
      isDeleted: false,
    });
  }

  private applyRemoteState(remote: NonNullable<ReturnType<UserSyncService['remoteState']>>): void {
    const pending = this.userSync.pendingOps();

    // 1. Watch Later (respect pending ops + tombstones)
    if (Array.isArray(remote.watchLater)) {
      const tombstones = remote.watchLaterTombstones ?? {};
      const byId = new Map<string, { video: Video; updatedAt: number }>();
      for (const item of remote.watchLater) {
        const video = normalizeVideo(item.video);
        if (video.id) byId.set(video.id, { video, updatedAt: item.updatedAt });
      }
      for (const localV of this.watchLater()) {
        const op = pending[`watch_later:${localV.id}`];
        const tombTs = tombstones[localV.id] ?? 0;
        if (op) {
          if (op.isDeleted) {
            byId.delete(localV.id);
          } else {
            byId.set(localV.id, { video: localV, updatedAt: op.clientUpdatedAt });
          }
        } else if (!byId.has(localV.id) && tombTs === 0) {
          // Local-only guest/unpushed item not yet tombstoned
          byId.set(localV.id, { video: localV, updatedAt: 0 });
        }
      }
      for (const op of Object.values(pending)) {
        if (op.kind === 'watch_item' && op.itemType === 'watch_later' && op.isDeleted) {
          byId.delete(op.itemId);
        }
      }
      const nextWl = Array.from(byId.values())
        .sort((a, b) => b.updatedAt - a.updatedAt)
        .map((e) => e.video);
      this.watchLater.set(nextWl);
      this.writeUserJson(WATCH_LATER_STORAGE_KEY, nextWl);
    }

    // 2. Video History (respect pending ops + tombstones)
    if (Array.isArray(remote.videoHistory)) {
      const tombstones = remote.videoHistoryTombstones ?? {};
      const remoteEntries: WatchHistoryEntry[] = remote.videoHistory.map((h) => ({
        video: normalizeVideo(h.video),
        progressSeconds: h.progressSeconds,
        durationSeconds: h.durationSeconds,
        watchedAt: h.watchedAt,
      }));
      const localFiltered = this.history().filter((e) => {
        const op = pending[`video_history:${e.video.id}`];
        if (op?.isDeleted) return false;
        const tombTs = tombstones[e.video.id] ?? 0;
        if (tombTs > e.watchedAt && (!op || tombTs > op.clientUpdatedAt)) {
          return false;
        }
        return true;
      });
      const mergedHist = this.mergeHistory(localFiltered, remoteEntries).filter((e) => {
        const op = pending[`video_history:${e.video.id}`];
        return !op?.isDeleted;
      });
      this.history.set(mergedHist);
      this.writeUserJson(HISTORY_STORAGE_KEY, mergedHist);
    }

    // 3. Video Playheads
    if (remote.videoPlayheads) {
      const mergedPh = this.mergePlayheads(this.playheads(), remote.videoPlayheads);
      this.playheads.set(mergedPh);
      this.writeUserJson(PLAYHEADS_STORAGE_KEY, mergedPh);
    }
  }

  private mergePlayheads(
    local: Record<string, VideoPlayheadEntry>,
    remote: Record<string, VideoPlayheadEntry>,
  ): Record<string, VideoPlayheadEntry> {
    const merged: Record<string, VideoPlayheadEntry> = { ...remote };
    for (const [id, entry] of Object.entries(local)) {
      const prev = merged[id];
      if (!prev || entry.updatedAt > prev.updatedAt) {
        merged[id] = entry;
      }
    }
    return this.capPlayheads(merged);
  }

  private capPlayheads(
    map: Record<string, VideoPlayheadEntry>,
  ): Record<string, VideoPlayheadEntry> {
    const entries = Object.entries(map);
    if (entries.length <= 200) return map;
    entries.sort((a, b) => b[1].updatedAt - a[1].updatedAt);
    return Object.fromEntries(entries.slice(0, 200));
  }

  private mergeHistory(
    local: WatchHistoryEntry[],
    remote: WatchHistoryEntry[],
  ): WatchHistoryEntry[] {
    const map = new Map<string, WatchHistoryEntry>();
    for (const entry of [...remote, ...local]) {
      const prev = map.get(entry.video.id);
      if (!prev || entry.watchedAt > prev.watchedAt) {
        map.set(entry.video.id, entry);
      }
    }
    return Array.from(map.values())
      .sort((a, b) => b.watchedAt - a.watchedAt)
      .slice(0, 100);
  }

  private readUserJson<T>(baseKey: string, fallback: T): T {
    const key = this.auth.isAuthenticated()
      ? this.userSync.userCacheKey(baseKey)
      : baseKey;
    return this.readJson(key, fallback);
  }

  private writeUserJson(baseKey: string, value: unknown): void {
    const key = this.auth.isAuthenticated()
      ? this.userSync.userCacheKey(baseKey)
      : baseKey;
    this.writeJson(key, value);
  }

  private readJson<T>(key: string, fallback: T): T {
    try {
      const raw = localStorage.getItem(key);
      return raw ? (JSON.parse(raw) as T) : fallback;
    } catch {
      return fallback;
    }
  }

  private writeJson(key: string, value: unknown): void {
    try {
      localStorage.setItem(key, JSON.stringify(value));
    } catch {
      // ignore storage quota errors
    }
  }

  private readBool(key: string, fallback: boolean): boolean {
    try {
      const raw = localStorage.getItem(key);
      return raw === null ? fallback : raw === 'true';
    } catch {
      return fallback;
    }
  }
}
