import {
  ChangeDetectionStrategy,
  Component,
  HostListener,
  inject,
  input,
  output,
  signal,
} from '@angular/core';
import { HighlightUsageService } from '../services/highlight-usage.service';
import {
  ACCENT_COUNT,
  HIGHLIGHT_PALETTE,
  HighlightSwatch,
  SHADES_PER_ACCENT,
  contrastColorFor,
  migrateLegacyWebHex,
} from './highlight-palette';
import { InlineToolbarAnchor } from './text-highlight.util';

export const READER_HIGHLIGHT_SWATCHES = HIGHLIGHT_PALETTE.map((s) => s.hex);

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
      [class.expanded]="paletteExpanded()"
      [style.top.px]="anchor().top"
      [style.left.px]="anchor().left"
      (mousedown)="$event.preventDefault()"
      (click)="$event.stopPropagation()"
    >
      @if (paletteExpanded() && anchor().placement !== 'below') {
        <div class="palette-panel top" role="group" aria-label="All highlight colours">
          @for (row of paletteRows; track $index) {
            <div class="palette-row">
              @for (s of row; track s.index) {
                <button
                  type="button"
                  class="swatch-btn"
                  [class.active]="isColorActive(s.hex)"
                  [style.background-color]="s.hex"
                  [style.color]="contrastFor(s.hex)"
                  [attr.aria-label]="'Highlight ' + s.name"
                  [title]="s.name"
                  (click)="pickSwatch(s)"
                >
                  @if (isColorActive(s.hex)) {
                    <span class="material-symbols-rounded swatch-check" aria-hidden="true">check</span>
                  }
                </button>
              }
            </div>
          }
        </div>
      }

      <div class="action-row">
        <div class="pop-group">
          @for (s of topSwatches(); track s.index) {
            <button
              type="button"
              class="swatch-btn"
              [class.active]="isColorActive(s.hex)"
              [style.background-color]="s.hex"
              [style.color]="contrastFor(s.hex)"
              [attr.aria-label]="'Highlight ' + s.name"
              [title]="s.name"
              (click)="pickSwatch(s)"
            >
              @if (isColorActive(s.hex)) {
                <span class="material-symbols-rounded swatch-check" aria-hidden="true">check</span>
              }
            </button>
          }
          <button
            type="button"
            class="pop-btn expand-btn"
            [class.active]="paletteExpanded()"
            [attr.aria-expanded]="paletteExpanded()"
            [title]="paletteExpanded() ? 'Fewer colours' : 'More colours'"
            [attr.aria-label]="paletteExpanded() ? 'Fewer colours' : 'More colours'"
            (click)="paletteExpanded.set(!paletteExpanded())"
          >
            <span class="material-symbols-rounded">
              {{ paletteExpanded() ? 'expand_less' : 'expand_more' }}
            </span>
          </button>
          <button
            type="button"
            class="pop-btn"
            title="Clear highlight"
            aria-label="Clear highlight"
            (click)="onClear()"
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

      @if (paletteExpanded() && anchor().placement === 'below') {
        <div class="palette-panel bottom" role="group" aria-label="All highlight colours">
          @for (row of paletteRows; track $index) {
            <div class="palette-row">
              @for (s of row; track s.index) {
                <button
                  type="button"
                  class="swatch-btn"
                  [class.active]="isColorActive(s.hex)"
                  [style.background-color]="s.hex"
                  [style.color]="contrastFor(s.hex)"
                  [attr.aria-label]="'Highlight ' + s.name"
                  [title]="s.name"
                  (click)="pickSwatch(s)"
                >
                  @if (isColorActive(s.hex)) {
                    <span class="material-symbols-rounded swatch-check" aria-hidden="true">check</span>
                  }
                </button>
              }
            </div>
          }
        </div>
      }
    </div>
  `,
  styles: [
    `
      .sel-popover {
        position: fixed;
        transform: translate(-50%, -100%);
        z-index: 65;
        display: flex;
        flex-direction: column;
        align-items: center;
        max-width: min(560px, calc(100vw - 16px));
        width: max-content;
        border-radius: 20px;
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        box-shadow: 0 10px 28px rgba(0, 0, 0, 0.24);
        overflow: hidden;
      }

      .sel-popover.below {
        transform: translate(-50%, 0);
      }

      .action-row {
        display: inline-flex;
        align-items: center;
        flex-wrap: nowrap;
        gap: 6px;
        min-height: 40px;
        max-width: 100%;
        overflow-x: auto;
        scrollbar-width: none;
        padding: 6px 10px;
      }

      .action-row::-webkit-scrollbar {
        display: none;
      }

      .palette-panel {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 6px;
        padding: 10px 12px;
        width: 100%;
        background-color: var(--surface);
      }

      .palette-panel.top {
        border-bottom: 1px solid var(--surface-border);
      }

      .palette-panel.bottom {
        border-top: 1px solid var(--surface-border);
      }

      .palette-row {
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 8px;
      }

      .pop-group {
        display: inline-flex;
        align-items: center;
        flex-wrap: nowrap;
        gap: 4px;
        flex-shrink: 0;
      }

      .swatch-btn {
        width: 22px;
        height: 22px;
        border-radius: var(--radius-pill);
        border: 1.5px solid rgba(0, 0, 0, 0.16);
        display: grid;
        place-items: center;
        flex-shrink: 0;
        transition: transform 120ms ease, border-color 120ms ease;
      }

      .swatch-btn:hover {
        transform: scale(1.12);
      }

      .swatch-btn.active {
        border-color: var(--on-surface);
        box-shadow: 0 0 0 1.5px var(--on-surface);
      }

      .swatch-check {
        font-size: 13px;
        font-weight: 700;
        line-height: 1;
      }

      .pop-sep {
        width: 1px;
        height: 20px;
        background-color: var(--surface-border);
        flex-shrink: 0;
      }

      .pop-btn {
        width: 28px;
        height: 28px;
        border-radius: var(--radius-pill);
        display: grid;
        place-items: center;
        flex-shrink: 0;
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
        flex-shrink: 0;
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
  private readonly usage = inject(HighlightUsageService);

  readonly anchor = input.required<InlineToolbarAnchor>();
  readonly activeColor = input<string | null>(null);
  readonly showBookmark = input<boolean>(false);
  readonly isBookmarked = input<boolean>(false);
  readonly showNote = input<boolean>(false);
  readonly hasNote = input<boolean>(false);
  readonly showCompare = input<boolean>(false);
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
  readonly copy = output<void>();
  readonly share = output<void>();
  readonly openCrossRefs = output<void>();
  readonly openStudy = output<void>();
  readonly closed = output<void>();

  readonly paletteExpanded = signal(false);
  readonly topSwatches = signal<HighlightSwatch[]>(this.usage.topSwatches(3));

  readonly paletteRows: readonly (readonly HighlightSwatch[])[] = Array.from(
    { length: SHADES_PER_ACCENT },
    (_, shade) =>
      HIGHLIGHT_PALETTE.slice(shade * ACCENT_COUNT, (shade + 1) * ACCENT_COUNT),
  );

  contrastFor(hex: string): string {
    return contrastColorFor(hex);
  }

  isColorActive(swatchHex: string): boolean {
    const active = this.activeColor();
    if (!active) return false;
    const normalizedActive = migrateLegacyWebHex(active).slice(0, 7).toUpperCase();
    return normalizedActive === swatchHex.toUpperCase();
  }

  pickSwatch(swatch: HighlightSwatch): void {
    if (this.isColorActive(swatch.hex)) {
      this.paletteExpanded.set(false);
      this.clear.emit();
      return;
    }
    this.usage.record(swatch.index);
    this.paletteExpanded.set(false);
    this.highlight.emit(swatch.hex);
  }

  onClear(): void {
    this.paletteExpanded.set(false);
    this.clear.emit();
  }

  @HostListener('document:keydown.escape')
  onEscape(): void {
    if (this.paletteExpanded()) {
      this.paletteExpanded.set(false);
    }
  }
}
