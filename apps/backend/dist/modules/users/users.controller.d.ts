import { CurrentUser as CurrentUserType } from '../../guards/current-user.decorator';
import { UsersService } from './users.service';
export declare class UsersController {
    private readonly usersService;
    constructor(usersService: UsersService);
    syncUser(body: {
        id: string;
        email: string;
        displayName?: string;
        photoUrl?: string;
    }): Promise<{
        id: string;
        createdAt: Date;
        updatedAt: Date;
        email: string;
        displayName: string | null;
        photoUrl: string | null;
        isBlocked: boolean;
        role: string;
        lastLoginAt: Date;
    }>;
    savePlayback(user: CurrentUserType, body: any): Promise<{
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
    getPlayback(user: CurrentUserType, mediaType?: string): Promise<any>;
    getUsers(search?: string): Promise<{
        id: string;
        createdAt: Date;
        updatedAt: Date;
        email: string;
        displayName: string | null;
        photoUrl: string | null;
        isBlocked: boolean;
        role: string;
        lastLoginAt: Date;
    }[]>;
    getUser(id: string): Promise<{
        id: string;
        createdAt: Date;
        updatedAt: Date;
        email: string;
        displayName: string | null;
        photoUrl: string | null;
        isBlocked: boolean;
        role: string;
        lastLoginAt: Date;
    }>;
    blockUser(id: string): Promise<{
        id: string;
        createdAt: Date;
        updatedAt: Date;
        email: string;
        displayName: string | null;
        photoUrl: string | null;
        isBlocked: boolean;
        role: string;
        lastLoginAt: Date;
    }>;
    unblockUser(id: string): Promise<{
        id: string;
        createdAt: Date;
        updatedAt: Date;
        email: string;
        displayName: string | null;
        photoUrl: string | null;
        isBlocked: boolean;
        role: string;
        lastLoginAt: Date;
    }>;
    toggleBlock(id: string): Promise<{
        id: string;
        createdAt: Date;
        updatedAt: Date;
        email: string;
        displayName: string | null;
        photoUrl: string | null;
        isBlocked: boolean;
        role: string;
        lastLoginAt: Date;
    }>;
}
