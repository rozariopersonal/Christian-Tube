import { Injectable, signal } from '@angular/core';

export interface BookHighlight {
  key: string; // `${bookId}:${chapterIndex}:${line}`
  bookId: string;
  chapterIndex: number;
  line: number;
  text: string;
  color: string;
  createdAt: string;
}

const KEY_HIGHLIGHTS = 'book_highlights';

@Injectable({ providedIn: 'root' })
export class BookHighlightsService {
  readonly highlights = signal<Record<string, BookHighlight>>(this.readAll());

  makeKey(bookId: string, chapterIndex: number, line: number): string {
    return `${bookId}:${chapterIndex}:${line}`;
  }

  colorFor(bookId: string, chapterIndex: number, line: number): string | null {
    return this.highlights()[this.makeKey(bookId, chapterIndex, line)]?.color ?? null;
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
  ): void {
    const key = this.makeKey(bookId, chapterIndex, line);
    const next = { ...this.highlights() };
    if (color) {
      next[key] = {
        key,
        bookId,
        chapterIndex,
        line,
        text,
        color,
        createdAt: new Date().toISOString(),
      };
    } else {
      delete next[key];
    }
    this.highlights.set(next);
    this.saveAll(next);
  }

  private readAll(): Record<string, BookHighlight> {
    try {
      const raw = localStorage.getItem(KEY_HIGHLIGHTS);
      return raw ? (JSON.parse(raw) as Record<string, BookHighlight>) : {};
    } catch {
      return {};
    }
  }

  private saveAll(map: Record<string, BookHighlight>): void {
    try {
      localStorage.setItem(KEY_HIGHLIGHTS, JSON.stringify(map));
    } catch {
      // ignore
    }
  }
}
