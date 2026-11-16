import {
  ChangeDetectionStrategy,
  Component,
  HostListener,
  OnInit,
  computed,
  effect,
  inject,
  signal,
} from '@angular/core';
import { ActivatedRoute, Router } from '@angular/router';
import { combineLatest } from 'rxjs';
import { ReaderAppearanceService } from '../../../core/services/reader-appearance.service';
import { BibleAppearanceSheetComponent } from '../components/bible-appearance-sheet.component';
import {
  BibleBookChapterSheetComponent,
  BiblePickerTab,
  BibleSelectionTarget,
} from '../components/bible-book-chapter-sheet.component';
import { BibleBookmarksSheetComponent } from '../components/bible-bookmarks-sheet.component';
import { BibleCrossRefsSheetComponent } from '../components/bible-cross-refs-sheet.component';
import { BibleNoteSheetComponent } from '../components/bible-note-sheet.component';
import { BibleReaderNavComponent } from '../components/bible-reader-nav.component';
import { BibleStudySheetComponent } from '../components/bible-study-sheet.component';
import { BibleVerseActionBarComponent } from '../components/bible-verse-action-bar.component';
import { BibleVersionSheetComponent } from '../components/bible-version-sheet.component';
import { BibleReaderStateService } from '../services/bible-reader-state.service';
import { BibleService } from '../services/bible.service';

@Component({
  selector: 'app-bible-reader',
  standalone: true,
  imports: [
    BibleVersionSheetComponent,
    BibleBookChapterSheetComponent,
    BibleVerseActionBarComponent,
    BibleReaderNavComponent,
    BibleAppearanceSheetComponent,
    BibleBookmarksSheetComponent,
    BibleCrossRefsSheetComponent,
    BibleStudySheetComponent,
    BibleNoteSheetComponent,
  ],
  providers: [BibleReaderStateService],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="bible-page" [attr.data-paper]="appearance.paperTheme()">
      <header class="bible-bar">
        <div class="bar-inner max-width-box">
          <div class="bar-left">
            <button
              type="button"
              class="version-pill"
              (click)="showVersionPicker.set(true)"
              aria-label="Bible Version"
            >
              <span>{{ state.activeVersionInfo().label }}</span>
              <span class="material-symbols-rounded pill-chev">expand_more</span>
            </button>

            <button
              type="button"
              class="book-btn"
              (click)="openBookPicker('books')"
            >
              <span>{{ bible.currentBook().name }} {{ bible.chapter() }}</span>
              <span class="material-symbols-rounded">expand_more</span>
            </button>
          </div>

          <div class="bar-right">
            <button
              type="button"
              class="icon-btn"
              title="Share chapter link"
              (click)="sharePassage()"
            >
              <span class="material-symbols-rounded">share</span>
            </button>
            <button
              type="button"
              class="icon-btn"
              title="Bookmarks"
              (click)="showBookmarks.set(true)"
            >
              <span class="material-symbols-rounded">bookmarks</span>
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

      <div class="reader-body max-width-box">
        @if (bible.loading()) {
          <p class="status-msg">
            Loading {{ bible.currentBook().name }} {{ bible.chapter() }}...
          </p>
        } @else if (bible.error()) {
          <div class="error-card">
            <p>{{ bible.error() }}</p>
            <button type="button" class="pill-chip active" (click)="bible.init()">
              Retry
            </button>
          </div>
        } @else {
          <header class="chapter-hero">
            <span class="hero-eyebrow">
              {{ state.activeVersionInfo().label }} ·
              {{ bible.bookNumber() <= 39 ? 'Old Testament' : 'New Testament' }}
            </span>
            <h1 class="hero-title font-display">
              {{ bible.currentBook().name }} {{ bible.chapter() }}
            </h1>
            <div class="hero-meta">
              <span>{{ bible.verses().length }} verses</span>
              <span>·</span>
              <span>{{ readingMinutes() }} min read</span>
            </div>
          </header>

          @if (bible.study()?.chapter_summary) {
            <div class="summary-card">
              <span class="summary-label">Chapter Summary</span>
              <p>{{ bible.study()!.chapter_summary }}</p>
            </div>
          }

          <article
            class="verses-flow"
            [class.paragraph-mode]="appearance.bibleLayout() === 'paragraph'"
            [style.font-family]="appearance.activeFont().cssFamily"
            [style.font-size.px]="appearance.fontSize()"
            [style.line-height]="appearance.lineHeight()"
          >
            @for (v of bible.verses(); track v.verse) {
              @let selected = state.selectedVerse()?.verse === v.verse;
              @let note = state.noteFor(v.verse);
              @if (appearance.bibleLayout() === 'paragraph') {
                <span
                  [id]="'verse-' + v.verse"
                  class="verse-inline"
                  [class.selected]="selected"
                  [style.background-color]="state.highlightFor(v.verse)"
                  (click)="state.toggleSelectVerse(v)"
                >
                  <sup class="verse-sup">{{ v.verse }}</sup>
                  <span>{{ v.text }}</span>
                  @if (bible.isBookmarked(v.verse)) {
                    <span class="material-symbols-rounded verse-mark-inline">bookmark</span>
                  }
                  @if (note) {
                    <span class="material-symbols-rounded verse-mark-inline">sticky_note_2</span>
                  }
                  {{ ' ' }}
                </span>
              } @else {
                <div
                  [id]="'verse-' + v.verse"
                  class="verse-row"
                  [class.selected]="selected"
                  [style.background-color]="state.highlightFor(v.verse)"
                  (click)="state.toggleSelectVerse(v)"
                >
                  <span class="verse-num">{{ v.verse }}</span>
                  <div class="verse-content">
                    <span class="verse-text">{{ v.text }}</span>
                    @if (note && selected) {
                      <p class="verse-note-preview">{{ note }}</p>
                    }
                  </div>
                  @if (bible.isBookmarked(v.verse)) {
                    <span class="material-symbols-rounded verse-mark">bookmark</span>
                  }
                  @if (note) {
                    <span class="material-symbols-rounded verse-mark">sticky_note_2</span>
                  }
                </div>
              }
            }
          </article>
        }
      </div>

      @if (state.selectedVerse(); as selected) {
        <app-bible-verse-action-bar
          [verse]="selected"
          [isBookmarked]="bible.isBookmarked(selected.verse)"
          [crossRefCount]="state.selectedCrossRefs().length"
          [studyTermCount]="state.selectedStudyTerms().length"
          (copy)="state.copySelected()"
          (share)="sharePassage(selected.verse)"
          (toggleBookmark)="bible.toggleBookmark(selected)"
          (openNote)="showNoteModal.set(true)"
          (openCrossRefs)="showCrossRefs.set(true)"
          (openStudy)="showStudy.set(true)"
          (highlightChanged)="bible.setHighlight(selected.verse, $event)"
          (closed)="state.clearSelection()"
        />
      } @else if (!bible.loading() && !bible.error()) {
        <app-bible-reader-nav
          [bookName]="bible.currentBook().name"
          [chapter]="bible.chapter()"
          [versionLabel]="state.activeVersionInfo().label"
          [verseCount]="bible.verses().length"
          (previous)="bible.prevChapter()"
          (next)="bible.nextChapter()"
          (openPicker)="openBookPicker('chapters')"
        />
      }

      @if (showVersionPicker()) {
        <app-bible-version-sheet
          [activeVersionId]="bible.version()"
          (versionSelected)="selectVersion($event)"
          (closed)="showVersionPicker.set(false)"
        />
      }

      @if (showBookPicker()) {
        <app-bible-book-chapter-sheet
          [books]="bible.books()"
          [currentBook]="bible.currentBook()"
          [currentChapter]="bible.chapter()"
          [initialTab]="bookPickerTab()"
          (selectionApplied)="applySelection($event)"
          (closed)="showBookPicker.set(false)"
        />
      }

      @if (showAppearance()) {
        <app-bible-appearance-sheet (closed)="showAppearance.set(false)" />
      }

      @if (showCrossRefs() && state.selectedVerse()) {
        <app-bible-cross-refs-sheet
          [referenceLabel]="selectedRefLabel()"
          [refs]="state.selectedCrossRefs()"
          (jumpTo)="jumpToCrossRef($event.abbrev, $event.chapter)"
          (closed)="showCrossRefs.set(false)"
        />
      }

      @if (showStudy() && state.selectedVerse(); as selected) {
        <app-bible-study-sheet
          [verseNumber]="selected.verse"
          [terms]="state.selectedStudyTerms()"
          (closed)="showStudy.set(false)"
        />
      }

      @if (showBookmarks()) {
        <app-bible-bookmarks-sheet
          [bookmarks]="bible.bookmarks()"
          (jumpTo)="jumpToBookmark($event.bookNumber, $event.chapter)"
          (closed)="showBookmarks.set(false)"
        />
      }

      @if (showNoteModal() && state.selectedVerse(); as selected) {
        <app-bible-note-sheet
          [referenceLabel]="selectedRefLabel()"
          [initialNote]="state.noteFor(selected.verse) ?? ''"
          (saved)="saveNote(selected.verse, $event)"
          (closed)="showNoteModal.set(false)"
        />
      }
    </div>
  `,
  styles: [
    `
      .bible-page {
        min-height: calc(100dvh - var(--shell-top-offset));
        background-color: var(--reader-bg, var(--bg));
        color: var(--reader-fg, var(--on-surface));
        transition: background-color 180ms ease, color 180ms ease;
      }

      .bible-page[data-paper='paper'] {
        --reader-bg: #faf8f5;
        --reader-fg: #1f2937;
        --reader-muted: #6b7280;
        --reader-border: rgba(31, 41, 55, 0.12);
      }

      .bible-page[data-paper='sepia'] {
        --reader-bg: #f4ecd8;
        --reader-fg: #433422;
        --reader-muted: #78644c;
        --reader-border: rgba(67, 52, 34, 0.14);
      }

      .bible-page[data-paper='night'] {
        --reader-bg: #121620;
        --reader-fg: #e2e8f0;
        --reader-muted: #94a3b8;
        --reader-border: rgba(226, 232, 240, 0.12);
      }

      .bible-bar {
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

      .bar-left,
      .bar-right {
        display: flex;
        align-items: center;
        gap: 6px;
        min-width: 0;
      }

      .version-pill {
        display: inline-flex;
        align-items: center;
        gap: 2px;
        height: 32px;
        padding: 0 10px 0 12px;
        border-radius: var(--radius-pill);
        background-color: var(--accent-soft);
        border: 1px solid var(--accent);
        color: var(--accent);
        font-size: 13px;
        font-weight: 700;
        flex-shrink: 0;
      }

      .pill-chev {
        font-size: 18px;
      }

      .book-btn {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        padding: 6px 10px;
        border-radius: var(--radius-sm);
        background-color: var(--surface-variant);
        border: 1px solid var(--reader-border, var(--surface-border));
        color: var(--on-surface);
        font-size: 15px;
        font-weight: 600;
        min-width: 0;
      }

      .book-btn span:first-child {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .aa-btn {
        font-family: Georgia, serif;
        font-weight: 700;
        font-size: 16px;
      }

      .reader-body {
        padding-top: 26px;
        padding-bottom: 120px;
        max-width: 720px;
      }

      .chapter-hero {
        margin-bottom: 20px;
        padding-bottom: 16px;
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
        font-size: clamp(24px, 3vw, 32px);
        line-height: 1.2;
        font-weight: 700;
      }

      .hero-meta {
        display: flex;
        align-items: center;
        gap: 6px;
        font-size: 13px;
        color: var(--reader-muted, var(--on-surface-muted));
      }

      .status-msg,
      .error-card {
        padding: 40px 0;
        text-align: center;
        color: var(--reader-muted, var(--on-surface-muted));
      }

      .summary-card {
        padding: 12px 14px;
        margin-bottom: 20px;
        border-radius: var(--radius-md);
        background-color: var(--accent-soft);
        border-left: 3px solid var(--accent);
        font-size: 14px;
      }

      .summary-label {
        display: block;
        font-size: 11px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        color: var(--accent);
        margin-bottom: 4px;
      }

      .summary-card p {
        margin: 0;
      }

      .verses-flow {
        display: flex;
        flex-direction: column;
        gap: 6px;
      }

      .verses-flow.paragraph-mode {
        display: block;
      }

      .verse-inline {
        cursor: pointer;
        border-radius: 4px;
        padding: 2px 3px;
        transition: background-color 120ms ease;
      }

      .verse-inline.selected {
        outline: 2px solid var(--accent);
      }

      .verse-sup {
        font-size: 0.7em;
        font-weight: 700;
        color: var(--accent);
        margin-right: 3px;
        font-variant-numeric: tabular-nums;
      }

      .verse-mark-inline {
        font-size: 14px;
        color: var(--accent);
        vertical-align: middle;
        margin-left: 2px;
      }

      .verse-row {
        display: flex;
        align-items: baseline;
        gap: 10px;
        padding: 6px 10px;
        border-radius: var(--radius-sm);
        cursor: pointer;
        transition: background-color 120ms ease;
      }

      .verse-row:hover {
        background-color: color-mix(in srgb, var(--accent) 7%, transparent);
      }

      .verse-row.selected {
        outline: 2px solid var(--accent);
      }

      .verse-num {
        font-size: 0.74em;
        font-weight: 700;
        color: var(--accent);
        min-width: 22px;
        font-variant-numeric: tabular-nums;
        user-select: none;
      }

      .verse-content {
        flex: 1;
        min-width: 0;
      }

      .verse-note-preview {
        margin: 6px 0 2px;
        padding: 6px 10px;
        border-radius: var(--radius-sm);
        background-color: var(--accent-soft);
        border-left: 2px solid var(--accent);
        font-size: 0.84em;
        color: var(--reader-muted, var(--on-surface-muted));
      }

      .verse-mark {
        font-size: 16px;
        color: var(--accent);
        flex-shrink: 0;
      }
    `,
  ],
})
export class BibleReaderComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  readonly bible = inject(BibleService);
  readonly appearance = inject(ReaderAppearanceService);
  readonly state = inject(BibleReaderStateService);

  readonly showVersionPicker = signal<boolean>(false);
  readonly showBookPicker = signal<boolean>(false);
  readonly bookPickerTab = signal<BiblePickerTab>('books');
  readonly showAppearance = signal<boolean>(false);
  readonly showCrossRefs = signal<boolean>(false);
  readonly showStudy = signal<boolean>(false);
  readonly showBookmarks = signal<boolean>(false);
  readonly showNoteModal = signal<boolean>(false);
  private readonly routeReady = signal<boolean>(false);

  readonly selectedRefLabel = computed(() => {
    const v = this.state.selectedVerse();
    return v
      ? `${this.bible.currentBook().name} ${this.bible.chapter()}:${v.verse}`
      : '';
  });

  readonly readingMinutes = computed(() => {
    const words = this.bible
      .verses()
      .reduce((acc, v) => acc + (v.text ? v.text.split(/\s+/).length : 0), 0);
    return Math.max(1, Math.round(words / 200));
  });

  @HostListener('window:keydown', ['$event'])
  onKeyDown(event: KeyboardEvent): void {
    if (event.key === 'Escape') {
      this.state.clearSelection();
      this.showVersionPicker.set(false);
      this.showBookPicker.set(false);
      this.showAppearance.set(false);
      this.showCrossRefs.set(false);
      this.showStudy.set(false);
      this.showBookmarks.set(false);
      this.showNoteModal.set(false);
      return;
    }
    if (
      this.showVersionPicker() ||
      this.showBookPicker() ||
      this.showAppearance() ||
      this.showCrossRefs() ||
      this.showStudy() ||
      this.showBookmarks() ||
      this.showNoteModal()
    ) {
      return;
    }
    if (event.key === 'ArrowLeft') {
      void this.bible.prevChapter();
    } else if (event.key === 'ArrowRight') {
      void this.bible.nextChapter();
    }
  }

  constructor() {
    effect(() => {
      if (!this.routeReady()) return;
      const version = this.bible.version();
      const book = this.bible.currentBookAbbrev();
      const chapter = this.bible.chapter();
      const verse = this.state.selectedVerse()?.verse;
      void this.router.navigate(['/bible'], {
        queryParams: {
          version,
          book,
          chapter,
          ...(verse ? { verse } : {}),
        },
        replaceUrl: true,
      });
    });
  }

  ngOnInit(): void {
    combineLatest([this.route.paramMap, this.route.queryParamMap]).subscribe(
      ([params, query]) => {
        const version =
          params.get('version') ?? query.get('version') ?? undefined;
        const book = params.get('book') ?? query.get('book') ?? undefined;
        const chapterRaw = params.get('chapter') ?? query.get('chapter');
        const verseRaw = params.get('verse') ?? query.get('verse');
        const chapter = chapterRaw ? Number(chapterRaw) : undefined;
        const verse = verseRaw ? Number(verseRaw) : undefined;
        const validChapter =
          chapter && Number.isFinite(chapter) ? chapter : undefined;
        const validVerse =
          verse && Number.isFinite(verse) ? verse : undefined;

        const alreadyLoaded =
          this.routeReady() &&
          (!version || version.toLowerCase() === this.bible.version()) &&
          (!book ||
            this.bible.resolveBookNumber(book) === this.bible.bookNumber()) &&
          (!validChapter || validChapter === this.bible.chapter()) &&
          (validVerse ?? undefined) === this.state.selectedVerse()?.verse;

        if (alreadyLoaded) return;

        void this.initFromRoute(version, book, validChapter, validVerse);
      },
    );
  }

  private async initFromRoute(
    version?: string,
    book?: string,
    chapter?: number,
    verse?: number,
  ): Promise<void> {
    this.routeReady.set(false);
    await this.bible.init({ version, book, chapter });
    if (verse && verse > 0) {
      this.focusVerse(verse);
    } else {
      this.state.clearSelection();
    }
    this.routeReady.set(true);
  }

  private focusVerse(verseNum: number): void {
    const match = this.bible.verses().find((v) => v.verse === verseNum);
    if (match) this.state.toggleSelectVerse(match);
    setTimeout(() => {
      document
        .getElementById(`verse-${verseNum}`)
        ?.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }, 60);
  }

  sharePassage(verseNum?: number): void {
    const url = new URL('/bible', window.location.origin);
    url.searchParams.set('version', this.bible.version());
    url.searchParams.set('book', this.bible.currentBookAbbrev());
    url.searchParams.set('chapter', String(this.bible.chapter()));
    if (verseNum) {
      url.searchParams.set('verse', String(verseNum));
    }
    const shareUrl = url.toString();
    const title = verseNum
      ? `${this.bible.currentBook().name} ${this.bible.chapter()}:${verseNum}`
      : `${this.bible.currentBook().name} ${this.bible.chapter()}`;
    if (navigator.share) {
      void navigator.share({ title, url: shareUrl }).catch(() => {
        void navigator.clipboard?.writeText(shareUrl);
      });
    } else {
      void navigator.clipboard?.writeText(shareUrl);
    }
  }

  selectVersion(versionId: string): void {
    this.showVersionPicker.set(false);
    this.state.clearSelection();
    void this.bible.loadVersion(versionId);
  }

  openBookPicker(tab: BiblePickerTab): void {
    this.bookPickerTab.set(tab);
    this.showBookPicker.set(true);
  }

  async applySelection(target: BibleSelectionTarget): Promise<void> {
    this.showBookPicker.set(false);
    this.state.clearSelection();
    await this.bible.loadChapter(target.bookNumber, target.chapter);
    if (target.verse) {
      const match = this.bible.verses().find((v) => v.verse === target.verse);
      if (match) this.state.toggleSelectVerse(match);
      setTimeout(() => {
        document
          .getElementById(`verse-${target.verse}`)
          ?.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }, 60);
    }
  }

  saveNote(verseNum: number, text: string): void {
    this.bible.saveNote(verseNum, text);
    this.showNoteModal.set(false);
  }

  jumpToCrossRef(abbrev: string, ch: number): void {
    this.showCrossRefs.set(false);
    this.state.clearSelection();
    this.bible.jumpToAbbrev(abbrev, ch);
  }

  jumpToBookmark(bookNum: number, ch: number): void {
    this.showBookmarks.set(false);
    this.state.clearSelection();
    void this.bible.loadChapter(bookNum, ch);
  }
}
