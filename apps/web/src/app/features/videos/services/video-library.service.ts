import { Injectable, computed, effect, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { ApiService } from '../../../core/api/api.service';
import { AuthService } from '../../../core/auth/auth.service';
import { Video } from '../models/video.model';

export interface WatchHistoryEntry {
  video: Video;
  progressSeconds: number;
  durationSeconds: number;
  watchedAt: number;
}

const HISTORY_STORAGE_KEY = 'ct_web_watch_history_v1';
const WATCH_LATER_STORAGE_KEY = 'ct_web_watch_later_v1';
const AUTOPLAY_STORAGE_KEY = 'ct_web_autoplay_v1';
const RECENT_SEARCHES_KEY = 'ct_web_recent_searches_v1';

@Injectable({ providedIn: 'root' })
export class VideoLibraryService {
  private readonly api = inject(ApiService);
  private readonly auth = inject(AuthService);

  readonly history = signal<WatchHistoryEntry[]>(this.readJson(HISTORY_STORAGE_KEY, []));
  readonly watchLater = signal<Video[]>(this.readJson(WATCH_LATER_STORAGE_KEY, []));
  readonly queue = signal<Video[]>([]);
  readonly autoplay = signal<boolean>(this.readBool(AUTOPLAY_STORAGE_KEY, true));
  readonly recentSearches = signal<string[]>(this.readJson(RECENT_SEARCHES_KEY, []));

  readonly watchLaterIds = computed(
    () => new Set(this.watchLater().map((v) => v.id)),
  );

  private syncedForUserId: string | null = null;

  constructor() {
    effect(() => {
      const user = this.auth.currentUser();
      if (user && user.id !== this.syncedForUserId) {
        this.syncedForUserId = user.id;
        void this.syncFromBackend();
      } else if (!user) {
        this.syncedForUserId = null;
      }
    });
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
    this.writeJson(WATCH_LATER_STORAGE_KEY, next);
    void this.persistToBackend('watch_later', next);
    return !exists;
  }

  removeFromWatchLater(videoId: string): void {
    const next = this.watchLater().filter((v) => v.id !== videoId);
    this.watchLater.set(next);
    this.writeJson(WATCH_LATER_STORAGE_KEY, next);
    void this.persistToBackend('watch_later', next);
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
      watchedAt: Date.now(),
    };
    const next = [entry, ...current].slice(0, 100);
    this.history.set(next);
    this.writeJson(HISTORY_STORAGE_KEY, next);
    void this.persistToBackend('video_history', next);
  }

  removeFromHistory(videoId: string): void {
    const next = this.history().filter((e) => e.video.id !== videoId);
    this.history.set(next);
    this.writeJson(HISTORY_STORAGE_KEY, next);
    void this.persistToBackend('video_history', next);
  }

  clearHistory(): void {
    this.history.set([]);
    this.writeJson(HISTORY_STORAGE_KEY, []);
    void this.persistToBackend('video_history', []);
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

  private async syncFromBackend(): Promise<void> {
    if (!this.auth.isAuthenticated()) return;
    try {
      const [histRes, wlRes] = await Promise.all([
        firstValueFrom(
          this.api.get<{ payloadJson?: string } | null>('/api/user/playback', {
            mediaType: 'video_history',
          }),
        ),
        firstValueFrom(
          this.api.get<{ payloadJson?: string } | null>('/api/user/playback', {
            mediaType: 'watch_later',
          }),
        ),
      ]);

      if (histRes?.payloadJson) {
        const remote = JSON.parse(histRes.payloadJson) as WatchHistoryEntry[];
        if (Array.isArray(remote) && remote.length > 0) {
          const merged = this.mergeHistory(this.history(), remote);
          this.history.set(merged);
          this.writeJson(HISTORY_STORAGE_KEY, merged);
        }
      }

      if (wlRes?.payloadJson) {
        const remote = JSON.parse(wlRes.payloadJson) as Video[];
        if (Array.isArray(remote) && remote.length > 0) {
          const existing = new Set(this.watchLater().map((v) => v.id));
          const merged = [
            ...this.watchLater(),
            ...remote.filter((v) => !existing.has(v.id)),
          ];
          this.watchLater.set(merged);
          this.writeJson(WATCH_LATER_STORAGE_KEY, merged);
        }
      }
    } catch {
      // Non-critical offline fallback
    }
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

  private async persistToBackend(
    mediaType: 'video_history' | 'watch_later',
    payload: unknown,
  ): Promise<void> {
    if (!this.auth.isAuthenticated()) return;
    try {
      await firstValueFrom(
        this.api.post('/api/user/playback', {
          mediaType,
          trackId: mediaType,
          positionSeconds: 0,
          durationSeconds: 0,
          payloadJson: JSON.stringify(payload),
        }),
      );
    } catch {
      // Non-critical
    }
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
