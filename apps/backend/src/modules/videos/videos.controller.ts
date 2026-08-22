import { Controller, Get, Param, Query } from '@nestjs/common';
import { VideosService } from './videos.service';

@Controller(['videos', 'api/videos'])
export class VideosController {
  constructor(private readonly videosService: VideosService) {}

  @Get()
  async getVideos(
    @Query('category') category?: string,
    @Query('type') type?: 'VIDEO' | 'SHORT',
    @Query('channelId') channelId?: string,
    @Query('search') search?: string,
    @Query('limit') limit?: number,
    @Query('offset') offset?: number,
  ) {
    return this.videosService.findAll({ category, type, channelId, search, limit, offset });
  }

  @Get(':id')
  async getVideoById(@Param('id') id: string) {
    return this.videosService.findOne(id);
  }
}
