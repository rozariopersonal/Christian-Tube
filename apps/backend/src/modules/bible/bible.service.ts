import { Injectable, Logger, Optional } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { CacheService } from '../cache/cache.service';

export interface BibleSearchHit {
  id: string;
  score: number;
  kind: 'verse' | 'passage';
  bookNumber: number | null;
  bookName: string | null;
  chapter: number | null;
  verse: number | null;
  endVerse: number | null;
  reference: string;
  text: string;
}

export interface BibleSearchResponse {
  query: string;
  count: number;
  results: BibleSearchHit[];
}

interface RawVectorHit {
  id: string;
  score: number;
  metadata?: Record<string, any>;
}

const MIN_DENSE_SCORE = 0.745;
const KEYWORD_BONUS_WEIGHT = 0.04;
const STOP_WORDS = new Set([
  'the',
  'and',
  'for',
  'with',
  'that',
  'this',
  'was',
  'were',
  'are',
  'his',
  'her',
  'him',
  'you',
  'your',
  'from',
  'into',
  'who',
  'what',
  'when',
  'where',
  'why',
  'how',
  'come',
  'without',
  'not',
]);

@Injectable()
export class BibleService {
  private readonly logger = new Logger(BibleService.name);
  private readonly restUrl: string;
  private readonly restToken: string;
  private readonly timeoutMs: number;
  private readonly cacheTtlSec = 2592000; // 30 days (Bible verses are static)

  constructor(
    private readonly configService: ConfigService,
    @Optional() private readonly cache?: CacheService,
  ) {
    this.restUrl = (
      this.configService.get<string>('upstashVector.restUrl') ||
      process.env.UPSTASH_VECTOR_REST_URL ||
      ''
    )
      .trim()
      .replace(/\/+$/, '');
    this.restToken = (
      this.configService.get<string>('upstashVector.restToken') ||
      process.env.UPSTASH_VECTOR_REST_TOKEN ||
      ''
    ).trim();
    this.timeoutMs =
      this.configService.get<number>('upstashVector.timeoutMs') || 3000;
  }

  isEnabled(): boolean {
    return Boolean(this.restUrl && this.restToken);
  }

  getStatus(): { enabled: boolean; provider: string } {
    return {
      enabled: this.isEnabled(),
      provider: this.isEnabled() ? 'upstash-vector' : 'none',
    };
  }

  async search(rawQuery?: string, rawLimit?: number): Promise<BibleSearchResponse> {
    const query = (rawQuery || '').trim();
    if (!query || !this.isEnabled()) {
      return { query, count: 0, results: [] };
    }

    const parsedLimit = Number(rawLimit);
    const limit = Number.isFinite(parsedLimit)
      ? Math.max(1, Math.min(50, Math.floor(parsedLimit)))
      : 20;

    const normalized = query.toLowerCase().replace(/\s+/g, ' ');
    const cacheKey = `search:v3:${limit}:${normalized}`;

    try {
      if (this.cache) {
        return await this.cache.getOrSet(
          'bible',
          cacheKey,
          this.cacheTtlSec,
          () => this.queryUpstashVector(query, limit),
        );
      }
      return await this.queryUpstashVector(query, limit);
    } catch (err: any) {
      this.logger.warn(
        `Upstash Vector Bible search failed for "${query}": ${err?.message || err}`,
      );
      return { query, count: 0, results: [] };
    }
  }

  private async queryUpstashVector(
    query: string,
    limit: number,
  ): Promise<BibleSearchResponse> {
    const fetchTopK = Math.min(50, Math.max(limit, 25));
    const [verseHits, windowHits] = await Promise.all([
      this.queryNamespace(query, fetchTopK, ''),
      this.queryNamespace(query, fetchTopK, 'windows').catch((err: any) => {
        this.logger.warn(
          `Upstash Vector windows namespace query failed for "${query}": ${err?.message || err}`,
        );
        return [] as BibleSearchHit[];
      }),
    ]);

    const seen = new Set<string>();
    const combined: BibleSearchHit[] = [];
    for (const hit of [...verseHits, ...windowHits]) {
      if (seen.has(hit.id)) continue;
      seen.add(hit.id);
      combined.push(hit);
    }

    const maxDense = combined.reduce((m, h) => Math.max(m, h.score), 0);
    const adaptiveGap =
      maxDense >= 0.86 ? 0.052 : maxDense >= 0.8 ? 0.055 : 0.06;
    const cutoff = Math.max(MIN_DENSE_SCORE, maxDense - adaptiveGap);
    const filtered = combined.filter((h) => h.score >= cutoff);

    const terms = this.extractContentTerms(query);
    const rankScores = new Map<string, number>();
    for (const hit of filtered) {
      const kw = this.keywordMatchFraction(hit.text, terms);
      rankScores.set(hit.id, hit.score + KEYWORD_BONUS_WEIGHT * kw);
    }

    filtered.sort((a, b) => {
      const diff = (rankScores.get(b.id) ?? b.score) - (rankScores.get(a.id) ?? a.score);
      if (Math.abs(diff) > 1e-6) return diff;
      if (a.kind !== b.kind) return a.kind === 'verse' ? -1 : 1;
      return 0;
    });

    const results = filtered.slice(0, limit);
    return {
      query,
      count: results.length,
      results,
    };
  }

  private extractContentTerms(query: string): string[] {
    return query
      .toLowerCase()
      .replace(/[^a-z0-9\s]/g, ' ')
      .split(/\s+/)
      .filter((w) => w.length >= 3 && !STOP_WORDS.has(w));
  }

  private keywordMatchFraction(text: string, terms: string[]): number {
    if (terms.length === 0 || !text) return 0;
    const low = text.toLowerCase();
    let hits = 0;
    for (const term of terms) {
      if (new RegExp(`\\b${term}`).test(low)) hits++;
    }
    return hits / terms.length;
  }

  private async queryNamespace(
    query: string,
    limit: number,
    namespace: string,
  ): Promise<BibleSearchHit[]> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    const endpoint = namespace
      ? `${this.restUrl}/query-data/${encodeURIComponent(namespace)}`
      : `${this.restUrl}/query-data`;

    try {
      const res = await fetch(endpoint, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${this.restToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          data: query,
          topK: limit,
          includeMetadata: true,
          queryMode: 'DENSE',
        }),
        signal: controller.signal,
      });

      if (!res.ok) {
        const text = await res.text().catch(() => '');
        throw new Error(`HTTP ${res.status} ${text.slice(0, 200)}`);
      }

      const payload = (await res.json()) as {
        result?: RawVectorHit[];
        error?: string;
      };

      if (payload.error) {
        throw new Error(payload.error);
      }

      const rawHits = Array.isArray(payload.result) ? payload.result : [];
      return rawHits.map((hit) => this.mapHit(hit, namespace));
    } finally {
      clearTimeout(timer);
    }
  }

  private mapHit(hit: RawVectorHit, namespace: string): BibleSearchHit {
    const meta = hit.metadata || {};
    const bookNumber = meta.b != null ? Number(meta.b) : null;
    const bookName = typeof meta.n === 'string' ? meta.n : null;
    const chapter = meta.c != null ? Number(meta.c) : null;
    const verse = meta.v != null ? Number(meta.v) : null;
    const rawEndV = meta.endV != null ? Number(meta.endV) : null;
    const isWindow =
      namespace === 'windows' ||
      meta.kind === 'window' ||
      (rawEndV != null && verse != null && rawEndV > verse);
    const endVerse = isWindow && rawEndV != null ? rawEndV : null;

    let reference = String(hit.id);
    if (bookName && chapter != null && verse != null) {
      reference =
        endVerse != null && endVerse > verse
          ? `${bookName} ${chapter}:${verse}-${endVerse}`
          : `${bookName} ${chapter}:${verse}`;
    }

    return {
      id: String(hit.id),
      score: Number(hit.score || 0),
      kind: isWindow ? 'passage' : 'verse',
      bookNumber,
      bookName,
      chapter,
      verse,
      endVerse,
      reference,
      text: typeof meta.text === 'string' ? meta.text : '',
    };
  }
}
