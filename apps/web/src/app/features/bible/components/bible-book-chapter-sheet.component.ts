import {
  ChangeDetectionStrategy,
  Component,
  OnInit,
  computed,
  inject,
  input,
  output,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';
import { BibleBook, BibleVerse } from '../models/bible.model';
import { BibleReaderStateService } from '../services/bible-reader-state.service';

export type BiblePickerTab = 'books' | 'chapters' | 'verses';

export interface BibleSelectionTarget {
  bookNumber: number;
  chapter: number;
  verse?: number;
}

@Component({
  selector: 'app-bible-book-chapter-sheet',
  standalone: true,
  imports: [FormsModule, ModalSheetComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-modal-sheet (closed)="closed.emit()">
      <div class="picker-tabs">
        <button
          type="button"
          class="picker-tab"
          [class.active]="pickerTab() === 'books'"
          (click)="pickerTab.set('books')"
        >
          BOOKS
        </button>
        <button
          type="button"
          class="picker-tab"
          [class.active]="pickerTab() === 'chapters'"
          (click)="pickerTab.set('chapters')"
        >
          CHAPTERS
        </button>
        <button
          type="button"
          class="picker-tab"
          [class.active]="pickerTab() === 'verses'"
          (click)="openVersesTab()"
        >
          VERSES
        </button>
      </div>

      @if (pickerTab() === 'books') {
        <div class="book-filters">
          <div class="sheet-search">
            <span class="material-symbols-rounded">search</span>
            <input
              type="search"
              placeholder="Search books..."
              [ngModel]="bookSearch()"
              (ngModelChange)="bookSearch.set($event)"
            />
          </div>
          <div class="testament-chips">
            @for (t of ['all', 'ot', 'nt']; track t) {
              <button
                type="button"
                class="pill-chip"
                [class.active]="testamentFilter() === t"
                (click)="testamentFilter.set($any(t))"
              >
                {{ t === 'all' ? 'All' : t.toUpperCase() }}
              </button>
            }
          </div>
        </div>

        <div class="books-list">
          @for (b of filteredBooks(); track b.bookNumber) {
            <button
              type="button"
              class="book-row"
              [class.active]="b.bookNumber === draftBook().bookNumber"
              (click)="pickBook(b)"
            >
              <span>{{ b.name }}</span>
              <span class="book-ch-count">{{ b.chapters }} ch</span>
            </button>
          }
        </div>
      } @else if (pickerTab() === 'chapters') {
        <div class="chapter-pick-head">
          <strong>{{ draftBook().name }}</strong>
          <button
            type="button"
            class="pill-chip active"
            (click)="apply(draftBook().bookNumber, draftChapter())"
          >
            Open Ch. {{ draftChapter() }}
          </button>
        </div>
        <div class="chapters-grid">
          @for (ch of chapterNumbers(); track ch) {
            <button
              type="button"
              class="ch-cell"
              [class.active]="
                draftBook().bookNumber === currentBook().bookNumber &&
                ch === draftChapter()
              "
              (click)="pickChapter(ch)"
            >
              {{ ch }}
            </button>
          }
        </div>
      } @else {
        <div class="chapter-pick-head">
          <strong>{{ draftBook().name }} {{ draftChapter() }}</strong>
          <button
            type="button"
            class="pill-chip active"
            (click)="apply(draftBook().bookNumber, draftChapter())"
          >
            Read Chapter
          </button>
        </div>
        @if (loadingVerses()) {
          <p class="status-msg">Loading verses...</p>
        } @else {
          <div class="chapters-grid">
            @for (v of pickerVerses(); track v.verse) {
              <button
                type="button"
                class="ch-cell"
                (click)="apply(draftBook().bookNumber, draftChapter(), v.verse)"
              >
                {{ v.verse }}
              </button>
            }
          </div>
        }
      }
    </app-modal-sheet>
  `,
  styles: [
    `
      .picker-tabs {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        border-bottom: 1px solid var(--surface-border);
      }

      .picker-tab {
        padding: 10px 6px;
        font-size: 12px;
        font-weight: 700;
        letter-spacing: 0.05em;
        color: var(--on-surface-muted);
        border-bottom: 2px solid transparent;
      }

      .picker-tab.active {
        color: var(--accent);
        border-bottom-color: var(--accent);
      }

      .book-filters {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }

      .sheet-search {
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

      .testament-chips {
        display: flex;
        gap: 8px;
        flex-wrap: wrap;
      }

      .books-list {
        display: flex;
        flex-direction: column;
        gap: 4px;
        max-height: 55dvh;
        overflow-y: auto;
      }

      .book-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 10px 12px;
        border-radius: var(--radius-sm);
        background-color: var(--surface-variant);
        border: 1px solid transparent;
        font-size: 14px;
        font-weight: 500;
      }

      .book-row.active {
        background-color: var(--accent-soft);
        border-color: var(--accent);
        color: var(--accent);
      }

      .book-ch-count {
        font-size: 12px;
        color: var(--on-surface-muted);
      }

      .chapter-pick-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
      }

      .chapters-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(52px, 1fr));
        gap: 8px;
        max-height: 50dvh;
        overflow-y: auto;
      }

      .ch-cell {
        height: 44px;
        border-radius: var(--radius-sm);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        font-weight: 600;
      }

      .ch-cell.active {
        background-color: var(--accent);
        color: var(--on-accent);
        border-color: var(--accent);
      }

      .status-msg {
        padding: 20px 0;
        text-align: center;
        color: var(--on-surface-muted);
      }
    `,
  ],
})
export class BibleBookChapterSheetComponent implements OnInit {
  private readonly readerState = inject(BibleReaderStateService);

  readonly books = input.required<BibleBook[]>();
  readonly currentBook = input.required<BibleBook>();
  readonly currentChapter = input.required<number>();
  readonly initialTab = input<BiblePickerTab>('books');

  readonly selectionApplied = output<BibleSelectionTarget>();
  readonly closed = output<void>();

  readonly pickerTab = signal<BiblePickerTab>('books');
  readonly testamentFilter = signal<'all' | 'ot' | 'nt'>('all');
  readonly bookSearch = signal<string>('');
  readonly draftBook = signal<BibleBook>({
    bookNumber: 1,
    name: 'Genesis',
    chapters: 50,
  });
  readonly draftChapter = signal<number>(1);
  readonly pickerVerses = signal<BibleVerse[]>([]);
  readonly loadingVerses = signal<boolean>(false);

  readonly filteredBooks = computed(() => {
    const q = this.bookSearch().trim().toLowerCase();
    const t = this.testamentFilter();
    return this.books().filter((b) => {
      if (t === 'ot' && b.bookNumber > 39) return false;
      if (t === 'nt' && b.bookNumber < 40) return false;
      if (q && !b.name.toLowerCase().includes(q)) return false;
      return true;
    });
  });

  readonly chapterNumbers = computed(() =>
    Array.from({ length: this.draftBook().chapters }, (_, i) => i + 1),
  );

  ngOnInit(): void {
    this.draftBook.set(this.currentBook());
    this.draftChapter.set(this.currentChapter());
    this.pickerTab.set(this.initialTab());
    if (this.initialTab() === 'verses') {
      void this.loadVerses();
    }
  }

  pickBook(b: BibleBook): void {
    this.draftBook.set(b);
    this.draftChapter.set(1);
    this.pickerTab.set('chapters');
  }

  pickChapter(ch: number): void {
    this.draftChapter.set(ch);
    this.openVersesTab();
  }

  openVersesTab(): void {
    this.pickerTab.set('verses');
    void this.loadVerses();
  }

  apply(bookNumber: number, chapter: number, verse?: number): void {
    this.selectionApplied.emit({ bookNumber, chapter, verse });
  }

  private async loadVerses(): Promise<void> {
    this.loadingVerses.set(true);
    const verses = await this.readerState.loadVersesForChapter(
      this.draftBook().bookNumber,
      this.draftChapter(),
    );
    this.pickerVerses.set(verses);
    this.loadingVerses.set(false);
  }
}
