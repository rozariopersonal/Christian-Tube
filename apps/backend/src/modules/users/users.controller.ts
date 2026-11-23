import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Put,
  Query,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '../../guards/auth.guard';
import { AdminGuard } from '../../guards/admin.guard';
import { CurrentUser, CurrentUser as CurrentUserType } from '../../guards/current-user.decorator';
import { UsersService } from './users.service';

@Controller(['users', 'api/users', 'user', 'api/user'])
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @UseGuards(AuthGuard)
  @Post('sync')
  async syncUser(
    @CurrentUser() user: CurrentUserType,
    @Body() body: { id?: string; email?: string; displayName?: string; photoUrl?: string },
  ) {
    return this.usersService.syncUser({
      id: user.userId,
      email: user.isGuest ? '' : (user.email || body?.email || ''),
      displayName: body?.displayName,
      photoUrl: body?.photoUrl,
    });
  }

  @UseGuards(AuthGuard)
  @Get('state')
  async getSyncState(@CurrentUser() user: CurrentUserType) {
    return this.usersService.getSyncState(user.userId, user.email);
  }

  @UseGuards(AuthGuard)
  @Get('preferences')
  async getPreferences(@CurrentUser() user: CurrentUserType) {
    return this.usersService.getPreferences(user.userId);
  }

  @UseGuards(AuthGuard)
  @Put('preferences')
  async savePreferences(
    @CurrentUser() user: CurrentUserType,
    @Body() body: any,
  ) {
    return this.usersService.savePreferences(user.userId, body, user.email);
  }

  @UseGuards(AuthGuard)
  @Patch('preferences')
  async patchPreferences(
    @CurrentUser() user: CurrentUserType,
    @Body() body: any,
  ) {
    return this.usersService.savePreferences(user.userId, body, user.email);
  }

  @UseGuards(AuthGuard)
  @Post('watch-items/batch')
  async upsertWatchItemsBatch(
    @CurrentUser() user: CurrentUserType,
    @Body() body: { items?: any[] },
  ) {
    return this.usersService.upsertWatchItemsBatch(
      user.userId,
      user.email,
      Array.isArray(body?.items) ? body.items : [],
    );
  }

  @UseGuards(AuthGuard)
  @Post('playback')
  async savePlayback(
    @CurrentUser() user: CurrentUserType,
    @Body() body: any,
  ) {
    return this.usersService.savePlayback({ ...body, userId: user.userId, userEmail: user.email });
  }

  @UseGuards(AuthGuard)
  @Get('playback')
  async getPlayback(
    @CurrentUser() user: CurrentUserType,
    @Query('mediaType') mediaType?: string,
  ) {
    return this.usersService.getPlayback({ userId: user.userId, userEmail: user.email, mediaType });
  }

  @UseGuards(AdminGuard)
  @Get()
  async getUsers(@Query('search') search?: string) {
    return this.usersService.findAll({ search });
  }

  @UseGuards(AdminGuard)
  @Get(':id')
  async getUser(@Param('id') id: string) {
    return this.usersService.findOne(id);
  }

  @UseGuards(AdminGuard)
  @Post(':id/block')
  async blockUser(@Param('id') id: string) {
    return this.usersService.blockUser(id);
  }

  @UseGuards(AdminGuard)
  @Post(':id/unblock')
  async unblockUser(@Param('id') id: string) {
    return this.usersService.unblockUser(id);
  }

  @UseGuards(AdminGuard)
  @Post(':id/toggle-block')
  async toggleBlock(@Param('id') id: string) {
    return this.usersService.toggleBlock(id);
  }

  @UseGuards(AdminGuard)
  @Delete(':id')
  async removeUser(
    @Param('id') id: string,
    @CurrentUser() admin: CurrentUserType,
  ) {
    return this.usersService.removeUser(id, admin.userId);
  }
}