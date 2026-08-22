import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';
import { PrismaService } from '../prisma/prisma.service';
import { YoutubeService } from '../youtube/youtube.service';

@Injectable()
export class ChannelsService {
  private readonly logger = new Logger(ChannelsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly configService: ConfigService,
    private readonly youtubeService: YoutubeService,
  ) {}

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

  async searchYouTube(query: string) {
    const apiKey = this.configService.get<string>('youtubeApiKey');
    if (!apiKey || !query || !query.trim()) {
      return [];
    }

    try {
      const searchUrl = `https://www.googleapis.com/youtube/v3/search?key=${apiKey}&q=${encodeURIComponent(query.trim())}&type=channel&part=snippet&maxResults=10`;
      const searchRes = await axios.get(searchUrl);
      const items = searchRes.data?.items || [];
      if (!items.length) return [];

      const channelIds = items.map((it: any) => it.snippet?.channelId || it.id?.channelId).filter(Boolean).join(',');
      const detailsUrl = `https://www.googleapis.com/youtube/v3/channels?key=${apiKey}&id=${channelIds}&part=snippet,statistics`;
      const detailsRes = await axios.get(detailsUrl);
      const detailMap = new Map<string, any>();
      for (const d of detailsRes.data?.items || []) {
        detailMap.set(d.id, d);
      }

      return items.map((it: any) => {
        const id = it.snippet?.channelId || it.id?.channelId;
        const detail = detailMap.get(id);
        const snippet = detail?.snippet || it.snippet;
        const stats = detail?.statistics;

        return {
          id: id || '',
          name: snippet?.title || 'Channel',
          handle: snippet?.customUrl || null,
          description: snippet?.description || null,
          thumbnail: snippet?.thumbnails?.high?.url || snippet?.thumbnails?.medium?.url || snippet?.thumbnails?.default?.url || null,
          subscriberCount: stats?.subscriberCount ? parseInt(stats.subscriberCount, 10) : null,
          videoCount: stats?.videoCount ? parseInt(stats.videoCount, 10) : null,
        };
      });
    } catch (e: any) {
      this.logger.error(`YouTube channel search error: ${e.message}`);
      return [];
    }
  }

  async addChannel(data: { channelUrl: string; name?: string; category?: string; language?: string }) {
    let rawUrl = (data.channelUrl || '').trim();
    let channelId = rawUrl;

    if (rawUrl.includes('youtube.com/channel/')) {
      channelId = rawUrl.split('youtube.com/channel/')[1].split('/')[0].split('?')[0];
    } else if (rawUrl.includes('youtu.be/')) {
      channelId = rawUrl.split('youtu.be/')[1].split('/')[0].split('?')[0];
    }

    let channelName = data.name || channelId;
    let thumbnail: string | null = null;
    let description: string | null = null;
    let subscriberCount: string | null = null;

    const apiKey = this.configService.get<string>('youtubeApiKey');
    if (apiKey) {
      try {
        let endpoint = `https://www.googleapis.com/youtube/v3/channels?key=${apiKey}&part=snippet,statistics`;
        if (channelId.startsWith('@') || rawUrl.includes('youtube.com/@')) {
          const handle = channelId.startsWith('@') 
            ? channelId.substring(1) 
            : rawUrl.split('youtube.com/@')[1].split('/')[0].split('?')[0];
          endpoint += `&forHandle=${handle}`;
        } else {
          endpoint += `&id=${channelId}`;
        }

        const res = await axios.get(endpoint);
        if (res.data?.items?.length > 0) {
          const item = res.data.items[0];
          channelId = item.id;
          channelName = item.snippet?.title || channelName;
          description = item.snippet?.description || null;
          thumbnail = item.snippet?.thumbnails?.high?.url || item.snippet?.thumbnails?.default?.url || null;
          subscriberCount = item.statistics?.subscriberCount ? String(item.statistics.subscriberCount) : null;
        }
      } catch (err: any) {
        this.logger.warn(`Could not fetch details from YouTube API: ${err.message}`);
      }
    }

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

    // Trigger instant background video sync for the new channel
    this.youtubeService.syncChannelVideos(channel.id, channel.category).catch((e) => {
      this.logger.warn(`Initial sync error for added channel: ${e.message}`);
    });

    return {
      status: 'success',
      message: 'Channel successfully added and video ingestion started',
      channel,
    };
  }

  async removeChannel(id: string) {
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
    } catch (e: any) {
      this.logger.error(`Error removing channel ${id}: ${e.message}`);
      throw e;
    }
  }

  async createRequest(data: { channelUrl: string; notes?: string; submittedBy?: string }) {
    if (data.channelUrl) {
      try {
        await this.addChannel({ channelUrl: data.channelUrl, name: data.notes });
      } catch (e: any) {
        this.logger.warn(`Auto-add on request failed: ${e.message}`);
      }
    }

    return this.prisma.channelRequest.create({
      data: {
        channelUrl: data.channelUrl,
        notes: data.notes,
        submittedBy: data.submittedBy,
      },
    });
  }
}
