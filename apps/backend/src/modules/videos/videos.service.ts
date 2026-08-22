import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class VideosService {
  constructor(private readonly prisma: PrismaService) {}

  async findAll(query: {
    category?: string;
    type?: 'VIDEO' | 'SHORT';
    channelId?: string;
    search?: string;
    limit?: number;
    offset?: number;
  }) {
    const where: any = {};

    if (query.type) {
      where.type = query.type;
    }

    if (query.category && query.category !== 'All') {
      where.category = query.category;
    }

    if (query.channelId) {
      where.channelId = query.channelId;
    }

    if (query.search) {
      where.OR = [
        { title: { contains: query.search, mode: 'insensitive' } },
        { description: { contains: query.search, mode: 'insensitive' } },
        { channelName: { contains: query.search, mode: 'insensitive' } },
      ];
    }

    const limit = query.limit ? Number(query.limit) : 20;
    const offset = query.offset ? Number(query.offset) : 0;

    return this.prisma.video.findMany({
      where,
      orderBy: { publishedAt: 'desc' },
      take: limit,
      skip: offset,
    });
  }

  async findOne(id: string) {
    const video = await this.prisma.video.findUnique({
      where: { id },
    });

    if (!video) {
      throw new NotFoundException({
        message: 'Video not found',
        error: 'Not Found',
        statusCode: 404,
      });
    }

    return video;
  }
}
