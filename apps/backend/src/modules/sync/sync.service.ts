import { Injectable, Logger, OnModuleInit, Optional } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService } from '../prisma/prisma.service';
import { YoutubeService, ExtractedVideo } from '../youtube/youtube.service';
import { CacheService } from '../cache/cache.service';
import { VideoVectorService } from '../video-vector/video-vector.service';
import { extractVideoMetadata, isSongChannel } from './metadata-extractor';
import { AdminAudioProcessorService } from '../admin-audio-processor/admin-audio-processor.service';

function isActiveOrUpcomingBroadcast(video: any): boolean {
  const broadcastState = video?.snippet?.liveBroadcastContent;
  return broadcastState === 'live' || broadcastState === 'upcoming';
}

@Injectable()
export class SyncService implements OnModuleInit {
  private readonly logger = new Logger(SyncService.name);
  private isSyncing = false;
  private syncEnabledOverride: boolean | null = null;

  constructor(
    private readonly configService: ConfigService,
    private readonly prisma: PrismaService,
    private readonly youtubeService: YoutubeService,
    @Optional() private readonly cache?: CacheService,
    @Optional() private readonly adminAudioProcessor?: AdminAudioProcessorService,
    @Optional() private readonly videoVector?: VideoVectorService,
  ) {}

  private queueVectorUpsert(videos: any[]) {
    if (!this.videoVector || !videos.length) return;
    this.videoVector.upsertVideos(videos).catch((e: any) => {
      this.logger.warn(`Upstash video vector upsert warning: ${e?.message || e}`);
    });
  }

  isSyncEnabled(): boolean {
    if (this.syncEnabledOverride !== null) return this.syncEnabledOverride;
    const cfg = this.configService.get<boolean>('youtubeSyncEnabled');
    if (cfg !== undefined) return cfg;
    return process.env.YOUTUBE_SYNC_ENABLED !== 'false';
  }

  setSyncEnabled(enabled: boolean): void {
    this.syncEnabledOverride = enabled;
    this.logger.log(`YouTube sync runtime override set to: ${enabled}`);
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  private async removeConfirmedPrivateVideo(videoId: string): Promise<boolean> {
    let removed = false;
    try {
      const deletedVideos = await this.prisma.video.deleteMany({
        where: { id: videoId },
      });
      if (deletedVideos.count > 0) {
        removed = true;
      }
      const shortCreationModel = (this.prisma as any).shortCreation;
      if (shortCreationModel?.deleteMany) {
        const deletedCreations = await shortCreationModel.deleteMany({
          where: { youtubeVideoId: videoId },
        });
        if (deletedCreations?.count > 0) {
          removed = true;
        }
      }
      if (removed) {
        this.logger.log(`Removed confirmed private video record: ${videoId}`);
        await this.cache?.invalidate('videos', 'channels');
      }
    } catch (err: any) {
      this.logger.warn(`Failed to remove confirmed private video ${videoId}: ${err.message}`);
    }
    return removed;
  }

  async onModuleInit() {
    if (!this.isSyncEnabled()) {
      this.logger.log('YouTube sync is disabled (YOUTUBE_SYNC_ENABLED=false). Skipping boot WebSub & channel sync.');
      return;
    }

    const syncOnBoot = process.env.SYNC_ON_BOOT === 'true' || this.configService.get<string>('SYNC_ON_BOOT') === 'true';
    setTimeout(async () => {
      // 1. Auto-subscribe all active channels to Google WebSub Hub
      this.renewAllWebSubSubscriptions().catch((e) => {
        this.logger.warn(`Initial WebSub subscription error on boot: ${e.message}`);
      });

      if (syncOnBoot) {
        // 2. Launch centralized sync on wakeup / boot only if SYNC_ON_BOOT=true
        this.syncAllChannels().catch((e) => {
          this.logger.warn(`Initial automated sync on boot error: ${e.message}`);
        });

        // 3. Backfill missing metadata & durations
        this.backfillVideoMetadata(500).catch((e) => {
          this.logger.warn(`Initial automated backfill on boot error: ${e.message}`);
        });
      } else {
        this.logger.log('Boot-time channel sync disabled (SYNC_ON_BOOT != true). Daily sync will run at 12:00 PM (IST).');
      }
    }, 3000);
  }

  /**
   * Periodic scheduler: Runs once a day at 12:00 PM (Noon) local time (IST)
   */
  @Cron('0 0 12 * * *', {
    timeZone: process.env.TIMEZONE || 'Asia/Kolkata',
  })
  async scheduledSync() {
    if (!this.isSyncEnabled()) {
      this.logger.log('Daily scheduled YouTube sync skipped (YOUTUBE_SYNC_ENABLED=false).');
      return { status: 'disabled' };
    }
    this.logger.log('⏰ Triggering daily daytime scheduled channel sync sweep at 12:00 PM (IST)...');
    return this.syncAllChannels();
  }

  /**
   * Renew Google WebSub leases every 3 days (leases expire after ~5 days).
   */
  @Cron('0 30 11 */3 * *', {
    timeZone: process.env.TIMEZONE || 'Asia/Kolkata',
  })
  async scheduledWebSubRenewal() {
    if (!this.isSyncEnabled()) return;
    this.logger.log('Renewing Google WebSub channel subscriptions (3-day schedule)...');
    await this.renewAllWebSubSubscriptions();
  }

  /**
   * Centralized sync method: Ingests videos for all active channels
   */
  async syncAllChannels(force = false, full = false) {
    if (!force && !this.isSyncEnabled()) {
      this.logger.log('YouTube sync is disabled (YOUTUBE_SYNC_ENABLED=false). Skipping syncAllChannels.');
      return { status: 'disabled', message: 'YouTube sync is disabled in this environment.' };
    }
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

      this.logger.log(`🔄 Centralized sync started for ${channels.length} active channels (full=${full})...`);

      let succeeded = 0;
      let failed = 0;
      for (const channel of channels) {
        try {
          await this.syncChannel(channel.id, channel.category, force, { full });
          succeeded++;
        } catch (err: any) {
          failed++;
          this.logger.error(`Error syncing channel ${channel.name} (${channel.id}): ${err.message}`);
        }
        await this.sleep(250);
      }

      return { status: 'success', channelCount: channels.length, succeeded, failed };
    } finally {
      this.isSyncing = false;
      await this.cache?.invalidate('videos', 'channels', 'video-search');
    }
  }

  /**
   * Sync a single channel using YouTube API or Web Scraper fallback
   */
  async syncChannel(
    channelId: string,
    defaultCategory?: string | null,
    force = false,
    options: { full?: boolean } = {},
  ) {
    if (!force && !this.isSyncEnabled()) {
      this.logger.log(`YouTube sync disabled; skipping syncChannel(${channelId}).`);
      return;
    }
    try {
      // 1. Refresh channel metadata
      await this.refreshChannelMetadata(channelId);

      // 2. Try official YouTube Data API v3 playlist sync
      if (this.youtubeService.hasApiKey()) {
        try {
          await this.syncViaPlaylistApi(channelId, defaultCategory, options);
          return;
        } catch (err: any) {
          this.logger.warn(
            `YouTube API playlist sync failed for ${channelId}: ${err.message}. Falling back to web scraper...`,
          );
        }
      }

      // 3. Fallback: Web Scraper & Atom RSS sync
      await this.syncViaWebScraper(channelId, defaultCategory, options);
    } finally {
      await this.cache?.invalidate('videos', 'channels');
    }
  }

  /**
   * Syncs videos using the YouTube Data API v3 Uploads playlist (UU...)
   */
  private async syncViaPlaylistApi(
    channelId: string,
    defaultCategory?: string | null,
    options: { full?: boolean } = {},
  ) {
    const channel = await this.prisma.channel.findUnique({
      where: { id: channelId },
    });
    if (!channel) return;

    const uploadsPlaylistId = channelId.startsWith('UC')
      ? `UU${channelId.substring(2)}`
      : channelId;

    const isIncremental = !options.full && channel.syncStatus === 'COMPLETED' && !channel.syncCursor;
    let pageToken: string | undefined = (channel as any).syncCursor || undefined;
    let batchesProcessed = 0;
    let totalSyncedInRun = 0;
    const syncedForVector: any[] = [];
    const maxBatches = 500; // Ingests up to 25,000 videos continuously

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

      const existingIds = isIncremental
        ? new Set(
            (
              await this.prisma.video.findMany({
                where: { id: { in: videoIds } },
                select: { id: true },
              })
            ).map((v) => v.id),
          )
        : new Set<string>();

      const visibilityMap = await this.youtubeService.verifyVideosVisibility(videoIds, {
        allowShortsOAuth: true,
        expectedChannelId: channelId,
      });

      for (const it of items) {
        const videoId = it.contentDetails?.videoId || it.snippet?.resourceId?.videoId;
        if (!videoId) continue;

        try {
          const visibility = visibilityMap.get(videoId);
          if (!visibility) continue;

          if (visibility.status === 'private') {
            await this.removeConfirmedPrivateVideo(videoId);
            continue;
          }

          if (visibility.status !== 'eligible' || !visibility.item) {
            continue;
          }

          const detail = visibility.item;
          // Do not sync upcoming or active broadcasts as ordinary videos. They
          // can be reconsidered after YouTube marks them as regular VODs.
          if (isActiveOrUpcomingBroadcast(detail)) continue;

          const snippet = detail.snippet;
          if (!snippet) continue;
          const contentDetails = detail.contentDetails;
          const stats = detail.statistics;

          const duration = this.youtubeService.parseIsoDuration(contentDetails?.duration || '');
          const durationSeconds = this.youtubeService.parseIsoDurationSeconds(contentDetails?.duration || '');
          const title = snippet?.title || 'Video';
          const titleLower = title.toLowerCase();
          const description = snippet?.description || '';
          const descLower = description.toLowerCase();
          const hasShortsTag = titleLower.includes('#short') || descLower.includes('#short');
          const isSong = isSongChannel(channel.name, channel.category);
          const isShort = isSong ? hasShortsTag : ((durationSeconds > 0 && durationSeconds <= 180) || hasShortsTag);
          const videoType = isShort ? 'SHORT' : 'VIDEO';
          const videoCategory = isSong ? 'Songs' : (defaultCategory || channel.category || 'General');
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

          const videoMetadata = extractVideoMetadata({
            title,
            description,
            channelTitle: snippet?.channelTitle || channel.name,
            tags,
          });

          const saved = await this.prisma.video.upsert({
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
              category: videoCategory,
              metadata: videoMetadata as any,
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
              category: videoCategory,
              metadata: videoMetadata as any,
              creatorName: parsedMeta?.creatorName || null,
              creatorEmail: parsedMeta?.creatorEmail || null,
              sourceVideoId: parsedMeta?.sourceVideoId || null,
              clipStartTime: parsedMeta?.startTime != null ? Number(parsedMeta.startTime) : null,
              clipEndTime: parsedMeta?.endTime != null ? Number(parsedMeta.endTime) : null,
              clippedAt: parsedMeta ? new Date() : null,
            },
          });
          this.adminAudioProcessor
            ?.enqueuePendingVideo({
              id: videoId,
              title,
              channelName: snippet?.channelTitle || channel.name,
              channelId,
              publishedAt,
              duration,
              thumbnail: thumb,
              type: videoType,
            })
            .catch(() => {});
          syncedForVector.push(saved);
          totalSyncedInRun++;
        } catch (videoErr: any) {
          this.logger.warn(`Skipping video ${videoId} in ${channelId}: ${videoErr.message}`);
        }
      }

      // During incremental sync, stop once an entire batch already exists in DB
      if (isIncremental && videoIds.length > 0 && videoIds.every((id) => existingIds.has(id))) {
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

    this.queueVectorUpsert(syncedForVector);
    this.logger.log(
      `✅ Synced ${totalSyncedInRun} videos in ${batchesProcessed} batch(es) for ${channel.name} (${channelId})`,
    );
  }

  /**
   * Syncs videos via public YouTube HTML pagination + Atom RSS feed fallback.
   * Streams each fetched page directly to PostgreSQL so partial progress is preserved on failures.
   */
  private async syncViaWebScraper(
    channelId: string,
    defaultCategory?: string | null,
    options: { full?: boolean; maxBatches?: number } = {},
  ) {
    const channel = await this.prisma.channel.findUnique({
      where: { id: channelId },
    });
    if (!channel) return;

    const isIncremental = !options.full && channel.syncStatus === 'COMPLETED' && !channel.syncCursor;
    const maxBatches = options.maxBatches ?? 500;
    const syncedForVector: any[] = [];
    let syncedCount = 0;

    // 1. Initial RSS feed sync (latest 15 videos)
    const rssVideos = await this.youtubeService.scrapeRssFeed(channelId);
    for (const v of rssVideos) {
      try {
        syncedForVector.push(await this.upsertScrapedVideo(v, channel, defaultCategory));
        syncedCount++;
      } catch (err: any) {
        this.logger.warn(`RSS upsert failed for ${v.videoId}: ${err.message}`);
      }
    }

    const createPageHandler = (overrideType?: 'VIDEO' | 'SHORT') => {
      return async (pageVideos: ExtractedVideo[]): Promise<boolean> => {
        if (!pageVideos.length) return true;

        const pageIds = pageVideos.map((v) => v.videoId).filter(Boolean);
        const existingIds = isIncremental
          ? new Set(
              (
                await this.prisma.video.findMany({
                  where: { id: { in: pageIds } },
                  select: { id: true },
                })
              ).map((v) => v.id),
            )
          : new Set<string>();

        for (const v of pageVideos) {
          try {
            const payload = overrideType ? { ...v, videoType: overrideType } : v;
            syncedForVector.push(await this.upsertScrapedVideo(payload, channel, defaultCategory));
            syncedCount++;
          } catch (err: any) {
            this.logger.warn(`Scraped video upsert failed for ${v.videoId}: ${err.message}`);
          }
        }

        if (isIncremental && pageIds.length > 0 && pageIds.every((id) => existingIds.has(id))) {
          return false;
        }
        return true;
      };
    };

    // 2. Multi-batch HTML channel /videos tab scraping (persisted page-by-page)
    const videosRes = await this.youtubeService.scrapeChannelVideosTab(channelId, {
      maxBatches,
      onPage: createPageHandler(),
    });

    // Do not scrape the /streams tab here: without YouTube API metadata it
    // mixes upcoming/live events with completed broadcasts. Completed archives
    // can enter through the /videos tab once YouTube publishes them as VODs.

    // 4. Multi-batch HTML channel /shorts tab scraping
    const isSong = isSongChannel(channel.name, channel.category);
    const shortsRes = await this.youtubeService.scrapeChannelShortsTab(channelId, {
      maxBatches,
      onPage: createPageHandler(isSong ? 'VIDEO' : 'SHORT'),
    });

    const allTabsComplete =
      (videosRes.exhausted || videosRes.stoppedEarly) &&
      (shortsRes.exhausted || shortsRes.stoppedEarly);

    this.queueVectorUpsert(syncedForVector);

    await this.prisma.channel.update({
      where: { id: channelId },
      data: {
        lastSyncedAt: new Date(),
        syncStatus: allTabsComplete ? 'COMPLETED' : 'PARTIAL',
        ...(allTabsComplete ? { syncCursor: null } : {}),
      },
    });

    this.logger.log(
      `✅ Synced total ${syncedCount} videos and shorts via web scraper for ${channel.name} (${channelId}) [status=${allTabsComplete ? 'COMPLETED' : 'PARTIAL'}]`,
    );
  }

  /**
   * Helper to upsert a scraped video into PostgreSQL
   */
  private async upsertScrapedVideo(v: ExtractedVideo, channel: any, defaultCategory?: string | null) {
    const normalizedTitle = (v.title || '').trim().toLowerCase();
    if (normalizedTitle === 'private video' || normalizedTitle === '[private video]') {
      return;
    }

    // HTML/RSS fallback sources do not reliably expose broadcast state. Treat
    // entries without a resolved duration as unknown and retry them on a later
    // sync instead of storing live/scheduled broadcasts as 0:00 videos.
    if (!v.durationSeconds || v.durationSeconds <= 0) {
      this.logger.debug(
        `Skipping video ${v.videoId}: duration/broadcast state is unresolved`,
      );
      return;
    }

    const isSong = isSongChannel(channel.name, channel.category);
    const hasShortsTag = v.title.toLowerCase().includes('#short');
    const finalType = isSong ? (hasShortsTag ? 'SHORT' : 'VIDEO') : v.videoType;
    const finalCategory = isSong ? 'Songs' : (defaultCategory || channel.category || 'General');

    const videoMetadata = extractVideoMetadata({
      title: v.title,
      description: '',
      channelTitle: channel.name,
    });

    const saved = await this.prisma.video.upsert({
      where: { id: v.videoId },
      update: {
        type: finalType,
        title: v.title,
        thumbnail: v.thumbnail,
        duration: v.duration && v.duration !== '0:00' ? v.duration : undefined,
        viewCount: v.viewCount && v.viewCount > 0 ? v.viewCount : undefined,
        channelName: channel.name,
        channelThumbnail: channel.thumbnail,
        channelSubscriberCount: channel.subscriberCount,
        category: finalCategory,
        metadata: videoMetadata as any,
      },
      create: {
        id: v.videoId,
        type: finalType,
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
        category: finalCategory,
        metadata: videoMetadata as any,
      },
    });
    return saved;
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
    if (!this.isSyncEnabled()) {
      return;
    }
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
    if (!this.isSyncEnabled()) {
      this.logger.log('WebSub push ignored (YOUTUBE_SYNC_ENABLED=false).');
      return;
    }
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

      this.logger.log(`⚡ Live WebSub video push event: ${videoId} on channel ${channelId}`);

      const channel = await this.prisma.channel.findUnique({ where: { id: channelId } });
      const channelName = channel?.name || 'Channel';
      const channelThumb = channel?.thumbnail || null;
      const category = channel?.category || 'General';

      const visibilityMap = await this.youtubeService.verifyVideosVisibility([videoId], {
        allowShortsOAuth: true,
        expectedChannelId: channelId,
      });
      const visibility = visibilityMap.get(videoId);

      if (visibility?.status === 'private') {
        await this.removeConfirmedPrivateVideo(videoId);
        return;
      }

      if (!visibility || visibility.status !== 'eligible' || !visibility.item) {
        this.logger.warn(
          `Skipping WebSub video ${videoId} (visibility: ${visibility?.status || 'unknown'})`,
        );
        return;
      }

      const item = visibility.item;
      if (isActiveOrUpcomingBroadcast(item)) {
        this.logger.log(
          `Skipping WebSub broadcast ${videoId}: ${item.snippet?.liveBroadcastContent}`,
        );
        return;
      }

      const snippet = item.snippet;
      const contentDetails = item.contentDetails;
      const stats = item.statistics;

      const duration = this.youtubeService.parseIsoDuration(contentDetails?.duration || '');
      const durationSeconds = this.youtubeService.parseIsoDurationSeconds(contentDetails?.duration || '');
      const hasShortsTag = (snippet?.title || '').toLowerCase().includes('#short') ||
                           (snippet?.description || '').toLowerCase().includes('#short');
      const isSong = isSongChannel(channel?.name, channel?.category);
      const isShort = isSong ? hasShortsTag : ((durationSeconds > 0 && durationSeconds <= 180) || hasShortsTag);
      const videoType = isShort ? 'SHORT' : 'VIDEO';
      const finalCategory = isSong ? 'Songs' : (channel?.category || 'General');
      const thumb =
        snippet?.thumbnails?.maxres?.url ||
        snippet?.thumbnails?.high?.url ||
        snippet?.thumbnails?.medium?.url ||
        `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;

      const videoMetadata = extractVideoMetadata({
        title: snippet?.title || title,
        description: snippet?.description || '',
        channelTitle: snippet?.channelTitle || channelName,
      });

      const saved = await this.prisma.video.upsert({
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
          category: finalCategory,
          metadata: videoMetadata as any,
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
          metadata: videoMetadata as any,
        },
      });
      this.queueVectorUpsert([saved]);
      this.logger.log(`✅ Live synced new video ${videoId} via WebSub push`);
      await this.cache?.invalidate('videos', 'channels', 'video-search');
      this.adminAudioProcessor
        ?.enqueuePendingVideo({
          id: saved.id,
          title: saved.title,
          channelName: saved.channelName,
          channelId: saved.channelId,
          publishedAt: saved.publishedAt,
          duration: saved.duration,
          thumbnail: saved.thumbnail,
          audioUrl: saved.audioUrl,
          type: saved.type,
        })
        .catch(() => {});
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
        select: { id: true, channelName: true },
      });

      if (!videos.length) return;

      this.logger.log(`Starting metadata backfill for ${videos.length} videos...`);
      const videoIds = videos.map((v) => v.id);
      const updatedForVector: any[] = [];

      for (let i = 0; i < videoIds.length; i += 50) {
        const chunk = videoIds.slice(i, i + 50);
        const visibilityMap = await this.youtubeService.verifyVideosVisibility(chunk);

        for (const [id, visibility] of visibilityMap.entries()) {
          if (visibility.status === 'private') {
            await this.removeConfirmedPrivateVideo(id);
            continue;
          }
          if (visibility.status !== 'eligible' || !visibility.item) {
            continue;
          }
          const item = visibility.item;
          const vObj = videos.find((v) => v.id === id);
          const isSong = isSongChannel(vObj?.channelName);
          const contentDetails = item.contentDetails;
          const stats = item.statistics;
          const duration = this.youtubeService.parseIsoDuration(contentDetails?.duration || '');
          const durationSeconds = this.youtubeService.parseIsoDurationSeconds(contentDetails?.duration || '');
          const hasShortsTag = (item.snippet?.title || '').toLowerCase().includes('#short') ||
                               (item.snippet?.description || '').toLowerCase().includes('#short');
          const isShort = isSong ? hasShortsTag : (durationSeconds > 0 && durationSeconds <= 180 || hasShortsTag);

          const updated = await this.prisma.video.update({
            where: { id },
            data: {
              duration: duration !== '0:00' ? duration : undefined,
              viewCount: stats?.viewCount ? parseInt(stats.viewCount, 10) : undefined,
              type: isShort ? 'SHORT' : (isSong ? 'VIDEO' : undefined),
              category: isSong ? 'Songs' : undefined,
            },
          });
          if (isShort || isSong) {
            updatedForVector.push(updated);
          }
        }
        await this.sleep(100);
      }
      this.queueVectorUpsert(updatedForVector);
      this.logger.log(`✅ Metadata backfill completed for ${videos.length} videos.`);
      await this.cache?.invalidate('videos', 'video-search');
    } catch (e: any) {
      this.logger.warn(`Video metadata backfill error: ${e.message}`);
    }
  }

  async syncSingleVideo(videoId: string, force = false) {
    if (!force && !this.isSyncEnabled()) {
      this.logger.log(`YouTube sync disabled; skipping syncSingleVideo(${videoId}).`);
      return null;
    }
    this.logger.log(`Directly syncing video from YouTube: ${videoId}`);
    const existing = await this.prisma.video.findUnique({
      where: { id: videoId },
      select: { channelId: true },
    });
    const customChannelId = this.configService.get<string>('shorts.customChannelId');
    const visibilityMap = await this.youtubeService.verifyVideosVisibility([videoId], {
      allowShortsOAuth: true,
      expectedChannelId: existing?.channelId || customChannelId || undefined,
    });
    const visibility = visibilityMap.get(videoId);

    if (visibility?.status === 'private') {
      await this.removeConfirmedPrivateVideo(videoId);
      return null;
    }

    if (!visibility || visibility.status !== 'eligible' || !visibility.item) {
      this.logger.warn(
        `Skipping single video sync for ${videoId} (visibility: ${visibility?.status || 'unknown'})`,
      );
      return null;
    }

    const item = visibility.item;
    if (isActiveOrUpcomingBroadcast(item)) {
      this.logger.log(
        `Skipping direct video sync for ${videoId}: ${item.snippet?.liveBroadcastContent}`,
      );
      return null;
    }
    const snippet = item.snippet;
    const contentDetails = item.contentDetails;
    const stats = item.statistics;
    const title = snippet?.title || 'Christian Short';
    const description = snippet?.description || '';
    const channelId = snippet?.channelId || 'UCSaJppP4zb2vivjxYfTqOKw';
    const channelName = snippet?.channelTitle || 'ChristianApp';
    const isSong = isSongChannel(channelName);
    const publishedAt = snippet?.publishedAt ? new Date(snippet.publishedAt) : new Date();
    const duration = this.youtubeService.parseIsoDuration(contentDetails?.duration || 'PT60S');
    const durationSeconds = this.youtubeService.parseIsoDurationSeconds(contentDetails?.duration || 'PT60S');
    const hasShortsTag = title.toLowerCase().includes('#short') || description.toLowerCase().includes('#short');
    const isShort = isSong ? hasShortsTag : ((durationSeconds > 0 && durationSeconds <= 180) || hasShortsTag);
    const finalCategory = isSong ? 'Songs' : 'General';
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

    const videoMetadata = extractVideoMetadata({
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
        category: finalCategory,
        publishedAt,
        duration,
        viewCount: stats?.viewCount ? parseInt(stats.viewCount, 10) : 0,
        metadata: videoMetadata as any,
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
        metadata: videoMetadata as any,
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
    this.queueVectorUpsert([saved]);

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
    await this.cache?.invalidate('videos', 'channels');
    return saved;
  }
}
