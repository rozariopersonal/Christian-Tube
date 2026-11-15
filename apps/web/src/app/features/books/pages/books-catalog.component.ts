import {
  ChangeDetectionStrategy,
  Component,
  OnInit,
  computed,
  inject,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { LanguageDropdownComponent } from '../../../shared/ui/language-dropdown.component';
import { canonicalLanguageCode } from '../../../shared/ui/language-meta';
import { BookCardComponent } from '../components/book-card.component';
import { BooksService } from '../services/books.service';

@Component({
  selector: 'app-books-catalog',
  standalone: true,
  imports: [FormsModule, RouterLink, LanguageDropdownComponent, BookCardComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="books-page max-width-box">
      <header class="page-head">
        <h1 class="font-display">Books Library</h1>
      </header>

      <div class="controls">
        <div class="search-box">
          <span class="material-symbols-rounded">search</span>
          <input
            type="search"
            placeholder="Search books or authors..."
            [ngModel]="search()"
            (ngModelChange)="search.set($event)"
          />
        </div>

        <app-language-dropdown
          [selectedLanguages]="selectedLanguages()"
          [availableLanguages]="languages()"
          [itemCounts]="languageCounts()"
          itemNoun="books"
          headerTitle="Book Languages"
          (languagesChange)="selectedLanguages.set($event)"
        />
      </div>

      <div class="subject-strip">
        @for (subj of subjects(); track subj) {
          <button
            type="button"
            class="pill-chip"
            [class.active]="selectedSubject() === subj"
            (click)="selectedSubject.set(subj)"
          >
            {{ subj }}
          </button>
        }
      </div>

      @if (booksService.recentBooks().length > 0 && !search().trim()) {
        <section class="section">
          <h2 class="section-title">Continue Reading</h2>
          <div class="recent-row">
            @for (p of booksService.recentBooks().slice(0, 6); track p.bookId) {
              <a class="recent-card" [routerLink]="['/books', p.bookId]">
                @if (p.coverFile) {
                  <img
                    class="recent-cover"
                    [src]="booksService.coverUrl(p.coverFile)"
                    [alt]="p.title"
                    loading="lazy"
                  />
                }
                <div class="recent-info">
                  <strong>{{ p.title }}</strong>
                  <span class="muted">
                    Ch. {{ p.chapterIndex }} / {{ p.totalChapters }}
                  </span>
                </div>
              </a>
            }
          </div>
        </section>
      }

      @if (booksService.loading()) {
        <p class="status-msg">Loading library...</p>
      } @else if (booksService.error()) {
        <div class="status-msg">
          <p>{{ booksService.error() }}</p>
          <button
            type="button"
            class="pill-chip active"
            (click)="booksService.loadCatalog()"
          >
            Retry
          </button>
        </div>
      } @else {
        <div class="books-grid">
          @for (book of filteredBooks(); track book.id) {
            <app-book-card
              [book]="book"
              [progress]="booksService.progressMap()[book.id]"
              [coverUrl]="book.coverFile ? booksService.coverUrl(book.coverFile) : null"
            />
          }
        </div>
      }
    </div>
  `,
  styles: [
    `
      .books-page {
        padding-top: 16px;
        padding-bottom: 32px;
      }

      .page-head h1 {
        margin: 0 0 14px;
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

      .subject-strip {
        display: flex;
        gap: 8px;
        overflow-x: auto;
        padding-bottom: 12px;
        margin-bottom: 12px;
        scrollbar-width: none;
      }

      .subject-strip::-webkit-scrollbar {
        display: none;
      }

      .section {
        margin-bottom: 24px;
      }

      .section-title {
        margin: 0 0 10px;
        font-size: 16px;
        font-weight: 700;
      }

      .recent-row {
        display: flex;
        gap: 12px;
        overflow-x: auto;
        padding-bottom: 4px;
      }

      .recent-card {
        flex: 0 0 220px;
        display: flex;
        gap: 10px;
        padding: 10px;
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-md);
        align-items: center;
      }

      .recent-cover {
        width: 44px;
        height: 62px;
        object-fit: cover;
        border-radius: 4px;
        flex-shrink: 0;
      }

      .recent-info {
        display: flex;
        flex-direction: column;
        gap: 4px;
        min-width: 0;
        font-size: 13px;
      }

      .recent-info strong {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .muted {
        font-size: 12px;
        color: var(--on-surface-muted);
      }

      .books-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
        gap: 18px 14px;
      }

      .status-msg {
        text-align: center;
        padding: 36px 0;
        color: var(--on-surface-muted);
      }
    `,
  ],
})
export class BooksCatalogComponent implements OnInit {
  readonly booksService = inject(BooksService);

  readonly search = signal<string>('');
  readonly selectedLanguages = signal<string[]>(['All']);
  readonly selectedSubject = signal<string>('All');

  readonly languageCounts = computed(() => {
    const counts: Record<string, number> = {
      All: this.booksService.catalog().length,
    };
    for (const b of this.booksService.catalog()) {
      const code = canonicalLanguageCode(b.lang);
      counts[code] = (counts[code] ?? 0) + 1;
    }
    return counts;
  });

  readonly languages = computed(() => {
    const counts = this.languageCounts();
    return Object.keys(counts)
      .filter((k) => k !== 'All')
      .sort((a, b) => (counts[b] ?? 0) - (counts[a] ?? 0));
  });

  readonly subjects = computed(() => {
    const set = new Set<string>(['All']);
    for (const b of this.booksService.catalog()) {
      if (b.subject) set.add(b.subject);
    }
    return [...set];
  });

  readonly filteredBooks = computed(() => {
    const q = this.search().trim().toLowerCase();
    const selLangs = this.selectedLanguages();
    const allLangs = selLangs.length === 0 || selLangs.includes('All');
    const langSet = new Set(selLangs.map((l) => l.toLowerCase()));
    const subj = this.selectedSubject();
    return this.booksService.catalog().filter((b) => {
      if (!allLangs && !langSet.has(canonicalLanguageCode(b.lang).toLowerCase())) {
        return false;
      }
      if (subj !== 'All' && b.subject !== subj) return false;
      if (
        q &&
        !b.title.toLowerCase().includes(q) &&
        !b.author.toLowerCase().includes(q)
      ) {
        return false;
      }
      return true;
    });
  });

  ngOnInit(): void {
    void this.booksService.loadCatalog();
  }
}
