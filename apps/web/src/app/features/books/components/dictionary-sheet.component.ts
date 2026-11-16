import {
  ChangeDetectionStrategy,
  Component,
  OnChanges,
  inject,
  input,
  output,
  signal,
} from '@angular/core';
import {
  DictionaryEntry,
  DictionaryService,
} from '../../../core/services/dictionary.service';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';

@Component({
  selector: 'app-dictionary-sheet',
  standalone: true,
  imports: [ModalSheetComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-modal-sheet [title]="'Dictionary · ' + word()" (closed)="closed.emit()">
      @if (loading()) {
        <p class="status-msg">Looking up "{{ word() }}"...</p>
      } @else if (error()) {
        <p class="status-msg">{{ error() }}</p>
      } @else if (entry(); as res) {
        <div class="dict-head">
          <div>
            <strong class="dict-word">{{ res.word }}</strong>
            @if (res.phonetic) {
              <span class="dict-phonetic">{{ res.phonetic }}</span>
            }
          </div>
          @if (res.audioUrl) {
            <button
              type="button"
              class="pill-chip"
              (click)="playPronunciation(res.audioUrl!)"
            >
              <span class="material-symbols-rounded">volume_up</span>
              Listen
            </button>
          }
        </div>

        <div class="meanings-list">
          @for (m of res.meanings; track $index) {
            <div class="meaning-block">
              @if (m.partOfSpeech) {
                <span class="pos-tag">{{ m.partOfSpeech }}</span>
              }
              <ol class="def-list">
                @for (d of m.definitions; track $index) {
                  <li>
                    <p class="def-text">{{ d.definition }}</p>
                    @if (d.example) {
                      <p class="def-example">"{{ d.example }}"</p>
                    }
                  </li>
                }
              </ol>
            </div>
          }
        </div>
      }
    </app-modal-sheet>
  `,
  styles: [
    `
      .status-msg {
        padding: 20px 0;
        text-align: center;
        color: var(--on-surface-muted);
      }

      .dict-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
      }

      .dict-word {
        font-size: 20px;
        margin-right: 8px;
      }

      .dict-phonetic {
        color: var(--on-surface-muted);
        font-size: 14px;
      }

      .meanings-list {
        display: flex;
        flex-direction: column;
        gap: 12px;
        max-height: 50dvh;
        overflow-y: auto;
      }

      .meaning-block {
        padding: 10px 12px;
        border-radius: var(--radius-md);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
      }

      .pos-tag {
        display: inline-block;
        font-size: 11px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        color: var(--accent);
        margin-bottom: 6px;
      }

      .def-list {
        margin: 0;
        padding-left: 18px;
        display: flex;
        flex-direction: column;
        gap: 6px;
      }

      .def-text {
        margin: 0;
        font-size: 14px;
      }

      .def-example {
        margin: 2px 0 0;
        font-size: 13px;
        font-style: italic;
        color: var(--on-surface-muted);
      }
    `,
  ],
})
export class DictionarySheetComponent implements OnChanges {
  private readonly dictionary = inject(DictionaryService);

  readonly word = input.required<string>();
  readonly closed = output<void>();

  readonly loading = signal<boolean>(true);
  readonly error = signal<string | null>(null);
  readonly entry = signal<DictionaryEntry | null>(null);

  ngOnChanges(): void {
    void this.fetch();
  }

  private async fetch(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    this.entry.set(null);
    try {
      const res = await this.dictionary.lookup(this.word());
      this.entry.set(res);
    } catch (err) {
      this.error.set(
        err instanceof Error ? err.message : 'Word definition not found.',
      );
    } finally {
      this.loading.set(false);
    }
  }

  playPronunciation(url: string): void {
    if (typeof Audio === 'undefined') return;
    void new Audio(url).play().catch(() => null);
  }
}
