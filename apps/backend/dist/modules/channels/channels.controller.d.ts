import { ChannelsService } from './channels.service';
export declare class ChannelsController {
    private readonly channelsService;
    constructor(channelsService: ChannelsService);
    getChannels(): Promise<{
        videoCount: number;
        _count: {
            videos: number;
        };
        id: string;
        description: string | null;
        thumbnail: string | null;
        createdAt: Date;
        updatedAt: Date;
        name: string;
        subscriberCount: string | null;
        category: string | null;
        language: string | null;
        isActive: boolean;
        syncCursor: string | null;
        syncStatus: string;
        lastSyncedAt: Date | null;
    }[]>;
    getChannel(id: string): Promise<{
        videoCount: number;
        _count: {
            videos: number;
        };
        id: string;
        description: string | null;
        thumbnail: string | null;
        createdAt: Date;
        updatedAt: Date;
        name: string;
        subscriberCount: string | null;
        category: string | null;
        language: string | null;
        isActive: boolean;
        syncCursor: string | null;
        syncStatus: string;
        lastSyncedAt: Date | null;
    }>;
    searchYouTube(q: string): Promise<any[]>;
    addChannel(body: {
        channelUrl: string;
        name?: string;
        category?: string;
        language?: string;
    }): Promise<{
        status: string;
        message: string;
        channel: {
            id: string;
            description: string | null;
            thumbnail: string | null;
            createdAt: Date;
            updatedAt: Date;
            name: string;
            subscriberCount: string | null;
            category: string | null;
            language: string | null;
            isActive: boolean;
            syncCursor: string | null;
            syncStatus: string;
            lastSyncedAt: Date | null;
        };
    }>;
    removeChannel(id: string): Promise<{
        status: string;
        message: string;
        channel: {
            id: string;
            description: string | null;
            thumbnail: string | null;
            createdAt: Date;
            updatedAt: Date;
            name: string;
            subscriberCount: string | null;
            category: string | null;
            language: string | null;
            isActive: boolean;
            syncCursor: string | null;
            syncStatus: string;
            lastSyncedAt: Date | null;
        };
    }>;
    syncChannel(id: string): Promise<{
        status: string;
        message: string;
    }>;
    listChannelRequests(): Promise<{
        status: string;
        id: string;
        createdAt: Date;
        updatedAt: Date;
        channelUrl: string;
        notes: string | null;
        submittedBy: string | null;
    }[]>;
    submitChannelRequest(body: {
        channelUrl: string;
        notes?: string;
        submittedBy?: string;
    }): Promise<{
        status: string;
        id: string;
        createdAt: Date;
        updatedAt: Date;
        channelUrl: string;
        notes: string | null;
        submittedBy: string | null;
    }>;
    approveChannelRequest(id: string, body: {
        adminEmail?: string;
    }): Promise<{
        status: string;
        message: string;
        request: {
            status: string;
            id: string;
            createdAt: Date;
            updatedAt: Date;
            channelUrl: string;
            notes: string | null;
            submittedBy: string | null;
        };
        channel: {
            id: string;
            description: string | null;
            thumbnail: string | null;
            createdAt: Date;
            updatedAt: Date;
            name: string;
            subscriberCount: string | null;
            category: string | null;
            language: string | null;
            isActive: boolean;
            syncCursor: string | null;
            syncStatus: string;
            lastSyncedAt: Date | null;
        };
    }>;
    rejectChannelRequest(id: string, body: {
        reason?: string;
    }): Promise<{
        status: string;
        message: string;
        request: {
            status: string;
            id: string;
            createdAt: Date;
            updatedAt: Date;
            channelUrl: string;
            notes: string | null;
            submittedBy: string | null;
        };
    }>;
}
