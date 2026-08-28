import { Controller, Get, Post, Body, Param, Query } from '@nestjs/common';
import { VideosService } from './videos.service';

@Controller(['videos', 'api/videos'])
export class VideosController {
  constructor(private readonly videosService: VideosService) {}

  @Get()
  async getVideos(
    @Query('category') category?: string,
    @Query('type') type?: 'VIDEO' | 'SHORT',
    @Query('channelId') channelId?: string,
    @Query('channelIds') channelIds?: string,
    @Query('search') search?: string,
    @Query('limit') limit?: number,
    @Query('offset') offset?: number,
  ) {
    return this.videosService.findAll({
      category,
      type,
      channelId,
      channelIds,
      search,
      limit,
      offset,
    });
  }

  @Post('import')
  async importShort(
    @Body()
    body: {
      youtubeVideoId: string;
      sourceVideoId?: string;
      creatorName?: string;
      creatorEmail?: string;
      clipStartTime?: number;
      clipEndTime?: number;
      cropOffsetX?: number;
      title?: string;
      description?: string;
      category?: string;
    },
  ) {
    return this.videosService.importShortVideo(body);
  }

  @Get(':id')
  async getVideo(@Param('id') id: string) {
    return this.videosService.findOne(id);
  }
}
