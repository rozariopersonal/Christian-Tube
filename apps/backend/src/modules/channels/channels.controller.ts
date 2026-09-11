import { Body, Controller, Delete, Get, Param, Post, Query, UseGuards } from '@nestjs/common';
import { AdminGuard } from '../../guards/admin.guard';
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

  @UseGuards(AdminGuard)
  @Get('requests')
  async listChannelRequests() {
    return this.channelsService.listRequests();
  }

  @Get(':id')
  async getChannel(@Param('id') id: string) {
    return this.channelsService.findOne(id);
  }

  @UseGuards(AdminGuard)
  @Post()
  async addChannel(
    @Body() body: { channelUrl: string; name?: string; category?: string; language?: string },
  ) {
    return this.channelsService.addChannel(body);
  }

  @UseGuards(AdminGuard)
  @Delete(':id')
  async removeChannel(@Param('id') id: string) {
    return this.channelsService.removeChannel(id);
  }

  @UseGuards(AdminGuard)
  @Post(':id/sync')
  async syncChannel(@Param('id') id: string) {
    return this.channelsService.syncChannel(id);
  }

  @Post('request')
  async submitChannelRequest(
    @Body() body: { channelUrl: string; notes?: string; submittedBy?: string },
  ) {
    return this.channelsService.createRequest(body);
  }

  @UseGuards(AdminGuard)
  @Post('requests/:id/approve')
  async approveChannelRequest(
    @Param('id') id: string,
    @Body() body: { adminEmail?: string },
  ) {
    return this.channelsService.approveRequest(id, body?.adminEmail);
  }

  @UseGuards(AdminGuard)
  @Post('requests/:id/reject')
  async rejectChannelRequest(
    @Param('id') id: string,
    @Body() body: { reason?: string },
  ) {
    return this.channelsService.rejectRequest(id, body?.reason);
  }
}