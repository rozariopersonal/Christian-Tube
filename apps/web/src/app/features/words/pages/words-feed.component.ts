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
import { Router } from '@angular/router';
import { ScreenClassService } from '../../../core/layout/screen-class.service';
import { HeaderSlotService } from '../../../core/services/header-slot.service';
import { ThemeService } from '../../../core/theme/theme.service';
import {
  BibleVersionPickerComponent,
  BibleVersionSelectionEvent,
} from '../../../shared/ui/bible-version-picker.component';
import { BOOK_ABBREVS } from '../../bible/models/bible.model';
import { WordsFilterDrawerComponent } from '../components/words-filter-drawer.component';
import { WordsStyleDrawerComponent } from '../components/words-style-drawer.component';
import {
  WordFeedItem,
  WordsFilterState,
  countActiveFilters,
} from '../models/words-feed.model';
import {
  findFontOption,
  getLanguageForVersion,
  getPreset,
  resolvePresetCssBackground,
} from '../models/words-theme.catalog';
import { WordsFeedService } from '../services/words-feed.service';
import { WordsImageExporterService } from '../services/words-image-exporter.service';
import { WordsPreferencesService } from '../services/words-preferences.service';

@Component({
  selector: 'app-words-feed',
  standalone: true,
  imports: [
    NgTemplateOutlet,
    BibleVersionPickerComponent,
    WordsFilterDrawerComponent,
    WordsStyleDrawerComponent,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <ng-template #topbarCenter>
      <div class="tb-words-center">
        <app-bible-version-picker
          contextKey="words"
          (selectionChanged)="onVersionsChanged($event)"
        />
        <div class="tb-actions-pill">
          <button
            type="button"
            class="tb-action-btn"
            title="Previous Word (↑)"
            aria-label="Previous Word"
            [disabled]="activeIndex() <= 0 || transitionPhase() !== 'idle'"
            (click)="prev()"
          >
            <span class="material-symbols-rounded">keyboard_arrow_up</span>
          </button>
          @if (words.items().length > 0) {
            <span class="tb-counter">
              {{ activeIndex() + 1 }} / {{ words.items().length }}
            </span>
          }
          <button
            type="button"
            class="tb-action-btn"
            title="Next Word (↓)"
            aria-label="Next Word"
            [disabled]="!canGoNext() || transitionPhase() !== 'idle'"
            (click)="next()"
          >
            <span class="material-symbols-rounded">keyboard_arrow_down</span>
          </button>
        </div>
      </div>
    </ng-template>

    <ng-template #topbarRight>
      <div class="tb-actions-pill">
        <button
          type="button"
          class="tb-action-btn tb-font-step"
          title="Decrease font size"
          aria-label="Decrease font size"
          [disabled]="prefs.appearance().fontSizeScale <= 0.8"
          (click)="stepFont(-0.1)"
        >
          <span class="material-symbols-rounded">remove</span>
        </button>
        <button
          type="button"
          class="tb-action-btn tb-aa-btn"
          title="Style Studio"
          aria-label="Style Studio"
          (click)="activeModal.set('style')"
        >
          Aa
        </button>
        <button
          type="button"
          class="tb-action-btn tb-font-step"
          title="Increase font size"
          aria-label="Increase font size"
          [disabled]="prefs.appearance().fontSizeScale >= 1.5"
          (click)="stepFont(0.1)"
        >
          <span class="material-symbols-rounded">add</span>
        </button>

        @if (currentItem(); as item) {
          <button
            type="button"
            class="tb-action-btn"
            [class.active-icon]="item.isSaved"
            [title]="item.isSaved ? 'Remove Bookmark' : 'Save Verse'"
            aria-label="Toggle Bookmark"
            (click)="toggleSave(item)"
          >
            <span class="material-symbols-rounded">
              {{ item.isSaved ? 'bookmark' : 'bookmark_border' }}
            </span>
          </button>
          <button
            type="button"
            class="tb-action-btn"
            title="Download Image Card"
            aria-label="Download Image Card"
            (click)="exportImage(item)"
          >
            <span class="material-symbols-rounded">image</span>
          </button>
          <button
            type="button"
            class="tb-action-btn"
            title="Copy Verse"
            aria-label="Copy Verse"
            (click)="copyWord(item)"
          >
            <span class="material-symbols-rounded">content_copy</span>
          </button>
          <button
            type="button"
            class="tb-action-btn"
            title="Share"
            aria-label="Share"
            (click)="shareWord(item)"
          >
            <span class="material-symbols-rounded">share</span>
          </button>
        }

        <button
          type="button"
          class="tb-action-btn"
          title="Shuffle Random Deck"
          aria-label="Shuffle Random Deck"
          (click)="selectRandomDeck()"
        >
          <span class="material-symbols-rounded">shuffle</span>
        </button>

        <button
          type="button"
          class="tb-action-btn"
          [class.active-icon]="activeFilterCount() > 0"
          title="Feed Filters & Order"
          aria-label="Feed Filters"
          (click)="activeModal.set('filter')"
        >
          <span class="material-symbols-rounded">tune</span>
          @if (activeFilterCount() > 0) {
            <span class="filter-count">{{ activeFilterCount() }}</span>
          }
        </button>
      </div>
    </ng-template>

    <div
      class="words-stage"
      [class.light-stage]="!theme.isDark()"
      [style.background]="stageBackground()"
      (touchstart)="onTouchStart($event)"
      (touchend)="onTouchEnd($event)"
      (wheel)="onWheel($event)"
    >
      @if (screen.isCompact()) {
        <div class="compact-topbar">
          <ng-container *ngTemplateOutlet="topbarCenter" />
          <ng-container *ngTemplateOutlet="topbarRight" />
        </div>
      }

      <div class="stage-body">
        @if (words.loading() && words.items().length === 0) {
          <p class="status-msg">Loading scripture...</p>
        } @else if (words.error()) {
          <div class="status-msg">
            <p>{{ words.error() }}</p>
            <button
              type="button"
              class="action-pill-btn"
              (click)="words.initialize()"
            >
              Retry
            </button>
          </div>
        } @else if (currentItem(); as item) {
          @let comparisons = item.comparisons ?? [];
          @let isComparing = comparisons.length > 0;
          <article
            class="word-spotlight"
            [class.comparing]="isComparing"
            [class.transition-exit-next]="transitionPhase() === 'exit' && transitionDirection() === 'next'"
            [class.transition-exit-prev]="transitionPhase() === 'exit' && transitionDirection() === 'prev'"
            [class.transition-enter-next]="transitionPhase() === 'enter' && transitionDirection() === 'next'"
            [class.transition-enter-prev]="transitionPhase() === 'enter' && transitionDirection() === 'prev'"
            [style.color]="prefs.appearance().textColorHex"
            (animationend)="onCardAnimationEnd($event)"
          >
            <div class="verse-scroll" #verseScroll>
              @if (isComparing) {
                <div
                  class="compare-grid"
                  [class.cols-2]="comparisons.length === 1"
                  [class.cols-3]="comparisons.length >= 2"
                >
                  <div class="compare-col">
                    <span class="cmp-ver-label">{{ (item.resolvedVersion || prefs.activeVersionId()).toUpperCase() }}</span>
                    <blockquote
                      class="verse-quote"
                      [style.fontFamily]="activeFontCss()"
                      [style.fontSize.px]="quoteFontPx()"
                      [style.fontWeight]="prefs.appearance().isBold ? '700' : '400'"
                      [style.fontStyle]="prefs.appearance().isItalic ? 'italic' : 'normal'"
                      [style.textAlign]="prefs.appearance().textAlign"
                    >
                      “{{ item.verseText || item.theme || item.referenceLabel }}”
                    </blockquote>
                  </div>

                  @for (c of comparisons; track c.version) {
                    <div class="compare-col compare-col-secondary">
                      <span class="cmp-ver-label">{{ c.version.toUpperCase() }}</span>
                      <blockquote
                        class="verse-quote cmp-quote"
                        [style.fontFamily]="activeFontCss()"
                        [style.fontSize.px]="quoteFontPx()"
                        [style.fontWeight]="prefs.appearance().isBold ? '700' : '400'"
                        [style.fontStyle]="prefs.appearance().isItalic ? 'italic' : 'normal'"
                        [style.textAlign]="prefs.appearance().textAlign"
                      >
                        “{{ c.text }}”
                      </blockquote>
                    </div>
                  }
                </div>
              } @else {
                <blockquote
                  class="verse-quote"
                  [style.fontFamily]="activeFontCss()"
                  [style.fontSize.px]="quoteFontPx()"
                  [style.fontWeight]="prefs.appearance().isBold ? '700' : '400'"
                  [style.fontStyle]="prefs.appearance().isItalic ? 'italic' : 'normal'"
                  [style.textAlign]="prefs.appearance().textAlign"
                >
                  “{{ item.verseText || item.theme || item.referenceLabel }}”
                </blockquote>
              }
            </div>

            <footer class="spotlight-footer">
              <div class="footer-info">
                <strong class="ref-label">{{ item.referenceLabel }}</strong>
                <div class="meta-badges">
                  @if (item.theme || item.category) {
                    <span class="theme-pill">{{ item.theme || item.category }}</span>
                  }
                  @if (words.filterState().readingOrder !== 'daily') {
                    <span class="order-pill">{{ words.filterState().readingOrder }}</span>
                  }
                  <span class="ver-tag">
                    {{ (item.resolvedVersion || prefs.activeVersionId()).toUpperCase() }}
                    @for (c of comparisons; track c.version) {
                      · {{ c.version.toUpperCase() }}
                    }
                  </span>
                </div>
              </div>
              <button
                type="button"
                class="read-btn"
                (click)="openInBible(item)"
              >
                <span class="material-symbols-rounded">menu_book</span>
                Open in Bible
              </button>
            </footer>
          </article>
        } @else {
          <div class="status-msg">
            @if (words.filterState().readingOrder === 'bookmarked') {
              <p>No saved verses yet. Tap the bookmark icon in the top bar to save verses here.</p>
              <button
                type="button"
                class="action-pill-btn"
                (click)="selectTopic('daily')"
              >
                Browse Daily Word
              </button>
            } @else {
              <p>No verses matched your filters.</p>
              <button
                type="button"
                class="action-pill-btn"
                (click)="resetFilters()"
              >
                Reset Filters
              </button>
            }
          </div>
        }
      </div>

      @if (toastMessage(); as msg) {
        <div class="toast-pill">{{ msg }}</div>
      }
    </div>

    @if (activeModal() === 'filter') {
      <app-words-filter-drawer
        [currentFilter]="words.filterState()"
        (applied)="onFiltersApplied($event)"
        (closed)="activeModal.set(null)"
      />
    } @else if (activeModal() === 'style') {
      <app-words-style-drawer
        [card]="currentItem()"
        (cardUpdated)="onCardStyleUpdated($event)"
        (closed)="activeModal.set(null)"
      />
    }
  `,
  styles: [
    `
      .tb-words-center {
        display: flex;
        align-items: center;
        gap: 8px;
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
        flex-shrink: 0;
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

      .tb-counter {
        font-size: 11.5px;
        font-weight: 600;
        color: var(--on-surface-muted);
        padding: 0 6px;
        white-space: nowrap;
      }

      .active-icon {
        color: var(--accent);
        background-color: var(--accent-soft);
      }

      .filter-count {
        position: absolute;
        top: 1px;
        right: 1px;
        min-width: 14px;
        height: 14px;
        padding: 0 3px;
        border-radius: var(--radius-pill);
        background-color: var(--accent);
        color: #ffffff;
        font-size: 9.5px;
        font-weight: 700;
        display: grid;
        place-items: center;
      }

      .words-stage {
        position: relative;
        height: calc(100dvh - var(--shell-bottom-offset, 0px) - var(--shell-top-offset));
        color: #ffffff;
        display: flex;
        flex-direction: column;
        padding: 16px;
        gap: 10px;
        transition: background 320ms ease;
        overflow: hidden;
      }

      .words-stage.light-stage {
        color: #0f172a;
      }

      @media (min-width: 600px) {
        .words-stage {
          padding: 24px;
        }
      }

      .compact-topbar {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
        flex-wrap: wrap;
        flex-shrink: 0;
      }

      .stage-body {
        flex: 1;
        min-height: 0;
        display: flex;
        align-items: stretch;
        justify-content: center;
      }

      .word-spotlight {
        width: 100%;
        height: 100%;
        overflow: hidden;
        border-radius: var(--radius-lg);
        background-color: rgba(0, 0, 0, 0.24);
        backdrop-filter: blur(14px);
        -webkit-backdrop-filter: blur(14px);
        border: 1px solid rgba(255, 255, 255, 0.16);
        display: flex;
        flex-direction: column;
      }

      .word-spotlight.transition-exit-next,
      .word-spotlight.transition-exit-prev,
      .word-spotlight.transition-enter-next,
      .word-spotlight.transition-enter-prev {
        will-change: transform, opacity;
      }

      .word-spotlight.transition-exit-next {
        animation: words-exit-next 180ms cubic-bezier(0.4, 0, 1, 1) both;
      }

      .word-spotlight.transition-exit-prev {
        animation: words-exit-prev 180ms cubic-bezier(0.4, 0, 1, 1) both;
      }

      .word-spotlight.transition-enter-next {
        animation: words-enter-next 220ms cubic-bezier(0, 0, 0.2, 1) both;
      }

      .word-spotlight.transition-enter-prev {
        animation: words-enter-prev 220ms cubic-bezier(0, 0, 0.2, 1) both;
      }

      @keyframes words-exit-next {
        to {
          transform: translate3d(0, -110%, 0);
          opacity: 0.35;
        }
      }

      @keyframes words-exit-prev {
        to {
          transform: translate3d(0, 110%, 0);
          opacity: 0.35;
        }
      }

      @keyframes words-enter-next {
        from {
          transform: translate3d(0, 110%, 0);
          opacity: 0.35;
        }
        to {
          transform: translate3d(0, 0, 0);
          opacity: 1;
        }
      }

      @keyframes words-enter-prev {
        from {
          transform: translate3d(0, -110%, 0);
          opacity: 0.35;
        }
        to {
          transform: translate3d(0, 0, 0);
          opacity: 1;
        }
      }

      @media (prefers-reduced-motion: reduce) {
        .word-spotlight.transition-exit-next,
        .word-spotlight.transition-exit-prev,
        .word-spotlight.transition-enter-next,
        .word-spotlight.transition-enter-prev {
          animation-duration: 1ms;
        }
      }

      .light-stage .word-spotlight {
        background-color: rgba(255, 255, 255, 0.72);
        border-color: rgba(15, 23, 42, 0.1);
        box-shadow: 0 12px 32px rgba(15, 23, 42, 0.08);
      }

      .verse-scroll {
        flex: 1;
        min-height: 0;
        overflow-y: auto;
        overscroll-behavior: contain;
        padding: clamp(20px, 3.5vw, 44px);
        display: flex;
        flex-direction: column;
        scrollbar-width: thin;
        scrollbar-color: rgba(255, 255, 255, 0.28) transparent;
      }

      .verse-scroll > .verse-quote,
      .verse-scroll > .compare-grid {
        margin-block: auto;
      }

      .verse-scroll::-webkit-scrollbar {
        width: 6px;
      }

      .verse-scroll::-webkit-scrollbar-track {
        background: transparent;
        margin: 14px 0;
      }

      .verse-scroll::-webkit-scrollbar-thumb {
        border-radius: 999px;
        background-color: rgba(255, 255, 255, 0.26);
      }

      .verse-scroll::-webkit-scrollbar-thumb:hover {
        background-color: rgba(255, 255, 255, 0.42);
      }

      .light-stage .verse-scroll {
        scrollbar-color: rgba(15, 23, 42, 0.22) transparent;
      }

      .light-stage .verse-scroll::-webkit-scrollbar-thumb {
        background-color: rgba(15, 23, 42, 0.2);
      }

      .light-stage .verse-scroll::-webkit-scrollbar-thumb:hover {
        background-color: rgba(15, 23, 42, 0.35);
      }

      .meta-badges {
        display: flex;
        align-items: center;
        gap: 6px;
        flex-wrap: wrap;
      }

      .theme-pill,
      .order-pill {
        font-size: 11px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        padding: 4px 10px;
        border-radius: var(--radius-pill);
        background-color: rgba(255, 255, 255, 0.16);
      }

      .light-stage .theme-pill,
      .light-stage .order-pill {
        background-color: rgba(15, 23, 42, 0.08);
      }

      .ver-tag {
        font-size: 12px;
        font-weight: 700;
        opacity: 0.85;
      }

      .verse-quote {
        margin: 0;
        line-height: 1.55;
        transition: font-size 160ms ease;
      }

      .compare-grid {
        display: grid;
        grid-template-columns: 1fr;
        gap: 18px;
      }

      .compare-col {
        display: flex;
        flex-direction: column;
        gap: 8px;
        min-width: 0;
      }

      .compare-col-secondary {
        padding-top: 14px;
        border-top: 1px dashed rgba(255, 255, 255, 0.22);
      }

      .light-stage .compare-col-secondary {
        border-top-color: rgba(15, 23, 42, 0.16);
      }

      @media (min-width: 600px) {
        .compare-grid.cols-2,
        .compare-grid.cols-3 {
          grid-template-columns: repeat(2, 1fr);
          gap: 24px;
          align-items: start;
        }

        .compare-col-secondary {
          padding-top: 0;
          padding-left: 24px;
          border-top: none;
          border-left: 1px dashed rgba(255, 255, 255, 0.22);
        }

        .light-stage .compare-col-secondary {
          border-left-color: rgba(15, 23, 42, 0.16);
        }
      }

      @media (min-width: 960px) {
        .compare-grid.cols-3 {
          grid-template-columns: repeat(3, 1fr);
        }
      }

      .cmp-ver-label {
        font-size: 11px;
        font-weight: 700;
        letter-spacing: 0.06em;
        opacity: 0.72;
      }

      .cmp-quote {
        opacity: 0.92;
      }

      .spotlight-footer {
        flex-shrink: 0;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        flex-wrap: wrap;
        padding: 14px clamp(16px, 3.5vw, 44px);
        border-top: 1px solid rgba(255, 255, 255, 0.14);
      }

      .footer-info {
        display: flex;
        align-items: center;
        gap: 10px;
        flex-wrap: wrap;
        min-width: 0;
      }

      .light-stage .spotlight-footer {
        border-top-color: rgba(15, 23, 42, 0.1);
      }

      .ref-label {
        font-size: 15px;
        font-weight: 700;
      }

      .read-btn {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        height: 36px;
        padding: 0 14px;
        border-radius: var(--radius-pill);
        background-color: #ffffff;
        color: #0f172a;
        font-size: 13px;
        font-weight: 600;
      }

      .light-stage .read-btn {
        background-color: #0f172a;
        color: #ffffff;
      }

      .read-btn .material-symbols-rounded {
        font-size: 18px;
      }

      @media (max-width: 479px) {
        .stage-body {
          flex-direction: column;
          gap: 12px;
        }

        .word-spotlight {
          width: 100%;
          flex: 1;
          min-height: 0;
        }
      }
      .status-msg {
        text-align: center;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 12px;
        max-width: 380px;
      }

      .action-pill-btn {
        height: 36px;
        padding: 0 16px;
        border-radius: var(--radius-pill);
        background-color: #ffffff;
        color: #0f172a;
        font-size: 13px;
        font-weight: 600;
      }

      .toast-pill {
        position: absolute;
        bottom: 20px;
        left: 50%;
        transform: translateX(-50%);
        padding: 8px 16px;
        border-radius: var(--radius-pill);
        background-color: #0f172a;
        color: #ffffff;
        font-size: 13px;
        font-weight: 600;
        box-shadow: 0 6px 20px rgba(0, 0, 0, 0.28);
        pointer-events: none;
        z-index: 20;
      }
    `,
  ],
})
export class WordsFeedComponent implements OnInit, AfterViewInit {
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);
  private readonly headerSlot = inject(HeaderSlotService);
  readonly screen = inject(ScreenClassService);
  readonly words = inject(WordsFeedService);
  readonly prefs = inject(WordsPreferencesService);
  readonly theme = inject(ThemeService);
  private readonly exporter = inject(WordsImageExporterService);

  @ViewChild('topbarCenter') topbarCenterRef?: TemplateRef<unknown>;
  @ViewChild('topbarRight') topbarRightRef?: TemplateRef<unknown>;
  @ViewChild('verseScroll') verseScrollRef?: ElementRef<HTMLElement>;

  readonly activeIndex = signal<number>(0);
  readonly transitionPhase = signal<'idle' | 'exit' | 'enter'>('idle');
  readonly transitionDirection = signal<'next' | 'prev'>('next');
  readonly activeModal = signal<'filter' | 'style' | null>(null);
  readonly toastMessage = signal<string | null>(null);
  private readonly viewInitialized = signal<boolean>(false);

  private touchStartY: number | null = null;
  private lastWheelAt = 0;
  private toastTimer: ReturnType<typeof setTimeout> | null = null;

  readonly currentItem = computed<WordFeedItem | null>(
    () => this.words.items()[this.activeIndex()] ?? null,
  );

  readonly canGoNext = computed(
    () =>
      this.activeIndex() + 1 < this.words.items().length ||
      this.words.hasMore(),
  );

  readonly activeFilterCount = computed(() =>
    countActiveFilters(this.words.filterState()),
  );

  readonly stageBackground = computed(() => {
    const item = this.currentItem();
    const presetId =
      item?.customBackgroundPreset ??
      this.prefs.appearance().backgroundPreset ??
      item?.backgroundPreset;
    return resolvePresetCssBackground(getPreset(presetId), this.theme.isDark());
  });

  readonly activeFontCss = computed(() => {
    const item = this.currentItem();
    const ap = this.prefs.appearance();
    const lang = getLanguageForVersion(ap.activeVersionId);
    const fontId = item?.customFontFamily ?? ap.activeFontFamily;
    return findFontOption(fontId, lang).cssFamily;
  });

  readonly quoteFontPx = computed(() =>
    Math.round(24 * this.prefs.appearance().fontSizeScale),
  );

  constructor() {
    this.destroyRef.onDestroy(() => this.headerSlot.clear());

    effect(() => {
      if (!this.viewInitialized()) return;
      if (this.screen.isMediumOrExpanded()) {
        this.headerSlot.setTemplates(
          this.topbarCenterRef ?? null,
          this.topbarRightRef ?? null,
        );
      } else {
        this.headerSlot.clear();
      }
    });
  }

  @HostListener('window:keydown', ['$event'])
  onKeyDown(event: KeyboardEvent): void {
    if (this.activeModal()) {
      if (event.key === 'Escape') {
        this.activeModal.set(null);
      }
      return;
    }
    const target = event.target as HTMLElement | null;
    if (target && ['INPUT', 'TEXTAREA', 'SELECT'].includes(target.tagName)) {
      return;
    }
    if (event.key === 'ArrowDown' || event.key === 'ArrowRight' || event.key === 'j') {
      this.next();
    } else if (event.key === 'ArrowUp' || event.key === 'ArrowLeft' || event.key === 'k') {
      this.prev();
    }
  }

  ngOnInit(): void {
    void this.words.initialize();
  }

  ngAfterViewInit(): void {
    this.viewInitialized.set(true);
  }

  selectTopic(slug: string): void {
    this.activeIndex.set(0);
    void this.words.selectTopic(slug);
  }

  selectRandomDeck(): void {
    this.activeIndex.set(0);
    void this.words.reshuffleRandom();
  }

  resetFilters(): void {
    this.activeIndex.set(0);
    void this.words.resetFilters();
  }

  prev(): void {
    this.navigateWord('prev');
  }

  next(): void {
    this.navigateWord('next');
  }

  onCardAnimationEnd(event: AnimationEvent): void {
    if (event.target !== event.currentTarget) return;

    if (this.transitionPhase() === 'exit') {
      const idx = this.activeIndex();
      const targetIdx =
        this.transitionDirection() === 'next' ? idx + 1 : idx - 1;
      if (targetIdx >= 0 && targetIdx < this.words.items().length) {
        this.activeIndex.set(targetIdx);
      }
      if (this.verseScrollRef?.nativeElement) {
        this.verseScrollRef.nativeElement.scrollTop = 0;
      }
      this.transitionPhase.set('enter');
    } else if (this.transitionPhase() === 'enter') {
      this.transitionPhase.set('idle');
    }
  }

  private navigateWord(direction: 'next' | 'prev'): void {
    if (this.transitionPhase() !== 'idle') return;
    const idx = this.activeIndex();

    if (direction === 'prev') {
      if (idx <= 0) return;
      this.transitionDirection.set('prev');
      this.transitionPhase.set('exit');
      return;
    }

    const nextIdx = idx + 1;
    if (nextIdx < this.words.items().length) {
      this.transitionDirection.set('next');
      this.transitionPhase.set('exit');
      if (
        this.words.hasMore() &&
        nextIdx >= this.words.items().length - 4
      ) {
        void this.words.loadMore();
      }
    } else if (this.words.hasMore()) {
      void this.words.loadMore();
    }
  }

  stepFont(delta: number): void {
    this.prefs.setFontScale(this.prefs.appearance().fontSizeScale + delta);
  }

  onVersionsChanged(event: BibleVersionSelectionEvent): void {
    if (event.kind === 'primary') {
      void this.words.rehydrateVersion(this.activeIndex());
    } else {
      void this.words.rehydrateComparison(this.activeIndex());
    }
  }

  onFiltersApplied(next: WordsFilterState): void {
    this.activeIndex.set(0);
    void this.words.applyFilterState(next);
  }

  onCardStyleUpdated(patch: {
    customBackgroundPreset?: string;
    customFontFamily?: string;
  }): void {
    const idx = this.activeIndex();
    this.words.items.update((list) =>
      list.map((item, i) => (i === idx ? { ...item, ...patch } : item)),
    );
  }

  toggleSave(item: WordFeedItem): void {
    const saved = this.prefs.toggleSave(item);
    this.words.syncSavedFlags();
    this.showToast(
      saved ? `Saved ${item.referenceLabel}` : 'Removed from saved verses',
    );
  }

  async exportImage(item: WordFeedItem): Promise<void> {
    try {
      const outcome = await this.exporter.exportCard(
        item,
        this.prefs.appearance(),
        this.theme.isDark(),
      );
      this.showToast(
        outcome === 'shared' ? 'Shared verse card' : 'Downloaded PNG card',
      );
    } catch {
      this.showToast('Unable to export image');
    }
  }

  openInBible(item: WordFeedItem): void {
    const ver = item.resolvedVersion ?? this.prefs.activeVersionId();
    const mapping =
      item.verseMappings?.[ver] ?? item.verseMappings?.[ver.toUpperCase()];
    const bookNum = mapping?.bookNumber ?? item.bookNumber;
    const chapter = mapping?.chapter ?? item.chapter;
    const verse = mapping?.startVerse ?? item.startVerse;
    const abbrev = BOOK_ABBREVS[bookNum] || String(bookNum);

    void this.router.navigate(['/bible'], {
      queryParams: {
        version: ver,
        book: abbrev,
        chapter,
        verse,
      },
    });
  }

  copyWord(item: WordFeedItem): void {
    const ver = (item.resolvedVersion ?? this.prefs.activeVersionId()).toUpperCase();
    const abbrev = BOOK_ABBREVS[item.bookNumber] || String(item.bookNumber);
    const url = `${window.location.origin}/bible?version=${encodeURIComponent(ver.toLowerCase())}&book=${encodeURIComponent(abbrev)}&chapter=${item.chapter}&verse=${item.startVerse}`;
    const text = item.verseText
      ? `“${item.verseText}” — ${item.referenceLabel} (${ver})\n${url}`
      : `${item.referenceLabel}\n${url}`;
    void navigator.clipboard?.writeText(text);
    this.showToast('Scripture copied to clipboard');
  }

  shareWord(item: WordFeedItem): void {
    const abbrev = BOOK_ABBREVS[item.bookNumber] || String(item.bookNumber);
    const url = `${window.location.origin}/bible?version=${encodeURIComponent(this.prefs.activeVersionId())}&book=${encodeURIComponent(abbrev)}&chapter=${item.chapter}&verse=${item.startVerse}`;
    if (navigator.share) {
      void navigator.share({ title: item.referenceLabel, url }).catch(() => {
        void navigator.clipboard?.writeText(url);
        this.showToast('Link copied to clipboard');
      });
    } else {
      void navigator.clipboard?.writeText(url);
      this.showToast('Link copied to clipboard');
    }
  }

  onTouchStart(event: TouchEvent): void {
    const target = event.target as HTMLElement | null;
    if (target?.closest('.dropdown-panel')) {
      this.touchStartY = null;
      return;
    }
    this.touchStartY = event.touches[0]?.clientY ?? null;
  }

  onTouchEnd(event: TouchEvent): void {
    if (this.touchStartY === null || this.activeModal()) return;
    const target = event.target as HTMLElement | null;
    if (target?.closest('.dropdown-panel')) {
      this.touchStartY = null;
      return;
    }
    const endY = event.changedTouches[0]?.clientY ?? this.touchStartY;
    const delta = this.touchStartY - endY;
    this.touchStartY = null;
    if (Math.abs(delta) < 48) return;
    const dir = delta > 0 ? 'next' : 'prev';
    if (this.canScrollVerse(dir)) return;
    this.navigateWord(dir);
  }

  onWheel(event: WheelEvent): void {
    const target = event.target as HTMLElement | null;
    if (target?.closest('.dropdown-panel')) return;
    if (
      this.activeModal() ||
      this.transitionPhase() !== 'idle' ||
      Math.abs(event.deltaY) < 28
    ) {
      return;
    }
    const dir = event.deltaY > 0 ? 'next' : 'prev';
    if (this.canScrollVerse(dir)) return;
    const now = Date.now();
    if (now - this.lastWheelAt < 380) return;
    this.lastWheelAt = now;
    this.navigateWord(dir);
  }

  private canScrollVerse(direction: 'next' | 'prev'): boolean {
    const el = this.verseScrollRef?.nativeElement;
    if (!el || el.scrollHeight <= el.clientHeight + 2) return false;
    if (direction === 'next') {
      return el.scrollTop + el.clientHeight < el.scrollHeight - 2;
    }
    return el.scrollTop > 2;
  }

  private showToast(msg: string): void {
    this.toastMessage.set(msg);
    if (this.toastTimer) clearTimeout(this.toastTimer);
    this.toastTimer = setTimeout(() => this.toastMessage.set(null), 2200);
  }
}
