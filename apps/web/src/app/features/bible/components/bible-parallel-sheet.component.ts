import {
  ChangeDetectionStrategy,
  Component,
  computed,
  input,
  output,
} from '@angular/core';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';
import { BIBLE_VERSIONS } from '../models/bible.model';

@Component({
  selector: 'app-bible-parallel-sheet',
  standalone: true,
  imports: [ModalSheetComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-modal-sheet title="Parallel Translations (Up to 3)" (closed)="closed.emit()">
      <div class="parallel-head">
        <span class="muted">
          Primary: <strong>{{ primaryLabel() }}</strong> ·
          {{ totalSelected() }} / 3 active
        </span>
        @if (compareIds().length > 0) {
          <button type="button" class="pill-chip" (click)="cleared.emit()">
            Single View
          </button>
        }
      </div>

      <div class="version-list">
        @for (v of versions; track v.id) {
          @let isPrimary = v.id === primaryId();
          @let isCompare = compareIds().includes(v.id);
          <button
            type="button"
            class="version-row"
            [class.active]="isPrimary || isCompare"
            [disabled]="isPrimary"
            (click)="toggled.emit(v.id)"
          >
            <span class="ver-badge">{{ v.label }}</span>
            <div class="ver-meta">
              <strong>{{ v.fullName }}</strong>
              <span class="muted">
                {{ v.language }}{{ isPrimary ? ' · Primary' : '' }}
              </span>
            </div>
            @if (isPrimary || isCompare) {
              <span class="material-symbols-rounded ver-check">check_circle</span>
            }
          </button>
        }
      </div>
    </app-modal-sheet>
  `,
  styles: [
    `
      .parallel-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
      }

      .muted {
        color: var(--on-surface-muted);
        font-size: 12px;
      }

      .version-list {
        display: flex;
        flex-direction: column;
        gap: 6px;
        max-height: 55dvh;
        overflow-y: auto;
      }

      .version-row {
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 10px 12px;
        border-radius: var(--radius-md);
        border: 1px solid var(--surface-border);
        background-color: var(--surface-variant);
        text-align: left;
      }

      .version-row.active {
        border-color: var(--accent);
        background-color: var(--accent-soft);
      }

      .version-row[disabled] {
        opacity: 0.85;
        cursor: default;
      }

      .ver-badge {
        min-width: 68px;
        text-align: center;
        padding: 5px 8px;
        border-radius: var(--radius-sm);
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        font-size: 12px;
        font-weight: 700;
        flex-shrink: 0;
      }

      .ver-meta {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 2px;
      }

      .ver-meta strong {
        font-size: 14px;
        line-height: 1.3;
      }

      .ver-check {
        color: var(--accent);
        flex-shrink: 0;
      }
    `,
  ],
})
export class BibleParallelSheetComponent {
  readonly primaryId = input.required<string>();
  readonly compareIds = input.required<string[]>();

  readonly toggled = output<string>();
  readonly cleared = output<void>();
  readonly closed = output<void>();

  readonly versions = BIBLE_VERSIONS;

  readonly primaryLabel = computed(
    () =>
      this.versions.find((v) => v.id === this.primaryId())?.label ??
      this.primaryId().toUpperCase(),
  );

  readonly totalSelected = computed(() => 1 + this.compareIds().length);
}
