import { Component, computed, inject, input, signal } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import {
  Video,
  formatTimeAgo,
  formatViewCount,
} from '../../features/videos/models/video.model';
import { VideoLibraryService } from '../../features/videos/services/video-library.service';
import { VideoWatchedOverlaysComponent } from './video-watched-overlays.component';

@Component({
  selector: 'app-video-card',
  standalone: true,
  imports: [RouterLink, VideoWatchedOverlaysComponent],
  template: `
    <article class="video-card" (mouseleave)="menuOpen.set(false)">
      <a class="thumb-wrap" [routerLink]="['/watch', video().id]">
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

        <app-video-watched-overlays [videoId]="video().id" />
      </a>

      <div class="meta-row">
        <a
          class="avatar-link"
          [routerLink]="['/channels', video().channelId]"
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
          <a class="title-link" [routerLink]="['/watch', video().id]">
            <h3 class="title">{{ video().title }}</h3>
          </a>
          <p class="sub">
            @if (video().channelId) {
              <a class="channel-link" [routerLink]="['/channels', video().channelId]">
                {{ video().channelTitle }}
              </a>
            } @else {
              <span>{{ video().channelTitle }}</span>
            }
          </p>
          <p class="sub stats">
            @if (video().viewCount > 0) {
              <span>{{ viewsLabel() }}</span>
            }
            @if (video().viewCount > 0 && timeLabel()) {
              <span> · </span>
            }
            @if (timeLabel()) {
              <span>{{ timeLabel() }}</span>
            }
            @if (isWatched()) {
              @if (video().viewCount > 0 || timeLabel()) {
                <span> · </span>
              }
              <span class="watched-status">Watched</span>
            } @else if (progressPct() > 0) {
              @if (video().viewCount > 0 || timeLabel()) {
                <span> · </span>
              }
              <span class="progress-status">{{ progressPct() }}% watched</span>
            }
          </p>
        </div>

        <div class="card-menu-wrap">
          <button
            type="button"
            class="more-btn"
            aria-label="Video actions"
            (click)="$event.stopPropagation(); menuOpen.set(!menuOpen())"
          >
            <span class="material-symbols-rounded">more_vert</span>
          </button>

          @if (menuOpen()) {
            <div class="card-menu" (click)="$event.stopPropagation()">
              <button type="button" class="card-menu-item" (click)="addToQueue()">
                <span class="material-symbols-rounded">queue_music</span>
                Add to queue
              </button>
              <button type="button" class="card-menu-item" (click)="toggleWatchLater()">
                <span class="material-symbols-rounded">
                  {{ isSaved() ? 'bookmark_remove' : 'watch_later' }}
                </span>
                {{ isSaved() ? 'Remove from Watch Later' : 'Save to Watch Later' }}
              </button>
              <button type="button" class="card-menu-item" (click)="toggleWatched()">
                <span class="material-symbols-rounded">
                  {{ isWatched() ? 'visibility_off' : 'check_circle' }}
                </span>
                {{ isWatched() ? 'Mark as unwatched' : 'Mark as watched' }}
              </button>
              <button type="button" class="card-menu-item" (click)="share()">
                <span class="material-symbols-rounded">share</span>
                Share
              </button>
              @if (video().channelId) {
                <button type="button" class="card-menu-item" (click)="goToChannel()">
                  <span class="material-symbols-rounded">tv</span>
                  Go to channel
                </button>
              }
            </div>
          }
        </div>
      </div>
    </article>
  `,
  styles: [
    `
      .video-card {
        display: flex;
        flex-direction: column;
        gap: 10px;
        position: relative;
      }

      .thumb-wrap {
        position: relative;
        width: 100%;
        aspect-ratio: 16 / 9;
        border-radius: var(--radius-md);
        overflow: hidden;
        background-color: var(--surface-variant);
        display: block;
      }

      .thumb {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
        transition: transform 220ms ease;
      }

      .video-card:hover .thumb {
        transform: scale(1.03);
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

      .watched-badge {
        left: 8px;
        top: 8px;
        right: auto;
        bottom: auto;
        background-color: rgba(0, 0, 0, 0.82);
        color: #ffffff;
      }

      .watched-badge .badge-icon {
        color: var(--accent);
      }

      .badge-icon {
        font-size: 13px;
      }

      .meta-row {
        display: flex;
        gap: 10px;
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

      .title-link {
        display: block;
      }

      .title {
        margin: 0 0 3px;
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
        font-size: 12px;
        color: var(--on-surface-muted);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .channel-link:hover {
        color: var(--on-surface);
      }

      .watched-status {
        color: var(--accent);
        font-weight: 600;
      }

      .progress-status {
        color: var(--on-surface-muted);
        font-weight: 500;
      }

      .card-menu-wrap {
        position: relative;
        flex-shrink: 0;
      }

      .more-btn {
        width: 28px;
        height: 28px;
        border-radius: var(--radius-pill);
        display: grid;
        place-items: center;
        color: var(--on-surface-muted);
        opacity: 0.75;
      }

      .more-btn:hover {
        background-color: var(--surface-variant);
        color: var(--on-surface);
        opacity: 1;
      }

      .more-btn .material-symbols-rounded {
        font-size: 18px;
      }

      .card-menu {
        position: absolute;
        right: 0;
        top: 32px;
        min-width: 200px;
        background-color: var(--surface-elevated);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-md);
        padding: 6px;
        box-shadow: 0 8px 24px rgba(0, 0, 0, 0.25);
        z-index: 40;
        display: flex;
        flex-direction: column;
        gap: 2px;
      }

      .card-menu-item {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 8px 10px;
        border-radius: var(--radius-sm);
        font-size: 13px;
        text-align: left;
      }

      .card-menu-item:hover {
        background-color: var(--surface-variant);
      }

      .card-menu-item .material-symbols-rounded {
        font-size: 18px;
        color: var(--on-surface-muted);
      }
    `,
  ],
})
export class VideoCardComponent {
  readonly video = input.required<Video>();
  private readonly library = inject(VideoLibraryService);
  private readonly router = inject(Router);

  readonly menuOpen = signal<boolean>(false);
  readonly isSaved = computed(() => this.library.isWatchLater(this.video().id));
  readonly watchStatus = computed(() => this.library.watchStatus(this.video().id));
  readonly isWatched = computed(() => this.watchStatus() === 'watched');
  readonly progressPct = computed(() =>
    Math.round(this.library.progressFraction(this.video().id) * 100),
  );

  viewsLabel(): string {
    return formatViewCount(this.video().viewCount);
  }

  timeLabel(): string {
    return formatTimeAgo(this.video().publishedAt);
  }

  addToQueue(): void {
    this.library.addToQueue(this.video());
    this.menuOpen.set(false);
  }

  toggleWatchLater(): void {
    this.library.toggleWatchLater(this.video());
    this.menuOpen.set(false);
  }

  toggleWatched(): void {
    const v = this.video();
    if (this.isWatched()) {
      this.library.markUnwatched(v.id);
    } else {
      this.library.markWatched(v);
    }
    this.menuOpen.set(false);
  }

  share(): void {
    this.menuOpen.set(false);
    const v = this.video();
    const url = `${window.location.origin}/watch/${v.id}`;
    if (navigator.share) {
      void navigator.share({ title: v.title, url });
    } else if (navigator.clipboard) {
      void navigator.clipboard.writeText(url);
    }
  }

  goToChannel(): void {
    this.menuOpen.set(false);
    const chId = this.video().channelId;
    if (chId) {
      void this.router.navigate(['/channels', chId]);
    }
  }
}
