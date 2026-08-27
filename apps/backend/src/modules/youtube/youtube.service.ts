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

function isIstDaytime(): boolean {
  const now = new Date();
  // IST offset: UTC+5:30 (+330 minutes)
  const totalIstMinutes = now.getUTCHours() * 60 + now.getUTCMinutes() + 330;
  const istHour = Math.floor((totalIstMinutes / 60) % 24);
  // Daytime in IST: 6:00 AM to 10:00 PM
  return istHour >= 6 && istHour <= 22;
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

  async onModuleInit() {
    setTimeout(() => {
      this.syncAllChannelsPeriodically().catch((e) => {
        this.logger.warn(`Initial automated sync on boot error: ${e.message}`);
      });
    }, 5000);
  }

  /**
   * Periodic scheduler: Runs every 2 hours during IST daytime (06:00 to 22:00 IST)
   * to sync channels in continuous batches and ingest latest uploads.
   */
  @Cron('0 6-22/2 * * *', {
    timeZone: 'Asia/Kolkata',
  })
  async syncAllChannelsPeriodically() {
    if (!isIstDaytime()) {
      this.logger.log('Outside IST daytime hours (06:00 - 22:00 IST). Skipping automated sync.');
      return;
    }

    if (this.isSyncing) {
      this.logger.log('Previous channel sync cycle is still active. Skipping concurrent run.');
      return;
    }

    this.isSyncing = true;
    try {
      const channels = await this.prisma.channel.findMany({
        where: { isActive: true },
        orderBy: { updatedAt: 'asc' },
      });

      if (!channels.length) return;

      this.logger.log(`🔄 Starting automated batch video & metadata sync for ${channels.length} channels (IST daytime schedule)...`);

      for (const channel of channels) {
        try {
          await this.syncChannelVideos(channel.id, channel.category, 4);
        } catch (err: any) {
          this.logger.error(`Error syncing channel ${channel.name} (${channel.id}): ${err.message}`);
        }
      }
    } finally {
      this.isSyncing = false;
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
  async syncChannelVideos(channelId: string, defaultCategory?: string | null, maxBatches = 5) {
    // 1. Sync & update channel metadata first
    const channel = await this.refreshChannelMetadata(channelId);

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
   * Allows paginating 50 items per batch across multiple pages with minimal quota cost!
   */
  private async syncViaPlaylistApi(channelId: string, defaultCategory?: string | null, maxBatches = 5) {
    const channel = await this.prisma.channel.findUnique({
      where: { id: channelId },
    });
    if (!channel) return;

    // Uploads playlist ID is standard: replace 'UC' prefix with 'UU'
    const uploadsPlaylistId = channelId.startsWith('UC')
      ? `UU${channelId.substring(2)}`
      : channelId;

    let pageToken: string | undefined = channel.syncCursor || undefined;
    let batchesProcessed = 0;
    let totalSyncedInRun = 0;

    while (batchesProcessed < maxBatches) {
      batchesProcessed++;

      const playlistUrl = `https://www.googleapis.com/youtube/v3/playlistItems?key=${this.apiKey}&playlistId=${uploadsPlaylistId}&part=snippet,contentDetails&maxResults=50${pageToken ? `&pageToken=${pageToken}` : ''}`;
      const playlistRes = await axios.get(playlistUrl, { timeout: 10000 });
      const items = playlistRes.data?.items || [];
      const nextPageToken = playlistRes.data?.nextPageToken;

      if (!items.length) {
        // No more items in playlist
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

      // Collect video IDs to fetch detailed duration and stats in 1 batch
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
        const isShort = (durationSeconds > 0 && durationSeconds <= 60) || hasShortsTag;
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

        await this.prisma.video.upsert({
          where: { id: videoId },
          update: {
            type: videoType,
            title,
            description,
            thumbnail: thumb,
            channelName: snippet?.channelTitle || channel.name,
            channelThumbnail: channel.thumbnail,
            channelSubscriberCount: channel.subscriberCount,
            duration,
            viewCount,
            tags,
            category: defaultCategory || channel.category || 'General',
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
          },
        });
        totalSyncedInRun++;
      }

      // Update progress & cursor
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
      } else {
        // Reached end of channel
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

    this.logger.log(
      `✅ Synced ${totalSyncedInRun} videos in ${batchesProcessed} batch(es) for ${channel.name} (${channelId})`,
    );
  }

  /**
   * Syncs videos via public YouTube HTML pagination + Atom RSS feed
   * Zero API key or quota required.
   */
  private async syncViaWebScraper(channelId: string, defaultCategory?: string | null, maxBatches = 5) {
    const channel = await this.prisma.channel.findUnique({
      where: { id: channelId },
    });
    if (!channel) return;

    let syncedCount = 0;

    // 1. Initial RSS feed sync (latest 15 videos)
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
      this.logger.warn(`RSS feed sync step: ${e.message}`);
    }

    // 2. Multi-batch HTML channel /videos tab scraping for older historical uploads
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

          for (const item of contents) {
            const renderer = item.richItemRenderer?.content?.videoRenderer || item.gridVideoRenderer || item.videoRenderer;
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
              const videoType = isShort ? 'SHORT' : 'VIDEO';
              const thumb =
                renderer.thumbnail?.thumbnails?.slice(-1)[0]?.url ||
                `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;
              const viewCountText = renderer.viewCountText?.simpleText || '';
              const viewCount = parseInt(viewCountText.replace(/[^0-9]/g, ''), 10) || 0;

              await this.prisma.video.upsert({
                where: { id: videoId },
                update: {
                  type: videoType,
                  title,
                  thumbnail: thumb,
                  duration,
                  viewCount: viewCount > 0 ? viewCount : undefined,
                  channelName: channel.name,
                  channelThumbnail: channel.thumbnail,
                  channelSubscriberCount: channel.subscriberCount,
                  category: defaultCategory || channel.category || 'General',
                },
                create: {
                  id: videoId,
                  type: videoType,
                  title,
                  description: '',
                  thumbnail: thumb,
                  channelId,
                  channelName: channel.name,
                  channelThumbnail: channel.thumbnail,
                  channelSubscriberCount: channel.subscriberCount,
                  publishedAt: new Date(),
                  duration,
                  viewCount,
                  category: defaultCategory || channel.category || 'General',
                  transcriptionStatus: 'pending',
                },
              });
              syncedCount++;
            }
          }
        }
      }
    } catch (err: any) {
      this.logger.warn(`Web scraper video pagination error for ${channelId}: ${err.message}`);
    }

    await this.prisma.channel.update({
      where: { id: channelId },
      data: {
        lastSyncedAt: new Date(),
        syncStatus: 'COMPLETED',
      },
    });

    this.logger.log(`✅ Synced ${syncedCount} videos via web scraper for ${channel.name} (${channelId})`);
  }
}

