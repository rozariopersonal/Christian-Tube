import {
  Injectable,
  NotFoundException,
  BadRequestException,
  ServiceUnavailableException,
  Logger,
  OnModuleInit,
  Optional,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { PrismaService } from "../prisma/prisma.service";
import { EmbeddingService } from "../embedding/embedding.service";
import { CacheService } from "../cache/cache.service";
import { YoutubeService } from "../youtube/youtube.service";
import { VideoVectorService } from "../video-vector/video-vector.service";

interface VideoQuery {
  category?: string;
  type?: "VIDEO" | "SHORT" | "ALL";
  channelId?: string;
  channelIds?: string | string[];
  search?: string;
  sort?: "latest" | "popular" | "oldest" | "relevance";
  limit?: number;
  offset?: number;
  publishedBefore?: string;
  beforeId?: string;
  publishedAfter?: string;
  afterId?: string;
}

interface BaseFilterSql {
  clause: string;
  params: any[];
}

interface CandidateListCacheEntry {
  ids: string[];
  degraded: boolean;
}

const YOUTUBE_URL_ID_RE =
  /(?:youtube\.com\/(?:watch\?v=|shorts\/|embed\/)|youtu\.be\/)([A-Za-z0-9_-]{11})/i;
const RAW_YOUTUBE_ID_RE = /^[A-Za-z0-9_-]{11}$/;

@Injectable()
export class VideosService implements OnModuleInit {
  private readonly logger = new Logger(VideosService.name);
  private inactiveChannelCache: { ids: string[]; expiresAt: number } | null = null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly configService: ConfigService,
    private readonly embeddingService: EmbeddingService,
    @Optional() private readonly cache?: CacheService,
    @Optional() private readonly youtubeService?: YoutubeService,
    @Optional() private readonly videoVector?: VideoVectorService,
  ) {}

  async onModuleInit() {
    if (process.env.NODE_ENV === "test") return;
    // Install searchVector trigger idempotently and backfill NULL rows in 1k batches without blocking boot.
    setTimeout(() => {
      this.ensureSearchVectorTriggerAndBackfill().catch((err: any) => {
        this.logger.warn(`Search vector bootstrap note: ${err?.message || err}`);
      });
    }, 2000);
  }

  private async ensureSearchVectorTriggerAndBackfill(): Promise<void> {
    if (typeof (this.prisma as any).$executeRawUnsafe !== "function") return;
    try {
      // Self-heal extension, column, and GIN indexes even if `prisma db push` skipped due to unrelated schema drift.
      await this.prisma.$executeRawUnsafe(`CREATE EXTENSION IF NOT EXISTS pg_trgm;`);
      await this.prisma.$executeRawUnsafe(`ALTER TABLE "Video" ADD COLUMN IF NOT EXISTS "searchVector" tsvector;`);
      await this.prisma.$executeRawUnsafe(`CREATE INDEX IF NOT EXISTS "Video_searchVector_idx" ON "Video" USING GIN ("searchVector");`);
      await this.prisma.$executeRawUnsafe(`CREATE INDEX IF NOT EXISTS "Video_title_trgm_idx" ON "Video" USING GIN ("title" gin_trgm_ops);`);
      await this.prisma.$executeRawUnsafe(`CREATE INDEX IF NOT EXISTS "Video_channelName_trgm_idx" ON "Video" USING GIN ("channelName" gin_trgm_ops);`);

      await this.prisma.$executeRawUnsafe(`
        CREATE OR REPLACE FUNCTION video_search_vector_update() RETURNS trigger AS $$
        BEGIN
          NEW."searchVector" :=
            setweight(to_tsvector('simple', coalesce(NEW.title, '')), 'A') ||
            setweight(to_tsvector('english', coalesce(NEW.title, '')), 'A') ||
            setweight(to_tsvector('simple', coalesce(NEW."channelName", '')), 'B') ||
            setweight(to_tsvector('english', coalesce(left(regexp_replace(coalesce(NEW.description, ''), '<!--.*?-->', ' ', 'gs'), 1000), '')), 'C');
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
      `);

      await this.prisma.$executeRawUnsafe(`
        DO $$
        BEGIN
          IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'video_search_vector_trg') THEN
            CREATE TRIGGER video_search_vector_trg
            BEFORE INSERT OR UPDATE OF title, "channelName", description
            ON "Video"
            FOR EACH ROW
            EXECUTE FUNCTION video_search_vector_update();
          END IF;
        END $$;
      `);

      // Non-blocking batched backfill of 1,000 rows at a time (prevents 30k-row lock & WAL spike)
      for (let batch = 0; batch < 100; batch++) {
        const updated = await this.prisma.$executeRawUnsafe(`
          UPDATE "Video"
          SET "searchVector" =
            setweight(to_tsvector('simple', coalesce(title, '')), 'A') ||
            setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
            setweight(to_tsvector('simple', coalesce("channelName", '')), 'B') ||
            setweight(to_tsvector('english', coalesce(left(regexp_replace(coalesce(description, ''), '<!--.*?-->', ' ', 'gs'), 1000), '')), 'C')
          WHERE id IN (
            SELECT id FROM "Video" WHERE "searchVector" IS NULL LIMIT 1000 FOR UPDATE SKIP LOCKED
          );
        `);
        if (!updated || Number(updated) < 1000) break;
        await new Promise((r) => setTimeout(r, 100));
      }
    } catch (err: any) {
      this.logger.warn(`searchVector trigger/backfill skipped: ${err?.message || err}`);
    }
  }

  private clampLimit(raw?: number): number {
    const n = Number(raw);
    if (!Number.isFinite(n) || n <= 0) return 50;
    return Math.max(1, Math.min(100, Math.floor(n)));
  }

  private clampOffset(raw?: number): number {
    const n = Number(raw);
    if (!Number.isFinite(n) || n < 0) return 0;
    return Math.max(0, Math.min(10_000, Math.floor(n)));
  }

  private parseChannelIds(raw?: string | string[]): string[] {
    if (!raw) return [];
    const list = Array.isArray(raw) ? raw : raw.split(",");
    return list.map((id) => id.trim()).filter(Boolean);
  }

  private extractDirectYoutubeId(rawSearch: string): string | null {
    const trimmed = rawSearch.trim();
    const urlMatch = trimmed.match(YOUTUBE_URL_ID_RE);
    if (urlMatch) return urlMatch[1];
    // Only treat bare 11-char tokens as YouTube IDs if they contain a digit, hyphen, or underscore
    // (avoids mistaking normal 11-letter English words like "forgiveness" for a video ID).
    if (RAW_YOUTUBE_ID_RE.test(trimmed) && /[0-9_-]/.test(trimmed)) {
      return trimmed;
    }
    return null;
  }

  private buildFeedCacheKey(query: VideoQuery): string {
    const channelIds = this.parseChannelIds(query.channelIds).join(",");
    const limit = this.clampLimit(query.limit);
    const offset = this.clampOffset(query.offset);
    const search = (query.search || "").trim().toLowerCase().replace(/\s+/g, " ");
    const sort = query.sort || (search ? "relevance" : "latest");
    return [
      `type=${query.type || "VIDEO"}`,
      `sort=${query.sort || "latest"}`,
      `cat=${query.category || "All"}`,
      `ch=${query.channelId || ""}`,
      `chs=${channelIds}`,
      `sort=${sort}`,
      `q=${search}`,
      `lim=${limit}`,
      `off=${offset}`,
      `before=${query.publishedBefore || ""}`,
      `beforeId=${query.beforeId || ""}`,
      `after=${query.publishedAfter || ""}`,
      `afterId=${query.afterId || ""}`,
    ].join(":");
  }

  private buildSearchCandidateKey(query: VideoQuery): string {
    const channelIds = this.parseChannelIds(query.channelIds).join(",");
    const search = (query.search || "").trim().toLowerCase().replace(/\s+/g, " ");
    return [
      `cand`,
      `type=${query.type || "VIDEO"}`,
      `cat=${query.category || "All"}`,
      `ch=${query.channelId || ""}`,
      `chs=${channelIds}`,
      `q=${search}`,
    ].join(":");
  }

  async findAll(query: VideoQuery) {
    const normalizedSearch = (query.search || "").trim();
    if (!normalizedSearch) {
      if (this.cache) {
        return this.cache.getOrSet(
          "videos",
          `feed:${this.buildFeedCacheKey(query)}`,
          86400,
          () => this.findAllUncached(query),
        );
      }
      return this.findAllUncached(query);
    }

    const effectiveSort = query.sort || "relevance";
    if (effectiveSort === "relevance") {
      return this.searchByRelevance(query, normalizedSearch);
    }

    if (this.cache) {
      return this.cache.getOrSet(
        "video-search",
        `sorted:${this.buildFeedCacheKey(query)}`,
        6 * 3600,
        () => this.searchSorted(query, normalizedSearch),
      );
    }
    return this.searchSorted(query, normalizedSearch);
  }

  private async findAllUncached(query: VideoQuery) {
    const where: any = {
      channel: {
        isActive: true,
      },
    };

    this.applyVideoTypeFilter(where, query.type);
    this.applyCategoryFilter(where, query.category);
    this.applyChannelFilter(where, query.channelId, query.channelIds);

    if (query.publishedBefore) {
      const before = new Date(query.publishedBefore);
      if (!Number.isNaN(before.getTime())) {
        where.AND = [
          ...(where.AND || []),
          {
            OR: [
              { publishedAt: { lt: before } },
              ...(query.beforeId
                ? [{ publishedAt: before, id: { lt: query.beforeId } }]
                : []),
            ],
          },
        ];
      }
    }

    if (query.publishedAfter) {
      const after = new Date(query.publishedAfter);
      if (!Number.isNaN(after.getTime())) {
        where.AND = [
          ...(where.AND || []),
          { OR: [
            { publishedAt: { gt: after } },
            ...(query.afterId ? [{ publishedAt: after, id: { gt: query.afterId } }] : []),
          ] },
        ];
      }
    }

    const limit = this.clampLimit(query.limit);
    const offset = this.clampOffset(query.offset);
    return this.fetchKeywords(where, limit, offset, query.sort);
  }

  private async searchByRelevance(query: VideoQuery, search: string) {
    const limit = this.clampLimit(query.limit);
    const offset = this.clampOffset(query.offset);

    // Cache top-100 fused candidate IDs across pages so infinite scroll = 1 Upstash op total.
    const loadCandidates = () => this.computeRelevanceCandidates(query, search);
    const entry: CandidateListCacheEntry = this.cache
      ? await this.cache.getOrSet(
          "video-search",
          this.buildSearchCandidateKey(query),
          6 * 3600,
          loadCandidates,
          { shouldCache: (val) => !val.degraded },
        )
      : await loadCandidates();

    if (offset < entry.ids.length) {
      const pageIds = entry.ids.slice(offset, offset + limit);
      return this.fetchEnrichedByIds(pageIds, query);
    }

    // Fall through to Neon lexical pagination past the top-100 fused window.
    if (entry.ids.length >= 100) {
      const extraIds = await this.lexicalSearchIds(query, search, limit, offset);
      const seen = new Set(entry.ids);
      const filtered = extraIds.filter((id) => !seen.has(id));
      return this.fetchEnrichedByIds(filtered, query);
    }

    return [];
  }

  private async computeRelevanceCandidates(
    query: VideoQuery,
    search: string,
  ): Promise<CandidateListCacheEntry> {
    const directId = this.extractDirectYoutubeId(search);
    const channelIds = this.parseChannelIds(query.channelIds);
    const useUpstash = Boolean(this.videoVector?.isEnabled());

    const excludeChannelIds =
      useUpstash && !query.channelId ? await this.getInactiveChannelIds() : [];

    const vectorPromise = useUpstash
      ? this.videoVector!.query(
          search,
          {
            type: query.type || "VIDEO",
            category: query.category,
            channelId: query.channelId,
            channelIds: channelIds.length > 0 ? channelIds : undefined,
            excludeChannelIds:
              excludeChannelIds.length > 0 ? excludeChannelIds : undefined,
          },
          channelIds.length > 25 ? 200 : 100,
        )
      : Promise.resolve({ ids: [] as string[], degraded: false });

    const [vectorRes, lexicalIds] = await Promise.all([
      vectorPromise,
      this.lexicalSearchIds(query, search, 100, 0),
    ]);

    const lists: string[][] = [];
    if (directId) lists.push([directId]);
    if (lexicalIds.length > 0) lists.push(lexicalIds);
    if (vectorRes.ids.length > 0) lists.push(vectorRes.ids);

    let fused = lists.length > 0 ? this.fuseRanks(lists) : [];
    if (directId) {
      fused = [directId, ...fused.filter((id) => id !== directId)];
    }

    return {
      ids: fused.slice(0, 120),
      degraded: vectorRes.degraded,
    };
  }

  private async searchSorted(query: VideoQuery, search: string) {
    const limit = this.clampLimit(query.limit);
    const offset = this.clampOffset(query.offset);
    const ids = await this.lexicalSearchIds(query, search, limit, offset, query.sort);
    if (ids.length > 0) {
      return this.fetchEnrichedByIds(ids, query);
    }
    return [];
  }

  private async getInactiveChannelIds(): Promise<string[]> {
    if (this.inactiveChannelCache && Date.now() < this.inactiveChannelCache.expiresAt) {
      return this.inactiveChannelCache.ids;
    }
    try {
      if (typeof (this.prisma as any).channel?.findMany !== "function") return [];
      const rows = await this.prisma.channel.findMany({
        where: { isActive: false },
        select: { id: true },
        take: 20,
      });
      const ids = rows.map((r) => r.id);
      this.inactiveChannelCache = { ids, expiresAt: Date.now() + 60_000 };
      return ids;
    } catch {
      return [];
    }
  }

  /**
   * Lexical + typo-tolerant search using Postgres FTS (searchVector GIN)
   * UNION ALL word_similarity (pg_trgm GIN) inside a PgBouncer-safe transaction.
   * Gracefully falls back to Prisma ILIKE if raw SQL / pg_trgm is unavailable.
   */
  private async lexicalSearchIds(
    query: VideoQuery,
    search: string,
    limit: number,
    offset: number,
    sort?: VideoQuery["sort"],
  ): Promise<string[]> {
    const clean = search.trim().slice(0, 200);
    if (!clean) return [];

    const hasTransaction =
      typeof (this.prisma as any).$transaction === "function" &&
      typeof (this.prisma as any).$queryRawUnsafe === "function";

    if (hasTransaction) {
      try {
        const filters = this.buildBaseFilterSql(query);
        const qIdx = filters.params.length + 1;
        const likeIdx = qIdx + 1;
        const innerLimIdx = likeIdx + 1;
        const limIdx = innerLimIdx + 1;
        const offIdx = limIdx + 1;
        const escapedLike = clean.toLowerCase().replace(/[\\%_]/g, "\\$&");
        const innerLimit = Math.min(500, Math.max(100, limit + offset));
        const params = [
          ...filters.params,
          clean,
          escapedLike,
          innerLimit,
          limit,
          offset,
        ];

        const innerOrderClause =
          sort === "popular"
            ? 'ORDER BY v."viewCount" DESC, v."publishedAt" DESC'
            : sort === "oldest"
              ? 'ORDER BY v."publishedAt" ASC'
              : sort === "latest"
                ? 'ORDER BY v."publishedAt" DESC'
                : 'ORDER BY score DESC, v."publishedAt" DESC';

        const outerOrderClause =
          sort === "popular"
            ? 'ORDER BY v."viewCount" DESC, v."publishedAt" DESC'
            : sort === "oldest"
              ? 'ORDER BY v."publishedAt" ASC'
              : sort === "latest"
                ? 'ORDER BY v."publishedAt" DESC'
                : 'ORDER BY MAX(c.score) DESC, v."publishedAt" DESC';

        const sql = `
          WITH fts AS (
            SELECT
              v.id,
              (
                ts_rank_cd(v."searchVector", websearch_to_tsquery('english', $${qIdx})) +
                ts_rank_cd(v."searchVector", websearch_to_tsquery('simple', $${qIdx})) +
                CASE WHEN lower(v.title) LIKE $${likeIdx} || '%' ESCAPE '\\' THEN 1.5
                     WHEN lower(v.title) LIKE '%' || $${likeIdx} || '%' ESCAPE '\\' THEN 0.8
                     ELSE 0 END
              ) AS score,
              v."viewCount",
              v."publishedAt"
            FROM "Video" v
            JOIN "Channel" c ON c.id = v."channelId"
            WHERE c."isActive" = true
              ${filters.clause}
              AND v."searchVector" IS NOT NULL
              AND (
                v."searchVector" @@ websearch_to_tsquery('english', $${qIdx})
                OR v."searchVector" @@ websearch_to_tsquery('simple', $${qIdx})
              )
            ${innerOrderClause}
            LIMIT $${innerLimIdx}
          ),
          trgm AS (
            SELECT
              v.id,
              GREATEST(word_similarity($${qIdx}, v.title), word_similarity($${qIdx}, v."channelName")) AS score,
              v."viewCount",
              v."publishedAt"
            FROM "Video" v
            JOIN "Channel" c ON c.id = v."channelId"
            WHERE c."isActive" = true
              ${filters.clause}
              AND (
                $${qIdx} <% v.title
                OR $${qIdx} <% v."channelName"
              )
            ${innerOrderClause}
            LIMIT $${innerLimIdx}
          ),
          combined AS (
            SELECT id, score FROM fts
            UNION ALL
            SELECT id, score FROM trgm
          )
          SELECT c.id
          FROM combined c
          JOIN "Video" v ON v.id = c.id
          GROUP BY c.id, v."viewCount", v."publishedAt"
          ${outerOrderClause}
          LIMIT $${limIdx}
          OFFSET $${offIdx}
        `;

        const rows: { id: string }[] = await this.prisma.$transaction(async (tx: any) => {
          await tx.$executeRawUnsafe(
            "SET LOCAL pg_trgm.word_similarity_threshold = 0.45",
          );
          return tx.$queryRawUnsafe(sql, ...params);
        });
        return rows.map((r) => r.id);
      } catch (err: any) {
        this.logger.warn(
          `FTS/trigram query failed, falling back to ILIKE: ${err?.message || err}`,
        );
      }
    }

    // Safe Prisma fallback (also used in unit tests without live Postgres)
    const keywordWhere: any = { channel: { isActive: true } };
    this.applyVideoTypeFilter(keywordWhere, query.type);
    this.applyCategoryFilter(keywordWhere, query.category);
    this.applyChannelFilter(keywordWhere, query.channelId, query.channelIds);
    keywordWhere.OR = this.searchTermClauses(clean);

    const rows = await this.prisma.video.findMany({
      where: keywordWhere,
      select: { id: true },
      orderBy: this.resolveOrderBy(sort),
      take: limit,
      skip: offset,
    });
    return rows.map((r) => r.id);
  }

  private searchTermClauses(term: string) {
    return [
      { title: { contains: term, mode: "insensitive" } },
      { description: { contains: term, mode: "insensitive" } },
      { channelName: { contains: term, mode: "insensitive" } },
    ];
  }

  private applyVideoTypeFilter(where: any, type?: "VIDEO" | "SHORT" | "ALL") {
    if (type === "ALL") {
      // Intentionally do not constrain where.type to return all content
    } else if (type === "SHORT") {
      where.type = "SHORT";
    } else {
      // Default to VIDEO so shorts are never mixed into regular feeds or recommendations
      where.type = "VIDEO";
    }
  }

  private applyCategoryFilter(where: any, category?: string) {
    if (category && category !== "All") {
      where.category = category;
    }
  }

  private applyChannelFilter(
    where: any,
    channelId?: string,
    channelIds?: string | string[],
  ) {
    if (channelId) {
      where.channelId = channelId;
    } else if (channelIds) {
      const ids = Array.isArray(channelIds)
        ? channelIds
        : channelIds
            .split(",")
            .map((id) => id.trim())
            .filter(Boolean);
      if (ids.length > 0) {
        where.channelId = { in: ids };
      }
    }
  }

  /**
   * Builds the shared WHERE fragment (type / category / channel) used by the
   * vector query, with positional parameter placeholders.
   */
  private buildBaseFilterSql(query: VideoQuery): BaseFilterSql {
    const params: any[] = [];
    const parts: string[] = [];

    if (query.type !== "ALL") {
      params.push(query.type === "SHORT" ? "SHORT" : "VIDEO");
      parts.push(`v.type = $${params.length}::"VideoType"`);
    }

    if (query.category && query.category !== "All") {
      params.push(query.category);
      parts.push(`v.category = $${params.length}`);
    }

    if (query.channelId) {
      params.push(query.channelId);
      parts.push(`v."channelId" = $${params.length}`);
    } else if (query.channelIds) {
      const ids = Array.isArray(query.channelIds)
        ? query.channelIds
        : query.channelIds
            .split(",")
            .map((id) => id.trim())
            .filter(Boolean);
      if (ids.length > 0) {
        params.push(ids);
        parts.push(`v."channelId" = ANY($${params.length}::text[])`);
      }
    }

    return {
      clause: parts.length ? ` AND ${parts.join(" AND ")}` : "",
      params,
    };
  }

  /**
   * Returns enriched video rows in the given id order.
   */
  private async fetchEnrichedByIds(ids: string[], query?: VideoQuery) {
    if (!ids.length) return [];
    const where: any = {
      id: { in: ids },
      channel: { isActive: true },
    };
    if (query) {
      this.applyChannelFilter(where, query.channelId, query.channelIds);
      this.applyCategoryFilter(where, query.category);
    }
    const videos = await this.prisma.video.findMany({
      where,
      include: {
        channel: {
          select: {
            id: true,
            name: true,
            thumbnail: true,
            subscriberCount: true,
          },
        },
      },
    });
    const byId = new Map(videos.map((v) => [v.id, v]));
    return ids
      .map((id) => byId.get(id))
      .filter(Boolean)
      .map((v) => this.enrich(v));
  }

  /**
   * Reciprocal Rank Fusion over the two candidate lists.
   */
  private fuseRanks(lists: string[][], k = 60): string[] {
    const scores = new Map<string, number>();
    for (const list of lists) {
      list.forEach((id, i) => {
        scores.set(id, (scores.get(id) || 0) + 1 / (k + i + 1));
      });
    }
    return [...scores.entries()].sort((a, b) => b[1] - a[1]).map(([id]) => id);
  }

  /**
   * Fuses dense title/description vectors, keyword matches, and transcript
   * idea-chunk vectors. Returns videos (enriched with their best content
   * match, when one exists) after a 3-way Reciprocal Rank Fusion.
   */
  private async hybridSearchWithContent(
    query: VideoQuery,
    vector: number[],
    limit: number,
    offset: number,
  ) {
    const [vectorIds, keywordIds] = await Promise.all([
      this.vectorTitleSearch(query, vector),
      this.keywordSearch(query),
    ]);

    const contentIds: string[] = [];
    const contentMatches = new Map<
      string,
      {
        title?: string;
        statement: string;
        quote?: string;
        scriptureRefs?: string[] | null;
        startSec?: number | null;
        endSec?: number | null;
        score: number;
      }
    >();

    const contentSearchEnabled = this.configService.get<boolean>(
      'contentSearch.enabled',
      true,
    );
    if (contentSearchEnabled) {
      const maxChunks = this.configService.get<number>(
        'contentSearch.maxChunks',
        60,
      );
      const rows = await this.contentChunkSearch(
        query,
        vector,
        maxChunks,
      ).catch((e: any) => {
        this.logger.warn(`Content search failed, skipping: ${e.message}`);
        return [];
      });
      for (const r of rows) {
        if (!contentMatches.has(r.videoId)) {
          contentMatches.set(r.videoId, r);
          contentIds.push(r.videoId);
        }
      }
    }

    const fusedIds = this.fuseRanks([vectorIds, keywordIds, contentIds]);
    const pageIds = fusedIds
      .filter(
        (id) =>
          vectorIds.includes(id) ||
          keywordIds.includes(id) ||
          contentIds.includes(id),
      )
      .slice(offset, offset + limit);

    const videos = this.fetchEnrichedByIds(pageIds);
    return (await videos).map((v: any) => {
      const m = contentMatches.get(v.id);
      if (m) v.contentMatch = { ...m, quote: m.quote ?? m.statement };
      return v;
    });
  }

  private async vectorTitleSearch(
    query: VideoQuery,
    vector: number[],
  ): Promise<string[]> {
    const filters = this.buildBaseFilterSql(query);

    const modelIdx = filters.params.length + 1;
    const versionIdx = modelIdx + 1;
    const vecIdx = versionIdx + 1;
    const vectorLiteral = `[${vector.join(',')}]`;
    const rawParams = [
      ...filters.params,
      this.embeddingService.modelName,
      this.embeddingService.modelVersion,
      vectorLiteral,
    ];

    const vectorSql = `
      SELECT v.id
      FROM "Video" v
      JOIN "VideoEmbedding" ve ON ve."videoId" = v.id
      JOIN "Channel" c ON c.id = v."channelId"
      WHERE c."isActive" = true
        ${filters.clause}
        AND ve."model" = $${modelIdx}
        AND ve."version" = $${versionIdx}
      ORDER BY ve.embedding <=> $${vecIdx}::vector
      LIMIT 100
    `;

    try {
      const rows: { id: string }[] = await this.prisma.$queryRawUnsafe(
        vectorSql,
        ...rawParams,
      );
      return rows.map((r) => r.id);
    } catch (e: any) {
      this.logger.warn(
        `Vector search failed, using keyword only: ${e.message}`,
      );
      return [];
    }
  }

  private async keywordSearch(query: VideoQuery): Promise<string[]> {
    const keywordWhere: any = {
      channel: { isActive: true },
    };
    this.applyVideoTypeFilter(keywordWhere, query.type);
    this.applyCategoryFilter(keywordWhere, query.category);
    this.applyChannelFilter(keywordWhere, query.channelId, query.channelIds);
    keywordWhere.OR = this.searchTermClauses(query.search);

    const rows = await this.prisma.video.findMany({
      where: keywordWhere,
      select: { id: true },
      orderBy: { publishedAt: "desc" },
      take: 100,
    });
    return rows.map((r) => r.id);
  }

  /**
   * Discourse idea-chunk vector search. Returns the closest chunk per video
   * (best match only) so one video occupies one rank slot.
   */
  private async contentChunkSearch(
    query: VideoQuery,
    vector: number[],
    maxChunks: number,
  ) {
    const filters = this.buildBaseFilterSql(query);

    const modelIdx = filters.params.length + 1;
    const versionIdx = modelIdx + 1;
    const vecIdx = versionIdx + 1;
    const vectorLiteral = `[${vector.join(",")}]`;
    const rawParams = [
      ...filters.params,
      this.embeddingService.modelName,
      this.embeddingService.modelVersion,
      vectorLiteral,
    ];

    const sql = `
      WITH ranked AS (
        SELECT
          vc."videoId",
          vc.title,
          vc.content,
          vc."quoteText",
          vc."scriptureRefs",
          vc."startSec",
          vc."endSec",
          vc.embedding <=> $${vecIdx}::vector AS dist,
          ROW_NUMBER() OVER (
            PARTITION BY vc."videoId" ORDER BY vc.embedding <=> $${vecIdx}::vector
          ) AS rn
        FROM "VideoChunk" vc
        JOIN "Video" v ON v.id = vc."videoId"
        JOIN "Channel" c ON c.id = v."channelId"
        WHERE c."isActive" = true
          ${filters.clause}
          AND vc."model" = $${modelIdx}
          AND vc."version" = $${versionIdx}
      )
      SELECT "videoId", title, content, "quoteText", "scriptureRefs", "startSec", "endSec", dist
      FROM ranked
      WHERE rn = 1
      ORDER BY dist
      LIMIT $${vecIdx + 1}
    `;

    const rows: {
      videoId: string;
      title: string | null;
      content: string;
      quoteText: string | null;
      scriptureRefs: string[] | null;
      startSec: number | null;
      endSec: number | null;
      dist: number;
    }[] = await this.prisma.$queryRawUnsafe(sql, ...rawParams, maxChunks);

    return rows.map((r) => ({
      videoId: r.videoId,
      title: r.title ?? undefined,
      statement: r.content,
      quote: r.quoteText ?? undefined,
      scriptureRefs: r.scriptureRefs ?? undefined,
      startSec: r.startSec,
      endSec: r.endSec,
      score: -r.dist, // higher = closer (cosine distance is [0,2])
    }));
  }

  /**
   * Legacy hybrid search (title/description dense + keyword only). Kept for
   * backward compatibility with tests; production goes through
   * hybridSearchWithContent.
   */
  private async hybridSearch(
    query: VideoQuery,
    vector: number[],
    limit: number,
    offset: number,
  ) {
    const [vectorIds, keywordIds] = await Promise.all([
      this.vectorTitleSearch(query, vector),
      this.keywordSearch(query),
    ]);

    const fusedIds = this.fuseRanks([vectorIds, keywordIds]);
    const pageIds = fusedIds
      .filter((id) => vectorIds.includes(id) || keywordIds.includes(id))
      .slice(offset, offset + limit);

    return this.fetchEnrichedByIds(pageIds);
  }

  private resolveOrderBy(sort?: VideoQuery["sort"]) {
    if (sort === "popular") return { viewCount: "desc" as const };
    if (sort === "oldest") {
      return [{ publishedAt: "asc" as const }, { id: "asc" as const }];
    }
    return [{ publishedAt: "desc" as const }, { id: "desc" as const }];
  }

  private async fetchKeywords(
    where: any,
    limit: number,
    offset: number,
    sort?: VideoQuery["sort"],
  ) {
    const videos = await this.prisma.video.findMany({
      where,
      include: {
        channel: {
          select: {
            id: true,
            name: true,
            thumbnail: true,
            subscriberCount: true,
          },
        },
      },
      orderBy: this.resolveOrderBy(sort),
      take: limit,
      skip: offset,
    });

    return videos.map((v) => this.enrich(v));
  }

  private enrich(v: any) {
    return {
      ...v,
      channelName: v.channelName || v.channel?.name || "Channel",
      channelAvatarUrl: v.channelThumbnail || v.channel?.thumbnail || null,
      channelTitle: v.channelName || v.channel?.name || "Channel",
    };
  }

  async getChannelPosition(id: string) {
    const video = await this.prisma.video.findUnique({
      where: { id },
      select: { id: true, channelId: true, publishedAt: true },
    });
    if (!video) throw new NotFoundException('Video not found');
    const base = { channelId: video.channelId, type: 'VIDEO' as const, channel: { isActive: true } };
    const [newer, older] = await Promise.all([
      this.prisma.video.count({ where: { ...base, OR: [
        { publishedAt: { gt: video.publishedAt } },
        { publishedAt: video.publishedAt, id: { gt: video.id } },
      ] } }),
      this.prisma.video.count({ where: { ...base, OR: [
        { publishedAt: { lt: video.publishedAt } },
        { publishedAt: video.publishedAt, id: { lt: video.id } },
      ] } }),
    ]);
    return { newer, older };
  }

  async findOne(id: string) {
    if (this.cache) {
      return this.cache.getOrSet("videos", `detail:${id}`, 86400, () =>
        this.findOneUncached(id),
      );
    }
    return this.findOneUncached(id);
  }

  private async findOneUncached(id: string) {
    const video = await this.prisma.video.findUnique({
      where: { id },
      select: {
        id: true,
        type: true,
        title: true,
        description: true,
        thumbnail: true,
        channelId: true,
        channelName: true,
        channelThumbnail: true,
        channelSubscriberCount: true,
        publishedAt: true,
        duration: true,
        viewCount: true,
        tags: true,
        category: true,
        metadata: true,
        creatorUserId: true,
        creatorName: true,
        creatorEmail: true,
        sourceVideoId: true,
        clipStartTime: true,
        clipEndTime: true,
        cropOffsetX: true,
        audioUrl: true,
        createdAt: true,
        updatedAt: true,
        channel: true,
      },
    });

    if (!video) {
      throw new NotFoundException({
        message: "Video not found",
        error: "Not Found",
        statusCode: 404,
      });
    }

    return this.enrich(video);
  }

  async importShortVideo(body: {
    youtubeVideoId: string;
    sourceVideoId?: string;
    creatorName?: string;
    creatorEmail?: string;
    clipStartTime?: number;
    clipEndTime?: number;
    cropOffsetX?: number;
    title?: string;
    description?: string;
    category?: string;
  }) {
    const videoId = body.youtubeVideoId?.trim();
    if (!videoId) {
      throw new BadRequestException("youtubeVideoId is required");
    }

    if (!this.youtubeService) {
      throw new ServiceUnavailableException(
        "YouTube verification service is unavailable",
      );
    }

    const visibilityMap = await this.youtubeService.verifyVideosVisibility(
      [videoId],
      { allowShortsOAuth: true },
    );
    const visibility = visibilityMap.get(videoId);

    if (visibility?.status === "private") {
      await this.prisma.video
        .deleteMany({ where: { id: videoId } })
        .catch(() => {});
      await (this.prisma as any).shortCreation
        ?.deleteMany?.({ where: { youtubeVideoId: videoId } })
        .catch(() => {});
      await this.cache?.invalidate("videos", "channels");
      this.logger.warn(`Rejected private video import for ${videoId}`);
      throw new BadRequestException("Private videos cannot be imported");
    }

    if (visibility?.status === "error") {
      this.logger.warn(
        `Visibility check error for import ${videoId}: ${visibility.errorMessage || "unknown"}`,
      );
      throw new ServiceUnavailableException(
        "Unable to verify video visibility with YouTube",
      );
    }

    if (!visibility || visibility.status !== "eligible" || !visibility.item) {
      this.logger.warn(
        `Rejected unverified video import for ${videoId} (status: ${visibility?.status || "unknown"})`,
      );
      throw new BadRequestException(
        "Video visibility could not be verified on YouTube",
      );
    }

    const item = visibility.item;
    let title = body.title || "Inspirational Short";
    let description = body.description || "";
    let thumbnail = `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;
    let channelId =
      this.configService.get<string>("shorts.customChannelId") ||
      "UCSaJppP4zb2vivjxYfTqOKw";
    let channelName = "ChristianApp";
    let channelThumbnail: string | null = null;
    let publishedAt = new Date();
    let duration = "PT60S";

    let parsedMeta: any = {
      creatorName: body.creatorName,
      creatorEmail: body.creatorEmail,
      sourceVideoId: body.sourceVideoId,
      clipStartTime: body.clipStartTime,
      clipEndTime: body.clipEndTime,
      cropOffsetX: body.cropOffsetX ?? 0.0,
    };

    // If sourceVideoId is provided, inherit the original preacher's channel details
    if (body.sourceVideoId) {
      const sourceVideo = await this.prisma.video.findUnique({
        where: { id: body.sourceVideoId },
        include: { channel: true },
      });
      if (sourceVideo) {
        channelId = sourceVideo.channelId || channelId;
        channelName = sourceVideo.channelName || channelName;
        channelThumbnail = sourceVideo.channelThumbnail || null;
      }
    }

    const snippet = item.snippet;
    if (snippet) {
      title = snippet.title || title;
      description = snippet.description || description;
      thumbnail =
        snippet.thumbnails?.maxres?.url ||
        snippet.thumbnails?.high?.url ||
        snippet.thumbnails?.medium?.url ||
        thumbnail;
      publishedAt = snippet.publishedAt
        ? new Date(snippet.publishedAt)
        : publishedAt;
      duration = item.contentDetails?.duration || duration;

      // Parse embedded <!-- CT_META: {...} --> from description if present
      const jsonMatch = description.match(
        /<!--\s*CT_META:\s*(\{.*?\})\s*-->/s,
      );
      if (jsonMatch) {
        try {
          const meta = JSON.parse(jsonMatch[1]);
          parsedMeta.creatorName =
            meta.creatorName || parsedMeta.creatorName;
          parsedMeta.creatorEmail =
            meta.creatorEmail || parsedMeta.creatorEmail;
          parsedMeta.sourceVideoId =
            meta.sourceVideoId || parsedMeta.sourceVideoId;
          parsedMeta.clipStartTime =
            meta.startTime ?? parsedMeta.clipStartTime;
          parsedMeta.clipEndTime = meta.endTime ?? parsedMeta.clipEndTime;
        } catch (_) {}
      }
    }

    // Ensure Channel exists
    await this.prisma.channel.upsert({
      where: { id: channelId },
      update: {},
      create: {
        id: channelId,
        name: channelName,
        thumbnail: channelThumbnail,
        isActive: true,
        category: body.category || "General",
      },
    });

    // Upsert Video into database as a SHORT
    const savedVideo = await this.prisma.video.upsert({
      where: { id: videoId },
      update: {
        type: "SHORT",
        title,
        description,
        thumbnail,
        creatorName: parsedMeta.creatorName || null,
        creatorEmail: parsedMeta.creatorEmail || null,
        sourceVideoId: parsedMeta.sourceVideoId || null,
        clipStartTime:
          parsedMeta.clipStartTime != null
            ? Number(parsedMeta.clipStartTime)
            : null,
        clipEndTime:
          parsedMeta.clipEndTime != null
            ? Number(parsedMeta.clipEndTime)
            : null,
        cropOffsetX:
          parsedMeta.cropOffsetX != null ? Number(parsedMeta.cropOffsetX) : 0.0,
        clippedAt: new Date(),
        category: body.category || "General",
      },
      create: {
        id: videoId,
        type: "SHORT",
        title,
        description,
        thumbnail,
        channelId,
        channelName,
        channelThumbnail,
        publishedAt,
        duration,
        viewCount: 0,
        tags: ["#Shorts"],
        creatorName: parsedMeta.creatorName || null,
        creatorEmail: parsedMeta.creatorEmail || null,
        sourceVideoId: parsedMeta.sourceVideoId || null,
        clipStartTime:
          parsedMeta.clipStartTime != null
            ? Number(parsedMeta.clipStartTime)
            : null,
        clipEndTime:
          parsedMeta.clipEndTime != null
            ? Number(parsedMeta.clipEndTime)
            : null,
        cropOffsetX:
          parsedMeta.cropOffsetX != null ? Number(parsedMeta.cropOffsetX) : 0.0,
        clippedAt: new Date(),
        category: body.category || "General",
      },
    });

    // Re-queue embedding for existing videos (new rows default to pending)
    await this.prisma.$executeRawUnsafe(
      `INSERT INTO "VideoPipelineStatus" ("videoId", "embedding", "updatedAt")
       VALUES ($1, jsonb_build_object('status', 'pending', 'error', NULL, 'hash', NULL), CURRENT_TIMESTAMP)
       ON CONFLICT ("videoId") DO UPDATE SET
         "embedding" = COALESCE("VideoPipelineStatus"."embedding", '{}'::jsonb)
                        || jsonb_build_object('status', 'pending', 'error', NULL, 'hash', NULL),
         "updatedAt" = CURRENT_TIMESTAMP`,
      savedVideo.id,
    );

    // Fire-and-forget Upstash Vector upsert using the full saved Prisma row
    this.videoVector?.upsertVideos([savedVideo]).catch((e: any) => {
      this.logger.warn(`Upstash vector upsert failed for short ${savedVideo.id}: ${e?.message || e}`);
    });

    await this.cache?.invalidate("videos", "channels", "video-search");

    this.logger.log(
      `Short imported and published: ${savedVideo.id} - "${savedVideo.title}"`,
    );
    return savedVideo;
  }
}
