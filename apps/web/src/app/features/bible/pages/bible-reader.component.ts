import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ReleaseDataService } from '../../../core/api/release-data.service';
import {
  READER_FONTS,
  ReaderAppearanceService,
} from '../../../core/services/reader-appearance.service';
import {
  BIBLE_VERSIONS,
  BibleBook,
  BibleVerse,
} from '../models/bible.model';
import { BibleService } from '../services/bible.service';

const HIGHLIGHT_SWATCHES = ['#FEF08A', '#BBF7D0', '#BFDBFE', '#FBCFE8'];

@Component({
  selector: 'app-bible-reader',
  standalone: true,
  imports: [FormsModule],
  template: `
    <div class="bible-page">
      <header class="bible-bar">
        <div class="bar-inner max-width-box">
          <div class="bar-left">
            <button
              type="button"
              class="version-pill"
              (click)="openVersionPicker()"
              aria-label="Bible Version"
            >
              <span>{{ activeVersionInfo().label }}</span>
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
          <p class="status-msg">Loading {{ bible.currentBook().name }} {{ bible.chapter() }}...</p>
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
                [class.selected]="selectedVerse()?.verse === v.verse"
                [style.background-color]="highlightFor(v.verse)"
                (click)="toggleSelectVerse(v)"
              >
                <span class="verse-num">{{ v.verse }}</span>
                <span class="verse-text">{{ v.text }}</span>
                @if (bible.isBookmarked(v.verse)) {
                  <span class="material-symbols-rounded verse-mark">bookmark</span>
                }
                @if (noteFor(v.verse)) {
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

      @if (selectedVerse()) {
        <div class="verse-action-bar">
          <div class="action-inner max-width-box">
            <div class="action-chips">
              <button type="button" class="pill-chip" (click)="copySelected()">
                <span class="material-symbols-rounded">content_copy</span>
                Copy
              </button>
              <button
                type="button"
                class="pill-chip"
                [class.active]="bible.isBookmarked(selectedVerse()!.verse)"
                (click)="bible.toggleBookmark(selectedVerse()!)"
              >
                <span class="material-symbols-rounded">bookmark</span>
                Bookmark
              </button>
              <button type="button" class="pill-chip" (click)="openNoteEditor()">
                <span class="material-symbols-rounded">edit_note</span>
                Note
              </button>
              @if (selectedCrossRefs().length > 0) {
                <button type="button" class="pill-chip active" (click)="showCrossRefs.set(true)">
                  Cross-Refs ({{ selectedCrossRefs().length }})
                </button>
              }
              @if (selectedStudyTerms().length > 0) {
                <button type="button" class="pill-chip active" (click)="showStudy.set(true)">
                  Study ({{ selectedStudyTerms().length }})
                </button>
              }
            </div>

            <div class="swatches">
              @for (c of highlightColors; track c) {
                <button
                  type="button"
                  class="hl-swatch"
                  [style.background-color]="c"
                  (click)="bible.setHighlight(selectedVerse()!.verse, c)"
                ></button>
              }
              <button
                type="button"
                class="pill-chip"
                (click)="bible.setHighlight(selectedVerse()!.verse, null)"
              >
                Clear
              </button>
              <button type="button" class="icon-btn" (click)="selectedVerse.set(null)">
                <span class="material-symbols-rounded">close</span>
              </button>
            </div>
          </div>
        </div>
      }

      @if (showVersionPicker()) {
        <div class="modal-backdrop" (click)="showVersionPicker.set(false)">
          <div class="modal-panel picker-modal" (click)="$event.stopPropagation()">
            <div class="drag-handle"></div>
            <div class="modal-head">
              <h2 class="font-display">Bible Versions</h2>
              <button type="button" class="icon-btn" (click)="showVersionPicker.set(false)">
                <span class="material-symbols-rounded">close</span>
              </button>
            </div>
            <div class="sheet-search">
              <span class="material-symbols-rounded">search</span>
              <input
                type="search"
                placeholder="Search translations..."
                [ngModel]="versionSearch()"
                (ngModelChange)="versionSearch.set($event)"
              />
            </div>
            <div class="version-list">
              @for (v of filteredVersions(); track v.id) {
                @let active = v.id === bible.version();
                <button
                  type="button"
                  class="version-row"
                  [class.active]="active"
                  (click)="selectVersion(v.id)"
                >
                  <span class="ver-badge">{{ v.label }}</span>
                  <div class="ver-meta">
                    <strong>{{ v.fullName }}</strong>
                    <span class="muted">{{ v.language }}</span>
                  </div>
                  @if (active) {
                    <span class="material-symbols-rounded ver-check">check_circle</span>
                  }
                </button>
              }
            </div>
          </div>
        </div>
      }

      @if (showBookPicker()) {
        <div class="modal-backdrop" (click)="showBookPicker.set(false)">
          <div class="modal-panel picker-modal" (click)="$event.stopPropagation()">
            <div class="drag-handle"></div>
            <div class="picker-tabs">
              <button
                type="button"
                class="picker-tab"
                [class.active]="pickerTab() === 'books'"
                (click)="pickerTab.set('books')"
              >
                BOOKS
              </button>
              <button
                type="button"
                class="picker-tab"
                [class.active]="pickerTab() === 'chapters'"
                (click)="pickerTab.set('chapters')"
              >
                CHAPTERS
              </button>
              <button
                type="button"
                class="picker-tab"
                [class.active]="pickerTab() === 'verses'"
                (click)="openVersesTab()"
              >
                VERSES
              </button>
            </div>

            @if (pickerTab() === 'books') {
              <div class="book-filters">
                <div class="sheet-search">
                  <span class="material-symbols-rounded">search</span>
                  <input
                    type="search"
                    placeholder="Search books..."
                    [ngModel]="bookSearch()"
                    (ngModelChange)="bookSearch.set($event)"
                  />
                </div>
                <div class="testament-chips">
                  @for (t of ['all', 'ot', 'nt']; track t) {
                    <button
                      type="button"
                      class="pill-chip"
                      [class.active]="testamentFilter() === t"
                      (click)="testamentFilter.set($any(t))"
                    >
                      {{ t === 'all' ? 'All' : t.toUpperCase() }}
                    </button>
                  }
                </div>
              </div>

              <div class="books-list">
                @for (b of filteredBooks(); track b.bookNumber) {
                  <button
                    type="button"
                    class="book-row"
                    [class.active]="b.bookNumber === draftBook().bookNumber"
                    (click)="pickBook(b)"
                  >
                    <span>{{ b.name }}</span>
                    <span class="book-ch-count">{{ b.chapters }} ch</span>
                  </button>
                }
              </div>
            } @else if (pickerTab() === 'chapters') {
              <div class="chapter-pick-head">
                <strong>{{ draftBook().name }}</strong>
                <button
                  type="button"
                  class="pill-chip active"
                  (click)="applySelection(draftBook().bookNumber, draftChapter())"
                >
                  Open Ch. {{ draftChapter() }}
                </button>
              </div>
              <div class="chapters-grid">
                @for (ch of chapterNumbers(draftBook().chapters); track ch) {
                  <button
                    type="button"
                    class="ch-cell"
                    [class.active]="draftBook().bookNumber === bible.bookNumber() && ch === draftChapter()"
                    (click)="pickChapter(ch)"
                  >
                    {{ ch }}
                  </button>
                }
              </div>
            } @else {
              <div class="chapter-pick-head">
                <strong>{{ draftBook().name }} {{ draftChapter() }}</strong>
                <button
                  type="button"
                  class="pill-chip active"
                  (click)="applySelection(draftBook().bookNumber, draftChapter())"
                >
                  Read Chapter
                </button>
              </div>
              @if (loadingPickerVerses()) {
                <p class="status-msg">Loading verses...</p>
              } @else {
                <div class="chapters-grid">
                  @for (v of pickerVerses(); track v.verse) {
                    <button
                      type="button"
                      class="ch-cell"
                      (click)="applySelection(draftBook().bookNumber, draftChapter(), v.verse)"
                    >
                      {{ v.verse }}
                    </button>
                  }
                </div>
              }
            }
          </div>
        </div>
      }

      @if (showAppearance()) {
        <div class="modal-backdrop" (click)="showAppearance.set(false)">
          <div class="modal-panel picker-modal" (click)="$event.stopPropagation()">
            <div class="drag-handle"></div>
            <div class="modal-head">
              <h2 class="font-display">Reader Appearance</h2>
              <button type="button" class="icon-btn" (click)="showAppearance.set(false)">
                <span class="material-symbols-rounded">close</span>
              </button>
            </div>

            <div class="appearance-section">
              <label class="label">Font Family</label>
              <div class="chip-wrap">
                @for (f of fonts; track f.id) {
                  <button
                    type="button"
                    class="pill-chip"
                    [class.active]="appearance.fontId() === f.id"
                    (click)="appearance.setFont(f.id)"
                  >
                    {{ f.label }}
                  </button>
                }
              </div>
            </div>

            <div class="appearance-section">
              <label class="label">Font Size: {{ appearance.fontSize() }}px</label>
              <input
                type="range"
                min="13"
                max="28"
                [ngModel]="appearance.fontSize()"
                (ngModelChange)="appearance.setFontSize($event)"
              />
            </div>

            <div class="appearance-section">
              <label class="label">Line Spacing: {{ appearance.lineHeight() }}</label>
              <input
                type="range"
                min="1.3"
                max="2.2"
                step="0.05"
                [ngModel]="appearance.lineHeight()"
                (ngModelChange)="appearance.setLineHeight($event)"
              />
            </div>
          </div>
        </div>
      }

      @if (showCrossRefs() && selectedVerse()) {
        <div class="modal-backdrop" (click)="showCrossRefs.set(false)">
          <div class="modal-panel picker-modal" (click)="$event.stopPropagation()">
            <div class="drag-handle"></div>
            <div class="modal-head">
              <h2 class="font-display">
                Cross-References · {{ bible.currentBook().name }} {{ bible.chapter() }}:{{ selectedVerse()!.verse }}
              </h2>
              <button type="button" class="icon-btn" (click)="showCrossRefs.set(false)">
                <span class="material-symbols-rounded">close</span>
              </button>
            </div>
            <div class="ref-list">
              @for (r of selectedCrossRefs(); track $index) {
                <button
                  type="button"
                  class="ref-row"
                  (click)="jumpToCrossRef(r.bt, r.c)"
                >
                  <span>{{ r.bt }} {{ r.c }}:{{ r.v }}{{ r.e ? '-' + r.e : '' }}</span>
                  <span class="material-symbols-rounded">arrow_forward</span>
                </button>
              }
            </div>
          </div>
        </div>
      }

      @if (showStudy() && selectedVerse()) {
        <div class="modal-backdrop" (click)="showStudy.set(false)">
          <div class="modal-panel picker-modal" (click)="$event.stopPropagation()">
            <div class="drag-handle"></div>
            <div class="modal-head">
              <h2 class="font-display">
                Study & Lexicon · Verse {{ selectedVerse()!.verse }}
              </h2>
              <button type="button" class="icon-btn" (click)="showStudy.set(false)">
                <span class="material-symbols-rounded">close</span>
              </button>
            </div>
            <div class="study-list">
              @for (t of selectedStudyTerms(); track $index) {
                <div class="study-card">
                  <h3>{{ t.concept_name || t.english_name }}</h3>
                  @if (t.lemma) {
                    <p class="lemma">Lemma: {{ t.lemma }}</p>
                  }
                  @if (t.definition) {
                    <p>{{ t.definition }}</p>
                  }
                  @if (t.biblical_meaning) {
                    <p class="muted">{{ t.biblical_meaning }}</p>
                  }
                </div>
              }
            </div>
          </div>
        </div>
      }

      @if (showBookmarks()) {
        <div class="modal-backdrop" (click)="showBookmarks.set(false)">
          <div class="modal-panel picker-modal" (click)="$event.stopPropagation()">
            <div class="drag-handle"></div>
            <div class="modal-head">
              <h2 class="font-display">Bookmarks</h2>
              <button type="button" class="icon-btn" (click)="showBookmarks.set(false)">
                <span class="material-symbols-rounded">close</span>
              </button>
            </div>
            @if (bible.bookmarks().length === 0) {
              <p class="status-msg">No bookmarks yet. Tap any verse to bookmark it.</p>
            } @else {
              <div class="ref-list">
                @for (bm of bible.bookmarks(); track bm.key) {
                  <button
                    type="button"
                    class="ref-row bm-row"
                    (click)="jumpToBookmark(bm.bookNumber, bm.chapter)"
                  >
                    <div>
                      <strong>{{ bm.bookName }} {{ bm.chapter }}:{{ bm.verse }}</strong>
                      <p class="bm-text">{{ bm.text }}</p>
                    </div>
                  </button>
                }
              </div>
            }
          </div>
        </div>
      }

      @if (showNoteModal() && selectedVerse()) {
        <div class="modal-backdrop" (click)="showNoteModal.set(false)">
          <div class="modal-panel picker-modal" (click)="$event.stopPropagation()">
            <div class="drag-handle"></div>
            <div class="modal-head">
              <h2 class="font-display">
                Note · {{ bible.currentBook().name }} {{ bible.chapter() }}:{{ selectedVerse()!.verse }}
              </h2>
              <button type="button" class="icon-btn" (click)="showNoteModal.set(false)">
                <span class="material-symbols-rounded">close</span>
              </button>
            </div>
            <textarea
              class="note-textarea"
              rows="4"
              [(ngModel)]="noteDraft"
              placeholder="Write your study note..."
            ></textarea>
            <div class="modal-actions">
              <button type="button" class="pill-chip" (click)="showNoteModal.set(false)">
                Cancel
              </button>
              <button type="button" class="pill-chip active" (click)="saveNote()">
                Save Note
              </button>
            </div>
          </div>
        </div>
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
        height: 34px;
        padding: 0 10px 0 12px;
        border-radius: var(--radius-pill);
        background-color: var(--accent-soft);
        color: var(--accent);
        border: 1px solid var(--accent);
        font-weight: 700;
        font-size: 13px;
        display: inline-flex;
        align-items: center;
        gap: 2px;
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
        font-weight: 700;
        font-size: 16px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .book-btn:hover {
        background-color: var(--surface-variant);
      }

      .aa-btn {
        font-weight: 700;
        font-size: 16px;
      }

      .reader-body {
        padding-top: 16px;
        padding-bottom: 96px;
      }

      .summary-card {
        padding: 12px 14px;
        margin-bottom: 16px;
        border-radius: var(--radius-md);
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        font-size: 13px;
        color: var(--on-surface-muted);
      }

      .verses-flow {
        display: flex;
        flex-direction: column;
        gap: 6px;
      }

      .verse-row {
        padding: 6px 10px;
        border-radius: var(--radius-sm);
        cursor: pointer;
        transition: background-color 120ms ease;
      }

      .verse-row.selected {
        outline: 2px solid var(--accent);
      }

      .verse-num {
        font-size: 0.72em;
        font-weight: 700;
        color: var(--accent);
        margin-right: 8px;
        vertical-align: super;
      }

      .verse-mark {
        font-size: 16px;
        color: var(--accent);
        margin-left: 6px;
        vertical-align: middle;
      }

      .chapter-nav {
        margin-top: 28px;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
      }

      .chapter-indicator-btn {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        padding: 6px 12px;
        border-radius: var(--radius-pill);
        background-color: var(--surface);
        border: 1px solid var(--surface-border);
        font-size: 13px;
        font-weight: 600;
      }

      .verse-action-bar {
        position: fixed;
        left: 0;
        right: 0;
        bottom: calc(var(--shell-bottom-height) + 8px);
        z-index: 45;
        padding: 0 12px;
      }

      @media (min-width: 600px) {
        .verse-action-bar {
          left: var(--shell-rail-width);
          bottom: 16px;
        }
      }

      .action-inner {
        background-color: var(--surface-elevated);
        border: 1px solid var(--surface-border);
        border-radius: var(--radius-lg);
        padding: 10px 12px;
        box-shadow: 0 10px 28px rgba(0, 0, 0, 0.25);
        display: flex;
        flex-direction: column;
        gap: 8px;
      }

      .action-chips,
      .swatches {
        display: flex;
        align-items: center;
        gap: 8px;
        overflow-x: auto;
      }

      .hl-swatch {
        width: 24px;
        height: 24px;
        border-radius: var(--radius-pill);
        border: 1px solid var(--surface-border);
        flex-shrink: 0;
      }

      .picker-modal {
        padding: 12px 18px 18px;
        gap: 12px;
      }

      .drag-handle {
        width: 40px;
        height: 4px;
        border-radius: 2px;
        background-color: var(--on-surface-disabled);
        margin: 0 auto 4px;
      }

      .modal-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
      }

      .modal-head h2 {
        margin: 0;
        font-size: 18px;
      }

      .sheet-search {
        flex: 1;
        display: flex;
        align-items: center;
        gap: 8px;
        height: 40px;
        padding: 0 12px;
        border-radius: var(--radius-md);
        background-color: var(--bg);
        border: 1px solid var(--surface-border);
      }

      .sheet-search input {
        flex: 1;
        border: none;
        outline: none;
        background: transparent;
      }

      .version-list {
        display: flex;
        flex-direction: column;
        gap: 6px;
        max-height: 55dvh;
        overflow-y: auto;
      }

      .version-row {
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 10px 12px;
        border-radius: var(--radius-md);
        background-color: var(--bg);
        border: 1px solid var(--surface-border);
        text-align: left;
      }

      .version-row.active {
        border-color: var(--accent);
        background-color: var(--accent-soft);
      }

      .ver-badge {
        min-width: 64px;
        text-align: center;
        padding: 4px 8px;
        border-radius: var(--radius-sm);
        background-color: var(--surface-variant);
        font-size: 12px;
        font-weight: 700;
      }

      .ver-meta {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
      }

      .ver-check {
        color: var(--accent);
      }

      .picker-tabs {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        border-bottom: 1px solid var(--surface-border);
      }

      .picker-tab {
        padding: 10px 4px;
        font-size: 12px;
        font-weight: 700;
        letter-spacing: 0.5px;
        color: var(--on-surface-muted);
        border-bottom: 2px solid transparent;
      }

      .picker-tab.active {
        color: var(--accent);
        border-bottom-color: var(--accent);
      }

      .book-filters {
        display: flex;
        gap: 8px;
        flex-wrap: wrap;
        align-items: center;
      }

      .testament-chips {
        display: flex;
        gap: 6px;
      }

      .books-list {
        display: flex;
        flex-direction: column;
        gap: 6px;
        max-height: 52dvh;
        overflow-y: auto;
      }

      .book-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 11px 14px;
        border-radius: var(--radius-md);
        background-color: var(--bg);
        border: 1px solid var(--surface-border);
        font-size: 14px;
        font-weight: 500;
      }

      .book-row.active {
        border-color: var(--accent);
        background-color: var(--accent-soft);
        color: var(--accent);
        font-weight: 700;
      }

      .book-ch-count {
        font-size: 12px;
        color: var(--on-surface-muted);
      }

      .chapter-pick-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
      }

      .chapters-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(52px, 1fr));
        gap: 8px;
        max-height: 52dvh;
        overflow-y: auto;
      }

      .ch-cell {
        padding: 12px 6px;
        border-radius: var(--radius-sm);
        background-color: var(--surface-variant);
        text-align: center;
        font-size: 14px;
        font-weight: 600;
      }

      .ch-cell.active {
        background-color: var(--accent);
        color: var(--on-accent);
        font-weight: 700;
      }

      .appearance-section {
        display: flex;
        flex-direction: column;
        gap: 8px;
      }

      .label {
        font-size: 13px;
        font-weight: 600;
      }

      .chip-wrap {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
      }

      .ref-list,
      .study-list {
        display: flex;
        flex-direction: column;
        gap: 8px;
      }

      .ref-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 10px 12px;
        border-radius: var(--radius-sm);
        background-color: var(--surface-variant);
        text-align: left;
      }

      .bm-row {
        align-items: flex-start;
      }

      .bm-text {
        margin: 4px 0 0;
        font-size: 13px;
        color: var(--on-surface-muted);
      }

      .study-card {
        padding: 12px;
        border-radius: var(--radius-md);
        background-color: var(--surface-variant);
      }

      .study-card h3 {
        margin: 0 0 6px;
        font-size: 15px;
      }

      .lemma {
        font-size: 12px;
        color: var(--accent);
        font-weight: 600;
      }

      .muted {
        color: var(--on-surface-muted);
        font-size: 12px;
      }

      .note-textarea {
        width: 100%;
        padding: 10px 12px;
        border-radius: var(--radius-sm);
        border: 1px solid var(--surface-border);
        background-color: var(--bg);
      }

      .modal-actions {
        display: flex;
        justify-content: flex-end;
        gap: 8px;
      }

      .status-msg,
      .error-card {
        text-align: center;
        padding: 36px 16px;
        color: var(--on-surface-muted);
      }
    `,
  ],
})
export class BibleReaderComponent implements OnInit {
  private readonly releases = inject(ReleaseDataService);
  readonly bible = inject(BibleService);
  readonly appearance = inject(ReaderAppearanceService);

  readonly versions = BIBLE_VERSIONS;
  readonly fonts = READER_FONTS;
  readonly highlightColors = HIGHLIGHT_SWATCHES;

  readonly selectedVerse = signal<BibleVerse | null>(null);
  readonly showVersionPicker = signal<boolean>(false);
  readonly versionSearch = signal<string>('');
  readonly showBookPicker = signal<boolean>(false);
  readonly pickerTab = signal<'books' | 'chapters' | 'verses'>('books');
  readonly testamentFilter = signal<'all' | 'ot' | 'nt'>('all');
  readonly bookSearch = signal<string>('');
  readonly draftBook = signal<BibleBook>({
    bookNumber: 1,
    name: 'Genesis',
    chapters: 50,
  });
  readonly draftChapter = signal<number>(1);
  readonly pickerVerses = signal<BibleVerse[]>([]);
  readonly loadingPickerVerses = signal<boolean>(false);

  readonly showAppearance = signal<boolean>(false);
  readonly showCrossRefs = signal<boolean>(false);
  readonly showStudy = signal<boolean>(false);
  readonly showBookmarks = signal<boolean>(false);
  readonly showNoteModal = signal<boolean>(false);
  noteDraft = '';

  readonly activeVersionInfo = computed(
    () =>
      this.versions.find((v) => v.id === this.bible.version()) ?? {
        id: this.bible.version(),
        label: this.bible.version().toUpperCase(),
        fullName: this.bible.version().toUpperCase(),
        language: '',
      },
  );

  readonly filteredVersions = computed(() => {
    const q = this.versionSearch().trim().toLowerCase();
    if (!q) return this.versions;
    return this.versions.filter(
      (v) =>
        v.label.toLowerCase().includes(q) ||
        v.fullName.toLowerCase().includes(q) ||
        v.language.toLowerCase().includes(q),
    );
  });

  readonly filteredBooks = computed(() => {
    const q = this.bookSearch().trim().toLowerCase();
    const t = this.testamentFilter();
    return this.bible.books().filter((b) => {
      if (t === 'ot' && b.bookNumber > 39) return false;
      if (t === 'nt' && b.bookNumber < 40) return false;
      if (q && !b.name.toLowerCase().includes(q)) return false;
      return true;
    });
  });

  readonly selectedCrossRefs = computed(() => {
    const v = this.selectedVerse()?.verse;
    if (!v) return [];
    return this.bible.crossRefs().find((x) => x.v === v)?.refs ?? [];
  });

  readonly selectedStudyTerms = computed(() => {
    const v = this.selectedVerse()?.verse;
    if (!v) return [];
    return (
      this.bible
        .study()
        ?.terms?.filter((t) => t.reference?.verse === v) ?? []
    );
  });

  ngOnInit(): void {
    void this.bible.init();
  }

  openVersionPicker(): void {
    this.versionSearch.set('');
    this.showVersionPicker.set(true);
  }

  selectVersion(versionId: string): void {
    this.showVersionPicker.set(false);
    this.selectedVerse.set(null);
    void this.bible.loadVersion(versionId);
  }

  openBookPicker(tab: 'books' | 'chapters' | 'verses' = 'books'): void {
    this.draftBook.set(this.bible.currentBook());
    this.draftChapter.set(this.bible.chapter());
    this.bookSearch.set('');
    this.pickerTab.set(tab);
    this.showBookPicker.set(true);
    if (tab === 'verses') {
      void this.loadPickerVerses();
    }
  }

  pickBook(b: BibleBook): void {
    this.draftBook.set(b);
    this.draftChapter.set(1);
    this.pickerTab.set('chapters');
  }

  pickChapter(ch: number): void {
    this.draftChapter.set(ch);
    this.openVersesTab();
  }

  openVersesTab(): void {
    this.pickerTab.set('verses');
    void this.loadPickerVerses();
  }

  private async loadPickerVerses(): Promise<void> {
    const b = this.draftBook().bookNumber;
    const ch = this.draftChapter();
    if (b === this.bible.bookNumber() && ch === this.bible.chapter()) {
      this.pickerVerses.set(this.bible.verses());
      return;
    }
    this.loadingPickerVerses.set(true);
    try {
      const verses = await this.releases.getJson<BibleVerse[]>(
        `bibles/${this.bible.version()}/${b}/${ch}.json`,
      );
      this.pickerVerses.set(verses);
    } catch {
      this.pickerVerses.set([]);
    } finally {
      this.loadingPickerVerses.set(false);
    }
  }

  async applySelection(
    bookNum: number,
    ch: number,
    verseNum?: number,
  ): Promise<void> {
    this.showBookPicker.set(false);
    this.selectedVerse.set(null);
    await this.bible.loadChapter(bookNum, ch);
    if (verseNum) {
      const target = this.bible.verses().find((v) => v.verse === verseNum);
      if (target) this.selectedVerse.set(target);
      setTimeout(() => {
        document
          .getElementById(`verse-${verseNum}`)
          ?.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }, 60);
    }
  }

  chapterNumbers(count: number): number[] {
    return Array.from({ length: count }, (_, i) => i + 1);
  }

  toggleSelectVerse(v: BibleVerse): void {
    this.selectedVerse.set(
      this.selectedVerse()?.verse === v.verse ? null : v,
    );
  }

  highlightFor(verseNum: number): string {
    const color = this.bible.highlights()[this.bible.verseKey(verseNum)];
    if (!color) return 'transparent';
    return `${color}55`;
  }

  noteFor(verseNum: number): string | undefined {
    return this.bible.notes()[this.bible.verseKey(verseNum)];
  }

  copySelected(): void {
    const v = this.selectedVerse();
    if (!v) return;
    const text = `${this.bible.currentBook().name} ${this.bible.chapter()}:${v.verse} (${this.bible.version().toUpperCase()}) — ${v.text}`;
    void navigator.clipboard?.writeText(text);
  }

  openNoteEditor(): void {
    const v = this.selectedVerse();
    if (!v) return;
    this.noteDraft = this.noteFor(v.verse) ?? '';
    this.showNoteModal.set(true);
  }

  saveNote(): void {
    const v = this.selectedVerse();
    if (!v) return;
    this.bible.saveNote(v.verse, this.noteDraft);
    this.showNoteModal.set(false);
  }

  jumpToCrossRef(abbrev: string, ch: number): void {
    this.showCrossRefs.set(false);
    this.selectedVerse.set(null);
    this.bible.jumpToAbbrev(abbrev, ch);
  }

  jumpToBookmark(bookNum: number, ch: number): void {
    this.showBookmarks.set(false);
    this.selectedVerse.set(null);
    void this.bible.loadChapter(bookNum, ch);
  }
}
