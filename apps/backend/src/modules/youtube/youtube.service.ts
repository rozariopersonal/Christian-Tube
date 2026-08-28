import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron, CronExpression } from '@nestjs/schedule';
import axios from 'axios';
import { PrismaService } from '../prisma/prisma.service';

function parseIsoDurationSeconds(duration: string): number {
  if (!duration) return 0;
  const match = duration.match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/);
  if (!match) return 0;
  const hours = parseInt(match[1] || '0', 10);
  const minutes = parseInt(match[2] || '0', 10);
  const seconds = parseInt(match[3] || '0', 10);
  return hours * 3600 + minutes * 60 + seconds;
}

function parseIsoDuration(duration: string): string {
  if (!duration) return '0:00';
  const match = duration.match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/);
  if (!match) return '0:00';
  const hours = parseInt(match[1] || '0', 10);
  const minutes = parseInt(match[2] || '0', 10);
  const seconds = parseInt(match[3] || '0', 10);

  const secStr = seconds.toString().padStart(2, '0');
  if (hours > 0) {
    const minStr = minutes.toString().padStart(2, '0');
    return `${hours}:${minStr}:${secStr}`;
  }
  return `${minutes}:${secStr}`;
}

function parseTextDurationToSeconds(text: string): number {
  if (!text) return 0;
  const parts = text.trim().split(':').map((p) => parseInt(p, 10));
  if (parts.length === 3) {
    return (parts[0] || 0) * 3600 + (parts[1] || 0) * 60 + (parts[2] || 0);
  }
  if (parts.length === 2) {
    return (parts[0] || 0) * 60 + (parts[1] || 0);
  }
  return 0;
}

function isIstDaytime(): boolean {
  const now = new Date();
  // IST offset: UTC+5:30 (+330 minutes)
  const totalIstMinutes = now.getUTCHours() * 60 + now.getUTCMinutes() + 330;
  const istHour = Math.floor((totalIstMinutes / 60) % 24);
  // Daytime in IST: 6:00 AM to 10:00 PM
  return istHour >= 6 && istHour <= 22;
}

function parseRelativeTimeToDate(text: string): Date | null {
  if (!text || typeof text !== 'string') return null;
  const str = text
    .toLowerCase()
    .replace('streamed', '')
    .replace('premiered', '')
    .replace('live stream', '')
    .replace('scheduled', '')
    .trim();
  const now = Date.now();

  if (str === 'yesterday') {
    return new Date(now - 86400 * 1000);
  }

  const match = str.match(/(\d+)\s+(second|minute|hour|day|week|month|year)s?\s+ago/i);
  if (!match) return null;

  const count = parseInt(match[1], 10);
  const unit = match[2].toLowerCase();

  switch (unit) {
    case 'second':
      return new Date(now - count * 1000);
    case 'minute':
      return new Date(now - count * 60 * 1000);
    case 'hour':
      return new Date(now - count * 3600 * 1000);
    case 'day':
      return new Date(now - count * 86400 * 1000);
    case 'week':
      return new Date(now - count * 7 * 86400 * 1000);
    case 'month':
      return new Date(now - count * 30 * 86400 * 1000);
    case 'year':
      return new Date(now - count * 365 * 86400 * 1000);
    default:
      return null;
  }
}

function parseViewsTextToNumber(text: string): number {
  if (!text || typeof text !== 'string') return 0;
  const clean = text
    .toLowerCase()
    .replace(/views?/g, '')
    .replace(/watching/g, '')
    .trim();
  if (!clean || clean === 'no') return 0;

  if (clean.endsWith('b')) {
    const val = parseFloat(clean.slice(0, -1).trim());
    return isNaN(val) ? 0 : Math.round(val * 1000000000);
  }
  if (clean.endsWith('m')) {
    const val = parseFloat(clean.slice(0, -1).trim());
    return isNaN(val) ? 0 : Math.round(val * 1000000);
  }
  if (clean.endsWith('k')) {
    const val = parseFloat(clean.slice(0, -1).trim());
    return isNaN(val) ? 0 : Math.round(val * 1000);
  }
  const digits = clean.replace(/[^0-9]/g, '');
  return digits ? parseInt(digits, 10) : 0;
}

function formatSecondsToDuration(totalSeconds: number): string {
  if (!totalSeconds || isNaN(totalSeconds) || totalSeconds <= 0) return '0:00';
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  const secStr = seconds.toString().padStart(2, '0');
  if (hours > 0) {
    const minStr = minutes.toString().padStart(2, '0');
    return `${hours}:${minStr}:${secStr}`;
  }
  return `${minutes}:${secStr}`;
}

interface ExtractedVideo {
  videoId: string;
  title: string;
  thumbnail: string;
  duration: string;
  durationSeconds: number;
  viewCount: number;
  publishedAt?: Date;
  videoType: 'VIDEO' | 'SHORT';
}

function extractVideosFromRichContents(contents: any[]): { videos: ExtractedVideo[]; nextContinuationToken?: string } {
  const videos: ExtractedVideo[] = [];
  let nextContinuationToken: string | undefined;

  for (const item of contents) {
    if (item.continuationItemRenderer) {
      const token =
        item.continuationItemRenderer?.continuationEndpoint?.continuationCommand?.token ||
        item.continuationItemRenderer?.continuationCommand?.token;
      if (token) nextContinuationToken = token;
      continue;
    }

    const content = item.richItemRenderer?.content || item;

    // 1. Modern lockupViewModel (2024+ YouTube channel videos grid)
    if (content.lockupViewModel) {
      const vm = content.lockupViewModel;
      const videoId =
        vm.contentId ||
        vm.rendererContext?.commandContext?.onTap?.innertubeCommand?.watchEndpoint?.videoId;
      if (!videoId) continue;

      const title =
        vm.metadata?.lockupMetadataViewModel?.title?.content ||
        vm.rendererContext?.accessibilityContext?.label ||
        'Video';

      // Extract duration from overlay badge
      const overlays = vm.contentImage?.thumbnailViewModel?.overlays || [];
      let durationText = '';
      for (const ov of overlays) {
        const badges = ov?.thumbnailBottomOverlayViewModel?.badges;
        const badgeList = Array.isArray(badges) ? badges : [badges];
        for (const b of badgeList) {
          const t = b?.thumbnailBadgeViewModel?.text;
          if (t && typeof t === 'string' && t.includes(':')) {
            durationText = t.trim();
            break;
          }
        }
        if (durationText) break;
      }

      const durationSeconds = parseTextDurationToSeconds(durationText);
      const duration = durationText || '0:00';
      const titleLower = title.toLowerCase();
      const hasShortsTag = titleLower.includes('#short');
      const isShort =
        vm.contentType === 'LOCKUP_CONTENT_TYPE_SHORTS' ||
        (durationSeconds > 0 && durationSeconds <= 60) ||
        hasShortsTag;
      const videoType: 'VIDEO' | 'SHORT' = isShort ? 'SHORT' : 'VIDEO';

      // Extract view count & published date from metadata rows
      let viewCount = 0;
      let publishedAt: Date | undefined;

      const metaRows =
        vm.metadata?.lockupMetadataViewModel?.metadata?.contentMetadataViewModel?.metadataRows ||
        vm.metadata?.lockupMetadataViewModel?.metadataRows ||
        [];

      for (const row of metaRows) {
        const parts = row?.metadataParts || [];
        for (const p of parts) {
          const t = p?.text?.content || p?.accessibilityLabel || '';
          if (!t || typeof t !== 'string') continue;
          const lower = t.toLowerCase();
          if (!viewCount && (lower.includes('view') || /^\d+(\.\d+)?[kmb]?$/i.test(lower.trim()))) {
            viewCount = parseViewsTextToNumber(t);
          }
          if (!publishedAt && (lower.includes('ago') || lower === 'yesterday')) {
            const parsed = parseRelativeTimeToDate(t);
            if (parsed) publishedAt = parsed;
          }
        }
      }

      // Accessibility context fallback
      const a11yLabel =
        vm.rendererContext?.accessibilityContext?.label ||
        vm.metadata?.lockupMetadataViewModel?.title?.accessibility?.accessibilityData?.label ||
        '';
      if (a11yLabel && typeof a11yLabel === 'string') {
        if (!viewCount && a11yLabel.toLowerCase().includes('view')) {
          const vMatch = a11yLabel.match(/([\d,\.]+\s*[kKmMbB]?)\s+views?/i);
          if (vMatch) viewCount = parseViewsTextToNumber(vMatch[0]);
        }
        if (!publishedAt && a11yLabel.toLowerCase().includes('ago')) {
          const dMatch = a11yLabel.match(/(\d+\s+(?:second|minute|hour|day|week|month|year)s?\s+ago)/i);
          if (dMatch) publishedAt = parseRelativeTimeToDate(dMatch[1]);
        }
      }

      const thumbSources = vm.contentImage?.thumbnailViewModel?.image?.sources || [];
      const thumb =
        thumbSources[thumbSources.length - 1]?.url ||
        `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;

      videos.push({
        videoId,
        title,
        thumbnail: thumb,
        duration,
        durationSeconds,
        viewCount,
        publishedAt,
        videoType,
      });
      continue;
    }

    // 2. Modern shortsLockupViewModel (YouTube Shorts grid)
    if (content.shortsLockupViewModel) {
      const vm = content.shortsLockupViewModel;
      const videoId =
        vm.onTap?.innertubeCommand?.reelWatchEndpoint?.videoId ||
        (typeof vm.entityId === 'string' ? vm.entityId.replace('shorts-shelf-item-', '') : null);
      if (!videoId) continue;

      const title = vm.overlayMetadata?.primaryText?.content || 'Short';
      const thumbSources = vm.thumbnail?.sources || [];
      const thumb =
        thumbSources[thumbSources.length - 1]?.url ||
        `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;

      let viewCount = 0;
      const secText = vm.overlayMetadata?.secondaryText?.content || '';
      if (secText) {
        viewCount = parseViewsTextToNumber(secText);
      } else if (vm.accessibilityText) {
        viewCount = parseViewsTextToNumber(vm.accessibilityText);
      }

      videos.push({
        videoId,
        title,
        thumbnail: thumb,
        duration: '0:30',
        durationSeconds: 30,
        viewCount,
        videoType: 'SHORT',
      });
      continue;
    }

    // 3. Legacy videoRenderer / gridVideoRenderer
    const renderer = content.videoRenderer || content.gridVideoRenderer;
    if (renderer && renderer.videoId) {
      const videoId = renderer.videoId;
      const title =
        renderer.title?.runs?.map((r: any) => r.text).join('') ||
        renderer.title?.simpleText ||
        'Video';
      const durationText =
        renderer.lengthText?.simpleText ||
        renderer.thumbnailOverlays?.find((o: any) => o.thumbnailOverlayTimeStatusRenderer)
          ?.thumbnailOverlayTimeStatusRenderer?.text?.simpleText ||
        '';
      const durationSeconds = parseTextDurationToSeconds(durationText);
      const duration = durationText.trim() || '0:00';
      const titleLower = title.toLowerCase();
      const hasShortsTag = titleLower.includes('#short');
      const isShort = (durationSeconds > 0 && durationSeconds <= 60) || hasShortsTag;
      const videoType: 'VIDEO' | 'SHORT' = isShort ? 'SHORT' : 'VIDEO';
      const thumb =
        renderer.thumbnail?.thumbnails?.slice(-1)[0]?.url ||
        `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;
      const viewCountText =
        renderer.viewCountText?.simpleText ||
        renderer.viewCountText?.runs?.map((r: any) => r.text).join('') ||
        renderer.shortViewCountText?.simpleText ||
        '';
      const viewCount = parseViewsTextToNumber(viewCountText);

      const publishedTimeText =
        renderer.publishedTimeText?.simpleText ||
        renderer.publishedTimeText?.runs?.map((r: any) => r.text).join('') ||
        '';
      const publishedAt = publishedTimeText ? parseRelativeTimeToDate(publishedTimeText) : undefined;

      videos.push({
        videoId,
        title,
        thumbnail: thumb,
        duration,
        durationSeconds,
        viewCount,
        publishedAt: publishedAt || undefined,
        videoType,
      });
    }
  }

  return { videos, nextContinuationToken };
}

@Injectable()
export class YoutubeService implements OnModuleInit {
  private readonly logger = new Logger(YoutubeService.name);
  private apiKey: string;
  private isSyncing = false;

  constructor(
    private readonly configService: ConfigService,
    private readonly prisma: PrismaService,
  ) {
    this.apiKey = this.configService.get<string>('youtubeApiKey') || '';
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  async onModuleInit() {
    setTimeout(async () => {
      // 1. Subscribe all active channels to Google WebSub Hub
      this.renewAllWebSubSubscriptions().catch((e) => {
        this.logger.warn(`Initial WebSub subscription error on boot: ${e.message}`);
      });

      // 2. Launch continuous deep sync on boot (runs till end of all playlists)
      this.syncAllChannelsPeriodically().catch((e) => {
        this.logger.warn(`Initial automated sync on boot error: ${e.message}`);
      });

      // 3. Backfill missing durations & stats
      this.backfillVideoMetadata(500).catch((e) => {
        this.logger.warn(`Initial automated backfill on boot error: ${e.message}`);
      });
    }, 3000);
  }

  /**
   * Periodic scheduler: Runs every 2 hours to sync new sermon uploads and continue pagination
   */
  @Cron(CronExpression.EVERY_2_HOURS)
  async syncAllChannelsPeriodically() {
    if (this.isSyncing) {
      this.logger.log('Previous channel sync cycle is still active. Skipping concurrent run.');
      return;
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

      if (!channels.length) return;

      this.logger.log(`🔄 Starting infinite continuous video & metadata sync for ${channels.length} channels...`);

      for (const channel of channels) {
        try {
          await this.syncChannelVideos(channel.id, channel.category);
        } catch (err: any) {
          this.logger.error(`Error syncing channel ${channel.name} (${channel.id}): ${err.message}`);
        }
        await this.sleep(300);
      }
    } finally {
      this.isSyncing = false;
    }
  }

  async syncAllChannels() {
    return this.syncAllChannelsPeriodically();
  }

  /**
   * Subscribe a channel to Google WebSub Hub for instant real-time push notifications
   */
  async subscribeChannelToWebSub(channelId: string, mode: 'subscribe' | 'unsubscribe' = 'subscribe') {
    try {
      const apiBaseUrl = this.configService.get<string>('apiBaseUrl') || 'https://christianapp-zjdh.onrender.com';
      const callbackUrl = `${apiBaseUrl.replace(/\/$/, '')}/youtube/webhook`;
      const topicUrl = `https://www.youtube.com/xml/feeds/videos.xml?channel_id=${channelId}`;

      const params = new URLSearchParams({
        'hub.callback': callbackUrl,
        'hub.mode': mode,
        'hub.topic': topicUrl,
        'hub.lease_seconds': '864000', // 10 days
      });

      const res = await axios.post('https://pubsubhubbub.appspot.com/subscribe', params.toString(), {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        timeout: 10000,
      });

      this.logger.log(`Google WebSub ${mode} request submitted for channel ${channelId} (Status: ${res.status})`);
      return true;
    } catch (err: any) {
      this.logger.warn(`Google WebSub ${mode} error for channel ${channelId}: ${err.message}`);
      return false;
    }
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

      this.logger.log(`⚡ Live WebSub video publish event received: "${title}" (${videoId}) on channel ${channelId}`);

      const channel = await this.prisma.channel.findUnique({ where: { id: channelId } });
      const channelName = channel?.name || 'Channel';
      const channelThumb = channel?.thumbnail || null;
      const category = channel?.category || 'General';

      if (this.apiKey) {
        try {
          const detailsUrl = `https://www.googleapis.com/youtube/v3/videos?key=${this.apiKey}&id=${videoId}&part=snippet,contentDetails,statistics`;
          const detailsRes = await axios.get(detailsUrl, { timeout: 10000 });
          const item = detailsRes.data?.items?.[0];

          if (item) {
            const snippet = item.snippet;
            const contentDetails = item.contentDetails;
            const stats = item.statistics;

            const duration = parseIsoDuration(contentDetails?.duration || '');
            const durationSeconds = parseIsoDurationSeconds(contentDetails?.duration || '');
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
   * Refresh channel metadata: avatar, title, description, subscriber count
   */
  async refreshChannelMetadata(channelId: string) {
    try {
      if (this.apiKey) {
        const url = `https://www.googleapis.com/youtube/v3/channels?key=${this.apiKey}&id=${encodeURIComponent(channelId)}&part=snippet,statistics`;
        const res = await axios.get(url, { timeout: 8000 });
        const items = res.data?.items || [];
        if (items.length > 0) {
          const item = items[0];
          const snippet = item.snippet;
          const stats = item.statistics;

          const thumbnail =
            snippet?.thumbnails?.high?.url ||
            snippet?.thumbnails?.medium?.url ||
            snippet?.thumbnails?.default?.url;
          const description = snippet?.description || null;
          const subscriberCount = stats?.subscriberCount ? String(stats.subscriberCount) : null;
          const title = snippet?.title;

          return await this.prisma.channel.update({
            where: { id: channelId },
            data: {
              name: title || undefined,
              thumbnail: thumbnail || undefined,
              description: description || undefined,
              subscriberCount: subscriberCount || undefined,
            },
          });
        }
      }

      // Web Scraper metadata fallback
      const targetUrl = `https://www.youtube.com/channel/${encodeURIComponent(channelId)}`;
      const res = await axios.get(targetUrl, {
        headers: {
          'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept-Language': 'en-US,en;q=0.9',
        },
        timeout: 10000,
      });

      const html = res.data;
      if (typeof html === 'string') {
        const titleMatch =
          html.match(/<meta\s+property="og:title"\s+content="([^"]+)"/i) ||
          html.match(/<title>([^<]+)<\/title>/i);
        const title = titleMatch ? titleMatch[1].replace(' - YouTube', '').trim() : undefined;

        const thumbMatch =
          html.match(/<meta\s+property="og:image"\s+content="([^"]+)"/i) ||
          html.match(/"avatar":{"thumbnails":\[{"url":"([^"]+)"/i);
        const thumbnail = thumbMatch ? thumbMatch[1] : undefined;

        const descMatch =
          html.match(/<meta\s+property="og:description"\s+content="([^"]+)"/i) ||
          html.match(/<meta\s+name="description"\s+content="([^"]+)"/i);
        const description = descMatch ? descMatch[1] : undefined;

        return await this.prisma.channel.update({
          where: { id: channelId },
          data: {
            name: title,
            thumbnail: thumbnail,
            description: description,
          },
        });
      }
    } catch (e: any) {
      this.logger.warn(`Could not refresh channel metadata for ${channelId}: ${e.message}`);
    }
  }

  /**
   * Syncs videos for a channel in continuous batches with full pagination
   */
  async syncChannelVideos(channelId: string, defaultCategory?: string | null, maxBatches = 50) {
    // 1. Sync & update channel metadata first
    await this.refreshChannelMetadata(channelId);

    // 2. Try YouTube Data API playlist sync
    if (this.apiKey) {
      try {
        await this.syncViaPlaylistApi(channelId, defaultCategory, maxBatches);
        return;
      } catch (err: any) {
        this.logger.warn(
          `YouTube API playlist batch sync failed for ${channelId}: ${err.message}. Falling back to web scraper sync...`,
        );
      }
    }

    // 3. Fallback: Continuous web scraper pagination & Atom RSS sync
    await this.syncViaWebScraper(channelId, defaultCategory, maxBatches);
  }

  /**
   * Syncs videos using the YouTube Data API v3 Uploads playlist (UU...)
   */
  private async syncViaPlaylistApi(channelId: string, defaultCategory?: string | null, maxBatches = 50) {
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

    while (batchesProcessed < maxBatches) {
      batchesProcessed++;

      const playlistUrl = `https://www.googleapis.com/youtube/v3/playlistItems?key=${this.apiKey}&playlistId=${uploadsPlaylistId}&part=snippet,contentDetails&maxResults=50${pageToken ? `&pageToken=${pageToken}` : ''}`;
      const playlistRes = await axios.get(playlistUrl, { timeout: 10000 });
      const items = playlistRes.data?.items || [];
      const nextPageToken = playlistRes.data?.nextPageToken;

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
        .filter(Boolean)
        .join(',');

      const detailsUrl = `https://www.googleapis.com/youtube/v3/videos?key=${this.apiKey}&id=${videoIds}&part=snippet,contentDetails,statistics`;
      const detailsRes = await axios.get(detailsUrl, { timeout: 10000 });
      const detailMap = new Map<string, any>();
      for (const d of detailsRes.data?.items || []) {
        detailMap.set(d.id, d);
      }

      for (const it of items) {
        const videoId = it.contentDetails?.videoId || it.snippet?.resourceId?.videoId;
        if (!videoId) continue;

        const detail = detailMap.get(videoId);
        const snippet = detail?.snippet || it.snippet;
        const contentDetails = detail?.contentDetails;
        const stats = detail?.statistics;

        const duration = parseIsoDuration(contentDetails?.duration || '');
        const durationSeconds = parseIsoDurationSeconds(contentDetails?.duration || '');
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

      // For already COMPLETED channels during routine checks, stop after Batch 1 delta check
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
        duration: v.duration,
        viewCount: v.viewCount,
        category: defaultCategory || channel.category || 'General',
        transcriptionStatus: 'pending',
      },
    });
  }

  /**
   * Syncs videos and shorts via public YouTube HTML pagination + InnerTube browse continuation API
   * Zero API key or quota required. Ingests all historical uploads in continuous batches.
   */
  private async syncViaWebScraper(channelId: string, defaultCategory?: string | null, maxBatches = 50) {
    const channel = await this.prisma.channel.findUnique({
      where: { id: channelId },
    });
    if (!channel) return;

    let syncedCount = 0;

    // 1. Initial RSS feed sync (latest 15 videos with official timestamps)
    try {
      const feedUrl = `https://www.youtube.com/feeds/videos.xml?channel_id=${channelId}`;
      const res = await axios.get(feedUrl, {
        headers: {
          'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/xml,text/xml,*/*',
        },
        timeout: 10000,
      });

      const xml = res.data;
      if (xml && typeof xml === 'string') {
        const entryMatches = xml.match(/<entry>[\s\S]*?<\/entry>/g) || [];
        for (const entryXml of entryMatches) {
          const videoIdMatch = entryXml.match(/<yt:videoId>([^<]+)<\/yt:videoId>/);
          const videoId = videoIdMatch ? videoIdMatch[1].trim() : null;
          if (!videoId) continue;

          const titleMatch = entryXml.match(/<title>([\s\S]*?)<\/title>/);
          const title = titleMatch ? titleMatch[1].trim() : 'Video';

          const descMatch = entryXml.match(/<media:description>([\s\S]*?)<\/media:description>/);
          const description = descMatch ? descMatch[1].trim() : '';

          const publishedMatch = entryXml.match(/<published>([^<]+)<\/published>/);
          const publishedAt = publishedMatch ? new Date(publishedMatch[1].trim()) : new Date();

          const thumbMatch = entryXml.match(/<media:thumbnail\s+url="([^"]+)"/);
          const thumbnail = thumbMatch
            ? thumbMatch[1]
            : `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;

          const titleLower = title.toLowerCase();
          const descLower = description.toLowerCase();
          const hasShortsTag = titleLower.includes('#short') || descLower.includes('#short');
          const videoType = hasShortsTag ? 'SHORT' : 'VIDEO';

          await this.prisma.video.upsert({
            where: { id: videoId },
            update: {
              type: videoType,
              title,
              description,
              thumbnail,
              publishedAt,
              channelName: channel.name,
              channelThumbnail: channel.thumbnail,
              channelSubscriberCount: channel.subscriberCount,
              category: defaultCategory || channel.category || 'General',
            },
            create: {
              id: videoId,
              type: videoType,
              title,
              description,
              thumbnail,
              channelId,
              channelName: channel.name,
              channelThumbnail: channel.thumbnail,
              channelSubscriberCount: channel.subscriberCount,
              publishedAt,
              duration: '0:00',
              viewCount: 0,
              category: defaultCategory || channel.category || 'General',
              transcriptionStatus: 'pending',
            },
          });
          syncedCount++;
        }
      }
    } catch (e: any) {
      this.logger.warn(`RSS feed sync step for ${channelId}: ${e.message}`);
    }

    // 2. Multi-batch HTML channel /videos tab scraping + InnerTube continuous pagination
    try {
      const videosUrl = `https://www.youtube.com/channel/${channelId}/videos`;
      const res = await axios.get(videosUrl, {
        headers: {
          'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept-Language': 'en-US,en;q=0.9',
        },
        timeout: 10000,
      });

      const html = res.data;
      if (typeof html === 'string') {
        const jsonMatch = html.match(/var ytInitialData = ({[\s\S]*?});<\/script>/);
        if (jsonMatch) {
          const data = JSON.parse(jsonMatch[1]);
          const tabs = data?.contents?.twoColumnBrowseResultsRenderer?.tabs || [];
          const videosTab = tabs.find((t: any) => t.tabRenderer?.title?.toLowerCase() === 'videos');
          const contents =
            videosTab?.tabRenderer?.content?.richGridRenderer?.contents ||
            data?.contents?.twoColumnBrowseResultsRenderer?.tabs?.[1]?.tabRenderer?.content?.sectionListRenderer?.contents?.[0]?.itemSectionRenderer?.contents?.[0]?.gridRenderer?.items ||
            [];

          let { videos, nextContinuationToken } = extractVideosFromRichContents(contents);

          for (const v of videos) {
            await this.upsertScrapedVideo(v, channel, defaultCategory);
            syncedCount++;
          }

          let batch = 1;
          while (nextContinuationToken && batch < maxBatches) {
            batch++;
            try {
              const browseRes = await axios.post(
                'https://www.youtube.com/youtubei/v1/browse',
                {
                  context: {
                    client: {
                      clientName: 'WEB',
                      clientVersion: '2.20240301.00.00',
                    },
                  },
                  continuation: nextContinuationToken,
                },
                {
                  headers: {
                    'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                  },
                  timeout: 10000,
                },
              );

              const actions = browseRes.data?.onResponseReceivedActions || [];
              const continuationItems = actions[0]?.appendContinuationItemsAction?.continuationItems || [];
              const pageResult = extractVideosFromRichContents(continuationItems);

              for (const v of pageResult.videos) {
                await this.upsertScrapedVideo(v, channel, defaultCategory);
                syncedCount++;
              }

              nextContinuationToken = pageResult.nextContinuationToken;
            } catch (pageErr: any) {
              this.logger.warn(`Continuation page ${batch} error for ${channelId}: ${pageErr.message}`);
              break;
            }
          }
        }
      }
    } catch (err: any) {
      this.logger.warn(`Web scraper video pagination error for ${channelId}: ${err.message}`);
    }

    // 3. Multi-batch HTML channel /shorts tab scraping
    try {
      const shortsUrl = `https://www.youtube.com/channel/${channelId}/shorts`;
      const res = await axios.get(shortsUrl, {
        headers: {
          'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept-Language': 'en-US,en;q=0.9',
        },
        timeout: 10000,
      });

      const html = res.data;
      if (typeof html === 'string') {
        const jsonMatch = html.match(/var ytInitialData = ({[\s\S]*?});<\/script>/);
        if (jsonMatch) {
          const data = JSON.parse(jsonMatch[1]);
          const tabs = data?.contents?.twoColumnBrowseResultsRenderer?.tabs || [];
          const shortsTab = tabs.find((t: any) => t.tabRenderer?.title?.toLowerCase() === 'shorts');
          const contents = shortsTab?.tabRenderer?.content?.richGridRenderer?.contents || [];

          let { videos, nextContinuationToken } = extractVideosFromRichContents(contents);

          for (const v of videos) {
            await this.upsertScrapedVideo({ ...v, videoType: 'SHORT' }, channel, defaultCategory);
            syncedCount++;
          }

          let sBatch = 1;
          while (nextContinuationToken && sBatch < 25) {
            sBatch++;
            try {
              const browseRes = await axios.post(
                'https://www.youtube.com/youtubei/v1/browse',
                {
                  context: {
                    client: {
                      clientName: 'WEB',
                      clientVersion: '2.20240301.00.00',
                    },
                  },
                  continuation: nextContinuationToken,
                },
                {
                  headers: {
                    'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                  },
                  timeout: 10000,
                },
              );

              const actions = browseRes.data?.onResponseReceivedActions || [];
              const continuationItems = actions[0]?.appendContinuationItemsAction?.continuationItems || [];
              const pageResult = extractVideosFromRichContents(continuationItems);

              for (const v of pageResult.videos) {
                await this.upsertScrapedVideo({ ...v, videoType: 'SHORT' }, channel, defaultCategory);
                syncedCount++;
              }

              nextContinuationToken = pageResult.nextContinuationToken;
            } catch (pageErr: any) {
              break;
            }
          }
        }
      }
    } catch (err: any) {
      this.logger.warn(`Web scraper shorts pagination error for ${channelId}: ${err.message}`);
    }

    await this.prisma.channel.update({
      where: { id: channelId },
      data: {
        lastSyncedAt: new Date(),
        syncStatus: 'COMPLETED',
      },
    });

    this.logger.log(`✅ Synced total ${syncedCount} videos and shorts via web scraper for ${channel.name} (${channelId})`);
  }

  /**
   * Fetches accurate YouTube metadata for a single video using YouTube Data API or InnerTube WEB player endpoint.
   * Returns exact publishedAt, viewCount, duration, and high-res thumbnail.
   */
  async fetchVideoDetails(videoId: string): Promise<{
    title?: string;
    description?: string;
    duration?: string;
    durationSeconds?: number;
    viewCount?: number;
    publishedAt?: Date;
    thumbnail?: string;
    channelName?: string;
  } | null> {
    if (!videoId) return null;

    // 1. YouTube Data API v3 if key exists
    if (this.apiKey) {
      try {
        const detailsUrl = `https://www.googleapis.com/youtube/v3/videos?key=${this.apiKey}&id=${encodeURIComponent(videoId)}&part=snippet,contentDetails,statistics`;
        const res = await axios.get(detailsUrl, { timeout: 8000 });
        const item = res.data?.items?.[0];
        if (item) {
          const snippet = item.snippet;
          const contentDetails = item.contentDetails;
          const stats = item.statistics;

          const duration = parseIsoDuration(contentDetails?.duration || '');
          const durationSeconds = parseIsoDurationSeconds(contentDetails?.duration || '');
          const viewCount = stats?.viewCount ? parseInt(stats.viewCount, 10) : 0;
          const publishedAt = snippet?.publishedAt ? new Date(snippet.publishedAt) : undefined;
          const thumbnail =
            snippet?.thumbnails?.maxres?.url ||
            snippet?.thumbnails?.high?.url ||
            snippet?.thumbnails?.medium?.url ||
            `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;

          return {
            title: snippet?.title,
            description: snippet?.description,
            duration,
            durationSeconds,
            viewCount,
            publishedAt,
            thumbnail,
            channelName: snippet?.channelTitle,
          };
        }
      } catch (err: any) {
        this.logger.warn(`YouTube Data API fetchVideoDetails for ${videoId} failed: ${err.message}`);
      }
    }

    // 2. InnerTube WEB Player API fallback (Zero API key needed)
    try {
      const playerRes = await axios.post(
        'https://www.youtube.com/youtubei/v1/player',
        {
          context: {
            client: {
              clientName: 'WEB',
              clientVersion: '2.20240301.00.00',
              hl: 'en',
            },
          },
          videoId,
        },
        {
          headers: {
            'Content-Type': 'application/json',
            'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
          timeout: 10000,
        },
      );

      const data = playerRes.data;
      const details = data?.videoDetails;
      const microformat = data?.microformat?.playerMicroformatRenderer;

      const title = details?.title || microformat?.title?.simpleText;
      const lengthSeconds = parseInt(details?.lengthSeconds || '0', 10);
      const duration = formatSecondsToDuration(lengthSeconds);
      const viewCount = parseInt(details?.viewCount || microformat?.viewCount || '0', 10);

      const pubDateStr = microformat?.publishDate || microformat?.uploadDate;
      const publishedAt = pubDateStr ? new Date(pubDateStr) : undefined;

      const thumbSources = microformat?.thumbnail?.thumbnails || details?.thumbnail?.thumbnails || [];
      const thumbnail =
        thumbSources[thumbSources.length - 1]?.url ||
        `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;

      return {
        title,
        duration: duration !== '0:00' ? duration : undefined,
        durationSeconds: lengthSeconds,
        viewCount,
        publishedAt,
        thumbnail,
        channelName: details?.author || microformat?.ownerChannelName,
      };
    } catch (err: any) {
      this.logger.warn(`InnerTube player fetchVideoDetails for ${videoId} failed: ${err.message}`);
    }

    return null;
  }

  /**
   * Backfill/Refresh accurate YouTube metadata for existing videos in the database.
   * Updates viewCount, duration, and true publishedAt for all videos that have 0 views
   * or placeholder timestamps.
   */
  async backfillVideoMetadata(limit = 150) {
    try {
      const staleVideos = await this.prisma.video.findMany({
        where: {
          OR: [
            { viewCount: 0 },
            { duration: '0:00' },
          ],
        },
        take: limit,
        orderBy: { updatedAt: 'asc' },
      });

      if (!staleVideos.length) return;

      this.logger.log(`🔍 Backfilling real YouTube metadata for ${staleVideos.length} videos...`);
      let updatedCount = 0;

      for (const v of staleVideos) {
        try {
          const details = await this.fetchVideoDetails(v.id);
          if (details) {
            await this.prisma.video.update({
              where: { id: v.id },
              data: {
                title: details.title || undefined,
                duration: details.duration || undefined,
                viewCount: details.viewCount !== undefined ? details.viewCount : undefined,
                publishedAt: details.publishedAt || undefined,
                thumbnail: details.thumbnail || undefined,
              },
            });
            updatedCount++;
          }
          await new Promise((r) => setTimeout(r, 200));
        } catch (e: any) {
          this.logger.warn(`Error backfilling video ${v.id}: ${e.message}`);
        }
      }

      this.logger.log(`✅ Backfilled real YouTube metadata for ${updatedCount}/${staleVideos.length} videos.`);
    } catch (err: any) {
      this.logger.error(`Backfill video metadata error: ${err.message}`);
    }
  }
}

