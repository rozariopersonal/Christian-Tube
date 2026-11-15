import { ChangeDetectionStrategy, Component, output, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';

export interface ChannelRequestPayload {
  name: string;
  url: string;
  reason?: string;
}

@Component({
  selector: 'app-channel-request-modal',
  standalone: true,
  imports: [FormsModule, ModalSheetComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-modal-sheet title="Request a Channel" (closed)="closed.emit()">
      <label class="field">
        <span>Channel Name</span>
        <input
          type="text"
          [ngModel]="name()"
          (ngModelChange)="name.set($event)"
          placeholder="e.g. Grace Fellowship"
        />
      </label>
      <label class="field">
        <span>YouTube Channel URL</span>
        <input
          type="url"
          [ngModel]="url()"
          (ngModelChange)="url.set($event)"
          placeholder="https://youtube.com/@..."
        />
      </label>
      <label class="field">
        <span>Reason (optional)</span>
        <textarea
          rows="3"
          [ngModel]="reason()"
          (ngModelChange)="reason.set($event)"
        ></textarea>
      </label>
      <div class="modal-actions">
        <button type="button" class="pill-chip" (click)="closed.emit()">
          Cancel
        </button>
        <button type="button" class="pill-chip active" (click)="submit()">
          Submit
        </button>
      </div>
    </app-modal-sheet>
  `,
  styles: [
    `
      .field {
        display: flex;
        flex-direction: column;
        gap: 6px;
        font-size: 13px;
        font-weight: 500;
      }

      .field input,
      .field textarea {
        padding: 10px 12px;
        border-radius: var(--radius-sm);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
      }

      .modal-actions {
        display: flex;
        justify-content: flex-end;
        gap: 8px;
      }
    `,
  ],
})
export class ChannelRequestModalComponent {
  readonly submitted = output<ChannelRequestPayload>();
  readonly closed = output<void>();

  readonly name = signal<string>('');
  readonly url = signal<string>('');
  readonly reason = signal<string>('');

  submit(): void {
    const trimmedName = this.name().trim();
    const trimmedUrl = this.url().trim();
    if (!trimmedName || !trimmedUrl) return;
    this.submitted.emit({
      name: trimmedName,
      url: trimmedUrl,
      reason: this.reason().trim() || undefined,
    });
  }
}
