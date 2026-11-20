import { Injectable, effect, inject, signal } from '@angular/core';
import { AuthService } from '../../../core/auth/auth.service';
import {
  SyncUserItem,
  UserItemsSyncService,
} from '../../../core/services/user-items-sync.service';

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
  note?: string;
  createdAt: string;
  updatedAt?: number;
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
  private readonly auth = inject(AuthService);
  private readonly itemsSync = inject(UserItemsSyncService);

  readonly highlights = signal<Record<string, BookHighlight>>({});
  readonly bookmarks = signal<Record<string, BookBookmark>>({});
  readonly textRanges = signal<Record<string, TextHighlightRange[]>>({});

  private syncedUserId: string | null = null;

  constructor() {
    this.reloadFromUserCache();

    effect(() => {
      const uid = this.auth.currentUser()?.id ?? null;
      if (uid !== this.syncedUserId) {
        this.syncedUserId = uid;
        this.reloadFromUserCache();
      }
    });

    effect(() => {
      const remote = this.itemsSync.remoteItems();
      if (!this.auth.isAuthenticated()) return;
      this.applyRemoteItems(remote);
    });
  }

  private reloadFromUserCache(): void {
    this.highlights.set(this.readMap<BookHighlight>(KEY_HIGHLIGHTS));
    this.bookmarks.set(this.readMap<BookBookmark>(KEY_BOOKMARKS));
    this.textRanges.set(this.readMap<TextHighlightRange[]>(KEY_TEXT_RANGES));
  }

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
    if (this.auth.isAuthenticated()) {
      const item = next[key];
      this.itemsSync.enqueueItem({
        id: `book_hl:${key}`,
        itemType: 'highlight',
        feature: 'book',
        targetId: key,
        book: bookId,
        chapter: chapterIndex,
        verseStart: line,
        color: item?.color ?? null,
        text,
        contextText: item?.note ?? null,
        deleted: !item,
      });
    }
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
    if (this.auth.isAuthenticated()) {
      const bm = next[key];
      this.itemsSync.enqueueItem({
        id: `book_bm:${key}`,
        itemType: 'bookmark',
        feature: 'book',
        targetId: key,
        book: bookId,
        chapter: chapterIndex,
        text: chapterTitle,
        deleted: !bm,
      });
    }
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
    note?: string,
  ): void {
    if (end <= start) return;
    const all = { ...this.textRanges() };
    const removed = (all[scopeKey] ?? []).filter(
      (r) => r.line === line && !(r.end <= start || r.start >= end),
    );
    const existing = (all[scopeKey] ?? []).filter(
      (r) => r.line !== line || r.end <= start || r.start >= end,
    );
    const created: TextHighlightRange = {
      id: `${scopeKey}:${line}:${start}-${end}`,
      scopeKey,
      line,
      start,
      end,
      text,
      color,
      note: note?.trim() || undefined,
      createdAt: new Date().toISOString(),
      updatedAt: Date.now(),
    };
    existing.push(created);
    existing.sort((a, b) =>
      a.line !== b.line ? a.line - b.line : a.start - b.start,
    );
    all[scopeKey] = existing;
    this.textRanges.set(all);
    this.saveMap(KEY_TEXT_RANGES, all);

    if (this.auth.isAuthenticated()) {
      const feature: 'book' | 'article' = scopeKey.startsWith('article:')
        ? 'article'
        : 'book';
      for (const r of removed) {
        if (r.id !== created.id) {
          this.itemsSync.enqueueItem({
            id: `range:${r.id}`,
            itemType: 'text_range',
            feature,
            targetId: scopeKey,
            verseStart: r.line,
            startOffset: r.start,
            endOffset: r.end,
            deleted: true,
          });
        }
      }
      this.itemsSync.enqueueItem({
        id: `range:${created.id}`,
        itemType: 'text_range',
        feature,
        targetId: scopeKey,
        verseStart: line,
        startOffset: start,
        endOffset: end,
        color,
        text,
        contextText: created.note ?? null,
        deleted: false,
      });
    }
  }

  clearRange(scopeKey: string, line: number, start: number, end: number): void {
    const all = { ...this.textRanges() };
    const current = all[scopeKey] ?? [];
    const removed = current.filter(
      (r) => r.line === line && !(r.end <= start || r.start >= end),
    );
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

    if (this.auth.isAuthenticated()) {
      const feature: 'book' | 'article' = scopeKey.startsWith('article:')
        ? 'article'
        : 'book';
      for (const r of removed) {
        this.itemsSync.enqueueItem({
          id: `range:${r.id}`,
          itemType: 'text_range',
          feature,
          targetId: scopeKey,
          verseStart: r.line,
          startOffset: r.start,
          endOffset: r.end,
          deleted: true,
        });
      }
    }
  }

  private applyRemoteItems(remote: SyncUserItem[]): void {
    const pending = this.itemsSync.pendingItems();
    const mergedById = new Map<string, SyncUserItem>();
    for (const item of remote) {
      if (item.feature === 'book' || item.feature === 'article') {
        mergedById.set(item.id, item);
      }
    }
    for (const op of Object.values(pending)) {
      if (op.feature === 'book' || op.feature === 'article') {
        mergedById.set(op.id, op);
      }
    }
    if (mergedById.size === 0) return;

    const nextHl: Record<string, BookHighlight> = {};
    const nextBm: Record<string, BookBookmark> = {};
    const nextRanges: Record<string, TextHighlightRange[]> = {};

    for (const item of mergedById.values()) {
      if (item.deleted) continue;
      if (item.itemType === 'highlight' && item.feature === 'book') {
        nextHl[item.targetId] = {
          key: item.targetId,
          bookId: item.book ?? '',
          chapterIndex: item.chapter ?? 0,
          line: item.verseStart ?? 0,
          text: item.text ?? '',
          color: item.color ?? '#FEF08A',
          note: item.contextText ?? undefined,
          createdAt: item.createdAt ?? item.updatedAt,
        };
      } else if (item.itemType === 'bookmark' && item.feature === 'book') {
        nextBm[item.targetId] = {
          key: item.targetId,
          bookId: item.book ?? '',
          chapterIndex: item.chapter ?? 0,
          chapterTitle: item.text ?? '',
          createdAt: item.createdAt ?? item.updatedAt,
        };
      } else if (item.itemType === 'text_range') {
        const scopeKey = item.targetId;
        const list = nextRanges[scopeKey] ?? [];
        list.push({
          id: item.id.replace(/^range:/, ''),
          scopeKey,
          line: item.verseStart ?? 0,
          start: item.startOffset ?? 0,
          end: item.endOffset ?? 0,
          text: item.text ?? '',
          color: item.color ?? '#FEF08A',
          note: item.contextText ?? undefined,
          createdAt: item.createdAt ?? item.updatedAt,
          updatedAt: Date.parse(item.updatedAt) || Date.now(),
        });
        nextRanges[scopeKey] = list;
      }
    }

    for (const list of Object.values(nextRanges)) {
      list.sort((a, b) => (a.line !== b.line ? a.line - b.line : a.start - b.start));
    }

    this.highlights.set(nextHl);
    this.saveMap(KEY_HIGHLIGHTS, nextHl);
    this.bookmarks.set(nextBm);
    this.saveMap(KEY_BOOKMARKS, nextBm);
    this.textRanges.set(nextRanges);
    this.saveMap(KEY_TEXT_RANGES, nextRanges);
  }

  private storageKey(baseKey: string): string {
    return this.auth.isAuthenticated()
      ? this.itemsSync.userCacheKey(baseKey)
      : baseKey;
  }

  private readMap<T>(baseKey: string): Record<string, T> {
    try {
      const raw = localStorage.getItem(this.storageKey(baseKey));
      return raw ? (JSON.parse(raw) as Record<string, T>) : {};
    } catch {
      return {};
    }
  }

  private saveMap<T>(baseKey: string, map: Record<string, T>): void {
    try {
      localStorage.setItem(this.storageKey(baseKey), JSON.stringify(map));
    } catch {
      // ignore
    }
  }
}
