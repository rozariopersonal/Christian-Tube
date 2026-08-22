import { Body, Controller, Get, Post } from '@nestjs/common';
import { ChannelsService } from './channels.service';

@Controller(['channels', 'api/channels'])
export class ChannelsController {
  constructor(private readonly channelsService: ChannelsService) {}

  @Get()
  async getChannels() {
    return this.channelsService.findAll();
  }

  @Post()
  async addChannel(
    @Body() body: { channelUrl: string; name?: string; category?: string; language?: string },
  ) {
    return this.channelsService.addChannel(body);
  }

  @Post('request')
  async submitChannelRequest(
    @Body() body: { channelUrl: string; notes?: string; submittedBy?: string },
  ) {
    return this.channelsService.createRequest(body);
  }
}
