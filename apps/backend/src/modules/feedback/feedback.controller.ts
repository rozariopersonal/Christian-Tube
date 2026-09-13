import { Body, Controller, Post } from '@nestjs/common';
import { CreateFeedbackDto, FeedbackService } from './feedback.service';

@Controller('api/feedback')
export class FeedbackController {
  constructor(private readonly feedbackService: FeedbackService) {}

  @Post()
  async submitFeedback(@Body() dto: CreateFeedbackDto) {
    return this.feedbackService.submitFeedback(dto);
  }
}
