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
const KNOWN_LANG_PREFIXES = ['ta', 'hi', 'te', 'kn', 'ml', 'de'] as const;

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

  /**
   * Resolves a book's language code from explicit `lang`, catalog metadata,
   * or bookId prefix (e.g. `ta_...`, `hi_...`, `te_...`, `kn_...`, `ml_...`, `de_...`).
   */
  inferBookLanguage(bookId: string, lang?: string): string {
    if (lang && lang.trim().length > 0 && lang.trim().toLowerCase() !== 'all') {
      return lang.trim().toLowerCase();
    }
    const cleanId = (bookId ?? '').trim();
    const match = this.catalog().find((b) => b.id === cleanId);
    if (match?.lang && match.lang.trim().length > 0) {
      return match.lang.trim().toLowerCase();
    }
    for (const prefix of KNOWN_LANG_PREFIXES) {
      if (cleanId.startsWith(`${prefix}_`)) {
        return prefix;
      }
    }
    return 'en';
  }

  coverUrls(coverFile?: string): string[] {
    const clean = (coverFile ?? '').trim();
    if (!clean) return [];
    return this.releases.urlsFor(`books/covers/${clean}`);
  }

  coverUrl(coverFile?: string): string {
    return this.coverUrls(coverFile)[0] ?? '';
  }

  /**
   * Returns all candidate URLs (both jsDelivr CDN and raw GitHub fallback mirrors)
   * for a book page image, checking the language-specific directory first for non-English books.
   */
  pageImageUrls(bookId: string, fileName: string, lang?: string): string[] {
    const clean = (fileName ?? '').trim();
    if (!clean || !bookId) return [];
    const resolvedLang = this.inferBookLanguage(bookId, lang);
    const urls: string[] = [];
    if (resolvedLang !== 'en') {
      urls.push(
        ...this.releases.urlsFor(`books/${resolvedLang}/${bookId}/pages/${clean}`),
      );
    }
    urls.push(...this.releases.urlsFor(`books/${bookId}/pages/${clean}`));
    urls.push(...this.releases.urlsFor(`books/en/${bookId}/pages/${clean}`));
    return Array.from(new Set(urls));
  }

  async fetchToc(bookId: string, lang?: string): Promise<BookToc> {
    const resolvedLang = this.inferBookLanguage(bookId, lang);
    const candidatePaths =
      resolvedLang !== 'en'
        ? [
            `books/${resolvedLang}/${bookId}/toc.json`,
            `books/${bookId}/toc.json`,
            `books/en/${bookId}/toc.json`,
          ]
        : [
            `books/${bookId}/toc.json`,
            `books/en/${bookId}/toc.json`,
          ];

    for (const path of candidatePaths) {
      try {
        return await this.releases.getJson<BookToc>(path);
      } catch {
        // try next candidate path
      }
    }
    throw new Error('Table of contents not found');
  }

  async fetchChapter(
    bookId: string,
    chapterIndex: number,
    lang?: string,
    totalChapters?: number,
    options?: { skipPreload?: boolean },
  ): Promise<BookLine[]> {
    const resolvedLang = this.inferBookLanguage(bookId, lang);
    const candidatePaths: Array<{ path: string; langUsed?: string }> =
      resolvedLang !== 'en'
        ? [
            {
              path: `books/${resolvedLang}/${bookId}/chapters/${chapterIndex}.json`,
              langUsed: resolvedLang,
            },
            {
              path: `books/${bookId}/chapters/${chapterIndex}.json`,
              langUsed: undefined,
            },
          ]
        : [
            {
              path: `books/${bookId}/chapters/${chapterIndex}.json`,
              langUsed: undefined,
            },
            {
              path: `books/en/${bookId}/chapters/${chapterIndex}.json`,
              langUsed: 'en',
            },
          ];

    for (const candidate of candidatePaths) {
      try {
        const lines = await this.releases.getJson<BookLine[]>(candidate.path);
        if (!options?.skipPreload) {
          this.preloadBookInBackground(
            bookId,
            chapterIndex,
            lines,
            totalChapters,
            candidate.langUsed,
          );
        }
        return lines;
      } catch {
        // try next candidate path
      }
    }
    throw new Error('Chapter not found');
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
