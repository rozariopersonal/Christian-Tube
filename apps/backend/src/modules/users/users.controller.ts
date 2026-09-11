import {
  Body,
  Controller,
  Get,
  Param,
  Post,
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

  @Post('sync')
  async syncUser(
    @Body() body: { id: string; email: string; displayName?: string; photoUrl?: string },
  ) {
    return this.usersService.syncUser(body);
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
}