import {
  ChangeDetectionStrategy,
  Component,
  OnDestroy,
  OnInit,
  computed,
  inject,
  signal,
} from '@angular/core';
import { RouterLink } from '@angular/router';
import { ScreenClassService } from '../../../core/layout/screen-class.service';
import { HeaderSearchService } from '../../../core/services/header-search.service';
import { SUPPORTED_LANGUAGES } from '../../../shared/ui/language-meta';
import { SearchInputComponent } from '../../../shared/ui/search-input.component';
import { SongsService } from '../services/songs.service';

@Component({
  selector: 'app-songs-library',
  standalone: true,
  imports: [RouterLink, SearchInputComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="max-width-box songs-page">
      <header class="page-head">
        <div>
          <h1 class="font-display">Songs & Hymns</h1>
          <p class="subtitle">Browse worship lyrics across languages and collections</p>
        </div>
        @if (languages().length > 1) {
          <div class="lang-chips" role="tablist" aria-label="Filter by language">
            <button
              type="button"
              class="pill-chip"
              [class.active]="selectedLang() === 'all'"
              (click)="selectedLang.set('all')"
            >
              All ({{ songsService.songs().length }})
            </button>
            @for (lang of languages(); track lang) {
              <button
                type="button"
                class="pill-chip"
                [class.active]="selectedLang() === lang"
                (click)="selectedLang.set(lang)"
              >
                {{ langLabel(lang) }}
              </button>
            }
          </div>
        }
      </header>

      @if (screen.isCompact()) {
        <div class="compact-search-wrap">
          <app-search-input
            placeholder="Search songs, lyrics, authors..."
            [value]="query()"
            (valueChange)="query.set($event)"
          />
        </div>
      }

      @if (songsService.loading() && songsService.songs().length === 0) {
        <div class="songs-grid">
          @for (_ of skeletons; track $index) {
            <div class="song-card skeleton-card" aria-hidden="true">
              <div class="sk-icon"></div>
              <div class="sk-lines">
                <div class="sk-line wide"></div>
                <div class="sk-line narrow"></div>
              </div>
            </div>
          }
        </div>
      } @else if (songsService.error()) {
        <div class="state-card">
          <span class="material-symbols-rounded state-ico">error_outline</span>
          <h3>Unable to load songs</h3>
          <p class="muted">{{ songsService.error() }}</p>
          <button type="button" class="pill-chip active" (click)="songsService.loadCatalog(true)">
            Retry
          </button>
        </div>
      } @else if (filteredSongs().length === 0) {
        <div class="state-card">
          <span class="material-symbols-rounded state-ico">music_off</span>
          <h3>No matching songs</h3>
          <p class="muted">Try adjusting your search or language filter.</p>
        </div>
      } @else {
        <div class="songs-grid">
          @for (song of visibleSongs(); track song.id) {
            <a class="song-card" [routerLink]="['/song', song.id]">
              <div class="song-icon-box">
                <span class="material-symbols-rounded">music_note</span>
              </div>
              <div class="song-meta">
                <strong class="song-title">{{ song.title }}</strong>
                @if (song.titleRoman) {
                  <span class="song-roman">{{ song.titleRoman }}</span>
                }
                <div class="song-sub">
                  <span>{{ langLabel(song.language) }}</span>
                  @if (song.collection || song.author) {
                    <span>· {{ song.collection || song.author }}</span>
                  }
                </div>
              </div>
              <span class="material-symbols-rounded chevron">chevron_right</span>
            </a>
          }
        </div>

        @if (filteredSongs().length > visibleLimit()) {
          <div class="load-more-wrap">
            <button
              type="button"
              class="pill-chip"
              (click)="visibleLimit.set(visibleLimit() + 60)"
            >
              Show more ({{ filteredSongs().length - visibleLimit() }} remaining)
            </button>
          </div>
        }
      }
    </div>
  `,
  styles: [
    `
      .songs-page {
        padding-top: 16px;
        padding-bottom: 32px;
        display: flex;
        flex-direction: column;
        gap: 16px;
      }

      .page-head {
        display: flex;
        flex-wrap: wrap;
        align-items: flex-end;
        justify-content: space-between;
        gap: 12px;
      }

      .page-head h1 {
        margin: 0;
        font-size: 20px;
        font-weight: 700;
        letter-spacing: -0.3px;
      }

      .subtitle {
        margin: 4px 0 0;
        font-size: 13px;
        color: var(--on-surface-muted);
      }

      .lang-chips {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
      }

      .compact-search-wrap {
        width: 100%;
      }

      .songs-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
        gap: 12px;
      }

      .song-card {
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 12px 14px;
        border-radius: var(--radius-md);
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        color: var(--on-surface);
        text-decoration: none;
        transition: border-color 0.15s ease, background-color 0.15s ease;
      }

      .song-card:hover {
        border-color: var(--accent);
        background-color: var(--surface-elevated);
      }

      .song-icon-box {
        width: 44px;
        height: 44px;
        border-radius: 11px;
        background-color: var(--accent-soft);
        color: var(--accent);
        display: grid;
        place-items: center;
        flex-shrink: 0;
      }

      .song-meta {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 2px;
      }

      .song-title {
        font-size: 14px;
        font-weight: 600;
        line-height: 1.3;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .song-roman {
        font-size: 12px;
        color: var(--on-surface-muted);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .song-sub {
        display: flex;
        align-items: center;
        gap: 4px;
        font-size: 12px;
        color: var(--on-surface-muted);
      }

      .chevron {
        color: var(--on-surface-muted);
        font-size: 20px;
        flex-shrink: 0;
      }

      .state-card {
        max-width: 420px;
        margin: 24px auto;
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

      .state-card h3 {
        margin: 0;
        font-size: 16px;
      }

      .muted {
        margin: 0;
        font-size: 13px;
        color: var(--on-surface-muted);
      }

      .load-more-wrap {
        display: flex;
        justify-content: center;
        padding-top: 8px;
      }

      .skeleton-card {
        pointer-events: none;
      }

      .sk-icon {
        width: 44px;
        height: 44px;
        border-radius: 11px;
        background-color: var(--surface-variant);
      }

      .sk-lines {
        flex: 1;
        display: flex;
        flex-direction: column;
        gap: 6px;
      }

      .sk-line {
        height: 12px;
        border-radius: 6px;
        background-color: var(--surface-variant);
      }

      .sk-line.wide {
        width: 72%;
      }

      .sk-line.narrow {
        width: 44%;
      }
    `,
  ],
})
export class SongsLibraryComponent implements OnInit, OnDestroy {
  readonly songsService = inject(SongsService);
  readonly screen = inject(ScreenClassService);
  private readonly headerSearch = inject(HeaderSearchService);
  private unregisterSearch?: () => void;

  readonly query = signal('');
  readonly selectedLang = signal('all');
  readonly visibleLimit = signal(60);
  readonly skeletons = Array.from({ length: 8 });

  readonly languages = computed(() => {
    const set = new Set<string>();
    for (const s of this.songsService.songs()) {
      if (s.language) set.add(s.language);
    }
    return Array.from(set).sort();
  });

  readonly filteredSongs = computed(() => {
    const lang = this.selectedLang();
    const q = this.query().trim().toLowerCase();
    return this.songsService.songs().filter((song) => {
      if (lang !== 'all' && song.language !== lang) return false;
      if (!q) return true;
      return (
        song.title.toLowerCase().includes(q) ||
        (song.titleRoman ?? '').toLowerCase().includes(q) ||
        (song.author ?? '').toLowerCase().includes(q) ||
        (song.collection ?? '').toLowerCase().includes(q) ||
        song.verses.some((v) => v.toLowerCase().includes(q)) ||
        song.versesRoman.some((v) => v.toLowerCase().includes(q))
      );
    });
  });

  readonly visibleSongs = computed(() =>
    this.filteredSongs().slice(0, this.visibleLimit()),
  );

  ngOnInit(): void {
    void this.songsService.loadCatalog();
    this.unregisterSearch = this.headerSearch.register({
      placeholder: 'Search songs, lyrics, authors...',
      onChange: (q) => this.query.set(q),
    });
  }

  ngOnDestroy(): void {
    this.unregisterSearch?.();
  }

  langLabel(code: string): string {
    const clean = code.trim().toLowerCase();
    return SUPPORTED_LANGUAGES[clean]?.englishName ?? code.toUpperCase();
  }
}
