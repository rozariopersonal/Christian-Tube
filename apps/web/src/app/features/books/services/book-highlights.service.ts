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

export interface TextHighlightRange {
  id: string;
  scopeKey: string; // `book:${bookId}:${chapterIndex}` | `article:${id}:${lang}`
  line: number;
  start: number;
  end: number;
  text: string;
  color: string;
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
const KEY_TEXT_RANGES = 'reader_text_highlights';

@Injectable({ providedIn: 'root' })
export class BookHighlightsService {
  readonly highlights = signal<Record<string, BookHighlight>>(
    this.readMap<BookHighlight>(KEY_HIGHLIGHTS),
  );
  readonly bookmarks = signal<Record<string, BookBookmark>>(
    this.readMap<BookBookmark>(KEY_BOOKMARKS),
  );
  readonly textRanges = signal<Record<string, TextHighlightRange[]>>(
    this.readMap<TextHighlightRange[]>(KEY_TEXT_RANGES),
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

  rangesForLine(scopeKey: string, line: number): TextHighlightRange[] {
    return (this.textRanges()[scopeKey] ?? []).filter((r) => r.line === line);
  }

  addRange(
    scopeKey: string,
    line: number,
    start: number,
    end: number,
    text: string,
    color: string,
  ): void {
    if (end <= start) return;
    const all = { ...this.textRanges() };
    const existing = (all[scopeKey] ?? []).filter(
      (r) => r.line !== line || r.end <= start || r.start >= end,
    );
    existing.push({
      id: `${scopeKey}:${line}:${start}-${end}`,
      scopeKey,
      line,
      start,
      end,
      text,
      color,
      createdAt: new Date().toISOString(),
    });
    existing.sort((a, b) =>
      a.line !== b.line ? a.line - b.line : a.start - b.start,
    );
    all[scopeKey] = existing;
    this.textRanges.set(all);
    this.saveMap(KEY_TEXT_RANGES, all);
  }

  clearRange(scopeKey: string, line: number, start: number, end: number): void {
    const all = { ...this.textRanges() };
    const current = all[scopeKey] ?? [];
    const next = current.filter(
      (r) => r.line !== line || r.end <= start || r.start >= end,
    );
    if (next.length === 0) {
      delete all[scopeKey];
    } else {
      all[scopeKey] = next;
    }
    this.textRanges.set(all);
    this.saveMap(KEY_TEXT_RANGES, all);
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
