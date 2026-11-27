import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { ScreenClassService } from '../../../core/layout/screen-class.service';
import { InfiniteScrollTriggerDirective } from '../../../shared/ui/infinite-scroll-trigger.directive';
import { BibleVersionPickerComponent } from '../../../shared/ui/bible-version-picker.component';
import { BibleSemanticHit } from '../../bible/models/bible.model';
import { BibleService } from '../../bible/services/bible.service';
import { ChannelService } from '../../channels/services/channel.service';
import { Video, formatTimeAgo, formatViewCount } from '../models/video.model';
import { VideoService } from '../services/video.service';

type SearchTypeFilter = 'ALL' | 'VIDEO' | 'SHORT' | 'CHANNELS' | 'BIBLE';
type SearchSort = 'relevance' | 'latest' | 'popular';

@Component({
  selector: 'app-search-page',
  standalone: true,
  imports: [
    FormsModule,
    RouterLink,
    InfiniteScrollTriggerDirective,
    BibleVersionPickerComponent,
  ],
  template: `
    <div class="search-page max-width-box">
      @if (screen.isCompact()) {
        <form class="search-bar" (ngSubmit)="submitCompactSearch()">
          <span class="material-symbols-rounded search-icon">search</span>
          <input
            type="search"
            class="search-input"
            placeholder="Search videos, Bible & channels..."
            [ngModel]="query()"
            name="qCompact"
            (ngModelChange)="query.set($event)"
          />
          <button type="submit" class="pill-chip active">Go</button>
        </form>
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

      @if (loading() && results().length === 0 && bibleResults().length === 0) {
        <p class="hint">Searching...</p>
      } @else if (query().trim().length === 0) {
        <p class="hint">Type to search sermons, worship, Bible verses, and channels.</p>
      } @else if (filteredResults().length === 0 && matchedChannels().length === 0 && visibleBibleResults().length === 0) {
        <p class="hint">No results for "{{ query() }}".</p>
      } @else {
        @if (visibleBibleResults().length > 0) {
          <section class="section">
            <div class="section-head">
              <h2 class="section-title">Bible</h2>
              <div class="bible-head-actions">
                <app-bible-version-picker
                  contextKey="bible-search"
                  [maxSelections]="1"
                  [alignRight]="true"
                  (selectionChanged)="onBibleVersionChange($event.primary)"
                />
                @if (typeFilter() === 'ALL' && bibleResults().length > 3) {
                  <a
                    class="see-all-link"
                    [routerLink]="['/bible/search']"
                    [queryParams]="{ q: query().trim(), scope: 'all' }"
                  >
                    See all Bible results
                  </a>
                }
              </div>
            </div>
            <div class="bible-rows">
              @for (b of visibleBibleResults(); track b.id) {
                <a
                  class="bible-row"
                  [routerLink]="['/bible', bibleService.version(), b.bookNumber, b.chapter, b.verse]"
                >
                  <div class="bible-row-head">
                    <span class="bible-ref">{{ b.reference }}</span>
                    @if (b.kind === 'passage') {
                      <span class="bible-kind-pill">Passage</span>
                    }
                  </div>
                  <p class="bible-text">{{ b.text }}</p>
                </a>
              }
            </div>
          </section>
        }

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

      .section-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        margin-bottom: 12px;
      }

      .section-title {
        margin: 0 0 12px;
        font-size: 15px;
        font-weight: 700;
      }

      .section-head .section-title {
        margin-bottom: 0;
      }

      .bible-head-actions {
        display: flex;
        align-items: center;
        gap: 10px;
      }

      .see-all-link {
        font-size: 13px;
        font-weight: 600;
        color: var(--accent);
      }

      .bible-rows {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }

      .bible-row {
        display: block;
        padding: 12px 14px;
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-md);
      }

      .bible-row:hover {
        border-color: var(--accent);
      }

      .bible-row-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
        margin-bottom: 4px;
      }

      .bible-ref {
        font-size: 13px;
        font-weight: 700;
        color: var(--accent);
      }

      .bible-kind-pill {
        font-size: 11px;
        font-weight: 600;
        padding: 2px 8px;
        border-radius: var(--radius-pill);
        background-color: var(--accent-soft);
        color: var(--accent);
      }

      .bible-text {
        margin: 0;
        font-size: 13px;
        line-height: 1.45;
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
        grid-template-columns: 140px 1fr;
        gap: 12px;
        align-items: start;
      }

      @media (min-width: 600px) {
        .result-row {
          grid-template-columns: clamp(200px, 34vw, 300px) 1fr;
          gap: 16px;
        }
      }

      @media (max-width: 599px) {
        .res-title {
          font-size: 14px;
        }

        .res-desc {
          display: none;
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
  readonly bibleService = inject(BibleService);
  readonly channels = inject(ChannelService);
  readonly screen = inject(ScreenClassService);

  readonly typeFilters: readonly { id: SearchTypeFilter; label: string }[] = [
    { id: 'ALL', label: 'All' },
    { id: 'VIDEO', label: 'Videos' },
    { id: 'SHORT', label: 'Shorts' },
    { id: 'CHANNELS', label: 'Channels' },
    { id: 'BIBLE', label: 'Bible' },
  ];

  readonly query = signal<string>('');
  readonly typeFilter = signal<SearchTypeFilter>('ALL');
  readonly sort = signal<SearchSort>('relevance');
  readonly results = signal<Video[]>([]);
  readonly bibleResults = signal<BibleSemanticHit[]>([]);
  readonly loading = signal<boolean>(false);
  readonly hasMore = signal<boolean>(true);

  private offset = 0;
  private readonly limit = 24;
  private rawBibleResults: BibleSemanticHit[] = [];

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
    if (f === 'CHANNELS' || f === 'BIBLE') return [];
    return this.results();
  });

  readonly visibleBibleResults = computed(() => {
    const f = this.typeFilter();
    if (f !== 'ALL' && f !== 'BIBLE') return [];
    const hits = this.bibleResults();
    return f === 'ALL' ? hits.slice(0, 3) : hits;
  });

  ngOnInit(): void {
    void this.channels.fetchChannels();
    void this.channels.loadSubscriptions();
    if (this.bibleService.books().length === 0) {
      void this.bibleService.loadChapter(
        this.bibleService.bookNumber(),
        this.bibleService.chapter(),
      );
    }
    this.route.queryParamMap.subscribe((qp) => {
      const q = qp.get('q') ?? '';
      if (q !== this.query()) {
        this.query.set(q);
        void this.loadMore(true);
      }
    });
  }

  submitCompactSearch(): void {
    const q = this.query().trim();
    void this.router.navigate([], {
      relativeTo: this.route,
      queryParams: { q: q || null },
      queryParamsHandling: 'merge',
    });
    void this.loadMore(true);
  }

  async onBibleVersionChange(versionId: string): Promise<void> {
    await this.bibleService.loadVersion(
      versionId,
      this.bibleService.bookNumber(),
      this.bibleService.chapter(),
    );
    if (this.rawBibleResults.length > 0) {
      const localized = await this.bibleService.resolveSearchHitsInVersion(
        this.rawBibleResults,
        this.bibleService.version(),
      );
      this.bibleResults.set(localized);
    }
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
      this.rawBibleResults = [];
      this.bibleResults.set([]);
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
      const f = this.typeFilter();
      if (f === 'BIBLE') {
        this.hasMore.set(false);
        const res = await this.bibleService.searchSemantic(q, 40).catch(() => ({
          query: q,
          count: 0,
          results: [],
        }));
        const filtered = (res.results || []).filter(
          (h) => h.bookNumber != null && h.chapter != null && h.verse != null,
        );
        this.rawBibleResults = filtered;
        const localized = await this.bibleService.resolveSearchHitsInVersion(
          filtered,
          this.bibleService.version(),
        );
        if (this.query().trim() === q) {
          this.bibleResults.set(localized);
        }
        return;
      }

      if (refresh && f === 'ALL') {
        void this.bibleService
          .searchSemantic(q, 12)
          .then(async (res) => {
            const filtered = (res.results || []).filter(
              (h) => h.bookNumber != null && h.chapter != null && h.verse != null,
            );
            this.rawBibleResults = filtered;
            const localized = await this.bibleService.resolveSearchHitsInVersion(
              filtered,
              this.bibleService.version(),
            );
            if (this.query().trim() === q) {
              this.bibleResults.set(localized);
            }
          })
          .catch(() => {
            if (this.query().trim() === q) {
              this.rawBibleResults = [];
              this.bibleResults.set([]);
            }
          });
      }

      const type = f === 'SHORT' ? 'SHORT' : f === 'VIDEO' ? 'VIDEO' : 'ALL';
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
