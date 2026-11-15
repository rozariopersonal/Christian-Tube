import { Component, input } from '@angular/core';
import { RouterLink } from '@angular/router';
import {
  Video,
  formatTimeAgo,
  formatViewCount,
} from '../../features/videos/models/video.model';

@Component({
  selector: 'app-video-card',
  standalone: true,
  imports: [RouterLink],
  template: `
    <a class="video-card" [routerLink]="['/watch', video().id]">
      <div class="thumb-wrap">
        <img
          class="thumb"
          [src]="video().thumbnailUrl"
          [alt]="video().title"
          loading="lazy"
        />
        @if (video().isLive) {
          <span class="badge live-badge">
            <span class="material-symbols-rounded badge-icon">sensors</span>
            LIVE
          </span>
        } @else if (video().duration && video().duration !== '0:00') {
          <span class="badge duration-badge">{{ video().duration }}</span>
        }
      </div>

      <div class="meta-row">
        <a
          class="avatar-link"
          [routerLink]="['/channels', video().channelId]"
          (click)="$event.stopPropagation()"
          [attr.aria-label]="video().channelTitle"
        >
          @if (video().channelAvatarUrl) {
            <img
              class="avatar"
              [src]="video().channelAvatarUrl"
              [alt]="video().channelTitle"
              loading="lazy"
            />
          } @else {
            <span class="avatar fallback">
              {{ video().channelTitle.slice(0, 1).toUpperCase() }}
            </span>
          }
        </a>

        <div class="meta-text">
          <h3 class="title">{{ video().title }}</h3>
          <p class="sub">
            {{ video().channelTitle }}
            @if (video().viewCount > 0) {
              <span> · {{ viewsLabel() }}</span>
            }
            @if (timeLabel()) {
              <span> · {{ timeLabel() }}</span>
            }
          </p>
        </div>
      </div>
    </a>
  `,
  styles: [
    `
      .video-card {
        display: flex;
        flex-direction: column;
        gap: 10px;
        text-decoration: none;
        color: inherit;
      }

      .thumb-wrap {
        position: relative;
        width: 100%;
        aspect-ratio: 16 / 9;
        border-radius: var(--radius-md);
        overflow: hidden;
        background-color: var(--surface-variant);
      }

      .thumb {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }

      .badge {
        position: absolute;
        right: 8px;
        bottom: 8px;
        padding: 2px 6px;
        border-radius: 4px;
        font-size: 11px;
        font-weight: 600;
        display: inline-flex;
        align-items: center;
        gap: 4px;
      }

      .duration-badge {
        background-color: rgba(0, 0, 0, 0.85);
        color: #ffffff;
      }

      .live-badge {
        background-color: var(--error);
        color: var(--on-error);
        font-weight: 700;
      }

      .badge-icon {
        font-size: 13px;
      }

      .meta-row {
        display: flex;
        gap: 12px;
        align-items: flex-start;
      }

      .avatar-link {
        flex-shrink: 0;
      }

      .avatar {
        width: 36px;
        height: 36px;
        border-radius: var(--radius-pill);
        object-fit: cover;
        display: block;
        background-color: var(--surface-variant);
      }

      .avatar.fallback {
        display: grid;
        place-items: center;
        font-weight: 700;
        font-size: 14px;
        color: var(--accent);
        background-color: var(--accent-soft);
      }

      .meta-text {
        min-width: 0;
        flex: 1;
      }

      .title {
        margin: 0 0 4px;
        font-size: 14px;
        font-weight: 600;
        line-height: 1.35;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }

      .sub {
        margin: 0;
        font-size: 13px;
        color: var(--on-surface-muted);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
    `,
  ],
})
export class VideoCardComponent {
  readonly video = input.required<Video>();

  viewsLabel(): string {
    return formatViewCount(this.video().viewCount);
  }

  timeLabel(): string {
    return formatTimeAgo(this.video().publishedAt);
  }
}
