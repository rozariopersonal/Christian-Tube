import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';
import { BookHighlight } from '../services/book-highlights.service';

@Component({
  selector: 'app-book-highlights-sheet',
  standalone: true,
  imports: [ModalSheetComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-modal-sheet title="Highlights" (closed)="closed.emit()">
      @if (highlights().length === 0) {
        <p class="empty-msg">No highlights yet. Tap any paragraph to highlight it.</p>
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
    </app-modal-sheet>
  `,
  styles: [
    `
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
    `,
  ],
})
export class BookHighlightsSheetComponent {
  readonly highlights = input.required<BookHighlight[]>();
  readonly jumpTo = output<{ chapter: number; line: number }>();
  readonly removed = output<BookHighlight>();
  readonly closed = output<void>();
}
