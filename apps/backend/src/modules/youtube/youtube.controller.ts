import { Controller, Post, Get, Headers, UnauthorizedException, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { YoutubeService } from './youtube.service';

@Controller('youtube')
export class YoutubeController {
  private readonly logger = new Logger(YoutubeController.name);

  constructor(
    private readonly youtubeService: YoutubeService,
    private readonly configService: ConfigService,
  ) {}

  @Get('sync')
  @Post('sync')
  async triggerSync(@Headers('x-job-secret') secret?: string) {
    const internalSecret = this.configService.get<string>('internalJobSecret');
    if (internalSecret && secret && secret !== internalSecret) {
      throw new UnauthorizedException('Invalid job secret');
    }

    this.logger.log('Manual YouTube sync triggered via API endpoint.');
    this.youtubeService.syncAllChannelsPeriodically().catch((e) => {
      this.logger.error(`Manual sync error: ${e.message}`);
    });

    return {
      status: 'accepted',
      message: 'Channel sync process initiated in background',
      timestamp: new Date().toISOString(),
    };
  }

  @Get('backfill')
  @Post('backfill')
  async triggerBackfill(@Headers('x-job-secret') secret?: string) {
    const internalSecret = this.configService.get<string>('internalJobSecret');
    if (internalSecret && secret && secret !== internalSecret) {
      throw new UnauthorizedException('Invalid job secret');
    }

    this.logger.log('Manual YouTube metadata backfill triggered via API endpoint.');
    this.youtubeService.backfillVideoMetadata(250).catch((e) => {
      this.logger.error(`Manual backfill error: ${e.message}`);
    });

    return {
      status: 'accepted',
      message: 'Video metadata backfill process initiated in background',
      timestamp: new Date().toISOString(),
    };
  }
}
