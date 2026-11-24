import {
  ChangeDetectionStrategy,
  Component,
  HostListener,
  OnInit,
  input,
  output,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';

@Component({
  selector: 'app-note-editor-modal',
  standalone: true,
  imports: [FormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div
      class="note-backdrop"
      role="dialog"
      aria-modal="true"
      aria-label="Personal note"
      (click)="closeModal.emit()"
    >
      <div class="note-dialog" (click)="$event.stopPropagation()">
        <header class="note-header">
          <div class="note-title-wrap">
            <span class="material-symbols-rounded note-icon">sticky_note_2</span>
            <div class="note-headings">
              <h2 class="note-title">{{ title() || 'Personal Note' }}</h2>
              @if (contextText()) {
                <p class="note-context">{{ contextText() }}</p>
              }
            </div>
          </div>
          <span class="private-pill">Private</span>
        </header>

        <textarea
          class="note-textarea"
          rows="6"
          placeholder="Write your personal note..."
          [ngModel]="draft()"
          (ngModelChange)="draft.set($event)"
          autofocus
        ></textarea>

        <footer class="note-footer">
          @if (hasExistingNote()) {
            <button
              type="button"
              class="btn btn-danger"
              (click)="deleteNote.emit()"
            >
              Delete
            </button>
          }
          <span class="spacer"></span>
          <button
            type="button"
            class="btn btn-ghost"
            (click)="closeModal.emit()"
          >
            Cancel
          </button>
          <button
            type="button"
            class="btn btn-primary"
            [disabled]="!draft().trim()"
            (click)="saveNote.emit(draft().trim())"
          >
            Save
          </button>
        </footer>
      </div>
    </div>
  `,
  styles: [
    `
      .note-backdrop {
        position: fixed;
        inset: 0;
        z-index: 1200;
        background: rgba(0, 0, 0, 0.58);
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 16px;
      }

      .note-dialog {
        width: min(100%, 540px);
        max-height: 85vh;
        overflow-y: auto;
        background: var(--surface);
        color: var(--on-surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-lg);
        padding: 20px;
        display: flex;
        flex-direction: column;
        gap: 14px;
        box-shadow: 0 20px 50px rgba(0, 0, 0, 0.35);
      }

      .note-header {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 12px;
      }

      .note-title-wrap {
        display: flex;
        align-items: flex-start;
        gap: 10px;
        min-width: 0;
      }

      .note-icon {
        color: var(--accent);
        font-size: 22px;
        margin-top: 2px;
      }

      .note-headings {
        min-width: 0;
      }

      .note-title {
        margin: 0;
        font-size: 16px;
        font-weight: 700;
        line-height: 1.3;
        overflow: hidden;
        text-overflow: ellipsis;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
      }

      .note-context {
        margin: 2px 0 0;
        font-size: 13px;
        color: var(--on-surface-muted);
      }

      .private-pill {
        flex-shrink: 0;
        font-size: 11px;
        font-weight: 600;
        padding: 3px 8px;
        border-radius: var(--radius-pill);
        background: var(--surface-variant);
        color: var(--on-surface-muted);
      }

      .note-textarea {
        width: 100%;
        box-sizing: border-box;
        resize: vertical;
        min-height: 140px;
        padding: 12px;
        border-radius: var(--radius-sm);
        border: 1px solid var(--surface-border);
        background: var(--bg);
        color: var(--on-surface);
        font: inherit;
        font-size: 14px;
        line-height: 1.5;
      }

      .note-textarea:focus {
        outline: 2px solid var(--accent);
        outline-offset: 1px;
      }

      .note-footer {
        display: flex;
        align-items: center;
        gap: 8px;
      }

      .spacer {
        flex: 1;
      }

      .btn {
        border: none;
        border-radius: var(--radius-pill);
        padding: 8px 16px;
        font-size: 13px;
        font-weight: 600;
        cursor: pointer;
      }

      .btn-ghost {
        background: transparent;
        color: var(--on-surface-muted);
      }

      .btn-primary {
        background: var(--accent);
        color: var(--on-accent);
      }

      .btn-primary:disabled {
        opacity: 0.45;
        cursor: not-allowed;
      }

      .btn-danger {
        background: color-mix(in srgb, var(--error) 12%, transparent);
        color: var(--error);
      }
    `,
  ],
})
export class NoteEditorModalComponent implements OnInit {
  readonly title = input<string | null>(null);
  readonly contextText = input<string | null>(null);
  readonly initialText = input<string>('');
  readonly hasExistingNote = input<boolean>(false);

  readonly saveNote = output<string>();
  readonly deleteNote = output<void>();
  readonly closeModal = output<void>();

  readonly draft = signal('');

  ngOnInit(): void {
    this.draft.set(this.initialText());
  }

  @HostListener('document:keydown.escape')
  onEscape(): void {
    this.closeModal.emit();
  }
}
