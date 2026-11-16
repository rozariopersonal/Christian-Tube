import {
  ChangeDetectionStrategy,
  Component,
  inject,
  input,
  output,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';
import { BookToc } from '../models/book.model';
import { BooksService } from '../services/books.service';

export interface BookSearchResult {
  chapterIndex: number;
  chapterTitle: string;
  lineIndex: number;
  snippet: string;
}

@Component({
  selector: 'app-book-search-sheet',
  standalone: true,
  imports: [FormsModule, ModalSheetComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-modal-sheet title="Search Inside Book" (closed)="closed.emit()">
      <form class="search-form" (submit)="runSearch($event)">
        <div class="sheet-search">
          <span class="material-symbols-rounded">search</span>
          <input
            type="search"
            placeholder="Search phrases or words..."
            [ngModel]="query()"
            name="q"
            (ngModelChange)="query.set($event)"
          />
        </div>
        <button type="submit" class="pill-chip active">Search</button>
      </form>

      @if (searching()) {
        <p class="status-msg">Searching chapters...</p>
      } @else if (searched() && results().length === 0) {
        <p class="status-msg">No matches found for "{{ query() }}".</p>
      } @else {
        <div class="results-list">
          @for (r of results(); track $index) {
            <button
              type="button"
              class="result-row"
              (click)="jumpTo.emit({ chapter: r.chapterIndex, line: r.lineIndex })"
            >
              <span class="res-ch">
                Ch. {{ r.chapterIndex }} · {{ r.chapterTitle }}
              </span>
              <p class="res-snippet">{{ r.snippet }}</p>
            </button>
          }
        </div>
      }
    </app-modal-sheet>
  `,
  styles: [
    `
      .search-form {
        display: flex;
        gap: 8px;
        align-items: center;
      }

      .sheet-search {
        flex: 1;
        min-width: 0;
        display: flex;
        align-items: center;
        gap: 8px;
        height: 40px;
        padding: 0 12px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
      }

      .sheet-search input {
        flex: 1;
        border: none;
        outline: none;
        background: transparent;
        min-width: 0;
      }

      .status-msg {
        padding: 20px 0;
        text-align: center;
        color: var(--on-surface-muted);
      }

      .results-list {
        display: flex;
        flex-direction: column;
        gap: 8px;
        max-height: 55dvh;
        overflow-y: auto;
      }

      .result-row {
        padding: 10px 12px;
        border-radius: var(--radius-md);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        text-align: left;
      }

      .res-ch {
        display: block;
        font-size: 12px;
        font-weight: 700;
        color: var(--accent);
        margin-bottom: 4px;
      }

      .res-snippet {
        margin: 0;
        font-size: 13px;
        line-height: 1.45;
      }
    `,
  ],
})
export class BookSearchSheetComponent {
  private readonly booksService = inject(BooksService);

  readonly bookId = input.required<string>();
  readonly bookLang = input<string | undefined>();
  readonly toc = input.required<BookToc>();

  readonly jumpTo = output<{ chapter: number; line: number }>();
  readonly closed = output<void>();

  readonly query = signal<string>('');
  readonly searching = signal<boolean>(false);
  readonly searched = signal<boolean>(false);
  readonly results = signal<BookSearchResult[]>([]);

  async runSearch(event: Event): Promise<void> {
    event.preventDefault();
    const q = this.query().trim().toLowerCase();
    if (q.length < 2) return;

    this.searching.set(true);
    this.searched.set(true);
    const hits: BookSearchResult[] = [];
    const chapters = this.toc().chapters;

    for (const ch of chapters) {
      if (hits.length >= 40) break;
      try {
        const lines = await this.booksService.fetchChapter(
          this.bookId(),
          ch.chapterIndex,
          this.bookLang(),
          chapters.length,
        );
        for (let i = 0; i < lines.length; i++) {
          const text = lines[i].text ?? '';
          const idx = text.toLowerCase().indexOf(q);
          if (idx >= 0) {
            const start = Math.max(0, idx - 45);
            const end = Math.min(text.length, idx + q.length + 75);
            const prefix = start > 0 ? '…' : '';
            const suffix = end < text.length ? '…' : '';
            hits.push({
              chapterIndex: ch.chapterIndex,
              chapterTitle: ch.title,
              lineIndex: i,
              snippet: `${prefix}${text.slice(start, end)}${suffix}`,
            });
            if (hits.length >= 40) break;
          }
        }
      } catch {
        // skip unavailable chapter
      }
    }

    this.results.set(hits);
    this.searching.set(false);
  }
}
