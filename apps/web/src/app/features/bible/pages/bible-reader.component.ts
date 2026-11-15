import {
  ChangeDetectionStrategy,
  Component,
  OnInit,
  computed,
  inject,
  signal,
} from '@angular/core';
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
    BibleAppearanceSheetComponent,
    BibleBookmarksSheetComponent,
    BibleCrossRefsSheetComponent,
    BibleStudySheetComponent,
    BibleNoteSheetComponent,
  ],
  providers: [BibleReaderStateService],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="bible-page">
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
          @if (bible.study()?.chapter_summary) {
            <div class="summary-card">
              {{ bible.study()!.chapter_summary }}
            </div>
          }

          <article
            class="verses-flow"
            [style.font-family]="appearance.activeFont().cssFamily"
            [style.font-size.px]="appearance.fontSize()"
            [style.line-height]="appearance.lineHeight()"
          >
            @for (v of bible.verses(); track v.verse) {
              <div
                [id]="'verse-' + v.verse"
                class="verse-row"
                [class.selected]="state.selectedVerse()?.verse === v.verse"
                [style.background-color]="state.highlightFor(v.verse)"
                (click)="state.toggleSelectVerse(v)"
              >
                <span class="verse-num">{{ v.verse }}</span>
                <span class="verse-text">{{ v.text }}</span>
                @if (bible.isBookmarked(v.verse)) {
                  <span class="material-symbols-rounded verse-mark">bookmark</span>
                }
                @if (state.noteFor(v.verse)) {
                  <span class="material-symbols-rounded verse-mark">sticky_note_2</span>
                }
              </div>
            }
          </article>

          <nav class="chapter-nav" aria-label="Chapter navigation">
            <button type="button" class="pill-chip" (click)="bible.prevChapter()">
              <span class="material-symbols-rounded">chevron_left</span>
              Previous
            </button>
            <button
              type="button"
              class="chapter-indicator-btn"
              (click)="openBookPicker('chapters')"
            >
              {{ bible.currentBook().name }} {{ bible.chapter() }}
              <span class="material-symbols-rounded">expand_more</span>
            </button>
            <button type="button" class="pill-chip" (click)="bible.nextChapter()">
              Next
              <span class="material-symbols-rounded">chevron_right</span>
            </button>
          </nav>
        }
      </div>

      @if (state.selectedVerse(); as selected) {
        <app-bible-verse-action-bar
          [verse]="selected"
          [isBookmarked]="bible.isBookmarked(selected.verse)"
          [crossRefCount]="state.selectedCrossRefs().length"
          [studyTermCount]="state.selectedStudyTerms().length"
          (copy)="state.copySelected()"
          (toggleBookmark)="bible.toggleBookmark(selected)"
          (openNote)="showNoteModal.set(true)"
          (openCrossRefs)="showCrossRefs.set(true)"
          (openStudy)="showStudy.set(true)"
          (highlightChanged)="bible.setHighlight(selected.verse, $event)"
          (closed)="state.clearSelection()"
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
      .bible-bar {
        position: sticky;
        top: 0;
        z-index: 30;
        background-color: var(--bg);
        border-bottom: 1px solid var(--surface-border);
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
        gap: 8px;
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
        border: 1px solid var(--surface-border);
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
        padding-top: 18px;
        padding-bottom: 96px;
      }

      .status-msg,
      .error-card {
        padding: 36px 0;
        text-align: center;
        color: var(--on-surface-muted);
      }

      .summary-card {
        padding: 12px 14px;
        margin-bottom: 16px;
        border-radius: var(--radius-md);
        background-color: var(--accent-soft);
        border: 1px solid var(--surface-border);
        font-size: 14px;
      }

      .verses-flow {
        display: flex;
        flex-direction: column;
        gap: 6px;
      }

      .verse-row {
        display: flex;
        align-items: baseline;
        gap: 8px;
        padding: 6px 10px;
        border-radius: var(--radius-sm);
        cursor: pointer;
        transition: background-color 120ms ease;
      }

      .verse-row:hover {
        background-color: var(--surface-variant);
      }

      .verse-row.selected {
        outline: 2px solid var(--accent);
      }

      .verse-num {
        font-size: 0.75em;
        font-weight: 700;
        color: var(--accent);
        min-width: 20px;
        user-select: none;
      }

      .verse-text {
        flex: 1;
      }

      .verse-mark {
        font-size: 16px;
        color: var(--accent);
      }

      .chapter-nav {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 10px;
        margin-top: 24px;
        padding-top: 16px;
        border-top: 1px solid var(--surface-border);
      }

      .chapter-indicator-btn {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        padding: 6px 12px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        font-size: 13px;
        font-weight: 600;
        color: var(--on-surface);
        min-width: 0;
      }
    `,
  ],
})
export class BibleReaderComponent implements OnInit {
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

  readonly selectedRefLabel = computed(() => {
    const v = this.state.selectedVerse();
    return v
      ? `${this.bible.currentBook().name} ${this.bible.chapter()}:${v.verse}`
      : '';
  });

  ngOnInit(): void {
    void this.bible.init();
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
