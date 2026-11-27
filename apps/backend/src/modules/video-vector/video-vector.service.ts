import { Injectable, Logger, Optional } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHash } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';

export interface VideoVectorInput {
  id: string;
  title: string;
  description?: string | null;
  channelId: string;
  channelName: string;
  type?: string | null;
  category?: string | null;
  tags?: string[] | null;
  metadata?: unknown;
  publishedAt?: Date | string | null;
}

export interface VideoVectorFilter {
  type?: 'VIDEO' | 'SHORT' | 'ALL';
  category?: string;
  channelId?: string;
  channelIds?: string[];
  excludeChannelIds?: string[];
}

export interface VideoVectorQueryResult {
  ids: string[];
  degraded: boolean;
}

interface RawVectorHit {
  id: string;
  score: number;
}

@Injectable()
export class VideoVectorService {
  private readonly logger = new Logger(VideoVectorService.name);
  private readonly restUrl: string;
  private readonly restToken: string;
  private readonly namespace: string;
  private readonly timeoutMs: number;
  private readonly minScore: number;
  private readonly maxInlineOps: number;
  private readonly readOnly: boolean;

  private circuitOpenUntil = 0;
  private supportsDenseQueryMode = true;
  private lastError: string | null = null;
  private lastSuccessAt: number | null = null;

  constructor(
    private readonly configService: ConfigService,
    @Optional() private readonly prisma?: PrismaService,
  ) {
    this.restUrl = (
      this.configService.get<string>('upstashVideoVector.restUrl') ||
      process.env.UPSTASH_VIDEO_VECTOR_REST_URL ||
      this.configService.get<string>('upstashVector.restUrl') ||
      process.env.UPSTASH_VECTOR_REST_URL ||
      ''
    )
      .trim()
      .replace(/\/+$/, '');

    this.restToken = (
      this.configService.get<string>('upstashVideoVector.restToken') ||
      process.env.UPSTASH_VIDEO_VECTOR_REST_TOKEN ||
      this.configService.get<string>('upstashVector.restToken') ||
      process.env.UPSTASH_VECTOR_REST_TOKEN ||
      ''
    ).trim();

    const instanceId =
      this.configService.get<string>('instanceId') ||
      process.env.INSTANCE_ID ||
      'christian_tube';
    this.namespace = (
      this.configService.get<string>('upstashVideoVector.namespace') ||
      process.env.UPSTASH_VIDEO_VECTOR_NAMESPACE ||
      (instanceId === 'christian_tube' ? 'videos' : `videos_${instanceId}`)
    ).trim();

    this.timeoutMs =
      this.configService.get<number>('upstashVideoVector.timeoutMs') || 2500;
    const rawMin = this.configService.get<number>('upstashVideoVector.minScore');
    this.minScore = Number.isFinite(rawMin) ? Number(rawMin) : 0.72;
    const rawCap = this.configService.get<number>(
      'upstashVideoVector.maxInlineOps',
    );
    this.maxInlineOps =
      Number.isFinite(rawCap) && Number(rawCap) > 0 ? Number(rawCap) : 200;
    this.readOnly =
      this.configService.get<boolean>('upstashVideoVector.readOnly') === true ||
      process.env.UPSTASH_VIDEO_VECTOR_READ_ONLY === 'true';
  }

  isEnabled(): boolean {
    return Boolean(this.restUrl && this.restToken);
  }

  isCircuitOpen(): boolean {
    return Date.now() < this.circuitOpenUntil;
  }

  getStatus() {
    return {
      enabled: this.isEnabled(),
      provider: this.isEnabled() ? 'upstash-vector' : 'none',
      namespace: this.namespace,
      minScore: this.minScore,
      circuitOpen: this.isCircuitOpen(),
      lastError: this.lastError,
      lastSuccessAt: this.lastSuccessAt
        ? new Date(this.lastSuccessAt).toISOString()
        : null,
    };
  }

  /**
   * Strips HTML/CT_META comments, URLs, emails, handles, and hashtag walls
   * before embedding so boilerplate channel footers do not dominate vectors.
   */
  scrubDescription(raw?: string | null, maxChars = 220): string {
    if (!raw) return '';
    const cleaned = raw
      .replace(/<!--[\s\S]*?-->/g, ' ')
      .replace(/https?:\/\/\S+/gi, ' ')
      .replace(/\bwww\.\S+/gi, ' ')
      .replace(/\b[\w.+-]+@[\w-]+\.[\w.-]+\b/g, ' ')
      .replace(/@[\w.-]+/g, ' ')
      .replace(/(?:#[\w-]+(?:\s+|$)){3,}/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
    if (cleaned.length <= maxChars) return cleaned;
    return cleaned.slice(0, maxChars).replace(/\s+\S*$/, '').trim();
  }

  private extractMetadataHints(meta: unknown): string {
    if (!meta || typeof meta !== 'object') return '';
    const m = meta as Record<string, unknown>;
    const parts: string[] = [];
    for (const key of ['speaker', 'preacher', 'artist', 'book', 'scripture', 'topic']) {
      const val = m[key];
      if (typeof val === 'string' && val.trim()) {
        parts.push(val.trim());
      } else if (Array.isArray(val)) {
        const joined = val
          .filter((v): v is string => typeof v === 'string' && v.trim().length > 0)
          .slice(0, 4)
          .join(', ');
        if (joined) parts.push(joined);
      }
    }
    return parts.join(', ');
  }

  buildDocument(video: VideoVectorInput): {
    id: string;
    data: string;
    hash: string;
    metadata: Record<string, string | number>;
  } {
    const title = (video.title || '').trim();
    const channelName = (video.channelName || '').trim();
    const category = (video.category || '').trim();
    const tags = Array.isArray(video.tags)
      ? video.tags
          .map((t) => String(t || '').replace(/^#/, '').trim())
          .filter((t) => t.length > 0 && t.toLowerCase() !== 'shorts')
          .slice(0, 8)
          .join(', ')
      : '';
    const hints = this.extractMetadataHints(video.metadata);
    const desc = this.scrubDescription(video.description, 220);

    const data = [title, channelName, category, tags, hints, desc]
      .filter((p) => p.length > 0)
      .join(' | ');

    const type = video.type === 'SHORT' ? 'SHORT' : 'VIDEO';
    const publishedAtSec = video.publishedAt
      ? Math.floor(new Date(video.publishedAt).getTime() / 1000) || 0
      : 0;

    const metadata: Record<string, string | number> = {
      type,
      channelId: video.channelId,
      publishedAt: publishedAtSec,
    };
    if (category) {
      metadata.category = category;
    }

    const hash = createHash('sha256')
      .update(`${data}|${type}|${video.channelId}|${category}`)
      .digest('hex');

    return { id: video.id, data, hash, metadata };
  }

  private escapeFilterValue(val: string): string {
    return val.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
  }

  buildFilterExpression(filter?: VideoVectorFilter): string | undefined {
    if (!filter) return undefined;
    const parts: string[] = [];

    if (filter.type && filter.type !== 'ALL') {
      parts.push(`type = '${this.escapeFilterValue(filter.type)}'`);
    }
    if (filter.category && filter.category !== 'All') {
      parts.push(`category = '${this.escapeFilterValue(filter.category)}'`);
    }
    if (filter.channelId) {
      parts.push(`channelId = '${this.escapeFilterValue(filter.channelId)}'`);
    } else if (
      filter.channelIds &&
      filter.channelIds.length > 0 &&
      filter.channelIds.length <= 25
    ) {
      const list = filter.channelIds
        .map((id) => `'${this.escapeFilterValue(id)}'`)
        .join(', ');
      parts.push(`channelId IN (${list})`);
    }

    if (
      !filter.channelId &&
      filter.excludeChannelIds &&
      filter.excludeChannelIds.length > 0 &&
      filter.excludeChannelIds.length <= 20
    ) {
      const list = filter.excludeChannelIds
        .map((id) => `'${this.escapeFilterValue(id)}'`)
        .join(', ');
      parts.push(`channelId NOT IN (${list})`);
    }

    return parts.length > 0 ? parts.join(' AND ') : undefined;
  }

  /**
   * Semantic vector search via Upstash Vector hosted embeddings (/query-data).
   * Uses DENSE cosine similarity so noise thresholding is calibrated in [0, 1].
   */
  async query(
    rawQuery: string,
    filter?: VideoVectorFilter,
    topK = 80,
  ): Promise<VideoVectorQueryResult> {
    const clean = (rawQuery || '').trim().slice(0, 200);
    if (!this.isEnabled() || clean.length < 2) {
      return { ids: [], degraded: false };
    }
    if (this.isCircuitOpen()) {
      return { ids: [], degraded: true };
    }

    const endpoint = this.namespace
      ? `${this.restUrl}/query-data/${encodeURIComponent(this.namespace)}`
      : `${this.restUrl}/query-data`;

    const filterExpr = this.buildFilterExpression(filter);
    const body: Record<string, unknown> = {
      data: clean,
      topK: Math.max(1, Math.min(200, topK)),
      includeMetadata: false,
    };
    if (this.supportsDenseQueryMode) {
      body.queryMode = 'DENSE';
    }
    if (filterExpr) {
      body.filter = filterExpr;
    }

    const runFetch = async (payloadBody: Record<string, unknown>) => {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), this.timeoutMs);
      try {
        return await fetch(endpoint, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${this.restToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(payloadBody),
          signal: controller.signal,
        });
      } finally {
        clearTimeout(timer);
      }
    };

    try {
      let res = await runFetch(body);

      // Pure-dense indexes may reject the `queryMode` field with HTTP 400.
      if (res.status === 400 && this.supportsDenseQueryMode) {
        const errText = await res.text().catch(() => '');
        if (errText.toLowerCase().includes('querymode') || errText.toLowerCase().includes('hybrid')) {
          this.supportsDenseQueryMode = false;
          delete body.queryMode;
          res = await runFetch(body);
        } else {
          this.recordFailure(`HTTP 400 ${errText.slice(0, 180)}`, 30_000);
          return { ids: [], degraded: true };
        }
      }

      if (res.status === 429) {
        this.recordFailure('Upstash Vector daily quota reached (429)', 5 * 60_000);
        return { ids: [], degraded: true };
      }
      if (!res.ok) {
        const errText = await res.text().catch(() => '');
        this.recordFailure(`HTTP ${res.status} ${errText.slice(0, 180)}`, 30_000);
        return { ids: [], degraded: true };
      }

      const payload = (await res.json()) as {
        result?: RawVectorHit[];
        error?: string;
      };
      if (payload.error) {
        this.recordFailure(payload.error, 30_000);
        return { ids: [], degraded: true };
      }

      this.lastError = null;
      this.lastSuccessAt = Date.now();

      const rawHits = Array.isArray(payload.result) ? payload.result : [];
      if (rawHits.length === 0) {
        return { ids: [], degraded: false };
      }

      const maxScore = rawHits.reduce((m, h) => Math.max(m, Number(h.score || 0)), 0);
      const adaptiveGap = maxScore >= 0.85 ? 0.14 : maxScore >= 0.72 ? 0.12 : 0.10;
      const cutoff = Math.max(this.minScore, maxScore - adaptiveGap);

      const ids = rawHits
        .filter((h) => h?.id && Number(h.score || 0) >= cutoff)
        .map((h) => String(h.id));

      return { ids, degraded: false };
    } catch (err: any) {
      this.recordFailure(err?.message || 'timeout', 30_000);
      return { ids: [], degraded: true };
    }
  }

  /**
   * Hash-gated, budget-capped upsert into Upstash Vector.
   * Only writes videos that are new or whose text/metadata hash changed.
   */
  async upsertVideos(
    videos: VideoVectorInput[],
    opts?: { maxOps?: number; skipHashCheck?: boolean },
  ): Promise<{ upserted: number; skipped: number }> {
    if (!this.isEnabled() || this.readOnly || this.isCircuitOpen() || !videos.length) {
      return { upserted: 0, skipped: videos.length };
    }

    const cap = opts?.maxOps ?? this.maxInlineOps;
    const dedup = new Map<string, VideoVectorInput>();
    for (const v of videos) {
      if (v?.id) dedup.set(v.id, v);
    }
    const uniqueVideos = Array.from(dedup.values()).slice(0, cap);
    const docs = uniqueVideos.map((v) => this.buildDocument(v));

    let toUpsert = docs;
    if (!opts?.skipHashCheck && this.prisma) {
      try {
        const ids = docs.map((d) => d.id);
        const existing: Array<{ videoId: string; upstashHash: string | null }> =
          await this.prisma.$queryRawUnsafe(
            `SELECT "videoId", "embedding"->>'upstashHash' AS "upstashHash"
             FROM "VideoPipelineStatus"
             WHERE "videoId" = ANY($1::text[])`,
            ids,
          );
        const existingMap = new Map(existing.map((r) => [r.videoId, r.upstashHash]));
        toUpsert = docs.filter((d) => existingMap.get(d.id) !== d.hash);
      } catch (err: any) {
        this.logger.warn(`Could not read VideoPipelineStatus hashes: ${err?.message || err}`);
      }
    }

    if (toUpsert.length === 0) {
      return { upserted: 0, skipped: docs.length };
    }

    const endpoint = this.namespace
      ? `${this.restUrl}/upsert-data/${encodeURIComponent(this.namespace)}`
      : `${this.restUrl}/upsert-data`;

    let upserted = 0;
    for (let i = 0; i < toUpsert.length; i += 100) {
      if (this.isCircuitOpen()) break;
      const batch = toUpsert.slice(i, i + 100);
      const body = batch.map((d) => ({
        id: d.id,
        data: d.data,
        metadata: d.metadata,
      }));

      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), Math.max(this.timeoutMs, 8000));
      try {
        const res = await fetch(endpoint, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${this.restToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(body),
          signal: controller.signal,
        });

        if (res.status === 429) {
          this.recordFailure('Upstash Vector daily update quota reached (429)', 5 * 60_000);
          break;
        }
        if (!res.ok) {
          const text = await res.text().catch(() => '');
          this.recordFailure(`Upsert HTTP ${res.status} ${text.slice(0, 160)}`, 30_000);
          break;
        }

        upserted += batch.length;
        this.lastSuccessAt = Date.now();
        this.lastError = null;
        await this.markUpstashSynced(batch);
      } catch (err: any) {
        this.recordFailure(`Upsert error: ${err?.message || err}`, 30_000);
        break;
      } finally {
        clearTimeout(timer);
      }
    }

    return { upserted, skipped: docs.length - upserted };
  }

  /**
   * Budget-capped vector deletion from Upstash Vector.
   */
  async deleteIds(ids: string[], opts?: { maxOps?: number }): Promise<number> {
    if (!this.isEnabled() || this.readOnly || this.isCircuitOpen() || !ids.length) {
      return 0;
    }

    const cap = opts?.maxOps ?? this.maxInlineOps;
    const unique = Array.from(new Set(ids.filter(Boolean))).slice(0, cap);
    const endpoint = this.namespace
      ? `${this.restUrl}/delete/${encodeURIComponent(this.namespace)}`
      : `${this.restUrl}/delete`;

    let deleted = 0;
    for (let i = 0; i < unique.length; i += 100) {
      if (this.isCircuitOpen()) break;
      const chunk = unique.slice(i, i + 100);
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), Math.max(this.timeoutMs, 5000));
      try {
        const res = await fetch(endpoint, {
          method: 'DELETE',
          headers: {
            Authorization: `Bearer ${this.restToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ ids: chunk }),
          signal: controller.signal,
        });
        if (res.status === 429) {
          this.recordFailure('Upstash Vector daily delete quota reached (429)', 5 * 60_000);
          break;
        }
        if (!res.ok) {
          const text = await res.text().catch(() => '');
          this.recordFailure(`Delete HTTP ${res.status} ${text.slice(0, 160)}`, 30_000);
          break;
        }
        deleted += chunk.length;
      } catch (err: any) {
        this.recordFailure(`Delete error: ${err?.message || err}`, 30_000);
        break;
      } finally {
        clearTimeout(timer);
      }
    }
    return deleted;
  }

  private async markUpstashSynced(
    batch: Array<{ id: string; hash: string }>,
  ): Promise<void> {
    if (!this.prisma || batch.length === 0) return;
    try {
      const ids = batch.map((b) => b.id);
      const hashes = batch.map((b) => b.hash);
      // FK-safe: join against existing "Video" rows so concurrent deletes never throw 23503.
      await this.prisma.$executeRawUnsafe(
        `INSERT INTO "VideoPipelineStatus" ("videoId", "embedding", "updatedAt")
         SELECT v.id, jsonb_build_object('upstashHash', u.hash), CURRENT_TIMESTAMP
         FROM unnest($1::text[], $2::text[]) AS u(id, hash)
         JOIN "Video" v ON v.id = u.id
         ON CONFLICT ("videoId") DO UPDATE SET
           "embedding" = COALESCE("VideoPipelineStatus"."embedding", '{}'::jsonb)
                         || jsonb_build_object('upstashHash', EXCLUDED."embedding"->>'upstashHash'),
           "updatedAt" = CURRENT_TIMESTAMP`,
        ids,
        hashes,
      );
    } catch (err: any) {
      this.logger.warn(`Failed to record upstashHash: ${err?.message || err}`);
    }
  }

  private recordFailure(message: string, cooldownMs: number): void {
    this.lastError = message;
    this.circuitOpenUntil = Date.now() + cooldownMs;
    this.logger.warn(`VideoVectorService: ${message}`);
  }
}
