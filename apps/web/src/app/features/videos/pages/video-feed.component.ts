import { Component, OnInit, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { AppConfig } from '../../../core/config/app-config';
import { AuthService } from '../../../core/auth/auth.service';
import { ScreenClassService } from '../../../core/layout/screen-class.service';
import { VideoCardComponent } from '../../../shared/ui/video-card.component';
import { ChannelService } from '../../channels/services/channel.service';
import { VideoService } from '../services/video.service';

@Component({
  selector: 'app-video-feed',
  standalone: true,
  imports: [RouterLink, VideoCardComponent],
  template: `
    <div class="feed-page">
      <header class="app-bar">
        <div class="app-bar-inner max-width-box">
          <div class="brand">
            <img src="logo.png" alt="ChristianApp" width="28" height="28" />
            <span class="brand-title font-display">{{ appName }}</span>
          </div>

          <div class="actions">
            @if (screen.collapseAppBarActions()) {
              <div class="menu-wrap">
                <button
                  type="button"
                  class="icon-btn"
                  aria-label="More actions"
                  (click)="menuOpen.set(!menuOpen())"
                >
                  <span class="material-symbols-rounded">more_vert</span>
                </button>
                @if (menuOpen()) {
                  <div class="overflow-menu" (click)="menuOpen.set(false)">
                    <a class="menu-item" routerLink="/search">
                      <span class="material-symbols-rounded">search</span>
                      Search
                    </a>
                    <a class="menu-item" routerLink="/channels">
                      <span class="material-symbols-rounded">subscriptions</span>
                      Channels
                    </a>
                    <a class="menu-item" routerLink="/settings">
                      <span class="material-symbols-rounded">account_circle</span>
                      Account & Settings
                    </a>
                  </div>
                }
              </div>
            } @else {
              <a class="icon-btn" routerLink="/channels" aria-label="Channels" title="Channels">
                <span class="material-symbols-rounded">subscriptions</span>
              </a>
              <a class="icon-btn" routerLink="/search" aria-label="Search" title="Search">
                <span class="material-symbols-rounded">search</span>
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
            }
          </div>
        </div>

        <div class="filter-strip max-width-box">
          <button
            type="button"
            class="pill-chip"
            [class.active]="selectedCategory() === 'All' && !selectedChannelId()"
            (click)="selectAll()"
          >
            {{ channels.subscribedChannels().length > 0 ? 'All Subscriptions' : 'All' }}
          </button>

          @for (ch of channels.subscribedChannels(); track ch.id) {
            <button
              type="button"
              class="pill-chip"
              [class.active]="selectedChannelId() === ch.id"
              (click)="selectChannel(ch.id)"
            >
              @if (ch.avatarUrl) {
                <img class="chip-avatar" [src]="ch.avatarUrl" [alt]="ch.title" />
              }
              {{ ch.title }}
            </button>
          }

          @for (cat of categories; track cat) {
            @if (cat !== 'All') {
              <button
                type="button"
                class="pill-chip"
                [class.active]="selectedCategory() === cat && !selectedChannelId()"
                (click)="selectCategory(cat)"
              >
                {{ cat }}
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
          <div class="video-grid" [attr.data-cols]="screen.feedColumns()">
            @for (i of [1, 2, 3, 4, 5, 6]; track i) {
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
            <p>No videos found for this filter.</p>
            <a class="pill-chip active" routerLink="/channels">Browse Channels</a>
          </div>
        } @else {
          <div class="video-grid" [attr.data-cols]="screen.feedColumns()">
            @for (video of videos.videos(); track video.id) {
              <app-video-card [video]="video" />
            }
          </div>

          @if (videos.hasMore()) {
            <div class="load-more-wrap">
              <button
                type="button"
                class="pill-chip"
                [disabled]="videos.isLoading()"
                (click)="videos.fetchVideos()"
              >
                {{ videos.isLoading() ? 'Loading...' : 'Load more videos' }}
              </button>
            </div>
          }
        }
      </div>
    </div>
  `,
  styles: [
    `
      .app-bar {
        position: sticky;
        top: 0;
        z-index: 30;
        background-color: var(--bg);
        border-bottom: 1px solid var(--surface-border);
      }

      .app-bar-inner {
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

      .menu-wrap {
        position: relative;
      }

      .overflow-menu {
        position: absolute;
        right: 0;
        top: 44px;
        min-width: 190px;
        background-color: var(--surface-elevated);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-md);
        padding: 6px;
        display: flex;
        flex-direction: column;
        gap: 2px;
        box-shadow: 0 8px 24px rgba(0, 0, 0, 0.24);
        z-index: 60;
      }

      .menu-item {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 10px 12px;
        border-radius: var(--radius-sm);
        font-size: 14px;
      }

      .menu-item:hover {
        background-color: var(--surface-variant);
      }

      .filter-strip {
        display: flex;
        align-items: center;
        gap: 8px;
        padding-top: 6px;
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
      }

      .feed-body {
        padding-top: 16px;
        padding-bottom: 32px;
      }

      .video-grid {
        display: grid;
        gap: 20px 16px;
        grid-template-columns: 1fr;
      }

      .video-grid[data-cols='2'] {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      .video-grid[data-cols='3'] {
        grid-template-columns: repeat(3, minmax(0, 1fr));
      }

      .load-more-wrap {
        display: flex;
        justify-content: center;
        margin-top: 24px;
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
  readonly channels = inject(ChannelService);
  readonly screen = inject(ScreenClassService);
  readonly auth = inject(AuthService);

  readonly appName = AppConfig.appName;
  readonly categories = AppConfig.defaultCategories;
  readonly selectedCategory = signal<string>('All');
  readonly selectedChannelId = signal<string | null>(null);
  readonly menuOpen = signal<boolean>(false);

  async ngOnInit(): Promise<void> {
    await Promise.all([
      this.channels.loadSubscriptions(),
      this.channels.fetchChannels(),
    ]);
    this.applyFilter();
  }

  selectAll(): void {
    this.selectedCategory.set('All');
    this.selectedChannelId.set(null);
    this.applyFilter();
  }

  selectChannel(channelId: string): void {
    this.selectedChannelId.set(channelId);
    this.selectedCategory.set('All');
    this.applyFilter();
  }

  selectCategory(category: string): void {
    this.selectedCategory.set(category);
    this.selectedChannelId.set(null);
    this.applyFilter();
  }

  reload(): void {
    this.applyFilter();
  }

  private applyFilter(): void {
    const subs = this.channels.subscribedIds();
    this.videos.setFilter({
      channelId: this.selectedChannelId(),
      category: this.selectedCategory(),
      subscribedIds: subs,
      onlySubscribed:
        !this.selectedChannelId() &&
        this.selectedCategory() === 'All' &&
        subs.length > 0,
    });
  }
}
