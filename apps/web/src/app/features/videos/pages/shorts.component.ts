import {
  ChangeDetectionStrategy,
  Component,
  HostListener,
  OnInit,
  computed,
  inject,
  signal,
} from '@angular/core';
import { DomSanitizer, SafeResourceUrl } from '@angular/platform-browser';
import { RouterLink } from '@angular/router';
import { ChannelService } from '../../channels/services/channel.service';
import { Video, formatViewCount } from '../models/video.model';
import { VideoService } from '../services/video.service';

@Component({
  selector: 'app-shorts-page',
  standalone: true,
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (activeShort(); as current) {
      <div class="shorts-stage">
        <div class="stage-top">
          <button
            type="button"
            class="stage-pill"
            (click)="activeIndex.set(null)"
          >
            <span class="material-symbols-rounded">grid_view</span>
            Shorts
          </button>
          <span class="stage-counter">
            {{ activeIndex()! + 1 }} / {{ videos.shorts().length }}
          </span>
        </div>

        <div class="stage-center">
          <div class="vertical-player">
            @if (current.streamUrl) {
              <video
                class="short-media"
                [src]="current.streamUrl"
                controls
                autoplay
                playsinline
                loop
              ></video>
            } @else {
              <iframe
                class="short-media"
                [src]="embedUrl(current)"
                [title]="current.title"
                allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                allowfullscreen
              ></iframe>
            }

            <div class="bottom-overlay">
              <div class="channel-row">
                <a
                  class="channel-link"
                  [routerLink]="['/channels', current.channelId]"
                >
                  {{ current.channelTitle }}
                </a>
                @if (current.channelId) {
                  <button
                    type="button"
                    class="follow-btn"
                    [class.active]="!isFollowing(current.channelId)"
                    (click)="channelService.toggleSubscribe(current.channelId)"
                  >
                    {{ isFollowing(current.channelId) ? 'Following' : 'Follow' }}
                  </button>
                }
              </div>
              <p class="overlay-title">{{ current.title }}</p>
            </div>
          </div>

          <div class="side-rail">
            <button
              type="button"
              class="rail-btn"
              title="Previous Short"
              [disabled]="activeIndex()! <= 0"
              (click)="prev()"
            >
              <span class="material-symbols-rounded">keyboard_arrow_up</span>
            </button>
            <button
              type="button"
              class="rail-btn"
              title="Next Short"
              [disabled]="activeIndex()! >= videos.shorts().length - 1"
              (click)="next()"
            >
              <span class="material-symbols-rounded">keyboard_arrow_down</span>
            </button>
            <button
              type="button"
              class="rail-btn"
              title="Share Short"
              (click)="shareShort(current)"
            >
              <span class="material-symbols-rounded">share</span>
            </button>
            <a
              class="rail-btn"
              title="Watch full video"
              [routerLink]="['/watch', current.id]"
            >
              <span class="material-symbols-rounded">open_in_new</span>
            </a>
          </div>
        </div>
      </div>
    } @else {
      <div class="shorts-page max-width-box">
        <header class="page-head">
          <h1 class="font-display">Shorts</h1>
        </header>

        @if (videos.shortsLoading() && videos.shorts().length === 0) {
          <p class="status-msg">Loading shorts...</p>
        } @else if (videos.shortsError()) {
          <div class="status-msg">
            <p>{{ videos.shortsError() }}</p>
            <button
              type="button"
              class="pill-chip active"
              (click)="videos.fetchShorts(true)"
            >
              Retry
            </button>
          </div>
        } @else if (videos.shorts().length === 0) {
          <p class="status-msg">No shorts available right now.</p>
        } @else {
          <div class="shorts-grid">
            @for (s of videos.shorts(); track s.id; let i = $index) {
              <button
                type="button"
                class="short-tile"
                (click)="activeIndex.set(i)"
              >
                <img
                  class="short-thumb"
                  [src]="s.thumbnailUrl"
                  [alt]="s.title"
                  loading="lazy"
                />
                <div class="short-scrim">
                  <span class="short-title">{{ s.title }}</span>
                  <span class="short-meta">
                    {{ s.channelTitle }}
                    @if (s.viewCount > 0) {
                      · {{ formatViews(s.viewCount) }}
                    }
                  </span>
                </div>
              </button>
            }
          </div>
        }
      </div>
    }
  `,
  styles: [
    `
      .shorts-page {
        padding-top: 16px;
        padding-bottom: 32px;
      }

      .page-head h1 {
        margin: 0 0 14px;
        font-size: 22px;
        font-weight: 700;
      }

      .shorts-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(165px, 1fr));
        gap: 14px;
      }

      .short-tile {
        position: relative;
        aspect-ratio: 9 / 16;
        border-radius: var(--radius-md);
        overflow: hidden;
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        text-align: left;
      }

      .short-thumb {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }

      .short-scrim {
        position: absolute;
        inset: auto 0 0 0;
        padding: 28px 10px 10px;
        background: linear-gradient(to top, rgba(0, 0, 0, 0.82), transparent);
        color: #ffffff;
        display: flex;
        flex-direction: column;
        gap: 3px;
      }

      .short-title {
        font-size: 13px;
        font-weight: 600;
        line-height: 1.3;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }

      .short-meta {
        font-size: 11px;
        color: rgba(255, 255, 255, 0.78);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      /* In-page Fullscreen Vertical Shorts Stage */
      .shorts-stage {
        height: calc(100dvh - var(--shell-bottom-height) - var(--shell-top-offset));
        background-color: #0b0f19;
        color: #ffffff;
        display: flex;
        flex-direction: column;
        padding: 12px 16px;
        gap: 10px;
      }

      @media (min-width: 600px) {
        .shorts-stage {
          height: calc(100dvh - var(--shell-top-offset));
          padding: 16px 24px;
        }
      }

      .stage-top {
        display: flex;
        align-items: center;
        justify-content: space-between;
      }

      .stage-pill {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        height: 34px;
        padding: 0 12px;
        border-radius: var(--radius-pill);
        background-color: rgba(255, 255, 255, 0.14);
        color: #ffffff;
        font-size: 13px;
        font-weight: 600;
      }

      .stage-counter {
        font-size: 12px;
        font-weight: 600;
        color: rgba(255, 255, 255, 0.75);
      }

      .stage-center {
        flex: 1;
        min-height: 0;
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 14px;
      }

      .vertical-player {
        position: relative;
        height: 100%;
        max-height: 780px;
        aspect-ratio: 9 / 16;
        max-width: calc(100% - 60px);
        background-color: #000000;
        border-radius: var(--radius-lg);
        overflow: hidden;
        box-shadow: 0 12px 32px rgba(0, 0, 0, 0.45);
      }

      .short-media {
        width: 100%;
        height: 100%;
        border: none;
        display: block;
      }

      .bottom-overlay {
        position: absolute;
        left: 0;
        right: 0;
        bottom: 0;
        padding: 36px 14px 14px;
        background: linear-gradient(to top, rgba(0, 0, 0, 0.85), transparent);
        pointer-events: none;
      }

      .channel-row,
      .follow-btn,
      .channel-link {
        pointer-events: auto;
      }

      .channel-row {
        display: flex;
        align-items: center;
        gap: 10px;
        margin-bottom: 6px;
      }

      .channel-link {
        font-size: 13px;
        font-weight: 700;
        color: #ffffff;
      }

      .follow-btn {
        padding: 4px 10px;
        border-radius: var(--radius-pill);
        background-color: rgba(255, 255, 255, 0.2);
        color: #ffffff;
        font-size: 12px;
        font-weight: 600;
      }

      .follow-btn.active {
        background-color: var(--accent);
        color: var(--on-accent);
      }

      .overlay-title {
        margin: 0;
        font-size: 13px;
        line-height: 1.35;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }

      .side-rail {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }

      .rail-btn {
        width: 44px;
        height: 44px;
        border-radius: var(--radius-pill);
        background-color: rgba(255, 255, 255, 0.14);
        color: #ffffff;
        display: grid;
        place-items: center;
      }

      .rail-btn[disabled] {
        opacity: 0.3;
        cursor: not-allowed;
      }

      .status-msg {
        text-align: center;
        padding: 36px 0;
        color: var(--on-surface-muted);
      }
    `,
  ],
})
export class ShortsComponent implements OnInit {
  private readonly sanitizer = inject(DomSanitizer);
  readonly videos = inject(VideoService);
  readonly channelService = inject(ChannelService);

  readonly activeIndex = signal<number | null>(null);

  readonly activeShort = computed<Video | null>(() => {
    const idx = this.activeIndex();
    if (idx === null) return null;
    return this.videos.shorts()[idx] ?? null;
  });

  formatViews = formatViewCount;

  @HostListener('window:keydown', ['$event'])
  onKeyDown(event: KeyboardEvent): void {
    if (this.activeIndex() === null) return;
    if (event.key === 'Escape') {
      this.activeIndex.set(null);
    } else if (event.key === 'ArrowDown' || event.key === 'ArrowRight') {
      this.next();
    } else if (event.key === 'ArrowUp' || event.key === 'ArrowLeft') {
      this.prev();
    }
  }

  ngOnInit(): void {
    void this.videos.fetchShorts();
    void this.channelService.loadSubscriptions();
  }

  isFollowing(channelId: string): boolean {
    return this.channelService.subscribedIds().includes(channelId);
  }

  embedUrl(v: Video): SafeResourceUrl {
    return this.sanitizer.bypassSecurityTrustResourceUrl(
      `https://www.youtube.com/embed/${encodeURIComponent(v.id)}?autoplay=1&rel=0`,
    );
  }

  prev(): void {
    const idx = this.activeIndex();
    if (idx !== null && idx > 0) {
      this.activeIndex.set(idx - 1);
    }
  }

  next(): void {
    const idx = this.activeIndex();
    if (idx !== null && idx + 1 < this.videos.shorts().length) {
      this.activeIndex.set(idx + 1);
    }
  }

  shareShort(v: Video): void {
    const url = `${window.location.origin}/watch/${encodeURIComponent(v.id)}`;
    if (navigator.share) {
      void navigator.share({ title: v.title, url }).catch(() => {
        void navigator.clipboard?.writeText(url);
      });
    } else {
      void navigator.clipboard?.writeText(url);
    }
  }
}
