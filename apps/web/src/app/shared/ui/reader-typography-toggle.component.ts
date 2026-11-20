import {
  ChangeDetectionStrategy,
  Component,
  ElementRef,
  HostListener,
  computed,
  inject,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import {
  LETTER_SPACING_PRESETS,
  LINE_HEIGHT_PRESETS,
  READER_FONTS,
  ReaderAppearanceService,
  ReaderFontOption,
} from '../../core/services/reader-appearance.service';

@Component({
  selector: 'app-reader-typography-toggle',
  standalone: true,
  imports: [FormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="reader-typography-seg">
      <div class="typo-pill" role="group" aria-label="Typography and text styling">
        <!-- 1. Font Family Dropdown Trigger -->
        <div class="popover-anchor">
          <button
            type="button"
            class="typo-btn font-trigger-btn"
            [class.active]="fontMenuOpen()"
            [title]="'Font: ' + activeFont().label"
            aria-label="Select font family"
            [attr.aria-expanded]="fontMenuOpen()"
            (click)="toggleFontMenu($event)"
          >
            <span class="material-symbols-rounded typo-icon" aria-hidden="true">text_fields</span>
            <span class="font-name">{{ activeFont().shortLabel || activeFont().label }}</span>
            <span class="material-symbols-rounded caret-icon" aria-hidden="true">expand_more</span>
          </button>

          @if (fontMenuOpen()) {
            <div
              class="font-menu-popover"
              role="menu"
              aria-label="Font family selection"
              (click)="$event.stopPropagation()"
            >
              <div class="popover-title">Font Family</div>
              @for (f of fonts; track f.id) {
                <button
                  type="button"
                  class="font-menu-item"
                  [class.active]="appearance.fontId() === f.id"
                  [style.font-family]="f.cssFamily"
                  role="menuitemradio"
                  [attr.aria-checked]="appearance.fontId() === f.id"
                  (click)="selectFont(f.id)"
                >
                  <span class="font-preview">{{ f.label }}</span>
                  @if (appearance.fontId() === f.id) {
                    <span class="material-symbols-rounded check-icon" aria-hidden="true">check</span>
                  }
                </button>
              }
            </div>
          }
        </div>

        <span class="seg-divider" aria-hidden="true"></span>

        <!-- 2. Font Size Stepper -->
        <div class="size-group">
          <button
            type="button"
            class="typo-btn size-step-btn"
            title="Decrease font size"
            aria-label="Decrease font size"
            [disabled]="appearance.fontSize() <= 13"
            (click)="appearance.stepFontSize(-1)"
          >
            <span class="material-symbols-rounded" aria-hidden="true">remove</span>
          </button>
          <span class="size-val" [title]="'Font size: ' + appearance.fontSize() + 'px'">
            {{ appearance.fontSize() }}
          </span>
          <button
            type="button"
            class="typo-btn size-step-btn"
            title="Increase font size"
            aria-label="Increase font size"
            [disabled]="appearance.fontSize() >= 28"
            (click)="appearance.stepFontSize(1)"
          >
            <span class="material-symbols-rounded" aria-hidden="true">add</span>
          </button>
        </div>

        <span class="seg-divider" aria-hidden="true"></span>

        <!-- 3. Line & Letter Spacing Popover Trigger -->
        <div class="popover-anchor">
          <button
            type="button"
            class="typo-btn spacing-trigger-btn"
            [class.active]="spacingOpen() || isCustomSpacing()"
            [title]="
              'Spacing (Line: ' +
              appearance.lineHeight() +
              ', Letter: ' +
              appearance.formatLetterSpacing() +
              ')'
            "
            aria-label="Line and letter spacing"
            [attr.aria-expanded]="spacingOpen()"
            (click)="toggleSpacing($event)"
          >
            <span class="material-symbols-rounded" aria-hidden="true">format_line_spacing</span>
          </button>

          @if (spacingOpen()) {
            <div
              class="spacing-popover"
              role="dialog"
              aria-label="Line and letter spacing"
              (click)="$event.stopPropagation()"
            >
              <!-- Line Spacing -->
              <section class="spacing-block">
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

              <!-- Letter Spacing -->
              <section class="spacing-block">
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
      </div>
    </div>
  `,
  styles: [
    `
      .reader-typography-seg {
        position: relative;
        display: inline-flex;
        align-items: center;
      }

      .typo-pill {
        display: inline-flex;
        align-items: center;
        gap: 2px;
        height: 32px;
        padding: 0 4px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
      }

      .popover-anchor {
        position: relative;
        display: inline-flex;
        align-items: center;
      }

      .typo-btn {
        height: 24px;
        border-radius: var(--radius-pill);
        color: var(--on-surface-muted);
        display: inline-flex;
        align-items: center;
        justify-content: center;
        transition: background-color 140ms ease, color 140ms ease;
      }

      .typo-btn:hover:not(:disabled) {
        background-color: color-mix(in srgb, var(--on-surface) 8%, transparent);
        color: var(--on-surface);
      }

      .typo-btn:disabled {
        opacity: 0.35;
        cursor: default;
      }

      .font-trigger-btn {
        padding: 0 6px 0 6px;
        gap: 4px;
        font-size: 12px;
        font-weight: 600;
        color: var(--on-surface);
      }

      .font-trigger-btn.active {
        background-color: color-mix(in srgb, var(--accent) 15%, transparent);
        color: var(--accent);
      }

      .typo-icon {
        font-size: 15px;
        color: var(--on-surface-muted);
      }

      .font-name {
        max-width: 82px;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      @media (max-width: 900px) {
        .font-name {
          display: none;
        }
      }

      .caret-icon {
        font-size: 16px;
        color: var(--on-surface-muted);
        margin-left: -2px;
      }

      .seg-divider {
        width: 1px;
        height: 16px;
        background-color: var(--surface-border);
        margin: 0 2px;
      }

      .size-group {
        display: inline-flex;
        align-items: center;
        gap: 1px;
      }

      .size-step-btn {
        width: 22px;
        height: 22px;
      }

      .size-step-btn .material-symbols-rounded {
        font-size: 14px;
      }

      .size-val {
        font-size: 11.5px;
        font-weight: 700;
        min-width: 18px;
        text-align: center;
        color: var(--on-surface);
        font-variant-numeric: tabular-nums;
        user-select: none;
      }

      .spacing-trigger-btn {
        width: 24px;
        height: 24px;
      }

      .spacing-trigger-btn .material-symbols-rounded {
        font-size: 15px;
      }

      .spacing-trigger-btn.active {
        background-color: var(--accent);
        color: var(--on-accent);
      }

      /* Font Selection Popover */
      .font-menu-popover {
        position: absolute;
        top: calc(100% + 8px);
        left: 0;
        min-width: 190px;
        padding: 6px;
        border-radius: var(--radius-md);
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        box-shadow: 0 12px 32px rgba(0, 0, 0, 0.22);
        z-index: 60;
        display: flex;
        flex-direction: column;
        gap: 2px;
      }

      .popover-title {
        font-size: 11px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        color: var(--on-surface-muted);
        padding: 6px 8px 4px;
      }

      .font-menu-item {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
        padding: 8px 10px;
        border-radius: var(--radius-sm);
        font-size: 13.5px;
        color: var(--on-surface);
        text-align: left;
        width: 100%;
        transition: background-color 140ms ease, color 140ms ease;
      }

      .font-menu-item:hover {
        background-color: var(--surface-variant);
      }

      .font-menu-item.active {
        background-color: color-mix(in srgb, var(--accent) 12%, transparent);
        color: var(--accent);
        font-weight: 700;
      }

      .font-preview {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .check-icon {
        font-size: 16px;
        color: var(--accent);
        flex-shrink: 0;
      }

      /* Spacing Popover */
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
export class ReaderTypographyToggleComponent {
  private readonly el = inject(ElementRef<HTMLElement>);
  readonly appearance = inject(ReaderAppearanceService);
  readonly Math = Math;

  readonly fonts = READER_FONTS;
  readonly linePresets = LINE_HEIGHT_PRESETS;
  readonly letterPresets = LETTER_SPACING_PRESETS;

  readonly fontMenuOpen = signal<boolean>(false);
  readonly spacingOpen = signal<boolean>(false);

  readonly activeFont = computed<ReaderFontOption>(() => this.appearance.activeFont());

  readonly isCustomSpacing = computed<boolean>(() => {
    return (
      Math.abs(this.appearance.lineHeight() - 1.65) > 0.01 ||
      Math.abs(this.appearance.letterSpacing()) > 0.005
    );
  });

  toggleFontMenu(event: MouseEvent): void {
    event.stopPropagation();
    const next = !this.fontMenuOpen();
    this.fontMenuOpen.set(next);
    if (next) this.spacingOpen.set(false);
  }

  selectFont(fontId: string): void {
    this.appearance.setFont(fontId);
    this.fontMenuOpen.set(false);
  }

  toggleSpacing(event: MouseEvent): void {
    event.stopPropagation();
    const next = !this.spacingOpen();
    this.spacingOpen.set(next);
    if (next) this.fontMenuOpen.set(false);
  }

  @HostListener('document:click', ['$event'])
  onDocumentClick(event: MouseEvent): void {
    if (
      (this.fontMenuOpen() || this.spacingOpen()) &&
      !this.el.nativeElement.contains(event.target as Node)
    ) {
      this.fontMenuOpen.set(false);
      this.spacingOpen.set(false);
    }
  }

  @HostListener('document:keydown.escape')
  onEscape(): void {
    this.fontMenuOpen.set(false);
    this.spacingOpen.set(false);
  }
}
