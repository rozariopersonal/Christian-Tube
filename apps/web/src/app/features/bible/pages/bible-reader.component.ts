import { NgTemplateOutlet } from '@angular/common';
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
import { ActivatedRoute, Router } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { combineLatest } from 'rxjs';
import { ScreenClassService } from '../../../core/layout/screen-class.service';
import { HeaderSearchService } from '../../../core/services/header-search.service';
import { HeaderSlotService } from '../../../core/services/header-slot.service';
import { ReaderAppearanceService } from '../../../core/services/reader-appearance.service';
import { ReaderFullscreenService } from '../../../core/services/reader-fullscreen.service';
import { InfiniteScrollTriggerDirective } from '../../../shared/ui/infinite-scroll-trigger.directive';
import { ReaderColumnsToggleComponent } from '../../../shared/ui/reader-columns-toggle.component';
import { ReaderTypographyToggleComponent } from '../../../shared/ui/reader-typography-toggle.component';
import { ReaderSpreadFooterComponent } from '../../../shared/ui/reader-spread-footer.component';
import {
  computeSpreadMetrics,
  scrollElementIntoSpread,
  scrollToSpreadPage,
} from '../../../shared/ui/spread-pager';
import { DictionarySheetComponent } from '../../books/components/dictionary-sheet.component';
import { BibleAppearanceSheetComponent } from '../components/bible-appearance-sheet.component';
import {
  BibleBookChapterSheetComponent,
  BiblePickerTab,
  BibleSelectionTarget,
} from '../components/bible-book-chapter-sheet.component';
import { BibleBookmarksSheetComponent } from '../components/bible-bookmarks-sheet.component';
import {
  BibleVersionPickerComponent,
  BibleVersionSelectionEvent,
} from '../../../shared/ui/bible-version-picker.component';
import { BibleVersionSelectionService } from '../../../core/services/bible-version-selection.service';
import { BibleCompareSheetComponent } from '../components/bible-compare-sheet.component';
import { BibleCrossRefsSheetComponent } from '../components/bible-cross-refs-sheet.component';
import { BibleNoteSheetComponent } from '../components/bible-note-sheet.component';
import { BibleSearchSheetComponent } from '../components/bible-search-sheet.component';
import { BibleSidebarComponent } from '../components/bible-sidebar.component';
import { BibleStudySheetComponent } from '../components/bible-study-sheet.component';
import {
  InlineToolbarAnchor,
  computeElementToolbarAnchor,
  computeInlineToolbarAnchor,
} from '../../../shared/ui/text-highlight.util';
import { TextSelectionPopoverComponent } from '../../../shared/ui/text-selection-popover.component';
import { ReaderAutoFullscreenToggleComponent } from '../../../shared/ui/reader-auto-fullscreen-toggle.component';
import { BIBLE_VERSIONS, BibleVerse } from '../models/bible.model';
import { BibleReaderStateService } from '../services/bible-reader-state.service';
import { BibleService } from '../services/bible.service';

interface AppendedBibleChapter {
  bookNumber: number;
  bookName: string;
  chapter: number;
  verses: BibleVerse[];
  parallelMap: Record<string, Record<number, string>>;
}

@Component({
  selector: 'app-bible-reader',
  standalone: true,
  imports: [
    NgTemplateOutlet,
    FormsModule,
    InfiniteScrollTriggerDirective,
    ReaderSpreadFooterComponent,
    BibleVersionPickerComponent,
    BibleBookChapterSheetComponent,
    BibleSidebarComponent,
    TextSelectionPopoverComponent,
    BibleAppearanceSheetComponent,
    BibleBookmarksSheetComponent,
    BibleCrossRefsSheetComponent,
    BibleStudySheetComponent,
    BibleNoteSheetComponent,
    BibleSearchSheetComponent,
    BibleCompareSheetComponent,
    DictionarySheetComponent,
  ],
  providers: [BibleReaderStateService],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div
      class="bible-page"
      [attr.data-paper]="appearance.paperTheme()"
      [class.immersive]="immersive()"
      [class.spread-mode]="spreadMode()"
      (pointerdown)="readerFullscreen.noteActivity('bible')"
      (wheel)="readerFullscreen.noteActivity('bible')"
      (touchstart)="readerFullscreen.noteActivity('bible')"
    >
      <ng-template #topbarCenter>
        <div class="tb-bible-center">
          <app-bible-version-picker
            contextKey="bible"
            (selectionChanged)="onVersionPickerChanged($event)"
          />
        </div>
      </ng-template>

      <ng-template #topbarRight>
        <div class="tb-font-stepper" aria-label="Font size">
          <button
            type="button"
            class="tb-step-btn"
            aria-label="Decrease font size"
            title="Decrease font size"
            (click)="appearance.stepFontSize(-1)"
          >
            −
          </button>
          <span class="tb-font-val">{{ appearance.fontSize() }}</span>
          <button
            type="button"
            class="tb-step-btn"
            aria-label="Increase font size"
            title="Increase font size"
            (click)="appearance.stepFontSize(1)"
          >
            +
          </button>
        </div>
        <div class="tb-actions-pill">
          <button
            type="button"
            class="tb-action-btn"
            title="Reader Appearance & Themes"
            aria-label="Reader Appearance & Themes"
            (click)="showAppearance.set(true)"
          >
            <span class="material-symbols-rounded">palette</span>
          </button>
          <div class="menu-wrap">
            <button
              type="button"
              class="tb-action-btn"
              aria-label="More reader options"
              title="Bookmarks, Share & Search"
              (click)="menuOpen.set(!menuOpen())"
            >
              <span class="material-symbols-rounded">more_vert</span>
            </button>
            @if (menuOpen()) {
              <div class="overflow-menu" (click)="menuOpen.set(false)">
                <button
                  type="button"
                  class="menu-item"
                  (click)="openBookPicker('books')"
                >
                  <span class="material-symbols-rounded">menu_book</span>
                  Books &amp; Chapters
                </button>
                <button
                  type="button"
                  class="menu-item"
                  (click)="submitTopbarSearch()"
                >
                  <span class="material-symbols-rounded">search</span>
                  Search Bible
                </button>
                <button
                  type="button"
                  class="menu-item"
                  (click)="showBookmarks.set(true)"
                >
                  <span class="material-symbols-rounded">bookmarks</span>
                  Bookmarks
                </button>
                <button
                  type="button"
                  class="menu-item"
                  (click)="sharePassage()"
                >
                  <span class="material-symbols-rounded">share</span>
                  Share Chapter
                </button>
              </div>
            }
          </div>
        </div>
      </ng-template>

      @if (!immersive() && screen.isCompact()) {
        <header class="bible-bar">
          <div class="bar-inner">
            <div class="bar-left">
              <app-bible-version-picker
                contextKey="bible"
                (selectionChanged)="onVersionPickerChanged($event)"
              />

              @if (
                !screen.isCompact() &&
                !bible.loading() &&
                !bible.error() &&
                displayVerseCount() > 0
              ) {
                <span class="bar-meta">
                  {{ displayBookNumber() <= 39 ? 'OT' : 'NT' }} ·
                  {{ displayVerseCount() }} verses ·
                  {{ displayReadingMinutes() }} min read
                </span>
              }
            </div>

            <div class="bar-right">
              @if (!screen.collapseAppBarActions()) {
                <button
                  type="button"
                  class="icon-btn"
                  title="Search Bible"
                  (click)="submitTopbarSearch()"
                >
                  <span class="material-symbols-rounded">search</span>
                </button>
                <button
                  type="button"
                  class="icon-btn aa-btn"
                  title="Reader Appearance"
                  (click)="showAppearance.set(true)"
                >
                  Aa
                </button>
              }

              @if (!screen.collapseReaderActions()) {
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
                  class="icon-btn"
                  title="Focus mode (F)"
                  (click)="immersive.set(true)"
                >
                  <span class="material-symbols-rounded">fullscreen</span>
                </button>
              } @else {
                <div class="menu-wrap">
                  <button
                    type="button"
                    class="icon-btn"
                    aria-label="More reader options"
                    (click)="menuOpen.set(!menuOpen())"
                  >
                    <span class="material-symbols-rounded">more_vert</span>
                  </button>
                  @if (menuOpen()) {
                    <div class="overflow-menu" (click)="menuOpen.set(false)">
                      @if (screen.collapseAppBarActions()) {
                        <button
                          type="button"
                          class="menu-item"
                          (click)="submitTopbarSearch()"
                        >
                          <span class="material-symbols-rounded">search</span>
                          Search Bible
                        </button>
                        <button
                          type="button"
                          class="menu-item"
                          (click)="showAppearance.set(true)"
                        >
                          <span class="material-symbols-rounded">text_fields</span>
                          Appearance (Aa)
                        </button>
                      }
                      <button
                        type="button"
                        class="menu-item"
                        (click)="showBookmarks.set(true)"
                      >
                        <span class="material-symbols-rounded">bookmarks</span>
                        Bookmarks
                      </button>
                      <button
                        type="button"
                        class="menu-item"
                        (click)="sharePassage()"
                      >
                        <span class="material-symbols-rounded">share</span>
                        Share Chapter
                      </button>
                      <button
                        type="button"
                        class="menu-item"
                        (click)="immersive.set(true)"
                      >
                        <span class="material-symbols-rounded">fullscreen</span>
                        Focus Mode
                      </button>
                    </div>
                  }
                </div>
              }
            </div>
          </div>
        </header>
      } @else if (immersive()) {
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
        class="bible-layout"
        [class.has-sidebar]="screen.isMediumOrExpanded() && !immersive() && bible.books().length > 0"
      >
        @if (screen.isMediumOrExpanded() && !immersive() && bible.books().length > 0) {
          <app-bible-sidebar
            [books]="bible.books()"
            [currentBookNumber]="displayBookNumber()"
            [currentChapter]="displayChapter()"
            [versionLabel]="state.activeVersionInfo().label"
            (selectChapter)="jumpFromSearch($event)"
            (versionChanged)="onVersionPickerChanged($event)"
          />
        }

        <div class="reader-body">
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
        } @else if (spreadMode()) {
          @if (bible.fallbackNotice()) {
            <p class="status-msg">{{ bible.fallbackNotice() }}</p>
          }
          <div class="spread-viewport" #spreadViewport>
            <div
              class="spread-track"
              [attr.data-cols]="effectiveCols()"
              [class.paragraph-mode]="appearance.bibleLayout() === 'paragraph'"
              [attr.data-chapter-book]="bible.bookNumber()"
              [attr.data-chapter-num]="bible.chapter()"
              [attr.data-chapter-name]="bible.currentBook().name"
              [attr.data-verse-count]="bible.verses().length"
              [style.font-family]="appearance.activeFont().cssFamily"
              [style.font-size.px]="appearance.fontSize()"
              [style.line-height]="appearance.lineHeight()"
              [style.letter-spacing.em]="appearance.letterSpacing()"
              (dblclick)="lookupFromSelection()"
            >
              <ng-container [ngTemplateOutlet]="bibleVersesTpl" />
            </div>
          </div>
          <app-reader-spread-footer
            [label]="spreadFooterLabel()"
            [page]="spreadPage()"
            [totalPages]="spreadTotalPages()"
            [hasPrevChapter]="hasPrevChapter()"
            [hasNextChapter]="hasNextChapter()"
            (prevPage)="goToSpreadPage(spreadPage() - 1)"
            (nextPage)="goToSpreadPage(spreadPage() + 1)"
          />
        } @else {
          @if (hasPrevChapter()) {
            <div class="top-scroll-sentinel">
              <button
                type="button"
                class="load-prev-btn"
                [disabled]="loadingPrev()"
                (click)="prependPrevChapter()"
              >
                @if (loadingPrev()) {
                  <span>Loading {{ prevChapterLabel() }}...</span>
                } @else {
                  <span class="material-symbols-rounded">arrow_upward</span>
                  <span>{{ prevChapterLabel() }}</span>
                }
              </button>
            </div>
          }

          @for (extra of prependedChapters(); track extra.bookNumber + ':' + extra.chapter) {
            <ng-container
              [ngTemplateOutlet]="extraChapterTpl"
              [ngTemplateOutletContext]="{ $implicit: extra, isPrepended: true }"
            />
          }

          @if (bible.fallbackNotice()) {
            <p class="status-msg">{{ bible.fallbackNotice() }}</p>
          }

          @if (bible.compareVersions().length > 0) {
            <div class="parallel-col-headers">
              @for (verId of activeCompareIds(); track verId) {
                <span class="parallel-header-pill">{{ versionLabel(verId) }}</span>
              }
            </div>
          }

          <article
            class="verses-flow"
            [attr.data-chapter-book]="bible.bookNumber()"
            [attr.data-chapter-num]="bible.chapter()"
            [attr.data-chapter-name]="bible.currentBook().name"
            [attr.data-verse-count]="bible.verses().length"
            [class.paragraph-mode]="
              appearance.bibleLayout() === 'paragraph' &&
              bible.compareVersions().length === 0
            "
            [attr.data-cols]="
              bible.compareVersions().length === 0 ? effectiveCols() : 1
            "
            [style.font-family]="appearance.activeFont().cssFamily"
            [style.font-size.px]="appearance.fontSize()"
            [style.line-height]="appearance.lineHeight()"
            [style.letter-spacing.em]="appearance.letterSpacing()"
            (dblclick)="lookupFromSelection()"
          >
            <ng-container [ngTemplateOutlet]="bibleVersesTpl" />
          </article>

          @for (extra of appendedChapters(); track extra.bookNumber + ':' + extra.chapter) {
            <ng-container
              [ngTemplateOutlet]="extraChapterTpl"
              [ngTemplateOutletContext]="{ $implicit: extra, isPrepended: false }"
            />
          }

          <ng-template #extraChapterTpl let-extra let-isPrepended="isPrepended">
            <section
              class="appended-chapter"
              [class.prepended-chapter]="isPrepended"
              [attr.data-chapter-book]="extra.bookNumber"
              [attr.data-chapter-num]="extra.chapter"
              [attr.data-chapter-name]="extra.bookName"
              [attr.data-verse-count]="extra.verses.length"
            >
              <header class="chapter-hero appended-hero">
                <h2 class="hero-title font-display">
                  {{ extra.bookName }} {{ extra.chapter }}
                </h2>
                <div class="hero-meta">
                  <span class="hero-eyebrow">{{ activeVersionLabels().join(' · ') }}</span>
                  <span>·</span>
                  <span>{{ extra.verses.length }} verses</span>
                </div>
              </header>

              <article
                class="verses-flow"
                [class.paragraph-mode]="
                  appearance.bibleLayout() === 'paragraph' &&
                  bible.compareVersions().length === 0
                "
                [attr.data-cols]="
                  bible.compareVersions().length === 0 ? effectiveCols() : 1
                "
                [style.font-family]="appearance.activeFont().cssFamily"
                [style.font-size.px]="appearance.fontSize()"
                [style.line-height]="appearance.lineHeight()"
                [style.letter-spacing.em]="appearance.letterSpacing()"
                (dblclick)="lookupFromSelection()"
              >
                @for (v of extra.verses; track v.verse) {
                  @if (bible.compareVersions().length > 0) {
                    <div class="parallel-row">
                      <div class="parallel-cell">
                        <span class="verse-num">{{ v.verse }}</span>
                        <span>{{ v.text }}</span>
                      </div>
                      @for (compId of bible.compareVersions(); track compId) {
                        <div class="parallel-cell">
                          <span class="verse-num">{{ v.verse }}</span>
                          <span>{{ extra.parallelMap[compId]?.[v.verse] || '—' }}</span>
                        </div>
                      }
                    </div>
                  } @else if (appearance.bibleLayout() === 'paragraph') {
                    <span class="verse-inline">
                      <sup class="verse-sup">{{ v.verse }}</sup>
                      <span>{{ v.text }}</span>{{ ' ' }}
                    </span>
                  } @else {
                    <div class="verse-row">
                      <span class="verse-num">{{ v.verse }}</span>
                      <div class="verse-content">
                        <span class="verse-text">{{ v.text }}</span>
                      </div>
                    </div>
                  }
                }
              </article>
            </section>
          </ng-template>

          <div
            class="scroll-sentinel"
            appInfiniteScrollTrigger
            [disabled]="loadingMore() || !hasNextChapter()"
            (triggered)="appendNextChapter()"
          >
            @if (loadingMore()) {
              <span>Loading next chapter...</span>
            }
          </div>
        }

        <ng-template #bibleVersesTpl>
          @for (v of bible.verses(); track v.verse) {
            @let selected = state.selectedVerse()?.verse === v.verse;
            @let note = state.noteFor(v.verse);
            @let refCount = state.crossRefCountMap().get(v.verse) ?? 0;
            @let studyCount = state.studyCountMap().get(v.verse) ?? 0;

            @if (bible.compareVersions().length > 0) {
              <div
                [id]="'verse-' + v.verse"
                class="parallel-row"
                [class.selected]="selected"
                [style.background-color]="state.highlightFor(v.verse)"
                (click)="onVerseTap(v)"
              >
                <div class="parallel-cell">
                  <span class="verse-num">{{ v.verse }}</span>
                  <span>{{ v.text }}</span>
                </div>
                @for (compId of bible.compareVersions(); track compId) {
                  <div class="parallel-cell">
                    <span class="verse-num">{{ v.verse }}</span>
                    <span>{{ primaryParallelMap()[compId]?.[v.verse] || '—' }}</span>
                  </div>
                }
              </div>
            } @else if (appearance.bibleLayout() === 'paragraph') {
              <span
                [id]="'verse-' + v.verse"
                class="verse-inline"
                [class.selected]="selected"
                [style.background-color]="state.highlightFor(v.verse)"
                (click)="onVerseTap(v)"
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
                (click)="onVerseTap(v)"
              >
                <span class="verse-num">{{ v.verse }}</span>
                <div class="verse-content">
                  <span class="verse-text">{{ v.text }}</span>
                  @if (note) {
                    <p class="verse-note-preview">{{ note }}</p>
                  }
                </div>
                <div class="verse-badges">
                  @if (refCount > 0) {
                    <button
                      type="button"
                      class="mini-badge"
                      title="Cross-References"
                      (click)="$event.stopPropagation(); openVerseCrossRefs(v)"
                    >
                      ↗ {{ refCount }}
                    </button>
                  }
                  @if (studyCount > 0) {
                    <button
                      type="button"
                      class="mini-badge study-badge"
                      title="Study & Lexicon"
                      (click)="$event.stopPropagation(); openVerseStudy(v)"
                    >
                      <span class="material-symbols-rounded badge-ic">school</span>
                      {{ studyCount }}
                    </button>
                  }
                  @if (bible.isBookmarked(v.verse)) {
                    <span class="material-symbols-rounded verse-mark">bookmark</span>
                  }
                  @if (note) {
                    <span class="material-symbols-rounded verse-mark">sticky_note_2</span>
                  }
                </div>
              </div>
            }
          }
        </ng-template>
        </div>
      </div>

      @if (screen.isCompact() && !immersive() && !spreadMode()) {
        <nav class="bible-bottom-pill" aria-label="Bible chapter navigation">
          <button
            type="button"
            class="pill-step-btn"
            aria-label="Previous chapter"
            title="Previous chapter"
            (click)="prevChapter()"
          >
            <span class="material-symbols-rounded">chevron_left</span>
          </button>

          <button
            type="button"
            class="pill-book-btn"
            (click)="openBookPicker('books')"
          >
            <span>{{ displayBookName() }} {{ displayChapter() }}</span>
            <span class="material-symbols-rounded">expand_more</span>
          </button>

          <button
            type="button"
            class="pill-step-btn"
            aria-label="Next chapter"
            title="Next chapter"
            (click)="nextChapter()"
          >
            <span class="material-symbols-rounded">chevron_right</span>
          </button>
        </nav>
      }

      @if (state.selectedVerse(); as selected) {
        <app-text-selection-popover
          [anchor]="verseToolbarAnchor() ?? defaultToolbarAnchor"
          [activeColor]="bible.highlights()[bible.verseKey(selected.verse)] ?? null"
          [showBookmark]="true"
          [isBookmarked]="bible.isBookmarked(selected.verse)"
          [showNote]="true"
          [hasNote]="!!state.noteFor(selected.verse)"
          [showCompare]="true"
          [showCopy]="true"
          [showShare]="true"
          [showClose]="true"
          [crossRefCount]="state.selectedCrossRefs().length"
          [studyTermCount]="state.selectedStudyTerms().length"
          (highlight)="bible.setHighlight(selected.verse, $event)"
          (clear)="bible.setHighlight(selected.verse, null)"
          (toggleBookmark)="bible.toggleBookmark(selected)"
          (openNote)="showNoteModal.set(true)"
          (compare)="showCompare.set(true)"
          (copy)="state.copySelected()"
          (share)="sharePassage(selected.verse)"
          (openCrossRefs)="showCrossRefs.set(true)"
          (openStudy)="showStudy.set(true)"
          (closed)="state.clearSelection()"
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

      @if (showSearch()) {
        <app-bible-search-sheet
          [version]="bible.version()"
          [currentBook]="bible.currentBook()"
          (jumpTo)="jumpFromSearch($event)"
          (closed)="showSearch.set(false)"
        />
      }

      @if (showAppearance()) {
        <app-bible-appearance-sheet (closed)="showAppearance.set(false)" />
      }

      @if (showCompare() && state.selectedVerse(); as selected) {
        <app-bible-compare-sheet
          [bookNumber]="bible.bookNumber()"
          [chapter]="bible.chapter()"
          [verse]="selected.verse"
          [referenceLabel]="selectedRefLabel()"
          (closed)="showCompare.set(false)"
        />
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
      .bible-page {
        min-height: calc(100dvh - var(--shell-top-offset));
        background-color: var(--reader-bg, var(--bg));
        color: var(--reader-fg, var(--on-surface));
        transition: background-color 180ms ease, color 180ms ease;
      }

      .bible-bar {
        position: sticky;
        top: var(--shell-top-offset);
        z-index: 30;
        border-bottom: 1px solid var(--reader-border, var(--surface-border));
      }

      .bible-bar::before {
        content: '';
        position: absolute;
        inset: 0;
        z-index: -1;
        pointer-events: none;
        background-color: color-mix(in srgb, var(--reader-bg, var(--bg)) 90%, transparent);
        backdrop-filter: blur(12px);
        -webkit-backdrop-filter: blur(12px);
      }

      .tb-bible-center {
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 8px;
        width: 100%;
        max-width: 620px;
        min-width: 0;
        margin: 0 auto;
      }

      .tb-bible-center app-bible-version-picker {
        flex: 0 1 auto;
        min-width: 0;
      }

      .bar-left app-bible-version-picker {
        flex: 0 1 auto;
        min-width: 0;
      }

      @media (max-width: 599px) {
        .bar-inner {
          padding-inline: 8px;
          gap: 4px;
        }

        .bar-left {
          flex: 1;
          gap: 4px;
        }

        .bar-left app-bible-version-picker {
          max-width: 148px;
          overflow: hidden;
        }

        .nav-step-btn {
          width: 24px;
        }

        .book-btn {
          font-size: 13px;
          padding: 0 4px;
        }
      }

      .tb-search-form {
        flex: 1;
        min-width: 180px;
        height: 40px;
        display: flex;
        align-items: center;
      }

      .tb-search-wrap {
        flex: 1;
        height: 100%;
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 0 12px;
        background-color: var(--bg);
        border: 1px solid var(--surface-border);
        border-right: none;
        border-radius: var(--radius-pill) 0 0 var(--radius-pill);
      }

      .tb-search-wrap:focus-within {
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
        font-size: 14px;
      }

      .tb-clear-btn {
        width: 24px;
        height: 24px;
        border-radius: var(--radius-pill);
        display: grid;
        place-items: center;
        color: var(--on-surface-muted);
      }

      .tb-clear-btn .material-symbols-rounded {
        font-size: 16px;
      }

      .tb-search-submit {
        height: 100%;
        width: 56px;
        display: grid;
        place-items: center;
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
        border-radius: 0 var(--radius-pill) var(--radius-pill) 0;
        color: var(--on-surface);
        flex-shrink: 0;
      }

      .tb-search-submit:hover {
        background-color: var(--surface-elevated);
      }

      .bar-inner {
        height: var(--topbar-height);
        width: 100%;
        padding-inline: clamp(10px, 2.5vw, 32px);
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 6px;
      }

      .bar-left,
      .bar-right {
        display: flex;
        align-items: center;
        gap: 4px;
        min-width: 0;
      }

      .version-pill {
        display: inline-flex;
        align-items: center;
        gap: 1px;
        height: 32px;
        padding: 0 8px 0 10px;
        border-radius: var(--radius-pill);
        background-color: var(--accent-soft);
        border: 1px solid var(--accent);
        color: var(--accent);
        font-size: 12px;
        font-weight: 700;
        flex-shrink: 0;
      }

      .pill-chev {
        font-size: 16px;
      }

      .chapter-nav-group {
        display: inline-flex;
        align-items: center;
        background-color: var(--surface-variant);
        border: 1px solid var(--reader-border, var(--surface-border));
        border-radius: var(--radius-sm);
        min-width: 0;
        overflow: hidden;
      }

      .nav-step-btn {
        width: 28px;
        height: 32px;
        display: grid;
        place-items: center;
        color: var(--on-surface);
        flex-shrink: 0;
      }

      .nav-step-btn:hover {
        background-color: var(--accent-soft);
        color: var(--accent);
      }

      .book-btn {
        display: inline-flex;
        align-items: center;
        gap: 2px;
        height: 32px;
        padding: 0 6px;
        color: var(--on-surface);
        font-size: 14px;
        font-weight: 600;
        flex: 1 1 auto;
        min-width: 0;
        overflow: hidden;
      }

      .book-btn span:first-child {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .book-btn .material-symbols-rounded {
        flex-shrink: 0;
        font-size: 18px;
      }

      .tb-font-stepper {
        display: inline-flex;
        align-items: center;
        height: 32px;
        padding: 0 2px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
      }

      .tb-step-btn {
        width: 26px;
        height: 28px;
        border-radius: var(--radius-pill);
        display: grid;
        place-items: center;
        color: var(--on-surface);
        font-size: 15px;
        font-weight: 600;
      }

      .tb-step-btn:hover {
        background-color: var(--accent-soft);
        color: var(--accent);
      }

      .tb-font-val {
        min-width: 22px;
        text-align: center;
        font-size: 12px;
        font-weight: 600;
        color: var(--on-surface-muted);
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
        position: relative;
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

      .compare-btn {
        position: relative;
      }

      .active-icon {
        color: var(--accent);
        background-color: var(--accent-soft);
      }

      .compare-count {
        position: absolute;
        top: 2px;
        right: 2px;
        min-width: 15px;
        height: 15px;
        border-radius: var(--radius-pill);
        background-color: var(--accent);
        color: var(--on-accent);
        font-size: 10px;
        font-weight: 700;
        display: grid;
        place-items: center;
      }

      .aa-btn {
        font-family: Georgia, serif;
        font-weight: 700;
        font-size: 16px;
      }

      .menu-wrap {
        position: relative;
      }

      .overflow-menu {
        position: absolute;
        top: 44px;
        right: 0;
        min-width: 190px;
        background-color: var(--surface);
        color: var(--on-surface);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-md);
        box-shadow: 0 8px 24px rgba(0, 0, 0, 0.16);
        padding: 6px;
        display: flex;
        flex-direction: column;
        z-index: 60;
      }

      .menu-item {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 10px 12px;
        border-radius: var(--radius-sm);
        font-size: 14px;
        text-align: left;
      }

      .menu-item:hover {
        background-color: var(--surface-variant);
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
        color: var(--on-surface);
        border: 1px solid var(--surface-border);
        display: grid;
        place-items: center;
        opacity: 0.75;
      }

      .bible-bottom-pill {
        position: fixed;
        left: calc(var(--sidebar-width, 0px) + 12px);
        right: 12px;
        bottom: calc(var(--shell-bottom-offset) + 8px);
        z-index: 32;
        max-width: 460px;
        height: 48px;
        margin-inline: auto;
        padding: 0 6px;
        border-radius: 24px;
        background-color: var(--accent);
        color: var(--on-accent);
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 4px;
        box-shadow: 0 6px 18px color-mix(in srgb, var(--scrim) 24%, transparent);
      }

      .pill-step-btn {
        width: 40px;
        height: 40px;
        border-radius: 20px;
        display: grid;
        place-items: center;
        color: var(--on-accent);
        flex-shrink: 0;
      }

      .pill-book-btn {
        flex: 1;
        min-width: 0;
        height: 40px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 4px;
        color: var(--on-accent);
        font-size: 15px;
        font-weight: 700;
      }

      .pill-book-btn span:first-child {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      @media (max-width: 599px) {
        .reader-body {
          padding-bottom: 132px;
        }
      }

      .reader-body {
        width: 100%;
        padding: 14px clamp(16px, 3vw, 40px) 72px;
      }

      .bar-meta {
        font-size: 12px;
        font-weight: 500;
        color: var(--reader-muted, var(--on-surface-muted));
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .bible-layout {
        display: flex;
        align-items: flex-start;
        width: 100%;
      }

      .bible-layout.has-sidebar .reader-body {
        flex: 1;
        min-width: 0;
      }

      .bible-page.spread-mode {
        height: calc(100dvh - var(--shell-top-offset) - var(--shell-bottom-offset, 0px));
        min-height: 0;
        overflow: hidden;
        display: flex;
        flex-direction: column;
      }

      .bible-page.spread-mode.immersive {
        height: 100dvh;
      }

      .bible-page.spread-mode .reader-bar {
        position: static;
        top: auto;
        flex-shrink: 0;
      }

      .bible-page.spread-mode .bible-layout {
        flex: 1;
        min-height: 0;
        align-items: stretch;
        overflow: hidden;
      }

      .bible-page.spread-mode .reader-body {
        flex: 1;
        min-width: 0;
        min-height: 0;
        display: flex;
        flex-direction: column;
        padding: 14px clamp(16px, 3vw, 40px) 0;
        overflow: hidden;
      }

      .spread-viewport {
        flex: 1;
        min-height: 0;
        overflow: hidden;
        position: relative;
      }

      .spread-track {
        height: 100%;
        column-fill: auto;
        column-gap: 44px;
        column-rule: 1px solid var(--reader-border, var(--surface-border));
      }

      .spread-track[data-cols='1'] {
        column-count: 1;
      }

      .spread-track[data-cols='2'] {
        column-count: 2;
      }

      .spread-track[data-cols='3'] {
        column-count: 3;
      }

      .spread-track .verse-row {
        break-inside: avoid;
        margin-bottom: 6px;
      }

      .nav-drawer-backdrop {
        position: fixed;
        inset: 0;
        z-index: 55;
        background-color: rgba(0, 0, 0, 0.42);
        display: flex;
      }

      .nav-drawer-panel {
        width: min(300px, 85vw);
        height: 100%;
        display: flex;
        flex-direction: column;
        background-color: var(--reader-bg, var(--surface));
        border-right: 1px solid var(--reader-border, var(--surface-border));
        box-shadow: 0 12px 32px rgba(0, 0, 0, 0.24);
      }

      .nav-drawer-top {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 10px 10px 10px 14px;
        border-bottom: 1px solid var(--reader-border, var(--surface-border));
      }

      .nav-drawer-title {
        font-size: 14px;
        font-weight: 700;
        color: var(--reader-fg, var(--on-surface));
      }

      .chapter-hero {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        flex-wrap: wrap;
        gap: 6px 14px;
        margin-bottom: 14px;
        padding-bottom: 10px;
        border-bottom: 1px solid var(--reader-border, var(--surface-border));
      }

      .appended-chapter {
        margin-top: 36px;
      }

      .prepended-chapter {
        margin-top: 0;
        margin-bottom: 36px;
      }

      .top-scroll-sentinel {
        display: flex;
        justify-content: center;
        margin-bottom: 16px;
      }

      .load-prev-btn {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        min-height: 32px;
        padding: 4px 12px;
        border-radius: var(--radius-pill);
        border: 1px solid var(--reader-border, var(--surface-border));
        background-color: var(--reader-surface, var(--surface-variant));
        color: var(--reader-muted, var(--on-surface-muted));
        font-size: 12px;
        font-weight: 600;
        cursor: pointer;
      }

      .load-prev-btn:hover {
        border-color: var(--accent);
        color: var(--accent);
      }

      .load-prev-btn .material-symbols-rounded {
        font-size: 15px;
      }

      .appended-hero {
        padding-top: 12px;
      }

      .hero-eyebrow {
        font-size: 12px;
        font-weight: 700;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: var(--accent);
      }

      .hero-title {
        margin: 0;
        font-size: clamp(20px, 2.4vw, 26px);
        line-height: 1.2;
        font-weight: 700;
      }

      .hero-meta {
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        gap: 6px;
        font-size: 13px;
        color: var(--reader-muted, var(--on-surface-muted));
      }

      .parallel-col-headers {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
        gap: 16px;
        margin-bottom: 10px;
        padding-bottom: 8px;
        border-bottom: 1px solid var(--reader-border, var(--surface-border));
      }

      .parallel-header-pill {
        font-size: 12px;
        font-weight: 700;
        color: var(--accent);
        text-transform: uppercase;
        letter-spacing: 0.05em;
      }

      .parallel-row {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
        gap: 16px;
        padding: 10px;
        border-radius: var(--radius-sm);
        border-bottom: 1px solid var(--reader-border, var(--surface-border));
        cursor: pointer;
      }

      .parallel-row.selected {
        outline: 2px solid var(--accent);
      }

      .parallel-cell {
        display: flex;
        align-items: baseline;
        gap: 8px;
        min-width: 0;
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

      .verses-flow[data-cols='2'],
      .verses-flow[data-cols='3'] {
        display: block;
        column-count: 2;
        column-gap: 44px;
        column-rule: 1px solid var(--reader-border, var(--surface-border));
      }

      .verses-flow[data-cols='3'] {
        column-count: 3;
        column-gap: 36px;
      }

      .verses-flow[data-cols='2'] .verse-row,
      .verses-flow[data-cols='3'] .verse-row {
        break-inside: avoid;
        margin-bottom: 6px;
      }

      .verse-inline {
        cursor: pointer;
        border-radius: 4px;
        padding: 2px 3px;
        transition: background-color 120ms ease;
      }

      .verse-inline.selected {
        outline: 2px solid var(--accent);
        outline-offset: -2px;
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
        outline-offset: -2px;
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

      .verse-badges {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        flex-shrink: 0;
      }

      .mini-badge {
        display: inline-flex;
        align-items: center;
        gap: 2px;
        padding: 2px 6px;
        border-radius: var(--radius-pill);
        background-color: var(--accent-soft);
        color: var(--accent);
        font-size: 11px;
        font-weight: 700;
      }

      .badge-ic {
        font-size: 12px;
      }

      .verse-mark {
        font-size: 16px;
        color: var(--accent);
        flex-shrink: 0;
      }

      .scroll-sentinel {
        height: 48px;
        display: grid;
        place-items: center;
        color: var(--reader-muted, var(--on-surface-muted));
        font-size: 13px;
      }
    `,
  ],
})
export class BibleReaderComponent implements OnInit, AfterViewInit {
  private readonly headerSlot = inject(HeaderSlotService);
  private readonly headerSearch = inject(HeaderSearchService);
  private readonly destroyRef = inject(DestroyRef);

  @ViewChild('topbarCenter') topbarCenterRef?: TemplateRef<unknown>;
  @ViewChild('topbarRight') topbarRightRef?: TemplateRef<unknown>;
  private spreadViewportRef?: ElementRef<HTMLElement>;
  private spreadResizeObserver?: ResizeObserver;
  @ViewChild('spreadViewport')
  set spreadViewportSetter(ref: ElementRef<HTMLElement> | undefined) {
    this.spreadViewportRef = ref;
    this.spreadResizeObserver?.disconnect();
    this.spreadResizeObserver = undefined;
    if (ref) {
      this.spreadResizeObserver = new ResizeObserver(() =>
        this.refreshSpreadMetrics(),
      );
      this.spreadResizeObserver.observe(ref.nativeElement);
      queueMicrotask(() => this.refreshSpreadMetrics());
    }
  }
  private readonly viewInitialized = signal<boolean>(false);
  readonly topbarSearchQuery = signal<string>('');
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  readonly screen = inject(ScreenClassService);
  readonly readerFullscreen = inject(ReaderFullscreenService);
  readonly isDesktop = this.screen.isDesktop;
  readonly effectiveCols = computed(() =>
    this.appearance.effectiveColumns(this.screen.screenClass()),
  );
  readonly bible = inject(BibleService);
  readonly appearance = inject(ReaderAppearanceService);
  readonly state = inject(BibleReaderStateService);

  readonly spreadMode = computed(
    () =>
      (this.effectiveCols() >= 2 || this.appearance.singleColPaginated()) &&
      this.bible.compareVersions().length === 0,
  );
  readonly spreadPage = signal<number>(1);
  readonly spreadTotalPages = signal<number>(1);
  private pendingLastSpreadPage = false;
  readonly spreadFooterLabel = computed(
    () => `${this.bible.currentBook().name} ${this.bible.chapter()}`,
  );

  readonly showBookPicker = signal<boolean>(false);
  readonly bookPickerTab = signal<BiblePickerTab>('books');
  readonly showSearch = signal<boolean>(false);
  readonly showAppearance = signal<boolean>(false);
  readonly showCrossRefs = signal<boolean>(false);
  readonly showStudy = signal<boolean>(false);
  readonly showBookmarks = signal<boolean>(false);
  readonly showNoteModal = signal<boolean>(false);
  readonly showCompare = signal<boolean>(false);
  readonly immersive = signal<boolean>(false);
  readonly menuOpen = signal<boolean>(false);
  readonly lookupWord = signal<string | null>(null);

  readonly primaryParallelMap = signal<Record<string, Record<number, string>>>({});
  readonly prependedChapters = signal<AppendedBibleChapter[]>([]);
  readonly appendedChapters = signal<AppendedBibleChapter[]>([]);
  readonly loadingPrev = signal<boolean>(false);
  readonly loadingMore = signal<boolean>(false);
  readonly visibleChapter = signal<{
    bookNumber: number;
    bookName: string;
    chapter: number;
    verseCount: number;
    minutes: number;
  } | null>(null);

  readonly displayBookNumber = computed(
    () => this.visibleChapter()?.bookNumber ?? this.bible.bookNumber(),
  );
  readonly displayBookName = computed(
    () => this.visibleChapter()?.bookName ?? this.bible.currentBook().name,
  );
  readonly displayChapter = computed(
    () => this.visibleChapter()?.chapter ?? this.bible.chapter(),
  );
  readonly displayVerseCount = computed(
    () => this.visibleChapter()?.verseCount ?? this.bible.verses().length,
  );
  readonly displayReadingMinutes = computed(
    () => this.visibleChapter()?.minutes ?? this.readingMinutes(),
  );

  private readonly routeReady = signal<boolean>(false);
  private hasScrolledDown = false;

  readonly activeCompareIds = computed(() => [
    this.bible.version(),
    ...this.bible.compareVersions(),
  ]);

  readonly activeVersionLabels = computed(() =>
    this.activeCompareIds().map((id) => this.versionLabel(id)),
  );

  readonly hasPrevChapter = computed(() => this.prevChapterTarget() !== null);

  readonly prevChapterLabel = computed(() => {
    const t = this.prevChapterTarget();
    return t ? `${t.bookName} ${t.chapter}` : '';
  });

  private prevChapterTarget(): {
    bookNumber: number;
    bookName: string;
    chapter: number;
  } | null {
    const list = this.prependedChapters();
    const first =
      list.length > 0
        ? list[0]
        : { bookNumber: this.bible.bookNumber(), chapter: this.bible.chapter() };
    return this.bible.prevChapterOf(first.bookNumber, first.chapter);
  }

  readonly hasNextChapter = computed(() => {
    const list = this.appendedChapters();
    const last = list.length > 0
      ? list[list.length - 1]
      : { bookNumber: this.bible.bookNumber(), chapter: this.bible.chapter() };
    return this.bible.nextChapterOf(last.bookNumber, last.chapter) !== null;
  });

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

  readonly verseToolbarAnchor = signal<InlineToolbarAnchor | null>(null);
  readonly defaultToolbarAnchor: InlineToolbarAnchor = {
    top: 120,
    left: 240,
    placement: 'below',
  };

  @HostListener('window:resize')
  onWindowResize(): void {
    this.refreshVerseToolbarAnchor();
  }

  @HostListener('window:scroll')
  onWindowScroll(): void {
    this.refreshVerseToolbarAnchor();
    if (this.spreadMode()) return;
    this.syncVisibleChapterFromScroll();
    if (window.scrollY > 180) {
      this.hasScrolledDown = true;
    } else if (
      this.hasScrolledDown &&
      window.scrollY <= 80 &&
      this.hasPrevChapter() &&
      !this.loadingPrev() &&
      !this.bible.loading()
    ) {
      void this.prependPrevChapter();
    }
  }

  private syncVisibleChapterFromScroll(): void {
    if (this.prependedChapters().length === 0 && this.appendedChapters().length === 0) {
      if (this.visibleChapter() !== null) {
        this.visibleChapter.set(null);
      }
      return;
    }
    const nodes = document.querySelectorAll<HTMLElement>('[data-chapter-book]');
    if (nodes.length === 0) return;

    let active: HTMLElement = nodes[0];
    for (const el of Array.from(nodes)) {
      const rect = el.getBoundingClientRect();
      if (rect.top <= 140) {
        active = el;
      } else {
        break;
      }
    }

    const bookNumber = Number(active.dataset['chapterBook'] ?? 0);
    const chapter = Number(active.dataset['chapterNum'] ?? 0);
    const bookName = active.dataset['chapterName'] ?? '';
    const verseCount = Number(active.dataset['verseCount'] ?? 0);
    if (!bookNumber || !chapter) return;

    const cur = this.visibleChapter();
    if (cur && cur.bookNumber === bookNumber && cur.chapter === chapter) {
      return;
    }

    const matchedExtra =
      this.prependedChapters().find(
        (c) => c.bookNumber === bookNumber && c.chapter === chapter,
      ) ??
      this.appendedChapters().find(
        (c) => c.bookNumber === bookNumber && c.chapter === chapter,
      );
    const versesList = matchedExtra ? matchedExtra.verses : this.bible.verses();
    const words = versesList.reduce(
      (acc, v) => acc + (v.text ? v.text.split(/\s+/).length : 0),
      0,
    );
    const minutes = Math.max(1, Math.round(words / 200));

    this.visibleChapter.set({
      bookNumber,
      bookName,
      chapter,
      verseCount,
      minutes,
    });
  }

  @HostListener('window:wheel', ['$event'])
  onWindowWheel(event: WheelEvent): void {
    if (this.spreadMode()) return;
    if (
      event.deltaY < 0 &&
      window.scrollY <= 4 &&
      this.hasPrevChapter() &&
      !this.loadingPrev() &&
      !this.bible.loading()
    ) {
      void this.prependPrevChapter();
    }
  }

  @HostListener('window:keydown', ['$event'])
  onKeyDown(event: KeyboardEvent): void {
    this.readerFullscreen.noteActivity('bible');
    const target = event.target as HTMLElement | null;
    if (
      target &&
      (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA')
    ) {
      return;
    }

    if (event.key === 'Escape') {
      this.state.clearSelection();
      this.showBookPicker.set(false);
      this.showSearch.set(false);
      this.showAppearance.set(false);
      this.showCrossRefs.set(false);
      this.showStudy.set(false);
      this.showBookmarks.set(false);
      this.showNoteModal.set(false);
      this.showCompare.set(false);
      this.lookupWord.set(null);
      this.immersive.set(false);
      this.menuOpen.set(false);
      return;
    }
    if (event.key === 'f' || event.key === 'F') {
      this.immersive.set(!this.immersive());
      return;
    }
    if (
      this.showBookPicker() ||
      this.showSearch() ||
      this.showAppearance() ||
      this.showCrossRefs() ||
      this.showStudy() ||
      this.showBookmarks() ||
      this.showNoteModal() ||
      this.showCompare() ||
      this.lookupWord()
    ) {
      return;
    }
    if (event.key === 'ArrowLeft') {
      if (this.spreadMode()) {
        event.preventDefault();
        this.goToSpreadPage(this.spreadPage() - 1);
      } else {
        this.prevChapter();
      }
    } else if (event.key === 'ArrowRight') {
      if (this.spreadMode()) {
        event.preventDefault();
        this.goToSpreadPage(this.spreadPage() + 1);
      } else {
        this.nextChapter();
      }
    }
  }

  constructor() {
    this.destroyRef.onDestroy(this.readerFullscreen.registerReader('bible', () => this.immersive.set(true)));
    effect(() => this.readerFullscreen.setFullscreen('bible', this.immersive()));
    this.destroyRef.onDestroy(() => {
      this.headerSlot.clear();
      this.spreadResizeObserver?.disconnect();
    });
    effect(() => {
      const spread = this.spreadMode();
      this.effectiveCols();
      this.bible.verses();
      this.bible.loading();
      this.appearance.fontSize();
      this.appearance.lineHeight();
      this.appearance.letterSpacing();
      this.appearance.fontId();
      this.appearance.bibleLayout();
      this.immersive();
      if (spread) {
        if (
          this.prependedChapters().length > 0 ||
          this.appendedChapters().length > 0 ||
          this.visibleChapter() !== null
        ) {
          this.resetInfiniteChapters();
        }
        window.scrollTo({ top: 0, behavior: 'auto' });
        setTimeout(() => this.refreshSpreadMetrics(), 0);
      }
    });
    const unregisterSearch = this.headerSearch.register({
      placeholder: 'Search Bible verses or ref (e.g. John 3:16)...',
      onChange: (q) => this.topbarSearchQuery.set(q),
      onSubmit: (q) => this.submitTopbarSearch(q),
    });
    this.destroyRef.onDestroy(unregisterSearch);

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

  ngAfterViewInit(): void {
    this.viewInitialized.set(true);
  }

  submitTopbarSearch(raw?: string): void {
    const q = (raw ?? this.topbarSearchQuery()).trim();
    void this.router.navigate(['/bible/search'], {
      queryParams: q ? { q } : undefined,
    });
  }

  versionLabel(id: string): string {
    return (
      BIBLE_VERSIONS.find((v) => v.id === id)?.label ?? id.toUpperCase()
    );
  }

  private resetInfiniteChapters(): void {
    this.prependedChapters.set([]);
    this.appendedChapters.set([]);
    this.visibleChapter.set(null);
    this.hasScrolledDown = false;
  }

  private readonly versionSelection = inject(BibleVersionSelectionService);

  private async initFromRoute(
    version?: string,
    book?: string,
    chapter?: number,
    verse?: number,
  ): Promise<void> {
    this.routeReady.set(false);
    this.resetInfiniteChapters();
    const ctxComparisons = this.versionSelection.getComparisonVersions('bible');
    if (version) {
      this.versionSelection.setSelection('bible', version, ctxComparisons);
    }
    const targetVersion = version ?? this.versionSelection.getPrimaryVersion('bible');
    this.bible.compareVersions.set(
      this.versionSelection.getComparisonVersions('bible'),
    );
    await this.bible.init({ version: targetVersion, book, chapter });
    await this.loadPrimaryParallel();
    if (verse && verse > 0) {
      this.focusVerse(verse);
    } else {
      this.state.clearSelection();
    }
    this.routeReady.set(true);
  }

  private async loadPrimaryParallel(): Promise<void> {
    const compareIds = this.bible.compareVersions();
    if (compareIds.length === 0) {
      this.primaryParallelMap.set({});
      return;
    }
    this.primaryParallelMap.set(
      await this.buildParallelMap(
        compareIds,
        this.bible.bookNumber(),
        this.bible.chapter(),
      ),
    );
  }

  private async buildParallelMap(
    versionIds: string[],
    bookNum: number,
    ch: number,
  ): Promise<Record<string, Record<number, string>>> {
    const map: Record<string, Record<number, string>> = {};
    await Promise.all(
      versionIds.map(async (id) => {
        const verses = await this.bible.fetchChapterVerses(id, bookNum, ch);
        const rec: Record<number, string> = {};
        for (const v of verses) {
          rec[v.verse] = v.text;
        }
        map[id] = rec;
      }),
    );
    return map;
  }

  async prependPrevChapter(): Promise<void> {
    if (this.loadingPrev() || this.bible.loading()) return;
    const prevTarget = this.prevChapterTarget();
    if (!prevTarget) return;

    this.loadingPrev.set(true);
    try {
      const verses = await this.bible.fetchChapterVerses(
        this.bible.version(),
        prevTarget.bookNumber,
        prevTarget.chapter,
        true,
      );
      if (verses.length === 0) return;

      const parallelMap =
        this.bible.compareVersions().length > 0
          ? await this.buildParallelMap(
              this.bible.compareVersions(),
              prevTarget.bookNumber,
              prevTarget.chapter,
            )
          : {};

      const prevHeight = document.documentElement.scrollHeight;
      this.prependedChapters.update((cur) => [
        {
          bookNumber: prevTarget.bookNumber,
          bookName: prevTarget.bookName,
          chapter: prevTarget.chapter,
          verses,
          parallelMap,
        },
        ...cur,
      ]);

      requestAnimationFrame(() => {
        const delta = document.documentElement.scrollHeight - prevHeight;
        if (delta > 0) {
          window.scrollBy(0, delta);
        }
      });
    } finally {
      this.loadingPrev.set(false);
    }
  }

  async appendNextChapter(): Promise<void> {
    if (this.loadingMore() || this.bible.loading()) return;
    const list = this.appendedChapters();
    const last =
      list.length > 0
        ? list[list.length - 1]
        : { bookNumber: this.bible.bookNumber(), chapter: this.bible.chapter() };
    const nextTarget = this.bible.nextChapterOf(last.bookNumber, last.chapter);
    if (!nextTarget) return;

    this.loadingMore.set(true);
    try {
      const verses = await this.bible.fetchChapterVerses(
        this.bible.version(),
        nextTarget.bookNumber,
        nextTarget.chapter,
        true,
      );
      if (verses.length === 0) return;

      const parallelMap =
        this.bible.compareVersions().length > 0
          ? await this.buildParallelMap(
              this.bible.compareVersions(),
              nextTarget.bookNumber,
              nextTarget.chapter,
            )
          : {};

      this.appendedChapters.update((cur) => [
        ...cur,
        {
          bookNumber: nextTarget.bookNumber,
          bookName: nextTarget.bookName,
          chapter: nextTarget.chapter,
          verses,
          parallelMap,
        },
      ]);
    } finally {
      this.loadingMore.set(false);
    }
  }

  goToSpreadPage(next: number): void {
    const vp = this.spreadViewportRef?.nativeElement;
    if (!vp) return;
    const total = this.spreadTotalPages();
    if (next < 1) {
      if (this.hasPrevChapter()) {
        this.pendingLastSpreadPage = true;
        this.prevChapter();
      }
      return;
    }
    if (next > total) {
      if (this.hasNextChapter()) {
        this.pendingLastSpreadPage = false;
        this.nextChapter();
      }
      return;
    }
    this.spreadPage.set(next);
    scrollToSpreadPage(vp, next, 44, false);
  }

  private refreshSpreadMetrics(): void {
    const vp = this.spreadViewportRef?.nativeElement;
    if (!vp) return;
    const { totalPages } = computeSpreadMetrics(vp, 44);
    this.spreadTotalPages.set(totalPages);
    if (this.pendingLastSpreadPage) {
      this.pendingLastSpreadPage = false;
      this.spreadPage.set(totalPages);
      scrollToSpreadPage(vp, totalPages, 44, false);
      return;
    }
    if (this.spreadPage() > totalPages) {
      this.spreadPage.set(totalPages);
      scrollToSpreadPage(vp, totalPages, 44, false);
    } else {
      scrollToSpreadPage(vp, this.spreadPage(), 44, false);
    }
  }

  prevChapter(): void {
    const target = this.bible.prevChapterOf(
      this.displayBookNumber(),
      this.displayChapter(),
    );
    this.resetInfiniteChapters();
    this.state.clearSelection();
    if (!this.pendingLastSpreadPage) {
      this.spreadPage.set(1);
    }
    if (target) {
      void this.bible.loadChapter(target.bookNumber, target.chapter);
    } else {
      this.bible.prevChapter();
    }
    void this.loadPrimaryParallel();
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  nextChapter(): void {
    const target = this.bible.nextChapterOf(
      this.displayBookNumber(),
      this.displayChapter(),
    );
    this.resetInfiniteChapters();
    this.state.clearSelection();
    this.pendingLastSpreadPage = false;
    this.spreadPage.set(1);
    if (target) {
      void this.bible.loadChapter(target.bookNumber, target.chapter);
    } else {
      this.bible.nextChapter();
    }
    void this.loadPrimaryParallel();
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  toggleParallelVersion(versionId: string): void {
    this.bible.toggleCompareVersion(versionId);
    void this.refreshAllParallelMaps();
  }

  clearParallelVersions(): void {
    this.bible.clearCompareVersions();
    this.primaryParallelMap.set({});
    this.prependedChapters.update((list) =>
      list.map((c) => ({ ...c, parallelMap: {} })),
    );
    this.appendedChapters.update((list) =>
      list.map((c) => ({ ...c, parallelMap: {} })),
    );
  }

  private async refreshAllParallelMaps(): Promise<void> {
    await this.loadPrimaryParallel();
    const compareIds = this.bible.compareVersions();
    const mapList = async (list: AppendedBibleChapter[]) =>
      list.length === 0
        ? list
        : Promise.all(
            list.map(async (c) => ({
              ...c,
              parallelMap:
                compareIds.length > 0
                  ? await this.buildParallelMap(compareIds, c.bookNumber, c.chapter)
                  : {},
            })),
          );
    const [prepUpdated, appUpdated] = await Promise.all([
      mapList(this.prependedChapters()),
      mapList(this.appendedChapters()),
    ]);
    this.prependedChapters.set(prepUpdated);
    this.appendedChapters.set(appUpdated);
  }

  private refreshVerseToolbarAnchor(): void {
    const selected = this.state.selectedVerse();
    if (!selected) {
      this.verseToolbarAnchor.set(null);
      return;
    }
    const sel = window.getSelection();
    if (sel && !sel.isCollapsed && sel.rangeCount > 0 && sel.toString().trim()) {
      const rangeRect = sel.getRangeAt(0).getBoundingClientRect();
      if (rangeRect.width > 0 || rangeRect.height > 0) {
        this.verseToolbarAnchor.set(computeInlineToolbarAnchor(rangeRect));
        return;
      }
    }
    const el = document.getElementById(`verse-${selected.verse}`);
    this.verseToolbarAnchor.set(
      computeElementToolbarAnchor(el) ?? {
        top: 120,
        left: typeof window !== 'undefined' ? window.innerWidth / 2 : 240,
        placement: 'below',
      },
    );
  }

  private focusVerse(verseNum: number): void {
    const match = this.bible.verses().find((v) => v.verse === verseNum);
    if (match) {
      this.state.selectedVerse.set(match);
      this.refreshVerseToolbarAnchor();
    }
    setTimeout(() => {
      const el = document.getElementById(`verse-${verseNum}`);
      if (!el) return;
      if (this.spreadMode()) {
        const vp = this.spreadViewportRef?.nativeElement;
        if (vp) {
          const page = scrollElementIntoSpread(vp, el, 44, true);
          this.spreadPage.set(page);
        }
      } else {
        el.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }
      this.refreshVerseToolbarAnchor();
      setTimeout(() => this.refreshVerseToolbarAnchor(), 260);
    }, 60);
  }

  onVerseTap(v: BibleVerse): void {
    const sel = window.getSelection()?.toString().trim();
    if (sel) {
      this.state.selectedVerse.set(v);
      this.refreshVerseToolbarAnchor();
      return;
    }
    this.state.toggleSelectVerse(v);
    this.refreshVerseToolbarAnchor();
  }

  openVerseCrossRefs(v: BibleVerse): void {
    this.state.selectedVerse.set(v);
    this.showCrossRefs.set(true);
  }

  openVerseStudy(v: BibleVerse): void {
    this.state.selectedVerse.set(v);
    this.showStudy.set(true);
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
    const v = this.state.selectedVerse();
    if (!v) return;
    const firstWord = v.text
      .split(/\s+/)
      .map((w) => w.replace(/[^a-zA-Z'-]/g, ''))
      .find((w) => w.length >= 4);
    if (firstWord) {
      this.lookupWord.set(firstWord);
    }
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

  onVersionPickerChanged(event: BibleVersionSelectionEvent): void {
    this.bible.compareVersions.set(event.comparisons);
    if (event.kind === 'primary') {
      void this.selectVersion(event.primary);
    } else {
      void this.refreshAllParallelMaps();
    }
  }

  async selectVersion(versionId: string): Promise<void> {
    this.state.clearSelection();
    this.resetInfiniteChapters();
    await this.bible.loadVersion(versionId);
    await this.loadPrimaryParallel();
  }

  openBookPicker(tab: BiblePickerTab): void {
    this.bookPickerTab.set(tab);
    this.showBookPicker.set(true);
  }

  async applySelection(target: BibleSelectionTarget): Promise<void> {
    this.showBookPicker.set(false);
    await this.jumpFromSearch({
      bookNumber: target.bookNumber,
      chapter: target.chapter,
      verse: target.verse,
    });
  }

  async jumpFromSearch(target: {
    bookNumber: number;
    chapter: number;
    verse?: number;
  }): Promise<void> {
    this.showSearch.set(false);
    this.state.clearSelection();
    this.resetInfiniteChapters();
    await this.bible.loadChapter(target.bookNumber, target.chapter);
    await this.loadPrimaryParallel();
    if (target.verse) {
      this.focusVerse(target.verse);
    } else {
      window.scrollTo({ top: 0, behavior: 'smooth' });
    }
  }

  saveNote(verseNum: number, text: string): void {
    this.bible.saveNote(verseNum, text);
    this.showNoteModal.set(false);
  }

  jumpToCrossRef(abbrev: string, ch: number): void {
    this.showCrossRefs.set(false);
    this.state.clearSelection();
    this.resetInfiniteChapters();
    this.bible.jumpToAbbrev(abbrev, ch);
    void this.loadPrimaryParallel();
  }

  jumpToBookmark(bookNum: number, ch: number): void {
    this.showBookmarks.set(false);
    this.state.clearSelection();
    this.resetInfiniteChapters();
    void this.bible.loadChapter(bookNum, ch).then(() => {
      void this.loadPrimaryParallel();
    });
  }
}
