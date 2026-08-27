import { Body, Controller, Delete, Get, Param, Post, Query } from '@nestjs/common';
import { ChannelsService } from './channels.service';

@Controller(['channels', 'api/channels'])
export class ChannelsController {
  constructor(private readonly channelsService: ChannelsService) {}

  @Get()
  async getChannels() {
    return this.channelsService.findAll();
  }

  @Get('check-admin')
  async checkAdmin(@Query('email') email: string) {
    const isAdmin = this.channelsService.isAdmin(email);
    return { email, isAdmin };
  }

  @Get('search-youtube')
  async searchYouTube(@Query('q') q: string) {
    return this.channelsService.searchYouTube(q);
  }

  @Post()
  async addChannel(
    @Body() body: { channelUrl: string; name?: string; category?: string; language?: string; adminEmail?: string },
  ) {
    return this.channelsService.addChannel(body);
  }

  @Delete(':id')
  async removeChannel(@Param('id') id: string) {
    return this.channelsService.removeChannel(id);
  }

  @Post(':id/sync')
  async syncChannel(@Param('id') id: string) {
    return this.channelsService.syncChannel(id);
  }

  @Get('requests')
  async listChannelRequests() {
    return this.channelsService.listRequests();
  }

  @Post('request')
  async submitChannelRequest(
    @Body() body: { channelUrl: string; notes?: string; submittedBy?: string },
  ) {
    return this.channelsService.createRequest(body);
  }

  @Post('requests/:id/approve')
  async approveChannelRequest(
    @Param('id') id: string,
    @Body() body: { adminEmail?: string },
  ) {
    return this.channelsService.approveRequest(id, body?.adminEmail);
  }

  @Post('requests/:id/reject')
  async rejectChannelRequest(
    @Param('id') id: string,
    @Body() body: { reason?: string },
  ) {
    return this.channelsService.rejectRequest(id, body?.reason);
  }
}
