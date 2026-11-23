import { Component, OnInit, computed, effect, inject, signal, untracked } from '@angular/core';
import { RouterLink } from '@angular/router';
import { AppConfig } from '../../../core/config/app-config';
import { AuthService } from '../../../core/auth/auth.service';
import { ScreenClassService } from '../../../core/layout/screen-class.service';
import { InfiniteScrollTriggerDirective } from '../../../shared/ui/infinite-scroll-trigger.directive';
import { VideoCardComponent } from '../../../shared/ui/video-card.component';
import { VideoWatchedOverlaysComponent } from '../../../shared/ui/video-watched-overlays.component';
import { ChannelService } from '../../channels/services/channel.service';
import { VideoLibraryService } from '../services/video-library.service';
import { VideoService } from '../services/video.service';

@Component({
  selector: 'app-video-feed',
  standalone: true,
  imports: [RouterLink, VideoCardComponent, InfiniteScrollTriggerDirective, VideoWatchedOverlaysComponent],
  template: `
    <div class="feed-page">
      <header class="feed-header">
        @if (screen.isCompact()) {
          <div class="compact-bar max-width-box">
            <div class="brand">
              <img src="logo.png" alt="ChristianApp" width="28" height="28" />
              <span class="brand-title font-display">{{ appName }}</span>
            </div>
            <div class="actions">
              <a class="icon-btn" routerLink="/search" aria-label="Search" title="Search">
                <span class="material-symbols-rounded">search</span>
              </a>
              <a class="icon-btn" routerLink="/channels" aria-label="Channels" title="Channels">
                <span class="material-symbols-rounded">subscriptions</span>
              </a>
              <a class="icon-btn" routerLink="/settings" aria-label="Account" title="Account & Settings">
                @if (auth.currentUser()?.photoUrl) {
                  <img
                    class="user-avatar"
                    [src]="auth.currentUser()!.photoUrl"
                    [alt]="auth.currentUser()!.displayName"
                  />
                } @else {
                  <span class="material-symbols-rounded">account_circle</span>
                }
              </a>
            </div>
          </div>
        }

        <div class="filter-strip max-width-box">
          <button
            type="button"
            class="pill-chip"
            [class.active]="filterMode() === 'all'"
            (click)="selectAll()"
          >
            All
          </button>

          <button
            type="button"
            class="pill-chip"
            [class.active]="filterMode() === 'watched'"
            (click)="selectStatus('watched')"
          >
            Watched
          </button>

          <button
            type="button"
            class="pill-chip"
            [class.active]="filterMode() === 'unwatched'"
            (click)="selectStatus('unwatched')"
          >
            Unwatched
          </button>

          <button
            type="button"
            class="pill-chip"
            [class.active]="filterMode() === 'in_progress'"
            (click)="selectStatus('in_progress')"
          >
            In Progress
          </button>

          <button
            type="button"
            class="pill-chip"
            [class.active]="filterMode() === 'liked'"
            (click)="selectStatus('liked')"
          >
            Liked
          </button>

          @if (channels.subscribedChannels().length > 0) {
            @for (ch of channels.subscribedChannels(); track ch.id) {
              <button
                type="button"
                class="pill-chip"
                [class.active]="filterMode() === 'channel' && selectedChannelId() === ch.id"
                (click)="selectChannel(ch.id)"
              >
                @if (ch.avatarUrl) {
                  <img class="chip-avatar" [src]="ch.avatarUrl" [alt]="ch.title" />
                } @else {
                  <span class="chip-avatar fallback">
                    {{ ch.title.slice(0, 1).toUpperCase() }}
                  </span>
                }
                {{ ch.title }}
              </button>
            }
          }
        </div>
      </header>

      <div class="feed-body max-width-box">
        @if (videos.error()) {
          <div class="state-card">
            <span class="material-symbols-rounded state-icon">cloud_off</span>
            <p>{{ videos.error() }}</p>
            <button type="button" class="pill-chip active" (click)="reload()">
              Retry
            </button>
          </div>
        } @else if (videos.videos().length === 0 && videos.isLoading()) {
          <div class="video-grid">
            @for (i of [1, 2, 3, 4, 5, 6, 7, 8]; track i) {
              <div class="skeleton-card">
                <div class="skeleton-thumb"></div>
                <div class="skeleton-line"></div>
                <div class="skeleton-line short"></div>
              </div>
            }
          </div>
        } @else if (videos.videos().length === 0) {
          <div class="state-card">
            <span class="material-symbols-rounded state-icon">video_library</span>
            <p>No videos found for this category.</p>
            <button type="button" class="pill-chip active" (click)="selectAll()">
              Show All Videos
            </button>
          </div>
        } @else {
          <div class="video-grid">
            @for (video of topBatch(); track video.id) {
              <app-video-card [video]="video" />
            }
          </div>

          @if (shelfShorts().length > 0 && filterMode() === 'all') {
            <section class="shorts-shelf">
              <div class="shelf-head">
                <div class="shelf-title">
                  <span class="material-symbols-rounded shelf-icon">smart_display</span>
                  <h2 class="font-display">Shorts</h2>
                </div>
                <a class="shelf-more" routerLink="/shorts">View all</a>
              </div>
              <div class="shelf-strip" (scroll)="onShortsScroll($event)">
                @for (short of shelfShorts(); track short.id) {
                  <a
                    class="shelf-card"
                    routerLink="/shorts"
                    [queryParams]="{ shortId: short.id }"
                  >
                    <div class="shelf-thumb-wrap">
                      <img
                        class="shelf-thumb"
                        [src]="short.thumbnailUrl"
                        [alt]="short.title"
                        loading="lazy"
                      />
                      <app-video-watched-overlays [videoId]="short.id" />
                    </div>
                    <h3 class="shelf-card-title">{{ short.title }}</h3>
                    <span class="shelf-card-sub">{{ short.channelTitle }}</span>
                  </a>
                }
                @if (videos.shortsLoading()) {
                  <span class="shelf-loading">Loading more shorts...</span>
                }
              </div>
            </section>
          }

          @if (restBatch().length > 0) {
            <div class="video-grid rest-grid">
              @for (video of restBatch(); track video.id) {
                <app-video-card [video]="video" />
              }
            </div>
          }

          @if (videos.hasMore()) {
            <div
              class="load-more-wrap"
              appInfiniteScrollTrigger
              [disabled]="videos.isLoading()"
              (triggered)="videos.fetchVideos()"
            >
              @if (videos.isLoading()) {
                <span class="loading-more">Loading more videos...</span>
              }
            </div>
          }
        }
      </div>
    </div>
  `,
  styles: [
    `
      .feed-header {
        position: sticky;
        top: var(--shell-top-offset);
        z-index: 30;
        background-color: var(--bg);
        border-bottom: 1px solid var(--surface-border);
      }

      .compact-bar {
        height: var(--topbar-height);
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
      }

      .brand {
        display: flex;
        align-items: center;
        gap: 10px;
        min-width: 0;
      }

      .brand-title {
        font-size: 19px;
        font-weight: 700;
        letter-spacing: -0.4px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .actions {
        display: flex;
        align-items: center;
        gap: 4px;
        flex-shrink: 0;
      }

      .user-avatar {
        width: 28px;
        height: 28px;
        border-radius: var(--radius-pill);
        object-fit: cover;
      }

      .filter-strip {
        display: flex;
        align-items: center;
        gap: 8px;
        padding-top: 8px;
        padding-bottom: 10px;
        overflow-x: auto;
        scrollbar-width: none;
      }

      .filter-strip::-webkit-scrollbar {
        display: none;
      }

      .chip-avatar {
        width: 18px;
        height: 18px;
        border-radius: var(--radius-pill);
        object-fit: cover;
        flex-shrink: 0;
      }

      .chip-avatar.fallback {
        display: grid;
        place-items: center;
        font-size: 10px;
        font-weight: 700;
        background-color: var(--accent-soft);
        color: var(--accent);
      }

      .feed-body {
        padding-top: 16px;
        padding-bottom: 40px;
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

      .rest-grid {
        margin-top: 24px;
      }

      .shorts-shelf {
        margin-top: 28px;
        padding: 18px 0;
        border-top: 1px solid var(--surface-border);
        border-bottom: 1px solid var(--surface-border);
      }

      .shelf-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        margin-bottom: 14px;
      }

      .shelf-title {
        display: flex;
        align-items: center;
        gap: 8px;
      }

      .shelf-title h2 {
        margin: 0;
        font-size: 18px;
        font-weight: 700;
      }

      .shelf-icon {
        color: var(--accent);
      }

      .shelf-more {
        font-size: 13px;
        font-weight: 600;
        color: var(--accent);
      }

      .shelf-strip {
        display: grid;
        grid-auto-flow: column;
        grid-auto-columns: minmax(150px, 180px);
        gap: 12px;
        overflow-x: auto;
        overflow-y: hidden;
        scrollbar-width: none;
        -ms-overflow-style: none;
        padding-bottom: 4px;
      }

      .shelf-strip::-webkit-scrollbar {
        display: none;
      }

      .shelf-loading {
        align-self: center;
        min-width: 160px;
        padding: 10px 0;
        text-align: center;
        font-size: 13px;
        color: var(--on-surface-muted);
      }

      .shelf-card {
        display: flex;
        flex-direction: column;
        gap: 6px;
      }

      .shelf-thumb-wrap {
        aspect-ratio: 9 / 16;
        border-radius: var(--radius-md);
        overflow: hidden;
        background-color: var(--surface-variant);
      }

      .shelf-thumb {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }

      .shelf-card-title {
        margin: 0;
        font-size: 13px;
        font-weight: 600;
        line-height: 1.3;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }

      .shelf-card-sub {
        font-size: 12px;
        color: var(--on-surface-muted);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .load-more-wrap {
        min-height: 36px;
        display: flex;
        align-items: center;
        justify-content: center;
        margin-top: 24px;
      }

      .loading-more {
        font-size: 13px;
        color: var(--on-surface-muted);
      }

      .state-card {
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-lg);
        padding: 36px 24px;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 12px;
        text-align: center;
      }

      .state-icon {
        font-size: 40px;
        color: var(--on-surface-muted);
      }

      .skeleton-card {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }

      .skeleton-thumb {
        aspect-ratio: 16 / 9;
        border-radius: var(--radius-md);
        background-color: var(--surface-variant);
      }

      .skeleton-line {
        height: 14px;
        border-radius: 4px;
        background-color: var(--surface-variant);
      }

      .skeleton-line.short {
        width: 60%;
      }
    `,
  ],
})
export class VideoFeedComponent implements OnInit {
  readonly videos = inject(VideoService);
  readonly library = inject(VideoLibraryService);
  readonly channels = inject(ChannelService);
  readonly screen = inject(ScreenClassService);
  readonly auth = inject(AuthService);

  readonly appName = AppConfig.appName;
  readonly filterMode = signal<
    'all' | 'watched' | 'unwatched' | 'in_progress' | 'liked' | 'channel'
  >('all');
  readonly selectedChannelId = signal<string | null>(null);

  readonly filteredVideos = computed(() => {
    const list = this.videos.videos();
    switch (this.filterMode()) {
      case 'watched':
        return list.filter((v) => this.library.isWatched(v.id));
      case 'unwatched':
        return list.filter((v) => !this.library.isWatched(v.id));
      case 'in_progress':
        return list.filter((v) => this.library.isInProgress(v.id));
      case 'liked':
        return list.filter((v) => this.library.isLiked(v.id));
      default:
        return list;
    }
  });

  readonly topBatch = computed(() => this.filteredVideos().slice(0, 6));
  readonly restBatch = computed(() => this.filteredVideos().slice(6));
  readonly shelfShorts = computed(() => this.videos.shorts());

  private lastSyncedSubKey = [...this.channels.subscribedIds()].sort().join(',');

  constructor() {
    effect(() => {
      const subs = this.channels.subscribedIds();
      const subKey = [...subs].sort().join(',');
      if (subKey !== this.lastSyncedSubKey) {
        this.lastSyncedSubKey = subKey;
        untracked(() => {
          void this.videos.fetchShorts(true);
          const activeChannel = this.selectedChannelId();
          if (
            this.filterMode() === 'channel' &&
            activeChannel &&
            !subs.includes(activeChannel)
          ) {
            this.selectAll();
          } else if (this.filterMode() === 'all') {
            this.applyFilter();
          }
        });
      }
    });
  }

  ngOnInit(): void {
    void this.channels.loadSubscriptions();
    void this.channels.fetchChannels();
    this.applyFilter();
    void this.videos.fetchShorts();
  }

  selectAll(): void {
    this.filterMode.set('all');
    this.selectedChannelId.set(null);
    this.applyFilter();
  }

  selectStatus(mode: 'watched' | 'unwatched' | 'in_progress' | 'liked'): void {
    if (this.filterMode() === mode) {
      this.selectAll();
      return;
    }
    this.filterMode.set(mode);
    this.selectedChannelId.set(null);
    this.applyFilter();
  }

  selectChannel(channelId: string): void {
    this.filterMode.set('channel');
    this.selectedChannelId.set(channelId);
    this.applyFilter();
  }

  reload(): void {
    this.applyFilter();
  }

  onShortsScroll(event: Event): void {
    const element = event.currentTarget as HTMLElement;
    const nearEnd =
      element.scrollLeft + element.clientWidth >= element.scrollWidth - 120;

    if (nearEnd && this.videos.shortsHasMore() && !this.videos.shortsLoading()) {
      void this.videos.fetchShorts();
    }
  }

  private applyFilter(): void {
    const mode = this.filterMode();
    const subs = this.channels.subscribedIds();
    this.videos.setFilter({
      channelId: mode === 'channel' ? this.selectedChannelId() : null,
      category: 'All',
      subscribedIds: subs,
      onlySubscribed: mode === 'all' && subs.length > 0,
    });
  }
}
