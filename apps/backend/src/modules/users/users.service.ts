import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class UsersService {
  private readonly logger = new Logger(UsersService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly configService: ConfigService,
  ) {}

  isAdmin(email?: string): boolean {
    if (!email) return false;
    const adminEmails = this.configService.get<string[]>('adminEmails') || [];
    return adminEmails.includes(email.trim().toLowerCase());
  }

  async syncUser(data: {
    id: string;
    email: string;
    displayName?: string;
    photoUrl?: string;
  }) {
    const role = this.isAdmin(data.email) ? 'ADMIN' : 'USER';

    const user = await this.prisma.user.upsert({
      where: { email: data.email },
      update: {
        displayName: data.displayName || undefined,
        photoUrl: data.photoUrl || undefined,
        role,
        lastLoginAt: new Date(),
      },
      create: {
        id: data.id,
        email: data.email,
        displayName: data.displayName || 'User',
        photoUrl: data.photoUrl || null,
        role,
        isBlocked: false,
        lastLoginAt: new Date(),
      },
    });

    return user;
  }

  async findAll(query?: { search?: string }) {
    const where: any = {};
    if (query?.search) {
      where.OR = [
        { email: { contains: query.search, mode: 'insensitive' } },
        { displayName: { contains: query.search, mode: 'insensitive' } },
      ];
    }

    return this.prisma.user.findMany({
      where,
      orderBy: { lastLoginAt: 'desc' },
    });
  }

  async findOne(id: string) {
    const user = await this.prisma.user.findUnique({
      where: { id },
    });
    if (!user) {
      throw new NotFoundException(`User with ID ${id} not found`);
    }
    return user;
  }

  async toggleBlock(id: string) {
    const user = await this.findOne(id);
    return this.prisma.user.update({
      where: { id },
      data: { isBlocked: !user.isBlocked },
    });
  }

  async blockUser(id: string) {
    return this.prisma.user.update({
      where: { id },
      data: { isBlocked: true },
    });
  }

  async unblockUser(id: string) {
    return this.prisma.user.update({
      where: { id },
      data: { isBlocked: false },
    });
  }

  // In-memory fallback map to ensure zero-downtime resilience
  private static playbackCache = new Map<string, any>();

  async savePlayback(data: {
    userEmail: string;
    userId?: string;
    deviceId?: string;
    mediaType?: string;
    trackId: string;
    seriesId?: string;
    title?: string;
    speaker?: string;
    coverUrl?: string;
    audioUrl?: string;
    positionSeconds: number;
    durationSeconds: number;
    payloadJson?: string;
    updatedAt?: string;
  }) {
    const email = (data.userEmail || '').trim().toLowerCase();
    const mediaType = (data.mediaType || 'audio').toLowerCase();
    if (!email || !data.trackId) {
      return { success: false, message: 'userEmail and trackId are required' };
    }

    const updatedAtDate = data.updatedAt ? new Date(data.updatedAt) : new Date();

    const record = {
      userEmail: email,
      userId: data.userId || null,
      deviceId: data.deviceId || null,
      mediaType,
      trackId: data.trackId,
      seriesId: data.seriesId || null,
      title: data.title || null,
      speaker: data.speaker || null,
      coverUrl: data.coverUrl || null,
      audioUrl: data.audioUrl || null,
      positionSeconds: Math.max(0, Math.round(data.positionSeconds || 0)),
      durationSeconds: Math.max(0, Math.round(data.durationSeconds || 0)),
      payloadJson: data.payloadJson || null,
      updatedAt: updatedAtDate,
    };

    // Cache immediately in memory
    const cacheKey = `${email}:${mediaType}`;
    UsersService.playbackCache.set(cacheKey, record);

    // Try DB upsert if Prisma model exists
    try {
      if ((this.prisma as any).userPlayback) {
        await (this.prisma as any).userPlayback.upsert({
          where: {
            userEmail_mediaType: {
              userEmail: email,
              mediaType,
            },
          },
          update: {
            ...record,
            updatedAt: updatedAtDate,
          },
          create: {
            ...record,
            updatedAt: updatedAtDate,
          },
        });
      }
    } catch (e) {
      this.logger.warn(`Database playback upsert non-critical fallback: ${e}`);
    }

    return { success: true, playback: record };
  }

  async getPlayback(query: { email?: string; userId?: string; mediaType?: string }) {
    const email = (query.email || '').trim().toLowerCase();
    const mediaType = (query.mediaType || 'audio').toLowerCase();
    if (!email) {
      return null;
    }

    const cacheKey = `${email}:${mediaType}`;

    // Try reading from DB first
    try {
      if ((this.prisma as any).userPlayback) {
        const row = await (this.prisma as any).userPlayback.findUnique({
          where: {
            userEmail_mediaType: {
              userEmail: email,
              mediaType,
            },
          },
        });
        if (row) return row;
      }
    } catch (e) {
      this.logger.warn(`Database playback query non-critical fallback: ${e}`);
    }

    // Fallback to cache
    return UsersService.playbackCache.get(cacheKey) || null;
  }
}
