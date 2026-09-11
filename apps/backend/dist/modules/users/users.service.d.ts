import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
export declare class UsersService {
    private readonly prisma;
    private readonly configService;
    private readonly logger;
    constructor(prisma: PrismaService, configService: ConfigService);
    isAdmin(email?: string): boolean;
    syncUser(data: {
        id: string;
        email: string;
        displayName?: string;
        photoUrl?: string;
    }): Promise<{
        id: string;
        email: string;
        displayName: string | null;
        photoUrl: string | null;
        isBlocked: boolean;
        role: string;
        lastLoginAt: Date;
        createdAt: Date;
        updatedAt: Date;
    }>;
    findAll(query?: {
        search?: string;
    }): Promise<{
        id: string;
        email: string;
        displayName: string | null;
        photoUrl: string | null;
        isBlocked: boolean;
        role: string;
        lastLoginAt: Date;
        createdAt: Date;
        updatedAt: Date;
    }[]>;
    findOne(id: string): Promise<{
        id: string;
        email: string;
        displayName: string | null;
        photoUrl: string | null;
        isBlocked: boolean;
        role: string;
        lastLoginAt: Date;
        createdAt: Date;
        updatedAt: Date;
    }>;
    toggleBlock(id: string): Promise<{
        id: string;
        email: string;
        displayName: string | null;
        photoUrl: string | null;
        isBlocked: boolean;
        role: string;
        lastLoginAt: Date;
        createdAt: Date;
        updatedAt: Date;
    }>;
    blockUser(id: string): Promise<{
        id: string;
        email: string;
        displayName: string | null;
        photoUrl: string | null;
        isBlocked: boolean;
        role: string;
        lastLoginAt: Date;
        createdAt: Date;
        updatedAt: Date;
    }>;
    unblockUser(id: string): Promise<{
        id: string;
        email: string;
        displayName: string | null;
        photoUrl: string | null;
        isBlocked: boolean;
        role: string;
        lastLoginAt: Date;
        createdAt: Date;
        updatedAt: Date;
    }>;
    private static playbackCache;
    savePlayback(data: {
        userId: string;
        userEmail?: string;
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
    }): Promise<{
        success: boolean;
        message: string;
        playback?: undefined;
    } | {
        success: boolean;
        playback: {
            userId: string;
            userEmail: string;
            deviceId: string;
            mediaType: string;
            trackId: string;
            seriesId: string;
            title: string;
            speaker: string;
            coverUrl: string;
            audioUrl: string;
            positionSeconds: number;
            durationSeconds: number;
            payloadJson: string;
            updatedAt: Date;
        };
        message?: undefined;
    }>;
    getPlayback(query: {
        userId?: string;
        userEmail?: string;
        mediaType?: string;
    }): Promise<any>;
}
