import {
  ChangeDetectionStrategy,
  Component,
  computed,
  inject,
  input,
  output,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { ReleaseDataService } from '../../../core/api/release-data.service';
import { BibleVersionPickerComponent } from '../../../shared/ui/bible-version-picker.component';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';
import { ScriptureRefParserService } from '../../books/services/scripture-ref-parser.service';
import { BibleBook, BibleVerse } from '../models/bible.model';
import { BibleService } from '../services/bible.service';

export interface BibleSearchHit {
  bookNumber: number;
  bookName: string;
  chapter: number;
  verse: number;
  endVerse?: number | null;
  kind?: 'verse' | 'passage';
  reference?: string;
  text: string;
}

@Component({
  selector: 'app-bible-search-sheet',
  standalone: true,
  imports: [FormsModule, ModalSheetComponent, BibleVersionPickerComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-modal-sheet title="Search Bible" (closed)="closed.emit()">
      <form class="search-form" (submit)="runSearch($event)">
        <div class="sheet-search">
          <span class="material-symbols-rounded">search</span>
          <input
            type="search"
            placeholder="Search words or reference (e.g. John 3:16)..."
            [ngModel]="query()"
            name="q"
            (ngModelChange)="query.set($event)"
          />
        </div>
        <app-bible-version-picker
          contextKey="bible"
          [maxSelections]="1"
          [alignRight]="true"
          (selectionChanged)="onVersionChange($event.primary)"
        />
        <button type="submit" class="pill-chip active">Search</button>
      </form>

      @if (searching()) {
        <p class="status-msg">Searching Bible...</p>
      } @else if (searched() && results().length === 0) {
        <p class="status-msg">No verses matched "{{ query().trim() }}".</p>
      } @else {
        <div class="results-list">
          @for (r of results(); track $index) {
            <button
              type="button"
              class="result-row"
              (click)="jumpTo.emit({ bookNumber: r.bookNumber, chapter: r.chapter, verse: r.verse })"
            >
              <div class="res-head">
                <span class="res-ref">
                  {{ r.reference || (r.bookName + ' ' + r.chapter + ':' + r.verse) }}
                </span>
                @if (r.kind === 'passage') {
                  <span class="res-kind-pill">Passage</span>
                }
              </div>
              <p class="res-text">{{ r.text }}</p>
            </button>
          }
        </div>
        @if (results().length > 0 && query().trim().length >= 2) {
          <button type="button" class="full-results-btn" (click)="openFullResults()">
            Open full results screen
            <span class="material-symbols-rounded">arrow_forward</span>
          </button>
        }
      }
    </app-modal-sheet>
  `,
  styles: [
    `
      .search-form {
        display: flex;
        gap: 8px;
        align-items: center;
      }

      .sheet-search {
        flex: 1;
        min-width: 0;
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

      .status-msg {
        padding: 20px 0;
        text-align: center;
        color: var(--on-surface-muted);
      }

      .results-list {
        display: flex;
        flex-direction: column;
        gap: 8px;
        max-height: 55dvh;
        overflow-y: auto;
      }

      .result-row {
        padding: 10px 12px;
        border-radius: var(--radius-md);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        text-align: left;
      }

      .res-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
        margin-bottom: 4px;
      }

      .res-ref {
        display: block;
        font-size: 12px;
        font-weight: 700;
        color: var(--accent);
      }

      .res-kind-pill {
        font-size: 10px;
        font-weight: 600;
        padding: 1px 7px;
        border-radius: var(--radius-pill);
        background-color: var(--accent-soft);
        color: var(--accent);
        flex-shrink: 0;
      }

      .res-text {
        margin: 0;
        font-size: 13px;
        line-height: 1.45;
      }

      .full-results-btn {
        margin-top: 10px;
        width: 100%;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 6px;
        padding: 10px 14px;
        border-radius: var(--radius-pill);
        background-color: var(--accent-soft);
        color: var(--accent);
        font-size: 13px;
        font-weight: 600;
      }
    `,
  ],
})
export class BibleSearchSheetComponent {
  private readonly releases = inject(ReleaseDataService);
  private readonly bible = inject(BibleService);
  private readonly router = inject(Router);
  private readonly parser = inject(ScriptureRefParserService);

  readonly version = input.required<string>();
  readonly currentBook = input.required<BibleBook>();
  readonly jumpTo = output<{ bookNumber: number; chapter: number; verse: number }>();
  readonly closed = output<void>();

  readonly query = signal<string>('');
  readonly searching = signal<boolean>(false);
  readonly searched = signal<boolean>(false);
  readonly results = signal<BibleSearchHit[]>([]);
  private rawResults: BibleSearchHit[] = [];

  async onVersionChange(versionId: string): Promise<void> {
    await this.bible.loadVersion(
      versionId,
      this.bible.bookNumber(),
      this.bible.chapter(),
    );
    if (this.rawResults.length > 0) {
      const resolved = await this.bible.resolveSearchHitsInVersion(
        this.rawResults,
        this.bible.version(),
      );
      this.results.set(resolved);
    }
  }

  openFullResults(): void {
    const q = this.query().trim();
    this.closed.emit();
    void this.router.navigate(['/bible/search'], {
      queryParams: q ? { q, scope: 'all' } : undefined,
    });
  }

  async runSearch(event: Event): Promise<void> {
    event.preventDefault();
    const raw = this.query().trim();
    if (raw.length < 2) return;

    // 1. Check if the query is a direct scripture reference (e.g. "John 3:16" or "mathew 6:33")
    const parsed = this.parser.parseSearchQuery(raw);
    if (parsed) {
      this.jumpTo.emit({
        bookNumber: parsed.bookNumber,
        chapter: parsed.chapter,
        verse: parsed.startVerse,
      });
      return;
    }

    this.searching.set(true);
    this.searched.set(true);
    this.rawResults = [];

    // 2. Semantic + hybrid passage search via backend
    try {
      const remote = await this.bible.searchSemantic(raw, 25);
      const mapped: BibleSearchHit[] = [];
      for (const item of remote.results || []) {
        if (item.bookNumber == null || item.chapter == null || item.verse == null) {
          continue;
        }
        mapped.push({
          bookNumber: item.bookNumber,
          bookName: item.bookName ?? `Book ${item.bookNumber}`,
          chapter: item.chapter,
          verse: item.verse,
          endVerse: item.endVerse ?? null,
          kind: item.kind,
          reference: item.reference,
          text: item.text,
        });
      }
      this.rawResults = mapped;
      const localized = await this.bible.resolveSearchHitsInVersion(
        mapped,
        this.bible.version(),
      );
      this.results.set(localized);
      this.searching.set(false);
      return;
    } catch {
      // Fall through to current-book local scan if offline
    }

    // 3. Fallback: search all chapters of the current book
    const q = raw.toLowerCase();
    const book = this.currentBook();
    const hits: BibleSearchHit[] = [];

    for (let ch = 1; ch <= book.chapters; ch++) {
      if (hits.length >= 40) break;
      try {
        const verses = await this.releases.getJson<BibleVerse[]>(
          `bibles/${this.version()}/${book.bookNumber}/${ch}.json`,
        );
        for (const v of verses) {
          if (v.text.toLowerCase().includes(q)) {
            hits.push({
              bookNumber: book.bookNumber,
              bookName: book.name,
              chapter: ch,
              verse: v.verse,
              text: v.text,
            });
            if (hits.length >= 40) break;
          }
        }
      } catch {
        // skip chapter if unavailable
      }
    }

    this.results.set(hits);
    this.searching.set(false);
  }
}
