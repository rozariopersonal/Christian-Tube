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
var ChannelsService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.ChannelsService = void 0;
const common_1 = require("@nestjs/common");
const config_1 = require("@nestjs/config");
const axios_1 = __importDefault(require("axios"));
const prisma_service_1 = require("../prisma/prisma.service");
const sync_service_1 = require("../sync/sync.service");
let ChannelsService = ChannelsService_1 = class ChannelsService {
    constructor(prisma, configService, syncService) {
        this.prisma = prisma;
        this.configService = configService;
        this.syncService = syncService;
        this.logger = new common_1.Logger(ChannelsService_1.name);
    }
    async findAll() {
        const channels = await this.prisma.channel.findMany({
            where: { isActive: true },
            include: {
                _count: {
                    select: { videos: true },
                },
            },
            orderBy: { name: 'asc' },
        });
        return channels.map((c) => ({
            ...c,
            videoCount: c._count.videos,
        }));
    }
    async findOne(id) {
        const channel = await this.prisma.channel.findUnique({
            where: { id },
            include: {
                _count: {
                    select: { videos: true },
                },
            },
        });
        if (!channel) {
            throw new common_1.NotFoundException('Channel not found');
        }
        return {
            ...channel,
            videoCount: channel._count.videos,
        };
    }
    async resolveChannelInfo(input) {
        let clean = input.trim();
        if (!clean)
            return null;
        let handle = null;
        let explicitId = null;
        if (clean.includes('youtube.com/channel/')) {
            explicitId = clean.split('youtube.com/channel/')[1].split('/')[0].split('?')[0];
        }
        else if (clean.includes('youtube.com/@')) {
            handle = clean.split('youtube.com/@')[1].split('/')[0].split('?')[0];
        }
        else if (clean.startsWith('@')) {
            handle = clean.substring(1).split('/')[0].split('?')[0];
        }
        else if (clean.startsWith('UC') && clean.length >= 20) {
            explicitId = clean.split('?')[0];
        }
        else if (!clean.startsWith('http')) {
            handle = clean;
        }
        const apiKey = this.configService.get('youtubeApiKey');
        if (apiKey) {
            try {
                let endpoint = `https://www.googleapis.com/youtube/v3/channels?key=${apiKey}&part=snippet,statistics`;
                if (handle) {
                    endpoint += `&forHandle=${encodeURIComponent(handle)}`;
                }
                else if (explicitId) {
                    endpoint += `&id=${encodeURIComponent(explicitId)}`;
                }
                const res = await axios_1.default.get(endpoint, { timeout: 8000 });
                if (res.data?.items?.length > 0) {
                    const item = res.data.items[0];
                    return {
                        id: item.id,
                        name: item.snippet?.title || handle || explicitId || 'Channel',
                        handle: item.snippet?.customUrl || (handle ? `@${handle}` : null),
                        description: item.snippet?.description || null,
                        thumbnail: item.snippet?.thumbnails?.high?.url || item.snippet?.thumbnails?.medium?.url || item.snippet?.thumbnails?.default?.url || null,
                        subscriberCount: item.statistics?.subscriberCount ? String(item.statistics.subscriberCount) : null,
                    };
                }
            }
            catch (e) {
                this.logger.warn(`YouTube API channel resolution failed: ${e.message}`);
            }
        }
        try {
            const targetUrl = handle
                ? `https://www.youtube.com/@${encodeURIComponent(handle)}`
                : `https://www.youtube.com/channel/${encodeURIComponent(explicitId || clean)}`;
            const res = await axios_1.default.get(targetUrl, {
                headers: {
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                    'Accept-Language': 'en-US,en;q=0.9',
                },
                timeout: 10000,
            });
            const html = res.data;
            if (typeof html === 'string') {
                const idMatch = html.match(/itemprop="identifier"\s+content="(UC[a-zA-Z0-9_-]{22})"/i) ||
                    html.match(/"channelId":"(UC[a-zA-Z0-9_-]{22})"/i) ||
                    html.match(/https:\/\/www\.youtube\.com\/channel\/(UC[a-zA-Z0-9_-]{22})/i);
                const channelId = idMatch ? idMatch[1] : explicitId || (handle ? `@${handle}` : clean);
                const titleMatch = html.match(/<meta\s+property="og:title"\s+content="([^"]+)"/i) ||
                    html.match(/<title>([^<]+)<\/title>/i);
                let name = titleMatch ? titleMatch[1].replace(' - YouTube', '').trim() : handle || 'YouTube Channel';
                const thumbMatch = html.match(/<meta\s+property="og:image"\s+content="([^"]+)"/i) ||
                    html.match(/"avatar":{"thumbnails":\[{"url":"([^"]+)"/i);
                const thumbnail = thumbMatch ? thumbMatch[1] : null;
                const descMatch = html.match(/<meta\s+property="og:description"\s+content="([^"]+)"/i) ||
                    html.match(/<meta\s+name="description"\s+content="([^"]+)"/i);
                const description = descMatch ? descMatch[1] : null;
                return {
                    id: channelId,
                    name,
                    handle: handle ? `@${handle}` : null,
                    thumbnail,
                    description,
                    subscriberCount: null,
                };
            }
        }
        catch (err) {
            this.logger.warn(`Web fallback channel resolution error: ${err.message}`);
        }
        return {
            id: explicitId || (handle ? `@${handle}` : clean),
            name: handle || clean,
            handle: handle ? `@${handle}` : null,
            thumbnail: null,
            description: null,
            subscriberCount: null,
        };
    }
    async searchYouTube(query) {
        const q = (query || '').trim();
        if (!q)
            return [];
        const results = [];
        const seenIds = new Set();
        if (q.startsWith('@') || q.startsWith('UC') || q.includes('youtube.com') || q.includes('youtu.be')) {
            const resolved = await this.resolveChannelInfo(q);
            if (resolved) {
                results.push(resolved);
                seenIds.add(resolved.id);
            }
        }
        const apiKey = this.configService.get('youtubeApiKey');
        if (apiKey) {
            try {
                const searchUrl = `https://www.googleapis.com/youtube/v3/search?key=${apiKey}&q=${encodeURIComponent(q)}&type=channel&part=snippet&maxResults=15`;
                const searchRes = await axios_1.default.get(searchUrl, { timeout: 8000 });
                const items = searchRes.data?.items || [];
                if (items.length > 0) {
                    const channelIds = items
                        .map((it) => it.snippet?.channelId || it.id?.channelId)
                        .filter(Boolean)
                        .join(',');
                    const detailsUrl = `https://www.googleapis.com/youtube/v3/channels?key=${apiKey}&id=${channelIds}&part=snippet,statistics`;
                    const detailsRes = await axios_1.default.get(detailsUrl, { timeout: 8000 });
                    const detailMap = new Map();
                    for (const d of detailsRes.data?.items || []) {
                        detailMap.set(d.id, d);
                    }
                    for (const it of items) {
                        const id = it.snippet?.channelId || it.id?.channelId;
                        if (!id || seenIds.has(id))
                            continue;
                        seenIds.add(id);
                        const detail = detailMap.get(id);
                        const snippet = detail?.snippet || it.snippet;
                        const stats = detail?.statistics;
                        results.push({
                            id,
                            name: snippet?.title || 'Channel',
                            handle: snippet?.customUrl || null,
                            description: snippet?.description || null,
                            thumbnail: snippet?.thumbnails?.high?.url ||
                                snippet?.thumbnails?.medium?.url ||
                                snippet?.thumbnails?.default?.url ||
                                null,
                            subscriberCount: stats?.subscriberCount ? parseInt(stats.subscriberCount, 10) : null,
                            videoCount: stats?.videoCount ? parseInt(stats.videoCount, 10) : null,
                        });
                    }
                }
            }
            catch (e) {
                this.logger.warn(`YouTube Data API search failed: ${e.message}`);
            }
        }
        try {
            const localChannels = await this.prisma.channel.findMany({
                where: {
                    OR: [
                        { name: { contains: q, mode: 'insensitive' } },
                        { id: { contains: q, mode: 'insensitive' } },
                        { description: { contains: q, mode: 'insensitive' } },
                    ],
                },
                include: { _count: { select: { videos: true } } },
                take: 10,
            });
            for (const lc of localChannels) {
                if (!seenIds.has(lc.id)) {
                    seenIds.add(lc.id);
                    results.push({
                        id: lc.id,
                        name: lc.name,
                        handle: null,
                        description: lc.description,
                        thumbnail: lc.thumbnail,
                        subscriberCount: lc.subscriberCount ? parseInt(lc.subscriberCount, 10) : null,
                        videoCount: lc._count.videos,
                        isExisting: true,
                    });
                }
            }
        }
        catch (_) { }
        if (results.length === 0) {
            try {
                const webSearchUrl = `https://www.youtube.com/results?search_query=${encodeURIComponent(q)}&sp=EgIQAg%253D%253D`;
                const res = await axios_1.default.get(webSearchUrl, {
                    headers: {
                        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                    },
                    timeout: 8000,
                });
                const html = res.data;
                if (typeof html === 'string') {
                    const jsonMatch = html.match(/var ytInitialData = ({[\s\S]*?});<\/script>/);
                    if (jsonMatch) {
                        const data = JSON.parse(jsonMatch[1]);
                        const contents = data?.contents?.twoColumnSearchResultsRenderer?.primaryContents?.sectionListRenderer?.contents?.[0]
                            ?.itemSectionRenderer?.contents || [];
                        for (const item of contents) {
                            const chRenderer = item.channelRenderer;
                            if (chRenderer) {
                                const id = chRenderer.channelId;
                                if (id && !seenIds.has(id)) {
                                    seenIds.add(id);
                                    const title = chRenderer.title?.simpleText || 'Channel';
                                    const thumb = chRenderer.thumbnail?.thumbnails?.[0]?.url || null;
                                    const desc = chRenderer.descriptionSnippet?.runs?.map((r) => r.text).join('') || null;
                                    const subsText = chRenderer.videoCountText?.simpleText || '';
                                    results.push({
                                        id,
                                        name: title,
                                        handle: chRenderer.navigationEndpoint?.browseEndpoint?.canonicalBaseUrl || null,
                                        thumbnail: thumb ? (thumb.startsWith('//') ? `https:${thumb}` : thumb) : null,
                                        description: desc,
                                        subscriberCount: null,
                                        videoCount: null,
                                    });
                                }
                            }
                        }
                    }
                }
            }
            catch (err) {
                this.logger.warn(`Web YouTube search scraper error: ${err.message}`);
            }
        }
        if (results.length === 0) {
            results.push({
                id: q.startsWith('@') ? q : `@${q.replaceAll(' ', '')}`,
                name: q,
                handle: q.startsWith('@') ? q : `@${q.replaceAll(' ', '')}`,
                thumbnail: null,
                description: 'Tap Add to ingest this YouTube channel directly into ChristianApp',
                subscriberCount: null,
            });
        }
        return results;
    }
    async addChannel(data) {
        const rawUrl = (data.channelUrl || '').trim();
        if (!rawUrl) {
            throw new Error('Channel URL or ID is required');
        }
        const resolved = await this.resolveChannelInfo(rawUrl);
        const channelId = resolved?.id || rawUrl;
        const channelName = data.name || resolved?.name || channelId;
        const thumbnail = resolved?.thumbnail || null;
        const description = resolved?.description || null;
        const subscriberCount = resolved?.subscriberCount || null;
        const channel = await this.prisma.channel.upsert({
            where: { id: channelId },
            update: {
                name: channelName,
                category: data.category || 'General',
                language: data.language || 'English',
                thumbnail: thumbnail,
                description: description,
                subscriberCount: subscriberCount,
                isActive: true,
            },
            create: {
                id: channelId,
                name: channelName,
                category: data.category || 'General',
                language: data.language || 'English',
                thumbnail: thumbnail,
                description: description,
                subscriberCount: subscriberCount,
                isActive: true,
            },
        });
        this.syncService.syncChannel(channel.id, channel.category).catch((e) => {
            this.logger.warn(`Initial sync error for added channel ${channel.id}: ${e.message}`);
        });
        this.syncService.subscribeChannelToWebSub(channel.id).catch((e) => {
            this.logger.warn(`WebSub subscription error for added channel ${channel.id}: ${e.message}`);
        });
        return {
            status: 'success',
            message: 'Channel successfully added and video ingestion started',
            channel,
        };
    }
    async syncChannel(id) {
        const channel = await this.prisma.channel.findUnique({
            where: { id },
        });
        if (!channel) {
            throw new common_1.NotFoundException(`Channel ${id} not found`);
        }
        this.syncService.syncChannel(channel.id, channel.category).catch((e) => {
            this.logger.error(`Error syncing channel ${channel.name}: ${e.message}`);
        });
        return {
            status: 'accepted',
            message: `Sync process initiated for channel ${channel.name}`,
        };
    }
    async removeChannel(id) {
        try {
            await this.prisma.video.deleteMany({
                where: { channelId: id },
            });
            const deleted = await this.prisma.channel.delete({
                where: { id },
            });
            return {
                status: 'success',
                message: `Channel ${deleted.name} (${id}) and videos removed successfully`,
                channel: deleted,
            };
        }
        catch (e) {
            this.logger.error(`Error removing channel ${id}: ${e.message}`);
            throw e;
        }
    }
    async listRequests() {
        return this.prisma.channelRequest.findMany({
            orderBy: { createdAt: 'desc' },
        });
    }
    async createRequest(data) {
        return this.prisma.channelRequest.create({
            data: {
                channelUrl: data.channelUrl,
                notes: data.notes || null,
                submittedBy: data.submittedBy || 'Anonymous',
                status: 'PENDING',
            },
        });
    }
    async approveRequest(id, adminEmail) {
        const req = await this.prisma.channelRequest.findUnique({
            where: { id },
        });
        if (!req) {
            throw new common_1.NotFoundException(`Channel request ${id} not found`);
        }
        const addResult = await this.addChannel({
            channelUrl: req.channelUrl,
            name: req.notes || undefined,
            adminEmail,
        });
        const updatedReq = await this.prisma.channelRequest.update({
            where: { id },
            data: { status: 'APPROVED' },
        });
        return {
            status: 'success',
            message: 'Channel request approved and channel successfully added',
            request: updatedReq,
            channel: addResult.channel,
        };
    }
    async rejectRequest(id, reason) {
        const req = await this.prisma.channelRequest.findUnique({
            where: { id },
        });
        if (!req) {
            throw new common_1.NotFoundException(`Channel request ${id} not found`);
        }
        const updatedReq = await this.prisma.channelRequest.update({
            where: { id },
            data: {
                status: 'REJECTED',
                notes: reason ? `${req.notes || ''} [Rejected: ${reason}]`.trim() : req.notes,
            },
        });
        return {
            status: 'success',
            message: 'Channel request rejected',
            request: updatedReq,
        };
    }
};
exports.ChannelsService = ChannelsService;
exports.ChannelsService = ChannelsService = ChannelsService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        config_1.ConfigService,
        sync_service_1.SyncService])
], ChannelsService);
//# sourceMappingURL=channels.service.js.map