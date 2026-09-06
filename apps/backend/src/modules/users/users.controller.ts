import { Body, Controller, Get, Param, Post, Query } from '@nestjs/common';
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

  @Post('playback')
  async savePlayback(@Body() body: any) {
    return this.usersService.savePlayback(body);
  }

  @Get('playback')
  async getPlayback(
    @Query('email') email?: string,
    @Query('userId') userId?: string,
    @Query('mediaType') mediaType?: string,
  ) {
    return this.usersService.getPlayback({ email, userId, mediaType });
  }

  @Get()
  async getUsers(@Query('search') search?: string) {
    return this.usersService.findAll({ search });
  }

  @Get(':id')
  async getUser(@Param('id') id: string) {
    return this.usersService.findOne(id);
  }

  @Post(':id/block')
  async blockUser(@Param('id') id: string) {
    return this.usersService.blockUser(id);
  }

  @Post(':id/unblock')
  async unblockUser(@Param('id') id: string) {
    return this.usersService.unblockUser(id);
  }

  @Post(':id/toggle-block')
  async toggleBlock(@Param('id') id: string) {
    return this.usersService.toggleBlock(id);
  }
}
