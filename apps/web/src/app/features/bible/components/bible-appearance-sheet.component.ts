import { ChangeDetectionStrategy, Component, inject, output } from '@angular/core';
import { FormsModule } from '@angular/forms';
import {
  READER_FONTS,
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
        gap: 6px;
      }

      .label {
        font-size: 13px;
        font-weight: 600;
        color: var(--on-surface-muted);
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
  readonly closed = output<void>();
}
