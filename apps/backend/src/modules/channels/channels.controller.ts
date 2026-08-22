import { Body, Controller, Delete, Get, Param, Post, Query } from '@nestjs/common';
import { ChannelsService } from './channels.service';

@Controller(['channels', 'api/channels'])
export class ChannelsController {
  constructor(private readonly channelsService: ChannelsService) {}

  @Get()
  async getChannels() {
    return this.channelsService.findAll();
  }

  @Get('search-youtube')
  async searchYouTube(@Query('q') q: string) {
    return this.channelsService.searchYouTube(q);
  }

  @Post()
  async addChannel(
    @Body() body: { channelUrl: string; name?: string; category?: string; language?: string },
  ) {
    return this.channelsService.addChannel(body);
  }

  @Delete(':id')
  async removeChannel(@Param('id') id: string) {
    return this.channelsService.removeChannel(id);
  }

  @Post('request')
  async submitChannelRequest(
    @Body() body: { channelUrl: string; notes?: string; submittedBy?: string },
  ) {
    return this.channelsService.createRequest(body);
  }
}
