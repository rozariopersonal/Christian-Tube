import { ConfigService } from '@nestjs/config';
export interface ExtractedVideo {
    videoId: string;
    title: string;
    thumbnail: string;
    duration?: string;
    durationSeconds?: number;
    viewCount?: number;
    publishedAt?: Date;
    videoType: 'VIDEO' | 'SHORT';
}
export declare function parseIsoDurationSeconds(duration: string): number;
export declare function parseIsoDuration(duration: string): string;
export declare function parseTextDurationToSeconds(text: string): number;
export declare function parseRelativeTimeToDate(text: string): Date | null;
export declare function parseViewsTextToNumber(text: string): number;
export declare class YoutubeService {
    private readonly configService;
    private readonly logger;
    private readonly apiKey;
    constructor(configService: ConfigService);
    hasApiKey(): boolean;
    parseIsoDuration(duration: string): string;
    parseIsoDurationSeconds(duration: string): number;
    fetchChannelMetadata(channelId: string): Promise<{
        title: any;
        thumbnail: any;
        description: any;
        subscriberCount: string;
    }>;
    fetchPlaylistItems(playlistId: string, pageToken?: string): Promise<{
        items: any;
        nextPageToken: any;
    }>;
    fetchVideosDetails(videoIds: string[]): Promise<Map<string, any>>;
    scrapeChannelVideosTab(channelId: string, maxBatches?: number): Promise<{
        videos: ExtractedVideo[];
    }>;
    scrapeChannelShortsTab(channelId: string, maxBatches?: number): Promise<{
        videos: ExtractedVideo[];
    }>;
    scrapeChannelStreamsTab(channelId: string, maxBatches?: number): Promise<{
        videos: ExtractedVideo[];
    }>;
    scrapeRssFeed(channelId: string): Promise<ExtractedVideo[]>;
    subscribeChannelToWebSub(channelId: string, mode?: 'subscribe' | 'unsubscribe'): Promise<boolean>;
}
