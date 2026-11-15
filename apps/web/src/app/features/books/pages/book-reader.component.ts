import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute } from '@angular/router';
import {
  READER_FONTS,
  ReaderAppearanceService,
} from '../../../core/services/reader-appearance.service';
import { BookLine, BookToc } from '../models/book.model';
import { BooksService } from '../services/books.service';

@Component({
  selector: 'app-book-reader',
  standalone: true,
  imports: [FormsModule],
  template: `
    <div class="book-reader-page">
      <header class="reader-bar">
        <div class="bar-inner max-width-box">
          <button type="button" class="toc-btn" (click)="showToc.set(true)">
            <span class="material-symbols-rounded">toc</span>
            <span class="book-name">{{ toc()?.title || 'Book Reader' }}</span>
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
      </header>

      <div class="reader-content max-width-box">
        @if (loading()) {
          <p class="status-msg">Loading chapter...</p>
        } @else if (error()) {
          <p class="status-msg">{{ error() }}</p>
        } @else {
          <article
            class="chapter-body"
            [style.font-family]="appearance.activeFont().cssFamily"
            [style.font-size.px]="appearance.fontSize()"
            [style.line-height]="appearance.lineHeight()"
          >
            @for (line of lines(); track $index) {
              @if (line.isHeading) {
                <h2 class="chapter-heading">{{ line.text }}</h2>
              } @else {
                <p class="chapter-para">{{ line.text }}</p>
              }
            }
          </article>

          <nav class="chapter-nav">
            <button
              type="button"
              class="pill-chip"
              [disabled]="chapterIndex() <= 1"
              (click)="loadChapter(chapterIndex() - 1)"
            >
              <span class="material-symbols-rounded">chevron_left</span>
              Previous
            </button>
            <span class="ch-status">
              Chapter {{ chapterIndex() }} / {{ toc()?.chapters?.length || 1 }}
            </span>
            <button
              type="button"
              class="pill-chip"
              [disabled]="chapterIndex() >= (toc()?.chapters?.length || 1)"
              (click)="loadChapter(chapterIndex() + 1)"
            >
              Next
              <span class="material-symbols-rounded">chevron_right</span>
            </button>
          </nav>
        }
      </div>

      @if (showToc() && toc()) {
        <div class="modal-backdrop" (click)="showToc.set(false)">
          <div class="modal-panel toc-modal" (click)="$event.stopPropagation()">
            <div class="modal-head">
              <h2 class="font-display">Table of Contents</h2>
              <button type="button" class="icon-btn" (click)="showToc.set(false)">
                <span class="material-symbols-rounded">close</span>
              </button>
            </div>
            <div class="toc-list">
              @for (ch of toc()!.chapters; track ch.chapterIndex) {
                <button
                  type="button"
                  class="toc-row"
                  [class.active]="ch.chapterIndex === chapterIndex()"
                  (click)="selectChapter(ch.chapterIndex)"
                >
                  <span>{{ ch.chapterIndex }}. {{ ch.title }}</span>
                </button>
              }
            </div>
          </div>
        </div>
      }

      @if (showAppearance()) {
        <div class="modal-backdrop" (click)="showAppearance.set(false)">
          <div class="modal-panel toc-modal" (click)="$event.stopPropagation()">
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
    </div>
  `,
  styles: [
    `
      .reader-bar {
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
        gap: 12px;
      }

      .toc-btn {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        min-width: 0;
        font-weight: 700;
        font-size: 16px;
      }

      .book-name {
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .aa-btn {
        font-weight: 700;
        font-size: 16px;
      }

      .reader-content {
        padding-top: 20px;
        padding-bottom: 40px;
        max-width: 780px;
      }

      .chapter-heading {
        margin: 0 0 18px;
        font-size: 1.35em;
        font-weight: 700;
        line-height: 1.3;
      }

      .chapter-para {
        margin: 0 0 1em;
      }

      .chapter-nav {
        margin-top: 32px;
        padding-top: 16px;
        border-top: 1px solid var(--surface-border);
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
      }

      .ch-status {
        font-size: 13px;
        color: var(--on-surface-muted);
        font-weight: 600;
      }

      .toc-modal {
        padding: 18px;
        gap: 14px;
      }

      .modal-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
      }

      .modal-head h2 {
        margin: 0;
        font-size: 18px;
      }

      .toc-list {
        display: flex;
        flex-direction: column;
        gap: 6px;
      }

      .toc-row {
        padding: 10px 12px;
        border-radius: var(--radius-sm);
        background-color: var(--surface-variant);
        text-align: left;
        font-size: 14px;
      }

      .toc-row.active {
        background-color: var(--accent);
        color: var(--on-accent);
        font-weight: 600;
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

      .status-msg {
        text-align: center;
        padding: 40px 0;
        color: var(--on-surface-muted);
      }
    `,
  ],
})
export class BookReaderComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly booksService = inject(BooksService);
  readonly appearance = inject(ReaderAppearanceService);

  readonly fonts = READER_FONTS;
  readonly toc = signal<BookToc | null>(null);
  readonly lines = signal<BookLine[]>([]);
  readonly chapterIndex = signal<number>(1);
  readonly loading = signal<boolean>(true);
  readonly error = signal<string | null>(null);
  readonly showToc = signal<boolean>(false);
  readonly showAppearance = signal<boolean>(false);

  private bookId = '';
  private bookLang?: string;

  ngOnInit(): void {
    void this.booksService.loadCatalog();
    this.route.paramMap.subscribe((params) => {
      const id = params.get('id');
      if (id) void this.openBook(id);
    });
  }

  async openBook(bookId: string): Promise<void> {
    this.bookId = bookId;
    this.loading.set(true);
    this.error.set(null);
    const catalogItem = this.booksService
      .catalog()
      .find((b) => b.id === bookId);
    this.bookLang = catalogItem?.lang;

    try {
      const toc = await this.booksService.fetchToc(bookId, this.bookLang);
      this.toc.set(toc);
      const saved = this.booksService.progressMap()[bookId]?.chapterIndex ?? 1;
      await this.loadChapter(saved);
    } catch (err) {
      this.error.set(
        err instanceof Error ? err.message : 'Unable to open book',
      );
      this.loading.set(false);
    }
  }

  async loadChapter(ch: number): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
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
      window.scrollTo({ top: 0, behavior: 'smooth' });
    } catch (err) {
      this.error.set(
        err instanceof Error ? err.message : 'Unable to load chapter',
      );
    } finally {
      this.loading.set(false);
    }
  }

  selectChapter(ch: number): void {
    this.showToc.set(false);
    void this.loadChapter(ch);
  }
}
