import {
  ChangeDetectionStrategy,
  Component,
  ElementRef,
  HostListener,
  computed,
  inject,
  input,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ScreenClassService } from '../../core/layout/screen-class.service';
import {
  LETTER_SPACING_PRESETS,
  LINE_HEIGHT_PRESETS,
  ReaderAppearanceService,
} from '../../core/services/reader-appearance.service';

@Component({
  selector: 'app-reader-columns-toggle',
  standalone: true,
  imports: [FormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="reader-toolbar-seg">
      <div class="cols-seg" role="group" aria-label="Reader layout and columns">
        @if (options().length > 1) {
          <span class="material-symbols-rounded cols-icon" aria-hidden="true">view_column</span>
          @for (c of options(); track c) {
            <button
              type="button"
              class="col-btn"
              [class.active]="activeCols() === c"
              [title]="c + (c === 1 ? ' column' : ' columns')"
              (click)="appearance.setBookColumns(c)"
            >
              {{ c }}
            </button>
          }
        }

        @if (activeCols() === 1) {
          @if (options().length > 1) {
            <span class="seg-divider" aria-hidden="true"></span>
          }
          <button
            type="button"
            class="layout-btn"
            [class.active]="appearance.singleColPaginated()"
            [title]="
              appearance.singleColPaginated()
                ? 'Paginated pages (click for vertical scroll)'
                : 'Vertical scroll (click for paginated pages)'
            "
            aria-label="Toggle single-column pagination"
            (click)="appearance.toggleSingleColPaginated()"
          >
            <span class="material-symbols-rounded">menu_book</span>
          </button>
        }

        @if (showLayoutToggle()) {
          @if (options().length > 1 || activeCols() === 1) {
            <span class="seg-divider" aria-hidden="true"></span>
          }
          <button
            type="button"
            class="layout-btn"
            [class.active]="appearance.bibleLayout() === 'verses'"
            title="Verse by verse"
            aria-label="Verse by verse"
            (click)="appearance.setBibleLayout('verses')"
          >
            <span class="material-symbols-rounded">format_list_numbered</span>
          </button>
          <button
            type="button"
            class="layout-btn"
            [class.active]="appearance.bibleLayout() === 'paragraph'"
            title="Paragraph flow"
            aria-label="Paragraph flow"
            (click)="appearance.setBibleLayout('paragraph')"
          >
            <span class="material-symbols-rounded">subject</span>
          </button>
        }

        @if (!hideSpacing()) {
          @if (options().length > 1 || activeCols() === 1 || showLayoutToggle()) {
            <span class="seg-divider" aria-hidden="true"></span>
          }
          <button
            type="button"
            class="layout-btn spacing-trigger-btn"
            [class.active]="spacingOpen() === 'line' || appearance.lineHeight() !== 1.65"
            [title]="'Line spacing (' + appearance.lineHeight() + ')'"
            aria-label="Line spacing"
            [attr.aria-expanded]="spacingOpen() === 'line'"
            (click)="toggleSpacingPopover('line', $event)"
          >
            <span class="material-symbols-rounded">format_line_spacing</span>
          </button>
          <button
            type="button"
            class="layout-btn spacing-trigger-btn"
            [class.active]="spacingOpen() === 'letter' || appearance.letterSpacing() !== 0"
            [title]="'Letter spacing (' + appearance.formatLetterSpacing() + ')'"
            aria-label="Letter spacing"
            [attr.aria-expanded]="spacingOpen() === 'letter'"
            (click)="toggleSpacingPopover('letter', $event)"
          >
            <span class="material-symbols-rounded">space_bar</span>
          </button>
        }
      </div>

      @if (spacingOpen() !== null) {
        <div
          class="spacing-popover"
          role="dialog"
          aria-label="Line and letter spacing"
          (click)="$event.stopPropagation()"
        >
          <section class="spacing-block" [class.focused]="spacingOpen() === 'line'">
            <div class="spacing-head">
              <span class="spacing-title">Line Spacing</span>
              <div class="spacing-controls">
                <span class="spacing-val">{{ appearance.lineHeight() }}</span>
                <button
                  type="button"
                  class="step-mini-btn"
                  aria-label="Decrease line spacing"
                  title="Decrease line spacing"
                  [disabled]="appearance.lineHeight() <= 1.3"
                  (click)="appearance.stepLineHeight(-0.05)"
                >
                  −
                </button>
                <button
                  type="button"
                  class="step-mini-btn"
                  aria-label="Increase line spacing"
                  title="Increase line spacing"
                  [disabled]="appearance.lineHeight() >= 2.2"
                  (click)="appearance.stepLineHeight(0.05)"
                >
                  +
                </button>
              </div>
            </div>
            <div class="preset-row">
              @for (p of linePresets; track p.id) {
                <button
                  type="button"
                  class="preset-chip"
                  [class.active]="Math.abs(appearance.lineHeight() - p.value) < 0.03"
                  (click)="appearance.setLineHeight(p.value)"
                >
                  {{ p.label }}
                </button>
              }
            </div>
            <input
              type="range"
              class="spacing-range"
              min="1.3"
              max="2.2"
              step="0.05"
              aria-label="Line spacing slider"
              [ngModel]="appearance.lineHeight()"
              (ngModelChange)="appearance.setLineHeight($event)"
            />
          </section>

          <section class="spacing-block" [class.focused]="spacingOpen() === 'letter'">
            <div class="spacing-head">
              <span class="spacing-title">Letter Spacing</span>
              <div class="spacing-controls">
                <span class="spacing-val">{{ appearance.formatLetterSpacing() }}</span>
                <button
                  type="button"
                  class="step-mini-btn"
                  aria-label="Decrease letter spacing"
                  title="Decrease letter spacing"
                  [disabled]="appearance.letterSpacing() <= -0.04"
                  (click)="appearance.stepLetterSpacing(-0.01)"
                >
                  −
                </button>
                <button
                  type="button"
                  class="step-mini-btn"
                  aria-label="Increase letter spacing"
                  title="Increase letter spacing"
                  [disabled]="appearance.letterSpacing() >= 0.12"
                  (click)="appearance.stepLetterSpacing(0.01)"
                >
                  +
                </button>
              </div>
            </div>
            <div class="preset-row">
              @for (p of letterPresets; track p.id) {
                <button
                  type="button"
                  class="preset-chip"
                  [class.active]="Math.abs(appearance.letterSpacing() - p.value) < 0.005"
                  (click)="appearance.setLetterSpacing(p.value)"
                >
                  {{ p.label }}
                </button>
              }
            </div>
            <input
              type="range"
              class="spacing-range"
              min="-0.04"
              max="0.12"
              step="0.01"
              aria-label="Letter spacing slider"
              [ngModel]="appearance.letterSpacing()"
              (ngModelChange)="appearance.setLetterSpacing($event)"
            />
          </section>
        </div>
      }
    </div>
  `,
  styles: [
    `
      .reader-toolbar-seg {
        position: relative;
        display: inline-flex;
        align-items: center;
      }

      .cols-seg {
        display: inline-flex;
        align-items: center;
        gap: 2px;
        height: 32px;
        padding: 0 4px 0 8px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
      }

      .cols-icon {
        font-size: 16px;
        color: var(--on-surface-muted);
        margin-right: 2px;
      }

      .col-btn,
      .layout-btn {
        width: 24px;
        height: 24px;
        border-radius: var(--radius-pill);
        font-size: 12px;
        font-weight: 700;
        color: var(--on-surface-muted);
        display: grid;
        place-items: center;
      }

      .layout-btn .material-symbols-rounded {
        font-size: 15px;
      }

      .col-btn.active,
      .layout-btn.active {
        background-color: var(--accent);
        color: var(--on-accent);
      }

      .seg-divider {
        width: 1px;
        height: 16px;
        background-color: var(--surface-border);
        margin: 0 3px;
      }

      .spacing-popover {
        position: absolute;
        top: calc(100% + 8px);
        right: 0;
        width: min(286px, calc(100vw - 24px));
        padding: 12px;
        border-radius: var(--radius-md);
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        box-shadow: 0 12px 32px rgba(0, 0, 0, 0.22);
        z-index: 60;
        display: flex;
        flex-direction: column;
        gap: 10px;
      }

      .spacing-block {
        display: flex;
        flex-direction: column;
        gap: 8px;
        padding: 10px;
        border-radius: var(--radius-sm);
        background-color: var(--surface-variant);
        border: 1px solid transparent;
        transition: border-color 150ms ease, background-color 150ms ease;
      }

      .spacing-block.focused {
        border-color: color-mix(in srgb, var(--accent) 55%, transparent);
        background-color: color-mix(in srgb, var(--accent) 6%, var(--surface-variant));
      }

      .spacing-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
      }

      .spacing-title {
        font-size: 12px;
        font-weight: 700;
        color: var(--on-surface);
      }

      .spacing-controls {
        display: inline-flex;
        align-items: center;
        gap: 4px;
      }

      .spacing-val {
        font-size: 11px;
        font-weight: 600;
        color: var(--on-surface-muted);
        font-variant-numeric: tabular-nums;
        margin-right: 2px;
      }

      .step-mini-btn {
        width: 22px;
        height: 22px;
        border-radius: var(--radius-pill);
        border: 1px solid var(--surface-border);
        background-color: var(--surface);
        color: var(--on-surface);
        font-size: 13px;
        font-weight: 700;
        display: grid;
        place-items: center;
      }

      .step-mini-btn:hover:not(:disabled) {
        border-color: var(--accent);
        color: var(--accent);
      }

      .step-mini-btn:disabled {
        opacity: 0.35;
        cursor: default;
      }

      .preset-row {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: 6px;
      }

      .preset-chip {
        height: 26px;
        border-radius: var(--radius-sm);
        border: 1px solid var(--surface-border);
        background-color: var(--surface);
        color: var(--on-surface);
        font-size: 11.5px;
        font-weight: 600;
        transition: background-color 140ms ease, color 140ms ease, border-color 140ms ease;
      }

      .preset-chip.active {
        background-color: var(--accent);
        border-color: var(--accent);
        color: var(--on-accent);
      }

      .spacing-range {
        width: 100%;
        accent-color: var(--accent);
      }
    `,
  ],
})
export class ReaderColumnsToggleComponent {
  private readonly el = inject(ElementRef<HTMLElement>);
  readonly screen = inject(ScreenClassService);
  readonly appearance = inject(ReaderAppearanceService);
  readonly Math = Math;

  readonly showLayoutToggle = input<boolean>(false);
  readonly maxColumns = input<2 | 3>(3);
  readonly hideSpacing = input<boolean>(false);

  readonly linePresets = LINE_HEIGHT_PRESETS;
  readonly letterPresets = LETTER_SPACING_PRESETS;
  readonly spacingOpen = signal<'line' | 'letter' | null>(null);

  readonly options = computed<readonly (1 | 2 | 3)[]>(() => {
    const cls = this.screen.screenClass();
    if (cls === 'compact') return [];
    if (cls === 'medium' || this.maxColumns() === 2) return [1, 2];
    return [1, 2, 3];
  });

  readonly activeCols = computed(() => {
    const cols = this.appearance.effectiveColumns(this.screen.screenClass());
    return Math.min(this.maxColumns(), cols) as 1 | 2 | 3;
  });

  toggleSpacingPopover(kind: 'line' | 'letter', event: MouseEvent): void {
    event.stopPropagation();
    this.spacingOpen.set(this.spacingOpen() === kind ? null : kind);
  }

  @HostListener('document:click', ['$event'])
  onDocumentClick(event: MouseEvent): void {
    if (
      this.spacingOpen() !== null &&
      !this.el.nativeElement.contains(event.target as Node)
    ) {
      this.spacingOpen.set(null);
    }
  }

  @HostListener('document:keydown.escape')
  onEscape(): void {
    this.spacingOpen.set(null);
  }
}
