import {
  ChangeDetectionStrategy,
  Component,
  inject,
  input,
  output,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ReleaseDataService } from '../../../core/api/release-data.service';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';
import { ScriptureRefParserService } from '../../books/services/scripture-ref-parser.service';
import { BibleBook, BibleVerse } from '../models/bible.model';

export interface BibleSearchHit {
  bookNumber: number;
  bookName: string;
  chapter: number;
  verse: number;
  text: string;
}

@Component({
  selector: 'app-bible-search-sheet',
  standalone: true,
  imports: [FormsModule, ModalSheetComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-modal-sheet title="Search Bible" (closed)="closed.emit()">
      <form class="search-form" (submit)="runSearch($event)">
        <div class="sheet-search">
          <span class="material-symbols-rounded">search</span>
          <input
            type="search"
            placeholder="Search words or reference (e.g. John 3:16)..."
            [ngModel]="query()"
            name="q"
            (ngModelChange)="query.set($event)"
          />
        </div>
        <button type="submit" class="pill-chip active">Search</button>
      </form>

      @if (searching()) {
        <p class="status-msg">Searching {{ currentBook().name }}...</p>
      } @else if (searched() && results().length === 0) {
        <p class="status-msg">No matches found in {{ currentBook().name }}.</p>
      } @else {
        <div class="results-list">
          @for (r of results(); track $index) {
            <button
              type="button"
              class="result-row"
              (click)="jumpTo.emit({ bookNumber: r.bookNumber, chapter: r.chapter, verse: r.verse })"
            >
              <span class="res-ref">
                {{ r.bookName }} {{ r.chapter }}:{{ r.verse }}
              </span>
              <p class="res-text">{{ r.text }}</p>
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

      .res-ref {
        display: block;
        font-size: 12px;
        font-weight: 700;
        color: var(--accent);
        margin-bottom: 4px;
      }

      .res-text {
        margin: 0;
        font-size: 13px;
        line-height: 1.45;
      }
    `,
  ],
})
export class BibleSearchSheetComponent {
  private readonly releases = inject(ReleaseDataService);
  private readonly parser = inject(ScriptureRefParserService);

  readonly version = input.required<string>();
  readonly currentBook = input.required<BibleBook>();
  readonly jumpTo = output<{ bookNumber: number; chapter: number; verse: number }>();
  readonly closed = output<void>();

  readonly query = signal<string>('');
  readonly searching = signal<boolean>(false);
  readonly searched = signal<boolean>(false);
  readonly results = signal<BibleSearchHit[]>([]);

  async runSearch(event: Event): Promise<void> {
    event.preventDefault();
    const raw = this.query().trim();
    if (raw.length < 2) return;

    // 1. Check if the query is a direct scripture reference (e.g. "John 3:16")
    const parsed = this.parser.parse(raw).find((t) => t.ref !== null)?.ref;
    if (parsed) {
      this.jumpTo.emit({
        bookNumber: parsed.bookNumber,
        chapter: parsed.chapter,
        verse: parsed.startVerse,
      });
      return;
    }

    // 2. Otherwise search all chapters of the current book
    const q = raw.toLowerCase();
    const book = this.currentBook();
    this.searching.set(true);
    this.searched.set(true);
    const hits: BibleSearchHit[] = [];

    for (let ch = 1; ch <= book.chapters; ch++) {
      if (hits.length >= 40) break;
      try {
        const verses = await this.releases.getJson<BibleVerse[]>(
          `bibles/${this.version()}/${book.bookNumber}/${ch}.json`,
        );
        for (const v of verses) {
          if (v.text.toLowerCase().includes(q)) {
            hits.push({
              bookNumber: book.bookNumber,
              bookName: book.name,
              chapter: ch,
              verse: v.verse,
              text: v.text,
            });
            if (hits.length >= 40) break;
          }
        }
      } catch {
        // skip chapter if unavailable
      }
    }

    this.results.set(hits);
    this.searching.set(false);
  }
}
