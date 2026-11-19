import { Component, inject } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { VideoCardComponent } from '../../../shared/ui/video-card.component';
import { VideoLibraryService } from '../services/video-library.service';

@Component({
  selector: 'app-watch-later-page',
  standalone: true,
  imports: [RouterLink, VideoCardComponent],
  template: `
    <div class="library-page max-width-box">
      <header class="page-head">
        <div>
          <h1 class="font-display">Watch Later</h1>
          <p class="sub">{{ library.watchLater().length }} saved videos</p>
        </div>
        @if (library.watchLater().length > 0) {
          <button type="button" class="pill-chip active" (click)="playAll()">
            <span class="material-symbols-rounded btn-icon">play_arrow</span>
            Play All
          </button>
        }
      </header>

      @if (library.watchLater().length === 0) {
        <div class="state-card">
          <span class="material-symbols-rounded state-icon">watch_later</span>
          <h2>No saved videos</h2>
          <p class="muted">Save sermons or videos to Watch Later from any card or watch page.</p>
          <a class="pill-chip active" routerLink="/feed">Browse Videos</a>
        </div>
      } @else {
        <div class="video-grid">
          @for (video of library.watchLater(); track video.id) {
            <div class="saved-item">
              <app-video-card [video]="video" />
              <button
                type="button"
                class="remove-link"
                (click)="library.removeFromWatchLater(video.id)"
              >
                Remove from Watch Later
              </button>
            </div>
          }
        </div>
      }
    </div>
  `,
  styles: [
    `
      .library-page {
        padding-top: 16px;
        padding-bottom: 40px;
      }

      .page-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        margin-bottom: 18px;
      }

      .page-head h1 {
        margin: 0;
        font-size: 22px;
        font-weight: 700;
      }

      .sub,
      .muted {
        margin: 2px 0 0;
        font-size: 13px;
        color: var(--on-surface-muted);
      }

      .btn-icon {
        font-size: 18px;
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

      .saved-item {
        display: flex;
        flex-direction: column;
        gap: 6px;
      }

      .remove-link {
        align-self: flex-start;
        font-size: 12px;
        color: var(--on-surface-muted);
      }

      .remove-link:hover {
        color: var(--error);
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
export class WatchLaterComponent {
  readonly library = inject(VideoLibraryService);
  private readonly router = inject(Router);

  playAll(): void {
    const list = this.library.watchLater();
    if (list.length === 0) return;
    this.library.clearQueue();
    for (const v of list.slice(1)) {
      this.library.addToQueue(v);
    }
    void this.router.navigate(['/watch', list[0].id]);
  }
}
