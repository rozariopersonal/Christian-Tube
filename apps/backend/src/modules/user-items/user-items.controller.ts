import { Body, Controller, Get, Post, Query, UseGuards } from '@nestjs/common';
import { AuthGuard } from '../../guards/auth.guard';
import {
  CurrentUser,
  CurrentUser as CurrentUserType,
} from '../../guards/current-user.decorator';
import { UserItemDto, UserItemsService } from './user-items.service';

@UseGuards(AuthGuard)
@Controller(['user/items', 'api/user/items'])
export class UserItemsController {
  constructor(private readonly userItemsService: UserItemsService) {}

  @Get()
  async listItems(
    @CurrentUser() user: CurrentUserType,
    @Query('after') after?: string,
    @Query('feature') feature?: string,
  ) {
    return this.userItemsService.listItems(user.userId, { after, feature });
  }

  @Post()
  async upsertItems(
    @CurrentUser() user: CurrentUserType,
    @Body() body: { items?: UserItemDto[] } | UserItemDto[],
  ) {
    const items = Array.isArray(body)
      ? body
      : Array.isArray(body?.items)
        ? body.items
        : [];
    return this.userItemsService.upsertBatch(user.userId, user.email, items);
  }
}
