import { Body, Controller, Post, HttpException, HttpStatus } from '@nestjs/common';
import { CreateFeedbackDto, FeedbackService } from './feedback.service';

@Controller('api/feedback')
export class FeedbackController {
  constructor(private readonly feedbackService: FeedbackService) {}

  @Post()
  async submitFeedback(@Body() dto: CreateFeedbackDto) {
    const result = await this.feedbackService.submitFeedback(dto);
    if (!result.success) {
      throw new HttpException(
        result.message || 'Failed to submit feedback',
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }
    return result;
  }
}
