import { Injectable, signal } from '@angular/core';

export interface BookHighlight {
  key: string; // `${bookId}:${chapterIndex}:${line}`
  bookId: string;
  chapterIndex: number;
  line: number;
  text: string;
  color: string;
  note?: string;
  createdAt: string;
}

export interface BookBookmark {
  key: string; // `${bookId}:${chapterIndex}`
  bookId: string;
  chapterIndex: number;
  chapterTitle: string;
  createdAt: string;
}

const KEY_HIGHLIGHTS = 'book_highlights';
const KEY_BOOKMARKS = 'book_bookmarks';

@Injectable({ providedIn: 'root' })
export class BookHighlightsService {
  readonly highlights = signal<Record<string, BookHighlight>>(
    this.readMap<BookHighlight>(KEY_HIGHLIGHTS),
  );
  readonly bookmarks = signal<Record<string, BookBookmark>>(
    this.readMap<BookBookmark>(KEY_BOOKMARKS),
  );

  makeKey(bookId: string, chapterIndex: number, line: number): string {
    return `${bookId}:${chapterIndex}:${line}`;
  }

  colorFor(bookId: string, chapterIndex: number, line: number): string | null {
    return this.highlights()[this.makeKey(bookId, chapterIndex, line)]?.color ?? null;
  }

  noteFor(bookId: string, chapterIndex: number, line: number): string {
    return this.highlights()[this.makeKey(bookId, chapterIndex, line)]?.note ?? '';
  }

  forBook(bookId: string): BookHighlight[] {
    return Object.values(this.highlights())
      .filter((h) => h.bookId === bookId)
      .sort((a, b) =>
        a.chapterIndex !== b.chapterIndex
          ? a.chapterIndex - b.chapterIndex
          : a.line - b.line,
      );
  }

  setHighlight(
    bookId: string,
    chapterIndex: number,
    line: number,
    text: string,
    color: string | null,
    note?: string,
  ): void {
    const key = this.makeKey(bookId, chapterIndex, line);
    const next = { ...this.highlights() };
    const existing = next[key];
    if (color || (note && note.trim())) {
      next[key] = {
        key,
        bookId,
        chapterIndex,
        line,
        text,
        color: color ?? existing?.color ?? '#FEF08A',
        note: note !== undefined ? note.trim() || undefined : existing?.note,
        createdAt: existing?.createdAt ?? new Date().toISOString(),
      };
    } else {
      delete next[key];
    }
    this.highlights.set(next);
    this.saveMap(KEY_HIGHLIGHTS, next);
  }

  saveNote(
    bookId: string,
    chapterIndex: number,
    line: number,
    text: string,
    note: string,
  ): void {
    const existing = this.highlights()[this.makeKey(bookId, chapterIndex, line)];
    this.setHighlight(
      bookId,
      chapterIndex,
      line,
      text,
      existing?.color ?? '#FEF08A',
      note,
    );
  }

  isBookmarked(bookId: string, chapterIndex: number): boolean {
    return Boolean(this.bookmarks()[`${bookId}:${chapterIndex}`]);
  }

  bookmarksForBook(bookId: string): BookBookmark[] {
    return Object.values(this.bookmarks())
      .filter((b) => b.bookId === bookId)
      .sort((a, b) => a.chapterIndex - b.chapterIndex);
  }

  toggleBookmark(bookId: string, chapterIndex: number, chapterTitle: string): void {
    const key = `${bookId}:${chapterIndex}`;
    const next = { ...this.bookmarks() };
    if (next[key]) {
      delete next[key];
    } else {
      next[key] = {
        key,
        bookId,
        chapterIndex,
        chapterTitle,
        createdAt: new Date().toISOString(),
      };
    }
    this.bookmarks.set(next);
    this.saveMap(KEY_BOOKMARKS, next);
  }

  private readMap<T>(storageKey: string): Record<string, T> {
    try {
      const raw = localStorage.getItem(storageKey);
      return raw ? (JSON.parse(raw) as Record<string, T>) : {};
    } catch {
      return {};
    }
  }

  private saveMap<T>(storageKey: string, map: Record<string, T>): void {
    try {
      localStorage.setItem(storageKey, JSON.stringify(map));
    } catch {
      // ignore
    }
  }
}
