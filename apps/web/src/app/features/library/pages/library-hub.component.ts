import {
  ChangeDetectionStrategy,
  Component,
  OnInit,
  computed,
  inject,
  signal,
} from '@angular/core';
import { RouterLink } from '@angular/router';
import { SUPPORTED_LANGUAGES } from '../../../shared/ui/language-meta';
import { ArticlesService } from '../../articles/services/articles.service';
import { BookCardComponent } from '../../books/components/book-card.component';
import { BooksService } from '../../books/services/books.service';
import { SongsService } from '../../songs/services/songs.service';

@Component({
  selector: 'app-library-hub',
  standalone: true,
  imports: [RouterLink, BookCardComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="max-width-box library-page">
      <header class="page-head">
        <div>
          <h1 class="font-display">Library</h1>
          <p class="subtitle">Books • Songs • Articles</p>
        </div>
        <button
          type="button"
          class="icon-btn"
          aria-label="Refresh library"
          title="Refresh library"
          (click)="refresh()"
        >
          <span class="material-symbols-rounded">refresh</span>
        </button>
      </header>

      @if (availableLanguages().length > 1) {
        <div class="lang-strip" role="tablist" aria-label="Library languages">
          <button
            type="button"
            class="pill-chip"
            [class.active]="selectedLang() === 'all'"
            (click)="selectedLang.set('all')"
          >
            All
          </button>
          @for (code of availableLanguages(); track code) {
            <button
              type="button"
              class="pill-chip"
              [class.active]="selectedLang() === code"
              (click)="selectedLang.set(code)"
            >
              {{ langName(code) }}
            </button>
          }
        </div>
      }

      @if (!hasAnyContent() && isLoading()) {
        <div class="shelf-skeletons" aria-hidden="true">
          @for (_ of [1, 2, 3]; track $index) {
            <div class="sk-row">
              <div class="sk-title"></div>
              <div class="sk-cards">
                @for (__ of [1, 2, 3, 4]; track $index) {
                  <div class="sk-card"></div>
                }
              </div>
            </div>
          }
        </div>
      } @else if (!hasAnyContent()) {
        <div class="state-card">
          <span class="material-symbols-rounded state-ico">search_off</span>
          <p class="muted">No library content found for the selected language.</p>
        </div>
      } @else {
        @if (shelfBooks().length > 0) {
          <section class="shelf-section">
            <div class="section-head">
              <div class="section-title">
                <span class="material-symbols-rounded sec-ico">collections_bookmark</span>
                <h2>Books</h2>
              </div>
              <a class="see-all-link" routerLink="/books">
                <span>See all</span>
                <span class="material-symbols-rounded">chevron_right</span>
              </a>
            </div>
            <div class="books-shelf">
              @for (book of shelfBooks(); track book.id) {
                <div class="book-shelf-item">
                  <app-book-card
                    [book]="book"
                    [progress]="booksService.progressMap()[book.id]"
                  />
                </div>
              }
            </div>
          </section>
        }

        @if (shelfSongs().length > 0) {
          <section class="shelf-section">
            <div class="section-head">
              <div class="section-title">
                <span class="material-symbols-rounded sec-ico">music_note</span>
                <h2>Songs</h2>
              </div>
              <a class="see-all-link" routerLink="/songs">
                <span>See all</span>
                <span class="material-symbols-rounded">chevron_right</span>
              </a>
            </div>
            <div class="songs-shelf">
              @for (song of shelfSongs(); track song.id) {
                <a class="song-shelf-card" [routerLink]="['/song', song.id]">
                  <div class="song-ico-box">
                    <span class="material-symbols-rounded">music_note</span>
                  </div>
                  <div class="song-shelf-meta">
                    <strong>{{ song.title }}</strong>
                    @if (song.titleRoman || song.author || song.collection) {
                      <span>{{ song.titleRoman || song.collection || song.author }}</span>
                    }
                  </div>
                </a>
              }
            </div>
          </section>
        }

        @if (shelfArticles().length > 0) {
          <section class="shelf-section">
            <div class="section-head">
              <div class="section-title">
                <span class="material-symbols-rounded sec-ico">article</span>
                <h2>Articles</h2>
              </div>
              <a class="see-all-link" routerLink="/articles">
                <span>See all</span>
                <span class="material-symbols-rounded">chevron_right</span>
              </a>
            </div>
            <div class="articles-shelf">
              @for (entry of shelfArticles(); track entry.id + ':' + entry.lang) {
                <a
                  class="article-row-card"
                  [routerLink]="['/article', entry.id]"
                  [queryParams]="{ lang: entry.lang }"
                >
                  <div class="article-ico-box">
                    <span class="material-symbols-rounded">menu_book</span>
                  </div>
                  <div class="article-row-meta">
                    <strong>{{ entry.title }}</strong>
                    <span>{{ entry.date }}</span>
                  </div>
                  <span class="material-symbols-rounded chevron">chevron_right</span>
                </a>
              }
            </div>
          </section>
        }
      }
    </div>
  `,
  styles: [
    `
      .library-page {
        padding-top: 12px;
        padding-bottom: 40px;
        display: flex;
        flex-direction: column;
        gap: 20px;
      }

      .page-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
      }

      .page-head h1 {
        margin: 0;
        font-size: 18px;
        font-weight: 700;
      }

      .subtitle {
        margin: 2px 0 0;
        font-size: 13px;
        color: var(--on-surface-muted);
      }

      .lang-strip {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
      }

      .shelf-section {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }

      .section-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
      }

      .section-title {
        display: flex;
        align-items: center;
        gap: 8px;
      }

      .sec-ico {
        font-size: 20px;
        color: var(--accent);
      }

      .section-title h2 {
        margin: 0;
        font-size: 16px;
        font-weight: 700;
      }

      .see-all-link {
        display: inline-flex;
        align-items: center;
        gap: 2px;
        font-size: 13px;
        font-weight: 600;
        color: var(--accent);
        text-decoration: none;
      }

      .see-all-link .material-symbols-rounded {
        font-size: 18px;
      }

      .books-shelf {
        display: flex;
        gap: 12px;
        overflow-x: auto;
        padding-bottom: 6px;
        scrollbar-width: thin;
      }

      .book-shelf-item {
        width: 126px;
        flex-shrink: 0;
      }

      .songs-shelf {
        display: flex;
        gap: 10px;
        overflow-x: auto;
        padding-bottom: 6px;
        scrollbar-width: thin;
      }

      .song-shelf-card {
        width: 220px;
        flex-shrink: 0;
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 10px 12px;
        border-radius: var(--radius-md);
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        color: var(--on-surface);
        text-decoration: none;
      }

      .song-shelf-card:hover {
        border-color: var(--accent);
      }

      .song-ico-box,
      .article-ico-box {
        width: 40px;
        height: 40px;
        border-radius: 10px;
        background-color: var(--accent-soft);
        color: var(--accent);
        display: grid;
        place-items: center;
        flex-shrink: 0;
      }

      .song-shelf-meta,
      .article-row-meta {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 2px;
      }

      .song-shelf-meta strong,
      .article-row-meta strong {
        font-size: 14px;
        font-weight: 600;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .song-shelf-meta span,
      .article-row-meta span {
        font-size: 12px;
        color: var(--on-surface-muted);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .articles-shelf {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
        gap: 10px;
      }

      .article-row-card {
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 12px 14px;
        border-radius: 14px;
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        color: var(--on-surface);
        text-decoration: none;
      }

      .article-row-card:hover {
        border-color: var(--accent);
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
        gap: 10px;
      }

      .state-ico {
        font-size: 40px;
        color: var(--on-surface-muted);
      }

      .muted {
        margin: 0;
        font-size: 14px;
        color: var(--on-surface-muted);
      }

      .shelf-skeletons {
        display: flex;
        flex-direction: column;
        gap: 20px;
      }

      .sk-row {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }

      .sk-title {
        width: 120px;
        height: 18px;
        border-radius: 6px;
        background-color: var(--surface-variant);
      }

      .sk-cards {
        display: flex;
        gap: 12px;
        overflow: hidden;
      }

      .sk-card {
        width: 126px;
        height: 180px;
        border-radius: var(--radius-md);
        background-color: var(--surface-variant);
        flex-shrink: 0;
      }
    `,
  ],
})
export class LibraryHubComponent implements OnInit {
  readonly booksService = inject(BooksService);
  readonly songsService = inject(SongsService);
  readonly articlesService = inject(ArticlesService);

  readonly selectedLang = signal('all');

  readonly isLoading = computed(
    () =>
      this.booksService.loading() ||
      this.songsService.loading() ||
      this.articlesService.loading(),
  );

  readonly availableLanguages = computed(() => {
    const set = new Set<string>();
    for (const b of this.booksService.catalog()) {
      const code = this.booksService.inferBookLanguage(b.id, b.lang);
      if (code) set.add(code);
    }
    for (const s of this.songsService.songs()) {
      if (s.language) set.add(s.language.toLowerCase());
    }
    for (const a of this.articlesService.entries()) {
      if (a.lang) set.add(a.lang.toLowerCase());
    }
    return Array.from(set).sort();
  });

  readonly shelfBooks = computed(() => {
    const lang = this.selectedLang();
    const progress = this.booksService.progressMap();
    const filtered = this.booksService.catalog().filter(
      (b) => lang === 'all' || this.booksService.inferBookLanguage(b.id, b.lang) === lang,
    );
    return [...filtered]
      .sort((a, b) => {
        const ta = Date.parse(progress[a.id]?.updatedAt ?? '') || 0;
        const tb = Date.parse(progress[b.id]?.updatedAt ?? '') || 0;
        return tb - ta;
      })
      .slice(0, 12);
  });

  readonly shelfSongs = computed(() => {
    const lang = this.selectedLang();
    return this.songsService
      .songs()
      .filter((s) => lang === 'all' || s.language.toLowerCase() === lang)
      .slice(0, 10);
  });

  readonly shelfArticles = computed(() => {
    const lang = this.selectedLang();
    return this.articlesService
      .entries()
      .filter((a) => lang === 'all' || a.lang.toLowerCase() === lang)
      .slice(0, 8);
  });

  readonly hasAnyContent = computed(
    () =>
      this.shelfBooks().length > 0 ||
      this.shelfSongs().length > 0 ||
      this.shelfArticles().length > 0,
  );

  ngOnInit(): void {
    this.refresh();
  }

  refresh(): void {
    void this.booksService.loadCatalog();
    void this.songsService.loadCatalog();
    void this.articlesService.loadIndex();
  }

  langName(code: string): string {
    return SUPPORTED_LANGUAGES[code.toLowerCase()]?.englishName ?? code.toUpperCase();
  }
}
