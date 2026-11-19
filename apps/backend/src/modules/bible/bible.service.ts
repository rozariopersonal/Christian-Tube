import { Injectable, Logger, Optional } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { CacheService } from '../cache/cache.service';

export interface BibleSearchHit {
  id: string;
  score: number;
  bookNumber: number | null;
  bookName: string | null;
  chapter: number | null;
  verse: number | null;
  reference: string;
  text: string;
}

export interface BibleSearchResponse {
  query: string;
  count: number;
  results: BibleSearchHit[];
}

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
    const cacheKey = `search:${limit}:${normalized}`;

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
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);

    try {
      const res = await fetch(`${this.restUrl}/query-data`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${this.restToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          data: query,
          topK: limit,
          includeMetadata: true,
        }),
        signal: controller.signal,
      });

      if (!res.ok) {
        const text = await res.text().catch(() => '');
        throw new Error(`HTTP ${res.status} ${text.slice(0, 200)}`);
      }

      const payload = (await res.json()) as {
        result?: Array<{
          id: string;
          score: number;
          metadata?: Record<string, any>;
        }>;
        error?: string;
      };

      if (payload.error) {
        throw new Error(payload.error);
      }

      const rawHits = Array.isArray(payload.result) ? payload.result : [];
      const results: BibleSearchHit[] = rawHits.map((hit) => {
        const meta = hit.metadata || {};
        const bookNumber = meta.b != null ? Number(meta.b) : null;
        const bookName = typeof meta.n === 'string' ? meta.n : null;
        const chapter = meta.c != null ? Number(meta.c) : null;
        const verse = meta.v != null ? Number(meta.v) : null;
        const reference =
          bookName && chapter != null && verse != null
            ? `${bookName} ${chapter}:${verse}`
            : String(hit.id);

        return {
          id: String(hit.id),
          score: Number(hit.score || 0),
          bookNumber,
          bookName,
          chapter,
          verse,
          reference,
          text: typeof meta.text === 'string' ? meta.text : '',
        };
      });

      return {
        query,
        count: results.length,
        results,
      };
    } finally {
      clearTimeout(timer);
    }
  }
}
