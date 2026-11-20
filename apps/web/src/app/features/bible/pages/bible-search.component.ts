import {
  AfterViewInit,
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  OnInit,
  TemplateRef,
  ViewChild,
  effect,
  inject,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { ScreenClassService } from '../../../core/layout/screen-class.service';
import { HeaderSearchService } from '../../../core/services/header-search.service';
import { HeaderSlotService } from '../../../core/services/header-slot.service';
import { ScriptureRefParserService } from '../../books/services/scripture-ref-parser.service';
import { BibleVersionSheetComponent } from '../components/bible-version-sheet.component';
import { BIBLE_VERSIONS, BibleBook } from '../models/bible.model';
import { BibleService } from '../services/bible.service';

interface BibleSearchHit {
  bookNumber: number;
  bookName: string;
  chapter: number;
  verse: number;
  endVerse?: number | null;
  kind?: 'verse' | 'passage';
  reference?: string;
  text: string;
}

type SearchScope = 'book' | 'ot' | 'nt' | 'all';

@Component({
  selector: 'app-bible-search-page',
  standalone: true,
  imports: [FormsModule, RouterLink, BibleVersionSheetComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <ng-template #topbarRight>
      <button
        type="button"
        class="pill-chip"
        (click)="showVersionPicker.set(true)"
        aria-label="Bible Version"
      >
        {{ versionLabel(bible.version()) }}
      </button>
      <a
        class="pill-chip"
        [routerLink]="['/bible', bible.version(), bible.bookNumber(), bible.chapter()]"
      >
        Reader
      </a>
    </ng-template>

    <div class="bible-search-page max-width-box">
      @if (screen.isCompact()) {
        <form class="compact-search-form" (ngSubmit)="submitQuery()">
          <span class="material-symbols-rounded">search</span>
          <input
            type="search"
            placeholder="Search Bible verses or ref (e.g. John 3:16)..."
            [ngModel]="query()"
            name="qc"
            (ngModelChange)="query.set($event)"
          />
          <button type="submit" class="pill-chip active">Go</button>
        </form>
      }

      <div class="scope-row">
        <span class="scope-label">Scope:</span>
        @for (s of scopes; track s.id) {
          <button
            type="button"
            class="pill-chip"
            [class.active]="scope() === s.id"
            (click)="selectScope(s.id)"
          >
            {{ s.id === 'book' ? bible.currentBook().name : s.label }}
          </button>
        }
        <button
          type="button"
          class="pill-chip version-switch-chip"
          (click)="showVersionPicker.set(true)"
          aria-label="Switch Bible Version"
        >
          {{ versionLabel(bible.version()) }} ▾
        </button>
      </div>

      @if (directRef(); as ref) {
        <a
          class="ref-jump-card"
          [routerLink]="['/bible', bible.version(), ref.bookNumber, ref.chapter, ref.startVerse]"
        >
          <span class="material-symbols-rounded">menu_book</span>
          <div>
            <strong>Go to {{ refLabel(ref.bookNumber, ref.chapter, ref.startVerse) }}</strong>
            <p class="muted">Open passage directly in {{ versionLabel(bible.version()) }}</p>
          </div>
          <span class="material-symbols-rounded arrow">arrow_forward</span>
        </a>
      }

      @if (searching()) {
        <p class="status-msg">
          Searching {{ scope() === 'book' ? bible.currentBook().name : 'Bible' }}...
        </p>
      } @else if (!searched() && !directRef()) {
        <div class="empty-card">
          <span class="material-symbols-rounded state-icon">search</span>
          <p class="muted">Search by verse quote, topic, story, or reference (e.g. "jesus wept", "valley of dry bones", "John 3:16").</p>
        </div>
      } @else if (results().length === 0 && !directRef()) {
        <div class="empty-card">
          <span class="material-symbols-rounded state-icon">search_off</span>
          <p class="muted">No verses matched "{{ activeQuery() }}".</p>
        </div>
      } @else if (results().length > 0) {
        <p class="results-count">
          {{ results().length }}{{ results().length >= maxResults ? '+' : '' }} results for "{{ activeQuery() }}"
        </p>
        <div class="results-list">
          @for (hit of results(); track $index) {
            <a
              class="result-row"
              [routerLink]="['/bible', bible.version(), hit.bookNumber, hit.chapter, hit.verse]"
            >
              <div class="res-head">
                <span class="res-ref">
                  {{ hit.reference || (hit.bookName + ' ' + hit.chapter + ':' + hit.verse) }}
                </span>
                @if (hit.kind === 'passage') {
                  <span class="res-kind-pill">Passage</span>
                }
              </div>
              <p class="res-text">{{ hit.text }}</p>
            </a>
          }
        </div>
      }
    </div>

    @if (showVersionPicker()) {
      <app-bible-version-sheet
        [activeVersionId]="bible.version()"
        (versionSelected)="onVersionChange($event)"
        (closed)="showVersionPicker.set(false)"
      />
    }
  `,
  styles: [
    `
      .tb-bible-center {
        display: flex;
        align-items: center;
        gap: 8px;
        width: 100%;
        max-width: 780px;
        min-width: 0;
      }

      .version-pill,
      .back-reader-pill {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        height: 34px;
        padding: 0 10px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        font-size: 13px;
        font-weight: 600;
        white-space: nowrap;
        flex-shrink: 0;
      }

      .version-pill {
        background-color: var(--accent-soft);
        border-color: color-mix(in srgb, var(--accent) 45%, transparent);
        color: var(--accent);
      }

      .version-pill .material-symbols-rounded,
      .back-reader-pill .material-symbols-rounded {
        font-size: 17px;
      }

      .tb-search-form {
        flex: 1;
        min-width: 160px;
        height: 38px;
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 0 6px 0 12px;
        border-radius: var(--radius-pill);
        background-color: var(--bg);
        border: 1px solid var(--surface-border);
      }

      .tb-search-form:focus-within {
        border-color: var(--accent);
      }

      .tb-search-icon {
        font-size: 18px;
        color: var(--on-surface-muted);
      }

      .tb-search-input {
        flex: 1;
        min-width: 0;
        border: none;
        outline: none;
        background: transparent;
        font-size: 13px;
      }

      .tb-search-go {
        height: 28px;
        padding: 0 12px;
        border-radius: var(--radius-pill);
        background-color: var(--accent);
        color: var(--on-accent);
        font-size: 12px;
        font-weight: 600;
        flex-shrink: 0;
      }

      .bible-search-page {
        padding-top: 18px;
        padding-bottom: 48px;
        display: flex;
        flex-direction: column;
        gap: 14px;
      }

      .compact-search-form {
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 6px 8px 6px 12px;
        border-radius: var(--radius-pill);
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
      }

      .compact-search-form input {
        flex: 1;
        min-width: 0;
        border: none;
        outline: none;
        background: transparent;
        font-size: 14px;
      }

      .scope-row {
        display: flex;
        align-items: center;
        gap: 8px;
        flex-wrap: wrap;
      }

      .scope-label {
        font-size: 13px;
        font-weight: 600;
        color: var(--on-surface-muted);
      }

      .version-switch-chip {
        margin-left: auto;
        border-color: color-mix(in srgb, var(--accent) 45%, transparent);
        background-color: var(--accent-soft);
        color: var(--accent);
        font-weight: 600;
      }

      .ref-jump-card {
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 14px 16px;
        border-radius: var(--radius-md);
        background-color: var(--accent-soft);
        border: 1px solid color-mix(in srgb, var(--accent) 45%, transparent);
      }

      .ref-jump-card .arrow {
        margin-left: auto;
      }

      .results-count {
        margin: 0;
        font-size: 13px;
        color: var(--on-surface-muted);
      }

      .results-list {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }

      .result-row {
        display: block;
        padding: 14px 16px;
        border-radius: var(--radius-md);
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        transition: border-color 140ms ease;
      }

      .result-row:hover {
        border-color: var(--accent);
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
        font-size: 13px;
        font-weight: 700;
        color: var(--accent);
      }

      .res-kind-pill {
        font-size: 11px;
        font-weight: 600;
        padding: 2px 8px;
        border-radius: var(--radius-pill);
        background-color: var(--accent-soft);
        color: var(--accent);
        flex-shrink: 0;
      }

      .res-text {
        margin: 0;
        font-size: 14px;
        line-height: 1.5;
      }

      .empty-card,
      .status-msg {
        text-align: center;
        padding: 36px 20px;
        color: var(--on-surface-muted);
      }

      .state-icon {
        font-size: 36px;
        margin-bottom: 8px;
      }

      .muted {
        margin: 2px 0 0;
        font-size: 13px;
        color: var(--on-surface-muted);
      }
    `,
  ],
})
export class BibleSearchPageComponent implements OnInit, AfterViewInit {
  readonly bible = inject(BibleService);
  readonly screen = inject(ScreenClassService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly parser = inject(ScriptureRefParserService);
  private readonly headerSlot = inject(HeaderSlotService);
  private readonly headerSearch = inject(HeaderSearchService);
  private readonly destroyRef = inject(DestroyRef);

  @ViewChild('topbarRight') topbarRightRef?: TemplateRef<unknown>;
  private readonly viewInitialized = signal<boolean>(false);

  readonly scopes: readonly { id: SearchScope; label: string }[] = [
    { id: 'book', label: 'Current Book' },
    { id: 'ot', label: 'Old Testament' },
    { id: 'nt', label: 'New Testament' },
    { id: 'all', label: 'Entire Bible' },
  ];

  readonly query = signal<string>('');
  readonly activeQuery = signal<string>('');
  readonly scope = signal<SearchScope>('all');
  readonly searching = signal<boolean>(false);
  readonly searched = signal<boolean>(false);
  readonly results = signal<BibleSearchHit[]>([]);
  readonly directRef = signal<{
    bookNumber: number;
    chapter: number;
    startVerse: number;
  } | null>(null);
  readonly showVersionPicker = signal<boolean>(false);
  readonly maxResults = 60;

  private searchRunId = 0;
  private rawResults: BibleSearchHit[] = [];

  constructor() {
    this.destroyRef.onDestroy(() => this.headerSlot.clear());
    const unregisterSearch = this.headerSearch.register({
      placeholder: 'Search Bible verses or ref (e.g. John 3:16)...',
      onChange: (q) => this.query.set(q),
      onSubmit: (q) => {
        this.query.set(q);
        this.submitQuery();
      },
    });
    this.destroyRef.onDestroy(unregisterSearch);

    effect(() => {
      if (!this.viewInitialized()) return;
      if (this.screen.isMediumOrExpanded()) {
        this.headerSlot.setTemplates(null, this.topbarRightRef ?? null);
      } else {
        this.headerSlot.clear();
      }
    });
  }

  async ngOnInit(): Promise<void> {
    if (this.bible.books().length === 0) {
      await this.bible.loadChapter(
        this.bible.bookNumber(),
        this.bible.chapter(),
      );
    }

    this.route.queryParamMap.subscribe((qp) => {
      const q = qp.get('q') ?? '';
      const rawScope = qp.get('scope');
      const sc: SearchScope =
        rawScope === 'book' || rawScope === 'ot' || rawScope === 'nt' || rawScope === 'all'
          ? rawScope
          : 'all';
      this.query.set(q);
      this.headerSearch.pageQuery.set(q);
      this.scope.set(sc);
      if (q.trim().length >= 2) {
        void this.executeSearch(q, sc);
      } else {
        this.results.set([]);
        this.directRef.set(null);
        this.searched.set(false);
      }
    });
  }

  ngAfterViewInit(): void {
    this.viewInitialized.set(true);
  }

  submitQuery(): void {
    const q = this.query().trim();
    void this.router.navigate(['/bible/search'], {
      queryParams: { q: q || null, scope: this.scope() },
    });
  }

  selectScope(sc: SearchScope): void {
    this.scope.set(sc);
    if (this.query().trim().length >= 2) {
      this.submitQuery();
    }
  }

  async onVersionChange(versionId: string): Promise<void> {
    this.showVersionPicker.set(false);
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
    } else if (this.activeQuery().length >= 2) {
      void this.executeSearch(this.activeQuery(), this.scope());
    }
  }

  versionLabel(id: string): string {
    return (
      BIBLE_VERSIONS.find((v) => v.id === id)?.label ?? id.toUpperCase()
    );
  }

  refLabel(bookNum: number, ch: number, verse: number): string {
    const name =
      this.bible.books().find((b) => b.bookNumber === bookNum)?.name ??
      `Book ${bookNum}`;
    return `${name} ${ch}:${verse}`;
  }

  private async executeSearch(raw: string, scope: SearchScope): Promise<void> {
    const runId = ++this.searchRunId;
    const trimmed = raw.trim();
    this.activeQuery.set(trimmed);

    const parsed = this.parser.parseSearchQuery(trimmed);
    this.directRef.set(
      parsed
        ? {
            bookNumber: parsed.bookNumber,
            chapter: parsed.chapter,
            startVerse: parsed.startVerse,
          }
        : null,
    );

    this.searching.set(true);
    this.searched.set(true);
    this.rawResults = [];
    this.results.set([]);

    let remoteSucceeded = false;
    try {
      const remote = await this.bible.searchSemantic(trimmed, 50);
      if (runId !== this.searchRunId) return;
      remoteSucceeded = true;

      const currentBookNum = this.bible.bookNumber();
      const mapped: BibleSearchHit[] = [];
      for (const item of remote.results || []) {
        if (item.bookNumber == null || item.chapter == null || item.verse == null) {
          continue;
        }
        if (scope === 'book' && item.bookNumber !== currentBookNum) continue;
        if (scope === 'ot' && item.bookNumber > 39) continue;
        if (scope === 'nt' && item.bookNumber < 40) continue;

        const bookName =
          item.bookName ??
          this.bible.books().find((b) => b.bookNumber === item.bookNumber)?.name ??
          `Book ${item.bookNumber}`;
        mapped.push({
          bookNumber: item.bookNumber,
          bookName,
          chapter: item.chapter,
          verse: item.verse,
          endVerse: item.endVerse ?? null,
          kind: item.kind,
          reference: item.reference,
          text: item.text,
        });
      }

      if (mapped.length > 0) {
        this.rawResults = mapped;
        const localized = await this.bible.resolveSearchHitsInVersion(
          mapped,
          this.bible.version(),
        );
        if (runId !== this.searchRunId) return;
        this.results.set(localized);
        this.searching.set(false);
        return;
      }

      // If semantic search succeeded with 0 relevant hits above threshold for broad scopes,
      // don't download hundreds of chapters for client-side substring scanning.
      if (remoteSucceeded && scope !== 'book') {
        this.searching.set(false);
        return;
      }
    } catch {
      // Fall back to local CDN chapter scan when offline or backend unreachable
    }

    const books = this.targetBooks(scope);
    const q = trimmed.toLowerCase();
    const hits: BibleSearchHit[] = [];

    const tasks: { book: BibleBook; ch: number }[] = [];
    for (const book of books) {
      for (let ch = 1; ch <= book.chapters; ch++) {
        tasks.push({ book, ch });
      }
    }

    const batchSize = 6;
    for (let i = 0; i < tasks.length; i += batchSize) {
      if (runId !== this.searchRunId || hits.length >= this.maxResults) break;
      const slice = tasks.slice(i, i + batchSize);
      const batchVerses = await Promise.all(
        slice.map(async ({ book, ch }) => {
          try {
            const verses = await this.bible.fetchChapterVerses(
              this.bible.version(),
              book.bookNumber,
              ch,
              true,
            );
            return { book, ch, verses };
          } catch {
            return { book, ch, verses: [] };
          }
        }),
      );

      for (const { book, ch, verses } of batchVerses) {
        for (const v of verses) {
          if (v.text.toLowerCase().includes(q)) {
            hits.push({
              bookNumber: book.bookNumber,
              bookName: book.name,
              chapter: ch,
              verse: v.verse,
              text: v.text,
            });
            if (hits.length >= this.maxResults) break;
          }
        }
        if (hits.length >= this.maxResults) break;
      }

      if (runId === this.searchRunId) {
        this.results.set([...hits]);
      }
    }

    if (runId === this.searchRunId) {
      this.results.set(hits);
      this.searching.set(false);
    }
  }

  private targetBooks(scope: SearchScope): BibleBook[] {
    const all = this.bible.books();
    if (scope === 'ot') return all.filter((b) => b.bookNumber <= 39);
    if (scope === 'nt') return all.filter((b) => b.bookNumber >= 40);
    if (scope === 'all') return all;
    return [this.bible.currentBook()];
  }
}
