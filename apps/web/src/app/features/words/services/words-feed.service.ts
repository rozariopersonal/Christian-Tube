import { Injectable, inject, signal } from '@angular/core';
import { ReleaseDataService } from '../../../core/api/release-data.service';
import { BibleVerse } from '../../bible/models/bible.model';
import { OnlineBibleService } from '../../bible/services/online-bible.service';
import {
  WordFeedItem,
  WordFeedManifest,
  WordsFilterState,
  buildCardId,
} from '../models/words-feed.model';
import { WordsPreferencesService } from './words-preferences.service';

@Injectable({ providedIn: 'root' })
export class WordsFeedService {
  private readonly releases = inject(ReleaseDataService);
  private readonly onlineBible = inject(OnlineBibleService);
  private readonly prefs = inject(WordsPreferencesService);

  readonly manifest = signal<WordFeedManifest | null>(null);
  readonly items = signal<WordFeedItem[]>([]);
  readonly loading = signal<boolean>(false);
  readonly loadingMore = signal<boolean>(false);
  readonly hasMore = signal<boolean>(false);
  readonly error = signal<string | null>(null);

  readonly filterState = signal<WordsFilterState>({
    readingOrder: 'daily',
    activeTopic: 'daily',
    testamentFilter: 'all',
    bookNumberFilter: null,
    selectedCategories: [],
    selectedTags: [],
  });

  private fullPoolCache: WordFeedItem[] | null = null;
  private activePool: WordFeedItem[] = [];
  private seenIds: string[] = [];
  private loadGeneration = 0;
  private readonly pageSize = 24;

  readonly versionId = (): string => this.prefs.activeVersionId();
  readonly comparisonVersionIds = (): string[] =>
    this.prefs.comparisonVersionIds();

  async initialize(): Promise<void> {
    await this.loadFeed(this.filterState());
  }

  async selectTopic(slug: string): Promise<void> {
    const next: WordsFilterState = {
      ...this.filterState(),
      readingOrder: 'daily',
      activeTopic: slug,
      testamentFilter: 'all',
      bookNumberFilter: null,
      selectedCategories: [],
      selectedTags: [],
    };
    await this.loadFeed(next);
  }

  async applyFilterState(next: WordsFilterState): Promise<void> {
    await this.loadFeed(next);
  }

  async resetFilters(): Promise<void> {
    await this.loadFeed({
      readingOrder: 'daily',
      activeTopic: 'daily',
      testamentFilter: 'all',
      bookNumberFilter: null,
      selectedCategories: [],
      selectedTags: [],
    });
  }

  async reshuffleRandom(): Promise<void> {
    this.seenIds = [];
    await this.loadFeed({
      ...this.filterState(),
      readingOrder: 'random',
    });
  }

  async loadFeed(state: WordsFilterState): Promise<void> {
    const gen = ++this.loadGeneration;
    this.filterState.set(state);
    this.loading.set(true);
    this.loadingMore.set(false);
    this.error.set(null);

    try {
      // Ensure manifest is loaded once for topic chips
      if (!this.manifest()) {
        const m = await this.releases
          .getJson<WordFeedManifest>('words_feed/manifest.json')
          .catch(() => null);
        if (m && gen === this.loadGeneration) {
          this.manifest.set(m);
        }
      }

      const hasStructuralFilters =
        state.testamentFilter !== 'all' ||
        state.bookNumberFilter !== null ||
        state.selectedCategories.length > 0 ||
        state.selectedTags.length > 0;

      let pool: WordFeedItem[];

      if (state.readingOrder === 'bookmarked') {
        pool = this.applyFilters(
          this.prefs.savedCards().map((c) => ({ ...c, isSaved: true })),
          state,
        );
      } else if (
        state.readingOrder === 'daily' &&
        !hasStructuralFilters
      ) {
        if (state.activeTopic === 'daily') {
          const daily = await this.releases.getJson<WordFeedItem[]>(
            'words_feed/daily.json',
          );
          const day = this.currentDayOfYear();
          pool = [...daily]
            .map((raw) => this.normalizeItem(raw))
            .sort((a, b) => {
              const da = Math.abs((a.dayOfYear ?? 0) - day);
              const db = Math.abs((b.dayOfYear ?? 0) - day);
              return da - db;
            });
        } else {
          const topicItems = await this.releases.getJson<WordFeedItem[]>(
            `words_feed/topics/${state.activeTopic}.json`,
          );
          pool = topicItems.map((raw) => this.normalizeItem(raw));
        }
      } else {
        // Full scriptures.json pool for random, canonical, or filtered daily
        const all = await this.getFullPool();
        pool = this.applyFilters(all, state);

        if (state.readingOrder === 'canonical') {
          pool.sort(
            (a, b) =>
              a.bookNumber - b.bookNumber ||
              a.chapter - b.chapter ||
              a.startVerse - b.startVerse,
          );
        } else {
          pool = this.shuffleExcludingSeen(pool);
        }
      }

      if (gen !== this.loadGeneration) return;
      this.activePool = pool;
      this.items.set([]);
      await this.appendNextPage(gen);
    } catch (err) {
      if (gen === this.loadGeneration) {
        this.error.set(
          err instanceof Error ? err.message : 'Unable to load Word Feed',
        );
      }
    } finally {
      if (gen === this.loadGeneration) {
        this.loading.set(false);
      }
    }
  }

  async loadMore(): Promise<void> {
    if (this.loadingMore() || !this.hasMore()) return;
    const gen = this.loadGeneration;
    this.loadingMore.set(true);
    try {
      await this.appendNextPage(gen);
    } finally {
      if (gen === this.loadGeneration) {
        this.loadingMore.set(false);
      }
    }
  }

  async rehydrateVersion(activeIndex: number): Promise<void> {
    const gen = this.loadGeneration;
    const list = [...this.items()];
    if (list.length === 0) return;

    const ver = this.versionId();
    const cmpIds = this.comparisonVersionIds();
    const eager = new Set<number>([
      activeIndex,
      ...(activeIndex + 1 < list.length ? [activeIndex + 1] : []),
      ...(activeIndex - 1 >= 0 ? [activeIndex - 1] : []),
    ]);

    await Promise.all(
      [...eager].map(async (idx) => {
        list[idx] = await this.hydrateItem(list[idx], ver, cmpIds);
      }),
    );
    if (gen !== this.loadGeneration) return;
    this.items.set([...list]);

    // Hydrate remaining loaded items in small batches
    for (let i = 0; i < list.length; i += 4) {
      if (gen !== this.loadGeneration) return;
      const indices = [i, i + 1, i + 2, i + 3].filter(
        (idx) => idx < list.length && !eager.has(idx),
      );
      if (indices.length === 0) continue;
      await Promise.all(
        indices.map(async (idx) => {
          list[idx] = await this.hydrateItem(list[idx], ver, cmpIds);
        }),
      );
      if (gen !== this.loadGeneration) return;
      this.items.set([...list]);
    }
  }

  async rehydrateComparison(activeIndex: number): Promise<void> {
    const gen = this.loadGeneration;
    const list = [...this.items()];
    if (list.length === 0) return;
    const cmpIds = this.comparisonVersionIds();

    const eager = new Set<number>([
      activeIndex,
      ...(activeIndex + 1 < list.length ? [activeIndex + 1] : []),
    ]);

    await Promise.all(
      [...eager].map(async (idx) => {
        list[idx] = await this.hydrateComparisonOnly(list[idx], cmpIds);
      }),
    );
    if (gen !== this.loadGeneration) return;
    this.items.set([...list]);

    for (let i = 0; i < list.length; i += 4) {
      if (gen !== this.loadGeneration) return;
      const indices = [i, i + 1, i + 2, i + 3].filter(
        (idx) => idx < list.length && !eager.has(idx),
      );
      if (indices.length === 0) continue;
      await Promise.all(
        indices.map(async (idx) => {
          list[idx] = await this.hydrateComparisonOnly(list[idx], cmpIds);
        }),
      );
      if (gen !== this.loadGeneration) return;
      this.items.set([...list]);
    }
  }

  syncSavedFlags(): void {
    const saved = this.prefs.savedIds();
    this.items.update((list) =>
      list.map((item) => ({ ...item, isSaved: saved.has(item.id) })),
    );
  }

  private async appendNextPage(gen: number): Promise<void> {
    const start = this.items().length;
    const slice = this.activePool.slice(start, start + this.pageSize);
    this.hasMore.set(start + slice.length < this.activePool.length);
    if (slice.length === 0) return;

    if (this.filterState().readingOrder === 'random') {
      for (const item of slice) {
        this.seenIds.push(item.id);
      }
      if (this.seenIds.length > 200) {
        this.seenIds = this.seenIds.slice(this.seenIds.length - 200);
      }
    }

    const ver = this.versionId();
    const cmpIds = this.comparisonVersionIds();
    const saved = this.prefs.savedIds();

    const hydrated = await Promise.all(
      slice.map(async (item) => {
        const withSaved = { ...item, isSaved: saved.has(item.id) };
        return this.hydrateItem(withSaved, ver, cmpIds);
      }),
    );

    if (gen !== this.loadGeneration) return;
    this.items.update((cur) => [...cur, ...hydrated]);
  }

  private async getFullPool(): Promise<WordFeedItem[]> {
    if (this.fullPoolCache) return this.fullPoolCache;
    const raw = await this.releases.getJson<WordFeedItem[]>('scriptures.json');
    this.fullPoolCache = raw.map((item) => this.normalizeItem(item));
    return this.fullPoolCache;
  }

  private normalizeItem(raw: Partial<WordFeedItem> & { text?: string }): WordFeedItem {
    const bookNumber = raw.bookNumber ?? 43;
    const chapter = raw.chapter ?? 3;
    const startVerse = raw.startVerse ?? 16;
    const endVerse = raw.endVerse ?? startVerse;
    const bookName = raw.bookName ?? 'John';
    return {
      ...raw,
      id: buildCardId({
        id: raw.id,
        bookNumber,
        chapter,
        startVerse,
        endVerse,
      }),
      bookNumber,
      bookName,
      chapter,
      startVerse,
      endVerse,
      referenceLabel:
        raw.referenceLabel ??
        `${bookName} ${chapter}:${startVerse}${endVerse > startVerse ? `-${endVerse}` : ''}`,
      verseText: raw.verseText ?? raw.text,
      tags: raw.tags ?? [],
      isSaved: this.prefs.isSaved(
        buildCardId({
          id: raw.id,
          bookNumber,
          chapter,
          startVerse,
          endVerse,
        }),
      ),
    };
  }

  private applyFilters(
    pool: WordFeedItem[],
    state: WordsFilterState,
  ): WordFeedItem[] {
    let result = pool;

    if (state.testamentFilter === 'ot') {
      result = result.filter((c) => c.bookNumber <= 39);
    } else if (state.testamentFilter === 'nt') {
      result = result.filter((c) => c.bookNumber >= 40);
    }

    if (state.bookNumberFilter !== null) {
      result = result.filter((c) => c.bookNumber === state.bookNumberFilter);
    }

    const effectiveCats: string[] = [];
    const effectiveTags: string[] = [...state.selectedTags];

    for (const cat of state.selectedCategories) {
      if (cat === 'prayer') {
        effectiveCats.push('prayer', 'consecration');
      } else if (cat === 'courage') {
        if (!effectiveTags.includes('courage')) effectiveTags.push('courage');
      } else {
        effectiveCats.push(cat);
      }
    }

    if (effectiveCats.length > 0 && effectiveTags.length > 0) {
      result = result.filter(
        (c) =>
          (c.category ? effectiveCats.includes(c.category) : false) ||
          (c.tags?.some((t) => effectiveTags.includes(t)) ?? false),
      );
    } else if (effectiveCats.length > 0) {
      result = result.filter((c) =>
        c.category ? effectiveCats.includes(c.category) : false,
      );
    } else if (effectiveTags.length > 0) {
      result = result.filter(
        (c) => c.tags?.some((t) => effectiveTags.includes(t)) ?? false,
      );
    }

    return [...result];
  }

  private shuffleExcludingSeen(pool: WordFeedItem[]): WordFeedItem[] {
    const seen = new Set(this.seenIds);
    let candidates = pool.filter((c) => !seen.has(c.id));
    if (candidates.length === 0 && pool.length > 0) {
      this.seenIds = [];
      candidates = [...pool];
    }
    for (let i = candidates.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [candidates[i], candidates[j]] = [candidates[j], candidates[i]];
    }
    return candidates;
  }

  private async hydrateItem(
    item: WordFeedItem,
    ver: string,
    cmpIds: string[],
  ): Promise<WordFeedItem> {
    let next = { ...item };

    if (next.resolvedVersion !== ver || !next.verseText) {
      const text = await this.fetchPassageText(next, ver);
      if (text) {
        next.verseText = text;
        next.resolvedVersion = ver;
      }
    }

    next = await this.hydrateComparisonOnly(next, cmpIds, ver);
    return next;
  }

  private async hydrateComparisonOnly(
    item: WordFeedItem,
    cmpIds: string[],
    primaryVer?: string,
  ): Promise<WordFeedItem> {
    const activeVer = primaryVer ?? this.versionId();
    const targets = cmpIds.filter((id) => id && id !== activeVer).slice(0, 3);
    if (targets.length === 0) {
      return { ...item, comparisons: [] };
    }

    const existing = new Map(
      (item.comparisons ?? []).map((c) => [c.version, c.text]),
    );
    const resolved = await Promise.all(
      targets.map(async (ver) => {
        const cached = existing.get(ver);
        if (cached) return { version: ver, text: cached };
        const text = await this.fetchPassageText(item, ver);
        return text ? { version: ver, text } : null;
      }),
    );

    return {
      ...item,
      comparisons: resolved.filter((x): x is { version: string; text: string } => x !== null),
    };
  }

  private async fetchPassageText(
    item: WordFeedItem,
    versionId: string,
  ): Promise<string | null> {
    const mapping =
      item.verseMappings?.[versionId] ??
      item.verseMappings?.[versionId.toUpperCase()];
    const bookNumber = mapping?.bookNumber ?? item.bookNumber;
    const chapter = mapping?.chapter ?? item.chapter;
    const startVerse = mapping?.startVerse ?? item.startVerse;
    const endVerse = mapping?.endVerse ?? item.endVerse ?? startVerse;

    try {
      let verses: BibleVerse[];
      if (this.onlineBible.isOnlineVersion(versionId)) {
        verses = await this.onlineBible.fetchChapter(
          versionId,
          bookNumber,
          chapter,
        );
      } else {
        verses = await this.releases.getJson<BibleVerse[]>(
          `bibles/${versionId}/${bookNumber}/${chapter}.json`,
        );
      }
      const text = verses
        .filter((v) => v.verse >= startVerse && v.verse <= endVerse)
        .map((v) => v.text)
        .join(' ')
        .trim();
      return text || null;
    } catch {
      return null;
    }
  }

  private currentDayOfYear(): number {
    const now = new Date();
    const start = new Date(now.getFullYear(), 0, 0);
    const diff = now.getTime() - start.getTime();
    return Math.floor(diff / 86_400_000);
  }
}
