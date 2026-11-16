import {
  ChangeDetectionStrategy,
  Component,
  input,
  output,
  signal,
} from '@angular/core';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';
import {
  BookBookmark,
  BookHighlight,
} from '../services/book-highlights.service';

@Component({
  selector: 'app-book-highlights-sheet',
  standalone: true,
  imports: [ModalSheetComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-modal-sheet title="Notebook" (closed)="closed.emit()">
      <div class="nb-tabs">
        <button
          type="button"
          class="nb-tab"
          [class.active]="tab() === 'highlights'"
          (click)="tab.set('highlights')"
        >
          Highlights & Notes ({{ highlights().length }})
        </button>
        <button
          type="button"
          class="nb-tab"
          [class.active]="tab() === 'bookmarks'"
          (click)="tab.set('bookmarks')"
        >
          Bookmarks ({{ bookmarks().length }})
        </button>
      </div>

      @if (tab() === 'highlights') {
        @if (highlights().length === 0) {
          <p class="empty-msg">
            No highlights yet. Tap any paragraph to highlight or add a note.
          </p>
        } @else {
          <div class="hl-list">
            @for (h of highlights(); track h.key) {
              <div class="hl-row">
                <button
                  type="button"
                  class="hl-body"
                  (click)="jumpTo.emit({ chapter: h.chapterIndex, line: h.line })"
                >
                  <span class="hl-meta">
                    <span class="hl-dot" [style.background-color]="h.color"></span>
                    Chapter {{ h.chapterIndex }}
                  </span>
                  <p class="hl-text">{{ h.text }}</p>
                  @if (h.note) {
                    <p class="hl-note">{{ h.note }}</p>
                  }
                </button>
                <button
                  type="button"
                  class="icon-btn"
                  title="Remove highlight"
                  (click)="removed.emit(h)"
                >
                  <span class="material-symbols-rounded">delete</span>
                </button>
              </div>
            }
          </div>
        }
      } @else {
        @if (bookmarks().length === 0) {
          <p class="empty-msg">
            No bookmarks yet. Tap the bookmark icon in the top bar.
          </p>
        } @else {
          <div class="hl-list">
            @for (bm of bookmarks(); track bm.key) {
              <div class="hl-row">
                <button
                  type="button"
                  class="hl-body"
                  (click)="jumpTo.emit({ chapter: bm.chapterIndex, line: 0 })"
                >
                  <span class="hl-meta">Chapter {{ bm.chapterIndex }}</span>
                  <p class="hl-text">{{ bm.chapterTitle || 'Chapter ' + bm.chapterIndex }}</p>
                </button>
                <button
                  type="button"
                  class="icon-btn"
                  title="Remove bookmark"
                  (click)="bookmarkRemoved.emit(bm)"
                >
                  <span class="material-symbols-rounded">delete</span>
                </button>
              </div>
            }
          </div>
        }
      }
    </app-modal-sheet>
  `,
  styles: [
    `
      .nb-tabs {
        display: grid;
        grid-template-columns: repeat(2, 1fr);
        border-bottom: 1px solid var(--surface-border);
      }

      .nb-tab {
        padding: 10px 6px;
        font-size: 13px;
        font-weight: 700;
        color: var(--on-surface-muted);
        border-bottom: 2px solid transparent;
      }

      .nb-tab.active {
        color: var(--accent);
        border-bottom-color: var(--accent);
      }

      .empty-msg {
        padding: 24px 0;
        text-align: center;
        color: var(--on-surface-muted);
      }

      .hl-list {
        display: flex;
        flex-direction: column;
        gap: 8px;
        max-height: 55dvh;
        overflow-y: auto;
      }

      .hl-row {
        display: flex;
        align-items: flex-start;
        gap: 8px;
        padding: 10px 12px;
        border-radius: var(--radius-md);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
      }

      .hl-body {
        flex: 1;
        min-width: 0;
        text-align: left;
      }

      .hl-meta {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        font-size: 12px;
        font-weight: 700;
        color: var(--on-surface-muted);
      }

      .hl-dot {
        width: 10px;
        height: 10px;
        border-radius: var(--radius-pill);
      }

      .hl-text {
        margin: 4px 0 0;
        font-size: 13px;
        line-height: 1.45;
        display: -webkit-box;
        -webkit-line-clamp: 3;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }

      .hl-note {
        margin: 6px 0 0;
        padding: 6px 8px;
        border-left: 2px solid var(--accent);
        background-color: var(--accent-soft);
        border-radius: 4px;
        font-size: 12px;
      }
    `,
  ],
})
export class BookHighlightsSheetComponent {
  readonly highlights = input.required<BookHighlight[]>();
  readonly bookmarks = input<BookBookmark[]>([]);
  readonly jumpTo = output<{ chapter: number; line: number }>();
  readonly removed = output<BookHighlight>();
  readonly bookmarkRemoved = output<BookBookmark>();
  readonly closed = output<void>();

  readonly tab = signal<'highlights' | 'bookmarks'>('highlights');
}
