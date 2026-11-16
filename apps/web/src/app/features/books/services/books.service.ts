import { Injectable, inject, signal } from '@angular/core';
import { ReleaseDataService } from '../../../core/api/release-data.service';
import {
  BookCatalogItem,
  BookLine,
  BookReadingProgress,
  BookToc,
} from '../models/book.model';

const KEY_BOOK_PROGRESS = 'books_reading_progress';
const MAX_BOOK_PRELOAD_BYTES = 1_048_576; // 1 MB

@Injectable({ providedIn: 'root' })
export class BooksService {
  private readonly releases = inject(ReleaseDataService);
  private activePreloadBookId: string | null = null;

  readonly catalog = signal<BookCatalogItem[]>([]);
  readonly loading = signal<boolean>(false);
  readonly error = signal<string | null>(null);
  readonly progressMap = signal<Record<string, BookReadingProgress>>(
    this.readProgress(),
  );

  async loadCatalog(): Promise<void> {
    if (this.catalog().length > 0) return;
    this.loading.set(true);
    this.error.set(null);
    try {
      const list = await this.releases.getJson<BookCatalogItem[]>(
        'books/catalog.json',
      );
      this.catalog.set(Array.isArray(list) ? list : []);
    } catch (err) {
      this.error.set(
        err instanceof Error ? err.message : 'Unable to load books catalog',
      );
    } finally {
      this.loading.set(false);
    }
  }

  coverUrl(coverFile?: string): string {
    if (!coverFile) return '';
    return this.releases.assetUrl(`books/covers/${coverFile}`);
  }

  async fetchToc(bookId: string, lang?: string): Promise<BookToc> {
    try {
      return await this.releases.getJson<BookToc>(`books/${bookId}/toc.json`);
    } catch {
      if (lang) {
        return await this.releases.getJson<BookToc>(
          `books/${lang}/${bookId}/toc.json`,
        );
      }
      throw new Error('Table of contents not found');
    }
  }

  async fetchChapter(
    bookId: string,
    chapterIndex: number,
    lang?: string,
    totalChapters?: number,
  ): Promise<BookLine[]> {
    let lines: BookLine[];
    try {
      lines = await this.releases.getJson<BookLine[]>(
        `books/${bookId}/chapters/${chapterIndex}.json`,
      );
      this.preloadBookInBackground(bookId, chapterIndex, lines, totalChapters);
      return lines;
    } catch {
      if (lang) {
        lines = await this.releases.getJson<BookLine[]>(
          `books/${lang}/${bookId}/chapters/${chapterIndex}.json`,
        );
        this.preloadBookInBackground(
          bookId,
          chapterIndex,
          lines,
          totalChapters,
          lang,
        );
        return lines;
      }
      throw new Error('Chapter not found');
    }
  }

  private preloadBookInBackground(
    bookId: string,
    currentChapter: number,
    currentLines: BookLine[],
    totalChapters?: number,
    lang?: string,
  ): void {
    this.activePreloadBookId = bookId;
    const prefix = lang ? `books/${lang}/${bookId}` : `books/${bookId}`;
    const total = totalChapters ?? currentChapter + 1;
    const ordered: number[] = [];

    if (currentChapter < total) ordered.push(currentChapter + 1);
    if (currentChapter > 1) ordered.push(currentChapter - 1);
    for (let ch = currentChapter + 2; ch <= total; ch++) {
      ordered.push(ch);
    }
    for (let ch = currentChapter - 2; ch >= 1; ch--) {
      ordered.push(ch);
    }

    const paths = ordered.map((ch) => `${prefix}/chapters/${ch}.json`);
    void this.releases.prefetchBatch(paths, {
      concurrency: 3,
      maxTotalBytes: MAX_BOOK_PRELOAD_BYTES,
      initialBytes: JSON.stringify(currentLines).length,
      shouldContinue: () => this.activePreloadBookId === bookId,
    });
  }

  saveProgress(progress: BookReadingProgress): void {
    const next = { ...this.progressMap(), [progress.bookId]: progress };
    this.progressMap.set(next);
    try {
      localStorage.setItem(KEY_BOOK_PROGRESS, JSON.stringify(next));
    } catch {
      // ignore
    }
  }

  recentBooks(): BookReadingProgress[] {
    return Object.values(this.progressMap()).sort((a, b) =>
      b.updatedAt.localeCompare(a.updatedAt),
    );
  }

  private readProgress(): Record<string, BookReadingProgress> {
    try {
      const raw = localStorage.getItem(KEY_BOOK_PROGRESS);
      return raw ? (JSON.parse(raw) as Record<string, BookReadingProgress>) : {};
    } catch {
      return {};
    }
  }
}
