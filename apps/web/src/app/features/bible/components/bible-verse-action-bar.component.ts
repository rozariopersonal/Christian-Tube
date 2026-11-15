import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';
import { BibleVerse } from '../models/bible.model';

const HIGHLIGHT_SWATCHES = ['#FEF08A', '#BBF7D0', '#BFDBFE', '#FBCFE8'];

@Component({
  selector: 'app-bible-verse-action-bar',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="verse-action-bar">
      <div class="action-inner max-width-box">
        <div class="action-chips">
          <button type="button" class="pill-chip" (click)="copy.emit()">
            <span class="material-symbols-rounded">content_copy</span>
            Copy
          </button>
          <button
            type="button"
            class="pill-chip"
            [class.active]="isBookmarked()"
            (click)="toggleBookmark.emit()"
          >
            <span class="material-symbols-rounded">bookmark</span>
            Bookmark
          </button>
          <button type="button" class="pill-chip" (click)="openNote.emit()">
            <span class="material-symbols-rounded">edit_note</span>
            Note
          </button>
          @if (crossRefCount() > 0) {
            <button type="button" class="pill-chip active" (click)="openCrossRefs.emit()">
              Cross-Refs ({{ crossRefCount() }})
            </button>
          }
          @if (studyTermCount() > 0) {
            <button type="button" class="pill-chip active" (click)="openStudy.emit()">
              Study ({{ studyTermCount() }})
            </button>
          }
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
            aria-label="Close verse actions"
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
      .verse-action-bar {
        position: fixed;
        left: 0;
        right: 0;
        bottom: var(--shell-bottom-height);
        z-index: 35;
        background-color: var(--surface);
        border-top: 1px solid var(--surface-border);
        padding: 10px 0;
      }

      @media (min-width: 600px) {
        .verse-action-bar {
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
export class BibleVerseActionBarComponent {
  readonly verse = input.required<BibleVerse>();
  readonly isBookmarked = input<boolean>(false);
  readonly crossRefCount = input<number>(0);
  readonly studyTermCount = input<number>(0);

  readonly copy = output<void>();
  readonly toggleBookmark = output<void>();
  readonly openNote = output<void>();
  readonly openCrossRefs = output<void>();
  readonly openStudy = output<void>();
  readonly highlightChanged = output<string | null>();
  readonly closed = output<void>();

  readonly highlightColors = HIGHLIGHT_SWATCHES;
}
