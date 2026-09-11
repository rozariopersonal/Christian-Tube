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
let VideosService = VideosService_1 = class VideosService {
    constructor(prisma, configService) {
        this.prisma = prisma;
        this.configService = configService;
        this.logger = new common_1.Logger(VideosService_1.name);
    }
    async findAll(query) {
        const where = {
            channel: {
                isActive: true,
            },
        };
        if (query.type === 'ALL') {
        }
        else if (query.type === 'SHORT') {
            where.type = 'SHORT';
        }
        else {
            where.type = 'VIDEO';
        }
        if (query.category && query.category !== 'All') {
            where.category = query.category;
        }
        if (query.channelId) {
            where.channelId = query.channelId;
        }
        else if (query.channelIds) {
            const ids = Array.isArray(query.channelIds)
                ? query.channelIds
                : query.channelIds.split(',').map((id) => id.trim()).filter(Boolean);
            if (ids.length > 0) {
                where.channelId = { in: ids };
            }
        }
        if (query.search) {
            where.OR = [
                { title: { contains: query.search, mode: 'insensitive' } },
                { description: { contains: query.search, mode: 'insensitive' } },
                { channelName: { contains: query.search, mode: 'insensitive' } },
            ];
        }
        const limit = query.limit ? Number(query.limit) : 50;
        const offset = query.offset ? Number(query.offset) : 0;
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
            orderBy: { publishedAt: 'desc' },
            take: limit,
            skip: offset,
        });
        return videos.map((v) => ({
            ...v,
            channelName: v.channelName || v.channel?.name || 'Channel',
            channelAvatarUrl: v.channelThumbnail || v.channel?.thumbnail || null,
            channelTitle: v.channelName || v.channel?.name || 'Channel',
        }));
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
                message: 'Video not found',
                error: 'Not Found',
                statusCode: 404,
            });
        }
        return {
            ...video,
            channelName: video.channelName || video.channel?.name || 'Channel',
            channelAvatarUrl: video.channelThumbnail || video.channel?.thumbnail || null,
            channelTitle: video.channelName || video.channel?.name || 'Channel',
        };
    }
    async importShortVideo(body) {
        const videoId = body.youtubeVideoId.trim();
        const apiKey = this.configService.get('youtubeApiKey');
        let title = body.title || 'Inspirational Short';
        let description = body.description || '';
        let thumbnail = `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;
        let channelId = this.configService.get('shorts.customChannelId') || 'UCSaJppP4zb2vivjxYfTqOKw';
        let channelName = 'Christian-Tube';
        let channelThumbnail = null;
        let publishedAt = new Date();
        let duration = 'PT60S';
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
                    publishedAt = snippet.publishedAt ? new Date(snippet.publishedAt) : publishedAt;
                    duration = item.contentDetails?.duration || duration;
                    const jsonMatch = description.match(/<!--\s*CT_META:\s*(\{.*?\})\s*-->/s);
                    if (jsonMatch) {
                        try {
                            const meta = JSON.parse(jsonMatch[1]);
                            parsedMeta.creatorName = meta.creatorName || parsedMeta.creatorName;
                            parsedMeta.creatorEmail = meta.creatorEmail || parsedMeta.creatorEmail;
                            parsedMeta.sourceVideoId = meta.sourceVideoId || parsedMeta.sourceVideoId;
                            parsedMeta.clipStartTime = meta.startTime ?? parsedMeta.clipStartTime;
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
                category: body.category || 'General',
            },
        });
        const savedVideo = await this.prisma.video.upsert({
            where: { id: videoId },
            update: {
                type: 'SHORT',
                title,
                description,
                thumbnail,
                creatorName: parsedMeta.creatorName || null,
                creatorEmail: parsedMeta.creatorEmail || null,
                sourceVideoId: parsedMeta.sourceVideoId || null,
                clipStartTime: parsedMeta.clipStartTime != null ? Number(parsedMeta.clipStartTime) : null,
                clipEndTime: parsedMeta.clipEndTime != null ? Number(parsedMeta.clipEndTime) : null,
                cropOffsetX: parsedMeta.cropOffsetX != null ? Number(parsedMeta.cropOffsetX) : 0.0,
                clippedAt: new Date(),
                category: body.category || 'General',
            },
            create: {
                id: videoId,
                type: 'SHORT',
                title,
                description,
                thumbnail,
                channelId,
                channelName,
                channelThumbnail,
                publishedAt,
                duration,
                viewCount: 0,
                tags: ['#Shorts'],
                creatorName: parsedMeta.creatorName || null,
                creatorEmail: parsedMeta.creatorEmail || null,
                sourceVideoId: parsedMeta.sourceVideoId || null,
                clipStartTime: parsedMeta.clipStartTime != null ? Number(parsedMeta.clipStartTime) : null,
                clipEndTime: parsedMeta.clipEndTime != null ? Number(parsedMeta.clipEndTime) : null,
                cropOffsetX: parsedMeta.cropOffsetX != null ? Number(parsedMeta.cropOffsetX) : 0.0,
                clippedAt: new Date(),
                category: body.category || 'General',
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
        config_1.ConfigService])
], VideosService);
//# sourceMappingURL=videos.service.js.map