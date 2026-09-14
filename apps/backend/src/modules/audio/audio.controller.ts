import { Controller, Get, Param, Res, HttpException, HttpStatus } from '@nestjs/common';
import { Response } from 'express';
import { ConfigService } from '@nestjs/config';

@Controller('audio')
export class AudioController {
  constructor(private readonly configService: ConfigService) {}

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
}
