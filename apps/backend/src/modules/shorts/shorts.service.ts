import { Injectable, Logger, BadRequestException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';
import { PrismaService } from '../prisma/prisma.service';

export interface InitiateUploadDto {
  title: string;
  description?: string;
  sourceVideoId?: string;
  clipStartTime?: number;
  clipEndTime?: number;
  cropOffsetX?: number;
  creatorUserId?: string;
  creatorName?: string;
  creatorEmail?: string;
}

export interface QuotaStatusResponse {
  date: string;
  unitsConsumed: number;
  unitsLimit: number;
  unitsRemaining: number;
  uploadAllowed: boolean;
  uploadCostUnits: number;
  nextRetryAfterHours?: number;
  retryAt?: string;
}

@Injectable()
export class ShortsService {
  private readonly logger = new Logger(ShortsService.name);

  constructor(
    private readonly configService: ConfigService,
    private readonly prisma: PrismaService,
  ) {}

  private getTodayUtcDateString(): string {
    const now = new Date();
    return now.toISOString().split('T')[0];
  }

  async getQuotaStatus(): Promise<QuotaStatusResponse> {
    const today = this.getTodayUtcDateString();
    const shortsConfig = this.configService.get('shorts') || {};
    const unitsLimit = shortsConfig.dailyQuotaUnits || 10000;
    const uploadCostUnits = shortsConfig.uploadCostUnits || 1600;

    let quotaLog = await this.prisma.dailyQuotaLog.findUnique({
      where: { date: today },
    });

    if (!quotaLog) {
      quotaLog = await this.prisma.dailyQuotaLog.create({
        data: {
          date: today,
          unitsConsumed: 0,
          unitsLimit,
        },
      });
    }

    const unitsRemaining = Math.max(0, unitsLimit - quotaLog.unitsConsumed);
    const uploadAllowed = unitsRemaining >= uploadCostUnits;

    const response: QuotaStatusResponse = {
      date: today,
      unitsConsumed: quotaLog.unitsConsumed,
      unitsLimit,
      unitsRemaining,
      uploadAllowed,
      uploadCostUnits,
    };

    if (!uploadAllowed) {
      // Calculate 5 hours from now or midnight UTC reset
      const retryDate = new Date(Date.now() + 5 * 60 * 60 * 1000);
      response.nextRetryAfterHours = 5;
      response.retryAt = retryDate.toISOString();
    }

    return response;
  }

  async initiateUploadSession(dto: InitiateUploadDto) {
    const quota = await this.getQuotaStatus();
    if (!quota.uploadAllowed) {
      this.logger.warn(`Upload rejected: Daily quota exhausted for ${quota.date} (${quota.unitsConsumed}/${quota.unitsLimit} units used).`);
      return {
        allowed: false,
        reason: 'QUOTA_EXCEEDED',
        message: 'Daily YouTube upload quota reached. Upload scheduled for later.',
        nextRetryAfterHours: quota.nextRetryAfterHours || 5,
        retryAt: quota.retryAt,
      };
    }

    const clientId = this.configService.get<string>('youtubeClientId');
    const clientSecret = this.configService.get<string>('youtubeClientSecret');
    const refreshToken = this.configService.get<string>('youtubeRefreshToken');
    const shortsConfig = this.configService.get('shorts') || {};

    const cleanTitle = (dto.title || 'Inspirational Christian Clip').trim();
    const maxTitleLength = 100 - ' #Shorts'.length;
    const safeTitle = cleanTitle.length > maxTitleLength
      ? `${cleanTitle.substring(0, maxTitleLength - 3)}... #Shorts`
      : `${cleanTitle} #Shorts`;

    // Metadata payload
    const metadataPayload = {
      creatorUserId: dto.creatorUserId || null,
      creatorName: dto.creatorName || 'Anonymous',
      creatorEmail: dto.creatorEmail || '',
      sourceVideoId: dto.sourceVideoId || null,
      startTime: dto.clipStartTime || 0,
      endTime: dto.clipEndTime || 0,
      cropOffsetX: dto.cropOffsetX ?? 0.0,
      clippedAt: new Date().toISOString(),
    };

    const description = [
      dto.description || cleanTitle,
      '',
      '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
      '✂️ Clipped via Christian-Tube',
      dto.creatorName ? `👤 Clipped by: ${dto.creatorName}` : '',
      dto.creatorEmail ? `📧 Contact: ${dto.creatorEmail}` : '',
      dto.sourceVideoId ? `📖 Original Video: https://youtube.com/watch?v=${dto.sourceVideoId}` : '',
      '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
      '#Shorts #ChristianTube #Faith #Sermon',
      '',
      `<!-- CT_META: ${JSON.stringify(metadataPayload)} -->`,
    ].filter(Boolean).join('\n');

    // If OAuth credentials exist, contact YouTube API for actual Resumable Session URL
    if (clientId && clientSecret && refreshToken) {
      try {
        const tokenRes = await axios.post(
          'https://oauth2.googleapis.com/token',
          new URLSearchParams({
            client_id: clientId,
            client_secret: clientSecret,
            refresh_token: refreshToken,
            grant_type: 'refresh_token',
          }).toString(),
          {
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            timeout: 10000,
          },
        );

        const accessToken = tokenRes.data?.access_token;
        if (!accessToken) {
          throw new Error('Failed to obtain YouTube access token from OAuth refresh response');
        }

        const ytRes = await axios.post(
          'https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status',
          {
            snippet: {
              title: safeTitle,
              description,
              categoryId: '29', // Nonprofits & Religion
              tags: ['#Shorts', 'Christian', 'Sermon', 'Faith'],
            },
            status: {
              privacyStatus: shortsConfig.defaultPrivacyStatus || 'unlisted',
              selfDeclaredMadeForKids: shortsConfig.selfDeclaredMadeForKids ?? true,
            },
          },
          {
            headers: {
              Authorization: `Bearer ${accessToken}`,
              'Content-Type': 'application/json; charset=UTF-8',
              'X-Upload-Content-Type': 'video/mp4',
            },
            timeout: 15000,
          },
        );

        const uploadUrl = ytRes.headers['location'];
        if (!uploadUrl) {
          throw new Error('YouTube did not return upload session URL in Location header');
        }

        // Increment daily quota units upon successful initiation
        await this.prisma.dailyQuotaLog.update({
          where: { date: quota.date },
          data: { unitsConsumed: { increment: quota.uploadCostUnits } },
        });

        this.logger.log(`YouTube upload session initialized successfully for: "${safeTitle}"`);

        return {
          allowed: true,
          uploadUrl,
          title: safeTitle,
          customChannelId: shortsConfig.customChannelId,
          metadata: metadataPayload,
        };
      } catch (err: any) {
        this.logger.error(`YouTube upload initiation failed: ${err.message}`);
        throw new BadRequestException(`Could not initiate YouTube upload: ${err.message}`);
      }
    } else {
      // Development / Mock mode when OAuth credentials are not yet set
      this.logger.warn('YouTube OAuth credentials not configured. Returning local simulated upload session URL.');
      
      await this.prisma.dailyQuotaLog.update({
        where: { date: quota.date },
        data: { unitsConsumed: { increment: quota.uploadCostUnits } },
      });

      return {
        allowed: true,
        uploadUrl: `mock://youtube-resumable-upload/${Date.now()}`,
        title: safeTitle,
        customChannelId: shortsConfig.customChannelId || 'UC_ChristianTube_Dev',
        metadata: metadataPayload,
        isSimulated: true,
      };
    }
  }

  async recordCreation(data: {
    userId?: string;
    userEmail?: string;
    creatorName?: string;
    youtubeVideoId: string;
    sourceVideoId?: string;
    title: string;
    description?: string;
    thumbnail?: string;
    durationSeconds?: number;
    clipStartTime?: number;
    clipEndTime?: number;
    cropOffsetX?: number;
  }) {
    try {
      return await (this.prisma as any).shortCreation.upsert({
        where: { id: `sc_${data.youtubeVideoId}` },
        update: {
          userId: data.userId || undefined,
          userEmail: data.userEmail || undefined,
          creatorName: data.creatorName || undefined,
          youtubeVideoId: data.youtubeVideoId,
          sourceVideoId: data.sourceVideoId || undefined,
          title: data.title,
          description: data.description,
          thumbnail: data.thumbnail,
          durationSeconds: data.durationSeconds || 60,
          clipStartTime: data.clipStartTime,
          clipEndTime: data.clipEndTime,
          cropOffsetX: data.cropOffsetX ?? 0.0,
        },
        create: {
          id: `sc_${data.youtubeVideoId}`,
          userId: data.userId || null,
          userEmail: data.userEmail || null,
          creatorName: data.creatorName || null,
          youtubeVideoId: data.youtubeVideoId,
          sourceVideoId: data.sourceVideoId || null,
          title: data.title,
          description: data.description,
          thumbnail: data.thumbnail,
          durationSeconds: data.durationSeconds || 60,
          clipStartTime: data.clipStartTime,
          clipEndTime: data.clipEndTime,
          cropOffsetX: data.cropOffsetX ?? 0.0,
        },
      });
    } catch (e: any) {
      this.logger.warn(`recordCreation notice: ${e.message}`);
      return null;
    }
  }

  async getMyCreations(userId?: string, email?: string) {
    if (!userId && !email) {
      return [];
    }

    const orConditions: any[] = [];
    if (userId) {
      orConditions.push({ userId }, { creatorUserId: userId });
    }
    if (email) {
      orConditions.push({ userEmail: email }, { creatorEmail: email });
    }

    try {
      // 1. Fetch from ShortCreation table
      const creations = await (this.prisma as any).shortCreation.findMany({
        where: {
          OR: orConditions,
        },
        orderBy: { createdAt: 'desc' },
      }).catch(() => []);

      // 2. Also fetch from Video table where type = SHORT
      const videos = await this.prisma.video.findMany({
        where: {
          type: 'SHORT',
          OR: orConditions,
        },
        orderBy: { createdAt: 'desc' },
      }).catch(() => []);

      // Deduplicate by YouTube Video ID
      const map = new Map<string, any>();

      for (const c of creations) {
        map.set(c.youtubeVideoId, {
          id: c.youtubeVideoId,
          title: c.title,
          description: c.description || '',
          thumbnailUrl: c.thumbnail || `https://img.youtube.com/vi/${c.youtubeVideoId}/hqdefault.jpg`,
          durationSeconds: c.durationSeconds || 60,
          sourceVideoId: c.sourceVideoId,
          clipStartTime: c.clipStartTime,
          clipEndTime: c.clipEndTime,
          cropOffsetX: c.cropOffsetX ?? 0.0,
          creatorName: c.creatorName,
          creatorEmail: c.userEmail,
          publishedAt: c.createdAt ? new Date(c.createdAt).toISOString() : new Date().toISOString(),
          isPublished: true,
        });
      }

      for (const v of videos) {
        if (!map.has(v.id)) {
          map.set(v.id, {
            id: v.id,
            title: v.title,
            description: v.description,
            thumbnailUrl: v.thumbnail,
            durationSeconds: 60,
            sourceVideoId: v.sourceVideoId,
            clipStartTime: v.clipStartTime,
            clipEndTime: v.clipEndTime,
            cropOffsetX: v.cropOffsetX ?? 0.0,
            creatorName: v.creatorName,
            creatorEmail: v.creatorEmail,
            publishedAt: v.publishedAt ? new Date(v.publishedAt).toISOString() : new Date().toISOString(),
            isPublished: true,
          });
        }
      }

      return Array.from(map.values());
    } catch (e: any) {
      this.logger.error(`getMyCreations error: ${e.message}`);
      return [];
    }
  }

  async cleanupLegacyShorts() {
    try {
      // 1. Delete any mock / virtual shorts with synthetic IDs
      const deletedVideos = await this.prisma.video.deleteMany({
        where: {
          OR: [
            { id: { startsWith: 'short_' } },
            { id: { startsWith: 'mock_' } },
            { id: { startsWith: 'local_' } },
            { type: 'SHORT', channelId: { startsWith: 'UC_ChristianTube' } },
          ],
        },
      });

      // 2. Delete any mock creations
      const deletedCreations = await (this.prisma as any).shortCreation.deleteMany({
        where: {
          OR: [
            { youtubeVideoId: { startsWith: 'short_' } },
            { youtubeVideoId: { startsWith: 'mock_' } },
            { youtubeVideoId: { startsWith: 'local_' } },
          ],
        },
      }).catch(() => ({ count: 0 }));

      this.logger.log(`🧹 Cleaned up legacy/mock shorts: ${deletedVideos.count} videos, ${deletedCreations.count} creations.`);
      return {
        success: true,
        deletedVideos: deletedVideos.count,
        deletedCreations: deletedCreations.count,
        message: 'All virtual/mock shorts removed from database. Feed now exclusively serves authentic YouTube shorts.',
      };
    } catch (e: any) {
      this.logger.error(`cleanupLegacyShorts error: ${e.message}`);
      return { success: false, error: e.message };
    }
  }
}
