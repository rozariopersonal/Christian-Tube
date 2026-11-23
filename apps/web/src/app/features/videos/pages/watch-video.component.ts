import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  ElementRef,
  HostListener,
  NgZone,
  OnDestroy,
  OnInit,
  ViewChild,
  computed,
  inject,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { combineLatest } from 'rxjs';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { ScreenClassService } from '../../../core/layout/screen-class.service';
import { ChannelService } from '../../channels/services/channel.service';
import {
  Video,
  formatTimeAgo,
  formatViewCount,
} from '../models/video.model';
import { VideoLibraryService } from '../services/video-library.service';
import { VideoPlayerService } from '../services/video-player.service';
import { VideoService } from '../services/video.service';
import { UserSyncService } from '../../../core/services/user-sync.service';

interface DescriptionSegment {
  text: string;
  seconds?: number;
}

declare global {
  interface Window {
    YT?: {
      Player: new (
        el: HTMLElement | string,
        opts: {
          width?: string | number;
          height?: string | number;
          videoId: string;
          playerVars?: Record<string, number | string>;
          events?: {
            onReady?: (e: { target: YTPlayerInstance }) => void;
            onStateChange?: (e: { data: number }) => void;
          };
        },
      ) => YTPlayerInstance;
      PlayerState?: {
        ENDED: number;
        PLAYING: number;
        PAUSED: number;
      };
    };
    onYouTubeIframeAPIReady?: () => void;
  }
}

interface YTPlayerInstance {
  loadVideoById(opts: { videoId: string; startSeconds?: number }): void;
  playVideo(): void;
  pauseVideo(): void;
  seekTo(seconds: number, allowSeekAhead: boolean): void;
  getCurrentTime(): number;
  getDuration(): number;
  getPlayerState(): number;
  isMuted(): boolean;
  mute(): void;
  unMute(): void;
  destroy(): void;
}

let ytApiPromise: Promise<void> | null = null;

function ensureYouTubeIframeApi(): Promise<void> {
  if (typeof window === 'undefined') return Promise.resolve();
  if (window.YT?.Player) return Promise.resolve();
  if (ytApiPromise) return ytApiPromise;

  ytApiPromise = new Promise<void>((resolve) => {
    const prev = window.onYouTubeIframeAPIReady;
    window.onYouTubeIframeAPIReady = () => {
      prev?.();
      resolve();
    };
    const script = document.createElement('script');
    script.src = 'https://www.youtube.com/iframe_api';
    script.async = true;
    document.head.appendChild(script);
  });
  return ytApiPromise;
}

@Component({
  selector: 'app-watch-video',
  standalone: true,
  imports: [RouterLink, FormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div
      class="watch-shell"
      [class.two-col]="screen.isDesktop()"
    >
      @if (loading()) {
        <div class="loading-box">Loading video...</div>
      } @else if (!video()) {
        <div class="loading-box">Video not found.</div>
      } @else {
        <div class="watch-columns" [class.two-col]="screen.isDesktop()">
          <div class="primary-col">
            <div class="player-frame" #playerContainer>
              @if (video()!.streamUrl) {
                <video
                  #nativeVideo
                  class="native-video"
                  [src]="video()!.streamUrl"
                  controls
                  autoplay
                  playsinline
                  (loadedmetadata)="onVideoLoaded($event)"
                  (timeupdate)="onNativeTimeUpdate($event)"
                  (ended)="onPlaybackEnded()"
                ></video>
              } @else {
                <div #ytHost class="yt-host"></div>
              }

              @if (countdown() !== null && nextUpVideo(); as nextV) {
                <div class="autoplay-overlay">
                  <p class="ap-label">Up next in {{ countdown() }}s</p>
                  <p class="ap-title">{{ nextV.title }}</p>
                  <div class="ap-actions">
                    <button type="button" class="pill-chip" (click)="cancelCountdown()">Cancel</button>
                    <button type="button" class="pill-chip active" (click)="playNextNow()">Play Now</button>
                  </div>
                </div>
              }
            </div>

            <div class="video-info">
              <h1 class="video-title">{{ video()!.title }}</h1>

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

                @if (video()!.channelId) {
                  <button
                    type="button"
                    class="pill-chip"
                    [class.active]="!isSubscribed()"
                    (click)="toggleSubscribe()"
                  >
                    {{ isSubscribed() ? 'Following' : 'Follow' }}
                  </button>
                }

                <div class="bar-actions">
                  <button type="button" class="pill-chip" [class.active]="isLiked()" (click)="toggleLike()" [attr.aria-pressed]="isLiked()">
                    <span class="material-symbols-rounded" [class.filled]="isLiked()">favorite</span>
                    {{ isLiked() ? 'Liked' : 'Like' }}
                  </button>
                  <button
                    type="button"
                    class="pill-chip"
                    [class.active]="isWatchLater()"
                    (click)="library.toggleWatchLater(video()!)"
                  >
                    <span class="material-symbols-rounded">
                      {{ isWatchLater() ? 'bookmark_added' : 'watch_later' }}
                    </span>
                    {{ isWatchLater() ? 'Saved' : 'Watch Later' }}
                  </button>

                  <button
                    type="button"
                    class="pill-chip"
                    (click)="library.addToQueue(video()!)"
                  >
                    <span class="material-symbols-rounded">queue_music</span>
                    Queue
                  </button>

                  <button
                    type="button"
                    class="pill-chip"
                    (click)="openShare()"
                  >
                    <span class="material-symbols-rounded">share</span>
                    Share
                  </button>

                  <button
                    type="button"
                    class="pill-chip"
                    title="Mini player"
                    (click)="minimizeToMini()"
                  >
                    <span class="material-symbols-rounded">picture_in_picture_alt</span>
                    Mini
                  </button>
                </div>
              </div>

              <div class="desc-card" [class.expanded]="descExpanded()">
                <div class="desc-meta">
                  @if (video()!.viewCount > 0) {
                    <span>{{ formatViews(video()!.viewCount) }}</span>
                  }
                  @if (video()!.publishedAt) {
                    <span>{{ formatTime(video()!.publishedAt) }}</span>
                  }
                  @if (video()!.category) {
                    <span class="cat-badge">{{ video()!.category }}</span>
                  }
                </div>

                @if (video()!.description) {
                  <p class="desc-text" [class.clamped]="!descExpanded()">
                    @for (seg of descriptionSegments(); track $index) {
                      @if (seg.seconds !== undefined) {
                        <button
                          type="button"
                          class="ts-link"
                          (click)="seekTo(seg.seconds!)"
                        >
                          {{ seg.text }}
                        </button>
                      } @else {
                        <span>{{ seg.text }}</span>
                      }
                    }
                  </p>
                  <button
                    type="button"
                    class="desc-toggle"
                    (click)="descExpanded.set(!descExpanded())"
                  >
                    {{ descExpanded() ? 'Show less' : '...more' }}
                  </button>
                }
              </div>
            </div>
          </div>

          <aside class="sidebar-col">
            @if (library.queue().length > 0) {
              <div class="queue-box">
                <div class="queue-head">
                  <h2 class="section-heading">Queue ({{ library.queue().length }})</h2>
                  <button type="button" class="clear-q" (click)="library.clearQueue()">
                    Clear
                  </button>
                </div>
                <div class="related-list">
                  @for (qItem of library.queue(); track qItem.id) {
                    <div class="queue-row">
                      <a class="related-row" [routerLink]="['/watch', qItem.id]">
                        <img class="rel-thumb" [src]="qItem.thumbnailUrl" [alt]="qItem.title" />
                        <div class="rel-meta">
                          <span class="rel-title">{{ qItem.title }}</span>
                          <span class="rel-sub">{{ qItem.channelTitle }}</span>
                        </div>
                      </a>
                      <button
                        type="button"
                        class="q-remove"
                        aria-label="Remove from queue"
                        (click)="library.removeFromQueue(qItem.id)"
                      >
                        <span class="material-symbols-rounded">close</span>
                      </button>
                    </div>
                  }
                </div>
              </div>
            }

            <div class="upnext-header">
              <h2 class="section-heading">Up Next</h2>
              @if (previousVideosAvailable()) {
                <button class="load-previous" type="button" [disabled]="loadingPreviousVideos()" (click)="loadPreviousVideos()">
                  {{ loadingPreviousVideos() ? 'Loading...' : previousLoadError() ? 'Retry previous videos' : 'Load previous videos' }}
                </button>
              }
              <label class="autoplay-toggle">
                <span>Autoplay</span>
                <input
                  type="checkbox"
                  [ngModel]="library.autoplay()"
                  (ngModelChange)="library.setAutoplay($event)"
                />
              </label>
            </div>

            @if (
              video() ||
              loadingMoreRecommendations() ||
              recommendationsLoadError() ||
              recommendationsHasMore()
            ) {
              <div class="related-list">
                @if (previousVideosAvailable()) {
                  <div #previousEnd></div>
                }
                @for (item of watchList(); track item.id) {
                  <a
                    class="related-row"
                    [class.now-playing]="item.id === video()!.id"
                    [routerLink]="['/watch', item.id]"
                  >
                    <div class="rel-thumb-wrap">
                      <img
                        class="rel-thumb"
                        [src]="item.thumbnailUrl"
                        [alt]="item.title"
                        loading="lazy"
                      />
                      @if (item.id === video()!.id) {
                        <span class="rel-playing">Playing</span>
                      } @else if (item.duration && item.duration !== '0:00') {
                        <span class="rel-dur">{{ item.duration }}</span>
                      }
                    </div>
                    <div class="rel-meta">
                      <span class="rel-title">{{ item.title }}</span>
                      <span class="rel-sub">{{ item.channelTitle }}</span>
                      <span class="rel-sub">
                        @if (item.viewCount > 0) {
                          {{ formatViews(item.viewCount) }}
                        }
                        @if (item.viewCount > 0 && item.publishedAt) {
                          ·
                        }
                        @if (item.publishedAt) {
                          {{ formatTime(item.publishedAt) }}
                        }
                      </span>
                    </div>
                  </a>
                }
                @if (recommendationsHasMore()) {
                  <div
                    #recommendationsEnd
                    class="recommendations-load-more"
                    aria-live="polite"
                  >
                    @if (recommendationsLoadError()) {
                      <button type="button" (click)="retryRecommendationsPage()">
                        Couldn’t load videos. Retry
                      </button>
                    } @else if (loadingMoreRecommendations()) {
                      <span>Loading more videos...</span>
                    } @else {
                      <button type="button" (click)="loadNextRecommendationsPage()">
                        Load more videos
                      </button>
                    }
                  </div>
                } @else if (recommendationsLoadError()) {
                  <div class="recommendations-load-more">
                    <button type="button" (click)="retryRecommendationsPage()">Couldn’t load videos. Retry</button>
                  </div>
                }
              </div>
            }
          </aside>
        </div>
      }

      @if (shareOpen() && video(); as v) {
        <div class="modal-backdrop" (click)="shareOpen.set(false)">
          <div class="modal-panel share-modal" (click)="$event.stopPropagation()">
            <div class="share-head">
              <h3>Share</h3>
              <button type="button" class="icon-btn" (click)="shareOpen.set(false)">
                <span class="material-symbols-rounded">close</span>
              </button>
            </div>
            <div class="share-url-row">
              <input type="text" readonly class="share-input" [value]="shareUrl()" />
              <button type="button" class="pill-chip active" (click)="copyShareUrl()">
                {{ copied() ? 'Copied' : 'Copy' }}
              </button>
            </div>
            <label class="share-start-check">
              <input
                type="checkbox"
                [ngModel]="shareAtCurrent()"
                (ngModelChange)="shareAtCurrent.set($event)"
              />
              <span>Start at {{ formatSeconds(currentSecondsSnapshot()) }}</span>
            </label>
          </div>
        </div>
      }
    </div>
  `,
  styles: [
    `
      .watch-shell {
        width: 100%;
      }

      .theater-stage {
        width: 100%;
        background-color: #000000;
        display: flex;
        justify-content: center;
      }

      .theater-frame {
        max-width: 1280px;
        max-height: 76vh;
        border-radius: 0 !important;
      }

      .watch-columns {
        width: 100%;
        padding: 16px;
        display: flex;
        flex-direction: column;
        gap: 20px;
      }

      .watch-columns.two-col {
        display: grid;
        grid-template-columns: minmax(0, 1fr) 360px;
        align-items: start;
        padding: 20px clamp(20px, 2.5vw, 32px);
      }

      .primary-col {
        min-width: 0;
      }

      .player-frame {
        position: relative;
        width: 100%;
        aspect-ratio: 16 / 9;
        background-color: #000000;
        border-radius: var(--radius-md);
        overflow: hidden;
      }

      .watch-columns:not(.two-col) .player-frame {
        max-height: 62dvh;
        max-width: calc(62dvh * 16 / 9);
        margin-inline: auto;
      }

      .yt-host,
      .native-video,
      :host ::ng-deep .player-frame iframe {
        width: 100%;
        height: 100%;
        border: 0;
        display: block;
      }

      .autoplay-overlay {
        position: absolute;
        inset: 0;
        background: rgba(0, 0, 0, 0.82);
        color: #ffffff;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 10px;
        padding: 20px;
        text-align: center;
        z-index: 10;
      }

      .ap-label {
        margin: 0;
        font-size: 13px;
        opacity: 0.8;
      }

      .ap-title {
        margin: 0;
        font-size: 16px;
        font-weight: 700;
        max-width: 420px;
      }

      .ap-actions {
        display: flex;
        gap: 10px;
      }

      .video-info {
        padding-top: 14px;
      }

      .video-title {
        margin: 0 0 12px;
        font-size: 19px;
        font-weight: 700;
        line-height: 1.35;
      }

      .channel-bar {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        flex-wrap: wrap;
        margin-bottom: 14px;
      }

      .bar-actions {
        display: flex;
        align-items: center;
        gap: 8px;
        flex-wrap: wrap;
        margin-left: auto;
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

      .desc-card {
        background-color: var(--surface-variant);
        border-radius: var(--radius-md);
        padding: 12px 14px;
      }

      .desc-meta {
        display: flex;
        align-items: center;
        gap: 10px;
        flex-wrap: wrap;
        font-size: 13px;
        font-weight: 600;
        margin-bottom: 6px;
      }

      .cat-badge {
        padding: 2px 8px;
        border-radius: var(--radius-pill);
        background-color: var(--accent-soft);
        color: var(--accent);
        font-size: 11px;
      }

      .desc-text {
        margin: 0;
        font-size: 13px;
        line-height: 1.5;
        white-space: pre-wrap;
        word-break: break-word;
      }

      .desc-text.clamped {
        display: -webkit-box;
        -webkit-line-clamp: 3;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }

      .ts-link {
        color: var(--accent);
        font-weight: 600;
      }

      .ts-link:hover {
        text-decoration: underline;
      }

      .desc-toggle {
        margin-top: 6px;
        font-size: 13px;
        font-weight: 600;
      }

      .sidebar-col {
        display: flex;
        flex-direction: column;
        gap: 14px;
        min-width: 0;
      }

      .queue-box {
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-md);
        padding: 12px;
      }

      .queue-head,
      .upnext-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
      }

      .section-heading {
        margin: 0;
        font-size: 15px;
        font-weight: 700;
      }

      .load-previous {
        border: 0;
        padding: 4px;
        background: transparent;
        color: var(--accent);
        font: inherit;
        font-size: 12px;
        cursor: pointer;
      }

      .clear-q {
        font-size: 12px;
        color: var(--accent);
        font-weight: 600;
      }

      .autoplay-toggle {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        font-size: 12px;
        color: var(--on-surface-muted);
        cursor: pointer;
      }

      .related-list {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }

      .recommendations-load-more {
        min-height: 36px;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 8px;
        color: var(--on-surface-muted);
        text-align: center;
        font-size: 12px;
      }

      .recommendations-load-more button {
        border: 0;
        padding: 4px 8px;
        background: transparent;
        color: var(--accent);
        font: inherit;
        cursor: pointer;
      }

      .queue-row {
        display: flex;
        align-items: center;
        gap: 6px;
      }

      .q-remove {
        color: var(--on-surface-muted);
        flex-shrink: 0;
      }

      .related-row {
        flex: 1;
        display: flex;
        gap: 10px;
        align-items: flex-start;
        min-width: 0;
        padding: 6px;
        border-radius: var(--radius-sm);
        transition: background-color 140ms ease;
      }

      .related-row:hover {
        background-color: var(--surface-variant);
      }

      .related-row.now-playing {
        background-color: var(--accent-soft);
        outline: 1px solid color-mix(in srgb, var(--accent) 45%, transparent);
      }

      .rel-playing {
        position: absolute;
        left: 4px;
        bottom: 4px;
        padding: 1px 6px;
        border-radius: 4px;
        font-size: 10px;
        font-weight: 700;
        background: var(--accent);
        color: var(--on-accent);
      }

      .rel-thumb-wrap {
        position: relative;
        flex-shrink: 0;
      }

      .rel-thumb {
        width: clamp(112px, 32vw, 156px);
        aspect-ratio: 16 / 9;
        object-fit: cover;
        border-radius: var(--radius-sm);
        background-color: var(--surface-variant);
        display: block;
      }

      .rel-dur {
        position: absolute;
        right: 4px;
        bottom: 4px;
        padding: 1px 5px;
        border-radius: 4px;
        font-size: 10px;
        font-weight: 600;
        background: rgba(0, 0, 0, 0.85);
        color: #ffffff;
      }

      .rel-meta {
        display: flex;
        flex-direction: column;
        gap: 3px;
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
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .loading-box {
        padding: 48px 16px;
        text-align: center;
        color: var(--on-surface-muted);
      }

      .share-modal {
        max-width: 420px;
        padding: 16px;
        gap: 12px;
      }

      .share-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
      }

      .share-head h3 {
        margin: 0;
        font-size: 16px;
        font-weight: 700;
      }

      .share-url-row {
        display: flex;
        gap: 8px;
      }

      .share-input {
        flex: 1;
        min-width: 0;
        padding: 8px 10px;
        border-radius: var(--radius-sm);
        border: 1px solid var(--surface-border);
        background-color: var(--bg);
        font-size: 13px;
      }

      .share-start-check {
        display: flex;
        align-items: center;
        gap: 8px;
        font-size: 13px;
        cursor: pointer;
      }
    `,
  ],
})
export class WatchVideoComponent implements OnInit, OnDestroy {
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly videoService = inject(VideoService);
  readonly channels = inject(ChannelService);
  readonly screen = inject(ScreenClassService);
  readonly library = inject(VideoLibraryService);
  readonly userSync = inject(UserSyncService);
  private readonly playerService = inject(VideoPlayerService);
  private readonly zone = inject(NgZone);
  private readonly destroyRef = inject(DestroyRef);

  private recommendationsObserver?: IntersectionObserver;
  private previousObserver?: IntersectionObserver;
  private previousLoadingEnabled = false;
  private previousScrollArmed = false;
  private previousCursor?: Video;
  private previousPage = 0;
  private previousTotalPages = 0;
  private nextPage = 0;
  private nextTotalPages = 0;
  private lastPreviousPageKey: string | null = null;

  @ViewChild('previousEnd')
  set previousEndRef(ref: ElementRef<HTMLDivElement> | undefined) {
    this.previousObserver?.disconnect();
    this.previousObserver = undefined;
    if (!ref || typeof IntersectionObserver === 'undefined') return;
    this.previousObserver = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) {
          if (this.previousLoadingEnabled && !this.loadingPreviousVideos()) {
            this.previousScrollArmed = true;
          }
        } else if (this.previousLoadingEnabled && this.previousScrollArmed &&
                   !this.loadingPreviousVideos() && !this.previousLoadError()) {
          this.previousScrollArmed = false;
          this.zone.run(() => void this.loadPreviousVideos());
        }
      }
    }, { rootMargin: '100px 0px' });
    this.previousObserver.observe(ref.nativeElement);
  }

  @ViewChild('recommendationsEnd')
  set recommendationsEndRef(ref: ElementRef<HTMLDivElement> | undefined) {
    this.recommendationsObserver?.disconnect();
    this.recommendationsObserver = undefined;
    if (!ref || typeof IntersectionObserver === 'undefined') return;

    this.recommendationsObserver = new IntersectionObserver(
      (entries) => {
        if (
          entries.some((entry) => entry.isIntersecting) &&
          !this.loadingMoreRecommendations() &&
          !this.recommendationsLoadError()
        ) {
          this.zone.run(() => this.loadNextRecommendationsPage());
        }
      },
      { rootMargin: '240px 0px' },
    );
    this.recommendationsObserver.observe(ref.nativeElement);
  }

  private ytHostRef?: ElementRef<HTMLDivElement>;
  private ytPlayerReady = false;
  private ytMountGeneration = 0;

  @ViewChild('ytHost')
  set ytHost(value: ElementRef<HTMLDivElement> | undefined) {
    if (this.ytHostRef?.nativeElement === value?.nativeElement) return;
    this.ytHostRef = value;
    if (value) void this.mountYouTubePlayer(value.nativeElement);
  }
  @ViewChild('nativeVideo') nativeVideoRef?: ElementRef<HTMLVideoElement>;
  @ViewChild('playerContainer') playerContainerRef?: ElementRef<HTMLDivElement>;

  readonly video = signal<Video | null>(null);
  readonly related = signal<Video[]>([]);
  readonly previousVideos = signal<Video[]>([]);
  readonly previousVideosAvailable = signal(false);
  readonly loadingPreviousVideos = signal(false);
  readonly previousLoadError = signal(false);
  readonly watchList = computed(() => {
    const current = this.video();
    const previous = this.previousVideos();
    const previousIds = new Set(previous.map((item) => item.id));
    return [...previous, ...(current ? [current] : []), ...this.related().filter((item) => !previousIds.has(item.id))];
  });
  readonly loading = signal<boolean>(true);
  readonly descExpanded = signal<boolean>(false);
  readonly shareOpen = signal<boolean>(false);
  readonly shareAtCurrent = signal<boolean>(false);
  readonly copied = signal<boolean>(false);
  readonly currentSecondsSnapshot = signal<number>(0);
  readonly countdown = signal<number | null>(null);
  readonly loadingMoreRecommendations = signal<boolean>(false);
  readonly recommendationsLoadError = signal<boolean>(false);

  private ytPlayer: YTPlayerInstance | null = null;
  private progressTimer: ReturnType<typeof setInterval> | null = null;
  private countdownTimer: ReturnType<typeof setInterval> | null = null;
  private initialStartSeconds = 0;
  readonly recommendationsHasMore = signal<boolean>(false);
  private recommendationsInitialLoadComplete = false;
  private recommendationsCursor?: Video;
  private lastRecommendationsPageKey: string | null = null;
  private recommendationsGeneration = 0;

  readonly isSubscribed = computed(() => {
    const chId = this.video()?.channelId;
    return chId ? this.channels.subscribedIds().includes(chId) : false;
  });

  readonly isWatchLater = computed(() => {
    const id = this.video()?.id;
    return id ? this.library.isWatchLater(id) : false;
  });

  readonly isLiked = computed(() => {
    const v = this.video();
    if (!v) return false;
    const itemType = v.type === 'SHORT' ? 'liked_short' : 'liked_video';
    return this.userSync.isLiked(itemType, v.id);
  });

  toggleLike(): void {
    const video = this.video();
    if (!video) return;
    const itemType = video.type === 'SHORT' ? 'liked_short' : 'liked_video';
    this.userSync.setLiked({ itemType, itemId: video.id, liked: !this.isLiked() });
  }

  readonly nextUpVideo = computed<Video | null>(() => {
    const currentId = this.video()?.id;
    const queued = this.library.queue().find((item) => item.id !== currentId);
    return queued ?? this.related()[0] ?? null;
  });

  readonly descriptionSegments = computed<DescriptionSegment[]>(() => {
    const text = this.video()?.description ?? '';
    if (!text) return [];
    const regex = /\b(\d{1,2}):(\d{2})(?::(\d{2}))?\b(?!\s*(?:am|pm)\b)/gi;
    const segments: DescriptionSegment[] = [];
    let lastIndex = 0;
    for (const match of text.matchAll(regex)) {
      const idx = match.index ?? 0;
      if (idx > lastIndex) {
        segments.push({ text: text.slice(lastIndex, idx) });
      }
      const p1 = Number(match[1]);
      const p2 = Number(match[2]);
      const p3 = match[3] !== undefined ? Number(match[3]) : null;
      const seconds = p3 !== null ? p1 * 3600 + p2 * 60 + p3 : p1 * 60 + p2;
      segments.push({ text: match[0], seconds });
      lastIndex = idx + match[0].length;
    }
    if (lastIndex < text.length) {
      segments.push({ text: text.slice(lastIndex) });
    }
    return segments;
  });

  readonly shareUrl = computed(() => {
    const v = this.video();
    if (!v || typeof window === 'undefined') return '';
    const base = `${window.location.origin}/watch/${v.id}`;
    if (this.shareAtCurrent() && this.currentSecondsSnapshot() > 0) {
      return `${base}?t=${this.currentSecondsSnapshot()}`;
    }
    return base;
  });

  ngOnInit(): void {
    this.playerService.closeMiniPlayer();
    void this.channels.loadSubscriptions();
    combineLatest([this.route.paramMap, this.route.queryParamMap]).pipe(takeUntilDestroyed(this.destroyRef)).subscribe(
      async ([params, qp]) => {
        const id = params.get('id');
        if (!id) return;
        const tParam = Number(qp.get('t') || '0');
        await this.loadVideo(id, Number.isFinite(tParam) ? tParam : 0);
      },
    );
  }

  ngOnDestroy(): void {
    this.recommendationsGeneration++;
    this.recommendationsObserver?.disconnect();
    this.previousObserver?.disconnect();
    this.saveCurrentProgress();
    this.teardownPlayers();
  }

  @HostListener('window:keydown', ['$event'])
  onKeyDown(event: KeyboardEvent): void {
    const target = event.target as HTMLElement | null;
    if (
      target &&
      (target.tagName === 'INPUT' ||
        target.tagName === 'TEXTAREA' ||
        target.isContentEditable)
    ) {
      return;
    }

    switch (event.key.toLowerCase()) {
      case ' ':
      case 'k':
        event.preventDefault();
        this.togglePlayPause();
        break;
      case 'j':
        this.seekRelative(-10);
        break;
      case 'l':
        this.seekRelative(10);
        break;
      case 'arrowleft':
        this.seekRelative(-5);
        break;
      case 'arrowright':
        this.seekRelative(5);
        break;
      case 'f':
        this.toggleFullscreen();
        break;
      case 'm':
        this.toggleMute();
        break;
    }
  }

  private async loadVideo(id: string, queryStartSeconds: number): Promise<void> {
    const generation = ++this.recommendationsGeneration;
    this.saveCurrentProgress();
    this.cancelCountdown();
    this.related.set([]);
    this.previousVideos.set([]);
    this.previousCursor = undefined;
    this.previousPage = 0;
    this.previousTotalPages = 0;
    this.nextPage = 0;
    this.nextTotalPages = 0;
    this.lastPreviousPageKey = null;
    this.previousVideosAvailable.set(false);
    this.loadingPreviousVideos.set(false);
    this.previousLoadError.set(false);
    this.previousLoadingEnabled = false;
    this.previousScrollArmed = false;
    this.recommendationsHasMore.set(false);
    this.recommendationsInitialLoadComplete = false;
    this.loadingMoreRecommendations.set(false);
    this.recommendationsLoadError.set(false);
    this.recommendationsCursor = undefined;
    this.lastRecommendationsPageKey = null;
    if (!this.video()) {
      this.loading.set(true);
    }
    this.descExpanded.set(false);

    const v = await this.videoService.fetchVideoById(id);
    if (generation !== this.recommendationsGeneration) return;
    this.video.set(v);
    this.loading.set(false);

    if (!v) {
      this.teardownPlayers();
      return;
    }

    this.initialStartSeconds =
      queryStartSeconds > 0 ? queryStartSeconds : this.library.resumeSeconds(v.id);

    this.library.recordProgress(v, this.initialStartSeconds, 0);

    this.previousCursor = v;
    this.recommendationsCursor = v;
    if (v.streamUrl) {
      this.teardownPlayers();
    } else if (this.ytPlayer && this.ytPlayerReady) {
      this.ytPlayer.loadVideoById({
        videoId: v.id,
        startSeconds: this.initialStartSeconds > 0 ? this.initialStartSeconds : 0,
      });
    }
    if (v.channelId) void this.loadChannelPageCounts(v, generation);
  }

  private async mountYouTubePlayer(host: HTMLDivElement): Promise<void> {
    const mountGeneration = ++this.ytMountGeneration;
    await ensureYouTubeIframeApi();
    const v = this.video();
    if (mountGeneration !== this.ytMountGeneration ||
        this.ytHostRef?.nativeElement !== host || !host.isConnected ||
        !v || v.streamUrl || !window.YT?.Player) return;

    const ytId = v.id;
    const playerTarget = document.createElement('div');
    host.replaceChildren(playerTarget);
    this.ytPlayer = new window.YT.Player(playerTarget, {
      width: '100%',
      height: '100%',
      videoId: ytId,
      playerVars: {
        autoplay: 1,
        rel: 0,
        playsinline: 1,
        start: this.initialStartSeconds > 0 ? this.initialStartSeconds : 0,
      },
      events: {
        onReady: (event) => {
          if (mountGeneration !== this.ytMountGeneration) return;
          this.ytPlayerReady = true;
          const current = this.video();
          if (current && !current.streamUrl) {
            event.target.loadVideoById({
              videoId: current.id,
              startSeconds: this.initialStartSeconds,
            });
          }
          this.startProgressPolling();
        },
        onStateChange: (ev) => {
          if (ev.data === window.YT?.PlayerState?.ENDED) {
            this.onPlaybackEnded();
          }
        },
      },
    });
  }

  private startProgressPolling(): void {
    if (this.progressTimer) clearInterval(this.progressTimer);
    this.progressTimer = setInterval(() => this.saveCurrentProgress(), 5000);
  }

  private saveCurrentProgress(): void {
    const v = this.video();
    if (!v) return;
    if (this.ytPlayer) {
      const pos = this.ytPlayer.getCurrentTime?.() ?? 0;
      const dur = this.ytPlayer.getDuration?.() ?? 0;
      if (pos > 0) {
        this.library.recordProgress(v, pos, dur);
      }
    } else if (this.nativeVideoRef?.nativeElement) {
      const el = this.nativeVideoRef.nativeElement;
      if (el.currentTime > 0) {
        this.library.recordProgress(v, el.currentTime, el.duration || 0);
      }
    }
  }

  private teardownPlayers(): void {
    this.ytMountGeneration++;
    this.ytPlayerReady = false;
    if (this.progressTimer) {
      clearInterval(this.progressTimer);
      this.progressTimer = null;
    }
    this.cancelCountdown();
    if (this.ytPlayer) {
      try {
        this.ytPlayer.destroy();
      } catch {
        // ignore
      }
      this.ytPlayer = null;
    }
  }

  onVideoLoaded(event: Event): void {
    const el = event.target as HTMLVideoElement | null;
    if (!el || this.initialStartSeconds <= 0) return;
    if (Number.isFinite(el.duration) && this.initialStartSeconds < el.duration) {
      el.currentTime = this.initialStartSeconds;
    }
  }

  onNativeTimeUpdate(event: Event): void {
    const el = event.target as HTMLVideoElement | null;
    const v = this.video();
    if (!el || !v) return;
    if (Math.floor(el.currentTime) % 5 === 0 && el.currentTime > 0) {
      this.library.recordProgress(v, el.currentTime, el.duration || 0);
    }
  }

  onPlaybackEnded(): void {
    if (!this.library.autoplay()) return;
    void this.startAutoplayCountdown();
  }

  private async startAutoplayCountdown(): Promise<void> {
    if (!this.nextUpVideo() && this.recommendationsHasMore()) {
      await this.loadMoreRecommendations(this.recommendationsGeneration);
    }
    if (!this.library.autoplay() || !this.nextUpVideo()) return;
    this.cancelCountdown();
    this.countdown.set(5);
    this.countdownTimer = setInterval(() => {
      const cur = this.countdown();
      if (cur === null) return;
      if (cur <= 1) {
        this.playNextNow();
      } else {
        this.countdown.set(cur - 1);
      }
    }, 1000);
  }

  cancelCountdown(): void {
    if (this.countdownTimer) {
      clearInterval(this.countdownTimer);
      this.countdownTimer = null;
    }
    this.countdown.set(null);
  }

  playNextNow(): void {
    this.cancelCountdown();
    const currentId = this.video()?.id;
    let queued = this.library.consumeNextInQueue();
    while (queued?.id === currentId) {
      queued = this.library.consumeNextInQueue();
    }
    const next = queued ?? this.related()[0] ?? null;
    if (next) {
      void this.router.navigate(['/watch', next.id]);
    }
  }

  loadNextRecommendationsPage(): void {
    void this.loadMoreRecommendations(this.recommendationsGeneration);
  }

  private async loadChannelPageCounts(current: Video, generation: number): Promise<void> {
    try {
      const counts = await this.videoService.fetchChannelPosition(current.id);
      if (generation !== this.recommendationsGeneration) return;
      this.previousTotalPages = Math.ceil(counts.newer / 16);
      this.nextTotalPages = Math.ceil(counts.older / 16);
      this.previousLoadError.set(false);
      this.previousVideosAvailable.set(this.previousPage < this.previousTotalPages);
      this.recommendationsHasMore.set(this.nextPage < this.nextTotalPages);
      if (this.recommendationsHasMore()) void this.loadMoreRecommendations(generation);
    } catch {
      if (generation === this.recommendationsGeneration) {
        this.previousLoadError.set(true);
        this.previousVideosAvailable.set(false);
        this.recommendationsLoadError.set(true);
      }
    }
  }

  async loadPreviousVideos(): Promise<void> {
    const current = this.video();
    const cursor = this.previousCursor;
    if (!current?.channelId || !cursor || !this.previousVideosAvailable() || this.loadingPreviousVideos()) return;
    this.previousLoadingEnabled = true;
    this.previousScrollArmed = false;
    this.loadingPreviousVideos.set(true);
    this.previousLoadError.set(false);
    const generation = this.recommendationsGeneration;
    try {
      const page = await this.videoService.queryVideos({
          channelId: current.channelId,
          type: 'VIDEO',
          sort: 'oldest',
          limit: 16,
          publishedAfter: cursor.publishedAt,
          afterId: cursor.id,
        });
        if (generation !== this.recommendationsGeneration) return;
        const key = page.map((item) => item.id).join('\u0000');
        if (page.length > 0 && key === this.lastPreviousPageKey) {
          throw new Error('Previous video pagination did not advance');
        }
        this.lastPreviousPageKey = key;
      if (generation !== this.recommendationsGeneration) return;
      const knownIds = new Set(this.previousVideos().map((item) => item.id));
      const cursorTime = Date.parse(cursor.publishedAt);
      const items = page.filter((item) => {
        const time = Date.parse(item.publishedAt);
        if (!item.id || knownIds.has(item.id) ||
            !(time > cursorTime || (time === cursorTime && item.id > cursor.id))) return false;
        knownIds.add(item.id);
        return true;
      });
      if (page.length > 0 && items.length !== page.length) {
        throw new Error('Previous video page did not advance');
      }
      if (items.length) {
        this.previousCursor = items[items.length - 1];
        this.previousVideos.set([...items.reverse(), ...this.previousVideos()]);
      }
      this.previousPage++;
      this.previousVideosAvailable.set(this.previousPage < this.previousTotalPages && items.length > 0);
    } catch {
      if (generation === this.recommendationsGeneration) this.previousLoadError.set(true);
    } finally {
      if (generation === this.recommendationsGeneration) this.loadingPreviousVideos.set(false);
    }
  }

  retryRecommendationsPage(): void {
    this.recommendationsLoadError.set(false);
    if (!this.recommendationsInitialLoadComplete && this.nextTotalPages === 0) {
      const current = this.video();
      if (current) void this.loadChannelPageCounts(current, this.recommendationsGeneration);
    } else {
      void this.loadMoreRecommendations(this.recommendationsGeneration);
    }
  }

  private async loadMoreRecommendations(generation: number): Promise<void> {
    const current = this.video();
    if (
      !current?.channelId ||
      (this.recommendationsInitialLoadComplete && !this.recommendationsHasMore()) ||
      this.loadingMoreRecommendations()
    ) {
      return;
    }

    this.loadingMoreRecommendations.set(true);
    this.recommendationsLoadError.set(false);
    try {
      {
        const cursor = this.recommendationsCursor;
        if (!cursor) return;
        const page = await this.videoService.queryVideos({
            channelId: current.channelId,
            type: 'VIDEO',
            sort: 'latest',
            limit: 16,
            publishedBefore: cursor.publishedAt,
            beforeId: cursor.id,
          });
          if (generation !== this.recommendationsGeneration) return;
          const pageKey = page.map((item) => item.id).join('\u0000');
          if (page.length > 0 && pageKey === this.lastRecommendationsPageKey) {
            throw new Error('Recommendations pagination did not advance');
          }
          this.lastRecommendationsPageKey = pageKey;

        const existingIds = new Set(this.related().map((item) => item.id));
        const currentTime = Date.parse(cursor.publishedAt);
        const unique = page.filter((item) => {
          const itemTime = Date.parse(item.publishedAt);
          const older = itemTime < currentTime ||
            (itemTime === currentTime && item.id < cursor.id);
          if (!item.id || !older || existingIds.has(item.id)) return false;
          existingIds.add(item.id);
          return true;
        });
        if (page.length > 0 && unique.length !== page.length) {
          throw new Error('Recommendations pagination did not advance');
        }
        if (unique.length > 0) {
          this.related.set([...this.related(), ...unique]);
          this.recommendationsCursor = unique[unique.length - 1];
        }
        this.nextPage++;
        this.recommendationsHasMore.set(this.nextPage < this.nextTotalPages && page.length > 0);
        this.recommendationsInitialLoadComplete = true;
      }
    } catch {
      if (generation === this.recommendationsGeneration) {
        this.recommendationsLoadError.set(true);
      }
    } finally {
      if (generation === this.recommendationsGeneration) {
        this.loadingMoreRecommendations.set(false);
      }
    }
  }

  seekTo(seconds: number): void {
    if (this.ytPlayer) {
      this.ytPlayer.seekTo(seconds, true);
      this.ytPlayer.playVideo();
    } else if (this.nativeVideoRef?.nativeElement) {
      this.nativeVideoRef.nativeElement.currentTime = seconds;
      void this.nativeVideoRef.nativeElement.play();
    }
  }

  private seekRelative(delta: number): void {
    const current = this.getCurrentSeconds();
    this.seekTo(Math.max(0, current + delta));
  }

  private getCurrentSeconds(): number {
    if (this.ytPlayer) {
      return Math.floor(this.ytPlayer.getCurrentTime?.() ?? 0);
    }
    if (this.nativeVideoRef?.nativeElement) {
      return Math.floor(this.nativeVideoRef.nativeElement.currentTime || 0);
    }
    return 0;
  }

  private togglePlayPause(): void {
    if (this.ytPlayer) {
      const state = this.ytPlayer.getPlayerState?.();
      if (state === window.YT?.PlayerState?.PLAYING) {
        this.ytPlayer.pauseVideo();
      } else {
        this.ytPlayer.playVideo();
      }
    } else if (this.nativeVideoRef?.nativeElement) {
      const el = this.nativeVideoRef.nativeElement;
      if (el.paused) void el.play();
      else el.pause();
    }
  }

  private toggleMute(): void {
    if (this.ytPlayer) {
      if (this.ytPlayer.isMuted()) this.ytPlayer.unMute();
      else this.ytPlayer.mute();
    } else if (this.nativeVideoRef?.nativeElement) {
      this.nativeVideoRef.nativeElement.muted =
        !this.nativeVideoRef.nativeElement.muted;
    }
  }

  private toggleFullscreen(): void {
    const el = this.playerContainerRef?.nativeElement;
    if (!el) return;
    if (document.fullscreenElement) {
      void document.exitFullscreen();
    } else {
      void el.requestFullscreen?.();
    }
  }

  minimizeToMini(): void {
    const v = this.video();
    if (!v) return;
    this.playerService.openMiniPlayer(v, this.getCurrentSeconds());
    void this.router.navigate(['/feed']);
  }

  openShare(): void {
    this.currentSecondsSnapshot.set(this.getCurrentSeconds());
    this.copied.set(false);
    this.shareOpen.set(true);
  }

  copyShareUrl(): void {
    const url = this.shareUrl();
    if (!url || !navigator.clipboard) return;
    void navigator.clipboard.writeText(url);
    this.copied.set(true);
  }

  toggleSubscribe(): void {
    const id = this.video()?.channelId;
    if (id) {
      void this.channels.toggleSubscribe(id);
    }
  }

  formatViews(n: number): string {
    return formatViewCount(n);
  }

  formatTime(iso: string): string {
    return formatTimeAgo(iso);
  }

  formatSeconds(total: number): string {
    const m = Math.floor(total / 60);
    const s = total % 60;
    return `${m}:${String(s).padStart(2, '0')}`;
  }
}
