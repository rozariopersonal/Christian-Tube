import { Component, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { VideoCardComponent } from '../../../shared/ui/video-card.component';
import { VideoLibraryService } from '../services/video-library.service';

@Component({
  selector: 'app-history-page',
  standalone: true,
  imports: [RouterLink, VideoCardComponent],
  template: `
    <div class="library-page max-width-box">
      <header class="page-head">
        <div>
          <h1 class="font-display">Watch History</h1>
          <p class="sub">{{ library.history().length }} videos watched</p>
        </div>
        @if (library.history().length > 0) {
          <button
            type="button"
            class="pill-chip"
            (click)="library.clearHistory()"
          >
            <span class="material-symbols-rounded btn-icon">delete_sweep</span>
            Clear History
          </button>
        }
      </header>

      @if (library.history().length === 0) {
        <div class="state-card">
          <span class="material-symbols-rounded state-icon">history</span>
          <h2>Your watch history is empty</h2>
          <p class="muted">Videos you watch will appear here with resume progress.</p>
          <a class="pill-chip active" routerLink="/feed">Explore Videos</a>
        </div>
      } @else {
        <div class="video-grid">
          @for (entry of library.history(); track entry.video.id) {
            <div class="history-item">
              <app-video-card [video]="entry.video" />
              <button
                type="button"
                class="remove-link"
                (click)="library.removeFromHistory(entry.video.id)"
              >
                Remove from history
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

      .history-item {
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
export class HistoryComponent {
  readonly library = inject(VideoLibraryService);
}
