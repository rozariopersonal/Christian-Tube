import { ChangeDetectionStrategy, Component, computed, inject } from '@angular/core';
import { DomSanitizer, SafeResourceUrl } from '@angular/platform-browser';
import { Router } from '@angular/router';
import { VideoPlayerService } from '../services/video-player.service';

@Component({
  selector: 'app-video-mini-player',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (player.miniVideo(); as video) {
      <div class="mini-video-dock" role="region" aria-label="Mini video player">
        <div class="mini-media">
          @if (video.streamUrl) {
            <video
              class="mini-el"
              [src]="video.streamUrl"
              controls
              autoplay
              playsinline
            ></video>
          } @else {
            <iframe
              class="mini-el"
              [src]="embedUrl()"
              [title]="video.title"
              allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
              allowfullscreen
            ></iframe>
          }
        </div>
        <div class="mini-footer">
          <button type="button" class="mini-info" (click)="expand(video.id)">
            <span class="mini-title">{{ video.title }}</span>
            <span class="mini-sub">{{ video.channelTitle }}</span>
          </button>
          <button
            type="button"
            class="mini-btn"
            aria-label="Expand player"
            title="Expand"
            (click)="expand(video.id)"
          >
            <span class="material-symbols-rounded">open_in_full</span>
          </button>
          <button
            type="button"
            class="mini-btn"
            aria-label="Close mini player"
            title="Close"
            (click)="player.closeMiniPlayer()"
          >
            <span class="material-symbols-rounded">close</span>
          </button>
        </div>
      </div>
    }
  `,
  styles: [
    `
      .mini-video-dock {
        position: fixed;
        right: 16px;
        bottom: 16px;
        width: 320px;
        max-width: calc(100vw - 32px);
        background-color: var(--surface-elevated);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-md);
        box-shadow: 0 12px 32px rgba(0, 0, 0, 0.28);
        overflow: hidden;
        z-index: 70;
      }

      @media (max-width: 599px) {
        .mini-video-dock {
          bottom: calc(var(--shell-bottom-offset, 0px) + env(safe-area-inset-bottom, 0px) + 8px);
          right: 10px;
          width: 260px;
        }
      }

      .mini-media {
        width: 100%;
        aspect-ratio: 16 / 9;
        background-color: #000000;
      }

      .mini-el {
        width: 100%;
        height: 100%;
        border: 0;
        display: block;
      }

      .mini-footer {
        display: flex;
        align-items: center;
        gap: 6px;
        padding: 8px 10px;
      }

      .mini-info {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
        text-align: left;
      }

      .mini-title {
        font-size: 12px;
        font-weight: 600;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .mini-sub {
        font-size: 11px;
        color: var(--on-surface-muted);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .mini-btn {
        width: 30px;
        height: 30px;
        border-radius: var(--radius-pill);
        display: grid;
        place-items: center;
        color: var(--on-surface-muted);
        flex-shrink: 0;
      }

      .mini-btn:hover {
        background-color: var(--surface-variant);
        color: var(--on-surface);
      }

      .mini-btn .material-symbols-rounded {
        font-size: 18px;
      }
    `,
  ],
})
export class VideoMiniPlayerComponent {
  readonly player = inject(VideoPlayerService);
  private readonly sanitizer = inject(DomSanitizer);
  private readonly router = inject(Router);

  readonly embedUrl = computed<SafeResourceUrl | null>(() => {
    const v = this.player.miniVideo();
    if (!v) return null;
    const ytId = v.id;
    const start = this.player.startSeconds();
    const url = `https://www.youtube.com/embed/${encodeURIComponent(ytId)}?autoplay=1&rel=0&playsinline=1${start > 0 ? `&start=${start}` : ''}`;
    return this.sanitizer.bypassSecurityTrustResourceUrl(url);
  });

  expand(videoId: string): void {
    this.player.closeMiniPlayer();
    void this.router.navigate(['/watch', videoId]);
  }
}
