import { Injectable, Logger, BadRequestException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';

export interface InitiateUploadDto {
  title: string;
  description?: string;
  sourceVideoId?: string;
  clipStartTime?: number;
  clipEndTime?: number;
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
      creatorName: dto.creatorName || 'Anonymous',
      creatorEmail: dto.creatorEmail || '',
      sourceVideoId: dto.sourceVideoId || null,
      startTime: dto.clipStartTime || 0,
      endTime: dto.clipEndTime || 0,
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
        const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({
            client_id: clientId,
            client_secret: clientSecret,
            refresh_token: refreshToken,
            grant_type: 'refresh_token',
          }),
        });

        const tokenData = await tokenResponse.json();
        if (!tokenResponse.ok || !tokenData.access_token) {
          throw new Error(tokenData.error_description || 'Failed to refresh YouTube access token');
        }

        const accessToken = tokenData.access_token;

        const ytResponse = await fetch(
          'https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status',
          {
            method: 'POST',
            headers: {
              Authorization: `Bearer ${accessToken}`,
              'Content-Type': 'application/json; charset=UTF-8',
              'X-Upload-Content-Type': 'video/mp4',
            },
            body: JSON.stringify({
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
            }),
          },
        );

        const uploadUrl = ytResponse.headers.get('location');
        if (!uploadUrl) {
          const errorBody = await ytResponse.text();
          throw new Error(`YouTube did not return upload session URL: ${errorBody}`);
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
}
