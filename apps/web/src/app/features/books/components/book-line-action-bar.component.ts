import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';
import { BookLine } from '../models/book.model';

const HIGHLIGHT_SWATCHES = ['#FEF08A', '#BBF7D0', '#BFDBFE', '#FBCFE8'];

@Component({
  selector: 'app-book-line-action-bar',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="line-action-bar">
      <div class="action-inner max-width-box">
        <div class="action-chips">
          <button type="button" class="pill-chip" (click)="copy.emit()">
            <span class="material-symbols-rounded">content_copy</span>
            Copy
          </button>
          <button type="button" class="pill-chip" (click)="share.emit()">
            <span class="material-symbols-rounded">share</span>
            Share
          </button>
        </div>

        <div class="swatches">
          @for (c of highlightColors; track c) {
            <button
              type="button"
              class="hl-swatch"
              [attr.aria-label]="'Highlight ' + c"
              [style.background-color]="c"
              (click)="highlightChanged.emit(c)"
            ></button>
          }
          <button
            type="button"
            class="pill-chip"
            (click)="highlightChanged.emit(null)"
          >
            Clear
          </button>
          <button
            type="button"
            class="icon-btn"
            aria-label="Close selection"
            (click)="closed.emit()"
          >
            <span class="material-symbols-rounded">close</span>
          </button>
        </div>
      </div>
    </div>
  `,
  styles: [
    `
      .line-action-bar {
        position: fixed;
        left: 0;
        right: 0;
        bottom: var(--shell-bottom-height);
        z-index: 36;
        background-color: var(--surface);
        border-top: 1px solid var(--surface-border);
        padding: 10px 0;
      }

      @media (min-width: 600px) {
        .line-action-bar {
          left: 0;
          bottom: 0;
        }
      }

      .action-inner {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        justify-content: space-between;
        gap: 10px;
      }

      .action-chips,
      .swatches {
        display: flex;
        align-items: center;
        gap: 8px;
        flex-wrap: wrap;
      }

      .hl-swatch {
        width: 24px;
        height: 24px;
        border-radius: var(--radius-pill);
        border: 1px solid var(--surface-border);
      }
    `,
  ],
})
export class BookLineActionBarComponent {
  readonly line = input.required<BookLine>();
  readonly copy = output<void>();
  readonly share = output<void>();
  readonly highlightChanged = output<string | null>();
  readonly closed = output<void>();

  readonly highlightColors = HIGHLIGHT_SWATCHES;
}
