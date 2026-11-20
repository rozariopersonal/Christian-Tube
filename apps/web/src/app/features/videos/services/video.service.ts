import { Injectable, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { ApiService } from '../../../core/api/api.service';
import { ChannelService } from '../../channels/services/channel.service';
import { Video, normalizeVideo } from '../models/video.model';

@Injectable({ providedIn: 'root' })
export class VideoService {
  private readonly api = inject(ApiService);
  private readonly channelService = inject(ChannelService);

  readonly videos = signal<Video[]>([]);
  readonly isLoading = signal<boolean>(false);
  readonly hasMore = signal<boolean>(true);
  readonly error = signal<string | null>(null);

  readonly shorts = signal<Video[]>([]);
  readonly shortsLoading = signal<boolean>(false);
  readonly shortsHasMore = signal<boolean>(true);
  readonly shortsError = signal<string | null>(null);

  private offset = 0;
  private shortsOffset = 0;
  private lastShortsChannelKey: string | null = null;
  private readonly limit = 24;
  private readonly shortsLimit = 30;
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
      this.offset = 0;
      this.hasMore.set(true);
    }
    if (!this.hasMore()) return;

    this.isLoading.set(true);
    this.error.set(null);

    try {
      const params: Record<string, string | number | undefined> = {
        offset: this.offset,
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
      this.offset += list.length;
      this.hasMore.set(list.length >= this.limit);
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

  async searchVideos(
    query: string,
    opts?: {
      type?: 'VIDEO' | 'SHORT' | 'ALL';
      sort?: 'relevance' | 'latest' | 'popular';
      limit?: number;
      offset?: number;
    },
  ): Promise<Video[]> {
    const q = query.trim();
    if (!q) return [];
    const res = await firstValueFrom(
      this.api.get<unknown>('/api/videos', {
        search: q,
        type: opts?.type ?? 'ALL',
        sort: opts?.sort ?? 'relevance',
        limit: opts?.limit ?? 24,
        offset: opts?.offset ?? 0,
      }),
    );
    return this.extractList(res).map((item) => normalizeVideo(item));
  }

  async queryVideos(params: {
    channelId?: string;
    channelIds?: string[];
    category?: string;
    type?: 'VIDEO' | 'SHORT' | 'ALL';
    search?: string;
    sort?: 'latest' | 'popular' | 'oldest' | 'relevance';
    limit?: number;
    offset?: number;
  }): Promise<Video[]> {
    const res = await firstValueFrom(
      this.api.get<unknown>('/api/videos', {
        channelId: params.channelId,
        channelIds: params.channelIds?.length
          ? params.channelIds.join(',')
          : undefined,
        category: params.category,
        type: params.type ?? 'VIDEO',
        search: params.search?.trim() || undefined,
        sort: params.sort ?? 'latest',
        limit: params.limit ?? 24,
        offset: params.offset ?? 0,
      }),
    );
    return this.extractList(res).map((item) => normalizeVideo(item));
  }

  async fetchRelatedVideos(video: Video): Promise<Video[]> {
    const res = await firstValueFrom(
      this.api.get<unknown>('/api/videos', {
        channelId: video.channelId || undefined,
        limit: 16,
        type: 'VIDEO',
      }),
    );
    return this.extractList(res)
      .map((item) => normalizeVideo(item))
      .filter((v) => v.id !== video.id);
  }

  async fetchShorts(refresh = false): Promise<void> {
    const followedIds = this.channelService.subscribedIds();
    if (followedIds.length === 0) {
      this.shorts.set([]);
      this.shortsOffset = 0;
      this.shortsHasMore.set(false);
      this.shortsError.set(null);
      this.lastShortsChannelKey = '';
      return;
    }

    const channelKey = [...followedIds].sort().join(',');
    if (this.lastShortsChannelKey !== null && this.lastShortsChannelKey !== channelKey) {
      refresh = true;
    }

    if (this.shortsLoading()) return;
    if (!refresh && this.shorts().length > 0 && !this.shortsHasMore()) return;
    if (refresh) {
      this.shortsOffset = 0;
      this.shortsHasMore.set(true);
    }
    if (!this.shortsHasMore()) return;

    this.shortsLoading.set(true);
    this.shortsError.set(null);
    try {
      const res = await firstValueFrom(
        this.api.get<unknown>('/api/videos', {
          type: 'SHORT',
          channelIds: followedIds.join(','),
          limit: this.shortsLimit,
          offset: this.shortsOffset,
        }),
      );
      const list = this.extractList(res).map((item) => normalizeVideo(item));
      if (refresh || this.shortsOffset === 0) {
        this.shorts.set(list);
      } else {
        const existing = new Set(this.shorts().map((s) => s.id));
        this.shorts.set([
          ...this.shorts(),
          ...list.filter((s) => !existing.has(s.id)),
        ]);
      }
      this.lastShortsChannelKey = channelKey;
      this.shortsOffset += list.length;
      this.shortsHasMore.set(list.length >= this.shortsLimit);
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
