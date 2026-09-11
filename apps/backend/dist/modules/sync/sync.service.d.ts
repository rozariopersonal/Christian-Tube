import { OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { YoutubeService } from '../youtube/youtube.service';
export declare class SyncService implements OnModuleInit {
    private readonly configService;
    private readonly prisma;
    private readonly youtubeService;
    private readonly logger;
    private isSyncing;
    constructor(configService: ConfigService, prisma: PrismaService, youtubeService: YoutubeService);
    private sleep;
    onModuleInit(): Promise<void>;
    scheduledSync(): Promise<{
        status: string;
        message: string;
        count?: undefined;
        channelCount?: undefined;
    } | {
        status: string;
        count: number;
        message?: undefined;
        channelCount?: undefined;
    } | {
        status: string;
        channelCount: number;
        message?: undefined;
        count?: undefined;
    }>;
    syncAllChannels(force?: boolean): Promise<{
        status: string;
        message: string;
        count?: undefined;
        channelCount?: undefined;
    } | {
        status: string;
        count: number;
        message?: undefined;
        channelCount?: undefined;
    } | {
        status: string;
        channelCount: number;
        message?: undefined;
        count?: undefined;
    }>;
    syncChannel(channelId: string, defaultCategory?: string | null): Promise<void>;
    private syncViaPlaylistApi;
    private syncViaWebScraper;
    private upsertScrapedVideo;
    refreshChannelMetadata(channelId: string): Promise<{
        id: string;
        createdAt: Date;
        updatedAt: Date;
        name: string;
        description: string | null;
        thumbnail: string | null;
        category: string | null;
        subscriberCount: string | null;
        language: string | null;
        isActive: boolean;
        syncCursor: string | null;
        syncStatus: string;
        lastSyncedAt: Date | null;
    }>;
    subscribeChannelToWebSub(channelId: string, mode?: 'subscribe' | 'unsubscribe'): Promise<boolean>;
    renewAllWebSubSubscriptions(): Promise<void>;
    handleWebSubPushNotification(xmlBody: string): Promise<void>;
    backfillVideoMetadata(batchSize?: number): Promise<void>;
    syncSingleVideo(videoId: string): Promise<{
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
    }>;
}
