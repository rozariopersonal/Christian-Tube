import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { ToastService } from './toast.service';

@Component({
  selector: 'app-toast-host',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="toast-host" role="status" aria-live="polite" aria-atomic="false">
      @for (toast of toastService.toasts(); track toast.id) {
        <div
          class="toast-item"
          [class.tone-success]="toast.tone === 'success'"
          [class.tone-error]="toast.tone === 'error'"
        >
          <span class="material-symbols-rounded toast-icon" aria-hidden="true">
            @if (toast.tone === 'success') {
              check_circle
            } @else if (toast.tone === 'error') {
              error
            } @else {
              info
            }
          </span>
          <span class="toast-msg">{{ toast.message }}</span>
          <button
            type="button"
            class="toast-close"
            aria-label="Dismiss notification"
            (click)="toastService.dismiss(toast.id)"
          >
            <span class="material-symbols-rounded">close</span>
          </button>
        </div>
      }
    </div>
  `,
  styles: [
    `
      .toast-host {
        position: fixed;
        left: 50%;
        bottom: calc(var(--shell-bottom-offset, 0px) + 16px);
        transform: translateX(-50%);
        z-index: 160;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 8px;
        width: min(calc(100vw - 32px), 420px);
        pointer-events: none;
      }

      .toast-item {
        pointer-events: auto;
        width: 100%;
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 10px 12px 10px 14px;
        border-radius: var(--radius-md);
        background-color: var(--surface-elevated);
        color: var(--on-surface);
        border: 1px solid var(--surface-border);
        box-shadow: 0 10px 28px rgba(0, 0, 0, 0.24);
        font-size: 13px;
        font-weight: 500;
      }

      .toast-item.tone-success .toast-icon {
        color: var(--accent);
      }

      .toast-item.tone-error {
        border-color: var(--error);
      }

      .toast-item.tone-error .toast-icon {
        color: var(--error);
      }

      .toast-icon {
        font-size: 18px;
        flex-shrink: 0;
        color: var(--on-surface-muted);
      }

      .toast-msg {
        flex: 1;
        min-width: 0;
        word-break: break-word;
      }

      .toast-close {
        width: 26px;
        height: 26px;
        border-radius: var(--radius-pill);
        display: grid;
        place-items: center;
        color: var(--on-surface-muted);
        flex-shrink: 0;
      }

      .toast-close:hover {
        background-color: var(--surface-variant);
        color: var(--on-surface);
      }

      .toast-close .material-symbols-rounded {
        font-size: 16px;
      }
    `,
  ],
})
export class ToastHostComponent {
  readonly toastService = inject(ToastService);
}
