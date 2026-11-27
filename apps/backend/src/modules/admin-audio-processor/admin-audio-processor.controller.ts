import {
  Body,
  Controller,
  Delete,
  Get,
  Post,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import { AdminGuard } from '../../guards/admin.guard';
import { AdminAudioProcessorService } from './admin-audio-processor.service';

@Controller(['admin/audio-processor', 'api/admin/audio-processor'])
@UseGuards(AdminGuard)
export class AdminAudioProcessorController {
  constructor(private readonly service: AdminAudioProcessorService) {}

  @Get('pending')
  async getPending(@Query('hours') hours?: string) {
    const h = hours ? parseInt(hours, 10) : 72;
    const data = await this.service.getPendingVideos(h);
    return { data };
  }

  @Post('claim')
  async claim(@Body() body: { videoId: string }, @Req() req: any) {
    return this.service.claimVideo(body?.videoId, req.user?.email || 'admin');
  }

  @Post('upload-session')
  async createUploadSession(
    @Body() body: { videoId: string; mime: string; size: number },
    @Req() req: any,
  ) {
    return this.service.createUploadSession(body, req.user?.email || 'admin');
  }

  @Post('complete')
  async complete(
    @Body() body: { uploadSessionId: string; durationSeconds?: number; bytesUploaded?: number },
  ) {
    return this.service.completeUpload(body);
  }

  @Post('mark-short')
  async markShort(@Body() body: { videoId: string }, @Req() req: any) {
    return this.service.markShort(body?.videoId, req.user?.email || 'admin');
  }

  @Post('ignore')
  async markIgnored(@Body() body: { videoId: string; reason?: string }, @Req() req: any) {
    return this.service.markIgnored(body?.videoId, req.user?.email || 'admin', body?.reason);
  }

  @Post('fail')
  async fail(
    @Body() body: { videoId: string; error: string; permanent?: boolean },
    @Req() req: any,
  ) {
    return this.service.reportFailure(body, req.user?.email || 'admin');
  }

  @Get('report')
  async getReport() {
    const data = await this.service.getReport();
    return { data };
  }

  @Post('device-token')
  async registerDeviceToken(@Body() body: { token: string }) {
    return this.service.registerDeviceToken(body?.token);
  }

  @Delete('device-token')
  async unregisterDeviceToken(@Body() body: { token: string }) {
    return this.service.unregisterDeviceToken(body?.token);
  }
}
