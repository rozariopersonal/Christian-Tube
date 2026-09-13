import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

export interface CreateFeedbackDto {
  title: string;
  body: string;
  screenContext?: string;
  route?: string;
  diagnostics?: Record<string, any>;
  rawText?: string;
}

@Injectable()
export class FeedbackService {
  private readonly logger = new Logger(FeedbackService.name);

  constructor(private readonly configService: ConfigService) {}

  async submitFeedback(dto: CreateFeedbackDto): Promise<{
    success: boolean;
    issueNumber?: number;
    issueUrl?: string;
    message?: string;
  }> {
    const token =
      process.env.GITHUB_FEEDBACK_TOKEN ||
      process.env.GITHUB_TOKEN ||
      this.configService.get<string>('githubFeedbackToken');

    const repo =
      process.env.GITHUB_REPO ||
      this.configService.get<string>('githubRepo') ||
      'rozariopersonal/Christian-Tube';

    if (!token) {
      this.logger.warn(
        'GITHUB_FEEDBACK_TOKEN is not configured. Feedback recorded in server logs:',
      );
      this.logger.log(`[Feedback - ${dto.screenContext || 'General'}] ${dto.title}`);
      this.logger.log(dto.body);

      return {
        success: true,
        message: 'Feedback received and recorded (token not set).',
      };
    }

    try {
      const response = await fetch(`https://api.github.com/repos/${repo}/issues`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: 'application/vnd.github+json',
          'Content-Type': 'application/json',
          'User-Agent': 'ChristianApp-Backend',
        },
        body: JSON.stringify({
          title: dto.title,
          body: dto.body,
          labels: ['user-feedback'],
        }),
      });

      if (!response.ok) {
        const errText = await response.text();
        this.logger.error(`GitHub API error (${response.status}): ${errText}`);
        return {
          success: false,
          message: `GitHub API error: ${response.status}`,
        };
      }

      const issueData = await response.json();
      this.logger.log(`Created GitHub Issue #${issueData.number}: ${issueData.html_url}`);

      return {
        success: true,
        issueNumber: issueData.number,
        issueUrl: issueData.html_url,
      };
    } catch (err: any) {
      this.logger.error(`Failed to post issue to GitHub: ${err.message}`, err.stack);
      return {
        success: false,
        message: err.message || 'Failed to communicate with GitHub',
      };
    }
  }
}
