import {
  ChangeDetectionStrategy,
  Component,
  computed,
  input,
  output,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';
import { BIBLE_VERSIONS } from '../models/bible.model';

@Component({
  selector: 'app-bible-version-sheet',
  standalone: true,
  imports: [FormsModule, ModalSheetComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-modal-sheet title="Bible Versions" (closed)="closed.emit()">
      <div class="sheet-search">
        <span class="material-symbols-rounded">search</span>
        <input
          type="search"
          placeholder="Search translations..."
          [ngModel]="search()"
          (ngModelChange)="search.set($event)"
        />
      </div>

      <div class="version-list">
        @for (v of filteredVersions(); track v.id) {
          @let active = v.id === activeVersionId();
          <button
            type="button"
            class="version-row"
            [class.active]="active"
            (click)="versionSelected.emit(v.id)"
          >
            <span class="ver-badge">{{ v.label }}</span>
            <div class="ver-meta">
              <strong>{{ v.fullName }}</strong>
              <span class="muted">{{ v.language }}</span>
            </div>
            @if (active) {
              <span class="material-symbols-rounded ver-check">check_circle</span>
            }
          </button>
        }
      </div>
    </app-modal-sheet>
  `,
  styles: [
    `
      .sheet-search {
        display: flex;
        align-items: center;
        gap: 8px;
        height: 40px;
        padding: 0 12px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
      }

      .sheet-search input {
        flex: 1;
        border: none;
        outline: none;
        background: transparent;
        min-width: 0;
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

      .muted {
        color: var(--on-surface-muted);
        font-size: 12px;
      }

      .ver-check {
        color: var(--accent);
        flex-shrink: 0;
      }
    `,
  ],
})
export class BibleVersionSheetComponent {
  readonly activeVersionId = input.required<string>();
  readonly versionSelected = output<string>();
  readonly closed = output<void>();

  readonly search = signal<string>('');

  readonly filteredVersions = computed(() => {
    const q = this.search().trim().toLowerCase();
    if (!q) return BIBLE_VERSIONS;
    return BIBLE_VERSIONS.filter(
      (v) =>
        v.label.toLowerCase().includes(q) ||
        v.fullName.toLowerCase().includes(q) ||
        v.language.toLowerCase().includes(q),
    );
  });
}
