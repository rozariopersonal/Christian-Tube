import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class VideosService {
  constructor(private readonly prisma: PrismaService) {}

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
}
