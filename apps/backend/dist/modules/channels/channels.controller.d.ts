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
    checkAdmin(email: string): Promise<{
        email: string;
        isAdmin: boolean;
    }>;
    searchYouTube(q: string): Promise<any[]>;
    listChannelRequests(): Promise<{
        id: string;
        createdAt: Date;
        updatedAt: Date;
        channelUrl: string;
        notes: string | null;
        status: string;
        submittedBy: string | null;
    }[]>;
    getChannel(id: string): Promise<{
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
    syncChannel(id: string): Promise<{
        status: string;
        message: string;
    }>;
    submitChannelRequest(body: {
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
    approveChannelRequest(id: string, body: {
        adminEmail?: string;
    }): Promise<{
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
    rejectChannelRequest(id: string, body: {
        reason?: string;
    }): Promise<{
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
