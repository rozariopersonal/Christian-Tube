import { Controller, Get, Post, Body } from '@nestjs/common';
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
}
