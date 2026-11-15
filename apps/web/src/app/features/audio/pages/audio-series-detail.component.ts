import { Component, OnInit, inject, signal } from '@angular/core';
import { ActivatedRoute } from '@angular/router';
import { AudioSeries, AudioTrack, formatDuration } from '../models/audio.model';
import { AudioLibraryService } from '../services/audio-library.service';
import { AudioPlayerService } from '../services/audio-player.service';

@Component({
  selector: 'app-audio-series-detail',
  standalone: true,
  template: `
    <div class="series-detail max-width-box">
      @if (loading()) {
        <p class="status-msg">Loading series...</p>
      } @else if (!series()) {
        <p class="status-msg">Audio series not found.</p>
      } @else {
        <header class="series-hero">
          @if (series()!.coverUrl) {
            <img class="hero-cover" [src]="series()!.coverUrl" [alt]="series()!.title" />
          }
          <div class="hero-meta">
            <h1 class="font-display">{{ series()!.title }}</h1>
            <p class="speaker">{{ series()!.speaker }} · {{ series()!.tracks.length }} tracks</p>
            @if (series()!.description) {
              <p class="desc">{{ series()!.description }}</p>
            }
            @if (series()!.tracks.length > 0) {
              <button
                type="button"
                class="pill-chip active"
                (click)="playTrack(series()!.tracks[0])"
              >
                <span class="material-symbols-rounded filled">play_arrow</span>
                Play All
              </button>
            }
          </div>
        </header>

        <div class="tracks-list">
          @for (track of series()!.tracks; track track.id; let i = $index) {
            <button
              type="button"
              class="track-row"
              [class.active]="player.currentTrack()?.id === track.id"
              (click)="playTrack(track)"
            >
              <span class="track-num">{{ i + 1 }}</span>
              <div class="track-info">
                <span class="track-title">{{ track.title }}</span>
                <span class="track-sub">{{ track.speaker }}</span>
              </div>
              <span class="track-dur">{{ formatTime(track.durationSeconds) }}</span>
              <span class="material-symbols-rounded filled play-icon">
                {{
                  player.currentTrack()?.id === track.id && player.isPlaying()
                    ? 'pause_circle'
                    : 'play_circle'
                }}
              </span>
            </button>
          }
        </div>
      }
    </div>
  `,
  styles: [
    `
      .series-detail {
        padding-top: 16px;
        padding-bottom: 90px;
      }

      .series-hero {
        display: flex;
        gap: 20px;
        flex-wrap: wrap;
        align-items: center;
        margin-bottom: 24px;
      }

      .hero-cover {
        width: 140px;
        height: 140px;
        border-radius: var(--radius-md);
        object-fit: cover;
        flex-shrink: 0;
      }

      .hero-meta {
        flex: 1;
        min-width: 220px;
        display: flex;
        flex-direction: column;
        align-items: flex-start;
        gap: 8px;
      }

      .hero-meta h1 {
        margin: 0;
        font-size: 22px;
      }

      .speaker {
        margin: 0;
        color: var(--on-surface-muted);
        font-size: 13px;
      }

      .desc {
        margin: 0;
        font-size: 13px;
        color: var(--on-surface-muted);
      }

      .tracks-list {
        display: flex;
        flex-direction: column;
        gap: 8px;
      }

      .track-row {
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 12px 14px;
        border-radius: var(--radius-md);
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        text-align: left;
      }

      .track-row.active {
        border-color: var(--accent);
        background-color: var(--accent-soft);
      }

      .track-num {
        width: 24px;
        font-size: 13px;
        color: var(--on-surface-muted);
        text-align: center;
      }

      .track-info {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
      }

      .track-title {
        font-size: 14px;
        font-weight: 600;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .track-sub {
        font-size: 12px;
        color: var(--on-surface-muted);
      }

      .track-dur {
        font-size: 12px;
        color: var(--on-surface-muted);
      }

      .play-icon {
        color: var(--accent);
      }

      .status-msg {
        text-align: center;
        padding: 40px 0;
        color: var(--on-surface-muted);
      }
    `,
  ],
})
export class AudioSeriesDetailComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly library = inject(AudioLibraryService);
  readonly player = inject(AudioPlayerService);

  readonly series = signal<AudioSeries | null>(null);
  readonly loading = signal<boolean>(true);
  formatTime = formatDuration;

  ngOnInit(): void {
    this.route.paramMap.subscribe((params) => {
      const id = params.get('id');
      if (id) void this.load(id);
    });
  }

  async load(id: string): Promise<void> {
    this.loading.set(true);
    this.series.set(await this.library.fetchSeries(id));
    this.loading.set(false);
  }

  playTrack(track: AudioTrack): void {
    const tracks = this.series()?.tracks ?? [];
    this.player.playTrack(track, tracks);
  }
}
