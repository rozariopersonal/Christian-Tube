import {
  ChangeDetectionStrategy,
  Component,
  OnInit,
  computed,
  inject,
  input,
  output,
  signal,
} from '@angular/core';
import { ReleaseDataService } from '../../../core/api/release-data.service';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';
import { BIBLE_VERSIONS, BibleVerse } from '../models/bible.model';

interface ComparedTranslation {
  id: string;
  label: string;
  fullName: string;
  text: string;
}

const COMPARE_IDS = ['nasb', 'kjv', 'asv', 'nlt', 'web', 'msg', 'ylt'];

@Component({
  selector: 'app-bible-compare-sheet',
  standalone: true,
  imports: [ModalSheetComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-modal-sheet [title]="sheetTitle()" (closed)="closed.emit()">
      @if (loading()) {
        <p class="status-msg">Loading translations...</p>
      } @else {
        <div class="compare-list">
          @for (item of items(); track item.id) {
            <div class="compare-card">
              <div class="compare-head">
                <span class="ver-badge">{{ item.label }}</span>
                <span class="muted">{{ item.fullName }}</span>
              </div>
              <p class="compare-text">{{ item.text }}</p>
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

      .compare-list {
        display: flex;
        flex-direction: column;
        gap: 10px;
        max-height: 60dvh;
        overflow-y: auto;
      }

      .compare-card {
        padding: 12px;
        border-radius: var(--radius-md);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
      }

      .compare-head {
        display: flex;
        align-items: center;
        gap: 8px;
        margin-bottom: 6px;
      }

      .ver-badge {
        padding: 2px 8px;
        border-radius: var(--radius-sm);
        background-color: var(--accent-soft);
        color: var(--accent);
        font-size: 11px;
        font-weight: 700;
      }

      .muted {
        font-size: 12px;
        color: var(--on-surface-muted);
      }

      .compare-text {
        margin: 0;
        font-size: 14px;
        line-height: 1.55;
      }
    `,
  ],
})
export class BibleCompareSheetComponent implements OnInit {
  private readonly releases = inject(ReleaseDataService);

  readonly bookNumber = input.required<number>();
  readonly chapter = input.required<number>();
  readonly verse = input.required<number>();
  readonly referenceLabel = input.required<string>();
  readonly closed = output<void>();

  readonly loading = signal<boolean>(true);
  readonly items = signal<ComparedTranslation[]>([]);

  readonly sheetTitle = computed(() => `Compare · ${this.referenceLabel()}`);

  ngOnInit(): void {
    void this.loadAll();
  }

  private async loadAll(): Promise<void> {
    this.loading.set(true);
    const targets = BIBLE_VERSIONS.filter((v) => COMPARE_IDS.includes(v.id));
    const loaded = await Promise.all(
      targets.map(async (v) => {
        try {
          const verses = await this.releases.getJson<BibleVerse[]>(
            `bibles/${v.id}/${this.bookNumber()}/${this.chapter()}.json`,
          );
          const match = verses.find((x) => x.verse === this.verse());
          return match
            ? {
                id: v.id,
                label: v.label,
                fullName: v.fullName,
                text: match.text,
              }
            : null;
        } catch {
          return null;
        }
      }),
    );
    this.items.set(loaded.filter((x): x is ComparedTranslation => x !== null));
    this.loading.set(false);
  }
}
