import {
  ChangeDetectionStrategy,
  Component,
  HostListener,
  OnInit,
  computed,
  inject,
  signal,
} from '@angular/core';
import { ActivatedRoute, Router } from '@angular/router';
import { combineLatest } from 'rxjs';
import { ReaderAppearanceService } from '../../../core/services/reader-appearance.service';
import { BookAppearanceSheetComponent } from '../components/book-appearance-sheet.component';
import { BookHighlightsSheetComponent } from '../components/book-highlights-sheet.component';
import { BookLineActionBarComponent } from '../components/book-line-action-bar.component';
import { BookReaderNavComponent } from '../components/book-reader-nav.component';
import { BookTocSheetComponent } from '../components/book-toc-sheet.component';
import { BookLine, BookToc } from '../models/book.model';
import {
  BookHighlight,
  BookHighlightsService,
} from '../services/book-highlights.service';
import { BooksService } from '../services/books.service';

@Component({
  selector: 'app-book-reader',
  standalone: true,
  imports: [
    BookTocSheetComponent,
    BookAppearanceSheetComponent,
    BookHighlightsSheetComponent,
    BookLineActionBarComponent,
    BookReaderNavComponent,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div
      class="book-reader-page"
      [attr.data-paper]="appearance.paperTheme()"
    >
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
              title="Highlights"
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
              title="Reader Appearance"
              (click)="showAppearance.set(true)"
            >
              Aa
            </button>
          </div>
        </div>
      </header>

      <div class="reader-content max-width-box">
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
            [style.font-family]="appearance.activeFont().cssFamily"
            [style.font-size.px]="appearance.fontSize()"
            [style.line-height]="appearance.lineHeight()"
          >
            @for (line of lines(); track $index) {
              @let hl = highlightColor(line.line);
              @if (line.isHeading) {
                <h2
                  [id]="'book-line-' + line.line"
                  class="chapter-heading"
                  [class.sub-heading]="(line.headingLevel ?? 1) > 1"
                >
                  {{ line.text }}
                </h2>
              } @else {
                <p
                  [id]="'book-line-' + line.line"
                  class="chapter-para"
                  [class.is-quote]="isQuoteLine(line)"
                  [class.selected]="selectedLine()?.line === line.line"
                  [style.background-color]="hl ? hl + '55' : null"
                  (click)="toggleSelectLine(line)"
                >
                  {{ line.text }}
                </p>
              }
            }
          </article>
        }
      </div>

      @if (selectedLine(); as sel) {
        <app-book-line-action-bar
          [line]="sel"
          (copy)="copySelected()"
          (share)="shareLocation(sel.line)"
          (highlightChanged)="setHighlight(sel, $event)"
          (closed)="selectedLine.set(null)"
        />
      } @else if (!loading() && toc()) {
        <app-book-reader-nav
          [chapterIndex]="chapterIndex()"
          [totalChapters]="toc()!.chapters.length || 1"
          [chapterTitle]="currentChapterTitle()"
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
          (jumpTo)="jumpToHighlight($event)"
          (removed)="removeHighlight($event)"
          (closed)="showHighlights.set(false)"
        />
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
        gap: 12px;
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
        gap: 4px;
        flex-shrink: 0;
      }

      .aa-btn {
        font-family: Georgia, serif;
        font-weight: 700;
        font-size: 16px;
      }

      .reader-content {
        padding-top: 28px;
        padding-bottom: 120px;
        max-width: 720px;
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

      .status-msg {
        text-align: center;
        padding: 48px 0;
        color: var(--reader-muted, var(--on-surface-muted));
      }
    `,
  ],
})
export class BookReaderComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly booksService = inject(BooksService);
  private readonly highlightsService = inject(BookHighlightsService);
  readonly appearance = inject(ReaderAppearanceService);

  readonly toc = signal<BookToc | null>(null);
  readonly lines = signal<BookLine[]>([]);
  readonly chapterIndex = signal<number>(1);
  readonly loading = signal<boolean>(true);
  readonly error = signal<string | null>(null);
  readonly selectedLine = signal<BookLine | null>(null);

  readonly showToc = signal<boolean>(false);
  readonly showAppearance = signal<boolean>(false);
  readonly showHighlights = signal<boolean>(false);

  private bookId = '';
  private bookLang?: string;

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

  readonly bookHighlights = computed(() =>
    this.bookId ? this.highlightsService.forBook(this.bookId) : [],
  );

  @HostListener('window:keydown', ['$event'])
  onKeyDown(event: KeyboardEvent): void {
    if (event.key === 'Escape') {
      this.selectedLine.set(null);
      this.showToc.set(false);
      this.showAppearance.set(false);
      this.showHighlights.set(false);
      return;
    }
    if (this.showToc() || this.showAppearance() || this.showHighlights()) {
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

        const sameBook = id === this.bookId && this.toc() !== null;
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
    this.bookId = bookId;
    this.loading.set(true);
    this.error.set(null);
    this.selectedLine.set(null);
    const catalogItem = this.booksService
      .catalog()
      .find((b) => b.id === bookId);
    this.bookLang = catalogItem?.lang;

    try {
      const toc = await this.booksService.fetchToc(bookId, this.bookLang);
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
    this.loading.set(true);
    this.error.set(null);
    this.selectedLine.set(null);
    this.chapterIndex.set(ch);
    try {
      const lines = await this.booksService.fetchChapter(
        this.bookId,
        ch,
        this.bookLang,
        this.toc()?.chapters.length,
      );
      this.lines.set(lines);
      const toc = this.toc();
      if (toc) {
        const catalogItem = this.booksService
          .catalog()
          .find((b) => b.id === this.bookId);
        this.booksService.saveProgress({
          bookId: this.bookId,
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
      void this.router.navigate(['/books', this.bookId], {
        queryParams: {
          chapter: ch,
          ...(syncPage ? { page: syncPage } : {}),
        },
        replaceUrl: true,
      });

      const scrollLine =
        (target?.line
          ? lines.find((l) => l.line >= target.line!)
          : undefined) ??
        (target?.page
          ? lines.find((l) => (l.page ?? 0) >= target.page!)
          : undefined);

      if (scrollLine) {
        setTimeout(() => {
          document
            .getElementById(`book-line-${scrollLine.line}`)
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

  toggleSelectLine(line: BookLine): void {
    this.selectedLine.set(
      this.selectedLine()?.line === line.line ? null : line,
    );
  }

  highlightColor(lineNum: number): string | null {
    return this.highlightsService.colorFor(
      this.bookId,
      this.chapterIndex(),
      lineNum,
    );
  }

  setHighlight(line: BookLine, color: string | null): void {
    this.highlightsService.setHighlight(
      this.bookId,
      this.chapterIndex(),
      line.line,
      line.text,
      color,
    );
  }

  copySelected(): void {
    const sel = this.selectedLine();
    if (!sel) return;
    const ref = `${this.toc()?.title || this.bookId} (Ch. ${this.chapterIndex()})`;
    void navigator.clipboard?.writeText(`${sel.text}\n— ${ref}`);
  }

  jumpToHighlight(target: { chapter: number; line: number }): void {
    this.showHighlights.set(false);
    void this.loadChapter(target.chapter, { line: target.line });
  }

  removeHighlight(h: BookHighlight): void {
    this.highlightsService.setHighlight(
      h.bookId,
      h.chapterIndex,
      h.line,
      h.text,
      null,
    );
  }

  shareLocation(lineNum?: number): void {
    const url = new URL(
      `/books/${encodeURIComponent(this.bookId)}`,
      window.location.origin,
    );
    url.searchParams.set('chapter', String(this.chapterIndex()));
    const page = this.lines().find((l) => l.page !== undefined)?.page;
    if (page) {
      url.searchParams.set('page', String(page));
    }
    if (lineNum) {
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
