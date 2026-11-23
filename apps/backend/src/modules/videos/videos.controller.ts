import { Controller, Get, Post, Body, Param, Query } from '@nestjs/common';
import { VideosService } from './videos.service';

@Controller(['videos', 'api/videos'])
export class VideosController {
  constructor(private readonly videosService: VideosService) {}

  @Get()
  async getVideos(
    @Query('category') category?: string,
    @Query('type') type?: 'VIDEO' | 'SHORT' | 'ALL',
    @Query('channelId') channelId?: string,
    @Query('channelIds') channelIds?: string,
    @Query('search') search?: string,
    @Query('sort') sort?: 'latest' | 'popular' | 'oldest' | 'relevance',
    @Query('limit') limit?: number,
    @Query('offset') offset?: number,
    @Query('publishedBefore') publishedBefore?: string,
    @Query('beforeId') beforeId?: string,
    @Query('publishedAfter') publishedAfter?: string,
    @Query('afterId') afterId?: string,
  ) {
    return this.videosService.findAll({
      category,
      type,
      channelId,
      channelIds,
      search,
      sort,
      limit,
      offset,
      publishedBefore,
      beforeId,
      publishedAfter,
      afterId,
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

  @Get(':id/channel-position')
  async getChannelPosition(@Param('id') id: string) {
    return this.videosService.getChannelPosition(id);
  }

  @Get(':id')
  async getVideo(@Param('id') id: string) {
    return this.videosService.findOne(id);
  }
}
