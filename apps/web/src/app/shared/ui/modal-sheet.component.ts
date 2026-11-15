import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';

@Component({
  selector: 'app-modal-sheet',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="modal-backdrop" (click)="closed.emit()">
      <div class="modal-panel sheet-panel" (click)="$event.stopPropagation()">
        @if (showHandle()) {
          <div class="drag-handle"></div>
        }
        @if (title()) {
          <div class="modal-head">
            <h2 class="font-display">{{ title() }}</h2>
            <button
              type="button"
              class="icon-btn"
              aria-label="Close"
              (click)="closed.emit()"
            >
              <span class="material-symbols-rounded">close</span>
            </button>
          </div>
        }
        <ng-content />
      </div>
    </div>
  `,
  styles: [
    `
      .sheet-panel {
        padding: 12px 18px 20px;
        gap: 12px;
      }

      .drag-handle {
        width: 36px;
        height: 4px;
        border-radius: 999px;
        background-color: var(--surface-border);
        margin: 0 auto 2px;
        flex-shrink: 0;
      }

      .modal-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
      }

      .modal-head h2 {
        margin: 0;
        font-size: 18px;
        line-height: 1.3;
      }
    `,
  ],
})
export class ModalSheetComponent {
  readonly title = input<string>('');
  readonly showHandle = input<boolean>(true);
  readonly closed = output<void>();
}
