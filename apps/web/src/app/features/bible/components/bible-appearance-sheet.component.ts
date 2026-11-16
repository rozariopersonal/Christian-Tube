import { ChangeDetectionStrategy, Component, inject, output } from '@angular/core';
import { FormsModule } from '@angular/forms';
import {
  READER_FONTS,
  READER_PAPER_THEMES,
  ReaderAppearanceService,
} from '../../../core/services/reader-appearance.service';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';

@Component({
  selector: 'app-bible-appearance-sheet',
  standalone: true,
  imports: [FormsModule, ModalSheetComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-modal-sheet title="Reader Appearance" (closed)="closed.emit()">
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
        <label class="label">Columns (Wide)</label>
        <div class="chip-wrap">
          <button
            type="button"
            class="pill-chip"
            [class.active]="appearance.bookColumns() === 1"
            (click)="appearance.setBookColumns(1)"
          >
            Single
          </button>
          <button
            type="button"
            class="pill-chip"
            [class.active]="appearance.bookColumns() === 2"
            (click)="appearance.setBookColumns(2)"
          >
            2-Column
          </button>
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
        <label class="label">Line Spacing: {{ appearance.lineHeight() }}</label>
        <input
          type="range"
          min="1.3"
          max="2.2"
          step="0.05"
          [ngModel]="appearance.lineHeight()"
          (ngModelChange)="appearance.setLineHeight($event)"
        />
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

      .chip-wrap {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
      }
    `,
  ],
})
export class BibleAppearanceSheetComponent {
  readonly appearance = inject(ReaderAppearanceService);
  readonly fonts = READER_FONTS;
  readonly paperThemes = READER_PAPER_THEMES;
  readonly closed = output<void>();
}
