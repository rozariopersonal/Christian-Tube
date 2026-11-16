import { Injectable, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { ApiService } from '../../../core/api/api.service';
import { Video, normalizeVideo } from '../models/video.model';

@Injectable({ providedIn: 'root' })
export class VideoService {
  private readonly api = inject(ApiService);

  readonly videos = signal<Video[]>([]);
  readonly isLoading = signal<boolean>(false);
  readonly hasMore = signal<boolean>(true);
  readonly error = signal<string | null>(null);

  readonly shorts = signal<Video[]>([]);
  readonly shortsLoading = signal<boolean>(false);
  readonly shortsError = signal<string | null>(null);

  private page = 1;
  private readonly limit = 24;
  private activeChannelId: string | null = null;
  private activeCategory: string | null = null;
  private subscribedIds: string[] = [];
  private onlySubscribed = false;

  setFilter(opts: {
    channelId?: string | null;
    category?: string | null;
    subscribedIds?: string[];
    onlySubscribed?: boolean;
  }): void {
    this.activeChannelId = opts.channelId ?? null;
    this.activeCategory =
      opts.category && opts.category !== 'All' ? opts.category : null;
    if (opts.subscribedIds !== undefined) {
      this.subscribedIds = opts.subscribedIds;
    }
    this.onlySubscribed = Boolean(opts.onlySubscribed);
    void this.fetchVideos(true);
  }

  async fetchVideos(refresh = false): Promise<void> {
    if (this.isLoading()) return;
    if (refresh) {
      this.page = 1;
      this.hasMore.set(true);
    }
    if (!this.hasMore()) return;

    this.isLoading.set(true);
    this.error.set(null);

    try {
      const params: Record<string, string | number | undefined> = {
        page: this.page,
        limit: this.limit,
        type: 'VIDEO',
      };
      if (this.activeChannelId) {
        params['channelId'] = this.activeChannelId;
      } else if (this.onlySubscribed && this.subscribedIds.length > 0) {
        params['channelIds'] = this.subscribedIds.join(',');
      }
      if (this.activeCategory) {
        params['category'] = this.activeCategory;
      }

      const res = await firstValueFrom(
        this.api.get<unknown>('/api/videos', params),
      );
      const list = this.extractList(res).map((item) => normalizeVideo(item));
      if (refresh) {
        this.videos.set(list);
      } else {
        const existingIds = new Set(this.videos().map((v) => v.id));
        this.videos.set([
          ...this.videos(),
          ...list.filter((v) => !existingIds.has(v.id)),
        ]);
      }
      this.hasMore.set(list.length >= this.limit);
      this.page += 1;
    } catch (err) {
      this.error.set(
        err instanceof Error ? err.message : 'Unable to load videos',
      );
    } finally {
      this.isLoading.set(false);
    }
  }

  async fetchVideoById(id: string): Promise<Video | null> {
    const cached = this.videos().find((v) => v.id === id);
    try {
      const res = await firstValueFrom(
        this.api.get<Record<string, unknown>>(`/api/videos/${id}`),
      );
      return normalizeVideo(res);
    } catch {
      return cached ?? null;
    }
  }

  async searchVideos(query: string): Promise<Video[]> {
    const q = query.trim();
    if (!q) return [];
    const res = await firstValueFrom(
      this.api.get<unknown>('/api/videos', { search: q, limit: 30 }),
    );
    return this.extractList(res).map((item) => normalizeVideo(item));
  }

  async fetchRelatedVideos(video: Video): Promise<Video[]> {
    const res = await firstValueFrom(
      this.api.get<unknown>('/api/videos', {
        channelId: video.channelId || undefined,
        limit: 12,
        type: 'VIDEO',
      }),
    );
    return this.extractList(res)
      .map((item) => normalizeVideo(item))
      .filter((v) => v.id !== video.id);
  }

  async fetchShorts(force = false): Promise<void> {
    if (!force && this.shorts().length > 0) return;
    this.shortsLoading.set(true);
    this.shortsError.set(null);
    try {
      const res = await firstValueFrom(
        this.api.get<unknown>('/api/videos', { type: 'SHORT', limit: 100 }),
      );
      this.shorts.set(this.extractList(res).map((item) => normalizeVideo(item)));
    } catch (err) {
      this.shortsError.set(
        err instanceof Error ? err.message : 'Unable to load shorts',
      );
    } finally {
      this.shortsLoading.set(false);
    }
  }

  private extractList(res: unknown): Record<string, unknown>[] {
    if (Array.isArray(res)) return res as Record<string, unknown>[];
    if (res && typeof res === 'object') {
      const obj = res as Record<string, unknown>;
      if (Array.isArray(obj['videos'])) {
        return obj['videos'] as Record<string, unknown>[];
      }
      if (Array.isArray(obj['data'])) {
        return obj['data'] as Record<string, unknown>[];
      }
    }
    return [];
  }
}
