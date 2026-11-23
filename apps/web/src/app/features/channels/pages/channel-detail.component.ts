import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { firstValueFrom } from 'rxjs';
import { ApiService } from '../../../core/api/api.service';
import { ScreenClassService } from '../../../core/layout/screen-class.service';
import { InfiniteScrollTriggerDirective } from '../../../shared/ui/infinite-scroll-trigger.directive';
import { VideoCardComponent } from '../../../shared/ui/video-card.component';
import { Video, formatTimeAgo, formatViewCount } from '../../videos/models/video.model';
import { VideoService } from '../../videos/services/video.service';
import { Channel } from '../models/channel.model';
import { ChannelService } from '../services/channel.service';

type ChannelTab = 'home' | 'videos' | 'shorts' | 'streams' | 'about';
type ChannelSort = 'latest' | 'popular' | 'oldest';

@Component({
  selector: 'app-channel-detail',
  standalone: true,
  imports: [
    FormsModule,
    RouterLink,
    VideoCardComponent,
    InfiniteScrollTriggerDirective,
  ],
  template: `
    <div class="channel-detail max-width-box">
      @if (loading()) {
        <p class="status-msg">Loading channel...</p>
      } @else if (!channel()) {
        <p class="status-msg">Channel not found.</p>
      } @else {
        @if (channel()!.bannerUrl) {
          <img class="banner" [src]="channel()!.bannerUrl" [alt]="channel()!.title" />
        }

        <div class="header">
          <div class="header-left">
            @if (channel()!.avatarUrl) {
              <img class="avatar" [src]="channel()!.avatarUrl" [alt]="channel()!.title" />
            } @else {
              <span class="avatar fallback">
                {{ (channel()!.title || 'C').slice(0, 1).toUpperCase() }}
              </span>
            }
            <div class="header-meta">
              <h1 class="font-display">{{ channel()!.title }}</h1>
              <p class="sub">
                @if (channel()!.subscriberCount > 0) {
                  <span>{{ formatViews(channel()!.subscriberCount).replace(' views', '') }} followers · </span>
                }
                <span>{{ channel()!.videoCount }} videos</span>
              </p>
              @if (channel()!.description) {
                <button
                  type="button"
                  class="header-desc"
                  (click)="selectTab('about')"
                >
                  {{ channel()!.description }}
                </button>
              }
              <div class="header-actions">
                <button
                  type="button"
                  class="pill-chip"
                  [class.active]="!isSubscribed()"
                  (click)="channelService.toggleSubscribe(channel()!.id)"
                >
                  {{ isSubscribed() ? 'Following' : 'Follow' }}
                </button>
              </div>
            </div>
          </div>
        </div>

        <div class="tab-bar">
          <div class="tabs-left">
            @for (tab of tabs; track tab) {
              <button
                type="button"
                class="tab-btn"
                [class.active]="activeTab() === tab"
                (click)="selectTab(tab)"
              >
                {{ tab[0].toUpperCase() + tab.slice(1) }}
              </button>
            }
          </div>

          <div class="channel-search">
            <span class="material-symbols-rounded">search</span>
            <input
              type="search"
              placeholder="Search channel..."
              [ngModel]="channelQuery()"
              (ngModelChange)="onSearchChange($event)"
            />
          </div>
        </div>

        @if (activeTab() === 'home') {
          @if (featuredVideo(); as feat) {
            <a class="featured-card" [routerLink]="['/watch', feat.id]">
              <img class="featured-thumb" [src]="feat.thumbnailUrl" [alt]="feat.title" />
              <div class="featured-meta">
                <span class="featured-badge">Latest</span>
                <h2 class="featured-title">{{ feat.title }}</h2>
                <p class="featured-sub">
                  @if (feat.viewCount > 0) {
                    {{ formatViews(feat.viewCount) }} ·
                  }
                  {{ formatTime(feat.publishedAt) }}
                </p>
                @if (feat.description) {
                  <p class="featured-desc">{{ feat.description }}</p>
                }
              </div>
            </a>
          }

          @if (homeVideos().length > 0) {
            <section class="home-section">
              <div class="section-head">
                <h3>Videos</h3>
                <button type="button" class="see-all" (click)="selectTab('videos')">See all</button>
              </div>
              <div class="video-grid">
                @for (v of homeVideos(); track v.id) {
                  <app-video-card [video]="v" />
                }
              </div>
            </section>
          }

          @if (homeShorts().length > 0) {
            <section class="home-section">
              <div class="section-head">
                <h3>Shorts</h3>
                <button type="button" class="see-all" (click)="selectTab('shorts')">See all</button>
              </div>
              <div class="shorts-strip">
                @for (s of homeShorts(); track s.id) {
                  <a class="short-tile" routerLink="/shorts">
                    <img class="short-thumb" [src]="s.thumbnailUrl" [alt]="s.title" />
                    <span class="short-title">{{ s.title }}</span>
                  </a>
                }
              </div>
            </section>
          }
        } @else if (activeTab() === 'about') {
          <div class="about-card">
            <p>{{ channel()!.description || 'No description provided.' }}</p>
          </div>
        } @else {
          @if (activeTab() === 'videos') {
            <div class="sort-row">
              @for (s of sorts; track s.id) {
                <button
                  type="button"
                  class="pill-chip"
                  [class.active]="sort() === s.id"
                  (click)="selectSort(s.id)"
                >
                  {{ s.label }}
                </button>
              }
            </div>
          }

          <div class="video-grid">
            @for (v of visibleItems(); track v.id) {
              <app-video-card [video]="v" />
            }
          </div>

          @if (visibleItems().length === 0 && !tabLoading()) {
            <p class="status-msg">No {{ activeTab() }} found.</p>
          }

          @if (hasMore() && activeTab() !== 'streams') {
            <div
              class="load-more-wrap"
              appInfiniteScrollTrigger
              [disabled]="tabLoading()"
              (triggered)="loadTabPage(false)"
            >
              @if (tabLoading()) {
                <span class="loading-more">Loading more...</span>
              }
            </div>
          }
        }
      }
    </div>
  `,
  styles: [
    `
      .channel-detail {
        padding-top: 16px;
        padding-bottom: 40px;
      }

      .banner {
        width: 100%;
        height: clamp(110px, 22vw, 190px);
        object-fit: cover;
        border-radius: var(--radius-lg);
        margin-bottom: 18px;
      }

      .header {
        margin-bottom: 18px;
      }

      .header-left {
        display: flex;
        align-items: flex-start;
        gap: 18px;
      }

      .avatar {
        width: 96px;
        height: 96px;
        border-radius: var(--radius-pill);
        object-fit: cover;
        flex-shrink: 0;
      }

      @media (max-width: 599px) {
        .avatar {
          width: 68px;
          height: 68px;
        }
      }

      .avatar.fallback {
        display: grid;
        place-items: center;
        font-size: 32px;
        font-weight: 700;
        background-color: var(--accent-soft);
        color: var(--accent);
      }

      .header-meta {
        display: flex;
        flex-direction: column;
        gap: 6px;
        min-width: 0;
      }

      .header h1 {
        margin: 0;
        font-size: 26px;
        font-weight: 700;
        line-height: 1.2;
      }

      .sub {
        margin: 0;
        color: var(--on-surface-muted);
        font-size: 13px;
      }

      .header-desc {
        margin: 0;
        padding: 0;
        text-align: left;
        font-size: 13px;
        color: var(--on-surface-muted);
        display: -webkit-box;
        -webkit-line-clamp: 1;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }

      .header-actions {
        margin-top: 4px;
      }

      .tab-bar {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        flex-wrap: wrap;
        border-bottom: 1px solid var(--surface-border);
        margin-bottom: 18px;
      }

      .tabs-left {
        display: flex;
        gap: 4px;
        overflow-x: auto;
      }

      .tab-btn {
        padding: 10px 14px;
        font-size: 14px;
        font-weight: 600;
        color: var(--on-surface-muted);
        border-bottom: 2px solid transparent;
        white-space: nowrap;
      }

      .tab-btn.active {
        color: var(--accent);
        border-bottom-color: var(--accent);
      }

      .channel-search {
        display: flex;
        align-items: center;
        gap: 6px;
        height: 34px;
        padding: 0 10px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        margin-bottom: 4px;
        flex: 1 1 160px;
        max-width: 260px;
      }

      .channel-search .material-symbols-rounded {
        font-size: 18px;
        color: var(--on-surface-muted);
      }

      .channel-search input {
        flex: 1;
        min-width: 0;
        border: none;
        outline: none;
        background: transparent;
        font-size: 13px;
      }

      .sort-row {
        display: flex;
        gap: 8px;
        margin-bottom: 16px;
      }

      .featured-card {
        display: grid;
        grid-template-columns: 1fr;
        gap: 16px;
        padding: 14px;
        border-radius: var(--radius-md);
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        margin-bottom: 24px;
      }

      @media (min-width: 768px) {
        .featured-card {
          grid-template-columns: clamp(240px, 36vw, 360px) 1fr;
        }
      }

      .featured-thumb {
        width: 100%;
        aspect-ratio: 16 / 9;
        object-fit: cover;
        border-radius: var(--radius-sm);
      }

      .featured-meta {
        display: flex;
        flex-direction: column;
        gap: 6px;
        min-width: 0;
      }

      .featured-badge {
        align-self: flex-start;
        padding: 2px 8px;
        border-radius: var(--radius-pill);
        background-color: var(--accent-soft);
        color: var(--accent);
        font-size: 11px;
        font-weight: 700;
      }

      .featured-title {
        margin: 0;
        font-size: 17px;
        font-weight: 700;
      }

      .featured-sub,
      .featured-desc {
        margin: 0;
        font-size: 13px;
        color: var(--on-surface-muted);
      }

      .featured-desc {
        display: -webkit-box;
        -webkit-line-clamp: 3;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }

      .home-section {
        margin-bottom: 28px;
      }

      .section-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        margin-bottom: 12px;
      }

      .section-head h3 {
        margin: 0;
        font-size: 16px;
        font-weight: 700;
      }

      .see-all {
        font-size: 13px;
        font-weight: 600;
        color: var(--accent);
      }

      .shorts-strip {
        display: grid;
        grid-auto-flow: column;
        grid-auto-columns: minmax(140px, 170px);
        gap: 12px;
        overflow-x: auto;
      }

      .short-tile {
        display: flex;
        flex-direction: column;
        gap: 6px;
      }

      .short-thumb {
        aspect-ratio: 9 / 16;
        width: 100%;
        object-fit: cover;
        border-radius: var(--radius-md);
      }

      .short-title {
        font-size: 12px;
        font-weight: 600;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }

      .video-grid {
        display: grid;
        gap: 24px 16px;
        grid-template-columns: 1fr;
      }

      @media (min-width: 600px) {
        .video-grid {
          grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
        }
      }

      .about-card {
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-md);
        padding: 16px;
        white-space: pre-wrap;
      }

      .load-more-wrap {
        min-height: 36px;
        display: flex;
        align-items: center;
        justify-content: center;
        margin-top: 24px;
      }

      .loading-more,
      .status-msg {
        text-align: center;
        color: var(--on-surface-muted);
        padding: 24px 0;
      }
    `,
  ],
})
export class ChannelDetailComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly api = inject(ApiService);
  private readonly videoService = inject(VideoService);
  readonly channelService = inject(ChannelService);
  readonly screen = inject(ScreenClassService);

  readonly tabs: readonly ChannelTab[] = [
    'home',
    'videos',
    'shorts',
    'streams',
    'about',
  ];
  readonly sorts: readonly { id: ChannelSort; label: string }[] = [
    { id: 'latest', label: 'Latest' },
    { id: 'popular', label: 'Popular' },
    { id: 'oldest', label: 'Oldest' },
  ];

  readonly channel = signal<Channel | null>(null);
  readonly loading = signal<boolean>(true);
  readonly activeTab = signal<ChannelTab>('home');
  readonly sort = signal<ChannelSort>('latest');
  readonly channelQuery = signal<string>('');

  readonly items = signal<Video[]>([]);
  readonly homeVideos = signal<Video[]>([]);
  readonly homeShorts = signal<Video[]>([]);
  readonly tabLoading = signal<boolean>(false);
  readonly hasMore = signal<boolean>(true);

  private channelId = '';
  private offset = 0;
  private readonly limit = 24;
  private searchTimer: ReturnType<typeof setTimeout> | null = null;

  readonly isSubscribed = computed(() => {
    const id = this.channel()?.id;
    return id ? this.channelService.subscribedIds().includes(id) : false;
  });

  readonly featuredVideo = computed(() => this.homeVideos()[0] ?? null);

  readonly visibleItems = computed(() => {
    if (this.activeTab() === 'streams') {
      return this.items().filter((v) => v.isLive);
    }
    return this.items();
  });

  ngOnInit(): void {
    void this.channelService.loadSubscriptions();
    this.route.paramMap.subscribe(async (params) => {
      const id = params.get('id');
      if (!id) return;
      this.channelId = id;
      this.loading.set(true);
      this.activeTab.set('home');
      this.channelQuery.set('');
      try {
        const ch = await this.channelService.fetchChannelDetails(id);
        this.channel.set(ch);
        const [vids, shorts] = await Promise.all([
          this.videoService.queryVideos({ channelId: id, type: 'VIDEO', limit: 8, offset: 0 }),
          this.videoService.queryVideos({ channelId: id, type: 'SHORT', limit: 8, offset: 0 }),
        ]);
        this.homeVideos.set(vids);
        this.homeShorts.set(shorts);
      } catch {
        this.channel.set(null);
      } finally {
        this.loading.set(false);
      }
    });
  }

  selectTab(tab: ChannelTab): void {
    this.activeTab.set(tab);
    if (tab === 'videos' || tab === 'shorts' || tab === 'streams') {
      void this.loadTabPage(true);
    }
  }

  selectSort(nextSort: ChannelSort): void {
    this.sort.set(nextSort);
    void this.loadTabPage(true);
  }

  onSearchChange(q: string): void {
    this.channelQuery.set(q);
    if (this.searchTimer) clearTimeout(this.searchTimer);
    this.searchTimer = setTimeout(() => {
      if (this.activeTab() === 'home' || this.activeTab() === 'about') {
        this.activeTab.set('videos');
      }
      void this.loadTabPage(true);
    }, 280);
  }

  async loadTabPage(refresh: boolean): Promise<void> {
    if (this.tabLoading() || !this.channelId) return;
    if (refresh) {
      this.offset = 0;
      this.hasMore.set(true);
    }
    if (!this.hasMore()) return;

    this.tabLoading.set(true);
    try {
      const type = this.activeTab() === 'shorts' ? 'SHORT' : 'VIDEO';
      const batch = await this.videoService.queryVideos({
        channelId: this.channelId,
        type,
        sort: this.activeTab() === 'videos' ? this.sort() : 'latest',
        search: this.channelQuery(),
        limit: this.limit,
        offset: this.offset,
      });
      if (refresh) {
        this.items.set(batch);
      } else {
        const seen = new Set(this.items().map((v) => v.id));
        this.items.set([
          ...this.items(),
          ...batch.filter((v) => !seen.has(v.id)),
        ]);
      }
      this.offset += batch.length;
      this.hasMore.set(batch.length >= this.limit);
    } finally {
      this.tabLoading.set(false);
    }
  }

  formatViews(n: number): string {
    return formatViewCount(n);
  }

  formatTime(iso: string): string {
    return formatTimeAgo(iso);
  }
}
