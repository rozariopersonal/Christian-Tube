import { Injectable, inject, signal } from '@angular/core';
import { ReleaseDataService } from '../../../core/api/release-data.service';
import { ReaderAppearanceService } from '../../../core/services/reader-appearance.service';
import { BIBLE_VERSIONS, BibleVerse } from '../../bible/models/bible.model';

export interface WordFeedTopic {
  slug: string;
  name: string;
  count: number;
}

export interface WordFeedManifest {
  totalItems: number;
  topTopics: WordFeedTopic[];
}

export interface WordFeedItem {
  dayOfYear?: number;
  bookNumber: number;
  bookName: string;
  chapter: number;
  startVerse: number;
  endVerse?: number;
  referenceLabel: string;
  category?: string;
  theme?: string;
  backgroundPreset?: string;
  tags?: string[];
  verseText?: string;
}

@Injectable({ providedIn: 'root' })
export class WordsFeedService {
  private readonly releases = inject(ReleaseDataService);
  private readonly appearance = inject(ReaderAppearanceService);

  readonly manifest = signal<WordFeedManifest | null>(null);
  readonly items = signal<WordFeedItem[]>([]);
  readonly loading = signal<boolean>(false);
  readonly error = signal<string | null>(null);
  readonly activeTopic = signal<string>('daily');

  readonly versionId = (): string => {
    const pref = this.appearance.primaryBibleVersion().toLowerCase();
    return BIBLE_VERSIONS.some((v) => v.id === pref) ? pref : 'nasb';
  };

  async loadDaily(): Promise<void> {
    this.activeTopic.set('daily');
    this.loading.set(true);
    this.error.set(null);
    try {
      const [manifest, daily] = await Promise.all([
        this.releases
          .getJson<WordFeedManifest>('words_feed/manifest.json')
          .catch(() => null),
        this.releases.getJson<WordFeedItem[]>('words_feed/daily.json'),
      ]);
      if (manifest) this.manifest.set(manifest);

      const day = this.currentDayOfYear();
      const sorted = [...daily].sort((a, b) => {
        const da = Math.abs((a.dayOfYear ?? 0) - day);
        const db = Math.abs((b.dayOfYear ?? 0) - day);
        return da - db;
      });
      await this.hydrateVerses(sorted.slice(0, 30));
    } catch (err) {
      this.error.set(
        err instanceof Error ? err.message : 'Unable to load Word Feed',
      );
    } finally {
      this.loading.set(false);
    }
  }

  async loadTopic(slug: string): Promise<void> {
    if (slug === 'daily') {
      await this.loadDaily();
      return;
    }
    this.activeTopic.set(slug);
    this.loading.set(true);
    this.error.set(null);
    try {
      const list = await this.releases.getJson<WordFeedItem[]>(
        `words_feed/topics/${slug}.json`,
      );
      await this.hydrateVerses(list.slice(0, 30));
    } catch (err) {
      this.error.set(
        err instanceof Error ? err.message : 'Unable to load topic',
      );
    } finally {
      this.loading.set(false);
    }
  }

  private async hydrateVerses(slice: WordFeedItem[]): Promise<void> {
    const ver = this.versionId();
    const hydrated = await Promise.all(
      slice.map(async (item) => {
        if (item.verseText) return item;
        try {
          const verses = await this.releases.getJson<BibleVerse[]>(
            `bibles/${ver}/${item.bookNumber}/${item.chapter}.json`,
          );
          const end = item.endVerse ?? item.startVerse;
          const text = verses
            .filter((v) => v.verse >= item.startVerse && v.verse <= end)
            .map((v) => v.text)
            .join(' ');
          return { ...item, verseText: text || undefined };
        } catch {
          return item;
        }
      }),
    );
    this.items.set(hydrated);
  }

  private currentDayOfYear(): number {
    const now = new Date();
    const start = new Date(now.getFullYear(), 0, 0);
    const diff = now.getTime() - start.getTime();
    return Math.floor(diff / 86_400_000);
  }
}
