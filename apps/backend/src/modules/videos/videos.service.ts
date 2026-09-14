import { Injectable, NotFoundException, Logger } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { PrismaService } from "../prisma/prisma.service";
import { EmbeddingService } from "../embedding/embedding.service";

interface VideoQuery {
  category?: string;
  type?: "VIDEO" | "SHORT" | "ALL";
  channelId?: string;
  channelIds?: string | string[];
  search?: string;
  limit?: number;
  offset?: number;
}

interface BaseFilterSql {
  clause: string;
  params: any[];
}

@Injectable()
export class VideosService {
  private readonly logger = new Logger(VideosService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly configService: ConfigService,
    private readonly embeddingService: EmbeddingService,
  ) {}

  async findAll(query: VideoQuery) {
    const where: any = {
      channel: {
        isActive: true,
      },
    };

    this.applyVideoTypeFilter(where, query.type);
    this.applyCategoryFilter(where, query.category);
    this.applyChannelFilter(where, query.channelId, query.channelIds);

    const limit = query.limit ? Number(query.limit) : 50;
    const offset = query.offset ? Number(query.offset) : 0;

    if (!query.search) {
      return this.fetchKeywords(where, limit, offset);
    }

    const vector = await this.embeddingService.embedQuery(query.search);
    if (vector) {
      return this.hybridSearchWithContent(query, vector, limit, offset);
    }

    where.OR = this.searchTermClauses(query.search);
    return this.fetchKeywords(where, limit, offset);
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
  private async fetchEnrichedByIds(ids: string[]) {
    if (!ids.length) return [];
    const videos = await this.prisma.video.findMany({
      where: { id: { in: ids } },
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
    const vectorLiteral = `[${vector.join(",")}]`;
    const rawParams = [
      ...filters.params,
      this.embeddingService.modelName,
      this.embeddingService.modelVersion,
      vectorLiteral,
    ];

    const vectorSql = `
      SELECT ve."videoId" AS id
      FROM "VideoEmbedding" ve
      JOIN "Video" v ON v.id = ve."videoId"
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
      SELECT "videoId", title, content, "quoteText", "startSec", "endSec", dist
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
      startSec: number | null;
      endSec: number | null;
      dist: number;
    }[] = await this.prisma.$queryRawUnsafe(sql, ...rawParams, maxChunks);

    return rows.map((r) => ({
      videoId: r.videoId,
      title: r.title ?? undefined,
      statement: r.content,
      quote: r.quoteText ?? undefined,
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

  private async fetchKeywords(where: any, limit: number, offset: number) {
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
      orderBy: { publishedAt: "desc" },
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

  async findOne(id: string) {
    const video = await this.prisma.video.findUnique({
      where: { id },
      include: {
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
    const videoId = body.youtubeVideoId.trim();
    const apiKey = this.configService.get<string>("youtubeApiKey");
    let title = body.title || "Inspirational Short";
    let description = body.description || "";
    let thumbnail = `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;
    let channelId =
      this.configService.get<string>("shorts.customChannelId") ||
      "UCSaJppP4zb2vivjxYfTqOKw";
    let channelName = "Christian-Tube";
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

    // Try to fetch YouTube metadata if API key is present
    if (apiKey) {
      try {
        const detailsUrl = `https://www.googleapis.com/youtube/v3/videos?key=${apiKey}&id=${encodeURIComponent(videoId)}&part=snippet,contentDetails,statistics`;
        const res = await fetch(detailsUrl);
        const data = await res.json();
        const item = data.items?.[0];

        if (item) {
          const snippet = item.snippet;
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
      } catch (e: any) {
        this.logger.warn(
          `Could not fetch details from YouTube for ${videoId}: ${e.message}`,
        );
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
        embeddingStatus: "pending",
        embeddingHash: null,
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

    this.logger.log(
      `Short imported and published: ${savedVideo.id} - "${savedVideo.title}"`,
    );
    return savedVideo;
  }
}
