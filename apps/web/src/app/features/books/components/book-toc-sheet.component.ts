import {
  ChangeDetectionStrategy,
  Component,
  computed,
  input,
  output,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';
import { BookTocChapter } from '../models/book.model';

@Component({
  selector: 'app-book-toc-sheet',
  standalone: true,
  imports: [FormsModule, ModalSheetComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-modal-sheet title="Table of Contents" (closed)="closed.emit()">
      <div class="sheet-search">
        <span class="material-symbols-rounded">search</span>
        <input
          type="search"
          placeholder="Filter chapters..."
          [ngModel]="search()"
          (ngModelChange)="search.set($event)"
        />
      </div>

      <div class="toc-list">
        @for (ch of filteredChapters(); track ch.chapterIndex) {
          @let active = ch.chapterIndex === currentChapter();
          <button
            type="button"
            class="toc-row"
            [class.active]="active"
            (click)="chapterSelected.emit(ch.chapterIndex)"
          >
            <span class="toc-idx">{{ ch.chapterIndex }}</span>
            <span class="toc-title">{{ ch.title }}</span>
            @if (ch.startPage) {
              <span class="toc-pages">
                p. {{ ch.startPage }}{{ ch.endPage && ch.endPage > ch.startPage ? '–' + ch.endPage : '' }}
              </span>
            }
          </button>
        }
      </div>
    </app-modal-sheet>
  `,
  styles: [
    `
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

      .toc-list {
        display: flex;
        flex-direction: column;
        gap: 6px;
        max-height: 58dvh;
        overflow-y: auto;
      }

      .toc-row {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 10px 12px;
        border-radius: var(--radius-md);
        background-color: var(--surface-variant);
        border: 1px solid transparent;
        text-align: left;
        font-size: 14px;
      }

      .toc-row.active {
        background-color: var(--accent-soft);
        border-color: var(--accent);
        color: var(--accent);
        font-weight: 600;
      }

      .toc-idx {
        width: 26px;
        height: 26px;
        border-radius: var(--radius-pill);
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        display: grid;
        place-items: center;
        font-size: 12px;
        font-weight: 700;
        flex-shrink: 0;
      }

      .toc-title {
        flex: 1;
        min-width: 0;
        line-height: 1.35;
      }

      .toc-pages {
        font-size: 11px;
        color: var(--on-surface-muted);
        white-space: nowrap;
        flex-shrink: 0;
      }
    `,
  ],
})
export class BookTocSheetComponent {
  readonly chapters = input.required<BookTocChapter[]>();
  readonly currentChapter = input.required<number>();
  readonly chapterSelected = output<number>();
  readonly closed = output<void>();

  readonly search = signal<string>('');

  readonly filteredChapters = computed(() => {
    const q = this.search().trim().toLowerCase();
    if (!q) return this.chapters();
    return this.chapters().filter(
      (c) =>
        c.title.toLowerCase().includes(q) ||
        String(c.chapterIndex).includes(q),
    );
  });
}
