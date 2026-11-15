import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { AudioLibraryService } from '../services/audio-library.service';
import { AudioPlayerService } from '../services/audio-player.service';

@Component({
  selector: 'app-audio-library',
  standalone: true,
  imports: [FormsModule, RouterLink],
  template: `
    <div class="audio-page max-width-box">
      <header class="page-head">
        <h1 class="font-display">Audio Library</h1>
        <button
          type="button"
          class="icon-btn"
          title="Refresh Library"
          (click)="library.loadCatalog(true)"
        >
          <span class="material-symbols-rounded">refresh</span>
        </button>
      </header>

      <div class="controls">
        <div class="search-box">
          <span class="material-symbols-rounded">search</span>
          <input
            type="search"
            placeholder="Search series or speakers..."
            [ngModel]="search()"
            (ngModelChange)="search.set($event)"
          />
        </div>
        <select
          class="lang-select"
          [ngModel]="selectedLang()"
          (ngModelChange)="selectedLang.set($event)"
          aria-label="Language"
        >
          <option value="all">All Languages</option>
          @for (lang of languages(); track lang) {
            <option [value]="lang">{{ lang.toUpperCase() }}</option>
          }
        </select>
      </div>

      <div class="mode-strip">
        @for (m of ['featured', 'category', 'speaker', 'az']; track m) {
          <button
            type="button"
            class="pill-chip"
            [class.active]="mode() === m"
            (click)="mode.set($any(m))"
          >
            {{ modeLabel(m) }}
          </button>
        }
      </div>

      @if (player.currentTrack(); as last) {
        <div class="continue-card" (click)="player.togglePlay()">
          <span class="material-symbols-rounded filled continue-icon">
            {{ player.isPlaying() ? 'pause_circle' : 'play_circle' }}
          </span>
          <div class="continue-meta">
            <span class="continue-label">Continue Listening</span>
            <strong>{{ last.title }}</strong>
            <span class="muted">{{ last.speaker }} · {{ last.seriesTitle }}</span>
          </div>
        </div>
      }

      @if (library.loading()) {
        <p class="status-msg">Loading audio series...</p>
      } @else if (library.error()) {
        <div class="status-msg">
          <p>{{ library.error() }}</p>
          <button type="button" class="pill-chip active" (click)="library.loadCatalog(true)">
            Retry
          </button>
        </div>
      } @else {
        <div class="series-grid">
          @for (s of displayedSeries(); track s.id) {
            <a class="series-card" [routerLink]="['/audio/series', s.id]">
              <div class="cover-wrap">
                @if (s.coverUrl) {
                  <img class="cover" [src]="s.coverUrl" [alt]="s.title" loading="lazy" />
                } @else {
                  <div class="cover fallback">
                    <span class="material-symbols-rounded">headphones</span>
                  </div>
                }
              </div>
              <div class="series-meta">
                <h3 class="series-title">{{ s.title }}</h3>
                <p class="series-sub">{{ s.speaker }} · {{ s.trackCount }} tracks</p>
              </div>
            </a>
          }
        </div>
      }
    </div>
  `,
  styles: [
    `
      .audio-page {
        padding-top: 16px;
        padding-bottom: 84px;
      }

      .page-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        margin-bottom: 12px;
      }

      .page-head h1 {
        margin: 0;
        font-size: 22px;
        font-weight: 700;
      }

      .controls {
        display: flex;
        gap: 10px;
        flex-wrap: wrap;
        margin-bottom: 12px;
      }

      .search-box {
        flex: 1;
        min-width: 200px;
        display: flex;
        align-items: center;
        gap: 8px;
        height: 42px;
        padding: 0 12px;
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-md);
      }

      .search-box input {
        flex: 1;
        border: none;
        outline: none;
        background: transparent;
      }

      .lang-select {
        height: 42px;
        padding: 0 12px;
        border-radius: var(--radius-md);
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
      }

      .mode-strip {
        display: flex;
        gap: 8px;
        overflow-x: auto;
        padding-bottom: 12px;
        margin-bottom: 12px;
      }

      .continue-card {
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 14px;
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-md);
        margin-bottom: 18px;
        cursor: pointer;
      }

      .continue-icon {
        font-size: 40px;
        color: var(--accent);
      }

      .continue-meta {
        display: flex;
        flex-direction: column;
        min-width: 0;
      }

      .continue-label {
        font-size: 11px;
        font-weight: 700;
        text-transform: uppercase;
        color: var(--accent);
      }

      .muted {
        font-size: 12px;
        color: var(--on-surface-muted);
      }

      .series-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(170px, 1fr));
        gap: 18px 14px;
      }

      .series-card {
        display: flex;
        flex-direction: column;
        gap: 8px;
      }

      .cover-wrap {
        aspect-ratio: 1 / 1;
        border-radius: var(--radius-md);
        overflow: hidden;
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
      }

      .cover {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }

      .cover.fallback {
        display: grid;
        place-items: center;
        color: var(--accent);
      }

      .series-title {
        margin: 0;
        font-size: 14px;
        font-weight: 600;
        line-height: 1.3;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }

      .series-sub {
        margin: 2px 0 0;
        font-size: 12px;
        color: var(--on-surface-muted);
      }

      .status-msg {
        text-align: center;
        padding: 36px 0;
        color: var(--on-surface-muted);
      }
    `,
  ],
})
export class AudioLibraryComponent implements OnInit {
  readonly library = inject(AudioLibraryService);
  readonly player = inject(AudioPlayerService);

  readonly search = signal<string>('');
  readonly selectedLang = signal<string>('all');
  readonly mode = signal<'featured' | 'category' | 'speaker' | 'az'>('featured');

  readonly languages = computed(() => {
    const set = new Set<string>();
    for (const s of this.library.seriesList()) {
      if (s.language) set.add(s.language);
    }
    return [...set].sort();
  });

  readonly displayedSeries = computed(() => {
    const q = this.search().trim().toLowerCase();
    const lang = this.selectedLang();
    const list = this.library.seriesList().filter((s) => {
      if (lang !== 'all' && s.language !== lang) return false;
      if (
        q &&
        !s.title.toLowerCase().includes(q) &&
        !s.speaker.toLowerCase().includes(q) &&
        !s.category.toLowerCase().includes(q)
      ) {
        return false;
      }
      return true;
    });
    if (this.mode() === 'az') {
      return [...list].sort((a, b) => a.title.localeCompare(b.title));
    }
    if (this.mode() === 'speaker') {
      return [...list].sort((a, b) => a.speaker.localeCompare(b.speaker));
    }
    if (this.mode() === 'category') {
      return [...list].sort((a, b) => a.category.localeCompare(b.category));
    }
    return list;
  });

  ngOnInit(): void {
    void this.library.loadCatalog();
  }

  modeLabel(m: string): string {
    switch (m) {
      case 'category':
        return 'By Category';
      case 'speaker':
        return 'By Speaker';
      case 'az':
        return 'A–Z';
      default:
        return 'Featured';
    }
  }
}
