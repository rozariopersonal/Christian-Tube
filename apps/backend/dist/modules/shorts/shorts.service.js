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
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
var ShortsService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.ShortsService = void 0;
const common_1 = require("@nestjs/common");
const config_1 = require("@nestjs/config");
const axios_1 = __importDefault(require("axios"));
const prisma_service_1 = require("../prisma/prisma.service");
let ShortsService = ShortsService_1 = class ShortsService {
    constructor(configService, prisma) {
        this.configService = configService;
        this.prisma = prisma;
        this.logger = new common_1.Logger(ShortsService_1.name);
    }
    getTodayUtcDateString() {
        const now = new Date();
        return now.toISOString().split('T')[0];
    }
    async getQuotaStatus() {
        const today = this.getTodayUtcDateString();
        const shortsConfig = this.configService.get('shorts') || {};
        const unitsLimit = shortsConfig.dailyQuotaUnits || 10000;
        const uploadCostUnits = shortsConfig.uploadCostUnits || 1600;
        let quotaLog = await this.prisma.dailyQuotaLog.findUnique({
            where: { date: today },
        });
        if (!quotaLog) {
            quotaLog = await this.prisma.dailyQuotaLog.create({
                data: {
                    date: today,
                    unitsConsumed: 0,
                    unitsLimit,
                },
            });
        }
        const unitsRemaining = Math.max(0, unitsLimit - quotaLog.unitsConsumed);
        const uploadAllowed = unitsRemaining >= uploadCostUnits;
        const response = {
            date: today,
            unitsConsumed: quotaLog.unitsConsumed,
            unitsLimit,
            unitsRemaining,
            uploadAllowed,
            uploadCostUnits,
        };
        if (!uploadAllowed) {
            const retryDate = new Date(Date.now() + 5 * 60 * 60 * 1000);
            response.nextRetryAfterHours = 5;
            response.retryAt = retryDate.toISOString();
        }
        return response;
    }
    async initiateUploadSession(dto) {
        const quota = await this.getQuotaStatus();
        if (!quota.uploadAllowed) {
            this.logger.warn(`Upload rejected: Daily quota exhausted for ${quota.date} (${quota.unitsConsumed}/${quota.unitsLimit} units used).`);
            return {
                allowed: false,
                reason: 'QUOTA_EXCEEDED',
                message: 'Daily YouTube upload quota reached. Upload scheduled for later.',
                nextRetryAfterHours: quota.nextRetryAfterHours || 5,
                retryAt: quota.retryAt,
            };
        }
        const clientId = this.configService.get('youtubeClientId');
        const clientSecret = this.configService.get('youtubeClientSecret');
        const refreshToken = this.configService.get('youtubeRefreshToken');
        const shortsConfig = this.configService.get('shorts') || {};
        const cleanTitle = (dto.title || 'Inspirational Christian Clip').trim();
        const maxTitleLength = 100 - ' #Shorts'.length;
        const safeTitle = cleanTitle.length > maxTitleLength
            ? `${cleanTitle.substring(0, maxTitleLength - 3)}... #Shorts`
            : `${cleanTitle} #Shorts`;
        const metadataPayload = {
            creatorUserId: dto.creatorUserId || null,
            creatorName: dto.creatorName || 'Anonymous',
            creatorEmail: dto.creatorEmail || '',
            sourceVideoId: dto.sourceVideoId || null,
            startTime: dto.clipStartTime || 0,
            endTime: dto.clipEndTime || 0,
            cropOffsetX: dto.cropOffsetX ?? 0.0,
            clippedAt: new Date().toISOString(),
        };
        const description = [
            dto.description || cleanTitle,
            '',
            '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
            '✂️ Clipped via Christian-Tube',
            dto.creatorName ? `👤 Clipped by: ${dto.creatorName}` : '',
            dto.creatorEmail ? `📧 Contact: ${dto.creatorEmail}` : '',
            dto.sourceVideoId ? `📖 Original Video: https://youtube.com/watch?v=${dto.sourceVideoId}` : '',
            '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
            '#Shorts #ChristianTube #Faith #Sermon',
            '',
            `<!-- CT_META: ${JSON.stringify(metadataPayload)} -->`,
        ].filter(Boolean).join('\n');
        if (!clientId || !clientSecret || !refreshToken) {
            this.logger.error('YouTube OAuth credentials or YOUTUBE_REFRESH_TOKEN not configured on backend.');
            throw new common_1.BadRequestException('YouTube channel upload is not authorized. YOUTUBE_REFRESH_TOKEN is missing on backend.');
        }
        try {
            const tokenRes = await axios_1.default.post('https://oauth2.googleapis.com/token', new URLSearchParams({
                client_id: clientId,
                client_secret: clientSecret,
                refresh_token: refreshToken,
                grant_type: 'refresh_token',
            }).toString(), {
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                timeout: 10000,
            });
            const accessToken = tokenRes.data?.access_token;
            if (!accessToken) {
                throw new Error('Failed to obtain YouTube access token from OAuth refresh response');
            }
            const ytRes = await axios_1.default.post('https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status', {
                snippet: {
                    title: safeTitle,
                    description,
                    categoryId: '29',
                    tags: ['#Shorts', 'Christian', 'Sermon', 'Faith'],
                },
                status: {
                    privacyStatus: shortsConfig.defaultPrivacyStatus || 'public',
                    selfDeclaredMadeForKids: shortsConfig.selfDeclaredMadeForKids ?? false,
                },
            }, {
                headers: {
                    Authorization: `Bearer ${accessToken}`,
                    'Content-Type': 'application/json; charset=UTF-8',
                    'X-Upload-Content-Type': 'video/mp4',
                },
                timeout: 15000,
            });
            const uploadUrl = ytRes.headers['location'];
            if (!uploadUrl) {
                throw new Error('YouTube did not return upload session URL in Location header');
            }
            this.logger.log(`✅ YouTube Resumable Upload session initialized for: "${safeTitle}"`);
            return {
                allowed: true,
                uploadUrl,
                title: safeTitle,
                customChannelId: shortsConfig.customChannelId,
                metadata: metadataPayload,
            };
        }
        catch (err) {
            this.logger.error(`YouTube upload initiation failed: ${err.message}`);
            throw new common_1.BadRequestException(`Could not initiate YouTube upload: ${err.message}`);
        }
    }
    async recordCreation(data) {
        try {
            try {
                const quota = await this.getQuotaStatus();
                await this.prisma.dailyQuotaLog.update({
                    where: { date: quota.date },
                    data: { unitsConsumed: { increment: quota.uploadCostUnits } },
                });
            }
            catch (quotaErr) {
                this.logger.warn(`Could not increment quota on recordCreation: ${quotaErr.message}`);
            }
            const creation = await this.prisma.shortCreation.upsert({
                where: { youtubeVideoId: data.youtubeVideoId },
                update: {
                    userId: data.userId || undefined,
                    userEmail: data.userEmail || undefined,
                    creatorName: data.creatorName || undefined,
                    youtubeVideoId: data.youtubeVideoId,
                    sourceVideoId: data.sourceVideoId || undefined,
                    title: data.title,
                    description: data.description,
                    thumbnail: data.thumbnail,
                    durationSeconds: data.durationSeconds || 60,
                    clipStartTime: data.clipStartTime,
                    clipEndTime: data.clipEndTime,
                    cropOffsetX: data.cropOffsetX ?? 0.0,
                },
                create: {
                    userId: data.userId || null,
                    userEmail: data.userEmail || null,
                    creatorName: data.creatorName || null,
                    youtubeVideoId: data.youtubeVideoId,
                    sourceVideoId: data.sourceVideoId || null,
                    title: data.title,
                    description: data.description,
                    thumbnail: data.thumbnail,
                    durationSeconds: data.durationSeconds || 60,
                    clipStartTime: data.clipStartTime,
                    clipEndTime: data.clipEndTime,
                    cropOffsetX: data.cropOffsetX ?? 0.0,
                },
            });
            try {
                let channelId = this.configService.get('shorts.customChannelId') || 'UCSaJppP4zb2vivjxYfTqOKw';
                let channelName = 'Community Shorts';
                let channelThumbnail = null;
                let category = 'General';
                if (data.sourceVideoId) {
                    const sourceVideo = await this.prisma.video.findUnique({
                        where: { id: data.sourceVideoId },
                        include: { channel: true },
                    });
                    if (sourceVideo) {
                        channelId = sourceVideo.channelId || channelId;
                        channelName = sourceVideo.channelName || channelName;
                        channelThumbnail = sourceVideo.channelThumbnail || null;
                        category = sourceVideo.category || category;
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
                        category,
                    },
                });
                await this.prisma.video.upsert({
                    where: { id: data.youtubeVideoId },
                    update: {
                        type: 'SHORT',
                        title: data.title,
                        description: data.description || '',
                        thumbnail: data.thumbnail || `https://img.youtube.com/vi/${data.youtubeVideoId}/hqdefault.jpg`,
                        creatorUserId: data.userId || undefined,
                        creatorName: data.creatorName || undefined,
                        creatorEmail: data.userEmail || undefined,
                        sourceVideoId: data.sourceVideoId || undefined,
                        clipStartTime: data.clipStartTime != null ? Number(data.clipStartTime) : undefined,
                        clipEndTime: data.clipEndTime != null ? Number(data.clipEndTime) : undefined,
                        cropOffsetX: data.cropOffsetX != null ? Number(data.cropOffsetX) : 0.0,
                        clippedAt: new Date(),
                        category,
                    },
                    create: {
                        id: data.youtubeVideoId,
                        type: 'SHORT',
                        title: data.title,
                        description: data.description || '',
                        thumbnail: data.thumbnail || `https://img.youtube.com/vi/${data.youtubeVideoId}/hqdefault.jpg`,
                        channelId,
                        channelName,
                        channelThumbnail,
                        publishedAt: new Date(),
                        duration: `PT${data.durationSeconds || 60}S`,
                        viewCount: 0,
                        tags: ['#Shorts', 'Christian'],
                        creatorUserId: data.userId || null,
                        creatorName: data.creatorName || null,
                        creatorEmail: data.userEmail || null,
                        sourceVideoId: data.sourceVideoId || null,
                        clipStartTime: data.clipStartTime != null ? Number(data.clipStartTime) : null,
                        clipEndTime: data.clipEndTime != null ? Number(data.clipEndTime) : null,
                        cropOffsetX: data.cropOffsetX != null ? Number(data.cropOffsetX) : 0.0,
                        clippedAt: new Date(),
                        category,
                    },
                });
                this.logger.log(`✅ Short automatically mirrored to Video feed: ${data.youtubeVideoId} ("${data.title}")`);
            }
            catch (feedErr) {
                this.logger.warn(`Could not mirror short creation to Video feed: ${feedErr.message}`);
            }
            return creation;
        }
        catch (e) {
            this.logger.warn(`recordCreation notice: ${e.message}`);
            return null;
        }
    }
    async getMyCreations(userId, email) {
        if (!userId && !email) {
            return [];
        }
        const orConditions = [];
        if (userId) {
            orConditions.push({ userId }, { creatorUserId: userId });
        }
        if (email) {
            orConditions.push({ userEmail: email }, { creatorEmail: email });
        }
        try {
            const creations = await this.prisma.shortCreation.findMany({
                where: {
                    OR: orConditions,
                },
                orderBy: { createdAt: 'desc' },
            }).catch(() => []);
            const videos = await this.prisma.video.findMany({
                where: {
                    type: 'SHORT',
                    OR: orConditions,
                },
                orderBy: { createdAt: 'desc' },
            }).catch(() => []);
            const map = new Map();
            for (const c of creations) {
                map.set(c.youtubeVideoId, {
                    id: c.youtubeVideoId,
                    title: c.title,
                    description: c.description || '',
                    thumbnailUrl: c.thumbnail || `https://img.youtube.com/vi/${c.youtubeVideoId}/hqdefault.jpg`,
                    durationSeconds: c.durationSeconds || 60,
                    sourceVideoId: c.sourceVideoId,
                    clipStartTime: c.clipStartTime,
                    clipEndTime: c.clipEndTime,
                    cropOffsetX: c.cropOffsetX ?? 0.0,
                    creatorName: c.creatorName,
                    creatorEmail: c.userEmail,
                    publishedAt: c.createdAt ? new Date(c.createdAt).toISOString() : new Date().toISOString(),
                    isPublished: true,
                });
            }
            for (const v of videos) {
                if (!map.has(v.id)) {
                    map.set(v.id, {
                        id: v.id,
                        title: v.title,
                        description: v.description,
                        thumbnailUrl: v.thumbnail,
                        durationSeconds: 60,
                        sourceVideoId: v.sourceVideoId,
                        clipStartTime: v.clipStartTime,
                        clipEndTime: v.clipEndTime,
                        cropOffsetX: v.cropOffsetX ?? 0.0,
                        creatorName: v.creatorName,
                        creatorEmail: v.creatorEmail,
                        publishedAt: v.publishedAt ? new Date(v.publishedAt).toISOString() : new Date().toISOString(),
                        isPublished: true,
                    });
                }
            }
            return Array.from(map.values());
        }
        catch (e) {
            this.logger.error(`getMyCreations error: ${e.message}`);
            return [];
        }
    }
    async cleanupLegacyShorts() {
        try {
            const deletedVideos = await this.prisma.video.deleteMany({
                where: {
                    OR: [
                        { id: { startsWith: 'short_' } },
                        { id: { startsWith: 'mock_' } },
                        { id: { startsWith: 'local_' } },
                        { type: 'SHORT', channelId: { startsWith: 'UC_ChristianTube' } },
                    ],
                },
            });
            const deletedCreations = await this.prisma.shortCreation.deleteMany({
                where: {
                    OR: [
                        { youtubeVideoId: { startsWith: 'short_' } },
                        { youtubeVideoId: { startsWith: 'mock_' } },
                        { youtubeVideoId: { startsWith: 'local_' } },
                    ],
                },
            }).catch(() => ({ count: 0 }));
            this.logger.log(`🧹 Cleaned up legacy/mock shorts: ${deletedVideos.count} videos, ${deletedCreations.count} creations.`);
            return {
                success: true,
                deletedVideos: deletedVideos.count,
                deletedCreations: deletedCreations.count,
                message: 'All virtual/mock shorts removed from database. Feed now exclusively serves authentic YouTube shorts.',
            };
        }
        catch (e) {
            this.logger.error(`cleanupLegacyShorts error: ${e.message}`);
            return { success: false, error: e.message };
        }
    }
};
exports.ShortsService = ShortsService;
exports.ShortsService = ShortsService = ShortsService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [config_1.ConfigService,
        prisma_service_1.PrismaService])
], ShortsService);
//# sourceMappingURL=shorts.service.js.map