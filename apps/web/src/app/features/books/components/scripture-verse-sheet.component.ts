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
import { Router } from '@angular/router';
import { ReleaseDataService } from '../../../core/api/release-data.service';
import { BibleVersionPickerComponent } from '../../../shared/ui/bible-version-picker.component';
import { BibleVersionSelectionService } from '../../../core/services/bible-version-selection.service';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';
import {
  BOOK_ABBREVS,
  BibleVerse,
} from '../../bible/models/bible.model';
import { OnlineBibleService } from '../../bible/services/online-bible.service';
import { ParsedScriptureRef } from '../services/scripture-ref-parser.service';

@Component({
  selector: 'app-scripture-verse-sheet',
  standalone: true,
  imports: [ModalSheetComponent, BibleVersionPickerComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-modal-sheet [title]="sheetTitle()" (closed)="closed.emit()">
      <div class="ver-row">
        <app-bible-version-picker
          contextKey="books"
          [maxSelections]="1"
          (selectionChanged)="switchVersion($event.primary)"
        />
      </div>

      @if (loading()) {
        <p class="status-msg">Loading verse...</p>
      } @else if (error()) {
        <p class="status-msg">{{ error() }}</p>
      } @else if (matchedVerses().length === 0) {
        <p class="status-msg">Verse not found in {{ versionId().toUpperCase() }}.</p>
      } @else {
        <div class="verses-box">
          @for (v of matchedVerses(); track v.verse) {
            <p class="verse-line">
              <sup class="v-num">{{ v.verse }}</sup>
              <span>{{ v.text }}</span>
            </p>
          }
        </div>

        <div class="sheet-actions">
          <button type="button" class="pill-chip" (click)="copyVerses()">
            <span class="material-symbols-rounded">content_copy</span>
            Copy
          </button>
          <button type="button" class="pill-chip active" (click)="openInBible()">
            <span class="material-symbols-rounded">menu_book</span>
            Open in Bible
          </button>
        </div>
      }
    </app-modal-sheet>
  `,
  styles: [
    `
      .ver-row {
        display: flex;
        gap: 6px;
        flex-wrap: wrap;
      }

      .status-msg {
        padding: 20px 0;
        text-align: center;
        color: var(--on-surface-muted);
      }

      .verses-box {
        padding: 12px 14px;
        border-radius: var(--radius-md);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        max-height: 45dvh;
        overflow-y: auto;
        display: flex;
        flex-direction: column;
        gap: 8px;
      }

      .verse-line {
        margin: 0;
        font-size: 15px;
        line-height: 1.6;
      }

      .v-num {
        font-weight: 700;
        color: var(--accent);
        margin-right: 4px;
      }

      .sheet-actions {
        display: flex;
        justify-content: flex-end;
        gap: 8px;
      }
    `,
  ],
})
export class ScriptureVerseSheetComponent implements OnInit {
  private readonly releases = inject(ReleaseDataService);
  private readonly versionSelection = inject(BibleVersionSelectionService);
  private readonly onlineBible = inject(OnlineBibleService);
  private readonly router = inject(Router);

  readonly ref = input.required<ParsedScriptureRef>();
  readonly closed = output<void>();

  readonly versionId = signal<string>('nasb');
  readonly verses = signal<BibleVerse[]>([]);
  readonly loading = signal<boolean>(true);
  readonly error = signal<string | null>(null);

  readonly sheetTitle = computed(() => {
    const r = this.ref();
    const range =
      r.endVerse && r.endVerse > r.startVerse
        ? `${r.startVerse}-${r.endVerse}`
        : `${r.startVerse}`;
    return `${r.bookName} ${r.chapter}:${range}`;
  });

  readonly matchedVerses = computed(() => {
    const r = this.ref();
    const end = r.endVerse ?? r.startVerse;
    return this.verses().filter(
      (v) => v.verse >= r.startVerse && v.verse <= end,
    );
  });

  ngOnInit(): void {
    this.versionId.set(this.versionSelection.getPrimaryVersion('books'));
    void this.load();
  }

  switchVersion(id: string): void {
    this.versionId.set(id);
    void this.load();
  }

  private async load(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    const r = this.ref();
    try {
      const ver = this.versionId();
      const data = this.onlineBible.isOnlineVersion(ver)
        ? await this.onlineBible.fetchChapter(ver, r.bookNumber, r.chapter)
        : await this.releases.getJson<BibleVerse[]>(
            `bibles/${ver}/${r.bookNumber}/${r.chapter}.json`,
          );
      this.verses.set(data);
    } catch {
      if (this.versionId() !== 'kjv') {
        try {
          const fallback = await this.releases.getJson<BibleVerse[]>(
            `bibles/kjv/${r.bookNumber}/${r.chapter}.json`,
          );
          this.versionId.set('kjv');
          this.verses.set(fallback);
          return;
        } catch {
          // fall through to error
        }
      }
      this.error.set('Unable to load verse text.');
    } finally {
      this.loading.set(false);
    }
  }

  copyVerses(): void {
    const text = this.matchedVerses()
      .map((v) => `${v.verse} ${v.text}`)
      .join(' ');
    void navigator.clipboard?.writeText(
      `${this.sheetTitle()} (${this.versionId().toUpperCase()}) — ${text}`,
    );
  }

  openInBible(): void {
    const r = this.ref();
    const abbrev = BOOK_ABBREVS[r.bookNumber] || String(r.bookNumber);
    this.closed.emit();
    void this.router.navigate(['/bible'], {
      queryParams: {
        version: this.versionId(),
        book: abbrev,
        chapter: r.chapter,
        verse: r.startVerse,
      },
    });
  }
}
