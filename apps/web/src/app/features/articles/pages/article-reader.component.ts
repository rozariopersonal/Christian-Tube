import {
  AfterViewInit,
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  ElementRef,
  HostListener,
  OnInit,
  TemplateRef,
  ViewChild,
  computed,
  effect,
  inject,
  signal,
} from '@angular/core';
import { ActivatedRoute } from '@angular/router';
import { combineLatest } from 'rxjs';
import { ScreenClassService } from '../../../core/layout/screen-class.service';
import { HeaderSlotService } from '../../../core/services/header-slot.service';
import { ReaderAppearanceService } from '../../../core/services/reader-appearance.service';
import { ReaderFullscreenService } from '../../../core/services/reader-fullscreen.service';
import { ReaderColumnsToggleComponent } from '../../../shared/ui/reader-columns-toggle.component';
import { ReaderTypographyToggleComponent } from '../../../shared/ui/reader-typography-toggle.component';
import { ReaderSpreadFooterComponent } from '../../../shared/ui/reader-spread-footer.component';
import { computeSpreadMetrics, scrollToSpreadPage } from '../../../shared/ui/spread-pager';
import {
  TextSelectionAnchor,
  applyHighlightRangesToTokens,
  extractLineTextSelection,
  selectHighlightElement,
} from '../../../shared/ui/text-highlight.util';
import { contrastColorFor } from '../../../shared/ui/highlight-palette';
import { TextSelectionPopoverComponent } from '../../../shared/ui/text-selection-popover.component';
import { ReaderAutoFullscreenToggleComponent } from '../../../shared/ui/reader-auto-fullscreen-toggle.component';
import { BookAppearanceSheetComponent } from '../../books/components/book-appearance-sheet.component';
import { DictionarySheetComponent } from '../../books/components/dictionary-sheet.component';
import { ScriptureVerseSheetComponent } from '../../books/components/scripture-verse-sheet.component';
import {
  BookHighlightsService,
  TextHighlightRange,
} from '../../books/services/book-highlights.service';
import {
  ParsedScriptureRef,
  ScriptureRefParserService,
  ScriptureSpanToken,
} from '../../books/services/scripture-ref-parser.service';
import { ArticleData, ArticleLine } from '../models/article.model';
import { ArticlesService } from '../services/articles.service';

@Component({
  selector: 'app-article-reader',
  standalone: true,
  imports: [
    ReaderColumnsToggleComponent,
    ReaderTypographyToggleComponent,
    ReaderSpreadFooterComponent,
    TextSelectionPopoverComponent,
    ReaderAutoFullscreenToggleComponent,
    BookAppearanceSheetComponent,
    DictionarySheetComponent,
    ScriptureVerseSheetComponent,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <ng-template #topbarCenter>
      <div class="tb-article-pill">
        <span class="material-symbols-rounded tb-ic">article</span>
        <span class="tb-title-text">{{ article()?.title || 'Article' }}</span>
      </div>
    </ng-template>

    <ng-template #topbarRight>
      <app-reader-columns-toggle />
      <app-reader-typography-toggle />
      <app-reader-auto-fullscreen-toggle />
      <div class="tb-actions-pill">
        <button
          type="button"
          class="tb-action-btn"
          title="Share article link"
          (click)="shareArticle()"
        >
          <span class="material-symbols-rounded">share</span>
        </button>
        <button
          type="button"
          class="tb-action-btn"
          title="Display & Themes"
          aria-label="Display & Themes"
          (click)="showAppearance.set(true)"
        >
          <span class="material-symbols-rounded">palette</span>
        </button>
      </div>
    </ng-template>

    <div
      class="article-page"
      [attr.data-paper]="appearance.paperTheme()"
      [class.spread-mode]="isPaginated()"
      [class.immersive]="immersive()"
      (pointerdown)="readerFullscreen.noteActivity('article')"
      (wheel)="readerFullscreen.noteActivity('article')"
      (touchstart)="readerFullscreen.noteActivity('article')"
    >
      @if (!immersive() && screen.isCompact()) {
        <header class="reader-bar">
          <div class="bar-inner">
            <div class="bar-title">
              <span class="material-symbols-rounded">article</span>
              <span class="title-text">{{ article()?.title || 'Article' }}</span>
            </div>

            <div class="bar-actions">
              <button
                type="button"
                class="icon-btn"
                title="Share article link"
                (click)="shareArticle()"
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
              <app-reader-auto-fullscreen-toggle />
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
        class="reader-content"
        [attr.data-margin]="appearance.bookMargin()"
      >
        @if (loading()) {
          <p class="status-msg">Loading article...</p>
        } @else if (error()) {
          <p class="status-msg">{{ error() }}</p>
        } @else if (article(); as art) {
          <div class="spread-viewport" #spreadViewport>
            <div class="spread-track" [attr.data-cols]="isPaginated() ? effectiveCols() : 1">
            <header class="article-hero">
              <span class="hero-eyebrow">
                Word for the Week · {{ lang().toUpperCase() }}
              </span>
              <h1 class="hero-title font-display">{{ art.title }}</h1>
              <div class="hero-meta">
                <span>{{ art.author }}</span>
                @if (art.date) {
                  <span>·</span>
                  <span>{{ art.date }}</span>
                }
                <span>·</span>
                <span>{{ readingMinutes() }} min read</span>
              </div>
            </header>

            <article
              class="article-body"
              [style.font-family]="appearance.activeFont().cssFamily"
              [style.font-size.px]="appearance.fontSize()"
              [style.line-height]="appearance.lineHeight()"
              [style.letter-spacing.em]="appearance.letterSpacing()"
              [style.text-align]="appearance.bookAlign()"
              (dblclick)="lookupFromSelection()"
            >
            @for (item of parsedLines(); track $index) {
              @if (item.line.isHeading) {
                <h2 class="article-heading">{{ item.line.text }}</h2>
              } @else {
                <p
                  class="article-para"
                  [attr.data-hl-scope]="articleScopeKey()"
                  [attr.data-hl-line]="$index"
                  (mouseup)="onTextSelectionChange()"
                  (touchend)="onTextSelectionChange()"
                >
                  @for (tok of item.tokens; track $index) {
                    @if (tok.ref) {
                      <button
                        type="button"
                        class="scripture-link"
                        [class.inline-hl]="!!tok.highlightColor"
                        [style.background-color]="tok.highlightColor ?? null"
                        [style.color]="tok.highlightColor ? contrastColor(tok.highlightColor) : null"
                        (click)="activeScriptureRef.set(tok.ref!)"
                      >
                        {{ tok.text }}
                      </button>
                    } @else if (tok.highlightColor) {
                      <mark
                        class="inline-hl"
                        [style.background-color]="tok.highlightColor"
                        [style.color]="contrastColor(tok.highlightColor)"
                        (click)="onHighlightMarkClick($event, tok.highlightRange)"
                      >{{ tok.text }}</mark>
                    } @else {
                      <span>{{ tok.text }}</span>
                    }
                  }
                </p>
              }
            }
          </article>
          </div>
          </div>
        }
      </div>

      @if (isPaginated() && article() && !loading() && !error()) {
        <app-reader-spread-footer
          [label]="article()!.title"
          [page]="spreadPage()"
          [totalPages]="spreadTotalPages()"
          (prevPage)="goToSpreadPage(spreadPage() - 1)"
          (nextPage)="goToSpreadPage(spreadPage() + 1)"
        />
      }

      @if (selectionAnchor(); as selAnchor) {
        <app-text-selection-popover
          [anchor]="selAnchor"
          [activeColor]="activeSelectionColor()"
          (highlight)="highlightSelection($event)"
          (clear)="clearSelectionHighlight()"
          (copy)="copySelection()"
          (share)="shareArticle(); clearSelectionPopover()"
          (closed)="clearSelectionPopover()"
        />
      }

      @if (showAppearance()) {
        <app-book-appearance-sheet (closed)="showAppearance.set(false)" />
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
    </div>
  `,
  styles: [
    `
      .article-page {
        min-height: calc(100dvh - var(--shell-top-offset));
        background-color: var(--reader-bg, var(--bg));
        color: var(--reader-fg, var(--on-surface));
        transition: background-color 180ms ease, color 180ms ease;
      }

      .article-page[data-paper='paper'] {
        --reader-bg: #faf8f5;
        --reader-fg: #1f2937;
        --reader-muted: #6b7280;
        --reader-border: rgba(31, 41, 55, 0.12);
      }

      .article-page[data-paper='sepia'] {
        --reader-bg: #f4ecd8;
        --reader-fg: #433422;
        --reader-muted: #78644c;
        --reader-border: rgba(67, 52, 34, 0.14);
      }

      .article-page[data-paper='night'] {
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
        width: 100%;
        padding-inline: clamp(16px, 3vw, 32px);
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
      }

      .tb-article-pill {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        height: 34px;
        padding: 0 14px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        min-width: 0;
        max-width: 100%;
        font-weight: 700;
        font-size: 13px;
        color: var(--on-surface);
      }

      .tb-ic {
        font-size: 17px;
        color: var(--on-surface-muted);
        flex-shrink: 0;
      }

      .tb-title-text {
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        min-width: 0;
      }

      .tb-actions-pill {
        display: inline-flex;
        align-items: center;
        gap: 2px;
        height: 32px;
        padding: 0 4px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
      }

      .tb-action-btn {
        width: 28px;
        height: 26px;
        border-radius: var(--radius-pill);
        display: grid;
        place-items: center;
        color: var(--on-surface);
      }

      .tb-action-btn:hover:not(:disabled) {
        background-color: color-mix(in srgb, var(--on-surface) 8%, transparent);
      }

      .tb-action-btn:disabled {
        opacity: 0.35;
        cursor: default;
      }

      .tb-action-btn .material-symbols-rounded {
        font-size: 18px;
      }

      .bar-title {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        min-width: 0;
        font-weight: 700;
        font-size: 15px;
      }

      .title-text {
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

      .reader-content {
        width: 100%;
        padding: 28px clamp(16px, 3vw, 40px) 64px;
      }

      .reader-content[data-margin='narrow'] {
        padding-inline: clamp(16px, 5vw, 72px);
      }

      .reader-content[data-margin='wide'] {
        padding-inline: clamp(12px, 1.5vw, 24px);
      }

      .article-page.spread-mode {
        height: calc(100dvh - var(--shell-top-offset));
        min-height: 0;
        display: flex;
        flex-direction: column;
        overflow: hidden;
      }

      .article-page.spread-mode.immersive {
        height: 100dvh;
      }

      .article-page.spread-mode .reader-bar {
        position: static;
        top: auto;
        flex-shrink: 0;
      }

      .article-page.spread-mode .reader-content {
        flex: 1;
        min-height: 0;
        display: flex;
        flex-direction: column;
        padding-top: 20px;
        padding-bottom: 12px;
        overflow: hidden;
      }

      .article-page.spread-mode .spread-viewport {
        flex: 1;
        min-height: 0;
        overflow: hidden;
      }

      .spread-mode .spread-track[data-cols='1'],
      .spread-track[data-cols='2'],
      .spread-track[data-cols='3'] {
        height: 100%;
        column-fill: auto;
        column-gap: 44px;
        column-rule: 1px solid var(--reader-border, var(--surface-border));
      }

      .spread-mode .spread-track[data-cols='1'] {
        column-count: 1;
      }

      .spread-track[data-cols='2'] {
        column-count: 2;
      }

      .spread-track[data-cols='3'] {
        column-count: 3;
      }

      .spread-mode .spread-track[data-cols='1'] .article-heading,
      .spread-track[data-cols='2'] .article-heading,
      .spread-track[data-cols='3'] .article-heading {
        break-inside: avoid;
        break-after: avoid;
        margin-bottom: 12px;
      }

      .spread-mode .spread-track[data-cols='1'] .article-para,
      .spread-track[data-cols='2'] .article-para,
      .spread-track[data-cols='3'] .article-para {
        orphans: 2;
        widows: 2;
        margin-bottom: 12px;
      }

      .spread-mode .spread-track[data-cols='1'] .article-hero,
      .spread-track[data-cols='2'] .article-hero,
      .spread-track[data-cols='3'] .article-hero {
        break-inside: avoid;
      }

      .article-hero {
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

      .article-body {
        display: flex;
        flex-direction: column;
        gap: 12px;
      }

      .article-heading {
        margin: 16px 0 4px;
        font-size: 1.15em;
        font-weight: 700;
      }

      .article-para {
        margin: 0;
      }

      .inline-hl {
        color: #111827;
        border-radius: 3px;
        padding: 1px 0;
        cursor: pointer;
      }

      .scripture-link {
        color: var(--accent);
        text-decoration: underline;
        text-decoration-style: dotted;
        text-underline-offset: 3px;
        font-weight: 600;
      }

      .status-msg {
        text-align: center;
        padding: 48px 0;
        color: var(--reader-muted, var(--on-surface-muted));
      }
    `,
  ],
})
export class ArticleReaderComponent implements OnInit, AfterViewInit {
  private readonly route = inject(ActivatedRoute);
  private readonly articlesService = inject(ArticlesService);
  private readonly scriptureParser = inject(ScriptureRefParserService);
  private readonly highlightsService = inject(BookHighlightsService);
  readonly appearance = inject(ReaderAppearanceService);
  readonly screen = inject(ScreenClassService);
  readonly readerFullscreen = inject(ReaderFullscreenService);
  private readonly headerSlot = inject(HeaderSlotService);
  private readonly destroyRef = inject(DestroyRef);

  @ViewChild('topbarCenter') topbarCenterRef?: TemplateRef<unknown>;
  @ViewChild('topbarRight') topbarRightRef?: TemplateRef<unknown>;
  @ViewChild('spreadViewport') spreadViewportRef?: ElementRef<HTMLDivElement>;
  private readonly viewInitialized = signal<boolean>(false);

  readonly spreadPage = signal<number>(1);
  readonly spreadTotalPages = signal<number>(1);

  readonly effectiveCols = computed(() =>
    this.appearance.effectiveColumns(this.screen.screenClass()),
  );

  readonly isPaginated = computed(
    () => this.effectiveCols() >= 2 || this.appearance.singleColPaginated(),
  );

  constructor() {
    this.destroyRef.onDestroy(this.readerFullscreen.registerReader('article', () => this.immersive.set(true)));
    effect(() => this.readerFullscreen.setFullscreen('article', this.immersive()));
    this.destroyRef.onDestroy(() => this.headerSlot.clear());
    effect(() => {
      if (!this.viewInitialized()) return;
      if (this.screen.isMediumOrExpanded() && !this.immersive()) {
        this.headerSlot.setTemplates(
          this.topbarCenterRef ?? null,
          this.topbarRightRef ?? null,
        );
      } else {
        this.headerSlot.clear();
      }
    });

    effect(() => {
      const paginated = this.isPaginated();
      this.effectiveCols();
      this.appearance.fontSize();
      this.appearance.lineHeight();
      this.appearance.letterSpacing();
      this.appearance.fontId();
      this.appearance.bookMargin();
      this.article();
      if (paginated) {
        window.scrollTo({ top: 0, behavior: 'auto' });
        setTimeout(() => this.refreshSpreadMetrics(), 60);
      }
    });
  }

  ngAfterViewInit(): void {
    this.viewInitialized.set(true);
    if (typeof ResizeObserver !== 'undefined') {
      const ro = new ResizeObserver(() => {
        if (this.isPaginated()) {
          this.refreshSpreadMetrics();
        }
      });
      if (this.spreadViewportRef?.nativeElement) {
        ro.observe(this.spreadViewportRef.nativeElement);
      }
      this.destroyRef.onDestroy(() => ro.disconnect());
    }
  }

  goToSpreadPage(next: number): void {
    const vp = this.spreadViewportRef?.nativeElement;
    if (!vp) return;
    const total = this.spreadTotalPages();
    const clamped = Math.min(total, Math.max(1, next));
    this.spreadPage.set(clamped);
    scrollToSpreadPage(vp, clamped, 44, false);
  }

  private refreshSpreadMetrics(): void {
    const vp = this.spreadViewportRef?.nativeElement;
    if (!vp) return;
    const { totalPages } = computeSpreadMetrics(vp, 44);
    this.spreadTotalPages.set(totalPages);
    if (this.spreadPage() > totalPages) {
      this.spreadPage.set(totalPages);
      scrollToSpreadPage(vp, totalPages, 44, false);
    }
  }

  readonly article = signal<ArticleData | null>(null);
  readonly lang = signal<string>('en');
  readonly loading = signal<boolean>(true);
  readonly error = signal<string | null>(null);
  readonly showAppearance = signal<boolean>(false);
  readonly immersive = signal<boolean>(false);
  readonly activeScriptureRef = signal<ParsedScriptureRef | null>(null);
  readonly lookupWord = signal<string | null>(null);
  readonly selectionAnchor = signal<TextSelectionAnchor | null>(null);

  readonly articleScopeKey = computed(() => {
    const art = this.article();
    return art ? `article:${art.id}:${this.lang()}` : '';
  });

  readonly parsedLines = computed(() => {
    const art = this.article();
    const scope = this.articleScopeKey();
    const rangeMap = this.highlightsService.textRanges();
    const lineRanges = scope ? (rangeMap[scope] ?? []) : [];
    const titleNorm = (art?.title ?? '').trim().toLowerCase();
    return (art?.lines ?? [])
      .filter(
        (line, index) =>
          !(
            index === 0 &&
            line.isHeading &&
            titleNorm &&
            line.text.trim().toLowerCase() === titleNorm
          ),
      )
      .map((line, idx) => {
        const baseTokens = line.isHeading
          ? []
          : this.scriptureParser.parse(line.text);
        const rangesForThis = lineRanges.filter((r) => r.line === idx);
        return {
          line,
          tokens: applyHighlightRangesToTokens(baseTokens, rangesForThis),
        };
      });
  });

  onTextSelectionChange(): void {
    setTimeout(() => {
      this.selectionAnchor.set(extractLineTextSelection());
    }, 10);
  }

  readonly activeSelectionColor = computed<string | null>(() => {
    const selAnchor = this.selectionAnchor();
    if (!selAnchor) return null;
    const ranges = this.highlightsService.rangesForLine(
      selAnchor.scopeKey,
      selAnchor.line,
    );
    const match = ranges.find(
      (r) => r.end > selAnchor.start && r.start < selAnchor.end,
    );
    return match?.color ?? null;
  });

  onHighlightMarkClick(
    event: MouseEvent,
    range: TextHighlightRange | undefined,
  ): void {
    if (!range) return;
    const sel = window.getSelection();
    if (sel && !sel.isCollapsed && sel.toString().trim().length > 0) {
      return;
    }
    event.stopPropagation();
    this.selectionAnchor.set(
      selectHighlightElement(event.currentTarget as HTMLElement, range),
    );
  }

  highlightSelection(color: string): void {
    const anchor = this.selectionAnchor();
    if (!anchor) return;
    this.highlightsService.addRange(
      anchor.scopeKey,
      anchor.line,
      anchor.start,
      anchor.end,
      anchor.text,
      color,
    );
    window.getSelection()?.removeAllRanges();
    this.selectionAnchor.set(null);
  }

  clearSelectionHighlight(): void {
    const anchor = this.selectionAnchor();
    if (!anchor) return;
    this.highlightsService.clearRange(
      anchor.scopeKey,
      anchor.line,
      anchor.start,
      anchor.end,
    );
    window.getSelection()?.removeAllRanges();
    this.selectionAnchor.set(null);
  }

  defineSelection(): void {
    const anchor = this.selectionAnchor();
    const raw = anchor?.text ?? window.getSelection()?.toString().trim() ?? '';
    const firstWord = raw.split(/\s+/)[0]?.replace(/[^a-zA-Z'-]/g, '');
    if (firstWord && firstWord.length >= 2) {
      this.lookupWord.set(firstWord);
    }
    this.selectionAnchor.set(null);
  }

  copySelection(): void {
    const anchor = this.selectionAnchor();
    if (!anchor) return;
    void navigator.clipboard?.writeText(anchor.text);
    this.clearSelectionPopover();
  }

  clearSelectionPopover(): void {
    window.getSelection()?.removeAllRanges();
    this.selectionAnchor.set(null);
  }

  readonly readingMinutes = computed(() => {
    const words = (this.article()?.lines ?? []).reduce(
      (acc, l) => acc + (l.text ? l.text.split(/\s+/).length : 0),
      0,
    );
    return Math.max(1, Math.round(words / 220));
  });

  @HostListener('window:keydown', ['$event'])
  onKeyDown(event: KeyboardEvent): void {
    this.readerFullscreen.noteActivity('article');
    const target = event.target as HTMLElement | null;
    if (
      target &&
      (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA')
    ) {
      return;
    }
    if (event.key === 'Escape') {
      this.showAppearance.set(false);
      this.activeScriptureRef.set(null);
      this.lookupWord.set(null);
      this.immersive.set(false);
    } else if (event.key === 'f' || event.key === 'F') {
      this.immersive.set(!this.immersive());
    } else if (
      this.isPaginated() &&
      !this.showAppearance() &&
      !this.activeScriptureRef() &&
      !this.lookupWord()
    ) {
      if (event.key === 'ArrowLeft') {
        event.preventDefault();
        this.goToSpreadPage(this.spreadPage() - 1);
      } else if (event.key === 'ArrowRight') {
        event.preventDefault();
        this.goToSpreadPage(this.spreadPage() + 1);
      }
    }
  }

  ngOnInit(): void {
    combineLatest([this.route.paramMap, this.route.queryParamMap]).subscribe(
      ([params, query]) => {
        const id = params.get('id');
        if (!id) return;
        const lang = query.get('lang') ?? 'en';
        void this.load(id, lang);
      },
    );
  }

  private async load(id: string, lang: string): Promise<void> {
    this.lang.set(lang);
    this.loading.set(true);
    this.error.set(null);
    try {
      const data = await this.articlesService.fetchArticle(id, lang);
      this.article.set(data);
    } catch (err) {
      this.error.set(
        err instanceof Error ? err.message : 'Unable to load article',
      );
    } finally {
      this.loading.set(false);
    }
  }

  lookupFromSelection(): void {
    const raw = window.getSelection()?.toString().trim() ?? '';
    const firstWord = raw.split(/\s+/)[0]?.replace(/[^a-zA-Z'-]/g, '');
    if (firstWord && firstWord.length >= 2) {
      this.lookupWord.set(firstWord);
    }
  }

  contrastColor(hex: string): string {
    return contrastColorFor(hex);
  }

  shareArticle(): void {
    const art = this.article();
    if (!art) return;
    const url = new URL(
      `/article/${encodeURIComponent(art.id)}`,
      window.location.origin,
    );
    if (this.lang() && this.lang() !== 'en') {
      url.searchParams.set('lang', this.lang());
    }
    const shareUrl = url.toString();
    if (navigator.share) {
      void navigator.share({ title: art.title, url: shareUrl }).catch(() => {
        void navigator.clipboard?.writeText(shareUrl);
      });
    } else {
      void navigator.clipboard?.writeText(shareUrl);
    }
  }
}
