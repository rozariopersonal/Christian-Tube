import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { firstValueFrom, timeout } from 'rxjs';
import { IndexedDbCacheService } from '../../../core/storage/indexed-db-cache.service';
import { BOOK_ABBREVS, BibleVerse } from '../models/bible.model';

type OnlineProvider = 'apiBible' | 'youVersion';

interface OnlineBibleConfig {
  versionId: string;
  provider: OnlineProvider;
  apiBibleId?: string;
  youVersionId?: number;
  fallbackProvider?: OnlineProvider;
}

const API_BIBLE_KEY = '7-rV1sxCwAuLPp4A2jAmQ';
const YOUVERSION_APP_KEY = 'uXc7kDxs9Ay9ClVThpIsSIGHiw2clfTWgSOPgAl1B0V6Z6jM';
const ONLINE_CACHE_REV = 'online-v1';

const ONLINE_CONFIGS: Record<string, OnlineBibleConfig> = {
  nasb: {
    versionId: 'nasb',
    provider: 'apiBible',
    apiBibleId: 'b8ee27bcd1cae43a-01',
    youVersionId: 100,
    fallbackProvider: 'youVersion',
  },
  nlt: {
    versionId: 'nlt',
    provider: 'apiBible',
    apiBibleId: 'd6e14a625393b4da-01',
  },
  msg: {
    versionId: 'msg',
    provider: 'apiBible',
    apiBibleId: '6f11a7de016f942e-01',
  },
  niv: {
    versionId: 'niv',
    provider: 'youVersion',
    youVersionId: 111,
  },
  amp: {
    versionId: 'amp',
    provider: 'youVersion',
    youVersionId: 1588,
  },
  hin_hcv: {
    versionId: 'hin_hcv',
    provider: 'apiBible',
    apiBibleId: '2133003bb8b5e62b-01',
  },
  tam_tcv: {
    versionId: 'tam_tcv',
    provider: 'apiBible',
    apiBibleId: '032ec262506b719f-01',
  },
  tel_tcv: {
    versionId: 'tel_tcv',
    provider: 'apiBible',
    apiBibleId: '81d6933d39d343f8-03',
  },
  mal_mcv: {
    versionId: 'mal_mcv',
    provider: 'apiBible',
    apiBibleId: 'de295e9ba65f6d0f-01',
  },
  kan_kcv: {
    versionId: 'kan_kcv',
    provider: 'apiBible',
    apiBibleId: '08389f036844c2de-01',
  },
  ben_bcv: {
    versionId: 'ben_bcv',
    provider: 'apiBible',
    apiBibleId: 'efd8a351a07d4264-01',
  },
  mar_mcv: {
    versionId: 'mar_mcv',
    provider: 'apiBible',
    apiBibleId: '1c825c8591183bb0-01',
  },
  pan_pcv: {
    versionId: 'pan_pcv',
    provider: 'apiBible',
    apiBibleId: '38de522697cd8943-01',
  },
  urd_ucv: {
    versionId: 'urd_ucv',
    provider: 'apiBible',
    apiBibleId: 'eecbca904435fce9-01',
  },
  guj_irv: {
    versionId: 'guj_irv',
    provider: 'apiBible',
    apiBibleId: 'a3644a98420c2703-01',
  },
  asm_irv: {
    versionId: 'asm_irv',
    provider: 'apiBible',
    apiBibleId: 'd199679f805f5b29-01',
  },
};

@Injectable({ providedIn: 'root' })
export class OnlineBibleService {
  private readonly http = inject(HttpClient);
  private readonly idb = inject(IndexedDbCacheService);
  private readonly memoryCache = new Map<string, BibleVerse[]>();
  private readonly inFlight = new Map<string, Promise<BibleVerse[]>>();

  isOnlineVersion(versionId: string): boolean {
    return versionId.toLowerCase() in ONLINE_CONFIGS;
  }

  async fetchChapter(
    versionId: string,
    bookNumber: number,
    chapter: number,
  ): Promise<BibleVerse[]> {
    const clean = versionId.toLowerCase();
    const config = ONLINE_CONFIGS[clean];
    if (!config) {
      throw new Error(`No online Bible config for ${versionId}`);
    }

    const cacheKey = `online_bible/${clean}/${bookNumber}/${chapter}`;
    const mem = this.memoryCache.get(cacheKey);
    if (mem && mem.length > 0) return mem;

    const existing = this.inFlight.get(cacheKey);
    if (existing) return existing;

    const req = this.loadChapter(config, cacheKey, bookNumber, chapter).finally(
      () => this.inFlight.delete(cacheKey),
    );
    this.inFlight.set(cacheKey, req);
    return req;
  }

  private async loadChapter(
    config: OnlineBibleConfig,
    cacheKey: string,
    bookNumber: number,
    chapter: number,
  ): Promise<BibleVerse[]> {
    const cached = await this.idb.get<BibleVerse[]>(cacheKey, ONLINE_CACHE_REV);
    if (cached && cached.length > 0) {
      this.memoryCache.set(cacheKey, cached);
      return cached;
    }

    const usfm = BOOK_ABBREVS[bookNumber];
    if (!usfm) {
      throw new Error(`Invalid book number: ${bookNumber}`);
    }

    let verses: BibleVerse[] = [];
    try {
      verses = await this.fetchWithProvider(config.provider, config, usfm, chapter);
    } catch (err) {
      if (config.fallbackProvider) {
        verses = await this.fetchWithProvider(
          config.fallbackProvider,
          config,
          usfm,
          chapter,
        );
      } else {
        throw err;
      }
    }

    if (verses.length === 0 && config.fallbackProvider) {
      verses = await this.fetchWithProvider(
        config.fallbackProvider,
        config,
        usfm,
        chapter,
      );
    }

    if (verses.length === 0) {
      throw new Error(`Empty response from online provider for ${usfm} ${chapter}`);
    }

    this.memoryCache.set(cacheKey, verses);
    void this.idb.set(cacheKey, verses, ONLINE_CACHE_REV);
    return verses;
  }

  private async fetchWithProvider(
    provider: OnlineProvider,
    config: OnlineBibleConfig,
    usfm: string,
    chapter: number,
  ): Promise<BibleVerse[]> {
    if (provider === 'apiBible') {
      return this.fetchApiBible(config, usfm, chapter);
    }
    return this.fetchYouVersion(config, usfm, chapter);
  }

  private async fetchApiBible(
    config: OnlineBibleConfig,
    usfm: string,
    chapter: number,
  ): Promise<BibleVerse[]> {
    if (!config.apiBibleId) return [];
    const url =
      `https://api.scripture.api.bible/v1/bibles/${config.apiBibleId}/chapters/${usfm}.${chapter}` +
      `?content-type=json&include-notes=false&include-titles=false` +
      `&include-chapter-numbers=false&include-verse-numbers=true&include-verse-spans=true`;

    const res = await firstValueFrom(
      this.http
        .get<{ data?: { content?: unknown[] } }>(url, {
          headers: new HttpHeaders({ 'api-key': API_BIBLE_KEY }),
        })
        .pipe(timeout(10000)),
    );

    const content = res?.data?.content;
    if (!Array.isArray(content)) return [];

    const rawVerses = new Map<string, string>();
    let currentKey: string | null = null;

    const walk = (node: unknown): void => {
      if (!node || typeof node !== 'object') return;
      const obj = node as Record<string, unknown>;
      const name = typeof obj['name'] === 'string' ? obj['name'] : null;
      const attrs =
        obj['attrs'] && typeof obj['attrs'] === 'object'
          ? (obj['attrs'] as Record<string, unknown>)
          : null;

      if (name === 'verse' && attrs) {
        const numAttr = attrs['number'] ?? attrs['sid'];
        if (numAttr != null) {
          currentKey = String(numAttr).trim();
          if (!rawVerses.has(currentKey)) {
            rawVerses.set(currentKey, '');
          }
          return;
        }
      }

      if (obj['type'] === 'text' && typeof obj['text'] === 'string' && currentKey) {
        rawVerses.set(currentKey, (rawVerses.get(currentKey) ?? '') + obj['text']);
      }

      if (Array.isArray(obj['items'])) {
        for (const child of obj['items']) {
          walk(child);
        }
      }
    };

    for (const node of content) {
      walk(node);
    }

    return this.normalizeVerseMap(rawVerses);
  }

  private async fetchYouVersion(
    config: OnlineBibleConfig,
    usfm: string,
    chapter: number,
  ): Promise<BibleVerse[]> {
    if (!config.youVersionId) return [];
    const url = `https://api.youversion.com/v1/bibles/${config.youVersionId}/passages/${usfm}.${chapter}?format=html`;

    const res = await firstValueFrom(
      this.http
        .get<{ content?: string }>(url, {
          headers: new HttpHeaders({ 'X-YVP-App-Key': YOUVERSION_APP_KEY }),
        })
        .pipe(timeout(10000)),
    );

    const html = res?.content;
    if (!html || typeof DOMParser === 'undefined') return [];

    const doc = new DOMParser().parseFromString(html, 'text/html');
    const rawVerses = new Map<string, string>();
    let currentKey: string | null = null;

    const walkDom = (node: Node): void => {
      if (node.nodeType === Node.ELEMENT_NODE) {
        const el = node as Element;
        if (el.classList.contains('yv-vlbl')) {
          return;
        }
        if (el.classList.contains('yv-v')) {
          const vAttr = el.getAttribute('v');
          if (vAttr) {
            currentKey = vAttr.trim();
            if (!rawVerses.has(currentKey)) {
              rawVerses.set(currentKey, '');
            }
          }
        }
      } else if (node.nodeType === Node.TEXT_NODE && currentKey) {
        rawVerses.set(
          currentKey,
          (rawVerses.get(currentKey) ?? '') + (node.textContent ?? ''),
        );
      }

      for (const child of Array.from(node.childNodes)) {
        walkDom(child);
      }
    };

    walkDom(doc.body);
    return this.normalizeVerseMap(rawVerses);
  }

  private normalizeVerseMap(rawVerses: Map<string, string>): BibleVerse[] {
    const map = new Map<number, BibleVerse>();
    for (const [key, rawText] of rawVerses.entries()) {
      const text = rawText.replace(/\s+/g, ' ').trim();
      if (!text) continue;

      const spanMatch = key.match(/(\d+)\s*[-–]\s*(\d+)/);
      if (spanMatch) {
        const start = Number.parseInt(spanMatch[1], 10) || 1;
        map.set(start, { verse: start, text });
      } else {
        const singleMatch = key.match(/(\d+)$/);
        if (singleMatch) {
          const v = Number.parseInt(singleMatch[1], 10) || 1;
          map.set(v, { verse: v, text });
        }
      }
    }
    return Array.from(map.values()).sort((a, b) => a.verse - b.verse);
  }
}
