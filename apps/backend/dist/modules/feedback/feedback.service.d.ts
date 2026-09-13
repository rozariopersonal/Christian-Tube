import { ConfigService } from '@nestjs/config';
export interface CreateFeedbackDto {
    title: string;
    body: string;
    screenContext?: string;
    route?: string;
    diagnostics?: Record<string, any>;
    rawText?: string;
}
export declare class FeedbackService {
    private readonly configService;
    private readonly logger;
    constructor(configService: ConfigService);
    submitFeedback(dto: CreateFeedbackDto): Promise<{
        success: boolean;
        issueNumber?: number;
        issueUrl?: string;
        message?: string;
    }>;
}
