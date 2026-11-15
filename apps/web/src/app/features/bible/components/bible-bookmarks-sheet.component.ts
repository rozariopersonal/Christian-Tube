import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';
import { BibleBookmark } from '../models/bible.model';

@Component({
  selector: 'app-bible-bookmarks-sheet',
  standalone: true,
  imports: [ModalSheetComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-modal-sheet title="Bookmarks" (closed)="closed.emit()">
      @if (bookmarks().length === 0) {
        <p class="status-msg">No bookmarks yet. Tap any verse to bookmark it.</p>
      } @else {
        <div class="ref-list">
          @for (bm of bookmarks(); track bm.key) {
            <button
              type="button"
              class="ref-row bm-row"
              (click)="jumpTo.emit({ bookNumber: bm.bookNumber, chapter: bm.chapter })"
            >
              <div>
                <strong>{{ bm.bookName }} {{ bm.chapter }}:{{ bm.verse }}</strong>
                <p class="bm-text">{{ bm.text }}</p>
              </div>
            </button>
          }
        </div>
      }
    </app-modal-sheet>
  `,
  styles: [
    `
      .status-msg {
        padding: 20px 0;
        text-align: center;
        color: var(--on-surface-muted);
      }

      .ref-list {
        display: flex;
        flex-direction: column;
        gap: 8px;
        max-height: 55dvh;
        overflow-y: auto;
      }

      .ref-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 10px 12px;
        border-radius: var(--radius-sm);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        text-align: left;
      }

      .bm-row {
        flex-direction: column;
        align-items: flex-start;
      }

      .bm-text {
        margin: 4px 0 0;
        font-size: 13px;
        color: var(--on-surface-muted);
      }
    `,
  ],
})
export class BibleBookmarksSheetComponent {
  readonly bookmarks = input.required<BibleBookmark[]>();
  readonly jumpTo = output<{ bookNumber: number; chapter: number }>();
  readonly closed = output<void>();
}
