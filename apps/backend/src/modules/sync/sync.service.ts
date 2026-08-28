import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService } from '../prisma/prisma.service';
import { YoutubeService, ExtractedVideo } from '../youtube/youtube.service';

@Injectable()
export class SyncService implements OnModuleInit {
  private readonly logger = new Logger(SyncService.name);
  private isSyncing = false;

  constructor(
    private readonly configService: ConfigService,
    private readonly prisma: PrismaService,
    private readonly youtubeService: YoutubeService,
  ) {}

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  async onModuleInit() {
    setTimeout(async () => {
      // 1. Auto-subscribe all active channels to Google WebSub Hub
      this.renewAllWebSubSubscriptions().catch((e) => {
        this.logger.warn(`Initial WebSub subscription error on boot: ${e.message}`);
      });

      // 2. Launch centralized sync on wakeup / boot
      this.syncAllChannels().catch((e) => {
        this.logger.warn(`Initial automated sync on boot error: ${e.message}`);
      });

      // 3. Backfill missing metadata & durations
      this.backfillVideoMetadata(500).catch((e) => {
        this.logger.warn(`Initial automated backfill on boot error: ${e.message}`);
      });
    }, 3000);
  }

  /**
   * Periodic scheduler: Runs every 2 hours
   */
  @Cron(CronExpression.EVERY_2_HOURS)
  async scheduledSync() {
    this.logger.log('⏰ Triggering 2-hour scheduled channel sync sweep...');
    return this.syncAllChannels();
  }

  /**
   * Centralized sync method: Ingests videos for all active channels
   */
  async syncAllChannels(force = false) {
    if (this.isSyncing) {
      this.logger.log('Previous channel sync cycle is still active. Skipping concurrent run.');
      return { status: 'skipped', message: 'Sync already in progress' };
    }
    this.isSyncing = true;

    try {
      // Ensure instance custom YouTube channel is registered if configured
      const customChannelId = this.configService.get<string>('shorts.customChannelId');
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
        } catch (_) {}
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
        } catch (err: any) {
          this.logger.error(`Error syncing channel ${channel.name} (${channel.id}): ${err.message}`);
        }
        await this.sleep(250);
      }

      return { status: 'success', channelCount: channels.length };
    } finally {
      this.isSyncing = false;
    }
  }

  /**
   * Sync a single channel using YouTube API or Web Scraper fallback
   */
  async syncChannel(channelId: string, defaultCategory?: string | null) {
    // 1. Refresh channel metadata
    await this.refreshChannelMetadata(channelId);

    // 2. Try official YouTube Data API v3 playlist sync
    if (this.youtubeService.hasApiKey()) {
      try {
        await this.syncViaPlaylistApi(channelId, defaultCategory);
        return;
      } catch (err: any) {
        this.logger.warn(
          `YouTube API playlist sync failed for ${channelId}: ${err.message}. Falling back to web scraper...`,
        );
      }
    }

    // 3. Fallback: Web Scraper & Atom RSS sync
    await this.syncViaWebScraper(channelId, defaultCategory);
  }

  /**
   * Syncs videos using the YouTube Data API v3 Uploads playlist (UU...)
   */
  private async syncViaPlaylistApi(channelId: string, defaultCategory?: string | null) {
    const channel = await this.prisma.channel.findUnique({
      where: { id: channelId },
    });
    if (!channel) return;

    const uploadsPlaylistId = channelId.startsWith('UC')
      ? `UU${channelId.substring(2)}`
      : channelId;

    let pageToken: string | undefined = (channel as any).syncCursor || undefined;
    let batchesProcessed = 0;
    let totalSyncedInRun = 0;
    const maxBatches = 200; // Ingests up to 10,000 videos continuously

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
          } as any,
        });
        break;
      }

      const videoIds = items
        .map((it: any) => it.contentDetails?.videoId || it.snippet?.resourceId?.videoId)
        .filter(Boolean);

      const detailMap = await this.youtubeService.fetchVideosDetails(videoIds);

      for (const it of items) {
        const videoId = it.contentDetails?.videoId || it.snippet?.resourceId?.videoId;
        if (!videoId) continue;

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
        const thumb =
          snippet?.thumbnails?.maxres?.url ||
          snippet?.thumbnails?.high?.url ||
          snippet?.thumbnails?.medium?.url ||
          snippet?.thumbnails?.default?.url ||
          `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;
        const tags = snippet?.tags || [];
        const publishedAt = snippet?.publishedAt ? new Date(snippet.publishedAt) : new Date();

        let parsedMeta: any = null;
        if (isShort && description) {
          const jsonMatch = description.match(/<!--\s*CT_META:\s*(\{.*?\})\s*-->/s);
          if (jsonMatch) {
            try {
              parsedMeta = JSON.parse(jsonMatch[1]);
            } catch (_) {}
          }
        }

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

      // If already COMPLETED during routine checks, stop after Batch 1
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
          } as any,
        });
        await this.sleep(150);
      } else {
        await this.prisma.channel.update({
          where: { id: channelId },
          data: {
            syncCursor: null,
            syncStatus: 'COMPLETED',
            lastSyncedAt: new Date(),
          } as any,
        });
        break;
      }
    }

    this.logger.log(
      `✅ Synced ${totalSyncedInRun} videos in ${batchesProcessed} batch(es) for ${channel.name} (${channelId})`,
    );
  }

  /**
   * Syncs videos via public YouTube HTML pagination + Atom RSS feed fallback
   */
  private async syncViaWebScraper(channelId: string, defaultCategory?: string | null, maxBatches = 50) {
    const channel = await this.prisma.channel.findUnique({
      where: { id: channelId },
    });
    if (!channel) return;

    let syncedCount = 0;

    // 1. Initial RSS feed sync (latest 15 videos)
    const rssVideos = await this.youtubeService.scrapeRssFeed(channelId);
    for (const v of rssVideos) {
      await this.upsertScrapedVideo(v, channel, defaultCategory);
      syncedCount++;
    }

    // 2. Multi-batch HTML channel /videos tab scraping
    const scrapedVideosResult = await this.youtubeService.scrapeChannelVideosTab(channelId, maxBatches);
    for (const v of scrapedVideosResult.videos) {
      await this.upsertScrapedVideo(v, channel, defaultCategory);
      syncedCount++;
    }

    // 3. Multi-batch HTML channel /shorts tab scraping
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

  /**
   * Helper to upsert a scraped video into PostgreSQL
   */
  private async upsertScrapedVideo(v: ExtractedVideo, channel: any, defaultCategory?: string | null) {
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
        transcriptionStatus: 'pending',
      },
    });
  }

  /**
   * Refresh channel metadata: avatar, title, description, subscriber count
   */
  async refreshChannelMetadata(channelId: string) {
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

  /**
   * Subscribe a channel to Google WebSub Hub
   */
  async subscribeChannelToWebSub(channelId: string, mode: 'subscribe' | 'unsubscribe' = 'subscribe') {
    return this.youtubeService.subscribeChannelToWebSub(channelId, mode);
  }

  /**
   * Auto-renew WebSub leases for all active channels daily
   */
  @Cron(CronExpression.EVERY_DAY_AT_MIDNIGHT)
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

  /**
   * Handle incoming XML push notification from Google WebSub
   */
  async handleWebSubPushNotification(xmlBody: string) {
    if (!xmlBody || typeof xmlBody !== 'string') return;

    try {
      const videoIdMatch = xmlBody.match(/<yt:videoId>([^<]+)<\/yt:videoId>/);
      const channelIdMatch = xmlBody.match(/<yt:channelId>([^<]+)<\/yt:channelId>/);
      const titleMatch = xmlBody.match(/<title>([^<]+)<\/title>/);
      const publishedMatch = xmlBody.match(/<published>([^<]+)<\/published>/);

      const videoId = videoIdMatch ? videoIdMatch[1].trim() : null;
      const channelId = channelIdMatch ? channelIdMatch[1].trim() : null;
      const title = titleMatch ? titleMatch[1].trim() : 'Video';
      const publishedAt = publishedMatch ? new Date(publishedMatch[1].trim()) : new Date();

      if (!videoId || !channelId) return;

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
            const thumb =
              snippet?.thumbnails?.maxres?.url ||
              snippet?.thumbnails?.high?.url ||
              snippet?.thumbnails?.medium?.url ||
              `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;

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
                transcriptionStatus: 'pending',
              },
            });
            this.logger.log(`✅ Live synced new video "${title}" (${videoId}) via WebSub push`);
            return;
          }
        } catch (apiErr: any) {
          this.logger.warn(`Could not fetch details for live WebSub video ${videoId}: ${apiErr.message}`);
        }
      }

      // Fallback direct upsert from XML payload
      await this.prisma.video.upsert({
        where: { id: videoId },
        update: {
          title,
          publishedAt,
          channelName,
          channelThumbnail: channelThumb,
          category,
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
          transcriptionStatus: 'pending',
        },
      });

      this.logger.log(`✅ Live synced new video "${title}" (${videoId}) via WebSub push XML`);
    } catch (err: any) {
      this.logger.error(`Error handling WebSub push notification payload: ${err.message}`);
    }
  }

  /**
   * Backfill missing duration & stats for videos with duration = '0:00'
   */
  async backfillVideoMetadata(batchSize = 250) {
    if (!this.youtubeService.hasApiKey()) return;

    try {
      const videos = await this.prisma.video.findMany({
        where: {
          OR: [{ duration: '0:00' }, { duration: '' }],
        },
        take: batchSize,
        select: { id: true },
      });

      if (!videos.length) return;

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
    } catch (e: any) {
      this.logger.warn(`Video metadata backfill error: ${e.message}`);
    }
  }

  async syncSingleVideo(videoId: string) {
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

    let parsedMeta: any = null;
    if (description) {
      const jsonMatch = description.match(/<!--\s*CT_META:\s*(\{.*?\})\s*-->/s);
      if (jsonMatch) {
        try {
          parsedMeta = JSON.parse(jsonMatch[1]);
        } catch (_) {}
      }
    }

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

    // Record in ShortCreation table if creator info is present
    if (isShort && (parsedMeta?.creatorUserId || parsedMeta?.creatorEmail)) {
      try {
        await (this.prisma as any).shortCreation.upsert({
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
      } catch (scErr: any) {
        this.logger.warn(`ShortCreation record notice: ${scErr.message}`);
      }
    }

    this.logger.log(`✅ Single video synced successfully: ${saved.id} ("${saved.title}")`);
    return saved;
  }
}
