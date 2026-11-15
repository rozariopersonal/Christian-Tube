import { ChangeDetectionStrategy, Component, computed, input, output } from '@angular/core';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';
import { CrossRefTarget } from '../models/bible.model';

@Component({
  selector: 'app-bible-cross-refs-sheet',
  standalone: true,
  imports: [ModalSheetComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-modal-sheet [title]="sheetTitle()" (closed)="closed.emit()">
      <div class="ref-list">
        @for (r of refs(); track $index) {
          <button
            type="button"
            class="ref-row"
            (click)="jumpTo.emit({ abbrev: r.bt, chapter: r.c })"
          >
            <span>{{ r.bt }} {{ r.c }}:{{ r.v }}{{ r.e ? '-' + r.e : '' }}</span>
            <span class="material-symbols-rounded">arrow_forward</span>
          </button>
        }
      </div>
    </app-modal-sheet>
  `,
  styles: [
    `
      .ref-list {
        display: flex;
        flex-direction: column;
        gap: 8px;
        max-height: 55dvh;
        overflow-y: auto;
      }

      .ref-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 10px 12px;
        border-radius: var(--radius-sm);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        text-align: left;
      }
    `,
  ],
})
export class BibleCrossRefsSheetComponent {
  readonly referenceLabel = input.required<string>();
  readonly refs = input.required<CrossRefTarget[]>();
  readonly jumpTo = output<{ abbrev: string; chapter: number }>();
  readonly closed = output<void>();

  readonly sheetTitle = computed(
    () => `Cross-References · ${this.referenceLabel()}`,
  );
}
