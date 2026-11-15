import { ChangeDetectionStrategy, Component, computed, input, output } from '@angular/core';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';
import { StudyTerm } from '../models/bible.model';

@Component({
  selector: 'app-bible-study-sheet',
  standalone: true,
  imports: [ModalSheetComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-modal-sheet [title]="sheetTitle()" (closed)="closed.emit()">
      <div class="study-list">
        @for (t of terms(); track $index) {
          <div class="study-card">
            <h3>{{ t.concept_name || t.english_name }}</h3>
            @if (t.lemma) {
              <p class="lemma">Lemma: {{ t.lemma }}</p>
            }
            @if (t.definition) {
              <p>{{ t.definition }}</p>
            }
            @if (t.biblical_meaning) {
              <p class="muted">{{ t.biblical_meaning }}</p>
            }
          </div>
        }
      </div>
    </app-modal-sheet>
  `,
  styles: [
    `
      .study-list {
        display: flex;
        flex-direction: column;
        gap: 10px;
        max-height: 55dvh;
        overflow-y: auto;
      }

      .study-card {
        padding: 12px;
        border-radius: var(--radius-md);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
      }

      .study-card h3 {
        margin: 0 0 6px;
        font-size: 16px;
      }

      .study-card p {
        margin: 4px 0;
        font-size: 14px;
      }

      .lemma {
        font-weight: 600;
        color: var(--accent);
      }

      .muted {
        color: var(--on-surface-muted);
      }
    `,
  ],
})
export class BibleStudySheetComponent {
  readonly verseNumber = input.required<number>();
  readonly terms = input.required<StudyTerm[]>();
  readonly closed = output<void>();

  readonly sheetTitle = computed(
    () => `Study & Lexicon · Verse ${this.verseNumber()}`,
  );
}
