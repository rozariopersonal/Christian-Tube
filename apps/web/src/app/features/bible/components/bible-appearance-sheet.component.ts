import {
  ChangeDetectionStrategy,
  Component,
  inject,
  output,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import {
  LETTER_SPACING_PRESETS,
  LINE_HEIGHT_PRESETS,
  ReaderAppearanceService,
} from '../../../core/services/reader-appearance.service';
import { ReaderFullscreenService } from '../../../core/services/reader-fullscreen.service';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';
import { ReaderColumnsToggleComponent } from '../../../shared/ui/reader-columns-toggle.component';
import { ReaderFontPickerComponent } from '../../../shared/ui/reader-font-picker.component';

@Component({
  selector: 'app-bible-appearance-sheet',
  standalone: true,
  imports: [
    FormsModule,
    ModalSheetComponent,
    ReaderColumnsToggleComponent,
    ReaderFontPickerComponent,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-modal-sheet title="Reader Appearance" (closed)="closed.emit()">
      @if (browsingFonts()) {
        <app-reader-font-picker
          [browsing]="true"
          (browsingChange)="browsingFonts.set($event)"
        />
      } @else {
        <div class="appearance-section">
          <label class="label">Paper Theme</label>
          <div class="paper-grid">
            @for (p of appearance.paperThemes(); track p.id) {
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
          <label class="label">Reading Layout</label>
          <div class="chip-wrap">
            <button
              type="button"
              class="pill-chip"
              [class.active]="appearance.bibleLayout() === 'verses'"
              (click)="appearance.setBibleLayout('verses')"
            >
              Verse by Verse
            </button>
            <button
              type="button"
              class="pill-chip"
              [class.active]="appearance.bibleLayout() === 'paragraph'"
              (click)="appearance.setBibleLayout('paragraph')"
            >
              Paragraph Flow
            </button>
          </div>
        </div>

        <div class="appearance-section">
          <app-reader-font-picker
            [browsing]="false"
            (browsingChange)="browsingFonts.set($event)"
          />
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

      <div class="appearance-section">
        <label class="label">Columns &amp; Page Layout</label>
        <div class="chip-wrap">
          <app-reader-columns-toggle [showLayoutToggle]="true" />
        </div>
      </div>

      <div class="appearance-section">
        <label class="label">Auto-Fullscreen (Idle)</label>
        <div class="chip-wrap">
          @for (opt of autoFullscreenOptions; track opt.value) {
            <button
              type="button"
              class="pill-chip"
              [class.active]="fullscreen.autoFullscreenSeconds() === opt.value"
              (click)="fullscreen.setAutoFullscreenSeconds(opt.value)"
            >
              {{ opt.label }}
            </button>
          }
        </div>
      </div>
      }
    </app-modal-sheet>
  `,
  styles: [
    `
      .appearance-section {
        display: flex;
        flex-direction: column;
        gap: 8px;
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

      .chip-wrap {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
      }

      .sys-scan-btn,
      .dl-all-btn {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        padding: 4px 10px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        font-size: 11.5px;
        font-weight: 600;
        color: var(--accent);
      }

      .sys-scan-btn .material-symbols-rounded,
      .dl-all-btn .material-symbols-rounded {
        font-size: 14px;
      }

      .font-groups-box {
        display: flex;
        flex-direction: column;
        gap: 12px;
        max-height: 260px;
        overflow-y: auto;
        padding: 10px;
        border-radius: var(--radius-md);
        background-color: var(--bg);
        border: 1px solid var(--surface-border);
      }

      .font-group-block {
        display: flex;
        flex-direction: column;
        gap: 6px;
      }

      .font-group-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
      }

      .font-group-label {
        font-size: 12px;
        font-weight: 700;
        color: var(--on-surface-muted);
      }

      .font-group-native {
        color: var(--accent);
      }

      .font-chip {
        gap: 5px;
      }

      .chip-dl-icon {
        font-size: 14px;
        opacity: 0.75;
      }
    `,
  ],
})
export class BibleAppearanceSheetComponent {
  readonly appearance = inject(ReaderAppearanceService);
  readonly fullscreen = inject(ReaderFullscreenService);
  readonly autoFullscreenOptions = [
    { value: 0, label: 'Off' },
    { value: 30, label: '30s' },
    { value: 60, label: '1m' },
    { value: 120, label: '2m' },
  ] as const;
  readonly browsingFonts = signal(false);
  readonly linePresets = LINE_HEIGHT_PRESETS;
  readonly letterPresets = LETTER_SPACING_PRESETS;
  readonly Math = Math;
  readonly closed = output<void>();
}
