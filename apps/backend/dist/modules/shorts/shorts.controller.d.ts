import { CurrentUser as CurrentUserType } from '../../guards/current-user.decorator';
import { ShortsService, InitiateUploadDto } from './shorts.service';
export declare class ShortsController {
    private readonly shortsService;
    constructor(shortsService: ShortsService);
    getQuotaStatus(): Promise<import("./shorts.service").QuotaStatusResponse>;
    initiateUpload(user: CurrentUserType, dto: InitiateUploadDto): Promise<{
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
    getMyCreations(user: CurrentUserType): Promise<any[]>;
    recordCreation(user: CurrentUserType, data: any): Promise<{
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
