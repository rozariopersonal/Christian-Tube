import { Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { formatDuration } from '../models/audio.model';
import { AudioPlayerService } from '../services/audio-player.service';

@Component({
  selector: 'app-mini-player',
  standalone: true,
  imports: [FormsModule],
  template: `
    @if (player.currentTrack(); as track) {
      <div class="mini-player" (click)="player.expanded.set(true)">
        <div class="progress-line" [style.width.%]="player.progressPercent()"></div>
        <div class="mini-inner">
          @if (track.thumbnailUrl || track.coverUrl) {
            <img
              class="mini-art"
              [src]="track.thumbnailUrl || track.coverUrl"
              [alt]="track.title"
            />
          } @else {
            <span class="mini-art fallback">
              <span class="material-symbols-rounded">headphones</span>
            </span>
          }

          <div class="mini-meta">
            <span class="mini-title">{{ track.title }}</span>
            <span class="mini-sub">{{ track.speaker }} · {{ track.seriesTitle }}</span>
          </div>

          <button
            type="button"
            class="icon-btn play-btn"
            aria-label="Play or pause"
            (click)="$event.stopPropagation(); player.togglePlay()"
          >
            <span class="material-symbols-rounded filled">
              {{ player.isPlaying() ? 'pause' : 'play_arrow' }}
            </span>
          </button>
        </div>
      </div>

      @if (player.expanded()) {
        <div class="modal-backdrop" (click)="player.expanded.set(false)">
          <div class="modal-panel full-player" (click)="$event.stopPropagation()">
            <div class="fp-head">
              <span class="fp-series">{{ track.seriesTitle }}</span>
              <button type="button" class="icon-btn" (click)="player.expanded.set(false)">
                <span class="material-symbols-rounded">keyboard_arrow_down</span>
              </button>
            </div>

            @if (track.thumbnailUrl || track.coverUrl) {
              <img
                class="fp-art"
                [src]="track.thumbnailUrl || track.coverUrl"
                [alt]="track.title"
              />
            }

            <div class="fp-info">
              <h2 class="font-display">{{ track.title }}</h2>
              <p class="muted">{{ track.speaker }}</p>
            </div>

            <div class="fp-seek">
              <input
                type="range"
                min="0"
                [max]="player.duration() || track.durationSeconds || 100"
                [ngModel]="player.position()"
                (ngModelChange)="player.seekTo($event)"
              />
              <div class="time-row">
                <span>{{ formatTime(player.position()) }}</span>
                <span>{{ formatTime(player.duration() || track.durationSeconds) }}</span>
              </div>
            </div>

            <div class="fp-controls">
              <button type="button" class="icon-btn" (click)="player.previous()">
                <span class="material-symbols-rounded">skip_previous</span>
              </button>
              <button type="button" class="fp-play-btn" (click)="player.togglePlay()">
                <span class="material-symbols-rounded filled">
                  {{ player.isPlaying() ? 'pause' : 'play_arrow' }}
                </span>
              </button>
              <button type="button" class="icon-btn" (click)="player.next()">
                <span class="material-symbols-rounded">skip_next</span>
              </button>
            </div>

            <div class="rate-row">
              @for (r of [1, 1.25, 1.5, 2]; track r) {
                <button
                  type="button"
                  class="pill-chip"
                  [class.active]="player.playbackRate() === r"
                  (click)="player.setRate(r)"
                >
                  {{ r }}x
                </button>
              }
            </div>
          </div>
        </div>
      }
    }
  `,
  styles: [
    `
      .mini-player {
        position: fixed;
        left: 0;
        right: 0;
        bottom: calc(var(--shell-bottom-height) + env(safe-area-inset-bottom, 0px));
        height: 60px;
        background-color: var(--surface-elevated);
        border-top: 1px solid var(--surface-border);
        z-index: 48;
        cursor: pointer;
        display: flex;
        flex-direction: column;
      }

      @media (min-width: 600px) {
        .mini-player {
          left: 0;
          bottom: 0;
        }
      }

      .progress-line {
        height: 2px;
        background-color: var(--accent);
        transition: width 150ms linear;
      }

      .mini-inner {
        flex: 1;
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 0 14px;
      }

      .mini-art {
        width: 40px;
        height: 40px;
        border-radius: var(--radius-sm);
        object-fit: cover;
        flex-shrink: 0;
      }

      .mini-art.fallback {
        display: grid;
        place-items: center;
        background-color: var(--accent-soft);
        color: var(--accent);
      }

      .mini-meta {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
      }

      .mini-title {
        font-size: 13px;
        font-weight: 600;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .mini-sub {
        font-size: 12px;
        color: var(--on-surface-muted);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .full-player {
        padding: 20px;
        gap: 16px;
        align-items: center;
        text-align: center;
      }

      .fp-head {
        width: 100%;
        display: flex;
        align-items: center;
        justify-content: space-between;
      }

      .fp-series {
        font-size: 13px;
        font-weight: 600;
        color: var(--on-surface-muted);
      }

      .fp-art {
        width: 200px;
        height: 200px;
        border-radius: var(--radius-lg);
        object-fit: cover;
      }

      .fp-info h2 {
        margin: 0 0 4px;
        font-size: 18px;
      }

      .muted {
        margin: 0;
        color: var(--on-surface-muted);
      }

      .fp-seek {
        width: 100%;
        display: flex;
        flex-direction: column;
        gap: 6px;
      }

      .fp-seek input {
        width: 100%;
      }

      .time-row {
        display: flex;
        justify-content: space-between;
        font-size: 12px;
        color: var(--on-surface-muted);
      }

      .fp-controls {
        display: flex;
        align-items: center;
        gap: 20px;
      }

      .fp-play-btn {
        width: 56px;
        height: 56px;
        border-radius: var(--radius-pill);
        background-color: var(--accent);
        color: var(--on-accent);
        display: grid;
        place-items: center;
      }

      .rate-row {
        display: flex;
        gap: 8px;
      }
    `,
  ],
})
export class MiniPlayerComponent {
  readonly player = inject(AudioPlayerService);
  formatTime = formatDuration;
}
