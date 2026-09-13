import { CreateFeedbackDto, FeedbackService } from './feedback.service';
export declare class FeedbackController {
    private readonly feedbackService;
    constructor(feedbackService: FeedbackService);
    submitFeedback(dto: CreateFeedbackDto): Promise<{
        success: boolean;
        issueNumber?: number;
        issueUrl?: string;
        message?: string;
    }>;
}
