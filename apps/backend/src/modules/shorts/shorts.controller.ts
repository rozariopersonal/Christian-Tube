import { Controller, Get, Post, Body, Query } from '@nestjs/common';
import { ShortsService, InitiateUploadDto } from './shorts.service';

@Controller(['shorts', 'api/shorts'])
export class ShortsController {
  constructor(private readonly shortsService: ShortsService) {}

  @Get('quota-status')
  async getQuotaStatus() {
    return this.shortsService.getQuotaStatus();
  }

  @Post('initiate-upload')
  async initiateUpload(@Body() dto: InitiateUploadDto) {
    return this.shortsService.initiateUploadSession(dto);
  }

  @Get('my-creations')
  async getMyCreations(
    @Query('userId') userId?: string,
    @Query('email') email?: string,
  ) {
    return this.shortsService.getMyCreations(userId, email);
  }

  @Post('record-creation')
  async recordCreation(@Body() data: any) {
    return this.shortsService.recordCreation(data);
  }
}
