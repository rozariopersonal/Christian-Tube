import { Body, Controller, Delete, Get, Param, Post, Query, UseGuards } from '@nestjs/common';
import { AdminGuard } from '../../guards/admin.guard';
import { AuthGuard } from '../../guards/auth.guard';
import { OptionalAuthGuard } from '../../guards/optional-auth.guard';
import { CurrentUser, CurrentUser as CurrentUserType } from '../../guards/current-user.decorator';
import { ChannelsService } from './channels.service';

@Controller(['channels', 'api/channels'])
export class ChannelsController {
  constructor(private readonly channelsService: ChannelsService) {}

  @Get()
  async getChannels(@Query('type') type?: 'VIDEO' | 'SHORT' | 'ALL') {
    return this.channelsService.findAll(type);
  }

  @UseGuards(AdminGuard)
  @Get('admin/all')
  async getAdminChannels() {
    return this.channelsService.findAllAdmin();
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

  @UseGuards(AuthGuard)
  @Get('subscriptions')
  async getSubscriptions(@CurrentUser() user: CurrentUserType) {
    return this.channelsService.listSubscriptions(user.userId);
  }

  @UseGuards(AuthGuard)
  @Post(':id/subscribe')
  async subscribe(
    @CurrentUser() user: CurrentUserType,
    @Param('id') id: string,
    @Body() body?: { clientUpdatedAt?: number | string },
  ) {
    return this.channelsService.subscribe(user, id, body?.clientUpdatedAt);
  }

  @UseGuards(AuthGuard)
  @Delete(':id/subscribe')
  async unsubscribe(
    @CurrentUser() user: CurrentUserType,
    @Param('id') id: string,
    @Query('clientUpdatedAt') clientUpdatedAt?: string,
  ) {
    return this.channelsService.unsubscribe(user.userId, id, clientUpdatedAt);
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
  @Post(':id/suspend')
  async suspendChannel(@Param('id') id: string) {
    return this.channelsService.setChannelActive(id, false);
  }

  @UseGuards(AdminGuard)
  @Post(':id/activate')
  async activateChannel(@Param('id') id: string) {
    return this.channelsService.setChannelActive(id, true);
  }

  @UseGuards(AdminGuard)
  @Post(':id/toggle-active')
  async toggleChannelActive(@Param('id') id: string) {
    return this.channelsService.toggleChannelActive(id);
  }

  @UseGuards(AdminGuard)
  @Post(':id/sync')
  async syncChannel(@Param('id') id: string) {
    return this.channelsService.syncChannel(id);
  }

  @UseGuards(OptionalAuthGuard)
  @Post('request')
  async submitChannelRequest(
    @Body() body: { channelUrl: string; channelName?: string; notes?: string },
    @CurrentUser() user?: CurrentUserType,
  ) {
    const verifiedEmail =
      user && !user.isGuest && typeof user.email === 'string' && user.email.trim()
        ? user.email.trim().toLowerCase()
        : undefined;
    return this.channelsService.createRequest({
      channelUrl: body?.channelUrl,
      channelName: body?.channelName,
      notes: body?.notes,
      submittedBy: verifiedEmail || 'Anonymous',
    });
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