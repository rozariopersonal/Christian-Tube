import {
  Controller,
  Post,
  Get,
  Param,
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
import { SyncService } from './sync.service';

@Controller(['sync', 'youtube', 'api/sync', 'api/youtube'])
export class SyncController {
  private readonly logger = new Logger(SyncController.name);

  constructor(
    private readonly syncService: SyncService,
    private readonly configService: ConfigService,
  ) {}

  /**
   * Google WebSub Verification Handshake (GET)
   */
  @Get(['webhook', 'webhooks'])
  verifyWebSubSubscription(
    @Query('hub.mode') mode?: string,
    @Query('hub.challenge') challenge?: string,
    @Query('hub.topic') topic?: string,
    @Res() res?: Response,
  ) {
    this.logger.log(`Google WebSub verification challenge (mode: ${mode}, topic: ${topic})`);
    if (challenge && res) {
      return res.status(200).send(challenge);
    }
    return res ? res.status(200).send('OK') : challenge || 'OK';
  }

  /**
   * Google WebSub Real-Time Push Notification (POST)
   */
  @Post(['webhook', 'webhooks'])
  async handleWebSubPush(
    @Req() req: any,
    @Body() body: any,
    @Res() res: Response,
  ) {
    const rawXml = typeof body === 'string' ? body : (req.rawBody || JSON.stringify(body));
    this.logger.log('Incoming Google WebSub real-time video push notification received.');

    this.syncService.handleWebSubPushNotification(rawXml).catch((err) => {
      this.logger.error(`Error processing WebSub push: ${err.message}`);
    });

    return res.status(204).send();
  }

  /**
   * Check or toggle YouTube sync status at runtime
   */
  @Get('status')
  getSyncStatus() {
    return {
      enabled: this.syncService.isSyncEnabled(),
      envDefault: this.configService.get<boolean>('youtubeSyncEnabled') !== false,
      timestamp: new Date().toISOString(),
    };
  }

  @Post('toggle')
  toggleSync(
    @Headers('x-job-secret') secret?: string,
    @Query('enabled') enabledQuery?: string,
    @Body() body?: { enabled?: boolean },
  ) {
    const internalSecret = this.configService.get<string>('internalJobSecret');
    if (internalSecret && secret !== internalSecret) {
      throw new UnauthorizedException('Invalid job secret');
    }

    const nextEnabled =
      typeof body?.enabled === 'boolean'
        ? body.enabled
        : enabledQuery !== undefined
          ? enabledQuery === 'true'
          : !this.syncService.isSyncEnabled();

    this.syncService.setSyncEnabled(nextEnabled);
    return {
      enabled: this.syncService.isSyncEnabled(),
      timestamp: new Date().toISOString(),
    };
  }

  /**
   * Manual trigger to sync all channels
   */
  @Get(['', 'sync'])
  @Post(['', 'sync'])
  async triggerSync(
    @Headers('x-job-secret') secret?: string,
    @Query('force') force?: string,
  ) {
    const internalSecret = this.configService.get<string>('internalJobSecret');
    if (internalSecret && secret && secret !== internalSecret) {
      throw new UnauthorizedException('Invalid job secret');
    }

    const isForced = force === 'true';
    if (!isForced && !this.syncService.isSyncEnabled()) {
      return {
        status: 'disabled',
        message: 'YouTube sync is disabled in this environment. Pass ?force=true or POST /sync/toggle {"enabled":true} to enable.',
        timestamp: new Date().toISOString(),
      };
    }

    this.logger.log('Manual channel sync triggered via API endpoint.');
    this.syncService.syncAllChannels(true).catch((e) => {
      this.logger.error(`Manual sync error: ${e.message}`);
    });

    return {
      status: 'accepted',
      message: 'Channel sync process initiated in background',
      timestamp: new Date().toISOString(),
    };
  }

  /**
   * Manual trigger to sync a single channel
   */
  @Post('channel/:id')
  async triggerChannelSync(@Param('id') id: string, @Query('force') force?: string) {
    const isForced = force === 'true';
    if (!isForced && !this.syncService.isSyncEnabled()) {
      return {
        status: 'disabled',
        message: 'YouTube sync is disabled in this environment. Pass ?force=true or POST /sync/toggle {"enabled":true} to enable.',
        timestamp: new Date().toISOString(),
      };
    }

    this.logger.log(`Manual sync triggered for channel: ${id}`);
    this.syncService.syncChannel(id, undefined, true).catch((e) => {
      this.logger.error(`Single channel sync error: ${e.message}`);
    });

    return {
      status: 'accepted',
      message: `Sync process initiated for channel ${id}`,
      timestamp: new Date().toISOString(),
    };
  }

  /**
   * Manual trigger to sync a single newly uploaded video
   */
  @Post('video/:id')
  async triggerVideoSync(@Param('id') id: string, @Query('force') force?: string) {
    const isForced = force === 'true';
    if (!isForced && !this.syncService.isSyncEnabled()) {
      return {
        status: 'disabled',
        message: 'YouTube sync is disabled in this environment. Pass ?force=true or POST /sync/toggle {"enabled":true} to enable.',
        timestamp: new Date().toISOString(),
      };
    }

    this.logger.log(`Instant sync triggered for video: ${id}`);
    const video = await this.syncService.syncSingleVideo(id, true);

    return {
      status: video ? 'synced' : 'pending',
      video,
      timestamp: new Date().toISOString(),
    };
  }

  /**
   * Manual trigger for metadata backfill
   */
  @Get('backfill')
  @Post('backfill')
  async triggerBackfill(@Headers('x-job-secret') secret?: string) {
    const internalSecret = this.configService.get<string>('internalJobSecret');
    if (internalSecret && secret && secret !== internalSecret) {
      throw new UnauthorizedException('Invalid job secret');
    }

    this.logger.log('Manual metadata backfill triggered via API endpoint.');
    this.syncService.backfillVideoMetadata(250).catch((e) => {
      this.logger.error(`Manual backfill error: ${e.message}`);
    });

    return {
      status: 'accepted',
      message: 'Video metadata backfill process initiated in background',
      timestamp: new Date().toISOString(),
    };
  }
}
