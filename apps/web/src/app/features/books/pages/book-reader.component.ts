import {
  ChangeDetectionStrategy,
  Component,
  HostListener,
  OnInit,
  computed,
  inject,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { combineLatest } from 'rxjs';
import { ReaderAppearanceService } from '../../../core/services/reader-appearance.service';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';
import { BookAppearanceSheetComponent } from '../components/book-appearance-sheet.component';
import { BookHighlightsSheetComponent } from '../components/book-highlights-sheet.component';
import { BookLineActionBarComponent } from '../components/book-line-action-bar.component';
import { BookReaderNavComponent } from '../components/book-reader-nav.component';
import { BookSearchSheetComponent } from '../components/book-search-sheet.component';
import { BookTocSheetComponent } from '../components/book-toc-sheet.component';
import { DictionarySheetComponent } from '../components/dictionary-sheet.component';
import { ScriptureVerseSheetComponent } from '../components/scripture-verse-sheet.component';
import { BookLine, BookToc } from '../models/book.model';
import {
  BookBookmark,
  BookHighlight,
  BookHighlightsService,
} from '../services/book-highlights.service';
import { BooksService } from '../services/books.service';
import {
  ParsedScriptureRef,
  ScriptureRefParserService,
  ScriptureSpanToken,
} from '../services/scripture-ref-parser.service';

@Component({
  selector: 'app-book-reader',
  standalone: true,
  imports: [
    FormsModule,
    ModalSheetComponent,
    BookTocSheetComponent,
    BookAppearanceSheetComponent,
    BookHighlightsSheetComponent,
    BookLineActionBarComponent,
    BookReaderNavComponent,
    BookSearchSheetComponent,
    DictionarySheetComponent,
    ScriptureVerseSheetComponent,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div
      class="book-reader-page"
      [attr.data-paper]="appearance.paperTheme()"
      [class.immersive]="immersive()"
    >
      @if (!immersive()) {
        <header class="reader-bar">
          <div class="bar-inner max-width-box">
            <button type="button" class="toc-btn" (click)="showToc.set(true)">
              <span class="material-symbols-rounded">toc</span>
              <span class="book-name">{{ toc()?.title || 'Book Reader' }}</span>
            </button>

            <div class="bar-actions">
              <button
                type="button"
                class="icon-btn"
                title="Search inside book"
                (click)="showSearch.set(true)"
              >
                <span class="material-symbols-rounded">search</span>
              </button>
              <button
                type="button"
                class="icon-btn"
                title="Bookmark this chapter"
                (click)="toggleChapterBookmark()"
              >
                <span
                  class="material-symbols-rounded"
                  [class.filled]="isChapterBookmarked()"
                  [class.accent-icon]="isChapterBookmarked()"
                >
                  bookmark
                </span>
              </button>
              <button
                type="button"
                class="icon-btn"
                title="Notebook (Highlights & Bookmarks)"
                (click)="showHighlights.set(true)"
              >
                <span class="material-symbols-rounded">border_color</span>
              </button>
              <button
                type="button"
                class="icon-btn"
                title="Share book link"
                (click)="shareLocation()"
              >
                <span class="material-symbols-rounded">share</span>
              </button>
              <button
                type="button"
                class="icon-btn aa-btn"
                title="Display & Layout"
                (click)="showAppearance.set(true)"
              >
                Aa
              </button>
              <button
                type="button"
                class="icon-btn"
                title="Focus mode (F)"
                (click)="immersive.set(true)"
              >
                <span class="material-symbols-rounded">fullscreen</span>
              </button>
            </div>
          </div>
        </header>
      } @else {
        <button
          type="button"
          class="exit-focus-btn"
          title="Exit focus mode (Esc / F)"
          (click)="immersive.set(false)"
        >
          <span class="material-symbols-rounded">fullscreen_exit</span>
        </button>
      }

      <div
        class="reader-content max-width-box"
        [attr.data-margin]="appearance.bookMargin()"
        [class.two-col]="appearance.bookColumns() === 2"
      >
        @if (loading()) {
          <p class="status-msg">Loading chapter...</p>
        } @else if (error()) {
          <p class="status-msg">{{ error() }}</p>
        } @else {
          <header class="chapter-hero">
            <span class="hero-eyebrow">
              {{ toc()?.title }} · Chapter {{ chapterIndex() }}
            </span>
            @if (currentChapterTitle()) {
              <h1 class="hero-title font-display">{{ currentChapterTitle() }}</h1>
            }
            <div class="hero-meta">
              @if (toc()?.author) {
                <span>{{ toc()!.author }}</span>
                <span>·</span>
              }
              <span>{{ readingMinutes() }} min read</span>
            </div>
          </header>

          <article
            class="chapter-body"
            [class.two-col-body]="appearance.bookColumns() === 2"
            [style.font-family]="appearance.activeFont().cssFamily"
            [style.font-size.px]="appearance.fontSize()"
            [style.line-height]="appearance.lineHeight()"
            [style.text-align]="appearance.bookAlign()"
            (dblclick)="lookupFromSelection()"
          >
            @for (item of parsedLines(); track $index) {
              @let line = item.line;
              @let hl = highlightColor($index);
              @let note = noteFor($index);
              @if (line.isHeading) {
                <h2
                  [id]="'book-line-' + $index"
                  class="chapter-heading"
                  [class.sub-heading]="(line.headingLevel ?? 1) > 1"
                >
                  {{ line.text }}
                </h2>
              } @else {
                <div
                  [id]="'book-line-' + $index"
                  class="chapter-para"
                  [class.is-quote]="isQuoteLine(line)"
                  [class.selected]="selectedIndex() === $index"
                  [style.background-color]="hl ? hl + '55' : null"
                  (click)="toggleSelectLine($index)"
                >
                  <p class="para-text">
                    @for (tok of item.tokens; track $index) {
                      @if (tok.ref) {
                        <button
                          type="button"
                          class="scripture-link"
                          (click)="$event.stopPropagation(); activeScriptureRef.set(tok.ref!)"
                        >
                          {{ tok.text }}
                        </button>
                      } @else {
                        <span>{{ tok.text }}</span>
                      }
                    }
                  </p>
                  @if (note) {
                    <p class="para-note">{{ note }}</p>
                  }
                </div>
              }
            }
          </article>
        }
      </div>

      @if (selectedLine(); as sel) {
        <app-book-line-action-bar
          [line]="sel"
          (define)="defineSelected()"
          (openNote)="openNoteEditor()"
          (copy)="copySelected()"
          (share)="shareLocation(selectedIndex()!)"
          (highlightChanged)="setHighlight(selectedIndex()!, sel, $event)"
          (closed)="selectedIndex.set(null)"
        />
      } @else if (!immersive() && !loading() && toc()) {
        <app-book-reader-nav
          [chapterIndex]="chapterIndex()"
          [totalChapters]="toc()!.chapters.length || 1"
          [chapterTitle]="currentChapterTitle()"
          [readingMinutes]="readingMinutes()"
          (previous)="loadChapter(chapterIndex() - 1)"
          (next)="loadChapter(chapterIndex() + 1)"
          (openToc)="showToc.set(true)"
        />
      }

      @if (showToc() && toc()) {
        <app-book-toc-sheet
          [chapters]="toc()!.chapters"
          [currentChapter]="chapterIndex()"
          (chapterSelected)="selectChapter($event)"
          (closed)="showToc.set(false)"
        />
      }

      @if (showAppearance()) {
        <app-book-appearance-sheet (closed)="showAppearance.set(false)" />
      }

      @if (showHighlights()) {
        <app-book-highlights-sheet
          [highlights]="bookHighlights()"
          [bookmarks]="bookBookmarks()"
          (jumpTo)="jumpToHighlight($event)"
          (removed)="removeHighlight($event)"
          (bookmarkRemoved)="removeBookmark($event)"
          (closed)="showHighlights.set(false)"
        />
      }

      @if (showSearch() && toc()) {
        <app-book-search-sheet
          [bookId]="currentBookId()"
          [bookLang]="currentBookLang()"
          [toc]="toc()!"
          (jumpTo)="jumpToHighlight($event)"
          (closed)="showSearch.set(false)"
        />
      }

      @if (activeScriptureRef(); as sRef) {
        <app-scripture-verse-sheet
          [ref]="sRef"
          (closed)="activeScriptureRef.set(null)"
        />
      }

      @if (lookupWord(); as word) {
        <app-dictionary-sheet
          [word]="word"
          (closed)="lookupWord.set(null)"
        />
      }

      @if (showNoteModal() && selectedLine()) {
        <app-modal-sheet title="Paragraph Note" (closed)="showNoteModal.set(false)">
          <textarea
            class="note-textarea"
            rows="4"
            [ngModel]="noteDraft()"
            (ngModelChange)="noteDraft.set($event)"
            placeholder="Write your note..."
          ></textarea>
          <div class="modal-actions">
            <button type="button" class="pill-chip" (click)="showNoteModal.set(false)">
              Cancel
            </button>
            <button type="button" class="pill-chip active" (click)="saveNote()">
              Save Note
            </button>
          </div>
        </app-modal-sheet>
      }
    </div>
  `,
  styles: [
    `
      .book-reader-page {
        min-height: calc(100dvh - var(--shell-top-offset));
        background-color: var(--reader-bg, var(--bg));
        color: var(--reader-fg, var(--on-surface));
        transition: background-color 180ms ease, color 180ms ease;
      }

      .book-reader-page[data-paper='paper'] {
        --reader-bg: #faf8f5;
        --reader-fg: #1f2937;
        --reader-muted: #6b7280;
        --reader-border: rgba(31, 41, 55, 0.12);
      }

      .book-reader-page[data-paper='sepia'] {
        --reader-bg: #f4ecd8;
        --reader-fg: #433422;
        --reader-muted: #78644c;
        --reader-border: rgba(67, 52, 34, 0.14);
      }

      .book-reader-page[data-paper='night'] {
        --reader-bg: #121620;
        --reader-fg: #e2e8f0;
        --reader-muted: #94a3b8;
        --reader-border: rgba(226, 232, 240, 0.12);
      }

      .reader-bar {
        position: sticky;
        top: var(--shell-top-offset);
        z-index: 30;
        background-color: color-mix(in srgb, var(--reader-bg, var(--bg)) 90%, transparent);
        backdrop-filter: blur(12px);
        -webkit-backdrop-filter: blur(12px);
        border-bottom: 1px solid var(--reader-border, var(--surface-border));
      }

      .bar-inner {
        height: var(--topbar-height);
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
      }

      .toc-btn {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        min-width: 0;
        font-weight: 700;
        font-size: 15px;
      }

      .book-name {
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .bar-actions {
        display: flex;
        align-items: center;
        gap: 2px;
        flex-shrink: 0;
      }

      .accent-icon {
        color: var(--accent);
      }

      .aa-btn {
        font-family: Georgia, serif;
        font-weight: 700;
        font-size: 16px;
      }

      .exit-focus-btn {
        position: fixed;
        top: calc(var(--shell-top-offset) + 12px);
        right: 16px;
        z-index: 40;
        width: 40px;
        height: 40px;
        border-radius: var(--radius-pill);
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        display: grid;
        place-items: center;
        opacity: 0.75;
      }

      .exit-focus-btn:hover {
        opacity: 1;
      }

      .reader-content {
        padding-top: 28px;
        padding-bottom: 120px;
        max-width: 720px;
        transition: max-width 200ms ease;
      }

      .reader-content[data-margin='narrow'] {
        max-width: 600px;
      }

      .reader-content[data-margin='wide'] {
        max-width: 880px;
      }

      @media (min-width: 840px) {
        .reader-content.two-col {
          max-width: 1080px;
        }

        .chapter-body.two-col-body {
          display: block;
          column-count: 2;
          column-gap: 44px;
          column-rule: 1px solid var(--reader-border, var(--surface-border));
        }

        .chapter-body.two-col-body .chapter-para,
        .chapter-body.two-col-body .chapter-heading {
          break-inside: avoid;
          margin-bottom: 12px;
        }
      }

      .chapter-hero {
        margin-bottom: 24px;
        padding-bottom: 18px;
        border-bottom: 1px solid var(--reader-border, var(--surface-border));
      }

      .hero-eyebrow {
        display: block;
        font-size: 12px;
        font-weight: 700;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: var(--accent);
        margin-bottom: 6px;
      }

      .hero-title {
        margin: 0 0 8px;
        font-size: clamp(22px, 3vw, 30px);
        line-height: 1.25;
        font-weight: 700;
      }

      .hero-meta {
        display: flex;
        align-items: center;
        gap: 6px;
        flex-wrap: wrap;
        font-size: 13px;
        color: var(--reader-muted, var(--on-surface-muted));
      }

      .chapter-body {
        display: flex;
        flex-direction: column;
        gap: 12px;
      }

      .chapter-heading {
        margin: 18px 0 4px;
        font-size: 1.2em;
        font-weight: 700;
        line-height: 1.3;
      }

      .chapter-heading.sub-heading {
        font-size: 1.05em;
      }

      .chapter-para {
        margin: 0;
        padding: 4px 8px;
        border-radius: var(--radius-sm);
        cursor: pointer;
        transition: background-color 120ms ease;
      }

      .chapter-para:hover {
        background-color: color-mix(in srgb, var(--accent) 7%, transparent);
      }

      .chapter-para.selected {
        outline: 2px solid var(--accent);
      }

      .chapter-para.is-quote {
        border-left: 3px solid var(--accent);
        padding-left: 14px;
        font-style: italic;
        color: var(--reader-muted, var(--on-surface-muted));
      }

      .para-text {
        margin: 0;
      }

      .para-note {
        margin: 6px 0 2px;
        padding: 6px 10px;
        border-radius: var(--radius-sm);
        background-color: var(--accent-soft);
        border-left: 2px solid var(--accent);
        font-size: 0.85em;
        color: var(--reader-muted, var(--on-surface-muted));
      }

      .scripture-link {
        color: var(--accent);
        text-decoration: underline;
        text-decoration-style: dotted;
        text-underline-offset: 3px;
        font-weight: 600;
      }

      .scripture-link:hover {
        text-decoration-style: solid;
      }

      .status-msg {
        text-align: center;
        padding: 48px 0;
        color: var(--reader-muted, var(--on-surface-muted));
      }

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
export class BookReaderComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly booksService = inject(BooksService);
  private readonly highlightsService = inject(BookHighlightsService);
  private readonly scriptureParser = inject(ScriptureRefParserService);
  readonly appearance = inject(ReaderAppearanceService);

  readonly toc = signal<BookToc | null>(null);
  readonly lines = signal<BookLine[]>([]);
  readonly chapterIndex = signal<number>(1);
  readonly loading = signal<boolean>(true);
  readonly error = signal<string | null>(null);
  readonly selectedIndex = signal<number | null>(null);
  readonly immersive = signal<boolean>(false);

  readonly showToc = signal<boolean>(false);
  readonly showAppearance = signal<boolean>(false);
  readonly showHighlights = signal<boolean>(false);
  readonly showSearch = signal<boolean>(false);
  readonly showNoteModal = signal<boolean>(false);
  readonly noteDraft = signal<string>('');
  readonly activeScriptureRef = signal<ParsedScriptureRef | null>(null);
  readonly lookupWord = signal<string | null>(null);

  readonly currentBookId = signal<string>('');
  readonly currentBookLang = signal<string | undefined>(undefined);

  readonly selectedLine = computed(() => {
    const idx = this.selectedIndex();
    return idx !== null ? (this.lines()[idx] ?? null) : null;
  });

  readonly parsedLines = computed<
    Array<{ line: BookLine; tokens: ScriptureSpanToken[] }>
  >(() =>
    this.lines().map((line) => ({
      line,
      tokens: line.isHeading ? [] : this.scriptureParser.parse(line.text),
    })),
  );

  readonly currentChapterTitle = computed(() => {
    const ch = this.toc()?.chapters.find(
      (c) => c.chapterIndex === this.chapterIndex(),
    );
    return ch?.title ?? '';
  });

  readonly readingMinutes = computed(() => {
    const words = this.lines().reduce(
      (acc, l) => acc + (l.text ? l.text.split(/\s+/).length : 0),
      0,
    );
    return Math.max(1, Math.round(words / 220));
  });

  readonly bookHighlights = computed(() => {
    const id = this.currentBookId();
    return id ? this.highlightsService.forBook(id) : [];
  });

  readonly bookBookmarks = computed(() => {
    const id = this.currentBookId();
    return id ? this.highlightsService.bookmarksForBook(id) : [];
  });

  readonly isChapterBookmarked = computed(() => {
    const id = this.currentBookId();
    return id
      ? this.highlightsService.isBookmarked(id, this.chapterIndex())
      : false;
  });

  @HostListener('window:keydown', ['$event'])
  onKeyDown(event: KeyboardEvent): void {
    const target = event.target as HTMLElement | null;
    if (
      target &&
      (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA')
    ) {
      return;
    }

    if (event.key === 'Escape') {
      this.selectedIndex.set(null);
      this.showToc.set(false);
      this.showAppearance.set(false);
      this.showHighlights.set(false);
      this.showSearch.set(false);
      this.showNoteModal.set(false);
      this.activeScriptureRef.set(null);
      this.lookupWord.set(null);
      this.immersive.set(false);
      return;
    }
    if (event.key === 'f' || event.key === 'F') {
      this.immersive.set(!this.immersive());
      return;
    }
    if (
      this.showToc() ||
      this.showAppearance() ||
      this.showHighlights() ||
      this.showSearch() ||
      this.showNoteModal() ||
      this.activeScriptureRef() ||
      this.lookupWord()
    ) {
      return;
    }
    const total = this.toc()?.chapters.length || 1;
    if (event.key === 'ArrowLeft' && this.chapterIndex() > 1) {
      void this.loadChapter(this.chapterIndex() - 1);
    } else if (event.key === 'ArrowRight' && this.chapterIndex() < total) {
      void this.loadChapter(this.chapterIndex() + 1);
    }
  }

  ngOnInit(): void {
    void this.booksService.loadCatalog();
    combineLatest([this.route.paramMap, this.route.queryParamMap]).subscribe(
      ([params, query]) => {
        const id = params.get('id');
        if (!id) return;
        const chRaw = params.get('chapter') ?? query.get('chapter');
        const pageRaw = query.get('page');
        const lineRaw = query.get('line');
        const targetChapter = chRaw ? Number(chRaw) : undefined;
        const targetPage = pageRaw ? Number(pageRaw) : undefined;
        const targetLine = lineRaw ? Number(lineRaw) : undefined;

        const sameBook = id === this.currentBookId() && this.toc() !== null;
        if (
          sameBook &&
          targetChapter === this.chapterIndex() &&
          !targetPage &&
          !targetLine
        ) {
          return;
        }
        void this.openBook(id, {
          chapter:
            targetChapter && Number.isFinite(targetChapter)
              ? targetChapter
              : undefined,
          page:
            targetPage && Number.isFinite(targetPage) ? targetPage : undefined,
          line:
            targetLine && Number.isFinite(targetLine) ? targetLine : undefined,
        });
      },
    );
  }

  async openBook(
    bookId: string,
    target?: { chapter?: number; page?: number; line?: number },
  ): Promise<void> {
    this.currentBookId.set(bookId);
    this.loading.set(true);
    this.error.set(null);
    this.selectedIndex.set(null);
    const catalogItem = this.booksService
      .catalog()
      .find((b) => b.id === bookId);
    this.currentBookLang.set(catalogItem?.lang);

    try {
      const toc = await this.booksService.fetchToc(bookId, catalogItem?.lang);
      this.toc.set(toc);
      let initialCh =
        target?.chapter ??
        (target?.page ? this.chapterForPage(toc, target.page) : undefined) ??
        this.booksService.progressMap()[bookId]?.chapterIndex ??
        1;
      initialCh = Math.min(toc.chapters.length || 1, Math.max(1, initialCh));
      await this.loadChapter(initialCh, target);
    } catch (err) {
      this.error.set(
        err instanceof Error ? err.message : 'Unable to open book',
      );
      this.loading.set(false);
    }
  }

  private chapterForPage(toc: BookToc, page: number): number | undefined {
    const exact = toc.chapters.find(
      (c) =>
        c.startPage !== undefined &&
        c.endPage !== undefined &&
        page >= c.startPage &&
        page <= c.endPage,
    );
    if (exact) return exact.chapterIndex;
    const candidates = toc.chapters.filter(
      (c) => c.startPage !== undefined && c.startPage <= page,
    );
    return candidates.length > 0
      ? candidates[candidates.length - 1].chapterIndex
      : undefined;
  }

  async loadChapter(
    ch: number,
    target?: { page?: number; line?: number },
  ): Promise<void> {
    const bookId = this.currentBookId();
    this.loading.set(true);
    this.error.set(null);
    this.selectedIndex.set(null);
    this.chapterIndex.set(ch);
    try {
      const lines = await this.booksService.fetchChapter(
        bookId,
        ch,
        this.currentBookLang(),
        this.toc()?.chapters.length,
      );
      this.lines.set(lines);
      const toc = this.toc();
      if (toc) {
        const catalogItem = this.booksService
          .catalog()
          .find((b) => b.id === bookId);
        this.booksService.saveProgress({
          bookId,
          title: toc.title,
          author: toc.author,
          coverFile: catalogItem?.coverFile,
          chapterIndex: ch,
          totalChapters: toc.chapters.length,
          updatedAt: new Date().toISOString(),
        });
      }

      const chapterMeta = toc?.chapters.find((c) => c.chapterIndex === ch);
      const syncPage = target?.page ?? chapterMeta?.startPage;
      void this.router.navigate(['/books', bookId], {
        queryParams: {
          chapter: ch,
          ...(syncPage ? { page: syncPage } : {}),
        },
        replaceUrl: true,
      });

      const scrollIdx =
        target?.line !== undefined &&
        target.line >= 0 &&
        target.line < lines.length
          ? target.line
          : target?.page
            ? lines.findIndex((l) => (l.page ?? 0) >= target.page!)
            : -1;

      if (scrollIdx >= 0) {
        setTimeout(() => {
          document
            .getElementById(`book-line-${scrollIdx}`)
            ?.scrollIntoView({ behavior: 'smooth', block: 'center' });
        }, 60);
      } else {
        window.scrollTo({ top: 0, behavior: 'smooth' });
      }
    } catch (err) {
      this.error.set(
        err instanceof Error ? err.message : 'Unable to load chapter',
      );
    } finally {
      this.loading.set(false);
    }
  }

  isQuoteLine(line: BookLine): boolean {
    const t = (line.contentType ?? '').toLowerCase();
    return t === 'quote' || t === 'blockquote' || t === 'scripture';
  }

  toggleSelectLine(index: number): void {
    const sel = window.getSelection()?.toString().trim();
    if (sel) return;
    this.selectedIndex.set(this.selectedIndex() === index ? null : index);
  }

  lookupFromSelection(): void {
    const raw = window.getSelection()?.toString().trim() ?? '';
    const firstWord = raw.split(/\s+/)[0]?.replace(/[^a-zA-Z'-]/g, '');
    if (firstWord && firstWord.length >= 2) {
      this.lookupWord.set(firstWord);
    }
  }

  defineSelected(): void {
    const raw = window.getSelection()?.toString().trim() ?? '';
    const wordFromSelection = raw.split(/\s+/)[0]?.replace(/[^a-zA-Z'-]/g, '');
    if (wordFromSelection && wordFromSelection.length >= 2) {
      this.lookupWord.set(wordFromSelection);
      return;
    }
    const line = this.selectedLine();
    if (!line) return;
    const firstWord = line.text
      .split(/\s+/)
      .map((w) => w.replace(/[^a-zA-Z'-]/g, ''))
      .find((w) => w.length >= 4);
    if (firstWord) {
      this.lookupWord.set(firstWord);
    }
  }

  highlightColor(index: number): string | null {
    return this.highlightsService.colorFor(
      this.currentBookId(),
      this.chapterIndex(),
      index,
    );
  }

  noteFor(index: number): string {
    return this.highlightsService.noteFor(
      this.currentBookId(),
      this.chapterIndex(),
      index,
    );
  }

  setHighlight(index: number, line: BookLine, color: string | null): void {
    this.highlightsService.setHighlight(
      this.currentBookId(),
      this.chapterIndex(),
      index,
      line.text,
      color,
    );
  }

  openNoteEditor(): void {
    const idx = this.selectedIndex();
    if (idx === null) return;
    this.noteDraft.set(this.noteFor(idx));
    this.showNoteModal.set(true);
  }

  saveNote(): void {
    const idx = this.selectedIndex();
    const sel = this.selectedLine();
    if (idx === null || !sel) return;
    this.highlightsService.saveNote(
      this.currentBookId(),
      this.chapterIndex(),
      idx,
      sel.text,
      this.noteDraft(),
    );
    this.showNoteModal.set(false);
  }

  toggleChapterBookmark(): void {
    this.highlightsService.toggleBookmark(
      this.currentBookId(),
      this.chapterIndex(),
      this.currentChapterTitle(),
    );
  }

  copySelected(): void {
    const sel = this.selectedLine();
    if (!sel) return;
    const ref = `${this.toc()?.title || this.currentBookId()} (Ch. ${this.chapterIndex()})`;
    void navigator.clipboard?.writeText(`${sel.text}\n— ${ref}`);
  }

  jumpToHighlight(target: { chapter: number; line: number }): void {
    this.showHighlights.set(false);
    this.showSearch.set(false);
    void this.loadChapter(target.chapter, { line: target.line });
  }

  removeHighlight(h: BookHighlight): void {
    this.highlightsService.setHighlight(
      h.bookId,
      h.chapterIndex,
      h.line,
      h.text,
      null,
      '',
    );
  }

  removeBookmark(bm: BookBookmark): void {
    this.highlightsService.toggleBookmark(
      bm.bookId,
      bm.chapterIndex,
      bm.chapterTitle,
    );
  }

  shareLocation(lineNum?: number): void {
    const url = new URL(
      `/books/${encodeURIComponent(this.currentBookId())}`,
      window.location.origin,
    );
    url.searchParams.set('chapter', String(this.chapterIndex()));
    const page = this.lines().find((l) => l.page !== undefined)?.page;
    if (page) {
      url.searchParams.set('page', String(page));
    }
    if (lineNum !== undefined) {
      url.searchParams.set('line', String(lineNum));
    }
    const shareUrl = url.toString();
    const title = this.toc()?.title || 'Book Reader';
    if (navigator.share) {
      void navigator.share({ title, url: shareUrl }).catch(() => {
        void navigator.clipboard?.writeText(shareUrl);
      });
    } else {
      void navigator.clipboard?.writeText(shareUrl);
    }
  }

  selectChapter(ch: number): void {
    this.showToc.set(false);
    void this.loadChapter(ch);
  }
}
