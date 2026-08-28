import { Injectable, NotFoundException, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class VideosService {
  private readonly logger = new Logger(VideosService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly configService: ConfigService,
  ) {}

  async findAll(query: {
    category?: string;
    type?: 'VIDEO' | 'SHORT';
    channelId?: string;
    channelIds?: string | string[];
    search?: string;
    limit?: number;
    offset?: number;
  }) {
    const where: any = {
      channel: {
        isActive: true,
      },
    };

    if (query.type) {
      where.type = query.type;
    }

    if (query.category && query.category !== 'All') {
      where.category = query.category;
    }

    if (query.channelId) {
      where.channelId = query.channelId;
    } else if (query.channelIds) {
      const ids = Array.isArray(query.channelIds)
        ? query.channelIds
        : query.channelIds.split(',').map((id) => id.trim()).filter(Boolean);
      if (ids.length > 0) {
        where.channelId = { in: ids };
      }
    }

    if (query.search) {
      where.OR = [
        { title: { contains: query.search, mode: 'insensitive' } },
        { description: { contains: query.search, mode: 'insensitive' } },
        { channelName: { contains: query.search, mode: 'insensitive' } },
      ];
    }

    const limit = query.limit ? Number(query.limit) : 50;
    const offset = query.offset ? Number(query.offset) : 0;

    const videos = await this.prisma.video.findMany({
      where,
      include: {
        channel: {
          select: {
            id: true,
            name: true,
            thumbnail: true,
            subscriberCount: true,
          },
        },
      },
      orderBy: { publishedAt: 'desc' },
      take: limit,
      skip: offset,
    });

    return videos.map((v) => ({
      ...v,
      channelName: v.channelName || v.channel?.name || 'Channel',
      channelAvatarUrl: v.channelThumbnail || v.channel?.thumbnail || null,
      channelTitle: v.channelName || v.channel?.name || 'Channel',
    }));
  }

  async findOne(id: string) {
    const video = await this.prisma.video.findUnique({
      where: { id },
      include: {
        channel: true,
      },
    });

    if (!video) {
      throw new NotFoundException({
        message: 'Video not found',
        error: 'Not Found',
        statusCode: 404,
      });
    }

    return {
      ...video,
      channelName: video.channelName || video.channel?.name || 'Channel',
      channelAvatarUrl: video.channelThumbnail || video.channel?.thumbnail || null,
      channelTitle: video.channelName || video.channel?.name || 'Channel',
    };
  }

  async importShortVideo(body: {
    youtubeVideoId: string;
    sourceVideoId?: string;
    creatorName?: string;
    creatorEmail?: string;
    clipStartTime?: number;
    clipEndTime?: number;
    title?: string;
    description?: string;
    category?: string;
  }) {
    const videoId = body.youtubeVideoId.trim();
    const apiKey = this.configService.get<string>('youtubeApiKey');
    let title = body.title || 'Inspirational Short';
    let description = body.description || '';
    let thumbnail = `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;
    let channelId = 'UC_ChristianTubeOfficial';
    let channelName = 'Christian-Tube';
    let channelThumbnail: string | null = null;
    let publishedAt = new Date();
    let duration = 'PT60S';

    let parsedMeta: any = {
      creatorName: body.creatorName,
      creatorEmail: body.creatorEmail,
      sourceVideoId: body.sourceVideoId,
      clipStartTime: body.clipStartTime,
      clipEndTime: body.clipEndTime,
    };

    // If sourceVideoId is provided, inherit the original preacher's channel details
    if (body.sourceVideoId) {
      const sourceVideo = await this.prisma.video.findUnique({
        where: { id: body.sourceVideoId },
        include: { channel: true },
      });
      if (sourceVideo) {
        channelId = sourceVideo.channelId || channelId;
        channelName = sourceVideo.channelName || channelName;
        channelThumbnail = sourceVideo.channelThumbnail || null;
      }
    }

    // Try to fetch YouTube metadata if API key is present
    if (apiKey) {
      try {
        const detailsUrl = `https://www.googleapis.com/youtube/v3/videos?key=${apiKey}&id=${encodeURIComponent(videoId)}&part=snippet,contentDetails,statistics`;
        const res = await fetch(detailsUrl);
        const data = await res.json();
        const item = data.items?.[0];

        if (item) {
          const snippet = item.snippet;
          title = snippet.title || title;
          description = snippet.description || description;
          thumbnail =
            snippet.thumbnails?.maxres?.url ||
            snippet.thumbnails?.high?.url ||
            snippet.thumbnails?.medium?.url ||
            thumbnail;
          publishedAt = snippet.publishedAt ? new Date(snippet.publishedAt) : publishedAt;
          duration = item.contentDetails?.duration || duration;

          // Parse embedded <!-- CT_META: {...} --> from description if present
          const jsonMatch = description.match(/<!--\s*CT_META:\s*(\{.*?\})\s*-->/s);
          if (jsonMatch) {
            try {
              const meta = JSON.parse(jsonMatch[1]);
              parsedMeta.creatorName = meta.creatorName || parsedMeta.creatorName;
              parsedMeta.creatorEmail = meta.creatorEmail || parsedMeta.creatorEmail;
              parsedMeta.sourceVideoId = meta.sourceVideoId || parsedMeta.sourceVideoId;
              parsedMeta.clipStartTime = meta.startTime ?? parsedMeta.clipStartTime;
              parsedMeta.clipEndTime = meta.endTime ?? parsedMeta.clipEndTime;
            } catch (_) {}
          }
        }
      } catch (e: any) {
        this.logger.warn(`Could not fetch details from YouTube for ${videoId}: ${e.message}`);
      }
    }

    // Ensure Channel exists
    await this.prisma.channel.upsert({
      where: { id: channelId },
      update: {},
      create: {
        id: channelId,
        name: channelName,
        thumbnail: channelThumbnail,
        isActive: true,
        category: body.category || 'General',
      },
    });

    // Upsert Video into database as a SHORT
    const savedVideo = await this.prisma.video.upsert({
      where: { id: videoId },
      update: {
        type: 'SHORT',
        title,
        description,
        thumbnail,
        creatorName: parsedMeta.creatorName || null,
        creatorEmail: parsedMeta.creatorEmail || null,
        sourceVideoId: parsedMeta.sourceVideoId || null,
        clipStartTime: parsedMeta.clipStartTime != null ? Number(parsedMeta.clipStartTime) : null,
        clipEndTime: parsedMeta.clipEndTime != null ? Number(parsedMeta.clipEndTime) : null,
        clippedAt: new Date(),
        category: body.category || 'General',
      },
      create: {
        id: videoId,
        type: 'SHORT',
        title,
        description,
        thumbnail,
        channelId,
        channelName,
        channelThumbnail,
        publishedAt,
        duration,
        viewCount: 0,
        tags: ['#Shorts'],
        creatorName: parsedMeta.creatorName || null,
        creatorEmail: parsedMeta.creatorEmail || null,
        sourceVideoId: parsedMeta.sourceVideoId || null,
        clipStartTime: parsedMeta.clipStartTime != null ? Number(parsedMeta.clipStartTime) : null,
        clipEndTime: parsedMeta.clipEndTime != null ? Number(parsedMeta.clipEndTime) : null,
        clippedAt: new Date(),
        category: body.category || 'General',
      },
    });

    this.logger.log(`Short imported and published: ${savedVideo.id} - "${savedVideo.title}"`);
    return savedVideo;
  }
}
