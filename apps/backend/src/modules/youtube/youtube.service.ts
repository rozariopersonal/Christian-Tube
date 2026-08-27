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

@Injectable()
export class YoutubeService implements OnModuleInit {
  private readonly logger = new Logger(YoutubeService.name);
  private apiKey: string;

  constructor(
    private readonly configService: ConfigService,
    private readonly prisma: PrismaService,
  ) {
    this.apiKey = this.configService.get<string>('youtubeApiKey') || '';
  }

  async onModuleInit() {
    try {
      await this.refreshAllChannelMetadata();
    } catch (e: any) {
      this.logger.warn(`Initial channel sync on boot skipped: ${e.message}`);
    }
  }

  async refreshAllChannelMetadata() {
    if (!this.apiKey) return;

    const channels = await this.prisma.channel.findMany({
      where: { isActive: true },
    });

    if (!channels.length) return;

    this.logger.log(`Refreshing metadata for ${channels.length} channels from YouTube API...`);
    const channelIds = channels.map((c) => c.id).join(',');

    try {
      const url = `https://www.googleapis.com/youtube/v3/channels?key=${this.apiKey}&id=${channelIds}&part=snippet,statistics`;
      const res = await axios.get(url);
      const items = res.data?.items || [];

      for (const item of items) {
        const id = item.id;
        const snippet = item.snippet;
        const stats = item.statistics;

        const thumbnail = snippet?.thumbnails?.high?.url || snippet?.thumbnails?.medium?.url || snippet?.thumbnails?.default?.url;
        const description = snippet?.description || null;
        const subscriberCount = stats?.subscriberCount ? String(stats.subscriberCount) : null;
        const title = snippet?.title;

        await this.prisma.channel.update({
          where: { id },
          data: {
            name: title || undefined,
            thumbnail: thumbnail || undefined,
            description: description || undefined,
            subscriberCount: subscriberCount || undefined,
          },
        });
      }
    } catch (err: any) {
      this.logger.error(`Error refreshing channel metadata: ${err.message}`);
    }
  }

  @Cron(CronExpression.EVERY_2_HOURS)
  async syncAllChannels() {
    if (!this.apiKey) {
      this.logger.warn('YOUTUBE_API_KEY is not set. Skipping channel sync.');
      return;
    }

    await this.refreshAllChannelMetadata();

    const channels = await this.prisma.channel.findMany({
      where: { isActive: true },
    });

    this.logger.log(`Starting automated YouTube sync for ${channels.length} channels...`);

    for (const channel of channels) {
      try {
        await this.syncChannelVideos(channel.id, channel.category);
      } catch (err: any) {
        this.logger.error(`Error syncing channel ${channel.name} (${channel.id}): ${err.message}`);
      }
    }
  }

  async syncChannelVideos(channelId: string, defaultCategory?: string | null) {
    if (this.apiKey) {
      try {
        await this.syncChannelVideosViaApi(channelId, defaultCategory);
        return;
      } catch (err: any) {
        this.logger.warn(`YouTube API sync failed for ${channelId}: ${err.message}. Falling back to RSS feed sync...`);
      }
    }

    // Fallback: sync via public YouTube Atom RSS feed (0 API quota required)
    await this.syncChannelVideosViaRss(channelId, defaultCategory);
  }

  private async syncChannelVideosViaApi(channelId: string, defaultCategory?: string | null) {
    // 1. Search recent uploads
    const searchUrl = `https://www.googleapis.com/youtube/v3/search?key=${this.apiKey}&channelId=${channelId}&part=snippet,id&order=date&maxResults=25`;
    const searchResponse = await axios.get(searchUrl);

    if (searchResponse.data && searchResponse.data.items) {
      const videoItems = searchResponse.data.items.filter((item: any) => item.id?.kind === 'youtube#video');
      if (!videoItems.length) return;

      const videoIds = videoItems.map((item: any) => item.id.videoId).join(',');

      // 2. Fetch full details (duration, views, high-res thumbnail)
      const detailsUrl = `https://www.googleapis.com/youtube/v3/videos?key=${this.apiKey}&id=${videoIds}&part=snippet,contentDetails,statistics`;
      const detailsResponse = await axios.get(detailsUrl);
      const detailMap = new Map<string, any>();

      for (const d of detailsResponse.data?.items || []) {
        detailMap.set(d.id, d);
      }

      const channel = await this.prisma.channel.findUnique({
        where: { id: channelId },
      });

      for (const item of videoItems) {
        const videoId = item.id.videoId;
        const detail = detailMap.get(videoId);
        const snippet = detail?.snippet || item.snippet;
        const contentDetails = detail?.contentDetails;
        const stats = detail?.statistics;

        const duration = parseIsoDuration(contentDetails?.duration || '');
        const durationSeconds = parseIsoDurationSeconds(contentDetails?.duration || '');
        const titleLower = (snippet.title || '').toLowerCase();
        const descLower = (snippet.description || '').toLowerCase();
        const hasShortsTag = titleLower.includes('#short') || descLower.includes('#short');
        const isShort = (durationSeconds > 0 && durationSeconds <= 60) || hasShortsTag;
        const videoType = isShort ? 'SHORT' : 'VIDEO';
        const viewCount = stats?.viewCount ? parseInt(stats.viewCount, 10) : 0;
        const thumb = snippet?.thumbnails?.maxres?.url || snippet?.thumbnails?.high?.url || snippet?.thumbnails?.default?.url || '';

        await this.prisma.video.upsert({
          where: { id: videoId },
          update: {
            type: videoType,
            title: snippet.title,
            description: snippet.description || '',
            thumbnail: thumb,
            channelName: snippet.channelTitle,
            channelThumbnail: channel?.thumbnail,
            channelSubscriberCount: channel?.subscriberCount,
            duration: duration,
            viewCount: viewCount,
            category: defaultCategory || 'General',
          },
          create: {
            id: videoId,
            type: videoType,
            title: snippet.title,
            description: snippet.description || '',
            thumbnail: thumb,
            channelId: channelId,
            channelName: snippet.channelTitle,
            channelThumbnail: channel?.thumbnail,
            channelSubscriberCount: channel?.subscriberCount,
            publishedAt: new Date(snippet.publishedAt),
            duration: duration,
            viewCount: viewCount,
            category: defaultCategory || 'General',
            transcriptionStatus: 'pending',
          },
        });
      }

      await this.prisma.channel.update({
        where: { id: channelId },
        data: { lastSyncedAt: new Date() },
      });
    }
  }

  async syncChannelVideosViaRss(channelId: string, defaultCategory?: string | null) {
    try {
      const feedUrl = `https://www.youtube.com/feeds/videos.xml?channel_id=${channelId}`;
      const res = await axios.get(feedUrl, {
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/xml,text/xml,*/*',
        },
        timeout: 10000,
      });

      const xml = res.data;
      if (!xml || typeof xml !== 'string') return;

      const channel = await this.prisma.channel.findUnique({
        where: { id: channelId },
      });

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

        const authorMatch = entryXml.match(/<author>[\s\S]*?<name>([^<]+)<\/name>[\s\S]*?<\/author>/);
        const channelName = authorMatch ? authorMatch[1].trim() : channel?.name || 'Channel';

        const thumbMatch = entryXml.match(/<media:thumbnail\s+url="([^"]+)"/);
        const thumbnail = thumbMatch ? thumbMatch[1] : `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;

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
            channelName,
            channelThumbnail: channel?.thumbnail,
            channelSubscriberCount: channel?.subscriberCount,
            category: defaultCategory || channel?.category || 'General',
          },
          create: {
            id: videoId,
            type: videoType,
            title,
            description,
            thumbnail,
            channelId: channelId,
            channelName,
            channelThumbnail: channel?.thumbnail,
            channelSubscriberCount: channel?.subscriberCount,
            publishedAt,
            duration: '0:00',
            viewCount: 0,
            category: defaultCategory || channel?.category || 'General',
            transcriptionStatus: 'pending',
          },
        });
      }

      await this.prisma.channel.update({
        where: { id: channelId },
        data: { lastSyncedAt: new Date() },
      });

      this.logger.log(`Successfully synced ${entryMatches.length} videos for channel ${channelId} via RSS feed`);
    } catch (e: any) {
      this.logger.error(`Error syncing channel ${channelId} via RSS: ${e.message}`);
    }
  }
}
