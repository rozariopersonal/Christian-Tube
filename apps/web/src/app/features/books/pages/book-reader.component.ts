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
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { combineLatest } from 'rxjs';
import { ScreenClassService } from '../../../core/layout/screen-class.service';
import { HeaderSlotService } from '../../../core/services/header-slot.service';
import { ReaderAppearanceService } from '../../../core/services/reader-appearance.service';
import { InfiniteScrollTriggerDirective } from '../../../shared/ui/infinite-scroll-trigger.directive';
import { ModalSheetComponent } from '../../../shared/ui/modal-sheet.component';
import { ReaderColumnsToggleComponent } from '../../../shared/ui/reader-columns-toggle.component';
import { ReaderSpreadFooterComponent } from '../../../shared/ui/reader-spread-footer.component';
import {
  computeSpreadMetrics,
  scrollElementIntoSpread,
  scrollToSpreadPage,
} from '../../../shared/ui/spread-pager';
import {
  HighlightedSpanToken,
  InlineToolbarAnchor,
  TextSelectionAnchor,
  applyHighlightRangesToTokens,
  computeElementToolbarAnchor,
  extractLineTextSelection,
} from '../../../shared/ui/text-highlight.util';
import { TextSelectionPopoverComponent } from '../../../shared/ui/text-selection-popover.component';
import { BookAppearanceSheetComponent } from '../components/book-appearance-sheet.component';
import { BookHighlightsSheetComponent } from '../components/book-highlights-sheet.component';
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

interface ParsedBookLineItem {
  line: BookLine;
  tokens: ScriptureSpanToken[];
}

interface ExtraBookChapter {
  chapterIndex: number;
  title: string;
  parsedLines: ParsedBookLineItem[];
  minutes: number;
}

interface SpreadBookChapter {
  chapterIndex: number;
  title: string;
  minutes: number;
  lines: BookLine[];
  parsedLines: Array<{
    line: BookLine;
    tokens: ScriptureSpanToken[];
    hidden: boolean;
  }>;
}

interface ImageSpread {
  chapterIndex: number;
  chapterTitle: string;
  pages: Array<{ fileName: string; pageNumber?: number }>;
}

@Component({
  selector: 'app-book-reader',
  standalone: true,
  imports: [
    NgTemplateOutlet,
    FormsModule,
    InfiniteScrollTriggerDirective,
    ModalSheetComponent,
    ReaderColumnsToggleComponent,
    ReaderSpreadFooterComponent,
    TextSelectionPopoverComponent,
    BookTocSheetComponent,
    BookAppearanceSheetComponent,
    BookHighlightsSheetComponent,
    BookReaderNavComponent,
    BookSearchSheetComponent,
    DictionarySheetComponent,
    ScriptureVerseSheetComponent,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <ng-template #topbarCenter>
      <div class="tb-book-pill">
        @if (!isDesktop()) {
          <button
            type="button"
            class="tb-book-trigger"
            title="Toggle book navigator"
            aria-label="Toggle book navigator"
            [attr.aria-expanded]="showNavigatorDrawer()"
            (click)="showNavigatorDrawer.set(!showNavigatorDrawer())"
          >
            <span class="material-symbols-rounded tb-book-ic">toc</span>
            <span class="tb-book-title">{{ toc()?.title || 'Book Reader' }}</span>
          </button>
        } @else {
          <span class="tb-book-trigger">
            <span class="material-symbols-rounded tb-book-ic">menu_book</span>
            <span class="tb-book-title">{{ toc()?.title || 'Book Reader' }}</span>
          </span>
        }

        @if (toc(); as t) {
          <span class="tb-pill-sep" aria-hidden="true"></span>
          <div class="tb-ch-stepper">
            <button
              type="button"
              class="tb-step-btn"
              aria-label="Previous chapter"
              title="Previous chapter"
              [disabled]="displayChapterIndex() <= 1"
              (click)="prevChapter()"
            >
              <span class="material-symbols-rounded">chevron_left</span>
            </button>
            <button
              type="button"
              class="tb-ch-label"
              (click)="isDesktop() ? null : showNavigatorDrawer.set(!showNavigatorDrawer())"
            >
              Ch. {{ displayChapterIndex() }} / {{ t.chapters.length || 1 }}
            </button>
            <button
              type="button"
              class="tb-step-btn"
              aria-label="Next chapter"
              title="Next chapter"
              [disabled]="displayChapterIndex() >= (t.chapters.length || 1)"
              (click)="nextChapter()"
            >
              <span class="material-symbols-rounded">chevron_right</span>
            </button>
          </div>
        }
      </div>
    </ng-template>

    <ng-template #topbarRight>
      <app-reader-columns-toggle [maxColumns]="isImageBook() ? 2 : 3" />
      <div class="tb-actions-pill">
        <button
          type="button"
          class="tb-action-btn"
          title="Search inside book"
          (click)="showSearch.set(true)"
        >
          <span class="material-symbols-rounded">search</span>
        </button>
        <button
          type="button"
          class="tb-action-btn tb-font-step"
          [title]="isImageBook() ? 'Zoom out' : 'Decrease font size'"
          [attr.aria-label]="isImageBook() ? 'Zoom out' : 'Decrease font size'"
          [disabled]="isImageBook() ? imageZoom() <= 1 : appearance.fontSize() <= 13"
          (click)="
            isImageBook()
              ? setImageZoom(imageZoom() - 0.25)
              : appearance.setFontSize(appearance.fontSize() - 1)
          "
        >
          <span class="material-symbols-rounded">remove</span>
        </button>
        <button
          type="button"
          class="tb-action-btn tb-aa-btn"
          [title]="isImageBook() ? 'Reset zoom / Display & Paper' : 'Display & Layout'"
          (click)="
            isImageBook() && imageZoom() > 1
              ? setImageZoom(1)
              : showAppearance.set(true)
          "
        >
          {{ isImageBook() && imageZoom() > 1 ? Math.round(imageZoom() * 100) + '%' : 'Aa' }}
        </button>
        <button
          type="button"
          class="tb-action-btn tb-font-step"
          [title]="isImageBook() ? 'Zoom in' : 'Increase font size'"
          [attr.aria-label]="isImageBook() ? 'Zoom in' : 'Increase font size'"
          [disabled]="isImageBook() ? imageZoom() >= 2.5 : appearance.fontSize() >= 28"
          (click)="
            isImageBook()
              ? setImageZoom(imageZoom() + 0.25)
              : appearance.setFontSize(appearance.fontSize() + 1)
          "
        >
          <span class="material-symbols-rounded">add</span>
        </button>
        <div class="tb-menu-wrap">
          <button
            type="button"
            class="tb-action-btn"
            aria-label="More book options"
            title="Bookmark, Notebook & Share"
            (click)="menuOpen.set(!menuOpen())"
          >
            <span class="material-symbols-rounded">more_vert</span>
          </button>
          @if (menuOpen()) {
            <div class="tb-overflow-menu" (click)="menuOpen.set(false)">
              <button
                type="button"
                class="tb-menu-item"
                (click)="toggleChapterBookmark()"
              >
                <span
                  class="material-symbols-rounded"
                  [class.filled]="isChapterBookmarked()"
                  [class.accent-icon]="isChapterBookmarked()"
                >
                  bookmark
                </span>
                {{ isChapterBookmarked() ? 'Remove Bookmark' : 'Bookmark Chapter' }}
              </button>
              <button
                type="button"
                class="tb-menu-item"
                (click)="showHighlights.set(true)"
              >
                <span class="material-symbols-rounded">border_color</span>
                Notebook
              </button>
              <button
                type="button"
                class="tb-menu-item"
                (click)="shareLocation()"
              >
                <span class="material-symbols-rounded">share</span>
                Share Book
              </button>
            </div>
          }
        </div>
      </div>
    </ng-template>

    <div
      class="book-reader-page"
      [attr.data-paper]="appearance.paperTheme()"
      [class.immersive]="immersive()"
      [class.spread-mode]="isPaginated()"
    >
      @if (!immersive() && screen.isCompact()) {
        <header class="reader-bar">
          <div class="bar-inner">
            <div class="bar-left">
              @if (!isDesktop()) {
                <button
                  type="button"
                  class="toc-btn"
                  title="Toggle book navigator"
                  aria-label="Toggle book navigator"
                  [attr.aria-expanded]="showNavigatorDrawer()"
                  (click)="showNavigatorDrawer.set(!showNavigatorDrawer())"
                >
                  <span class="material-symbols-rounded">toc</span>
                  <span class="book-name">{{ toc()?.title || 'Book Reader' }}</span>
                </button>
              } @else {
                <span class="toc-btn book-title-label">
                  <span class="material-symbols-rounded">menu_book</span>
                  <span class="book-name">{{ toc()?.title || 'Book Reader' }}</span>
                </span>
              }

              @if (toc(); as t) {
                <div class="chapter-nav-group">
                  <button
                    type="button"
                    class="nav-step-btn"
                    aria-label="Previous chapter"
                    title="Previous chapter"
                    [disabled]="displayChapterIndex() <= 1"
                    (click)="prevChapter()"
                  >
                    <span class="material-symbols-rounded">chevron_left</span>
                  </button>
                  <button
                    type="button"
                    class="ch-pill-btn"
                    (click)="isDesktop() ? null : showNavigatorDrawer.set(!showNavigatorDrawer())"
                  >
                    <span>Ch. {{ displayChapterIndex() }} / {{ t.chapters.length || 1 }}</span>
                  </button>
                  <button
                    type="button"
                    class="nav-step-btn"
                    aria-label="Next chapter"
                    title="Next chapter"
                    [disabled]="displayChapterIndex() >= (t.chapters.length || 1)"
                    (click)="nextChapter()"
                  >
                    <span class="material-symbols-rounded">chevron_right</span>
                  </button>
                </div>
              }

              @if (!screen.isCompact() && !loading() && !error()) {
                <span class="bar-meta">
                  @if (displayChapterTitle()) {
                    {{ displayChapterTitle() }} ·
                  }
                  {{ displayReadingMinutes() }} min read
                </span>
              }
            </div>

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

      <div class="book-layout" [class.has-sidebar]="isDesktop() && !immersive() && !!toc()">
        @if (isDesktop() && !immersive() && toc(); as t) {
          <div
            class="nav-shell"
            [class.pinned]="navPinned()"
            (mouseenter)="navHovered.set(true)"
            (mouseleave)="navHovered.set(false)"
          >
            @if (!navOpen()) {
              <div class="collapsed-rail">
                <button
                  type="button"
                  class="rail-toggle-btn"
                  title="Expand & pin book chapters"
                  aria-label="Expand & pin book chapters"
                  (click)="toggleNavPin()"
                >
                  <span class="material-symbols-rounded">left_panel_open</span>
                </button>
                <span class="rail-badge" [title]="t.title + ' · Ch. ' + displayChapterIndex()">
                  <span class="material-symbols-rounded rail-ic">menu_book</span>
                  <span class="rail-ch">{{ displayChapterIndex() }}</span>
                </span>
              </div>
            }

            <aside
              class="book-sidebar"
              [class.floating]="!navPinned() && navHovered()"
              [class.hidden]="!navOpen()"
              aria-label="Book chapters"
            >
              <div class="sidebar-header">
                <div class="sidebar-header-top">
                  <h2 class="sidebar-title font-display">{{ t.title }}</h2>
                  <button
                    type="button"
                    class="pin-btn"
                    [class.active]="navPinned()"
                    [title]="navPinned() ? 'Collapse chapters (hover to expand)' : 'Keep chapters expanded'"
                    [attr.aria-label]="navPinned() ? 'Collapse chapters' : 'Keep chapters expanded'"
                    (click)="toggleNavPin()"
                  >
                    <span class="material-symbols-rounded">
                      {{ navPinned() ? 'left_panel_close' : 'keep' }}
                    </span>
                  </button>
                </div>
                @if (t.author) {
                  <p class="sidebar-author">{{ t.author }}</p>
                }
                <input
                  type="search"
                  class="sidebar-filter"
                  [ngModel]="sidebarFilter()"
                  (ngModelChange)="sidebarFilter.set($event)"
                  placeholder="Filter chapters..."
                  aria-label="Filter chapters"
                />
              </div>

              <nav class="sidebar-list">
                @for (ch of filteredSidebarChapters(); track ch.chapterIndex) {
                  <button
                    type="button"
                    class="sidebar-item"
                    [class.active]="ch.chapterIndex === displayChapterIndex()"
                    (click)="selectChapter(ch.chapterIndex)"
                  >
                    <span class="sidebar-idx">{{ ch.chapterIndex }}</span>
                    <span class="sidebar-ch-title">{{ ch.title || ('Chapter ' + ch.chapterIndex) }}</span>
                  </button>
                }
              </nav>
            </aside>
          </div>
        }

        @if (!isDesktop() && showNavigatorDrawer() && !immersive() && toc(); as t) {
          <div
            class="nav-drawer-backdrop"
            (click)="showNavigatorDrawer.set(false)"
          >
            <div
              class="nav-drawer-panel"
              role="dialog"
              aria-label="Book navigator"
              (click)="$event.stopPropagation()"
            >
              <div class="nav-drawer-top">
                <span class="nav-drawer-title">Book Navigator</span>
                <button
                  type="button"
                  class="icon-btn"
                  aria-label="Close book navigator"
                  (click)="showNavigatorDrawer.set(false)"
                >
                  <span class="material-symbols-rounded">close</span>
                </button>
              </div>
              <aside class="book-sidebar in-drawer" aria-label="Book chapters">
                <div class="sidebar-header">
                  <h2 class="sidebar-title font-display">{{ t.title }}</h2>
                  @if (t.author) {
                    <p class="sidebar-author">{{ t.author }}</p>
                  }
                  <input
                    type="search"
                    class="sidebar-filter"
                    [ngModel]="sidebarFilter()"
                    (ngModelChange)="sidebarFilter.set($event)"
                    placeholder="Filter chapters..."
                    aria-label="Filter chapters"
                  />
                </div>

                <nav class="sidebar-list">
                  @for (ch of filteredSidebarChapters(); track ch.chapterIndex) {
                    <button
                      type="button"
                      class="sidebar-item"
                      [class.active]="ch.chapterIndex === displayChapterIndex()"
                      (click)="selectChapterFromDrawer(ch.chapterIndex)"
                    >
                      <span class="sidebar-idx">{{ ch.chapterIndex }}</span>
                      <span class="sidebar-ch-title">{{ ch.title || ('Chapter ' + ch.chapterIndex) }}</span>
                    </button>
                  }
                </nav>
              </aside>
            </div>
          </div>
        }

        <div
          class="reader-content"
          [attr.data-margin]="appearance.bookMargin()"
          [class.two-col]="appearance.bookColumns() === 2"
        >
          @if (loading()) {
            <p class="status-msg">Loading chapter...</p>
          } @else if (error()) {
            <p class="status-msg">{{ error() }}</p>
          } @else if (isImageBook() && isPaginated()) {
            @if (activeImageSpread(); as spread) {
              <div class="image-spread-stage">
                @if (imageSpreadIndex() > 0) {
                  <button
                    type="button"
                    class="image-edge-btn prev"
                    aria-label="Previous page"
                    (click)="goToImageSpread(imageSpreadIndex() - 1)"
                  >
                    <span class="material-symbols-rounded">chevron_left</span>
                  </button>
                }
                <div
                  class="image-spread-deck"
                  [class.two-up]="imageCols() === 2"
                  [class.zoomed]="imageZoom() > 1"
                  [style.--img-zoom]="imageZoom()"
                >
                  @for (p of spread.pages; track p.fileName) {
                    @let st = imageStatusMap()[p.fileName] ?? 'loading';
                    <div
                      class="image-spread-frame"
                      (dblclick)="toggleImageZoom()"
                    >
                      @if (st === 'loading') {
                        <div class="img-skeleton" aria-hidden="true"></div>
                      }
                      @if (st === 'error') {
                        <div class="img-error-card">
                          <span class="material-symbols-rounded">broken_image</span>
                          <span>Page {{ p.pageNumber ?? '' }} unavailable</span>
                          <button
                            type="button"
                            class="pill-chip"
                            (click)="retryPageImage(p.fileName)"
                          >
                            Retry
                          </button>
                        </div>
                      } @else {
                        <img
                          class="image-spread-img"
                          [class.ready]="st === 'loaded'"
                          [src]="pageImageUrl(p.fileName)"
                          (load)="onPageImageLoad(p.fileName)"
                          (error)="onPageImageError($event, p.fileName)"
                          [alt]="(toc()?.title || 'Book') + ' page ' + (p.pageNumber ?? '')"
                          loading="eager"
                        />
                      }
                      @if (p.pageNumber !== undefined) {
                        <span class="img-page-badge">p. {{ p.pageNumber }}</span>
                      }
                    </div>
                  }
                </div>
                @if (imageSpreadIndex() < imageSpreads().length - 1) {
                  <button
                    type="button"
                    class="image-edge-btn next"
                    aria-label="Next page"
                    (click)="goToImageSpread(imageSpreadIndex() + 1)"
                  >
                    <span class="material-symbols-rounded">chevron_right</span>
                  </button>
                }
              </div>
            }
            <app-reader-spread-footer
              [label]="spreadFooterLabel()"
              [page]="imageSpreadIndex() + 1"
              [totalPages]="imageSpreads().length || 1"
              [hasPrevChapter]="false"
              [hasNextChapter]="false"
              (prevPage)="goToImageSpread(imageSpreadIndex() - 1)"
              (nextPage)="goToImageSpread(imageSpreadIndex() + 1)"
            />
          } @else if (isPaginated()) {
            <div class="spread-viewport" #spreadViewport>
              <div
                class="spread-track"
                [class.full-book]="fullBookChapters().length > 0"
                [attr.data-cols]="effectiveCols()"
                [style.font-family]="appearance.activeFont().cssFamily"
                [style.font-size.px]="appearance.fontSize()"
                [style.line-height]="appearance.lineHeight()"
                [style.text-align]="appearance.bookAlign()"
                (dblclick)="lookupFromSelection()"
              >
                @if (fullBookChapters().length > 0) {
                  @for (ch of fullBookChapters(); track ch.chapterIndex) {
                    <section
                      class="spread-chapter"
                      [attr.data-spread-ch]="ch.chapterIndex"
                    >
                      <header class="chapter-hero">
                        <span class="hero-eyebrow">
                          {{ toc()?.title }} · Chapter {{ ch.chapterIndex }}
                        </span>
                        @if (ch.title) {
                          <h1 class="hero-title font-display">{{ ch.title }}</h1>
                        }
                        <div class="hero-meta">
                          @if (toc()?.author) {
                            <span>{{ toc()!.author }}</span>
                            <span>·</span>
                          }
                          <span>{{ ch.minutes }} min read</span>
                        </div>
                      </header>

                      @for (item of ch.parsedLines; track $index) {
                        @if (!item.hidden) {
                          @let line = item.line;
                          @let hl = highlightColor($index, ch.chapterIndex);
                          @let note = noteFor($index, ch.chapterIndex);
                          @if (line.isHeading) {
                            <h2
                              [id]="'spread-line-' + ch.chapterIndex + '-' + $index"
                              class="chapter-heading"
                              [class.sub-heading]="(line.headingLevel ?? 1) > 1"
                            >
                              {{ line.text }}
                            </h2>
                          } @else {
                            <div
                              [id]="'spread-line-' + ch.chapterIndex + '-' + $index"
                              class="chapter-para"
                              [class.is-quote]="isQuoteLine(line)"
                              [class.selected]="
                                chapterIndex() === ch.chapterIndex &&
                                selectedIndex() === $index
                              "
                              [style.background-color]="hl ? hl + '55' : null"
                              (click)="toggleSelectLine($index, ch.chapterIndex)"
                            >
                              <p
                                class="para-text"
                                [attr.data-hl-scope]="bookScopeKey(ch.chapterIndex)"
                                [attr.data-hl-line]="$index"
                                (mouseup)="onTextSelectionChange()"
                                (touchend)="onTextSelectionChange()"
                              >
                                @for (tok of tokensWithHighlights(ch.chapterIndex, $index, item.tokens); track $index) {
                                  @if (tok.ref) {
                                    <button
                                      type="button"
                                      class="scripture-link"
                                      [class.inline-hl]="!!tok.highlightColor"
                                      [style.background-color]="tok.highlightColor ?? null"
                                      (click)="$event.stopPropagation(); activeScriptureRef.set(tok.ref!)"
                                    >
                                      {{ tok.text }}
                                    </button>
                                  } @else if (tok.highlightColor) {
                                    <mark class="inline-hl" [style.background-color]="tok.highlightColor">{{ tok.text }}</mark>
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
                      }
                    </section>
                  }
                } @else {
                  <ng-container [ngTemplateOutlet]="bookHeroTpl" />
                  <ng-container [ngTemplateOutlet]="bookLinesTpl" />
                }
              </div>
            </div>
            <app-reader-spread-footer
              [label]="spreadFooterLabel()"
              [page]="spreadPage()"
              [totalPages]="spreadTotalPages()"
              [hasPrevChapter]="fullBookChapters().length === 0 && chapterIndex() > 1"
              [hasNextChapter]="
                fullBookChapters().length === 0 &&
                chapterIndex() < (toc()?.chapters?.length || 1)
              "
              (prevPage)="goToSpreadPage(spreadPage() - 1)"
              (nextPage)="goToSpreadPage(spreadPage() + 1)"
            />
          } @else {
            @if (hasPrevBookChapter()) {
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

            @for (extra of prependedChapters(); track extra.chapterIndex) {
              <ng-container
                [ngTemplateOutlet]="extraBookChapterTpl"
                [ngTemplateOutletContext]="{ $implicit: extra, isPrepended: true }"
              />
            }

            <section class="chapter-section" [attr.data-book-ch]="chapterIndex()">
              <ng-container [ngTemplateOutlet]="bookHeroTpl" />

              <article
                class="chapter-body"
                [attr.data-cols]="effectiveCols()"
                [style.font-family]="appearance.activeFont().cssFamily"
                [style.font-size.px]="appearance.fontSize()"
                [style.line-height]="appearance.lineHeight()"
                [style.text-align]="appearance.bookAlign()"
                (dblclick)="lookupFromSelection()"
              >
                <ng-container [ngTemplateOutlet]="bookLinesTpl" />
              </article>
            </section>

            @for (extra of appendedChapters(); track extra.chapterIndex) {
              <ng-container
                [ngTemplateOutlet]="extraBookChapterTpl"
                [ngTemplateOutletContext]="{ $implicit: extra, isPrepended: false }"
              />
            }

            <ng-template #extraBookChapterTpl let-extra let-isPrepended="isPrepended">
              <section
                class="appended-chapter"
                [class.prepended-chapter]="isPrepended"
                [attr.data-book-ch]="extra.chapterIndex"
              >
                <header class="chapter-hero appended-hero">
                  <span class="hero-eyebrow">
                    {{ toc()?.title }} · Chapter {{ extra.chapterIndex }}
                  </span>
                  @if (extra.title) {
                    <h2 class="hero-title font-display">{{ extra.title }}</h2>
                  }
                  <div class="hero-meta">
                    <span>{{ extra.minutes }} min read</span>
                  </div>
                </header>

                <article
                  class="chapter-body"
                  [attr.data-cols]="effectiveCols()"
                  [style.font-family]="appearance.activeFont().cssFamily"
                  [style.font-size.px]="appearance.fontSize()"
                  [style.line-height]="appearance.lineHeight()"
                  [style.text-align]="appearance.bookAlign()"
                  (dblclick)="lookupFromSelection()"
                >
                  @for (item of extra.parsedLines; track $index) {
                    @let line = item.line;
                    @if (line.isHeading) {
                      <h3
                        class="chapter-heading"
                        [class.sub-heading]="(line.headingLevel ?? 1) > 1"
                      >
                        {{ line.text }}
                      </h3>
                    } @else {
                      <div class="chapter-para" [class.is-quote]="isQuoteLine(line)">
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
                      </div>
                    }
                  }
                </article>
              </section>
            </ng-template>

            <div
              class="scroll-sentinel"
              appInfiniteScrollTrigger
              [disabled]="loadingMore() || !hasNextBookChapter()"
              (triggered)="appendNextChapter()"
            >
              @if (loadingMore()) {
                <span>Loading next chapter...</span>
              }
            </div>
          }

          <ng-template #bookHeroTpl>
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
          </ng-template>

          <ng-template #bookLinesTpl>
            @for (item of parsedLines(); track $index) {
              @if (!item.hidden) {
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
                } @else if (isImageLine(line)) {
                  <div [id]="'book-line-' + $index" class="book-page-img-wrap">
                    <img
                      class="book-page-img"
                      [src]="pageImageUrl(line.text)"
                      (error)="onPageImageError($event, line.text)"
                      [alt]="(toc()?.title || 'Book') + ' page ' + (line.page ?? '')"
                      loading="lazy"
                    />
                  </div>
                } @else {
                  <div
                    [id]="'book-line-' + $index"
                    class="chapter-para"
                    [class.is-quote]="isQuoteLine(line)"
                    [class.selected]="selectedIndex() === $index"
                    [style.background-color]="hl ? hl + '55' : null"
                    (click)="toggleSelectLine($index)"
                  >
                    <p
                      class="para-text"
                      [attr.data-hl-scope]="bookScopeKey(chapterIndex())"
                      [attr.data-hl-line]="$index"
                      (mouseup)="onTextSelectionChange()"
                      (touchend)="onTextSelectionChange()"
                    >
                      @for (tok of tokensWithHighlights(chapterIndex(), $index, item.tokens); track $index) {
                        @if (tok.ref) {
                          <button
                            type="button"
                            class="scripture-link"
                            [class.inline-hl]="!!tok.highlightColor"
                            [style.background-color]="tok.highlightColor ?? null"
                            (click)="$event.stopPropagation(); activeScriptureRef.set(tok.ref!)"
                          >
                            {{ tok.text }}
                          </button>
                        } @else if (tok.highlightColor) {
                          <mark class="inline-hl" [style.background-color]="tok.highlightColor">{{ tok.text }}</mark>
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
            }
          </ng-template>
        </div>
      </div>

      @if (activeToolbarAnchor(); as selAnchor) {
        <app-text-selection-popover
          [anchor]="selAnchor"
          [activeColor]="activeToolbarColor()"
          [showNote]="activeTargetLineIndex() !== null"
          [hasNote]="activeTargetHasNote()"
          [showDefine]="true"
          [showCopy]="true"
          [showShare]="true"
          [showClose]="true"
          (highlight)="onInlineHighlight($event)"
          (clear)="onInlineClearHighlight()"
          (openNote)="openNoteEditorForActive()"
          (define)="onInlineDefine()"
          (copy)="onInlineCopy()"
          (share)="onInlineShare()"
          (closed)="clearInlineSelection()"
        />
      }

      @if (!isDesktop() && !isPaginated() && !immersive() && !loading() && toc()) {
        <app-book-reader-nav
          [chapterIndex]="displayChapterIndex()"
          [totalChapters]="toc()!.chapters.length || 1"
          [chapterTitle]="displayChapterTitle()"
          [readingMinutes]="displayReadingMinutes()"
          (previous)="prevChapter()"
          (next)="nextChapter()"
          (openToc)="showNavigatorDrawer.set(!showNavigatorDrawer())"
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
        width: 100%;
        padding-inline: clamp(16px, 3vw, 32px);
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
      }

      .bar-left {
        display: flex;
        align-items: center;
        gap: 10px;
        min-width: 0;
        flex: 1;
      }

      .toc-btn {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        min-width: 0;
        font-weight: 700;
        font-size: 15px;
      }

      .book-title-label {
        cursor: default;
      }

      .chapter-nav-group {
        display: inline-flex;
        align-items: center;
        flex-shrink: 0;
        border: 1px solid var(--reader-border, var(--surface-border));
        border-radius: var(--radius-pill);
        background-color: var(--reader-surface, var(--surface));
        overflow: hidden;
      }

      .nav-step-btn {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 30px;
        height: 30px;
        color: var(--reader-fg, var(--on-surface));
      }

      .nav-step-btn:disabled {
        opacity: 0.35;
        cursor: default;
      }

      .nav-step-btn .material-symbols-rounded {
        font-size: 18px;
      }

      .ch-pill-btn {
        display: inline-flex;
        align-items: center;
        height: 30px;
        padding: 0 8px;
        font-weight: 700;
        font-size: 13px;
        white-space: nowrap;
      }

      .bar-meta {
        font-size: 12px;
        font-weight: 500;
        color: var(--reader-muted, var(--on-surface-muted));
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .tb-book-pill {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        height: 34px;
        max-width: 100%;
        min-width: 0;
        padding: 0 4px 0 12px;
        border-radius: var(--radius-pill);
        background-color: var(--surface-variant);
        border: 1px solid var(--surface-border);
      }

      .tb-book-trigger {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        min-width: 0;
        font-size: 13px;
        font-weight: 700;
        color: var(--on-surface);
      }

      .tb-book-ic {
        font-size: 17px;
        color: var(--on-surface-muted);
        flex-shrink: 0;
      }

      .tb-book-title {
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        min-width: 0;
      }

      .tb-pill-sep {
        width: 1px;
        height: 16px;
        background-color: var(--surface-border);
        flex-shrink: 0;
      }

      .tb-ch-stepper {
        display: inline-flex;
        align-items: center;
        flex-shrink: 0;
      }

      .tb-step-btn {
        width: 26px;
        height: 26px;
        border-radius: var(--radius-pill);
        display: grid;
        place-items: center;
        color: var(--on-surface);
      }

      .tb-step-btn:hover:not(:disabled) {
        background-color: var(--accent-soft);
        color: var(--accent);
      }

      .tb-step-btn:disabled {
        opacity: 0.35;
        cursor: default;
      }

      .tb-step-btn .material-symbols-rounded {
        font-size: 18px;
      }

      .tb-ch-label {
        padding: 0 6px;
        font-size: 12px;
        font-weight: 700;
        color: var(--on-surface);
        white-space: nowrap;
        font-variant-numeric: tabular-nums;
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

      .tb-font-step .material-symbols-rounded {
        font-size: 16px;
      }

      .tb-action-btn .material-symbols-rounded {
        font-size: 18px;
      }

      .tb-aa-btn {
        font-family: Georgia, serif;
        font-weight: 700;
        font-size: 14px;
      }

      .tb-menu-wrap {
        position: relative;
      }

      .tb-overflow-menu {
        position: absolute;
        right: 0;
        top: calc(100% + 6px);
        min-width: 196px;
        padding: 6px;
        border-radius: var(--radius-md);
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        box-shadow: 0 10px 28px rgba(0, 0, 0, 0.18);
        display: flex;
        flex-direction: column;
        z-index: 60;
      }

      .tb-menu-item {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 10px 12px;
        border-radius: var(--radius-sm);
        font-size: 14px;
        text-align: left;
        color: var(--on-surface);
      }

      .tb-menu-item:hover {
        background-color: var(--surface-variant);
      }

      .book-layout {
        display: flex;
        align-items: flex-start;
        width: 100%;
      }

      .nav-shell {
        position: sticky;
        top: var(--shell-top-offset);
        align-self: flex-start;
        flex-shrink: 0;
        width: 44px;
        height: calc(100dvh - var(--shell-top-offset));
        z-index: 25;
      }

      .nav-shell.pinned {
        width: 280px;
      }

      .book-reader-page.spread-mode .nav-shell {
        position: relative;
        top: auto;
        height: 100%;
      }

      .collapsed-rail {
        width: 44px;
        height: 100%;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 10px;
        padding: 10px 4px;
        border-right: 1px solid var(--reader-border, var(--surface-border));
        background-color: color-mix(in srgb, var(--reader-bg, var(--bg)) 96%, var(--on-surface) 4%);
      }

      .rail-toggle-btn,
      .pin-btn {
        width: 30px;
        height: 30px;
        border-radius: var(--radius-sm);
        display: grid;
        place-items: center;
        color: var(--on-surface-muted);
        flex-shrink: 0;
      }

      .rail-toggle-btn:hover,
      .pin-btn:hover {
        background-color: var(--surface-variant);
        color: var(--on-surface);
      }

      .pin-btn.active {
        color: var(--accent);
        background-color: var(--accent-soft);
      }

      .rail-toggle-btn .material-symbols-rounded,
      .pin-btn .material-symbols-rounded {
        font-size: 18px;
      }

      .rail-badge {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 2px;
        padding: 6px 4px;
        border-radius: var(--radius-sm);
        background-color: var(--accent-soft);
        color: var(--accent);
        width: 34px;
      }

      .rail-ic {
        font-size: 16px;
      }

      .rail-ch {
        font-size: 11px;
        font-weight: 700;
        font-variant-numeric: tabular-nums;
      }

      .book-sidebar {
        width: 280px;
        height: 100%;
        display: flex;
        flex-direction: column;
        border-right: 1px solid var(--reader-border, var(--surface-border));
        background-color: color-mix(in srgb, var(--reader-bg, var(--bg)) 96%, var(--on-surface) 4%);
      }

      .book-sidebar.floating {
        position: absolute;
        top: 0;
        left: 0;
        z-index: 30;
        background-color: var(--reader-bg, var(--surface));
        box-shadow: 6px 0 24px rgba(0, 0, 0, 0.18);
      }

      .book-sidebar.hidden {
        display: none;
      }

      .sidebar-header-top {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 8px;
      }

      .book-sidebar.in-drawer {
        position: static;
        top: auto;
        width: 100%;
        height: auto;
        flex: 1;
        min-height: 0;
        border-right: none;
        background-color: transparent;
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

      .sidebar-header {
        padding: 16px 14px 12px;
        border-bottom: 1px solid var(--reader-border, var(--surface-border));
      }

      .sidebar-title {
        margin: 0 0 2px;
        font-size: 15px;
        font-weight: 700;
        line-height: 1.3;
      }

      .sidebar-author {
        margin: 0 0 10px;
        font-size: 12px;
        color: var(--reader-muted, var(--on-surface-muted));
      }

      .sidebar-filter {
        width: 100%;
        padding: 7px 10px;
        border-radius: var(--radius-sm);
        border: 1px solid var(--reader-border, var(--surface-border));
        background-color: var(--reader-bg, var(--bg));
        color: var(--reader-fg, var(--on-surface));
        font-size: 13px;
      }

      .sidebar-list {
        flex: 1;
        overflow-y: auto;
        padding: 8px;
        display: flex;
        flex-direction: column;
        gap: 2px;
      }

      .sidebar-item {
        display: flex;
        align-items: center;
        gap: 10px;
        width: 100%;
        padding: 8px 10px;
        border-radius: var(--radius-sm);
        text-align: left;
        font-size: 13px;
        color: var(--reader-fg, var(--on-surface));
      }

      .sidebar-item:hover {
        background-color: color-mix(in srgb, var(--accent) 8%, transparent);
      }

      .sidebar-item.active {
        background-color: var(--accent-soft);
        color: var(--accent);
        font-weight: 700;
      }

      .sidebar-idx {
        min-width: 24px;
        font-size: 12px;
        font-weight: 700;
        opacity: 0.7;
        font-variant-numeric: tabular-nums;
      }

      .sidebar-ch-title {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
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

      .appended-chapter {
        margin-top: 40px;
      }

      .prepended-chapter {
        margin-top: 0;
        margin-bottom: 40px;
      }

      .appended-hero {
        padding-top: 12px;
      }

      .scroll-sentinel {
        display: flex;
        justify-content: center;
        padding: 24px 0 8px;
        font-size: 13px;
        color: var(--reader-muted, var(--on-surface-muted));
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
        width: 100%;
        padding: 28px clamp(16px, 3vw, 40px) 120px;
        transition: padding-inline 200ms ease;
      }

      .reader-content[data-margin='narrow'] {
        padding-inline: clamp(16px, 5vw, 72px);
      }

      .reader-content[data-margin='wide'] {
        padding-inline: clamp(12px, 1.5vw, 24px);
      }

      .book-reader-page.spread-mode {
        height: calc(100dvh - var(--shell-top-offset));
        min-height: 0;
        overflow: hidden;
        display: flex;
        flex-direction: column;
      }

      .book-reader-page.spread-mode.immersive {
        height: 100dvh;
      }

      .book-reader-page.spread-mode .reader-bar {
        position: static;
        top: auto;
        flex-shrink: 0;
      }

      .book-reader-page.spread-mode .book-layout {
        flex: 1;
        min-height: 0;
        align-items: stretch;
        overflow: hidden;
      }

      .book-reader-page.spread-mode .book-sidebar {
        position: static;
        height: 100%;
      }

      .book-reader-page.spread-mode .reader-content {
        flex: 1;
        min-width: 0;
        min-height: 0;
        display: flex;
        flex-direction: column;
        padding-top: 20px;
        padding-bottom: 0;
        overflow: hidden;
      }

      .image-spread-stage {
        position: relative;
        flex: 1;
        min-height: 0;
        display: flex;
        flex-direction: column;
      }

      .image-spread-deck {
        flex: 1;
        min-height: 0;
        display: grid;
        grid-template-columns: minmax(0, 1fr);
        gap: 20px;
        align-items: center;
        justify-items: center;
        padding: 4px 36px 12px;
        overflow: hidden;
      }

      .image-spread-deck.two-up {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      .image-spread-deck.zoomed {
        overflow: auto;
        align-items: start;
      }

      .image-spread-frame {
        position: relative;
        width: 100%;
        height: 100%;
        min-height: 0;
        display: flex;
        align-items: center;
        justify-content: center;
      }

      .image-spread-deck.zoomed .image-spread-frame {
        height: auto;
        min-height: 100%;
      }

      .image-spread-img {
        max-width: 100%;
        max-height: 100%;
        width: auto;
        height: auto;
        object-fit: contain;
        border-radius: var(--radius-sm);
        box-shadow: 0 4px 18px rgba(0, 0, 0, 0.12);
        opacity: 0;
        transition: opacity 140ms ease;
        cursor: zoom-in;
      }

      .image-spread-img.ready {
        opacity: 1;
      }

      .image-spread-deck.zoomed .image-spread-img {
        max-height: none;
        max-width: none;
        width: calc(100% * var(--img-zoom, 1));
        cursor: zoom-out;
      }

      .book-reader-page[data-paper='night'] .image-spread-img,
      .book-reader-page[data-paper='night'] .book-page-img {
        filter: invert(0.9) hue-rotate(180deg) contrast(0.95);
      }

      .book-reader-page[data-paper='sepia'] .image-spread-img,
      .book-reader-page[data-paper='sepia'] .book-page-img {
        filter: sepia(0.24) brightness(0.96);
      }

      .img-skeleton {
        position: absolute;
        width: min(420px, 80%);
        height: min(560px, 82%);
        border-radius: var(--radius-md);
        background: linear-gradient(
          90deg,
          var(--surface-variant) 25%,
          color-mix(in srgb, var(--surface-variant) 60%, var(--on-surface) 8%) 50%,
          var(--surface-variant) 75%
        );
        background-size: 200% 100%;
        animation: imgShimmer 1.3s infinite linear;
      }

      @keyframes imgShimmer {
        from { background-position: 200% 0; }
        to { background-position: -200% 0; }
      }

      .img-error-card {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 8px;
        padding: 24px;
        border-radius: var(--radius-md);
        border: 1px solid var(--surface-border);
        background-color: var(--surface-variant);
        color: var(--on-surface-muted);
        font-size: 13px;
      }

      .img-page-badge {
        position: absolute;
        bottom: 8px;
        right: 10px;
        padding: 2px 8px;
        border-radius: var(--radius-pill);
        background-color: color-mix(in srgb, var(--surface) 88%, transparent);
        border: 1px solid var(--surface-border);
        font-size: 11px;
        font-weight: 600;
        color: var(--on-surface-muted);
        pointer-events: none;
      }

      .image-edge-btn {
        position: absolute;
        top: 50%;
        transform: translateY(-50%);
        z-index: 12;
        width: 34px;
        height: 52px;
        border-radius: var(--radius-md);
        display: grid;
        place-items: center;
        color: var(--on-surface);
        background-color: color-mix(in srgb, var(--surface) 82%, transparent);
        border: 1px solid var(--surface-border);
        opacity: 0.45;
        transition: opacity 150ms ease, background-color 150ms ease;
      }

      .image-spread-stage:hover .image-edge-btn {
        opacity: 0.95;
      }

      .image-edge-btn:hover {
        background-color: var(--surface);
      }

      .image-edge-btn.prev {
        left: 0;
      }

      .image-edge-btn.next {
        right: 0;
      }

      .book-page-img-wrap {
        display: flex;
        justify-content: center;
        margin: 12px 0;
      }

      .book-page-img {
        max-width: min(720px, 100%);
        width: 100%;
        height: auto;
        border-radius: var(--radius-sm);
        box-shadow: 0 2px 12px rgba(0, 0, 0, 0.08);
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

      .spread-track.full-book {
        display: flex;
        flex-direction: row;
        gap: 44px;
        height: 100%;
        width: max-content;
        column-count: unset;
        column-rule: none;
      }

      .spread-chapter {
        flex: 0 0 auto;
        height: 100%;
        column-fill: auto;
        column-gap: 44px;
        column-rule: 1px solid var(--reader-border, var(--surface-border));
        box-sizing: border-box;
        overflow: hidden;
      }

      .spread-track .chapter-hero {
        margin-bottom: 18px;
        padding-bottom: 14px;
      }

      .spread-track .chapter-heading {
        break-after: avoid;
      }

      .chapter-body[data-cols='2'],
      .chapter-body[data-cols='3'] {
        display: block;
        column-count: 2;
        column-gap: 44px;
        column-rule: 1px solid var(--reader-border, var(--surface-border));
      }

      .chapter-body[data-cols='3'] {
        column-count: 3;
        column-gap: 36px;
      }

      .chapter-body[data-cols='2'] .chapter-para,
      .chapter-body[data-cols='2'] .chapter-heading,
      .chapter-body[data-cols='3'] .chapter-para,
      .chapter-body[data-cols='3'] .chapter-heading {
        break-inside: avoid;
        margin-bottom: 12px;
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
        outline-offset: -2px;
      }

      .inline-hl {
        color: #111827;
        border-radius: 3px;
        padding: 1px 0;
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
export class BookReaderComponent implements OnInit, AfterViewInit {
  private readonly headerSlot = inject(HeaderSlotService);
  private readonly destroyRef = inject(DestroyRef);

  @ViewChild('topbarCenter') topbarCenterRef?: TemplateRef<unknown>;
  @ViewChild('topbarRight') topbarRightRef?: TemplateRef<unknown>;
  readonly menuOpen = signal<boolean>(false);
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

  readonly spreadPage = signal<number>(1);
  readonly spreadTotalPages = signal<number>(1);
  readonly imageSpreadIndex = signal<number>(0);
  readonly imageZoom = signal<number>(1);
  readonly imageStatusMap = signal<Record<string, 'loading' | 'loaded' | 'error'>>({});
  readonly Math = Math;
  readonly fullBookChapters = signal<SpreadBookChapter[]>([]);
  private fullBookLoadedForId = '';
  private fullBookLoadingForId = '';
  private pendingLastSpreadPage = false;

  constructor() {
    this.destroyRef.onDestroy(() => {
      this.headerSlot.clear();
      this.spreadResizeObserver?.disconnect();
    });
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
      this.parsedLines();
      this.fullBookChapters();
      this.appearance.fontSize();
      this.appearance.lineHeight();
      this.appearance.fontId();
      this.appearance.bookMargin();
      this.appearance.bookAlign();
      this.loading();
      this.immersive();
      if (paginated) {
        if (this.prependedChapters().length > 0) this.prependedChapters.set([]);
        if (this.appendedChapters().length > 0) this.appendedChapters.set([]);
        window.scrollTo({ top: 0, behavior: 'auto' });
        const toc = this.toc();
        const bookId = this.currentBookId();
        if (toc && bookId && this.fullBookLoadedForId !== bookId) {
          void this.loadFullBookForSpread(bookId, toc);
        }
        setTimeout(() => this.refreshSpreadMetrics(), 0);
      }
    });
    effect(() => {
      if (!this.isImageBook() || !this.isPaginated()) return;
      const spreads = this.imageSpreads();
      const idx = this.imageSpreadIndex();
      for (const offset of [1, 2]) {
        const upcoming = spreads[idx + offset];
        if (!upcoming) continue;
        for (const p of upcoming.pages) {
          const url = this.pageImageUrl(p.fileName);
          if (url) {
            const img = new Image();
            img.src = url;
          }
        }
      }
    });
  }

  ngAfterViewInit(): void {
    this.viewInitialized.set(true);
  }
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly booksService = inject(BooksService);
  private readonly highlightsService = inject(BookHighlightsService);
  private readonly scriptureParser = inject(ScriptureRefParserService);
  readonly screen = inject(ScreenClassService);
  readonly appearance = inject(ReaderAppearanceService);
  readonly isDesktop = this.screen.isDesktop;

  readonly toc = signal<BookToc | null>(null);
  readonly lines = signal<BookLine[]>([]);
  readonly chapterIndex = signal<number>(1);
  readonly loading = signal<boolean>(true);
  readonly error = signal<string | null>(null);
  readonly selectedIndex = signal<number | null>(null);
  readonly immersive = signal<boolean>(false);
  readonly sidebarFilter = signal<string>('');
  readonly navPinned = signal<boolean>(this.readNavPinned());
  readonly navHovered = signal<boolean>(false);
  readonly navOpen = computed(() => this.navPinned() || this.navHovered());

  toggleNavPin(): void {
    const next = !this.navPinned();
    this.navPinned.set(next);
    try {
      localStorage.setItem('book_nav_pinned', next ? '1' : '0');
    } catch {
      // ignore
    }
  }

  private readNavPinned(): boolean {
    try {
      return localStorage.getItem('book_nav_pinned') === '1';
    } catch {
      return false;
    }
  }

  readonly prependedChapters = signal<ExtraBookChapter[]>([]);
  readonly appendedChapters = signal<ExtraBookChapter[]>([]);
  readonly loadingPrev = signal<boolean>(false);
  readonly loadingMore = signal<boolean>(false);
  readonly visibleChapterIndex = signal<number | null>(null);
  private hasScrolledDown = false;

  readonly showToc = signal<boolean>(false);
  readonly showNavigatorDrawer = signal<boolean>(false);
  readonly showAppearance = signal<boolean>(false);
  readonly showHighlights = signal<boolean>(false);
  readonly showSearch = signal<boolean>(false);
  readonly showNoteModal = signal<boolean>(false);
  readonly noteDraft = signal<string>('');
  readonly activeScriptureRef = signal<ParsedScriptureRef | null>(null);
  readonly lookupWord = signal<string | null>(null);
  readonly selectionAnchor = signal<TextSelectionAnchor | null>(null);
  readonly lineToolbarAnchor = signal<InlineToolbarAnchor | null>(null);

  readonly activeToolbarAnchor = computed<InlineToolbarAnchor | null>(
    () => this.selectionAnchor() ?? this.lineToolbarAnchor(),
  );

  readonly activeTargetLineIndex = computed<number | null>(
    () => this.selectionAnchor()?.line ?? this.selectedIndex(),
  );

  readonly activeToolbarColor = computed<string | null>(() => {
    const selAnchor = this.selectionAnchor();
    if (selAnchor) {
      const ranges = this.highlightsService.rangesForLine(
        selAnchor.scopeKey,
        selAnchor.line,
      );
      const match = ranges.find(
        (r) => r.end > selAnchor.start && r.start < selAnchor.end,
      );
      return match?.color ?? null;
    }
    const idx = this.selectedIndex();
    return idx !== null ? this.highlightColor(idx) : null;
  });

  readonly activeTargetHasNote = computed<boolean>(() => {
    const idx = this.activeTargetLineIndex();
    return idx !== null ? Boolean(this.noteFor(idx)) : false;
  });

  bookScopeKey(chIdx: number): string {
    return `book:${this.currentBookId()}:${chIdx}`;
  }

  tokensWithHighlights(
    chIdx: number,
    lineIdx: number,
    baseTokens: ScriptureSpanToken[],
  ): HighlightedSpanToken[] {
    const scope = this.bookScopeKey(chIdx);
    const ranges = this.highlightsService.rangesForLine(scope, lineIdx);
    return applyHighlightRangesToTokens(baseTokens, ranges);
  }

  onTextSelectionChange(): void {
    setTimeout(() => {
      const extracted = extractLineTextSelection();
      this.selectionAnchor.set(extracted);
      if (extracted) {
        this.selectedIndex.set(null);
        this.lineToolbarAnchor.set(null);
      }
    }, 10);
  }

  private refreshLineToolbarAnchor(): void {
    const idx = this.selectedIndex();
    if (idx === null) {
      this.lineToolbarAnchor.set(null);
      return;
    }
    const ch = this.chapterIndex();
    const el =
      document.getElementById(`spread-line-${ch}-${idx}`) ??
      document.getElementById(`book-line-${idx}`);
    this.lineToolbarAnchor.set(
      computeElementToolbarAnchor(el) ?? {
        top: 120,
        left: typeof window !== 'undefined' ? window.innerWidth / 2 : 240,
        placement: 'below',
      },
    );
  }

  onInlineHighlight(color: string): void {
    if (this.selectionAnchor()) {
      this.highlightSelection(color);
      return;
    }
    const idx = this.selectedIndex();
    const sel = this.selectedLine();
    if (idx !== null && sel) {
      this.setHighlight(idx, sel, color);
    }
  }

  onInlineClearHighlight(): void {
    if (this.selectionAnchor()) {
      this.clearSelectionHighlight();
      return;
    }
    const idx = this.selectedIndex();
    const sel = this.selectedLine();
    if (idx !== null && sel) {
      this.setHighlight(idx, sel, null);
    }
  }

  openNoteEditorForActive(): void {
    const selAnchor = this.selectionAnchor();
    if (selAnchor) {
      this.selectedIndex.set(selAnchor.line);
      window.getSelection()?.removeAllRanges();
      this.selectionAnchor.set(null);
      this.refreshLineToolbarAnchor();
    }
    this.openNoteEditor();
  }

  onInlineDefine(): void {
    if (this.selectionAnchor()) {
      this.defineSelection();
      return;
    }
    this.defineSelected();
  }

  onInlineCopy(): void {
    if (this.selectionAnchor()) {
      this.copySelection();
      return;
    }
    this.copySelected();
  }

  onInlineShare(): void {
    const idx = this.activeTargetLineIndex();
    this.shareLocation(idx ?? undefined);
    this.clearInlineSelection();
  }

  clearInlineSelection(): void {
    window.getSelection()?.removeAllRanges();
    this.selectionAnchor.set(null);
    this.selectedIndex.set(null);
    this.lineToolbarAnchor.set(null);
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
    window.getSelection()?.removeAllRanges();
    this.selectionAnchor.set(null);
  }

  readonly currentBookId = signal<string>('');
  readonly currentBookLang = signal<string | undefined>(undefined);

  readonly selectedLine = computed(() => {
    const idx = this.selectedIndex();
    return idx !== null ? (this.lines()[idx] ?? null) : null;
  });

  readonly parsedLines = computed<
    Array<{ line: BookLine; tokens: ScriptureSpanToken[]; hidden: boolean }>
  >(() => {
    const chTitle = this.currentChapterTitle();
    return this.lines().map((line, index) => ({
      line,
      tokens: line.isHeading ? [] : this.scriptureParser.parse(line.text),
      hidden:
        index === 0 &&
        Boolean(line.isHeading) &&
        this.isDuplicateChapterHeading(line.text, chTitle),
    }));
  });

  private isDuplicateChapterHeading(heading: string, chapterTitle: string): boolean {
    const normalize = (s: string) =>
      s
        .trim()
        .replace(/^chapter\s+\d+[:.\-\s]*/i, '')
        .replace(/^\d+[:.\-\s]+/, '')
        .trim()
        .toLowerCase();
    const h = normalize(heading);
    const t = normalize(chapterTitle);
    if (!h || !t) return false;
    return h === t || h.includes(t) || t.includes(h);
  }

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

  readonly displayChapterIndex = computed(
    () => this.visibleChapterIndex() ?? this.chapterIndex(),
  );

  readonly displayChapterTitle = computed(() => {
    const idx = this.displayChapterIndex();
    const ch = this.toc()?.chapters.find((c) => c.chapterIndex === idx);
    return ch?.title ?? '';
  });

  readonly displayReadingMinutes = computed(() => {
    const idx = this.visibleChapterIndex();
    if (idx !== null && idx !== this.chapterIndex()) {
      const extra =
        this.prependedChapters().find((c) => c.chapterIndex === idx) ??
        this.appendedChapters().find((c) => c.chapterIndex === idx);
      if (extra) return extra.minutes;
    }
    return this.readingMinutes();
  });

  readonly effectiveCols = computed(() =>
    this.appearance.effectiveColumns(this.screen.screenClass()),
  );

  readonly isPaginated = computed(
    () => this.effectiveCols() >= 2 || this.appearance.singleColPaginated(),
  );

  readonly isImageBook = computed(() => {
    const list = this.lines();
    return list.length > 0 && list.every((l) => this.isImageLine(l));
  });

  readonly imageCols = computed<1 | 2>(() =>
    this.effectiveCols() >= 2 ? 2 : 1,
  );

  readonly imageSpreads = computed<ImageSpread[]>(() => {
    if (!this.isImageBook()) return [];
    const cols = this.imageCols();
    const chapters =
      this.fullBookChapters().length > 0
        ? this.fullBookChapters().map((c) => ({
            chapterIndex: c.chapterIndex,
            title: c.title,
            lines: c.lines,
          }))
        : [
            {
              chapterIndex: this.chapterIndex(),
              title: this.currentChapterTitle(),
              lines: this.lines(),
            },
          ];
    const spreads: ImageSpread[] = [];
    for (const ch of chapters) {
      const imgs = ch.lines
        .filter((l) => this.isImageLine(l))
        .map((l) => ({ fileName: l.text.trim(), pageNumber: l.page }));
      for (let i = 0; i < imgs.length; i += cols) {
        spreads.push({
          chapterIndex: ch.chapterIndex,
          chapterTitle: ch.title,
          pages: imgs.slice(i, i + cols),
        });
      }
    }
    return spreads;
  });

  readonly activeImageSpread = computed(() => {
    const list = this.imageSpreads();
    if (list.length === 0) return null;
    const idx = Math.min(list.length - 1, Math.max(0, this.imageSpreadIndex()));
    return list[idx] ?? null;
  });

  goToImageSpread(nextIdx: number): void {
    const list = this.imageSpreads();
    if (list.length === 0) return;
    const clamped = Math.min(list.length - 1, Math.max(0, nextIdx));
    this.imageSpreadIndex.set(clamped);
    const ch = list[clamped].chapterIndex;
    if (ch > 0 && ch !== this.visibleChapterIndex()) {
      this.visibleChapterIndex.set(ch);
      this.chapterIndex.set(ch);
      const match = this.fullBookChapters().find((c) => c.chapterIndex === ch);
      if (match) this.lines.set(match.lines);
    }
  }

  isImageLine(line: BookLine): boolean {
    return (line.contentType ?? '').toLowerCase() === 'img';
  }

  pageImageUrl(fileName: string): string {
    return (
      this.booksService.pageImageUrls(
        this.currentBookId(),
        fileName,
        this.currentBookLang(),
      )[0] ?? ''
    );
  }

  onPageImageLoad(fileName: string): void {
    const clean = fileName.trim();
    if (this.imageStatusMap()[clean] === 'loaded') return;
    this.imageStatusMap.update((m) => ({ ...m, [clean]: 'loaded' }));
  }

  onPageImageError(event: Event, fileName: string): void {
    const img = event.target as HTMLImageElement | null;
    if (!img) return;
    const urls = this.booksService.pageImageUrls(
      this.currentBookId(),
      fileName,
      this.currentBookLang(),
    );
    const nextIdx = Number(img.dataset['fallbackIdx'] ?? '0') + 1;
    if (nextIdx < urls.length) {
      img.dataset['fallbackIdx'] = String(nextIdx);
      img.src = urls[nextIdx];
      return;
    }
    this.imageStatusMap.update((m) => ({ ...m, [fileName.trim()]: 'error' }));
  }

  retryPageImage(fileName: string): void {
    const clean = fileName.trim();
    this.imageStatusMap.update((m) => ({ ...m, [clean]: 'loading' }));
  }

  setImageZoom(next: number): void {
    const clamped = Math.min(2.5, Math.max(1, Number(next.toFixed(2))));
    this.imageZoom.set(clamped);
  }

  toggleImageZoom(): void {
    this.setImageZoom(this.imageZoom() > 1 ? 1 : 1.5);
  }

  readonly spreadFooterLabel = computed(() => {
    const ch = this.displayChapterIndex();
    const title = this.displayChapterTitle();
    return title ? `Ch. ${ch} · ${title}` : `Chapter ${ch}`;
  });

  goToSpreadPage(next: number): void {
    const vp = this.spreadViewportRef?.nativeElement;
    if (!vp) return;
    const total = this.spreadTotalPages();
    if (this.fullBookChapters().length > 0) {
      const clamped = Math.min(total, Math.max(1, next));
      this.spreadPage.set(clamped);
      scrollToSpreadPage(vp, clamped, 44, false);
      this.syncVisibleChapterFromSpread();
      return;
    }
    const totalChapters = this.toc()?.chapters.length || 1;
    if (next < 1) {
      if (this.chapterIndex() > 1) {
        this.pendingLastSpreadPage = true;
        void this.loadChapter(this.chapterIndex() - 1);
      }
      return;
    }
    if (next > total) {
      if (this.chapterIndex() < totalChapters) {
        this.pendingLastSpreadPage = false;
        void this.loadChapter(this.chapterIndex() + 1);
      }
      return;
    }
    this.spreadPage.set(next);
    scrollToSpreadPage(vp, next, 44, false);
  }

  private layoutFullBookSpreads(vp: HTMLElement): void {
    if (this.fullBookChapters().length === 0) return;
    const vw = vp.clientWidth;
    if (vw <= 0) return;
    const cols = this.effectiveCols();
    const gap = 44;
    const nodes = Array.from(
      vp.querySelectorAll<HTMLElement>('[data-spread-ch]'),
    );
    if (nodes.length === 0) return;
    for (const el of nodes) {
      el.style.width = `${vw}px`;
      el.style.columnCount = String(cols);
    }
    const pageCounts = nodes.map((el) => {
      const sw = el.scrollWidth;
      return Math.max(1, Math.ceil((sw - 4) / (vw + gap)));
    });
    nodes.forEach((el, idx) => {
      const chPages = pageCounts[idx];
      el.style.width = `${chPages * vw + (chPages - 1) * gap}px`;
      el.style.columnCount = String(chPages * cols);
    });
  }

  private refreshSpreadMetrics(): void {
    const vp = this.spreadViewportRef?.nativeElement;
    if (!vp) return;
    this.layoutFullBookSpreads(vp);
    const { totalPages } = computeSpreadMetrics(vp, 44);
    this.spreadTotalPages.set(totalPages);
    if (this.pendingLastSpreadPage) {
      this.pendingLastSpreadPage = false;
      this.spreadPage.set(totalPages);
      scrollToSpreadPage(vp, totalPages, 44, false);
      this.syncVisibleChapterFromSpread();
      return;
    }
    if (this.spreadPage() > totalPages) {
      this.spreadPage.set(totalPages);
      scrollToSpreadPage(vp, totalPages, 44, false);
    } else {
      scrollToSpreadPage(vp, this.spreadPage(), 44, false);
    }
    this.syncVisibleChapterFromSpread();
  }

  private syncVisibleChapterFromSpread(): void {
    if (this.fullBookChapters().length === 0) return;
    const vp = this.spreadViewportRef?.nativeElement;
    if (!vp) return;
    const nodes = vp.querySelectorAll<HTMLElement>('[data-spread-ch]');
    if (nodes.length === 0) return;
    const vpLeft = vp.getBoundingClientRect().left;
    let active = nodes[0];
    for (const el of Array.from(nodes)) {
      if (el.getBoundingClientRect().left <= vpLeft + 24) {
        active = el;
      } else {
        break;
      }
    }
    const ch = Number(active.dataset['spreadCh'] ?? 0);
    if (ch > 0 && ch !== this.visibleChapterIndex()) {
      this.visibleChapterIndex.set(ch);
      this.chapterIndex.set(ch);
      const match = this.fullBookChapters().find((c) => c.chapterIndex === ch);
      if (match) {
        this.lines.set(match.lines);
      }
    }
  }

  private scrollToSpreadChapter(ch: number, line?: number): void {
    if (this.isImageBook()) {
      const idx = this.imageSpreads().findIndex((s) => s.chapterIndex === ch);
      if (idx >= 0) {
        this.goToImageSpread(idx);
        void this.router.navigate(['/books', this.currentBookId()], {
          queryParams: { chapter: ch },
          replaceUrl: true,
        });
      }
      return;
    }
    const vp = this.spreadViewportRef?.nativeElement;
    if (!vp) return;
    const targetEl =
      (line !== undefined
        ? document.getElementById(`spread-line-${ch}-${line}`)
        : null) ?? vp.querySelector<HTMLElement>(`[data-spread-ch="${ch}"]`);
    if (!targetEl) return;
    const page = scrollElementIntoSpread(vp, targetEl, 44, false);
    this.spreadPage.set(page);
    this.visibleChapterIndex.set(ch);
    this.chapterIndex.set(ch);
    const match = this.fullBookChapters().find((c) => c.chapterIndex === ch);
    if (match) {
      this.lines.set(match.lines);
    }
    void this.router.navigate(['/books', this.currentBookId()], {
      queryParams: { chapter: ch },
      replaceUrl: true,
    });
  }

  private async loadFullBookForSpread(
    bookId: string,
    toc: BookToc,
  ): Promise<void> {
    if (
      this.fullBookLoadedForId === bookId ||
      this.fullBookLoadingForId === bookId
    ) {
      return;
    }
    this.fullBookLoadingForId = bookId;
    try {
      const lang = this.currentBookLang();
      const total = toc.chapters.length;
      const loaded = await Promise.all(
        toc.chapters.map(async (meta): Promise<SpreadBookChapter> => {
          const rawLines = await this.booksService.fetchChapter(
            bookId,
            meta.chapterIndex,
            lang,
            total,
          );
          const words = rawLines.reduce(
            (acc, l) => acc + (l.text ? l.text.split(/\s+/).length : 0),
            0,
          );
          return {
            chapterIndex: meta.chapterIndex,
            title: meta.title ?? '',
            minutes: Math.max(1, Math.round(words / 220)),
            lines: rawLines,
            parsedLines: rawLines.map((line, index) => ({
              line,
              tokens: line.isHeading
                ? []
                : this.scriptureParser.parse(line.text),
              hidden:
                index === 0 &&
                Boolean(line.isHeading) &&
                this.isDuplicateChapterHeading(line.text, meta.title ?? ''),
            })),
          };
        }),
      );
      if (this.currentBookId() !== bookId) return;
      this.fullBookChapters.set(loaded);
      this.fullBookLoadedForId = bookId;
      setTimeout(() => {
        this.refreshSpreadMetrics();
        this.scrollToSpreadChapter(this.chapterIndex());
      }, 20);
    } finally {
      if (this.fullBookLoadingForId === bookId) {
        this.fullBookLoadingForId = '';
      }
    }
  }

  readonly filteredSidebarChapters = computed(() => {
    const list = this.toc()?.chapters ?? [];
    const q = this.sidebarFilter().trim().toLowerCase();
    if (!q) return list;
    return list.filter(
      (c) =>
        c.title.toLowerCase().includes(q) ||
        String(c.chapterIndex).includes(q),
    );
  });

  readonly hasPrevBookChapter = computed(() => {
    const first = this.prependedChapters()[0]?.chapterIndex ?? this.chapterIndex();
    return first > 1;
  });

  readonly hasNextBookChapter = computed(() => {
    const list = this.appendedChapters();
    const last = list.length > 0 ? list[list.length - 1].chapterIndex : this.chapterIndex();
    const total = this.toc()?.chapters.length ?? 1;
    return last < total;
  });

  readonly prevChapterLabel = computed(() => {
    const first = this.prependedChapters()[0]?.chapterIndex ?? this.chapterIndex();
    const prev = first - 1;
    if (prev < 1) return '';
    const title = this.toc()?.chapters.find((c) => c.chapterIndex === prev)?.title;
    return title ? `Ch. ${prev}: ${title}` : `Chapter ${prev}`;
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

  @HostListener('window:resize')
  onWindowResize(): void {
    this.refreshLineToolbarAnchor();
  }

  @HostListener('window:scroll')
  onWindowScroll(): void {
    this.refreshLineToolbarAnchor();
    if (this.isPaginated()) return;
    this.syncVisibleChapterFromScroll();
    if (window.scrollY > 180) {
      this.hasScrolledDown = true;
    } else if (
      this.hasScrolledDown &&
      window.scrollY <= 80 &&
      this.hasPrevBookChapter() &&
      !this.loadingPrev() &&
      !this.loading()
    ) {
      void this.prependPrevChapter();
    }
  }

  @HostListener('window:wheel', ['$event'])
  onWindowWheel(event: WheelEvent): void {
    if (this.isPaginated()) return;
    if (
      event.deltaY < 0 &&
      window.scrollY <= 4 &&
      this.hasPrevBookChapter() &&
      !this.loadingPrev() &&
      !this.loading()
    ) {
      void this.prependPrevChapter();
    }
  }

  private syncVisibleChapterFromScroll(): void {
    if (this.prependedChapters().length === 0 && this.appendedChapters().length === 0) {
      if (this.visibleChapterIndex() !== null) {
        this.visibleChapterIndex.set(null);
      }
      return;
    }
    const nodes = document.querySelectorAll<HTMLElement>('[data-book-ch]');
    if (nodes.length === 0) return;

    let active: HTMLElement = nodes[0];
    for (const el of Array.from(nodes)) {
      if (el.getBoundingClientRect().top <= 140) {
        active = el;
      } else {
        break;
      }
    }
    const ch = Number(active.dataset['bookCh'] ?? 0);
    if (ch > 0 && ch !== this.visibleChapterIndex()) {
      this.visibleChapterIndex.set(ch);
    }
  }

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
      this.showNavigatorDrawer.set(false);
      this.showAppearance.set(false);
      this.showHighlights.set(false);
      this.showSearch.set(false);
      this.showNoteModal.set(false);
      this.activeScriptureRef.set(null);
      this.lookupWord.set(null);
      this.menuOpen.set(false);
      this.immersive.set(false);
      return;
    }
    if (event.key === 'f' || event.key === 'F') {
      this.immersive.set(!this.immersive());
      return;
    }
    if (
      this.showToc() ||
      this.showNavigatorDrawer() ||
      this.showAppearance() ||
      this.showHighlights() ||
      this.showSearch() ||
      this.showNoteModal() ||
      this.activeScriptureRef() ||
      this.lookupWord()
    ) {
      return;
    }
    if (this.isPaginated()) {
      if (event.key === 'ArrowLeft') {
        event.preventDefault();
        if (this.isImageBook()) {
          this.goToImageSpread(this.imageSpreadIndex() - 1);
        } else {
          this.goToSpreadPage(this.spreadPage() - 1);
        }
      } else if (event.key === 'ArrowRight') {
        event.preventDefault();
        if (this.isImageBook()) {
          this.goToImageSpread(this.imageSpreadIndex() + 1);
        } else {
          this.goToSpreadPage(this.spreadPage() + 1);
        }
      }
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
    this.fullBookChapters.set([]);
    this.fullBookLoadedForId = '';
    this.fullBookLoadingForId = '';
    this.imageSpreadIndex.set(0);
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
      if (this.isPaginated()) {
        void this.loadFullBookForSpread(bookId, toc);
      }
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
    this.prependedChapters.set([]);
    this.appendedChapters.set([]);
    this.visibleChapterIndex.set(null);
    this.hasScrolledDown = false;
    if (!this.pendingLastSpreadPage) {
      this.spreadPage.set(1);
    }
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
          const el = document.getElementById(`book-line-${scrollIdx}`);
          if (!el) return;
          if (this.isPaginated()) {
            const vp = this.spreadViewportRef?.nativeElement;
            if (vp && scrollIdx > 0) {
              const page = scrollElementIntoSpread(vp, el, 44, true);
              this.spreadPage.set(page);
            }
          } else {
            el.scrollIntoView({ behavior: 'smooth', block: 'center' });
          }
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

  toggleSelectLine(index: number, chIdx?: number): void {
    const sel = window.getSelection()?.toString().trim();
    if (sel) return;
    this.selectionAnchor.set(null);
    if (chIdx !== undefined && chIdx !== this.chapterIndex()) {
      this.chapterIndex.set(chIdx);
      const match = this.fullBookChapters().find(
        (c) => c.chapterIndex === chIdx,
      );
      if (match) this.lines.set(match.lines);
      this.selectedIndex.set(index);
      this.refreshLineToolbarAnchor();
      return;
    }
    this.selectedIndex.set(this.selectedIndex() === index ? null : index);
    this.refreshLineToolbarAnchor();
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

  highlightColor(index: number, chIdx?: number): string | null {
    return this.highlightsService.colorFor(
      this.currentBookId(),
      chIdx ?? this.chapterIndex(),
      index,
    );
  }

  noteFor(index: number, chIdx?: number): string {
    return this.highlightsService.noteFor(
      this.currentBookId(),
      chIdx ?? this.chapterIndex(),
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
    if (this.isPaginated() && this.fullBookChapters().length > 0) {
      this.scrollToSpreadChapter(target.chapter, target.line);
      return;
    }
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

  prevChapter(): void {
    const cur = this.displayChapterIndex();
    if (cur > 1) {
      if (this.isPaginated() && this.fullBookChapters().length > 0) {
        this.scrollToSpreadChapter(cur - 1);
      } else {
        void this.loadChapter(cur - 1);
      }
    }
  }

  nextChapter(): void {
    const cur = this.displayChapterIndex();
    const total = this.toc()?.chapters.length ?? 1;
    if (cur < total) {
      if (this.isPaginated() && this.fullBookChapters().length > 0) {
        this.scrollToSpreadChapter(cur + 1);
      } else {
        void this.loadChapter(cur + 1);
      }
    }
  }

  async prependPrevChapter(): Promise<void> {
    if (this.loadingPrev() || this.loading()) return;
    const first = this.prependedChapters()[0]?.chapterIndex ?? this.chapterIndex();
    const prevIdx = first - 1;
    if (prevIdx < 1) return;

    this.loadingPrev.set(true);
    try {
      const extra = await this.buildExtraChapter(prevIdx);
      if (!extra) return;

      const prevHeight = document.documentElement.scrollHeight;
      this.prependedChapters.update((cur) => [extra, ...cur]);
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
    if (this.loadingMore() || this.loading()) return;
    const list = this.appendedChapters();
    const last = list.length > 0 ? list[list.length - 1].chapterIndex : this.chapterIndex();
    const nextIdx = last + 1;
    const total = this.toc()?.chapters.length ?? 1;
    if (nextIdx > total) return;

    this.loadingMore.set(true);
    try {
      const extra = await this.buildExtraChapter(nextIdx);
      if (!extra) return;
      this.appendedChapters.update((cur) => [...cur, extra]);
    } finally {
      this.loadingMore.set(false);
    }
  }

  private async buildExtraChapter(ch: number): Promise<ExtraBookChapter | null> {
    const bookId = this.currentBookId();
    if (!bookId) return null;
    try {
      const lines = await this.booksService.fetchChapter(
        bookId,
        ch,
        this.currentBookLang(),
        this.toc()?.chapters.length,
      );
      if (lines.length === 0) return null;
      const title =
        this.toc()?.chapters.find((c) => c.chapterIndex === ch)?.title ?? '';
      const parsedLines: ParsedBookLineItem[] = lines
        .filter(
          (line, index) =>
            !(
              index === 0 &&
              Boolean(line.isHeading) &&
              this.isDuplicateChapterHeading(line.text, title)
            ),
        )
        .map((line) => ({
          line,
          tokens: line.isHeading ? [] : this.scriptureParser.parse(line.text),
        }));
      const words = lines.reduce(
        (acc, l) => acc + (l.text ? l.text.split(/\s+/).length : 0),
        0,
      );
      return {
        chapterIndex: ch,
        title,
        parsedLines,
        minutes: Math.max(1, Math.round(words / 220)),
      };
    } catch {
      return null;
    }
  }

  selectChapterFromDrawer(ch: number): void {
    this.showNavigatorDrawer.set(false);
    this.selectChapter(ch);
  }

  selectChapter(ch: number): void {
    this.showToc.set(false);
    if (this.isPaginated() && this.fullBookChapters().length > 0) {
      this.scrollToSpreadChapter(ch);
      return;
    }
    void this.loadChapter(ch);
  }
}
