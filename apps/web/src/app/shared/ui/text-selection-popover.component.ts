import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';
import { TextSelectionAnchor } from './text-highlight.util';

const SWATCHES = ['#FEF08A', '#BBF7D0', '#BFDBFE', '#FBCFE8'];

@Component({
  selector: 'app-text-selection-popover',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div
      class="sel-popover"
      [style.top.px]="anchor().top"
      [style.left.px]="anchor().left"
      (mousedown)="$event.preventDefault()"
    >
      @for (c of swatches; track c) {
        <button
          type="button"
          class="swatch-btn"
          [style.background-color]="c"
          [attr.aria-label]="'Highlight ' + c"
          title="Highlight selection"
          (click)="highlight.emit(c)"
        ></button>
      }
      <button
        type="button"
        class="pop-btn"
        title="Clear highlight"
        aria-label="Clear highlight"
        (click)="clear.emit()"
      >
        <span class="material-symbols-rounded">format_color_reset</span>
      </button>
      <span class="pop-sep" aria-hidden="true"></span>
      <button
        type="button"
        class="pop-btn"
        title="Define"
        aria-label="Define"
        (click)="define.emit()"
      >
        <span class="material-symbols-rounded">dictionary</span>
      </button>
      <button
        type="button"
        class="pop-btn"
        title="Copy"
        aria-label="Copy"
        (click)="copy.emit()"
      >
        <span class="material-symbols-rounded">content_copy</span>
      </button>
    </div>
  `,
  styles: [
    `
      .sel-popover {
        position: fixed;
        transform: translateX(-50%);
        z-index: 65;
        display: inline-flex;
        align-items: center;
        gap: 6px;
        height: 38px;
        padding: 0 10px;
        border-radius: var(--radius-pill);
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        box-shadow: 0 8px 24px rgba(0, 0, 0, 0.2);
      }

      .swatch-btn {
        width: 20px;
        height: 20px;
        border-radius: var(--radius-pill);
        border: 1px solid rgba(0, 0, 0, 0.14);
      }

      .swatch-btn:hover {
        transform: scale(1.12);
      }

      .pop-sep {
        width: 1px;
        height: 18px;
        background-color: var(--surface-border);
      }

      .pop-btn {
        width: 26px;
        height: 26px;
        border-radius: var(--radius-pill);
        display: grid;
        place-items: center;
        color: var(--on-surface);
      }

      .pop-btn:hover {
        background-color: var(--surface-variant);
      }

      .pop-btn .material-symbols-rounded {
        font-size: 16px;
      }
    `,
  ],
})
export class TextSelectionPopoverComponent {
  readonly anchor = input.required<TextSelectionAnchor>();
  readonly highlight = output<string>();
  readonly clear = output<void>();
  readonly define = output<void>();
  readonly copy = output<void>();

  readonly swatches = SWATCHES;
}
