import { ConfigService } from '@nestjs/config';
import { Response } from 'express';
import { SyncService } from './sync.service';
export declare class SyncController {
    private readonly syncService;
    private readonly configService;
    private readonly logger;
    constructor(syncService: SyncService, configService: ConfigService);
    verifyWebSubSubscription(mode?: string, challenge?: string, topic?: string, res?: Response): string | Response<any, Record<string, any>>;
    handleWebSubPush(req: any, body: any, res: Response): Promise<Response<any, Record<string, any>>>;
    triggerSync(secret?: string): Promise<{
        status: string;
        message: string;
        timestamp: string;
    }>;
    triggerChannelSync(id: string): Promise<{
        status: string;
        message: string;
        timestamp: string;
    }>;
    triggerVideoSync(id: string): Promise<{
        status: string;
        video: {
            id: string;
            createdAt: Date;
            updatedAt: Date;
            channelName: string;
            description: string;
            title: string;
            type: import(".prisma/client").$Enums.VideoType;
            thumbnail: string;
            channelId: string;
            channelThumbnail: string | null;
            channelSubscriberCount: string | null;
            publishedAt: Date;
            duration: string;
            viewCount: number;
            tags: string[];
            category: string | null;
            transcriptionStatus: import(".prisma/client").$Enums.TranscriptionStatus;
            transcriptionProgress: number | null;
            transcriptionRetryCount: number;
            transcriptionDetail: import("@prisma/client/runtime/library").JsonValue | null;
            lastTranscriptionError: string | null;
            content: string | null;
            creatorUserId: string | null;
            creatorName: string | null;
            creatorEmail: string | null;
            sourceVideoId: string | null;
            clipStartTime: number | null;
            clipEndTime: number | null;
            cropOffsetX: number | null;
            clippedAt: Date | null;
        };
        timestamp: string;
    }>;
    triggerBackfill(secret?: string): Promise<{
        status: string;
        message: string;
        timestamp: string;
    }>;
}
