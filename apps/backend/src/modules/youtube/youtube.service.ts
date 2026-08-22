import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron, CronExpression } from '@nestjs/schedule';
import axios from 'axios';
import { PrismaService } from '../prisma/prisma.service';

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
    await this.seedInitialChannels();
  }

  async seedInitialChannels() {
    const seedChannels = this.configService.get<any[]>('seedChannels') || [];
    if (!seedChannels.length) return;

    this.logger.log(`Checking ${seedChannels.length} seed channels for instance...`);
    for (const sc of seedChannels) {
      const exists = await this.prisma.channel.findUnique({
        where: { id: sc.id },
      });

      if (!exists) {
        await this.prisma.channel.create({
          data: {
            id: sc.id,
            name: sc.name,
            category: sc.category,
            language: sc.language,
            isActive: true,
          },
        });
        this.logger.log(`Seeded channel: ${sc.name} (${sc.id})`);
      }
    }
  }

  @Cron(CronExpression.EVERY_2_HOURS)
  async syncAllChannels() {
    if (!this.apiKey) {
      this.logger.warn('YOUTUBE_API_KEY is not set. Skipping channel sync.');
      return;
    }

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
    if (!this.apiKey) return;

    const url = `https://www.googleapis.com/youtube/v3/search?key=${this.apiKey}&channelId=${channelId}&part=snippet,id&order=date&maxResults=15`;
    const response = await axios.get(url);

    if (response.data && response.data.items) {
      for (const item of response.data.items) {
        if (item.id.kind === 'youtube#video') {
          const videoId = item.id.videoId;
          const snippet = item.snippet;

          const exists = await this.prisma.video.findUnique({
            where: { id: videoId },
          });

          if (!exists) {
            await this.prisma.video.create({
              data: {
                id: videoId,
                type: 'VIDEO',
                title: snippet.title,
                description: snippet.description || '',
                thumbnail: snippet.thumbnails?.high?.url || snippet.thumbnails?.default?.url || '',
                channelId: channelId,
                channelName: snippet.channelTitle,
                publishedAt: new Date(snippet.publishedAt),
                duration: '0:00',
                category: defaultCategory || 'General',
                transcriptionStatus: 'pending',
              },
            });
            this.logger.log(`Indexed new video: ${snippet.title} (${videoId})`);
          }
        }
      }

      await this.prisma.channel.update({
        where: { id: channelId },
        data: { lastSyncedAt: new Date() },
      });
    }
  }
}
