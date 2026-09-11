export interface ScriptureCitation {
    book?: string;
    chapter?: number;
    verse?: number;
}
export interface VideoChapter {
    title: string;
    seconds: number;
    timestamp: string;
}
export interface ExtractedVideoMetadata {
    speaker?: string;
    language?: string;
    secondaryLanguage?: string;
    cleanTitle?: string;
    subSeries?: string;
    partNumber?: number;
    meetingType?: string;
    location?: string;
    targetAudience?: string;
    topics?: string[];
    scripture?: ScriptureCitation;
    chapters?: VideoChapter[];
}
export interface MetadataExtractorInput {
    title: string;
    description?: string;
    channelTitle?: string;
    tags?: string[];
}
export declare function romanToDecimal(roman: string): number;
export declare function extractVideoMetadata(input: MetadataExtractorInput): ExtractedVideoMetadata;
