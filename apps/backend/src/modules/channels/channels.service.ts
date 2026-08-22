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
    return this.prisma.channel.findMany({
      where: { isActive: true },
      orderBy: { name: 'asc' },
    });
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
    let subscriberCount: number | null = null;

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
          channelName = item.snippet.title || channelName;
          description = item.snippet.description || null;
          thumbnail = item.snippet.thumbnails?.high?.url || item.snippet.thumbnails?.default?.url || null;
          subscriberCount = item.statistics?.subscriberCount ? parseInt(item.statistics.subscriberCount) : null;
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
