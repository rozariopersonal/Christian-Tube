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
var SyncService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.SyncService = void 0;
const common_1 = require("@nestjs/common");
const config_1 = require("@nestjs/config");
const schedule_1 = require("@nestjs/schedule");
const prisma_service_1 = require("../prisma/prisma.service");
const youtube_service_1 = require("../youtube/youtube.service");
const metadata_extractor_1 = require("./metadata-extractor");
let SyncService = SyncService_1 = class SyncService {
    constructor(configService, prisma, youtubeService) {
        this.configService = configService;
        this.prisma = prisma;
        this.youtubeService = youtubeService;
        this.logger = new common_1.Logger(SyncService_1.name);
        this.isSyncing = false;
    }
    sleep(ms) {
        return new Promise((resolve) => setTimeout(resolve, ms));
    }
    async onModuleInit() {
        setTimeout(async () => {
            this.renewAllWebSubSubscriptions().catch((e) => {
                this.logger.warn(`Initial WebSub subscription error on boot: ${e.message}`);
            });
            this.syncAllChannels().catch((e) => {
                this.logger.warn(`Initial automated sync on boot error: ${e.message}`);
            });
            this.backfillVideoMetadata(500).catch((e) => {
                this.logger.warn(`Initial automated backfill on boot error: ${e.message}`);
            });
        }, 3000);
    }
    async scheduledSync() {
        this.logger.log('⏰ Triggering 2-hour scheduled channel sync sweep...');
        return this.syncAllChannels();
    }
    async syncAllChannels(force = false) {
        if (this.isSyncing) {
            this.logger.log('Previous channel sync cycle is still active. Skipping concurrent run.');
            return { status: 'skipped', message: 'Sync already in progress' };
        }
        this.isSyncing = true;
        try {
            const customChannelId = this.configService.get('shorts.customChannelId');
            if (customChannelId && customChannelId.startsWith('UC')) {
                try {
                    await this.prisma.channel.upsert({
                        where: { id: customChannelId },
                        update: { isActive: true },
                        create: {
                            id: customChannelId,
                            name: 'Community Shorts',
                            isActive: true,
                            category: 'Shorts',
                        },
                    });
                }
                catch (_) { }
            }
            const channels = await this.prisma.channel.findMany({
                where: { isActive: true },
                orderBy: { updatedAt: 'asc' },
            });
            if (!channels.length) {
                this.logger.log('No active channels found to sync.');
                return { status: 'completed', count: 0 };
            }
            this.logger.log(`🔄 Centralized sync started for ${channels.length} active channels...`);
            for (const channel of channels) {
                try {
                    await this.syncChannel(channel.id, channel.category);
                }
                catch (err) {
                    this.logger.error(`Error syncing channel ${channel.name} (${channel.id}): ${err.message}`);
                }
                await this.sleep(250);
            }
            return { status: 'success', channelCount: channels.length };
        }
        finally {
            this.isSyncing = false;
        }
    }
    async syncChannel(channelId, defaultCategory) {
        await this.refreshChannelMetadata(channelId);
        if (this.youtubeService.hasApiKey()) {
            try {
                await this.syncViaPlaylistApi(channelId, defaultCategory);
                return;
            }
            catch (err) {
                this.logger.warn(`YouTube API playlist sync failed for ${channelId}: ${err.message}. Falling back to web scraper...`);
            }
        }
        await this.syncViaWebScraper(channelId, defaultCategory);
    }
    async syncViaPlaylistApi(channelId, defaultCategory) {
        const channel = await this.prisma.channel.findUnique({
            where: { id: channelId },
        });
        if (!channel)
            return;
        const uploadsPlaylistId = channelId.startsWith('UC')
            ? `UU${channelId.substring(2)}`
            : channelId;
        let pageToken = channel.syncCursor || undefined;
        let batchesProcessed = 0;
        let totalSyncedInRun = 0;
        const maxBatches = 200;
        while (batchesProcessed < maxBatches) {
            batchesProcessed++;
            const playlistRes = await this.youtubeService.fetchPlaylistItems(uploadsPlaylistId, pageToken);
            const items = playlistRes.items || [];
            const nextPageToken = playlistRes.nextPageToken;
            if (!items.length) {
                await this.prisma.channel.update({
                    where: { id: channelId },
                    data: {
                        syncStatus: 'COMPLETED',
                        syncCursor: null,
                        lastSyncedAt: new Date(),
                    },
                });
                break;
            }
            const videoIds = items
                .map((it) => it.contentDetails?.videoId || it.snippet?.resourceId?.videoId)
                .filter(Boolean);
            const detailMap = await this.youtubeService.fetchVideosDetails(videoIds);
            for (const it of items) {
                const videoId = it.contentDetails?.videoId || it.snippet?.resourceId?.videoId;
                if (!videoId)
                    continue;
                const detail = detailMap.get(videoId);
                const snippet = detail?.snippet || it.snippet;
                const contentDetails = detail?.contentDetails;
                const stats = detail?.statistics;
                const duration = this.youtubeService.parseIsoDuration(contentDetails?.duration || '');
                const durationSeconds = this.youtubeService.parseIsoDurationSeconds(contentDetails?.duration || '');
                const title = snippet?.title || 'Video';
                const titleLower = title.toLowerCase();
                const description = snippet?.description || '';
                const descLower = description.toLowerCase();
                const hasShortsTag = titleLower.includes('#short') || descLower.includes('#short');
                const isShort = (durationSeconds > 0 && durationSeconds <= 180) || hasShortsTag;
                const videoType = isShort ? 'SHORT' : 'VIDEO';
                const viewCount = stats?.viewCount ? parseInt(stats.viewCount, 10) : 0;
                const thumb = snippet?.thumbnails?.maxres?.url ||
                    snippet?.thumbnails?.high?.url ||
                    snippet?.thumbnails?.medium?.url ||
                    snippet?.thumbnails?.default?.url ||
                    `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;
                const tags = snippet?.tags || [];
                const publishedAt = snippet?.publishedAt ? new Date(snippet.publishedAt) : new Date();
                let parsedMeta = null;
                if (isShort && description) {
                    const jsonMatch = description.match(/<!--\s*CT_META:\s*(\{.*?\})\s*-->/s);
                    if (jsonMatch) {
                        try {
                            parsedMeta = JSON.parse(jsonMatch[1]);
                        }
                        catch (_) { }
                    }
                }
                const videoMetadata = (0, metadata_extractor_1.extractVideoMetadata)({
                    title,
                    description,
                    channelTitle: snippet?.channelTitle || channel.name,
                    tags,
                });
                await this.prisma.video.upsert({
                    where: { id: videoId },
                    update: {
                        type: videoType,
                        title,
                        description,
                        thumbnail: thumb,
                        publishedAt,
                        channelName: snippet?.channelTitle || channel.name,
                        channelThumbnail: channel.thumbnail,
                        channelSubscriberCount: channel.subscriberCount,
                        duration,
                        viewCount,
                        tags,
                        category: defaultCategory || channel.category || 'General',
                        metadata: videoMetadata,
                        creatorName: parsedMeta?.creatorName || undefined,
                        creatorEmail: parsedMeta?.creatorEmail || undefined,
                        sourceVideoId: parsedMeta?.sourceVideoId || undefined,
                        clipStartTime: parsedMeta?.startTime != null ? Number(parsedMeta.startTime) : undefined,
                        clipEndTime: parsedMeta?.endTime != null ? Number(parsedMeta.endTime) : undefined,
                    },
                    create: {
                        id: videoId,
                        type: videoType,
                        title,
                        description,
                        thumbnail: thumb,
                        channelId,
                        channelName: snippet?.channelTitle || channel.name,
                        channelThumbnail: channel.thumbnail,
                        channelSubscriberCount: channel.subscriberCount,
                        publishedAt,
                        duration,
                        viewCount,
                        tags,
                        category: defaultCategory || channel.category || 'General',
                        metadata: videoMetadata,
                        transcriptionStatus: 'pending',
                        creatorName: parsedMeta?.creatorName || null,
                        creatorEmail: parsedMeta?.creatorEmail || null,
                        sourceVideoId: parsedMeta?.sourceVideoId || null,
                        clipStartTime: parsedMeta?.startTime != null ? Number(parsedMeta.startTime) : null,
                        clipEndTime: parsedMeta?.endTime != null ? Number(parsedMeta.endTime) : null,
                        clippedAt: parsedMeta ? new Date() : null,
                    },
                });
                totalSyncedInRun++;
            }
            if (channel.syncStatus === 'COMPLETED' && !channel.syncCursor && batchesProcessed === 1) {
                await this.prisma.channel.update({
                    where: { id: channelId },
                    data: { lastSyncedAt: new Date() },
                });
                break;
            }
            if (nextPageToken) {
                pageToken = nextPageToken;
                await this.prisma.channel.update({
                    where: { id: channelId },
                    data: {
                        syncCursor: nextPageToken,
                        syncStatus: 'SYNCING',
                        lastSyncedAt: new Date(),
                    },
                });
                await this.sleep(150);
            }
            else {
                await this.prisma.channel.update({
                    where: { id: channelId },
                    data: {
                        syncCursor: null,
                        syncStatus: 'COMPLETED',
                        lastSyncedAt: new Date(),
                    },
                });
                break;
            }
        }
        this.logger.log(`✅ Synced ${totalSyncedInRun} videos in ${batchesProcessed} batch(es) for ${channel.name} (${channelId})`);
    }
    async syncViaWebScraper(channelId, defaultCategory, maxBatches = 50) {
        const channel = await this.prisma.channel.findUnique({
            where: { id: channelId },
        });
        if (!channel)
            return;
        let syncedCount = 0;
        const rssVideos = await this.youtubeService.scrapeRssFeed(channelId);
        for (const v of rssVideos) {
            await this.upsertScrapedVideo(v, channel, defaultCategory);
            syncedCount++;
        }
        const scrapedVideosResult = await this.youtubeService.scrapeChannelVideosTab(channelId, maxBatches);
        for (const v of scrapedVideosResult.videos) {
            await this.upsertScrapedVideo(v, channel, defaultCategory);
            syncedCount++;
        }
        const scrapedStreamsResult = await this.youtubeService.scrapeChannelStreamsTab(channelId, maxBatches);
        for (const v of scrapedStreamsResult.videos) {
            await this.upsertScrapedVideo(v, channel, defaultCategory);
            syncedCount++;
        }
        const scrapedShortsResult = await this.youtubeService.scrapeChannelShortsTab(channelId, 25);
        for (const v of scrapedShortsResult.videos) {
            await this.upsertScrapedVideo({ ...v, videoType: 'SHORT' }, channel, defaultCategory);
            syncedCount++;
        }
        await this.prisma.channel.update({
            where: { id: channelId },
            data: {
                lastSyncedAt: new Date(),
                syncStatus: 'COMPLETED',
                syncCursor: null,
            },
        });
        this.logger.log(`✅ Synced total ${syncedCount} videos and shorts via web scraper for ${channel.name} (${channelId})`);
    }
    async upsertScrapedVideo(v, channel, defaultCategory) {
        const videoMetadata = (0, metadata_extractor_1.extractVideoMetadata)({
            title: v.title,
            description: '',
            channelTitle: channel.name,
        });
        await this.prisma.video.upsert({
            where: { id: v.videoId },
            update: {
                type: v.videoType,
                title: v.title,
                thumbnail: v.thumbnail,
                duration: v.duration && v.duration !== '0:00' ? v.duration : undefined,
                viewCount: v.viewCount > 0 ? v.viewCount : undefined,
                publishedAt: v.publishedAt || undefined,
                channelName: channel.name,
                channelThumbnail: channel.thumbnail,
                channelSubscriberCount: channel.subscriberCount,
                category: defaultCategory || channel.category || 'General',
                metadata: videoMetadata,
            },
            create: {
                id: v.videoId,
                type: v.videoType,
                title: v.title,
                description: '',
                thumbnail: v.thumbnail,
                channelId: channel.id,
                channelName: channel.name,
                channelThumbnail: channel.thumbnail,
                channelSubscriberCount: channel.subscriberCount,
                publishedAt: v.publishedAt || new Date(),
                duration: v.duration || '0:00',
                viewCount: v.viewCount || 0,
                category: defaultCategory || channel.category || 'General',
                metadata: videoMetadata,
                transcriptionStatus: 'pending',
            },
        });
    }
    async refreshChannelMetadata(channelId) {
        const meta = await this.youtubeService.fetchChannelMetadata(channelId);
        if (meta) {
            return await this.prisma.channel.update({
                where: { id: channelId },
                data: {
                    name: meta.title || undefined,
                    thumbnail: meta.thumbnail || undefined,
                    description: meta.description || undefined,
                    subscriberCount: meta.subscriberCount || undefined,
                },
            });
        }
    }
    async subscribeChannelToWebSub(channelId, mode = 'subscribe') {
        return this.youtubeService.subscribeChannelToWebSub(channelId, mode);
    }
    async renewAllWebSubSubscriptions() {
        const channels = await this.prisma.channel.findMany({
            where: { isActive: true },
        });
        this.logger.log(`🔄 Renewing Google WebSub subscriptions for ${channels.length} channels...`);
        for (const ch of channels) {
            await this.subscribeChannelToWebSub(ch.id, 'subscribe');
            await this.sleep(200);
        }
    }
    async handleWebSubPushNotification(xmlBody) {
        if (!xmlBody || typeof xmlBody !== 'string')
            return;
        try {
            const videoIdMatch = xmlBody.match(/<yt:videoId>([^<]+)<\/yt:videoId>/);
            const channelIdMatch = xmlBody.match(/<yt:channelId>([^<]+)<\/yt:channelId>/);
            const titleMatch = xmlBody.match(/<title>([^<]+)<\/title>/);
            const publishedMatch = xmlBody.match(/<published>([^<]+)<\/published>/);
            const videoId = videoIdMatch ? videoIdMatch[1].trim() : null;
            const channelId = channelIdMatch ? channelIdMatch[1].trim() : null;
            const title = titleMatch ? titleMatch[1].trim() : 'Video';
            const publishedAt = publishedMatch ? new Date(publishedMatch[1].trim()) : new Date();
            if (!videoId || !channelId)
                return;
            this.logger.log(`⚡ Live WebSub video publish event: "${title}" (${videoId}) on channel ${channelId}`);
            const channel = await this.prisma.channel.findUnique({ where: { id: channelId } });
            const channelName = channel?.name || 'Channel';
            const channelThumb = channel?.thumbnail || null;
            const category = channel?.category || 'General';
            if (this.youtubeService.hasApiKey()) {
                try {
                    const detailMap = await this.youtubeService.fetchVideosDetails([videoId]);
                    const item = detailMap.get(videoId);
                    if (item) {
                        const snippet = item.snippet;
                        const contentDetails = item.contentDetails;
                        const stats = item.statistics;
                        const duration = this.youtubeService.parseIsoDuration(contentDetails?.duration || '');
                        const durationSeconds = this.youtubeService.parseIsoDurationSeconds(contentDetails?.duration || '');
                        const hasShortsTag = (snippet?.title || '').toLowerCase().includes('#short') ||
                            (snippet?.description || '').toLowerCase().includes('#short');
                        const isShort = (durationSeconds > 0 && durationSeconds <= 180) || hasShortsTag;
                        const videoType = isShort ? 'SHORT' : 'VIDEO';
                        const thumb = snippet?.thumbnails?.maxres?.url ||
                            snippet?.thumbnails?.high?.url ||
                            snippet?.thumbnails?.medium?.url ||
                            `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;
                        const videoMetadata = (0, metadata_extractor_1.extractVideoMetadata)({
                            title: snippet?.title || title,
                            description: snippet?.description || '',
                            channelTitle: snippet?.channelTitle || channelName,
                        });
                        await this.prisma.video.upsert({
                            where: { id: videoId },
                            update: {
                                type: videoType,
                                title: snippet?.title || title,
                                description: snippet?.description || '',
                                thumbnail: thumb,
                                publishedAt: snippet?.publishedAt ? new Date(snippet.publishedAt) : publishedAt,
                                duration,
                                viewCount: stats?.viewCount ? parseInt(stats.viewCount, 10) : 0,
                                channelName: snippet?.channelTitle || channelName,
                                channelThumbnail: channelThumb,
                                category,
                                metadata: videoMetadata,
                            },
                            create: {
                                id: videoId,
                                type: videoType,
                                title: snippet?.title || title,
                                description: snippet?.description || '',
                                thumbnail: thumb,
                                channelId,
                                channelName: snippet?.channelTitle || channelName,
                                channelThumbnail: channelThumb,
                                publishedAt: snippet?.publishedAt ? new Date(snippet.publishedAt) : publishedAt,
                                duration,
                                viewCount: stats?.viewCount ? parseInt(stats.viewCount, 10) : 0,
                                category,
                                metadata: videoMetadata,
                                transcriptionStatus: 'pending',
                            },
                        });
                        this.logger.log(`✅ Live synced new video "${title}" (${videoId}) via WebSub push`);
                        return;
                    }
                }
                catch (apiErr) {
                    this.logger.warn(`Could not fetch details for live WebSub video ${videoId}: ${apiErr.message}`);
                }
            }
            const fallbackMeta = (0, metadata_extractor_1.extractVideoMetadata)({
                title,
                description: '',
                channelTitle: channelName,
            });
            await this.prisma.video.upsert({
                where: { id: videoId },
                update: {
                    title,
                    publishedAt,
                    channelName,
                    channelThumbnail: channelThumb,
                    category,
                    metadata: fallbackMeta,
                },
                create: {
                    id: videoId,
                    type: 'VIDEO',
                    title,
                    description: '',
                    thumbnail: `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`,
                    channelId,
                    channelName,
                    channelThumbnail: channelThumb,
                    publishedAt,
                    duration: '0:00',
                    viewCount: 0,
                    category,
                    metadata: fallbackMeta,
                    transcriptionStatus: 'pending',
                },
            });
            this.logger.log(`✅ Live synced new video "${title}" (${videoId}) via WebSub push XML`);
        }
        catch (err) {
            this.logger.error(`Error handling WebSub push notification payload: ${err.message}`);
        }
    }
    async backfillVideoMetadata(batchSize = 250) {
        if (!this.youtubeService.hasApiKey())
            return;
        try {
            const videos = await this.prisma.video.findMany({
                where: {
                    OR: [{ duration: '0:00' }, { duration: '' }],
                },
                take: batchSize,
                select: { id: true },
            });
            if (!videos.length)
                return;
            this.logger.log(`Starting metadata backfill for ${videos.length} videos...`);
            const videoIds = videos.map((v) => v.id);
            for (let i = 0; i < videoIds.length; i += 50) {
                const chunk = videoIds.slice(i, i + 50);
                const detailMap = await this.youtubeService.fetchVideosDetails(chunk);
                for (const [id, item] of detailMap.entries()) {
                    const contentDetails = item.contentDetails;
                    const stats = item.statistics;
                    const duration = this.youtubeService.parseIsoDuration(contentDetails?.duration || '');
                    const durationSeconds = this.youtubeService.parseIsoDurationSeconds(contentDetails?.duration || '');
                    const isShort = durationSeconds > 0 && durationSeconds <= 180;
                    await this.prisma.video.update({
                        where: { id },
                        data: {
                            duration: duration !== '0:00' ? duration : undefined,
                            viewCount: stats?.viewCount ? parseInt(stats.viewCount, 10) : undefined,
                            type: isShort ? 'SHORT' : undefined,
                        },
                    });
                }
                await this.sleep(100);
            }
            this.logger.log(`✅ Metadata backfill completed for ${videos.length} videos.`);
        }
        catch (e) {
            this.logger.warn(`Video metadata backfill error: ${e.message}`);
        }
    }
    async syncSingleVideo(videoId) {
        this.logger.log(`Directly syncing video from YouTube: ${videoId}`);
        const detailMap = await this.youtubeService.fetchVideosDetails([videoId]);
        const item = detailMap.get(videoId);
        if (!item) {
            this.logger.warn(`Could not find details for video ${videoId} from YouTube API`);
            return null;
        }
        const snippet = item.snippet;
        const contentDetails = item.contentDetails;
        const stats = item.statistics;
        const title = snippet?.title || 'Christian Short';
        const description = snippet?.description || '';
        const channelId = snippet?.channelId || 'UCSaJppP4zb2vivjxYfTqOKw';
        const channelName = snippet?.channelTitle || 'Christian Tube';
        const publishedAt = snippet?.publishedAt ? new Date(snippet.publishedAt) : new Date();
        const duration = this.youtubeService.parseIsoDuration(contentDetails?.duration || 'PT60S');
        const durationSeconds = this.youtubeService.parseIsoDurationSeconds(contentDetails?.duration || 'PT60S');
        const isShort = (durationSeconds > 0 && durationSeconds <= 180) || title.toLowerCase().includes('#short') || description.toLowerCase().includes('#short');
        const thumb = snippet?.thumbnails?.maxres?.url || snippet?.thumbnails?.high?.url || `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;
        let parsedMeta = null;
        if (description) {
            const jsonMatch = description.match(/<!--\s*CT_META:\s*(\{.*?\})\s*-->/s);
            if (jsonMatch) {
                try {
                    parsedMeta = JSON.parse(jsonMatch[1]);
                }
                catch (_) { }
            }
        }
        const videoMetadata = (0, metadata_extractor_1.extractVideoMetadata)({
            title,
            description,
            channelTitle: channelName,
        });
        const saved = await this.prisma.video.upsert({
            where: { id: videoId },
            update: {
                type: isShort ? 'SHORT' : 'VIDEO',
                title,
                description,
                thumbnail: thumb,
                channelId,
                channelName,
                publishedAt,
                duration,
                viewCount: stats?.viewCount ? parseInt(stats.viewCount, 10) : 0,
                metadata: videoMetadata,
                creatorUserId: parsedMeta?.creatorUserId || undefined,
                creatorName: parsedMeta?.creatorName || undefined,
                creatorEmail: parsedMeta?.creatorEmail || undefined,
                sourceVideoId: parsedMeta?.sourceVideoId || undefined,
                clipStartTime: parsedMeta?.startTime != null ? Number(parsedMeta.startTime) : undefined,
                clipEndTime: parsedMeta?.endTime != null ? Number(parsedMeta.endTime) : undefined,
                cropOffsetX: parsedMeta?.cropOffsetX != null ? Number(parsedMeta.cropOffsetX) : undefined,
            },
            create: {
                id: videoId,
                type: isShort ? 'SHORT' : 'VIDEO',
                title,
                description,
                thumbnail: thumb,
                channelId,
                channelName,
                publishedAt,
                duration,
                viewCount: stats?.viewCount ? parseInt(stats.viewCount, 10) : 0,
                tags: ['#Shorts'],
                category: 'Shorts',
                metadata: videoMetadata,
                transcriptionStatus: 'pending',
                creatorUserId: parsedMeta?.creatorUserId || null,
                creatorName: parsedMeta?.creatorName || null,
                creatorEmail: parsedMeta?.creatorEmail || null,
                sourceVideoId: parsedMeta?.sourceVideoId || null,
                clipStartTime: parsedMeta?.startTime != null ? Number(parsedMeta.startTime) : null,
                clipEndTime: parsedMeta?.endTime != null ? Number(parsedMeta.endTime) : null,
                cropOffsetX: parsedMeta?.cropOffsetX != null ? Number(parsedMeta.cropOffsetX) : 0.0,
                clippedAt: parsedMeta ? new Date() : null,
            },
        });
        if (isShort && (parsedMeta?.creatorUserId || parsedMeta?.creatorEmail)) {
            try {
                await this.prisma.shortCreation.upsert({
                    where: { id: `sc_${videoId}` },
                    update: {
                        userId: parsedMeta.creatorUserId || undefined,
                        userEmail: parsedMeta.creatorEmail || undefined,
                        creatorName: parsedMeta.creatorName || undefined,
                        youtubeVideoId: videoId,
                        sourceVideoId: parsedMeta.sourceVideoId || undefined,
                        title,
                        description,
                        thumbnail: thumb,
                        durationSeconds,
                        clipStartTime: parsedMeta.startTime != null ? Number(parsedMeta.startTime) : undefined,
                        clipEndTime: parsedMeta.endTime != null ? Number(parsedMeta.endTime) : undefined,
                        cropOffsetX: parsedMeta.cropOffsetX != null ? Number(parsedMeta.cropOffsetX) : undefined,
                    },
                    create: {
                        id: `sc_${videoId}`,
                        userId: parsedMeta.creatorUserId || null,
                        userEmail: parsedMeta.creatorEmail || null,
                        creatorName: parsedMeta.creatorName || null,
                        youtubeVideoId: videoId,
                        sourceVideoId: parsedMeta.sourceVideoId || null,
                        title,
                        description,
                        thumbnail: thumb,
                        durationSeconds,
                        clipStartTime: parsedMeta.startTime != null ? Number(parsedMeta.startTime) : null,
                        clipEndTime: parsedMeta.endTime != null ? Number(parsedMeta.endTime) : null,
                        cropOffsetX: parsedMeta.cropOffsetX != null ? Number(parsedMeta.cropOffsetX) : 0.0,
                    },
                });
            }
            catch (scErr) {
                this.logger.warn(`ShortCreation record notice: ${scErr.message}`);
            }
        }
        this.logger.log(`✅ Single video synced successfully: ${saved.id} ("${saved.title}")`);
        return saved;
    }
};
exports.SyncService = SyncService;
__decorate([
    (0, schedule_1.Cron)(schedule_1.CronExpression.EVERY_2_HOURS),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", Promise)
], SyncService.prototype, "scheduledSync", null);
__decorate([
    (0, schedule_1.Cron)(schedule_1.CronExpression.EVERY_DAY_AT_MIDNIGHT),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", Promise)
], SyncService.prototype, "renewAllWebSubSubscriptions", null);
exports.SyncService = SyncService = SyncService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [config_1.ConfigService,
        prisma_service_1.PrismaService,
        youtube_service_1.YoutubeService])
], SyncService);
//# sourceMappingURL=sync.service.js.map