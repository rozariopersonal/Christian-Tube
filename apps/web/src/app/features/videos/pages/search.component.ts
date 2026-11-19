import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { ScreenClassService } from '../../../core/layout/screen-class.service';
import { InfiniteScrollTriggerDirective } from '../../../shared/ui/infinite-scroll-trigger.directive';
import { ChannelService } from '../../channels/services/channel.service';
import { Video, formatTimeAgo, formatViewCount } from '../models/video.model';
import { VideoService } from '../services/video.service';

type SearchTypeFilter = 'ALL' | 'VIDEO' | 'SHORT' | 'CHANNELS';
type SearchSort = 'relevance' | 'latest' | 'popular';

@Component({
  selector: 'app-search-page',
  standalone: true,
  imports: [
    FormsModule,
    RouterLink,
    InfiniteScrollTriggerDirective,
  ],
  template: `
    <div class="search-page max-width-box">
      @if (screen.isCompact()) {
        <div class="search-bar">
          <span class="material-symbols-rounded search-icon">search</span>
          <input
            type="search"
            class="search-input"
            placeholder="Search videos & channels..."
            [ngModel]="query()"
            (ngModelChange)="onQueryChange($event)"
          />
        </div>
      }

      <div class="filter-bar">
        <div class="filter-chips">
          @for (f of typeFilters; track f.id) {
            <button
              type="button"
              class="pill-chip"
              [class.active]="typeFilter() === f.id"
              (click)="selectType(f.id)"
            >
              {{ f.label }}
            </button>
          }
        </div>

        @if (typeFilter() !== 'CHANNELS') {
          <select
            class="sort-select"
            aria-label="Sort search results"
            [ngModel]="sort()"
            (ngModelChange)="selectSort($event)"
          >
            <option value="relevance">Relevance</option>
            <option value="latest">Newest</option>
            <option value="popular">Most viewed</option>
          </select>
        }
      </div>

      @if (loading() && results().length === 0) {
        <p class="hint">Searching...</p>
      } @else if (query().trim().length === 0) {
        <p class="hint">Type to search sermons, worship, and channels.</p>
      } @else if (filteredResults().length === 0 && matchedChannels().length === 0) {
        <p class="hint">No results for "{{ query() }}".</p>
      } @else {
        @if (matchedChannels().length > 0 && (typeFilter() === 'ALL' || typeFilter() === 'CHANNELS')) {
          <section class="section">
            <h2 class="section-title">Channels</h2>
            <div class="channel-rows">
              @for (ch of matchedChannels(); track ch.id) {
                <div class="channel-row">
                  <a class="ch-main" [routerLink]="['/channels', ch.id]">
                    @if (ch.avatarUrl) {
                      <img class="ch-avatar" [src]="ch.avatarUrl" [alt]="ch.title" />
                    } @else {
                      <span class="ch-avatar fallback">
                        {{ ch.title.slice(0, 1).toUpperCase() }}
                      </span>
                    }
                    <div class="ch-meta">
                      <span class="ch-name">{{ ch.title }}</span>
                      <span class="ch-sub">{{ ch.videoCount }} videos</span>
                    </div>
                  </a>
                  <button
                    type="button"
                    class="pill-chip"
                    [class.active]="!isFollowing(ch.id)"
                    (click)="channels.toggleSubscribe(ch.id)"
                  >
                    {{ isFollowing(ch.id) ? 'Following' : 'Follow' }}
                  </button>
                </div>
              }
            </div>
          </section>
        }

        @if (typeFilter() !== 'CHANNELS' && filteredResults().length > 0) {
          <section class="section">
            <div class="results-list">
              @for (v of filteredResults(); track v.id) {
                <a class="result-row" [routerLink]="['/watch', v.id]">
                  <div class="res-thumb-wrap">
                    <img
                      class="res-thumb"
                      [src]="v.thumbnailUrl"
                      [alt]="v.title"
                      loading="lazy"
                    />
                    @if (v.duration && v.duration !== '0:00') {
                      <span class="res-dur">{{ v.duration }}</span>
                    }
                  </div>
                  <div class="res-meta">
                    <h3 class="res-title">{{ v.title }}</h3>
                    <p class="res-stats">
                      @if (v.viewCount > 0) {
                        <span>{{ formatViews(v.viewCount) }}</span>
                      }
                      @if (v.viewCount > 0 && v.publishedAt) {
                        <span> · </span>
                      }
                      @if (v.publishedAt) {
                        <span>{{ formatTime(v.publishedAt) }}</span>
                      }
                    </p>
                    <p class="res-channel">{{ v.channelTitle }}</p>
                    @if (v.description) {
                      <p class="res-desc">{{ v.description }}</p>
                    }
                  </div>
                </a>
              }
            </div>

            @if (hasMore()) {
              <div
                class="load-more-wrap"
                appInfiniteScrollTrigger
                [disabled]="loading()"
                (triggered)="loadMore(false)"
              >
                @if (loading()) {
                  <span class="hint-inline">Loading more results...</span>
                }
              </div>
            }
          </section>
        }
      }
    </div>
  `,
  styles: [
    `
      .search-page {
        padding-top: 16px;
        padding-bottom: 40px;
      }

      .search-bar {
        display: flex;
        align-items: center;
        gap: 10px;
        height: 44px;
        padding: 0 14px;
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-pill);
        margin-bottom: 14px;
      }

      .search-icon {
        color: var(--on-surface-muted);
      }

      .search-input {
        flex: 1;
        border: none;
        outline: none;
        background: transparent;
        font-size: 15px;
      }

      .filter-bar {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        flex-wrap: wrap;
        margin-bottom: 18px;
      }

      .filter-chips {
        display: flex;
        align-items: center;
        gap: 8px;
        flex-wrap: wrap;
      }

      .sort-select {
        height: 34px;
        padding: 0 10px;
        border-radius: var(--radius-pill);
        border: 1px solid var(--surface-border);
        background-color: var(--surface);
        font-size: 13px;
      }

      .hint,
      .hint-inline {
        color: var(--on-surface-muted);
        text-align: center;
        padding: 32px 0;
        font-size: 13px;
      }

      .section {
        margin-bottom: 24px;
      }

      .section-title {
        margin: 0 0 12px;
        font-size: 15px;
        font-weight: 700;
      }

      .channel-rows {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }

      .channel-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        padding: 12px 14px;
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-md);
      }

      .ch-main {
        display: flex;
        align-items: center;
        gap: 12px;
        min-width: 0;
      }

      .ch-avatar {
        width: 48px;
        height: 48px;
        border-radius: var(--radius-pill);
        object-fit: cover;
        flex-shrink: 0;
      }

      .ch-avatar.fallback {
        display: grid;
        place-items: center;
        font-weight: 700;
        background-color: var(--accent-soft);
        color: var(--accent);
      }

      .ch-meta {
        display: flex;
        flex-direction: column;
        min-width: 0;
      }

      .ch-name {
        font-weight: 600;
        font-size: 15px;
      }

      .ch-sub {
        font-size: 12px;
        color: var(--on-surface-muted);
      }

      .results-list {
        display: flex;
        flex-direction: column;
        gap: 16px;
      }

      .result-row {
        display: grid;
        grid-template-columns: 1fr;
        gap: 12px;
        align-items: start;
      }

      @media (min-width: 600px) {
        .result-row {
          grid-template-columns: 300px 1fr;
          gap: 16px;
        }
      }

      .res-thumb-wrap {
        position: relative;
        aspect-ratio: 16 / 9;
        border-radius: var(--radius-md);
        overflow: hidden;
        background-color: var(--surface-variant);
      }

      .res-thumb {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }

      .res-dur {
        position: absolute;
        right: 8px;
        bottom: 8px;
        padding: 2px 6px;
        border-radius: 4px;
        font-size: 11px;
        font-weight: 600;
        background: rgba(0, 0, 0, 0.85);
        color: #ffffff;
      }

      .res-meta {
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 4px;
      }

      .res-title {
        margin: 0;
        font-size: 16px;
        font-weight: 600;
        line-height: 1.35;
      }

      .res-stats,
      .res-channel {
        margin: 0;
        font-size: 12px;
        color: var(--on-surface-muted);
      }

      .res-desc {
        margin: 4px 0 0;
        font-size: 12px;
        color: var(--on-surface-muted);
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }

      .load-more-wrap {
        min-height: 36px;
        display: flex;
        align-items: center;
        justify-content: center;
        margin-top: 20px;
      }
    `,
  ],
})
export class SearchComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly videoService = inject(VideoService);
  readonly channels = inject(ChannelService);
  readonly screen = inject(ScreenClassService);

  readonly typeFilters: readonly { id: SearchTypeFilter; label: string }[] = [
    { id: 'ALL', label: 'All' },
    { id: 'VIDEO', label: 'Videos' },
    { id: 'SHORT', label: 'Shorts' },
    { id: 'CHANNELS', label: 'Channels' },
  ];

  readonly query = signal<string>('');
  readonly typeFilter = signal<SearchTypeFilter>('ALL');
  readonly sort = signal<SearchSort>('relevance');
  readonly results = signal<Video[]>([]);
  readonly loading = signal<boolean>(false);
  readonly hasMore = signal<boolean>(true);

  private offset = 0;
  private readonly limit = 24;
  private debounceHandle: ReturnType<typeof setTimeout> | null = null;

  readonly matchedChannels = computed(() => {
    const q = this.query().trim().toLowerCase();
    if (!q) return [];
    return this.channels
      .channels()
      .filter((c) => c.title.toLowerCase().includes(q))
      .slice(0, 8);
  });

  readonly filteredResults = computed(() => {
    const f = this.typeFilter();
    if (f === 'CHANNELS') return [];
    return this.results();
  });

  ngOnInit(): void {
    void this.channels.fetchChannels();
    void this.channels.loadSubscriptions();
    this.route.queryParamMap.subscribe((qp) => {
      const q = qp.get('q') ?? '';
      if (q !== this.query()) {
        this.query.set(q);
        void this.loadMore(true);
      }
    });
  }

  onQueryChange(value: string): void {
    this.query.set(value);
    if (this.debounceHandle) clearTimeout(this.debounceHandle);
    this.debounceHandle = setTimeout(() => {
      void this.router.navigate([], {
        relativeTo: this.route,
        queryParams: { q: value.trim() || null },
        queryParamsHandling: 'merge',
        replaceUrl: true,
      });
      void this.loadMore(true);
    }, 300);
  }

  selectType(f: SearchTypeFilter): void {
    this.typeFilter.set(f);
    if (f !== 'CHANNELS') {
      void this.loadMore(true);
    }
  }

  selectSort(nextSort: SearchSort): void {
    this.sort.set(nextSort);
    void this.loadMore(true);
  }

  async loadMore(refresh: boolean): Promise<void> {
    const q = this.query().trim();
    if (!q) {
      this.results.set([]);
      this.hasMore.set(false);
      return;
    }
    if (this.loading() || this.typeFilter() === 'CHANNELS') return;
    if (refresh) {
      this.offset = 0;
      this.hasMore.set(true);
    }
    if (!this.hasMore()) return;

    this.loading.set(true);
    try {
      const type = this.typeFilter() === 'SHORT' ? 'SHORT' : this.typeFilter() === 'VIDEO' ? 'VIDEO' : 'ALL';
      const batch = await this.videoService.searchVideos(q, {
        type,
        sort: this.sort(),
        limit: this.limit,
        offset: this.offset,
      });
      if (refresh) {
        this.results.set(batch);
      } else {
        const seen = new Set(this.results().map((v) => v.id));
        this.results.set([
          ...this.results(),
          ...batch.filter((v) => !seen.has(v.id)),
        ]);
      }
      this.offset += batch.length;
      this.hasMore.set(batch.length >= this.limit);
    } finally {
      this.loading.set(false);
    }
  }

  isFollowing(id: string): boolean {
    return this.channels.subscribedIds().includes(id);
  }

  formatViews(n: number): string {
    return formatViewCount(n);
  }

  formatTime(iso: string): string {
    return formatTimeAgo(iso);
  }
}
