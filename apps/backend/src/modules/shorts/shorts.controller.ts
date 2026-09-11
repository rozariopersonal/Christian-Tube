import {
  Controller,
  Get,
  Post,
  Body,
  Query,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '../../guards/auth.guard';
import { CurrentUser, CurrentUser as CurrentUserType } from '../../guards/current-user.decorator';
import { ShortsService, InitiateUploadDto } from './shorts.service';

@Controller(['shorts', 'api/shorts'])
export class ShortsController {
  constructor(private readonly shortsService: ShortsService) {}

  @Get('quota-status')
  async getQuotaStatus() {
    return this.shortsService.getQuotaStatus();
  }

  @UseGuards(AuthGuard)
  @Post('initiate-upload')
  async initiateUpload(
    @CurrentUser() user: CurrentUserType,
    @Body() dto: InitiateUploadDto,
  ) {
    return this.shortsService.initiateUploadSession({ ...dto, userId: user.userId, userEmail: user.email });
  }

  @UseGuards(AuthGuard)
  @Get('my-creations')
  async getMyCreations(@CurrentUser() user: CurrentUserType) {
    return this.shortsService.getMyCreations(user.userId, user.email);
  }

  @UseGuards(AuthGuard)
  @Post('record-creation')
  async recordCreation(
    @CurrentUser() user: CurrentUserType,
    @Body() data: any,
  ) {
    return this.shortsService.recordCreation({ ...data, userId: user.userId, userEmail: user.email });
  }

  @Post('cleanup-legacy-shorts')
  async cleanupLegacyShorts() {
    return this.shortsService.cleanupLegacyShorts();
  }
}