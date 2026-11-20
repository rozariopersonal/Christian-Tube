import { ChangeDetectionStrategy, Component, inject, output } from '@angular/core';
import { FormsModule } from '@angular/forms';
import {
  LETTER_SPACING_PRESETS,
  LINE_HEIGHT_PRESETS,
  READER_FONTS,
  READER_PAPER_THEMES,
  ReaderAppearanceService,
} from '../../../core/services/reader-appearance.service';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';

@Component({
  selector: 'app-book-appearance-sheet',
  standalone: true,
  imports: [FormsModule, ModalSheetComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-modal-sheet title="Display & Layout" (closed)="closed.emit()">
      <div class="appearance-section">
        <label class="label">Paper Theme</label>
        <div class="paper-grid">
          @for (p of paperThemes; track p.id) {
            <button
              type="button"
              class="paper-swatch"
              [class.active]="appearance.paperTheme() === p.id"
              [style.background]="p.swatchBg"
              [style.color]="p.swatchFg"
              (click)="appearance.setPaperTheme(p.id)"
            >
              <span class="swatch-aa">Aa</span>
              <span class="swatch-label">{{ p.label }}</span>
            </button>
          }
        </div>
      </div>

      <div class="appearance-section">
        <label class="label">Font Family</label>
        <div class="chip-wrap">
          @for (f of fonts; track f.id) {
            <button
              type="button"
              class="pill-chip"
              [class.active]="appearance.fontId() === f.id"
              (click)="appearance.setFont(f.id)"
            >
              {{ f.label }}
            </button>
          }
        </div>
      </div>

      <div class="appearance-section">
        <label class="label">Font Size: {{ appearance.fontSize() }}px</label>
        <input
          type="range"
          min="13"
          max="28"
          [ngModel]="appearance.fontSize()"
          (ngModelChange)="appearance.setFontSize($event)"
        />
      </div>

      <div class="appearance-section">
        <div class="section-head">
          <label class="label">Line Spacing: {{ appearance.lineHeight() }}</label>
          <div class="step-group">
            <button
              type="button"
              class="step-btn"
              aria-label="Decrease line spacing"
              [disabled]="appearance.lineHeight() <= 1.3"
              (click)="appearance.stepLineHeight(-0.05)"
            >
              −
            </button>
            <button
              type="button"
              class="step-btn"
              aria-label="Increase line spacing"
              [disabled]="appearance.lineHeight() >= 2.2"
              (click)="appearance.stepLineHeight(0.05)"
            >
              +
            </button>
          </div>
        </div>
        <div class="chip-wrap">
          @for (p of linePresets; track p.id) {
            <button
              type="button"
              class="pill-chip"
              [class.active]="Math.abs(appearance.lineHeight() - p.value) < 0.03"
              (click)="appearance.setLineHeight(p.value)"
            >
              {{ p.label }}
            </button>
          }
        </div>
        <input
          type="range"
          min="1.3"
          max="2.2"
          step="0.05"
          [ngModel]="appearance.lineHeight()"
          (ngModelChange)="appearance.setLineHeight($event)"
        />
      </div>

      <div class="appearance-section">
        <div class="section-head">
          <label class="label">
            Letter Spacing: {{ appearance.formatLetterSpacing() }}
          </label>
          <div class="step-group">
            <button
              type="button"
              class="step-btn"
              aria-label="Decrease letter spacing"
              [disabled]="appearance.letterSpacing() <= -0.04"
              (click)="appearance.stepLetterSpacing(-0.01)"
            >
              −
            </button>
            <button
              type="button"
              class="step-btn"
              aria-label="Increase letter spacing"
              [disabled]="appearance.letterSpacing() >= 0.12"
              (click)="appearance.stepLetterSpacing(0.01)"
            >
              +
            </button>
          </div>
        </div>
        <div class="chip-wrap">
          @for (p of letterPresets; track p.id) {
            <button
              type="button"
              class="pill-chip"
              [class.active]="Math.abs(appearance.letterSpacing() - p.value) < 0.005"
              (click)="appearance.setLetterSpacing(p.value)"
            >
              {{ p.label }}
            </button>
          }
        </div>
        <input
          type="range"
          min="-0.04"
          max="0.12"
          step="0.01"
          [ngModel]="appearance.letterSpacing()"
          (ngModelChange)="appearance.setLetterSpacing($event)"
        />
      </div>

      <div class="split-controls">
        <div class="appearance-section">
          <label class="label">Alignment</label>
          <div class="chip-wrap">
            <button
              type="button"
              class="pill-chip"
              [class.active]="appearance.bookAlign() === 'left'"
              (click)="appearance.setBookAlign('left')"
            >
              Left
            </button>
            <button
              type="button"
              class="pill-chip"
              [class.active]="appearance.bookAlign() === 'justify'"
              (click)="appearance.setBookAlign('justify')"
            >
              Justify
            </button>
          </div>
        </div>
      </div>

      <div class="appearance-section">
        <label class="label">Margins</label>
        <div class="chip-wrap">
          @for (m of ['narrow', 'medium', 'wide']; track m) {
            <button
              type="button"
              class="pill-chip"
              [class.active]="appearance.bookMargin() === m"
              (click)="appearance.setBookMargin($any(m))"
            >
              {{ m[0].toUpperCase() + m.slice(1) }}
            </button>
          }
        </div>
      </div>
    </app-modal-sheet>
  `,
  styles: [
    `
      .appearance-section {
        display: flex;
        flex-direction: column;
        gap: 8px;
      }

      .label {
        font-size: 13px;
        font-weight: 600;
        color: var(--on-surface-muted);
      }

      .paper-grid {
        display: grid;
        grid-template-columns: repeat(4, 1fr);
        gap: 8px;
      }

      .paper-swatch {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 4px;
        padding: 10px 6px;
        border-radius: var(--radius-md);
        border: 2px solid var(--surface-border);
      }

      .paper-swatch.active {
        border-color: var(--accent);
      }

      .swatch-aa {
        font-family: Georgia, serif;
        font-size: 16px;
        font-weight: 700;
      }

      .swatch-label {
        font-size: 11px;
        font-weight: 600;
      }

      .section-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
      }

      .step-group {
        display: inline-flex;
        align-items: center;
        gap: 6px;
      }

      .step-btn {
        width: 26px;
        height: 26px;
        border-radius: var(--radius-pill);
        border: 1px solid var(--surface-border);
        background-color: var(--surface-variant);
        color: var(--on-surface);
        font-weight: 700;
        display: grid;
        place-items: center;
      }

      .step-btn:hover:not(:disabled) {
        border-color: var(--accent);
        color: var(--accent);
      }

      .step-btn:disabled {
        opacity: 0.35;
        cursor: default;
      }

      .chip-wrap {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
      }

      .split-controls {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
        gap: 12px;
      }
    `,
  ],
})
export class BookAppearanceSheetComponent {
  readonly appearance = inject(ReaderAppearanceService);
  readonly fonts = READER_FONTS;
  readonly paperThemes = READER_PAPER_THEMES;
  readonly linePresets = LINE_HEIGHT_PRESETS;
  readonly letterPresets = LETTER_SPACING_PRESETS;
  readonly Math = Math;
  readonly closed = output<void>();
}
