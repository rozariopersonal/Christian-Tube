import { ChangeDetectionStrategy, Component, computed, inject, input } from '@angular/core';
import { VideoLibraryService } from '../../features/videos/services/video-library.service';

@Component({
  selector: 'app-video-watched-overlays',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (watched()) {
      <span class="watched-badge">
        <span class="material-symbols-rounded watched-icon">check_circle</span>
        Watched
      </span>
    }
    @if (progressPct() > 0) {
      <div class="progress-track" aria-hidden="true">
        <div class="progress-fill" [style.width.%]="progressPct()"></div>
      </div>
    }
  `,
  styles: [
    `
      :host {
        position: absolute;
        inset: 0;
        pointer-events: none;
      }

      .watched-badge {
        position: absolute;
        top: 8px;
        left: 8px;
        display: inline-flex;
        align-items: center;
        gap: 4px;
        padding: 2px 7px;
        border-radius: 6px;
        background-color: rgba(0, 0, 0, 0.82);
        color: #ffffff;
        font-size: 11px;
        font-weight: 700;
        line-height: 1.3;
      }

      .watched-icon {
        font-size: 13px;
        color: var(--accent);
      }

      .progress-track {
        position: absolute;
        left: 0;
        right: 0;
        bottom: 0;
        height: 5px;
        background-color: rgba(255, 255, 255, 0.28);
      }

      .progress-fill {
        height: 100%;
        background-color: var(--accent);
      }
    `,
  ],
})
export class VideoWatchedOverlaysComponent {
  readonly videoId = input.required<string>();
  private readonly library = inject(VideoLibraryService);

  readonly watched = computed(() => this.library.isWatched(this.videoId()));
  readonly progressPct = computed(() =>
    Math.round(this.library.progressFraction(this.videoId()) * 100),
  );
}
