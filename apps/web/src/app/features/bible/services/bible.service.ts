import { Injectable, computed, inject, signal } from '@angular/core';
import { ReleaseDataService } from '../../../core/api/release-data.service';
import { ReaderAppearanceService } from '../../../core/services/reader-appearance.service';
import {
  BOOK_ABBREVS,
  BibleBook,
  BibleBookmark,
  BibleVerse,
  ChapterStudy,
  VerseCrossRefs,
} from '../models/bible.model';

const KEY_STATE = 'bible_reader_state';
const KEY_HIGHLIGHTS = 'bible_highlights';
const KEY_BOOKMARKS = 'bible_bookmarks';
const KEY_NOTES = 'bible_notes';

@Injectable({ providedIn: 'root' })
export class BibleService {
  private readonly releases = inject(ReleaseDataService);
  private readonly appearance = inject(ReaderAppearanceService);

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
      const books = await this.releases.getJson<BibleBook[]>(
        `bibles/${cleanVer}/books.json`,
      );
      this.books.set(books);
      const resolvedNum = this.resolveBookNumber(bookRef, books);
      const validBook =
        (resolvedNum ? books.find((b) => b.bookNumber === resolvedNum) : null) ??
        books[0];
      const clampedCh = Math.min(validBook.chapters, Math.max(1, ch));
      await this.loadChapter(validBook.bookNumber, clampedCh);
    } catch (err) {
      if (cleanVer !== 'nasb') {
        await this.loadVersion('nasb', bookRef, ch);
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

    try {
      const verses = await this.releases.getJson<BibleVerse[]>(
        `bibles/${ver}/${bookNum}/${ch}.json`,
      );
      this.verses.set(verses);
    } catch (err) {
      this.verses.set([]);
      this.error.set(
        err instanceof Error ? err.message : 'Unable to load chapter',
      );
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

    this.preloadAdjacentChapters(ver, bookNum, ch);
  }

  private preloadAdjacentChapters(
    ver: string,
    bookNum: number,
    ch: number,
  ): void {
    const books = this.books();
    const cur = books.find((b) => b.bookNumber === bookNum);
    if (!cur) return;

    const targets: Array<{ b: number; c: number }> = [];
    if (ch < cur.chapters) {
      targets.push({ b: bookNum, c: ch + 1 });
    } else {
      const nextBook = books.find((b) => b.bookNumber === bookNum + 1);
      if (nextBook) targets.push({ b: nextBook.bookNumber, c: 1 });
    }

    if (ch > 1) {
      targets.push({ b: bookNum, c: ch - 1 });
    } else {
      const prevBook = books.find((b) => b.bookNumber === bookNum - 1);
      if (prevBook) targets.push({ b: prevBook.bookNumber, c: prevBook.chapters });
    }

    for (const t of targets) {
      this.releases.prefetchJson(`bibles/${ver}/${t.b}/${t.c}.json`);
      const adjAbbrev = BOOK_ABBREVS[t.b];
      if (adjAbbrev) {
        this.releases.prefetchJson(`cross_references/${adjAbbrev}/${t.c}.json`);
      }
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
    return `${this.bookNumber()}:${this.chapter()}:${verseNum}`;
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
