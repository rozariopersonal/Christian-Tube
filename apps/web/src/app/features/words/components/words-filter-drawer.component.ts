import {
  ChangeDetectionStrategy,
  Component,
  OnInit,
  computed,
  input,
  output,
  signal,
} from '@angular/core';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';
import { SearchInputComponent } from '../../../shared/ui/search-input.component';
import {
  BIBLE_BOOK_LIST,
  CATEGORY_DEFINITIONS,
  ReadingOrder,
  TAG_DEFINITIONS,
  TestamentFilter,
  WordsFilterState,
  countActiveFilters,
} from '../models/words-feed.model';

const ORDER_OPTIONS: readonly { id: ReadingOrder; label: string; icon: string }[] = [
  { id: 'daily', label: 'Daily Word', icon: 'today' },
  { id: 'random', label: 'Random Deck', icon: 'shuffle' },
  { id: 'canonical', label: 'Canonical', icon: 'format_list_numbered' },
  { id: 'bookmarked', label: 'Bookmarked', icon: 'bookmark' },
];

const TESTAMENT_OPTIONS: readonly { id: TestamentFilter; label: string }[] = [
  { id: 'all', label: 'All' },
  { id: 'ot', label: 'Old Testament' },
  { id: 'nt', label: 'New Testament' },
];

@Component({
  selector: 'app-words-filter-drawer',
  standalone: true,
  imports: [ModalSheetComponent, SearchInputComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-modal-sheet title="Feed Filters & Order" (closed)="closed.emit()">
      <div class="filter-scroll">
        <section class="filter-section">
          <h3 class="sec-title">Reading Order</h3>
          <div class="order-grid">
            @for (opt of orderOptions; track opt.id) {
              <button
                type="button"
                class="order-card"
                [class.active]="readingOrder() === opt.id"
                (click)="readingOrder.set(opt.id)"
              >
                <span class="material-symbols-rounded order-icon">{{ opt.icon }}</span>
                <span>{{ opt.label }}</span>
              </button>
            }
          </div>
        </section>

        <section class="filter-section">
          <h3 class="sec-title">Testament</h3>
          <div class="seg-row">
            @for (t of testamentOptions; track t.id) {
              <button
                type="button"
                class="seg-btn"
                [class.active]="testamentFilter() === t.id"
                (click)="setTestament(t.id)"
              >
                {{ t.label }}
              </button>
            }
          </div>
        </section>

        <section class="filter-section">
          <div class="sec-head">
            <h3 class="sec-title">Book</h3>
            <span class="sec-meta">
              {{ selectedBookName() }}
              @if (bookNumberFilter() !== null) {
                ·
                <button
                  type="button"
                  class="link-btn"
                  (click)="bookNumberFilter.set(null)"
                >
                  Clear
                </button>
              }
            </span>
          </div>
          <app-search-input
            placeholder="Search 66 books..."
            [value]="bookQuery()"
            (valueChange)="bookQuery.set($event)"
          />
          <div class="book-grid">
            <button
              type="button"
              class="book-cell"
              [class.active]="bookNumberFilter() === null"
              (click)="bookNumberFilter.set(null)"
            >
              All Books
            </button>
            @for (b of filteredBooks(); track b.bookNumber) {
              <button
                type="button"
                class="book-cell"
                [class.active]="bookNumberFilter() === b.bookNumber"
                (click)="bookNumberFilter.set(b.bookNumber)"
              >
                {{ b.name }}
              </button>
            }
          </div>
        </section>

        <section class="filter-section">
          <div class="sec-head">
            <h3 class="sec-title">Categories</h3>
            @if (selectedCategories().length > 0) {
              <button
                type="button"
                class="link-btn"
                (click)="selectedCategories.set([])"
              >
                Clear ({{ selectedCategories().length }})
              </button>
            }
          </div>
          <div class="chip-grid">
            @for (c of categories; track c.id) {
              <button
                type="button"
                class="choice-chip"
                [class.active]="selectedCategories().includes(c.id)"
                (click)="toggleCategory(c.id)"
              >
                <span class="material-symbols-rounded chip-icon">{{ c.icon }}</span>
                <span>{{ c.label }}</span>
              </button>
            }
          </div>
        </section>

        <section class="filter-section">
          <div class="sec-head">
            <h3 class="sec-title">Tags</h3>
            @if (selectedTags().length > 0) {
              <button
                type="button"
                class="link-btn"
                (click)="selectedTags.set([])"
              >
                Clear ({{ selectedTags().length }})
              </button>
            }
          </div>
          <div class="chip-grid">
            @for (tag of tags; track tag) {
              <button
                type="button"
                class="choice-chip"
                [class.active]="selectedTags().includes(tag)"
                (click)="toggleTag(tag)"
              >
                {{ formatTag(tag) }}
              </button>
            }
          </div>
        </section>
      </div>

      <div class="sheet-footer">
        <button type="button" class="btn-secondary" (click)="resetAll()">
          Reset All
        </button>
        <button type="button" class="btn-primary" (click)="apply()">
          Apply Filters
          @if (draftCount() > 0) {
            <span class="count-pill">{{ draftCount() }}</span>
          }
        </button>
      </div>
    </app-modal-sheet>
  `,
  styles: [
    `
      .filter-scroll {
        display: flex;
        flex-direction: column;
        gap: 20px;
        max-height: 64dvh;
        overflow-y: auto;
        padding: 4px 8px 6px 2px;
        scrollbar-width: thin;
        scrollbar-color: var(--surface-border) transparent;
      }

      .filter-scroll::-webkit-scrollbar,
      .book-grid::-webkit-scrollbar {
        width: 5px;
      }

      .filter-scroll::-webkit-scrollbar-thumb,
      .book-grid::-webkit-scrollbar-thumb {
        border-radius: 999px;
        background-color: var(--surface-border);
      }

      .filter-section {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }

      .filter-section + .filter-section {
        padding-top: 16px;
        border-top: 1px solid var(--surface-border);
      }

      .sec-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
      }

      .sec-title {
        margin: 0;
        font-size: 11.5px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--on-surface-muted);
      }

      .sec-meta {
        font-size: 12px;
        font-weight: 600;
        color: var(--on-surface-muted);
      }

      .link-btn {
        font-size: 12px;
        font-weight: 600;
        color: var(--accent);
      }

      .order-grid {
        display: grid;
        grid-template-columns: repeat(2, 1fr);
        gap: 8px;
      }

      @media (min-width: 520px) {
        .order-grid {
          grid-template-columns: repeat(4, 1fr);
        }
      }

      .order-card {
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 6px;
        padding: 10px 8px;
        border-radius: var(--radius-md);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        color: var(--on-surface);
        font-size: 12.5px;
        font-weight: 600;
        transition: background-color 140ms ease, border-color 140ms ease;
      }

      .order-card:hover {
        border-color: var(--accent);
      }

      .order-card.active {
        background-color: var(--accent-soft);
        border-color: var(--accent);
        color: var(--accent);
      }

      .order-icon {
        font-size: 20px;
      }

      .seg-row {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: 4px;
        padding: 4px;
        border-radius: var(--radius-md);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
      }

      .seg-btn {
        height: 34px;
        border-radius: var(--radius-sm);
        font-size: 13px;
        font-weight: 500;
        color: var(--on-surface-muted);
        transition: background-color 140ms ease, color 140ms ease;
      }

      .seg-btn.active {
        background-color: var(--surface);
        color: var(--on-surface);
        font-weight: 600;
        box-shadow: 0 1px 3px rgba(0, 0, 0, 0.12);
      }

      .book-search {
        display: flex;
        align-items: center;
        gap: 8px;
        height: 38px;
        padding: 0 12px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
      }

      .search-ico {
        font-size: 18px;
        color: var(--on-surface-muted);
      }

      .book-search input {
        flex: 1;
        border: none;
        outline: none;
        background: transparent;
        color: var(--on-surface);
        font-size: 13px;
        min-width: 0;
      }

      .book-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(120px, 1fr));
        gap: 6px;
        max-height: 152px;
        overflow-y: auto;
        padding-right: 4px;
        scrollbar-width: thin;
        scrollbar-color: var(--surface-border) transparent;
      }

      .book-cell {
        height: 32px;
        padding: 0 10px;
        border-radius: var(--radius-sm);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        color: var(--on-surface);
        font-size: 12.5px;
        font-weight: 500;
        text-align: left;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .book-cell.active {
        background-color: var(--accent-soft);
        border-color: var(--accent);
        color: var(--accent);
        font-weight: 600;
      }

      .chip-grid {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
      }

      .choice-chip {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        height: 32px;
        padding: 0 12px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        color: var(--on-surface);
        font-size: 12.5px;
        font-weight: 500;
        white-space: nowrap;
        transition: background-color 140ms ease, border-color 140ms ease;
      }

      .choice-chip:hover {
        border-color: var(--accent);
      }

      .choice-chip.active {
        background-color: var(--accent-soft);
        border-color: var(--accent);
        color: var(--accent);
        font-weight: 600;
      }

      .chip-icon {
        font-size: 16px;
      }

      .sheet-footer {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 10px;
        padding-top: 12px;
        border-top: 1px solid var(--surface-border);
      }

      .btn-secondary {
        height: 40px;
        padding: 0 16px;
        border-radius: var(--radius-pill);
        border: 1px solid var(--surface-border);
        color: var(--on-surface);
        font-size: 13px;
        font-weight: 600;
      }

      .btn-secondary:hover {
        background-color: var(--surface-variant);
      }

      .btn-primary {
        flex: 1;
        height: 40px;
        padding: 0 18px;
        border-radius: var(--radius-pill);
        background-color: var(--accent);
        color: #ffffff;
        font-size: 14px;
        font-weight: 600;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 8px;
      }

      .count-pill {
        padding: 2px 7px;
        border-radius: 999px;
        background-color: rgba(255, 255, 255, 0.24);
        font-size: 12px;
        font-weight: 700;
      }
    `,
  ],
})
export class WordsFilterDrawerComponent implements OnInit {
  readonly currentFilter = input.required<WordsFilterState>();
  readonly applied = output<WordsFilterState>();
  readonly closed = output<void>();

  readonly orderOptions = ORDER_OPTIONS;
  readonly testamentOptions = TESTAMENT_OPTIONS;
  readonly categories = CATEGORY_DEFINITIONS;
  readonly tags = TAG_DEFINITIONS;

  readonly readingOrder = signal<ReadingOrder>('daily');
  readonly testamentFilter = signal<TestamentFilter>('all');
  readonly bookNumberFilter = signal<number | null>(null);
  readonly selectedCategories = signal<string[]>([]);
  readonly selectedTags = signal<string[]>([]);
  readonly bookQuery = signal<string>('');

  readonly filteredBooks = computed(() => {
    const test = this.testamentFilter();
    const q = this.bookQuery().trim().toLowerCase();
    return BIBLE_BOOK_LIST.filter((b) => {
      if (test !== 'all' && b.testament !== test) return false;
      if (q && !b.name.toLowerCase().includes(q)) return false;
      return true;
    });
  });

  readonly selectedBookName = computed(() => {
    const num = this.bookNumberFilter();
    if (num === null) return 'All Books';
    return BIBLE_BOOK_LIST.find((b) => b.bookNumber === num)?.name ?? 'All Books';
  });

  readonly draftCount = computed(() =>
    countActiveFilters({
      readingOrder: this.readingOrder(),
      activeTopic: this.currentFilter().activeTopic,
      testamentFilter: this.testamentFilter(),
      bookNumberFilter: this.bookNumberFilter(),
      selectedCategories: this.selectedCategories(),
      selectedTags: this.selectedTags(),
    }),
  );

  ngOnInit(): void {
    const cur = this.currentFilter();
    this.readingOrder.set(cur.readingOrder);
    this.testamentFilter.set(cur.testamentFilter);
    this.bookNumberFilter.set(cur.bookNumberFilter);
    this.selectedCategories.set([...cur.selectedCategories]);
    this.selectedTags.set([...cur.selectedTags]);
  }

  setTestament(t: TestamentFilter): void {
    this.testamentFilter.set(t);
    const bookNum = this.bookNumberFilter();
    if (bookNum !== null) {
      const book = BIBLE_BOOK_LIST.find((b) => b.bookNumber === bookNum);
      if (book && t !== 'all' && book.testament !== t) {
        this.bookNumberFilter.set(null);
      }
    }
  }

  toggleCategory(id: string): void {
    this.selectedCategories.update((list) =>
      list.includes(id) ? list.filter((x) => x !== id) : [...list, id],
    );
  }

  toggleTag(tag: string): void {
    this.selectedTags.update((list) =>
      list.includes(tag) ? list.filter((x) => x !== tag) : [...list, tag],
    );
  }

  formatTag(tag: string): string {
    return tag
      .split('_')
      .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
      .join(' ');
  }

  resetAll(): void {
    this.readingOrder.set('daily');
    this.testamentFilter.set('all');
    this.bookNumberFilter.set(null);
    this.selectedCategories.set([]);
    this.selectedTags.set([]);
    this.bookQuery.set('');
  }

  apply(): void {
    this.applied.emit({
      readingOrder: this.readingOrder(),
      activeTopic: this.currentFilter().activeTopic,
      testamentFilter: this.testamentFilter(),
      bookNumberFilter: this.bookNumberFilter(),
      selectedCategories: this.selectedCategories(),
      selectedTags: this.selectedTags(),
    });
    this.closed.emit();
  }
}
