import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { SyncService } from '../sync/sync.service';
export declare class ChannelsService {
    private readonly prisma;
    private readonly configService;
    private readonly syncService;
    private readonly logger;
    constructor(prisma: PrismaService, configService: ConfigService, syncService: SyncService);
    findAll(): Promise<{
        videoCount: number;
        _count: {
            videos: number;
        };
        id: string;
        name: string;
        description: string | null;
        thumbnail: string | null;
        subscriberCount: string | null;
        category: string | null;
        language: string | null;
        isActive: boolean;
        syncCursor: string | null;
        syncStatus: string;
        lastSyncedAt: Date | null;
        createdAt: Date;
        updatedAt: Date;
    }[]>;
    findOne(id: string): Promise<{
        videoCount: number;
        _count: {
            videos: number;
        };
        id: string;
        name: string;
        description: string | null;
        thumbnail: string | null;
        subscriberCount: string | null;
        category: string | null;
        language: string | null;
        isActive: boolean;
        syncCursor: string | null;
        syncStatus: string;
        lastSyncedAt: Date | null;
        createdAt: Date;
        updatedAt: Date;
    }>;
    resolveChannelInfo(input: string): Promise<{
        id: string;
        name: string;
        thumbnail: string | null;
        description: string | null;
        subscriberCount: string | null;
        handle?: string | null;
    } | null>;
    searchYouTube(query: string): Promise<any[]>;
    addChannel(data: {
        channelUrl: string;
        name?: string;
        category?: string;
        language?: string;
        adminEmail?: string;
    }): Promise<{
        status: string;
        message: string;
        channel: {
            id: string;
            name: string;
            description: string | null;
            thumbnail: string | null;
            subscriberCount: string | null;
            category: string | null;
            language: string | null;
            isActive: boolean;
            syncCursor: string | null;
            syncStatus: string;
            lastSyncedAt: Date | null;
            createdAt: Date;
            updatedAt: Date;
        };
    }>;
    syncChannel(id: string): Promise<{
        status: string;
        message: string;
    }>;
    removeChannel(id: string): Promise<{
        status: string;
        message: string;
        channel: {
            id: string;
            name: string;
            description: string | null;
            thumbnail: string | null;
            subscriberCount: string | null;
            category: string | null;
            language: string | null;
            isActive: boolean;
            syncCursor: string | null;
            syncStatus: string;
            lastSyncedAt: Date | null;
            createdAt: Date;
            updatedAt: Date;
        };
    }>;
    listRequests(): Promise<{
        id: string;
        createdAt: Date;
        updatedAt: Date;
        channelUrl: string;
        notes: string | null;
        status: string;
        submittedBy: string | null;
    }[]>;
    createRequest(data: {
        channelUrl: string;
        notes?: string;
        submittedBy?: string;
    }): Promise<{
        id: string;
        createdAt: Date;
        updatedAt: Date;
        channelUrl: string;
        notes: string | null;
        status: string;
        submittedBy: string | null;
    }>;
    approveRequest(id: string, adminEmail?: string): Promise<{
        status: string;
        message: string;
        request: {
            id: string;
            createdAt: Date;
            updatedAt: Date;
            channelUrl: string;
            notes: string | null;
            status: string;
            submittedBy: string | null;
        };
        channel: {
            id: string;
            name: string;
            description: string | null;
            thumbnail: string | null;
            subscriberCount: string | null;
            category: string | null;
            language: string | null;
            isActive: boolean;
            syncCursor: string | null;
            syncStatus: string;
            lastSyncedAt: Date | null;
            createdAt: Date;
            updatedAt: Date;
        };
    }>;
    rejectRequest(id: string, reason?: string): Promise<{
        status: string;
        message: string;
        request: {
            id: string;
            createdAt: Date;
            updatedAt: Date;
            channelUrl: string;
            notes: string | null;
            status: string;
            submittedBy: string | null;
        };
    }>;
}
