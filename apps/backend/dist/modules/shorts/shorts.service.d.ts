import { ConfigService } from '@nestjs/config';
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
    userId?: string;
    userEmail?: string;
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
export declare class ShortsService {
    private readonly configService;
    private readonly prisma;
    private readonly logger;
    constructor(configService: ConfigService, prisma: PrismaService);
    private getTodayUtcDateString;
    getQuotaStatus(): Promise<QuotaStatusResponse>;
    initiateUploadSession(dto: InitiateUploadDto): Promise<{
        allowed: boolean;
        reason: string;
        message: string;
        nextRetryAfterHours: number;
        retryAt: string;
        uploadUrl?: undefined;
        title?: undefined;
        customChannelId?: undefined;
        metadata?: undefined;
    } | {
        allowed: boolean;
        uploadUrl: any;
        title: string;
        customChannelId: any;
        metadata: {
            creatorUserId: string;
            creatorName: string;
            creatorEmail: string;
            sourceVideoId: string;
            startTime: number;
            endTime: number;
            cropOffsetX: number;
            clippedAt: string;
        };
        reason?: undefined;
        message?: undefined;
        nextRetryAfterHours?: undefined;
        retryAt?: undefined;
    }>;
    recordCreation(data: {
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
    }): Promise<{
        id: string;
        youtubeVideoId: string;
        userId: string | null;
        userEmail: string | null;
        creatorName: string | null;
        sourceVideoId: string | null;
        title: string;
        description: string | null;
        thumbnail: string | null;
        durationSeconds: number | null;
        clipStartTime: number | null;
        clipEndTime: number | null;
        cropOffsetX: number | null;
        createdAt: Date;
        updatedAt: Date;
    }>;
    getMyCreations(userId?: string, email?: string): Promise<any[]>;
    cleanupLegacyShorts(): Promise<{
        success: boolean;
        deletedVideos: number;
        deletedCreations: any;
        message: string;
        error?: undefined;
    } | {
        success: boolean;
        error: any;
        deletedVideos?: undefined;
        deletedCreations?: undefined;
        message?: undefined;
    }>;
}
