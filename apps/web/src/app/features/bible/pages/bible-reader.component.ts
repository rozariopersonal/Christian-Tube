import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
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
            <select
              class="version-pill"
              [ngModel]="bible.version()"
              (ngModelChange)="onVersionChange($event)"
              aria-label="Bible Version"
            >
              @for (v of versions; track v.id) {
                <option [value]="v.id">{{ v.label }}</option>
              }
            </select>

            <button
              type="button"
              class="book-btn"
              (click)="openBookPicker()"
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
            <span class="chapter-indicator">
              {{ bible.currentBook().name }} {{ bible.chapter() }}
            </span>
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

      @if (showBookPicker()) {
        <div class="modal-backdrop" (click)="showBookPicker.set(false)">
          <div class="modal-panel picker-modal" (click)="$event.stopPropagation()">
            <div class="modal-head">
              <h2 class="font-display">Select Book & Chapter</h2>
              <button type="button" class="icon-btn" (click)="showBookPicker.set(false)">
                <span class="material-symbols-rounded">close</span>
              </button>
            </div>

            @if (!pickedBook()) {
              <div class="books-grid">
                @for (b of bible.books(); track b.bookNumber) {
                  <button
                    type="button"
                    class="book-item"
                    [class.active]="b.bookNumber === bible.bookNumber()"
                    (click)="pickedBook.set(b)"
                  >
                    {{ b.name }}
                  </button>
                }
              </div>
            } @else {
              <div class="chapter-pick-head">
                <button type="button" class="pill-chip" (click)="pickedBook.set(null)">
                  All Books
                </button>
                <strong>{{ pickedBook()!.name }}</strong>
              </div>
              <div class="chapters-grid">
                @for (ch of chapterNumbers(pickedBook()!.chapters); track ch) {
                  <button
                    type="button"
                    class="ch-cell"
                    [class.active]="pickedBook()!.bookNumber === bible.bookNumber() && ch === bible.chapter()"
                    (click)="selectBookChapter(pickedBook()!.bookNumber, ch)"
                  >
                    {{ ch }}
                  </button>
                }
              </div>
            }
          </div>
        </div>
      }

      @if (showAppearance()) {
        <div class="modal-backdrop" (click)="showAppearance.set(false)">
          <div class="modal-panel picker-modal" (click)="$event.stopPropagation()">
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
        padding: 0 10px;
        border-radius: var(--radius-pill);
        background-color: var(--accent-soft);
        color: var(--accent);
        border: 1px solid var(--accent);
        font-weight: 700;
        font-size: 13px;
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

      .chapter-indicator {
        font-size: 13px;
        font-weight: 600;
        color: var(--on-surface-muted);
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
        padding: 18px;
        gap: 14px;
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

      .books-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
        gap: 8px;
      }

      .book-item,
      .ch-cell {
        padding: 10px;
        border-radius: var(--radius-sm);
        background-color: var(--surface-variant);
        text-align: left;
        font-size: 13px;
        font-weight: 500;
      }

      .book-item.active,
      .ch-cell.active {
        background-color: var(--accent);
        color: var(--on-accent);
        font-weight: 700;
      }

      .chapter-pick-head {
        display: flex;
        align-items: center;
        gap: 12px;
      }

      .chapters-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(52px, 1fr));
        gap: 8px;
      }

      .ch-cell {
        text-align: center;
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
        font-size: 13px;
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
  readonly bible = inject(BibleService);
  readonly appearance = inject(ReaderAppearanceService);

  readonly versions = BIBLE_VERSIONS;
  readonly fonts = READER_FONTS;
  readonly highlightColors = HIGHLIGHT_SWATCHES;

  readonly selectedVerse = signal<BibleVerse | null>(null);
  readonly showBookPicker = signal<boolean>(false);
  readonly pickedBook = signal<BibleBook | null>(null);
  readonly showAppearance = signal<boolean>(false);
  readonly showCrossRefs = signal<boolean>(false);
  readonly showStudy = signal<boolean>(false);
  readonly showBookmarks = signal<boolean>(false);
  readonly showNoteModal = signal<boolean>(false);
  noteDraft = '';

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

  onVersionChange(versionId: string): void {
    this.selectedVerse.set(null);
    void this.bible.loadVersion(versionId);
  }

  openBookPicker(): void {
    this.pickedBook.set(null);
    this.showBookPicker.set(true);
  }

  chapterNumbers(count: number): number[] {
    return Array.from({ length: count }, (_, i) => i + 1);
  }

  selectBookChapter(bookNum: number, ch: number): void {
    this.showBookPicker.set(false);
    this.selectedVerse.set(null);
    void this.bible.loadChapter(bookNum, ch);
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
