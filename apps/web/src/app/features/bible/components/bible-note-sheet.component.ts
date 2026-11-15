import {
  ChangeDetectionStrategy,
  Component,
  OnInit,
  computed,
  input,
  output,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';

@Component({
  selector: 'app-bible-note-sheet',
  standalone: true,
  imports: [FormsModule, ModalSheetComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-modal-sheet [title]="sheetTitle()" (closed)="closed.emit()">
      <textarea
        class="note-textarea"
        rows="4"
        [ngModel]="draft()"
        (ngModelChange)="draft.set($event)"
        placeholder="Write your study note..."
      ></textarea>
      <div class="modal-actions">
        <button type="button" class="pill-chip" (click)="closed.emit()">
          Cancel
        </button>
        <button
          type="button"
          class="pill-chip active"
          (click)="saved.emit(draft())"
        >
          Save Note
        </button>
      </div>
    </app-modal-sheet>
  `,
  styles: [
    `
      .note-textarea {
        width: 100%;
        padding: 10px 12px;
        border-radius: var(--radius-md);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        resize: vertical;
      }

      .modal-actions {
        display: flex;
        justify-content: flex-end;
        gap: 8px;
      }
    `,
  ],
})
export class BibleNoteSheetComponent implements OnInit {
  readonly referenceLabel = input.required<string>();
  readonly initialNote = input<string>('');
  readonly saved = output<string>();
  readonly closed = output<void>();

  readonly draft = signal<string>('');

  readonly sheetTitle = computed(() => `Note · ${this.referenceLabel()}`);

  ngOnInit(): void {
    this.draft.set(this.initialNote());
  }
}
