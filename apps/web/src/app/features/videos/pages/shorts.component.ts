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
import { Video, formatViewCount } from '../models/video.model';
import { VideoService } from '../services/video.service';

@Component({
  selector: 'app-shorts-page',
  standalone: true,
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
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

      @if (activeShort(); as current) {
        <div class="player-backdrop" (click)="activeIndex.set(null)">
          <div class="player-shell" (click)="$event.stopPropagation()">
            <div class="player-top">
              <span class="short-counter">
                {{ activeIndex()! + 1 }} / {{ videos.shorts().length }}
              </span>
              <button
                type="button"
                class="icon-btn light-btn"
                aria-label="Close shorts player"
                (click)="activeIndex.set(null)"
              >
                <span class="material-symbols-rounded">close</span>
              </button>
            </div>

            <div class="vertical-frame">
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
            </div>

            <div class="player-footer">
              <div class="footer-meta">
                <strong>{{ current.title }}</strong>
                <span>{{ current.channelTitle }}</span>
              </div>
              <div class="footer-actions">
                <button
                  type="button"
                  class="pill-chip"
                  [disabled]="activeIndex()! <= 0"
                  (click)="prev()"
                >
                  <span class="material-symbols-rounded">keyboard_arrow_up</span>
                  Prev
                </button>
                <button
                  type="button"
                  class="pill-chip"
                  [disabled]="activeIndex()! >= videos.shorts().length - 1"
                  (click)="next()"
                >
                  Next
                  <span class="material-symbols-rounded">keyboard_arrow_down</span>
                </button>
                <a
                  class="pill-chip active"
                  [routerLink]="['/watch', current.id]"
                  (click)="activeIndex.set(null)"
                >
                  Watch
                </a>
                <button
                  type="button"
                  class="pill-chip"
                  (click)="shareShort(current)"
                >
                  <span class="material-symbols-rounded">share</span>
                </button>
              </div>
            </div>
          </div>
        </div>
      }
    </div>
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

      .player-backdrop {
        position: fixed;
        inset: 0;
        z-index: 100;
        background-color: rgba(0, 0, 0, 0.85);
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 16px;
      }

      .player-shell {
        width: 100%;
        max-width: 420px;
        max-height: 92dvh;
        display: flex;
        flex-direction: column;
        gap: 10px;
      }

      .player-top {
        display: flex;
        align-items: center;
        justify-content: space-between;
        color: #ffffff;
      }

      .short-counter {
        font-size: 13px;
        font-weight: 600;
      }

      .light-btn {
        color: #ffffff;
      }

      .vertical-frame {
        width: 100%;
        aspect-ratio: 9 / 16;
        max-height: 68dvh;
        background-color: #000000;
        border-radius: var(--radius-lg);
        overflow: hidden;
      }

      .short-media {
        width: 100%;
        height: 100%;
        border: none;
        display: block;
      }

      .player-footer {
        background-color: var(--surface);
        border-radius: var(--radius-md);
        padding: 10px 12px;
        display: flex;
        flex-direction: column;
        gap: 8px;
      }

      .footer-meta {
        display: flex;
        flex-direction: column;
        gap: 2px;
      }

      .footer-meta strong {
        font-size: 14px;
        line-height: 1.3;
      }

      .footer-meta span {
        font-size: 12px;
        color: var(--on-surface-muted);
      }

      .footer-actions {
        display: flex;
        align-items: center;
        gap: 6px;
        flex-wrap: wrap;
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
