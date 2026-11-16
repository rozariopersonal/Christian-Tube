import {
  ChangeDetectionStrategy,
  Component,
  computed,
  input,
  output,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { BibleBook } from '../models/bible.model';

@Component({
  selector: 'app-bible-sidebar',
  standalone: true,
  imports: [FormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <aside class="bible-sidebar" aria-label="Bible books and chapters">
      <div class="sidebar-header">
        <div class="sidebar-tabs">
          <button
            type="button"
            class="sidebar-tab"
            [class.active]="testament() === 'all'"
            (click)="testament.set('all')"
          >
            All
          </button>
          <button
            type="button"
            class="sidebar-tab"
            [class.active]="testament() === 'ot'"
            (click)="testament.set('ot')"
          >
            OT
          </button>
          <button
            type="button"
            class="sidebar-tab"
            [class.active]="testament() === 'nt'"
            (click)="testament.set('nt')"
          >
            NT
          </button>
        </div>
        <input
          type="search"
          class="sidebar-filter"
          [ngModel]="filter()"
          (ngModelChange)="filter.set($event)"
          placeholder="Filter books..."
          aria-label="Filter Bible books"
        />
      </div>

      <nav class="sidebar-list">
        @for (b of filteredBooks(); track b.bookNumber) {
          @let isExpanded = activeExpandedBook() === b.bookNumber;
          <div>
            <button
              type="button"
              class="sidebar-item"
              [class.active]="b.bookNumber === currentBookNumber()"
              (click)="toggleBook(b.bookNumber)"
            >
              <span class="sidebar-ch-title">{{ b.name }}</span>
              <span class="sidebar-count">{{ b.chapters }}</span>
            </button>
            @if (isExpanded) {
              <div class="sidebar-ch-grid">
                @for (ch of chaptersFor(b.chapters); track ch) {
                  <button
                    type="button"
                    class="sidebar-ch-btn"
                    [class.active]="
                      b.bookNumber === currentBookNumber() &&
                      ch === currentChapter()
                    "
                    (click)="selectChapter.emit({ bookNumber: b.bookNumber, chapter: ch })"
                  >
                    {{ ch }}
                  </button>
                }
              </div>
            }
          </div>
        }
      </nav>
    </aside>
  `,
  styles: [
    `
      .bible-sidebar {
        position: sticky;
        top: calc(var(--shell-top-offset) + var(--topbar-height));
        width: 268px;
        flex-shrink: 0;
        height: calc(100dvh - var(--shell-top-offset) - var(--topbar-height));
        display: flex;
        flex-direction: column;
        border-right: 1px solid var(--reader-border, var(--surface-border));
        background-color: color-mix(in srgb, var(--reader-bg, var(--bg)) 96%, var(--on-surface) 4%);
      }

      .sidebar-header {
        padding: 12px 12px 10px;
        border-bottom: 1px solid var(--reader-border, var(--surface-border));
        display: flex;
        flex-direction: column;
        gap: 8px;
      }

      .sidebar-tabs {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: 4px;
      }

      .sidebar-tab {
        padding: 5px 6px;
        border-radius: var(--radius-sm);
        font-size: 12px;
        font-weight: 700;
        color: var(--reader-muted, var(--on-surface-muted));
        background-color: var(--reader-bg, var(--bg));
        border: 1px solid var(--reader-border, var(--surface-border));
      }

      .sidebar-tab.active {
        background-color: var(--accent-soft);
        border-color: var(--accent);
        color: var(--accent);
      }

      .sidebar-filter {
        width: 100%;
        padding: 7px 10px;
        border-radius: var(--radius-sm);
        border: 1px solid var(--reader-border, var(--surface-border));
        background-color: var(--reader-bg, var(--bg));
        color: var(--reader-fg, var(--on-surface));
        font-size: 13px;
      }

      .sidebar-list {
        flex: 1;
        overflow-y: auto;
        padding: 8px;
        display: flex;
        flex-direction: column;
        gap: 2px;
      }

      .sidebar-item {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
        width: 100%;
        padding: 7px 10px;
        border-radius: var(--radius-sm);
        text-align: left;
        font-size: 13px;
        color: var(--reader-fg, var(--on-surface));
      }

      .sidebar-item:hover {
        background-color: color-mix(in srgb, var(--accent) 8%, transparent);
      }

      .sidebar-item.active {
        background-color: var(--accent-soft);
        color: var(--accent);
        font-weight: 700;
      }

      .sidebar-ch-title {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .sidebar-count {
        font-size: 11px;
        opacity: 0.65;
        font-variant-numeric: tabular-nums;
      }

      .sidebar-ch-grid {
        display: grid;
        grid-template-columns: repeat(5, minmax(0, 1fr));
        gap: 4px;
        padding: 6px 6px 10px;
      }

      .sidebar-ch-btn {
        height: 28px;
        border-radius: var(--radius-sm);
        border: 1px solid var(--reader-border, var(--surface-border));
        background-color: var(--reader-bg, var(--bg));
        color: var(--reader-fg, var(--on-surface));
        font-size: 12px;
        font-weight: 600;
        font-variant-numeric: tabular-nums;
      }

      .sidebar-ch-btn:hover {
        border-color: var(--accent);
        color: var(--accent);
      }

      .sidebar-ch-btn.active {
        background-color: var(--accent);
        border-color: var(--accent);
        color: #fff;
      }
    `,
  ],
})
export class BibleSidebarComponent {
  readonly books = input.required<BibleBook[]>();
  readonly currentBookNumber = input.required<number>();
  readonly currentChapter = input.required<number>();
  readonly selectChapter = output<{ bookNumber: number; chapter: number }>();

  readonly testament = signal<'all' | 'ot' | 'nt'>('all');
  readonly filter = signal<string>('');
  readonly manualExpanded = signal<number | null>(null);

  readonly activeExpandedBook = computed(
    () => this.manualExpanded() ?? this.currentBookNumber(),
  );

  readonly filteredBooks = computed(() => {
    const test = this.testament();
    const q = this.filter().trim().toLowerCase();
    return this.books().filter((b) => {
      if (test === 'ot' && b.bookNumber > 39) return false;
      if (test === 'nt' && b.bookNumber <= 39) return false;
      if (q && !b.name.toLowerCase().includes(q)) return false;
      return true;
    });
  });

  toggleBook(bookNumber: number): void {
    this.manualExpanded.set(
      this.activeExpandedBook() === bookNumber ? -1 : bookNumber,
    );
  }

  chaptersFor(count: number): number[] {
    return Array.from({ length: count }, (_, i) => i + 1);
  }
}
