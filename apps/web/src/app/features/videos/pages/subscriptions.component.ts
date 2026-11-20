import { Component, OnInit, effect, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { InfiniteScrollTriggerDirective } from '../../../shared/ui/infinite-scroll-trigger.directive';
import { VideoCardComponent } from '../../../shared/ui/video-card.component';
import { ChannelService } from '../../channels/services/channel.service';
import { Video } from '../models/video.model';
import { VideoService } from '../services/video.service';

@Component({
  selector: 'app-subscriptions-page',
  standalone: true,
  imports: [RouterLink, VideoCardComponent, InfiniteScrollTriggerDirective],
  template: `
    <div class="subs-page max-width-box">
      <header class="page-head">
        <div>
          <h1 class="font-display">Following</h1>
          <p class="sub">Latest uploads from channels you follow</p>
        </div>
        <a class="pill-chip active" routerLink="/channels">
          <span class="material-symbols-rounded btn-icon">tune</span>
          Manage
        </a>
      </header>

      @if (channels.subscribedChannels().length > 0) {
        <div class="channel-strip">
          <button
            type="button"
            class="pill-chip"
            [class.active]="selectedChannelId() === null"
            (click)="selectChannel(null)"
          >
            All Following
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
        </div>
      }

      @if (channels.subscribedIds().length === 0 && !loading()) {
        <div class="state-card">
          <span class="material-symbols-rounded state-icon">subscriptions</span>
          <h2>Not following any channels yet</h2>
          <p class="muted">Follow Christian channels to see their latest sermons and worship here.</p>
          <a class="pill-chip active" routerLink="/channels">Browse Channels</a>
        </div>
      } @else if (loading() && items().length === 0) {
        <p class="status-msg">Loading followed channels...</p>
      } @else if (items().length === 0) {
        <div class="state-card">
          <span class="material-symbols-rounded state-icon">video_library</span>
          <p>No videos found for the selected channel.</p>
        </div>
      } @else {
        <div class="video-grid">
          @for (v of items(); track v.id) {
            <app-video-card [video]="v" />
          }
        </div>

        @if (hasMore()) {
          <div
            class="load-more-wrap"
            appInfiniteScrollTrigger
            [disabled]="loading()"
            (triggered)="loadMore()"
          >
            @if (loading()) {
              <span class="loading-more">Loading more videos...</span>
            }
          </div>
        }
      }
    </div>
  `,
  styles: [
    `
      .subs-page {
        padding-top: 16px;
        padding-bottom: 40px;
      }

      .page-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        margin-bottom: 14px;
      }

      .page-head h1 {
        margin: 0;
        font-size: 22px;
        font-weight: 700;
      }

      .sub {
        margin: 2px 0 0;
        font-size: 13px;
        color: var(--on-surface-muted);
      }

      .btn-icon {
        font-size: 18px;
      }

      .channel-strip {
        display: flex;
        align-items: center;
        gap: 8px;
        padding-bottom: 16px;
        overflow-x: auto;
        scrollbar-width: none;
      }

      .channel-strip::-webkit-scrollbar {
        display: none;
      }

      .chip-avatar {
        width: 18px;
        height: 18px;
        border-radius: var(--radius-pill);
        object-fit: cover;
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

      .load-more-wrap {
        min-height: 36px;
        display: flex;
        align-items: center;
        justify-content: center;
        margin-top: 24px;
      }

      .loading-more,
      .status-msg,
      .muted {
        color: var(--on-surface-muted);
      }

      .status-msg {
        text-align: center;
        padding: 36px 0;
      }

      .state-card {
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-lg);
        padding: 36px 24px;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 10px;
        text-align: center;
      }

      .state-icon {
        font-size: 40px;
        color: var(--on-surface-muted);
      }
    `,
  ],
})
export class SubscriptionsComponent implements OnInit {
  readonly channels = inject(ChannelService);
  private readonly videoService = inject(VideoService);

  readonly selectedChannelId = signal<string | null>(null);
  readonly items = signal<Video[]>([]);
  readonly loading = signal<boolean>(false);
  readonly hasMore = signal<boolean>(true);

  private offset = 0;
  private readonly limit = 24;
  private lastSyncedSubKey = [...this.channels.subscribedIds()].sort().join(',');

  constructor() {
    effect(() => {
      const subKey = [...this.channels.subscribedIds()].sort().join(',');
      if (subKey !== this.lastSyncedSubKey) {
        this.lastSyncedSubKey = subKey;
        void this.loadMore(true);
      }
    });
  }

  ngOnInit(): void {
    void this.channels.loadSubscriptions();
    void this.channels.fetchChannels();
    void this.loadMore(true);
  }

  selectChannel(channelId: string | null): void {
    this.selectedChannelId.set(channelId);
    void this.loadMore(true);
  }

  async loadMore(refresh = false): Promise<void> {
    if (this.loading()) return;
    const subIds = this.channels.subscribedIds();
    if (subIds.length === 0) {
      this.items.set([]);
      this.hasMore.set(false);
      return;
    }

    if (refresh) {
      this.offset = 0;
      this.hasMore.set(true);
    }
    if (!this.hasMore()) return;

    this.loading.set(true);
    try {
      const chId = this.selectedChannelId();
      const batch = await this.videoService.queryVideos({
        channelId: chId ?? undefined,
        channelIds: chId ? undefined : subIds,
        type: 'VIDEO',
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
      this.loading.set(false);
    }
  }
}
