import { Injectable, computed, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { ApiService } from '../../../core/api/api.service';
import { ReleaseDataService } from '../../../core/api/release-data.service';
import { ReaderAppearanceService } from '../../../core/services/reader-appearance.service';
import { OnlineBibleService } from './online-bible.service';
import {
  BOOK_ABBREVS,
  BibleBook,
  BibleBookmark,
  BibleSemanticSearchResponse,
  BibleVerse,
  ChapterStudy,
  VerseCrossRefs,
} from '../models/bible.model';

const KEY_STATE = 'bible_reader_state';
const KEY_HIGHLIGHTS = 'bible_highlights';
const KEY_BOOKMARKS = 'bible_bookmarks';
const KEY_NOTES = 'bible_notes';
const FALLBACK_VERSION = 'kjv';
const INCOMPLETE_VERSIONS = new Set(['nasb', 'nlt', 'msg']);

@Injectable({ providedIn: 'root' })
export class BibleService {
  private readonly api = inject(ApiService);
  private readonly releases = inject(ReleaseDataService);
  private readonly appearance = inject(ReaderAppearanceService);
  private readonly onlineBible = inject(OnlineBibleService);

  readonly version = signal<string>(
    this.readState().version ??
      this.appearance.primaryBibleVersion().toLowerCase(),
  );
  readonly bookNumber = signal<number>(this.readState().bookNumber ?? 1);
  readonly chapter = signal<number>(this.readState().chapter ?? 1);

  readonly books = signal<BibleBook[]>([]);
  readonly verses = signal<BibleVerse[]>([]);
  readonly crossRefs = signal<VerseCrossRefs[]>([]);
  readonly study = signal<ChapterStudy | null>(null);
  readonly loading = signal<boolean>(false);
  readonly error = signal<string | null>(null);
  readonly fallbackNotice = signal<string | null>(null);
  readonly compareVersions = signal<string[]>([]);

  readonly highlights = signal<Record<string, string>>(
    this.readJson<Record<string, string>>(KEY_HIGHLIGHTS, {}),
  );
  readonly bookmarks = signal<BibleBookmark[]>(
    this.readJson<BibleBookmark[]>(KEY_BOOKMARKS, []),
  );
  readonly notes = signal<Record<string, string>>(
    this.readJson<Record<string, string>>(KEY_NOTES, {}),
  );

  readonly currentBook = computed(
    () =>
      this.books().find((b) => b.bookNumber === this.bookNumber()) ?? {
        bookNumber: this.bookNumber(),
        name: `Book ${this.bookNumber()}`,
        chapters: 1,
      },
  );

  readonly currentBookAbbrev = computed(
    () => BOOK_ABBREVS[this.bookNumber()] || String(this.bookNumber()),
  );

  async init(overrides?: {
    version?: string;
    book?: string;
    chapter?: number;
  }): Promise<void> {
    const targetVersion = overrides?.version?.trim() || this.version();
    await this.loadVersion(
      targetVersion,
      overrides?.book ?? this.bookNumber(),
      overrides?.chapter ?? this.chapter(),
    );
  }

  resolveBookNumber(
    bookParam: string | number,
    booksList: BibleBook[] = this.books(),
  ): number | null {
    if (typeof bookParam === 'number') {
      return bookParam >= 1 && bookParam <= 66 ? bookParam : null;
    }
    const raw = bookParam.trim();
    if (!raw) return null;

    const num = Number(raw);
    if (Number.isInteger(num) && num >= 1 && num <= 66) {
      return num;
    }

    const upper = raw.toUpperCase();
    const abbrevIdx = BOOK_ABBREVS.indexOf(upper);
    if (abbrevIdx > 0) return abbrevIdx;

    const normalized = raw.toLowerCase().replace(/[-_]+/g, ' ');
    const exactMatch = booksList.find(
      (b) => b.name.toLowerCase() === normalized,
    );
    if (exactMatch) return exactMatch.bookNumber;

    const prefixMatch = booksList.find((b) =>
      b.name.toLowerCase().startsWith(normalized),
    );
    return prefixMatch?.bookNumber ?? null;
  }

  private bookNamesCache: Record<string, Record<string, string>> | null = null;

  private async getLocalizedBookNames(
    versionId: string,
  ): Promise<Record<string, string> | null> {
    if (!this.bookNamesCache) {
      try {
        this.bookNamesCache = await this.releases.getJson<
          Record<string, Record<string, string>>
        >('book_names.json');
      } catch {
        this.bookNamesCache = {};
      }
    }
    return this.bookNamesCache[versionId.toLowerCase()] ?? null;
  }

  async loadVersion(
    versionId: string,
    bookRef: number | string = this.bookNumber(),
    ch = this.chapter(),
  ): Promise<void> {
    const cleanVer = versionId.toLowerCase();
    this.version.set(cleanVer);
    this.loading.set(true);
    this.error.set(null);
    try {
      let rawBooks: BibleBook[];
      try {
        rawBooks = await this.releases.getJson<BibleBook[]>(
          `bibles/${cleanVer}/books.json`,
        );
      } catch (err) {
        if (!this.onlineBible.isOnlineVersion(cleanVer)) throw err;
        rawBooks = await this.releases.getJson<BibleBook[]>(
          `bibles/${FALLBACK_VERSION}/books.json`,
        );
      }
      const localized = await this.getLocalizedBookNames(cleanVer);
      const books = localized
        ? rawBooks.map((b) => ({
            ...b,
            name: localized[String(b.bookNumber)] ?? b.name,
          }))
        : rawBooks;
      this.books.set(books);
      const resolvedNum = this.resolveBookNumber(bookRef, books);
      const validBook =
        (resolvedNum ? books.find((b) => b.bookNumber === resolvedNum) : null) ??
        books[0];
      const clampedCh = Math.min(validBook.chapters, Math.max(1, ch));
      await this.loadChapter(validBook.bookNumber, clampedCh);
    } catch (err) {
      if (cleanVer !== FALLBACK_VERSION) {
        await this.loadVersion(FALLBACK_VERSION, bookRef, ch);
        return;
      }
      this.error.set(
        err instanceof Error ? err.message : 'Unable to load Bible version',
      );
      this.loading.set(false);
    }
  }

  async loadChapter(bookNum: number, ch: number): Promise<void> {
    const ver = this.version();
    this.bookNumber.set(bookNum);
    this.chapter.set(ch);
    this.saveState();
    this.loading.set(true);
    this.error.set(null);
    this.fallbackNotice.set(null);

    try {
      const verses = await this.fetchVersionChapter(ver, bookNum, ch);
      this.verses.set(verses);
    } catch (err) {
      if (ver !== FALLBACK_VERSION) {
        try {
          const fallbackVerses = await this.releases.getJson<BibleVerse[]>(
            `bibles/${FALLBACK_VERSION}/${bookNum}/${ch}.json`,
          );
          this.verses.set(fallbackVerses);
          this.fallbackNotice.set(
            `This chapter is unavailable in ${ver.toUpperCase()} — showing ${FALLBACK_VERSION.toUpperCase()}.`,
          );
        } catch {
          this.verses.set([]);
          this.error.set(
            err instanceof Error ? err.message : 'Unable to load chapter',
          );
        }
      } else {
        this.verses.set([]);
        this.error.set(
          err instanceof Error ? err.message : 'Unable to load chapter',
        );
      }
    } finally {
      this.loading.set(false);
    }

    // Load cross-references & study concepts in background
    const abbrev = BOOK_ABBREVS[bookNum];
    if (abbrev) {
      this.releases
        .getJson<VerseCrossRefs[]>(`cross_references/${abbrev}/${ch}.json`)
        .then((refs) => this.crossRefs.set(refs))
        .catch(() => this.crossRefs.set([]));
    } else {
      this.crossRefs.set([]);
    }

    const bb = String(bookNum).padStart(2, '0');
    const ccc = String(ch).padStart(3, '0');
    this.releases
      .getJson<ChapterStudy>(`study/${ver}/chapters/b${bb}_c${ccc}.json`)
      .then((st) => this.study.set(st))
      .catch(() => this.study.set(null));

    this.preloadBibleInBackground(ver, bookNum, ch);
  }

  private preloadBibleInBackground(
    ver: string,
    bookNum: number,
    ch: number,
  ): void {
    if (INCOMPLETE_VERSIONS.has(ver)) return;
    const books = this.books();
    const cur = books.find((b) => b.bookNumber === bookNum);
    if (!cur) return;

    const adjacent: Array<{ b: number; c: number }> = [];
    if (ch < cur.chapters) {
      adjacent.push({ b: bookNum, c: ch + 1 });
    } else {
      const nextBook = books.find((b) => b.bookNumber === bookNum + 1);
      if (nextBook) adjacent.push({ b: nextBook.bookNumber, c: 1 });
    }

    if (ch > 1) {
      adjacent.push({ b: bookNum, c: ch - 1 });
    } else {
      const prevBook = books.find((b) => b.bookNumber === bookNum - 1);
      if (prevBook) adjacent.push({ b: prevBook.bookNumber, c: prevBook.chapters });
    }

    for (const t of adjacent) {
      this.releases.prefetchJson(`bibles/${ver}/${t.b}/${t.c}.json`);
      const adjAbbrev = BOOK_ABBREVS[t.b];
      if (adjAbbrev) {
        this.releases.prefetchJson(`cross_references/${adjAbbrev}/${t.c}.json`);
      }
    }

    // Tier 2: Preload remaining chapters of the current Bible book into IndexedDB
    const bookPaths: string[] = [];
    for (let c = ch + 2; c <= cur.chapters; c++) {
      bookPaths.push(`bibles/${ver}/${bookNum}/${c}.json`);
    }
    for (let c = ch - 2; c >= 1; c--) {
      bookPaths.push(`bibles/${ver}/${bookNum}/${c}.json`);
    }
    if (bookPaths.length > 0) {
      void this.releases.prefetchBatch(bookPaths, {
        concurrency: 3,
        maxTotalBytes: 1_048_576,
        shouldContinue: () =>
          this.version() === ver && this.bookNumber() === bookNum,
      });
    }
  }

  prevChapter(): void {
    const ch = this.chapter();
    if (ch > 1) {
      void this.loadChapter(this.bookNumber(), ch - 1);
      return;
    }
    const prevBook = this.books().find(
      (b) => b.bookNumber === this.bookNumber() - 1,
    );
    if (prevBook) {
      void this.loadChapter(prevBook.bookNumber, prevBook.chapters);
    }
  }

  nextChapter(): void {
    const cur = this.currentBook();
    if (this.chapter() < cur.chapters) {
      void this.loadChapter(cur.bookNumber, this.chapter() + 1);
      return;
    }
    const nextBook = this.books().find(
      (b) => b.bookNumber === cur.bookNumber + 1,
    );
    if (nextBook) {
      void this.loadChapter(nextBook.bookNumber, 1);
    }
  }

  jumpToAbbrev(abbrev: string, chapter: number): void {
    const idx = BOOK_ABBREVS.indexOf(abbrev.toUpperCase());
    if (idx > 0) {
      void this.loadChapter(idx, chapter);
    }
  }

  verseKey(verseNum: number): string {
    return this.verseKeyFor(this.bookNumber(), this.chapter(), verseNum);
  }

  verseKeyFor(bookNum: number, ch: number, verseNum: number): string {
    return `${bookNum}:${ch}:${verseNum}`;
  }

  toggleCompareVersion(versionId: string): void {
    const clean = versionId.toLowerCase();
    if (clean === this.version()) return;
    const cur = this.compareVersions();
    if (cur.includes(clean)) {
      this.compareVersions.set(cur.filter((v) => v !== clean));
    } else if (cur.length < 2) {
      this.compareVersions.set([...cur, clean]);
    } else {
      this.compareVersions.set([cur[1], clean]);
    }
  }

  clearCompareVersions(): void {
    this.compareVersions.set([]);
  }

  prevChapterOf(
    bookNum: number,
    ch: number,
  ): { bookNumber: number; bookName: string; chapter: number } | null {
    const books = this.books();
    const cur = books.find((b) => b.bookNumber === bookNum);
    if (!cur) return null;
    if (ch > 1) {
      return { bookNumber: bookNum, bookName: cur.name, chapter: ch - 1 };
    }
    const prevBook = books.find((b) => b.bookNumber === bookNum - 1);
    if (prevBook) {
      return {
        bookNumber: prevBook.bookNumber,
        bookName: prevBook.name,
        chapter: prevBook.chapters,
      };
    }
    return null;
  }

  nextChapterOf(
    bookNum: number,
    ch: number,
  ): { bookNumber: number; bookName: string; chapter: number } | null {
    const books = this.books();
    const cur = books.find((b) => b.bookNumber === bookNum);
    if (!cur) return null;
    if (ch < cur.chapters) {
      return { bookNumber: bookNum, bookName: cur.name, chapter: ch + 1 };
    }
    const nextBook = books.find((b) => b.bookNumber === bookNum + 1);
    if (nextBook) {
      return {
        bookNumber: nextBook.bookNumber,
        bookName: nextBook.name,
        chapter: 1,
      };
    }
    return null;
  }

  private async fetchVersionChapter(
    ver: string,
    bookNum: number,
    ch: number,
  ): Promise<BibleVerse[]> {
    const clean = ver.toLowerCase();
    if (this.onlineBible.isOnlineVersion(clean)) {
      try {
        return await this.onlineBible.fetchChapter(clean, bookNum, ch);
      } catch {
        // Fall back to releases CDN if online API fails
      }
    }
    return this.releases.getJson<BibleVerse[]>(
      `bibles/${clean}/${bookNum}/${ch}.json`,
    );
  }

  async fetchChapterVerses(
    versionId: string,
    bookNum: number,
    ch: number,
    allowFallback = false,
  ): Promise<BibleVerse[]> {
    const clean = versionId.toLowerCase();
    try {
      return await this.fetchVersionChapter(clean, bookNum, ch);
    } catch {
      if (allowFallback && clean !== FALLBACK_VERSION) {
        try {
          return await this.releases.getJson<BibleVerse[]>(
            `bibles/${FALLBACK_VERSION}/${bookNum}/${ch}.json`,
          );
        } catch {
          return [];
        }
      }
      return [];
    }
  }

  async searchSemantic(
    query: string,
    limit = 30,
  ): Promise<BibleSemanticSearchResponse> {
    const clean = query.trim();
    if (!clean) return { query: clean, count: 0, results: [] };
    return firstValueFrom(
      this.api.get<BibleSemanticSearchResponse>('/api/bible/search', {
        q: clean,
        limit,
      }),
    );
  }

  /**
   * Resolves verse and multi-verse passage hit texts into [versionId] so search
   * results render in whichever Bible translation is currently active.
   */
  async resolveSearchHitsInVersion<
    T extends {
      bookNumber: number | null;
      bookName?: string | null;
      chapter: number | null;
      verse: number | null;
      endVerse?: number | null;
      reference?: string;
      text: string;
    },
  >(hits: readonly T[], versionId: string): Promise<T[]> {
    const targetVersion = versionId.trim().toLowerCase();
    if (!targetVersion || hits.length === 0) return [...hits];

    const uniqueChapters = new Map<string, { bookNumber: number; chapter: number }>();
    for (const hit of hits) {
      if (hit.bookNumber == null || hit.chapter == null) continue;
      const key = `${hit.bookNumber}:${hit.chapter}`;
      if (!uniqueChapters.has(key)) {
        uniqueChapters.set(key, { bookNumber: hit.bookNumber, chapter: hit.chapter });
      }
    }

    const chapterMap = new Map<string, BibleVerse[]>();
    await Promise.all(
      Array.from(uniqueChapters.entries()).map(async ([key, ref]) => {
        const verses = await this.fetchChapterVerses(
          targetVersion,
          ref.bookNumber,
          ref.chapter,
          false,
        );
        if (verses.length > 0) {
          chapterMap.set(key, verses);
        }
      }),
    );

    const localBooks = this.books();
    return hits.map((hit) => {
      if (hit.bookNumber == null || hit.chapter == null || hit.verse == null) {
        return hit;
      }
      const key = `${hit.bookNumber}:${hit.chapter}`;
      const verses = chapterMap.get(key);
      const localBookName =
        localBooks.find((b) => b.bookNumber === hit.bookNumber)?.name ??
        hit.bookName ??
        `Book ${hit.bookNumber}`;
      const endV = hit.endVerse;
      const localizedRef =
        endV != null && endV > hit.verse
          ? `${localBookName} ${hit.chapter}:${hit.verse}-${endV}`
          : `${localBookName} ${hit.chapter}:${hit.verse}`;

      if (!verses || verses.length === 0) {
        return { ...hit, bookName: localBookName, reference: localizedRef };
      }

      let resolvedText = '';
      if (endV != null && endV > hit.verse) {
        const range = verses.filter(
          (v) => v.verse >= hit.verse! && v.verse <= endV,
        );
        if (range.length > 0) {
          resolvedText = range.map((v) => `${v.verse}. ${v.text}`).join(' ');
        }
      } else {
        const match = verses.find((v) => v.verse === hit.verse);
        if (match?.text) {
          resolvedText = match.text;
        }
      }

      return {
        ...hit,
        bookName: localBookName,
        reference: localizedRef,
        text: resolvedText || hit.text,
      };
    });
  }

  setHighlight(verseNum: number, color: string | null): void {
    const key = this.verseKey(verseNum);
    const next = { ...this.highlights() };
    if (color) {
      next[key] = color;
    } else {
      delete next[key];
    }
    this.highlights.set(next);
    this.writeJson(KEY_HIGHLIGHTS, next);
  }

  toggleBookmark(verse: BibleVerse): void {
    const key = this.verseKey(verse.verse);
    const existing = this.bookmarks();
    const next = existing.some((b) => b.key === key)
      ? existing.filter((b) => b.key !== key)
      : [
          {
            key,
            bookNumber: this.bookNumber(),
            bookName: this.currentBook().name,
            chapter: this.chapter(),
            verse: verse.verse,
            text: verse.text,
            createdAt: new Date().toISOString(),
          },
          ...existing,
        ];
    this.bookmarks.set(next);
    this.writeJson(KEY_BOOKMARKS, next);
  }

  isBookmarked(verseNum: number): boolean {
    const key = this.verseKey(verseNum);
    return this.bookmarks().some((b) => b.key === key);
  }

  saveNote(verseNum: number, text: string): void {
    const key = this.verseKey(verseNum);
    const next = { ...this.notes() };
    if (text.trim()) {
      next[key] = text.trim();
    } else {
      delete next[key];
    }
    this.notes.set(next);
    this.writeJson(KEY_NOTES, next);
  }

  private saveState(): void {
    this.writeJson(KEY_STATE, {
      version: this.version(),
      bookNumber: this.bookNumber(),
      chapter: this.chapter(),
    });
  }

  private readState(): {
    version?: string;
    bookNumber?: number;
    chapter?: number;
  } {
    return this.readJson(KEY_STATE, {});
  }

  private readJson<T>(key: string, fallback: T): T {
    try {
      const raw = localStorage.getItem(key);
      return raw ? (JSON.parse(raw) as T) : fallback;
    } catch {
      return fallback;
    }
  }

  private writeJson(key: string, value: unknown): void {
    try {
      localStorage.setItem(key, JSON.stringify(value));
    } catch {
      // ignore
    }
  }
}
