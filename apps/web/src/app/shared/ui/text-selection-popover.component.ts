import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';
import { InlineToolbarAnchor } from './text-highlight.util';

export const READER_HIGHLIGHT_SWATCHES = ['#FEF08A', '#BBF7D0', '#BFDBFE', '#FBCFE8'];

@Component({
  selector: 'app-text-selection-popover',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div
      class="sel-popover"
      role="toolbar"
      aria-label="Reader actions"
      [class.below]="anchor().placement === 'below'"
      [style.top.px]="anchor().top"
      [style.left.px]="anchor().left"
      (mousedown)="$event.preventDefault()"
      (click)="$event.stopPropagation()"
    >
      <div class="pop-group">
        @for (c of swatches; track c) {
          <button
            type="button"
            class="swatch-btn"
            [class.active]="isColorActive(c)"
            [style.background-color]="c"
            [attr.aria-label]="'Highlight ' + c"
            title="Highlight"
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
      </div>

      <span class="pop-sep" aria-hidden="true"></span>

      <div class="pop-group">
        @if (showBookmark()) {
          <button
            type="button"
            class="pop-btn"
            [class.active]="isBookmarked()"
            title="Bookmark"
            aria-label="Bookmark"
            (click)="toggleBookmark.emit()"
          >
            <span class="material-symbols-rounded">bookmark</span>
          </button>
        }
        @if (showNote()) {
          <button
            type="button"
            class="pop-btn"
            [class.active]="hasNote()"
            title="Note"
            aria-label="Note"
            (click)="openNote.emit()"
          >
            <span class="material-symbols-rounded">edit_note</span>
          </button>
        }
        @if (showCompare()) {
          <button
            type="button"
            class="pop-btn"
            title="Compare"
            aria-label="Compare"
            (click)="compare.emit()"
          >
            <span class="material-symbols-rounded">compare_arrows</span>
          </button>
        }
        @if (showDefine()) {
          <button
            type="button"
            class="pop-btn"
            title="Define"
            aria-label="Define"
            (click)="define.emit()"
          >
            <span class="material-symbols-rounded">dictionary</span>
          </button>
        }
        @if (showCopy()) {
          <button
            type="button"
            class="pop-btn"
            title="Copy"
            aria-label="Copy"
            (click)="copy.emit()"
          >
            <span class="material-symbols-rounded">content_copy</span>
          </button>
        }
        @if (showShare()) {
          <button
            type="button"
            class="pop-btn"
            title="Share"
            aria-label="Share"
            (click)="share.emit()"
          >
            <span class="material-symbols-rounded">share</span>
          </button>
        }
        @if (crossRefCount() > 0) {
          <button
            type="button"
            class="pop-chip"
            title="Cross-References"
            aria-label="Cross-Refs"
            (click)="openCrossRefs.emit()"
          >
            ↗ {{ crossRefCount() }}
          </button>
        }
        @if (studyTermCount() > 0) {
          <button
            type="button"
            class="pop-chip"
            title="Study & Lexicon"
            aria-label="Study"
            (click)="openStudy.emit()"
          >
            <span class="material-symbols-rounded chip-ic">school</span>
            {{ studyTermCount() }}
          </button>
        }
        @if (showClose()) {
          <button
            type="button"
            class="pop-btn close-btn"
            title="Close"
            aria-label="Close"
            (click)="closed.emit()"
          >
            <span class="material-symbols-rounded">close</span>
          </button>
        }
      </div>
    </div>
  `,
  styles: [
    `
      .sel-popover {
        position: fixed;
        transform: translate(-50%, -100%);
        z-index: 65;
        display: inline-flex;
        flex-wrap: wrap;
        align-items: center;
        justify-content: center;
        gap: 6px;
        min-height: 40px;
        max-width: min(540px, calc(100vw - 16px));
        width: max-content;
        padding: 6px 10px;
        border-radius: 20px;
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        box-shadow: 0 10px 28px rgba(0, 0, 0, 0.24);
      }

      .sel-popover.below {
        transform: translate(-50%, 0);
      }

      .pop-group {
        display: inline-flex;
        align-items: center;
        flex-wrap: wrap;
        gap: 4px;
      }

      .swatch-btn {
        width: 22px;
        height: 22px;
        border-radius: var(--radius-pill);
        border: 1.5px solid rgba(0, 0, 0, 0.16);
        transition: transform 120ms ease, border-color 120ms ease;
      }

      .swatch-btn:hover {
        transform: scale(1.12);
      }

      .swatch-btn.active {
        border-color: var(--on-surface);
        box-shadow: 0 0 0 1.5px var(--on-surface);
      }

      .pop-sep {
        width: 1px;
        height: 20px;
        background-color: var(--surface-border);
      }

      .pop-btn {
        width: 28px;
        height: 28px;
        border-radius: var(--radius-pill);
        display: grid;
        place-items: center;
        color: var(--on-surface);
        transition: background-color 120ms ease, color 120ms ease;
      }

      .pop-btn:hover {
        background-color: var(--surface-variant);
      }

      .pop-btn.active {
        color: var(--accent);
        background-color: var(--accent-soft, var(--surface-variant));
      }

      .pop-btn .material-symbols-rounded {
        font-size: 17px;
      }

      .pop-chip {
        height: 26px;
        padding: 0 8px;
        border-radius: var(--radius-pill);
        display: inline-flex;
        align-items: center;
        gap: 3px;
        font-size: 0.72rem;
        font-weight: 700;
        color: var(--accent);
        background-color: var(--accent-soft, var(--surface-variant));
        border: 1px solid var(--surface-border);
      }

      .pop-chip .chip-ic {
        font-size: 14px;
      }
    `,
  ],
})
export class TextSelectionPopoverComponent {
  readonly anchor = input.required<InlineToolbarAnchor>();
  readonly activeColor = input<string | null>(null);
  readonly showBookmark = input<boolean>(false);
  readonly isBookmarked = input<boolean>(false);
  readonly showNote = input<boolean>(false);
  readonly hasNote = input<boolean>(false);
  readonly showCompare = input<boolean>(false);
  readonly showDefine = input<boolean>(true);
  readonly showCopy = input<boolean>(true);
  readonly showShare = input<boolean>(true);
  readonly showClose = input<boolean>(true);
  readonly crossRefCount = input<number>(0);
  readonly studyTermCount = input<number>(0);

  readonly highlight = output<string>();
  readonly clear = output<void>();
  readonly toggleBookmark = output<void>();
  readonly openNote = output<void>();
  readonly compare = output<void>();
  readonly define = output<void>();
  readonly copy = output<void>();
  readonly share = output<void>();
  readonly openCrossRefs = output<void>();
  readonly openStudy = output<void>();
  readonly closed = output<void>();

  readonly swatches = READER_HIGHLIGHT_SWATCHES;

  isColorActive(swatch: string): boolean {
    const active = this.activeColor();
    if (!active) return false;
    return active.slice(0, 7).toUpperCase() === swatch.toUpperCase();
  }
}
