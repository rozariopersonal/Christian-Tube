import {
  Controller,
  Post,
  Get,
  Headers,
  Query,
  Body,
  Req,
  Res,
  UnauthorizedException,
  Logger,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Response } from 'express';
import { YoutubeService } from './youtube.service';

@Controller(['youtube', 'api/youtube'])
export class YoutubeController {
  private readonly logger = new Logger(YoutubeController.name);

  constructor(
    private readonly youtubeService: YoutubeService,
    private readonly configService: ConfigService,
  ) {}

  /**
   * Google WebSub Verification Handshake (GET)
   * Google's Hub sends hub.challenge to verify callback URL ownership
   */
  @Get(['webhook', 'webhooks'])
  verifyWebSubSubscription(
    @Query('hub.mode') mode?: string,
    @Query('hub.challenge') challenge?: string,
    @Query('hub.topic') topic?: string,
    @Res() res?: Response,
  ) {
    this.logger.log(`Google WebSub verification challenge received (mode: ${mode}, topic: ${topic})`);
    if (challenge && res) {
      return res.status(200).send(challenge);
    }
    return res ? res.status(200).send('OK') : challenge || 'OK';
  }

  /**
   * Google WebSub Real-Time Push Notification (POST)
   * Triggered in 1-5 seconds whenever a channel publishes a new sermon or Short
   */
  @Post(['webhook', 'webhooks'])
  async handleWebSubPush(
    @Req() req: any,
    @Body() body: any,
    @Res() res: Response,
  ) {
    const rawXml = typeof body === 'string' ? body : (req.rawBody || JSON.stringify(body));
    this.logger.log('Incoming Google WebSub real-time video push notification received.');

    // Process notification asynchronously so Google Hub gets instant HTTP 200/204
    this.youtubeService.handleWebSubPushNotification(rawXml).catch((err) => {
      this.logger.error(`Error processing WebSub push notification: ${err.message}`);
    });

    return res.status(204).send();
  }

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
