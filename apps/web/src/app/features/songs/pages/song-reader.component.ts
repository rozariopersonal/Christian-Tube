import {
  ChangeDetectionStrategy,
  Component,
  OnInit,
  computed,
  inject,
  signal,
} from '@angular/core';
import { ActivatedRoute } from '@angular/router';
import { ReaderAppearanceService } from '../../../core/services/reader-appearance.service';
import { Song, songHasTransliteration } from '../models/song.model';
import { SongsService } from '../services/songs.service';

@Component({
  selector: 'app-song-reader',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="max-width-box song-reader-page">
      @if (loading()) {
        <div class="state-card">
          <span class="material-symbols-rounded state-ico">music_note</span>
          <p class="muted">Loading song lyrics...</p>
        </div>
      } @else if (!song()) {
        <div class="state-card">
          <span class="material-symbols-rounded state-ico">music_off</span>
          <h3>Song not found</h3>
          <p class="muted">This song could not be loaded.</p>
        </div>
      } @else {
        <header class="song-header">
          <div class="song-title-block">
            <h1 class="font-display">{{ song()!.title }}</h1>
            @if (song()!.titleRoman) {
              <p class="roman-title">{{ song()!.titleRoman }}</p>
            }
            @if (song()!.author || song()!.collection) {
              <p class="meta-line">
                {{ song()!.collection || '' }}
                @if (song()!.collection && song()!.author) {
                  ·
                }
                {{ song()!.author || '' }}
              </p>
            }
          </div>

          <div class="toolbar-pills">
            @if (hasRoman()) {
              <button
                type="button"
                class="pill-chip"
                [class.active]="showRoman()"
                (click)="showRoman.set(!showRoman())"
              >
                <span class="material-symbols-rounded">translate</span>
                <span>{{ showRoman() ? 'Native' : 'Romanized' }}</span>
              </button>
            }
            <div class="font-stepper">
              <button
                type="button"
                class="step-btn"
                aria-label="Decrease font size"
                (click)="appearance.stepFontSize(-1)"
              >
                A-
              </button>
              <span class="font-size-val">{{ appearance.fontSize() }}px</span>
              <button
                type="button"
                class="step-btn"
                aria-label="Increase font size"
                (click)="appearance.stepFontSize(1)"
              >
                A+
              </button>
            </div>
          </div>
        </header>

        <div class="verses-stack">
          @for (verse of activeVerses(); track $index) {
            <article class="verse-card">
              <span class="verse-num">{{ $index + 1 }}</span>
              <p
                class="verse-text"
                [style.fontSize.px]="appearance.fontSize()"
                [style.lineHeight]="appearance.lineHeight()"
              >
                {{ verse }}
              </p>
            </article>
          }
        </div>
      }
    </div>
  `,
  styles: [
    `
      .song-reader-page {
        padding-top: 16px;
        padding-bottom: 48px;
        display: flex;
        flex-direction: column;
        gap: 20px;
      }

      .song-header {
        display: flex;
        flex-wrap: wrap;
        align-items: flex-start;
        justify-content: space-between;
        gap: 12px;
        padding: 16px;
        border-radius: var(--radius-lg);
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
      }

      .song-title-block h1 {
        margin: 0;
        font-size: 20px;
        font-weight: 700;
      }

      .roman-title {
        margin: 4px 0 0;
        font-size: 14px;
        color: var(--on-surface-muted);
      }

      .meta-line {
        margin: 4px 0 0;
        font-size: 13px;
        color: var(--accent);
        font-weight: 500;
      }

      .toolbar-pills {
        display: flex;
        align-items: center;
        gap: 8px;
      }

      .font-stepper {
        display: inline-flex;
        align-items: center;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        overflow: hidden;
      }

      .step-btn {
        border: none;
        background: transparent;
        color: var(--on-surface);
        padding: 6px 10px;
        font-size: 13px;
        font-weight: 600;
        cursor: pointer;
      }

      .font-size-val {
        font-size: 12px;
        color: var(--on-surface-muted);
        padding: 0 4px;
      }

      .verses-stack {
        display: flex;
        flex-direction: column;
        gap: 12px;
      }

      .verse-card {
        display: flex;
        gap: 14px;
        padding: 16px;
        border-radius: var(--radius-lg);
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
      }

      .verse-num {
        width: 26px;
        height: 26px;
        border-radius: var(--radius-pill);
        background-color: var(--accent-soft);
        color: var(--accent);
        font-size: 12px;
        font-weight: 700;
        display: grid;
        place-items: center;
        flex-shrink: 0;
        margin-top: 2px;
      }

      .verse-text {
        margin: 0;
        white-space: pre-line;
        color: var(--on-surface);
      }

      .state-card {
        max-width: 420px;
        margin: 32px auto;
        padding: 24px;
        border-radius: var(--radius-lg);
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        text-align: center;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 8px;
      }

      .state-ico {
        font-size: 36px;
        color: var(--on-surface-muted);
      }

      .muted {
        margin: 0;
        font-size: 13px;
        color: var(--on-surface-muted);
      }
    `,
  ],
})
export class SongReaderComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly songsService = inject(SongsService);
  readonly appearance = inject(ReaderAppearanceService);

  readonly song = signal<Song | null>(null);
  readonly loading = signal(true);
  readonly showRoman = signal(false);

  readonly hasRoman = computed(() => {
    const s = this.song();
    return s ? songHasTransliteration(s) : false;
  });

  readonly activeVerses = computed(() => {
    const s = this.song();
    if (!s) return [];
    if (this.showRoman() && s.versesRoman.some((v) => v.trim().length > 0)) {
      return s.versesRoman;
    }
    return s.verses;
  });

  async ngOnInit(): Promise<void> {
    const id = this.route.snapshot.paramMap.get('id') ?? '';
    if (id) {
      const loaded = await this.songsService.getSong(id);
      this.song.set(loaded);
    }
    this.loading.set(false);
  }
}
