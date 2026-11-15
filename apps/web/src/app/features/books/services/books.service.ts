import { Injectable, inject, signal } from '@angular/core';
import { ReleaseDataService } from '../../../core/api/release-data.service';
import {
  BookCatalogItem,
  BookLine,
  BookReadingProgress,
  BookToc,
} from '../models/book.model';

const KEY_BOOK_PROGRESS = 'books_reading_progress';

@Injectable({ providedIn: 'root' })
export class BooksService {
  private readonly releases = inject(ReleaseDataService);

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
  ): Promise<BookLine[]> {
    try {
      return await this.releases.getJson<BookLine[]>(
        `books/${bookId}/chapters/${chapterIndex}.json`,
      );
    } catch {
      if (lang) {
        return await this.releases.getJson<BookLine[]>(
          `books/${lang}/${bookId}/chapters/${chapterIndex}.json`,
        );
      }
      throw new Error('Chapter not found');
    }
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
