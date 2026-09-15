"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var VideosService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.VideosService = void 0;
const common_1 = require("@nestjs/common");
const config_1 = require("@nestjs/config");
const prisma_service_1 = require("../prisma/prisma.service");
const embedding_service_1 = require("../embedding/embedding.service");
let VideosService = VideosService_1 = class VideosService {
    constructor(prisma, configService, embeddingService) {
        this.prisma = prisma;
        this.configService = configService;
        this.embeddingService = embeddingService;
        this.logger = new common_1.Logger(VideosService_1.name);
    }
    async findAll(query) {
        const where = {
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
    searchTermClauses(term) {
        return [
            { title: { contains: term, mode: "insensitive" } },
            { description: { contains: term, mode: "insensitive" } },
            { channelName: { contains: term, mode: "insensitive" } },
        ];
    }
    applyVideoTypeFilter(where, type) {
        if (type === "ALL") {
        }
        else if (type === "SHORT") {
            where.type = "SHORT";
        }
        else {
            where.type = "VIDEO";
        }
    }
    applyCategoryFilter(where, category) {
        if (category && category !== "All") {
            where.category = category;
        }
    }
    applyChannelFilter(where, channelId, channelIds) {
        if (channelId) {
            where.channelId = channelId;
        }
        else if (channelIds) {
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
    buildBaseFilterSql(query) {
        const params = [];
        const parts = [];
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
        }
        else if (query.channelIds) {
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
    async fetchEnrichedByIds(ids) {
        if (!ids.length)
            return [];
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
    fuseRanks(lists, k = 60) {
        const scores = new Map();
        for (const list of lists) {
            list.forEach((id, i) => {
                scores.set(id, (scores.get(id) || 0) + 1 / (k + i + 1));
            });
        }
        return [...scores.entries()].sort((a, b) => b[1] - a[1]).map(([id]) => id);
    }
    async hybridSearchWithContent(query, vector, limit, offset) {
        const [vectorIds, keywordIds] = await Promise.all([
            this.vectorTitleSearch(query, vector),
            this.keywordSearch(query),
        ]);
        const contentIds = [];
        const contentMatches = new Map();
        const contentSearchEnabled = this.configService.get('contentSearch.enabled', true);
        if (contentSearchEnabled) {
            const maxChunks = this.configService.get('contentSearch.maxChunks', 60);
            const rows = await this.contentChunkSearch(query, vector, maxChunks).catch((e) => {
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
            .filter((id) => vectorIds.includes(id) ||
            keywordIds.includes(id) ||
            contentIds.includes(id))
            .slice(offset, offset + limit);
        const videos = this.fetchEnrichedByIds(pageIds);
        return (await videos).map((v) => {
            const m = contentMatches.get(v.id);
            if (m)
                v.contentMatch = { ...m, quote: m.quote ?? m.statement };
            return v;
        });
    }
    async vectorTitleSearch(query, vector) {
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
            const rows = await this.prisma.$queryRawUnsafe(vectorSql, ...rawParams);
            return rows.map((r) => r.id);
        }
        catch (e) {
            this.logger.warn(`Vector search failed, using keyword only: ${e.message}`);
            return [];
        }
    }
    async keywordSearch(query) {
        const keywordWhere = {
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
    async contentChunkSearch(query, vector, maxChunks) {
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
        const rows = await this.prisma.$queryRawUnsafe(sql, ...rawParams, maxChunks);
        return rows.map((r) => ({
            videoId: r.videoId,
            title: r.title ?? undefined,
            statement: r.content,
            quote: r.quoteText ?? undefined,
            scriptureRefs: r.scriptureRefs ?? undefined,
            startSec: r.startSec,
            endSec: r.endSec,
            score: -r.dist,
        }));
    }
    async hybridSearch(query, vector, limit, offset) {
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
    async fetchKeywords(where, limit, offset) {
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
    enrich(v) {
        return {
            ...v,
            channelName: v.channelName || v.channel?.name || "Channel",
            channelAvatarUrl: v.channelThumbnail || v.channel?.thumbnail || null,
            channelTitle: v.channelName || v.channel?.name || "Channel",
        };
    }
    async findOne(id) {
        const video = await this.prisma.video.findUnique({
            where: { id },
            include: {
                channel: true,
            },
        });
        if (!video) {
            throw new common_1.NotFoundException({
                message: "Video not found",
                error: "Not Found",
                statusCode: 404,
            });
        }
        return this.enrich(video);
    }
    async importShortVideo(body) {
        const videoId = body.youtubeVideoId.trim();
        const apiKey = this.configService.get("youtubeApiKey");
        let title = body.title || "Inspirational Short";
        let description = body.description || "";
        let thumbnail = `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;
        let channelId = this.configService.get("shorts.customChannelId") ||
            "UCSaJppP4zb2vivjxYfTqOKw";
        let channelName = "Christian-Tube";
        let channelThumbnail = null;
        let publishedAt = new Date();
        let duration = "PT60S";
        let parsedMeta = {
            creatorName: body.creatorName,
            creatorEmail: body.creatorEmail,
            sourceVideoId: body.sourceVideoId,
            clipStartTime: body.clipStartTime,
            clipEndTime: body.clipEndTime,
            cropOffsetX: body.cropOffsetX ?? 0.0,
        };
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
                    const jsonMatch = description.match(/<!--\s*CT_META:\s*(\{.*?\})\s*-->/s);
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
                        }
                        catch (_) { }
                    }
                }
            }
            catch (e) {
                this.logger.warn(`Could not fetch details from YouTube for ${videoId}: ${e.message}`);
            }
        }
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
                clipStartTime: parsedMeta.clipStartTime != null
                    ? Number(parsedMeta.clipStartTime)
                    : null,
                clipEndTime: parsedMeta.clipEndTime != null
                    ? Number(parsedMeta.clipEndTime)
                    : null,
                cropOffsetX: parsedMeta.cropOffsetX != null ? Number(parsedMeta.cropOffsetX) : 0.0,
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
                clipStartTime: parsedMeta.clipStartTime != null
                    ? Number(parsedMeta.clipStartTime)
                    : null,
                clipEndTime: parsedMeta.clipEndTime != null
                    ? Number(parsedMeta.clipEndTime)
                    : null,
                cropOffsetX: parsedMeta.cropOffsetX != null ? Number(parsedMeta.cropOffsetX) : 0.0,
                clippedAt: new Date(),
                category: body.category || "General",
            },
        });
        this.logger.log(`Short imported and published: ${savedVideo.id} - "${savedVideo.title}"`);
        return savedVideo;
    }
};
exports.VideosService = VideosService;
exports.VideosService = VideosService = VideosService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        config_1.ConfigService,
        embedding_service_1.EmbeddingService])
], VideosService);
//# sourceMappingURL=videos.service.js.map