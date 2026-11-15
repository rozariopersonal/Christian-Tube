import { ChangeDetectionStrategy, Component, OnInit, computed, inject, signal } from '@angular/core';
import { DomSanitizer, SafeResourceUrl } from '@angular/platform-browser';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { combineLatest } from 'rxjs';
import { ScreenClassService } from '../../../core/layout/screen-class.service';
import { ChannelService } from '../../channels/services/channel.service';
import {
  Video,
  formatTimeAgo,
  formatViewCount,
} from '../models/video.model';
import { VideoService } from '../services/video.service';

@Component({
  selector: 'app-watch-video',
  standalone: true,
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="watch-page" [class.two-col]="screen.isMediumOrExpanded()">
      @if (loading()) {
        <div class="loading-box">Loading video...</div>
      } @else if (!video()) {
        <div class="loading-box">Video not found.</div>
      } @else {
        <div class="primary-col">
          <div class="player-frame">
            @if (video()!.streamUrl) {
              <video
                class="native-video"
                [src]="video()!.streamUrl"
                controls
                autoplay
                playsinline
                (loadedmetadata)="onVideoLoaded($event)"
              ></video>
            } @else {
              <iframe
                class="yt-iframe"
                [src]="embedUrl()"
                [title]="video()!.title"
                allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                allowfullscreen
              ></iframe>
            }
          </div>

          <div class="video-info">
            <h1 class="video-title">{{ video()!.title }}</h1>
            <p class="video-stats">
              @if (video()!.viewCount > 0) {
                <span>{{ formatViews(video()!.viewCount) }} · </span>
              }
              <span>{{ formatTime(video()!.publishedAt) }}</span>
            </p>

            <div class="channel-bar">
              <a class="channel-link" [routerLink]="['/channels', video()!.channelId]">
                @if (video()!.channelAvatarUrl) {
                  <img
                    class="ch-avatar"
                    [src]="video()!.channelAvatarUrl"
                    [alt]="video()!.channelTitle"
                  />
                } @else {
                  <span class="ch-avatar fallback">
                    {{ video()!.channelTitle.slice(0, 1).toUpperCase() }}
                  </span>
                }
                <div class="ch-meta">
                  <span class="ch-name">{{ video()!.channelTitle }}</span>
                  @if (video()!.subscriberCount) {
                    <span class="ch-subs">{{ video()!.subscriberCount }}</span>
                  }
                </div>
              </a>

              <div class="bar-actions">
                <button
                  type="button"
                  class="pill-chip"
                  (click)="shareVideo()"
                >
                  <span class="material-symbols-rounded">share</span>
                  Share
                </button>
                @if (video()!.channelId) {
                  <button
                    type="button"
                    class="pill-chip"
                    [class.active]="!isSubscribed()"
                    (click)="toggleSubscribe()"
                  >
                    {{ isSubscribed() ? 'Subscribed' : 'Subscribe' }}
                  </button>
                }
              </div>
            </div>
          </div>
        </div>

        <aside class="sidebar-col">
          @if (video()!.description) {
            <div class="desc-card">
              <h2 class="section-heading">Description</h2>
              <p class="desc-text">{{ video()!.description }}</p>
            </div>
          }

          @if (related().length > 0) {
            <div class="related-list">
              <h2 class="section-heading">Related Videos</h2>
              @for (item of related(); track item.id) {
                <a class="related-row" [routerLink]="['/watch', item.id]">
                  <img
                    class="rel-thumb"
                    [src]="item.thumbnailUrl"
                    [alt]="item.title"
                    loading="lazy"
                  />
                  <div class="rel-meta">
                    <span class="rel-title">{{ item.title }}</span>
                    <span class="rel-sub">{{ item.channelTitle }}</span>
                  </div>
                </a>
              }
            </div>
          }
        </aside>
      }
    </div>
  `,
  styles: [
    `
      .watch-page {
        width: 100%;
        max-width: 1360px;
        margin-inline: auto;
        padding: 16px;
        display: flex;
        flex-direction: column;
        gap: 20px;
      }

      .watch-page.two-col {
        display: grid;
        grid-template-columns: minmax(0, 1fr) 360px;
        align-items: start;
        padding: 20px 24px;
      }

      .primary-col {
        min-width: 0;
        max-width: 1280px;
      }

      .player-frame {
        width: 100%;
        aspect-ratio: 16 / 9;
        background-color: #000000;
        border-radius: var(--radius-md);
        overflow: hidden;
      }

      .yt-iframe,
      .native-video {
        width: 100%;
        height: 100%;
        border: 0;
        display: block;
      }

      .video-info {
        padding-top: 14px;
      }

      .video-title {
        margin: 0 0 6px;
        font-size: 18px;
        font-weight: 700;
        line-height: 1.35;
      }

      .video-stats {
        margin: 0 0 14px;
        font-size: 13px;
        color: var(--on-surface-muted);
      }

      .channel-bar {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        flex-wrap: wrap;
        padding: 12px;
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-md);
      }

      .bar-actions {
        display: flex;
        align-items: center;
        gap: 8px;
        flex-wrap: wrap;
      }

      .channel-link {
        display: flex;
        align-items: center;
        gap: 10px;
        min-width: 0;
      }

      .ch-avatar {
        width: 40px;
        height: 40px;
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
        font-size: 14px;
      }

      .ch-subs {
        font-size: 12px;
        color: var(--on-surface-muted);
      }

      .sidebar-col {
        display: flex;
        flex-direction: column;
        gap: 16px;
        min-width: 0;
      }

      .desc-card,
      .related-list {
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-md);
        padding: 14px;
      }

      .section-heading {
        margin: 0 0 10px;
        font-size: 14px;
        font-weight: 700;
      }

      .desc-text {
        margin: 0;
        font-size: 13px;
        color: var(--on-surface-muted);
        white-space: pre-wrap;
        line-height: 1.5;
      }

      .related-list {
        display: flex;
        flex-direction: column;
        gap: 12px;
      }

      .related-row {
        display: flex;
        gap: 10px;
        align-items: flex-start;
      }

      .rel-thumb {
        width: 128px;
        aspect-ratio: 16 / 9;
        border-radius: var(--radius-sm);
        object-fit: cover;
        flex-shrink: 0;
        background-color: var(--surface-variant);
      }

      .rel-meta {
        display: flex;
        flex-direction: column;
        gap: 4px;
        min-width: 0;
      }

      .rel-title {
        font-size: 13px;
        font-weight: 600;
        line-height: 1.3;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }

      .rel-sub {
        font-size: 12px;
        color: var(--on-surface-muted);
      }

      .loading-box {
        padding: 40px 16px;
        text-align: center;
        color: var(--on-surface-muted);
      }
    `,
  ],
})
export class WatchVideoComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly sanitizer = inject(DomSanitizer);
  private readonly videoService = inject(VideoService);
  private readonly channelService = inject(ChannelService);
  readonly screen = inject(ScreenClassService);

  readonly video = signal<Video | null>(null);
  readonly related = signal<Video[]>([]);
  readonly loading = signal<boolean>(true);
  readonly startSeconds = signal<number>(0);

  private nativeVideoEl: HTMLVideoElement | null = null;

  readonly isSubscribed = computed(() => {
    const chId = this.video()?.channelId;
    return chId ? this.channelService.subscribedIds().includes(chId) : false;
  });

  readonly embedUrl = computed<SafeResourceUrl>(() => {
    const id = this.video()?.id ?? '';
    const start = this.startSeconds();
    const startParam = start > 0 ? `&start=${Math.floor(start)}` : '';
    return this.sanitizer.bypassSecurityTrustResourceUrl(
      `https://www.youtube.com/embed/${encodeURIComponent(id)}?autoplay=1&rel=0${startParam}`,
    );
  });

  ngOnInit(): void {
    combineLatest([this.route.paramMap, this.route.queryParamMap]).subscribe(
      ([params, query]) => {
        const id = params.get('id');
        const startRaw = query.get('start') ?? query.get('t');
        const parsed = startRaw ? Number(startRaw) : 0;
        this.startSeconds.set(
          Number.isFinite(parsed) && parsed > 0 ? Math.floor(parsed) : 0,
        );
        if (id) void this.loadVideo(id);
      },
    );
  }

  onVideoLoaded(event: Event): void {
    const el = event.target as HTMLVideoElement | null;
    this.nativeVideoEl = el;
    const start = this.startSeconds();
    if (el && start > 0) {
      el.currentTime = start;
    }
  }

  shareVideo(): void {
    const v = this.video();
    if (!v) return;
    const url = new URL(`/watch/${encodeURIComponent(v.id)}`, window.location.origin);
    const sec = Math.floor(this.nativeVideoEl?.currentTime ?? this.startSeconds());
    if (sec > 0) {
      url.searchParams.set('start', String(sec));
    }
    const shareUrl = url.toString();
    if (navigator.share) {
      void navigator.share({ title: v.title, url: shareUrl }).catch(() => {
        void navigator.clipboard?.writeText(shareUrl);
      });
    } else {
      void navigator.clipboard?.writeText(shareUrl);
    }
  }

  async loadVideo(id: string): Promise<void> {
    this.loading.set(true);
    const v = await this.videoService.fetchVideoById(id);
    this.video.set(v);
    this.loading.set(false);
    if (v) {
      this.related.set(await this.videoService.fetchRelatedVideos(v));
    }
  }

  toggleSubscribe(): void {
    const chId = this.video()?.channelId;
    if (chId) void this.channelService.toggleSubscribe(chId);
  }

  formatViews = formatViewCount;
  formatTime = formatTimeAgo;
}
