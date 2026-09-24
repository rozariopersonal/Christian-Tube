import { Controller, Get, Param, Res, HttpException, HttpStatus, Query, Post, Headers, UnauthorizedException, NotFoundException, Header } from '@nestjs/common';
import { Response } from 'express';
import { ConfigService } from '@nestjs/config';
import { AudioService } from './audio.service';

@Controller(['audio', 'api/audio'])
export class AudioController {
  constructor(
    private readonly configService: ConfigService,
    private readonly audioService: AudioService,
  ) {}

  @Get('catalog')
  @Header('Cache-Control', 'public, max-age=3600, stale-while-revalidate=86400')
  async getCatalog() {
    const data = await this.audioService.getCatalog();
    return { data };
  }

  @Get('series/:id')
  @Header('Cache-Control', 'public, max-age=3600, stale-while-revalidate=86400')
  async getSeries(@Param('id') id: string) {
    const data = await this.audioService.getSeries(id);
    if (!data) {
      throw new NotFoundException(`Audio series not found: ${id}`);
    }
    return { data };
  }

  @Get('stream/:id')
  async getAudioStream(@Param('id') id: string, @Res() res: Response) {
    const token = this.configService.get<string>('AUDIO_COM_TOKEN');
    
    if (!token) {
      throw new HttpException('Audio service not configured', HttpStatus.INTERNAL_SERVER_ERROR);
    }

    try {
      const response = await fetch(`https://api.audio.com/v1/audio/view?id=${id}`, {
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: 'application/json',
        },
      });

      if (!response.ok) {
        throw new HttpException('Failed to resolve audio stream from Audio.com', response.status);
      }

      const data = await response.json();
      const play = data?.play || {};
      const streamUrl = play.url || play.stream_url || play.streamUrl;

      if (!streamUrl) {
        throw new HttpException('Stream URL not found on Audio.com', HttpStatus.NOT_FOUND);
      }

      // Redirect directly to the presigned AWS S3 stream URL
      return res.redirect(HttpStatus.FOUND, streamUrl);
      
    } catch (error) {
      if (error instanceof HttpException) {
        throw error;
      }
      throw new HttpException('Failed to resolve audio stream', HttpStatus.INTERNAL_SERVER_ERROR);
    }
  }
  @Get('sync')
  async getSyncData(@Query('since') since?: string) {
    const timestamp = since ? parseInt(since, 10) : undefined;
    const data = await this.audioService.getSyncData(timestamp);
    return { data };
  }

  @Get('search')
  async search(@Query('q') q: string, @Query('limit') limit?: string) {
    if (!q) return { data: [] };
    const max = limit ? parseInt(limit, 10) : 20;
    const results = await this.audioService.searchCatalog(q, max);
    return { data: results };
  }

  @Post('trigger-sync')
  async triggerSync(@Headers('x-api-key') apiKey?: string) {
    const expectedKey = this.configService.get<string>('ADMIN_API_KEY');
    if (!expectedKey || apiKey !== expectedKey) {
      throw new UnauthorizedException('Invalid or missing API key');
    }

    this.audioService.syncCatalogFromGitHub().catch(err => {
      console.error('Background sync failed:', err);
    });
    return { status: 'accepted', message: 'Audio catalog sync initiated' };
  }
}
