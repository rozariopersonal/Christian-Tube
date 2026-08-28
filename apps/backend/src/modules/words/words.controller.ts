import { Body, Controller, Delete, Get, Param, Post, Query, Res } from '@nestjs/common';
import { WordsService } from './words.service';
import { Response } from 'express';
import * as path from 'path';
import * as fs from 'fs';

@Controller(['words', 'api/words', 'micro-feed', 'api/micro-feed', 'micro-feeds', 'api/micro-feeds'])
export class WordsController {
  constructor(private readonly wordsService: WordsService) {}

  @Get('offline-db')
  async downloadOfflineDb(@Res() res: Response) {
    const jsonPath = path.join(process.cwd(), 'data', 'scriptures.json');
    if (fs.existsSync(jsonPath)) {
      res.sendFile(jsonPath);
    } else {
      res.status(404).send({ message: 'Offline database not generated yet.' });
    }
  }

  @Get()
  async getWords(
    @Query('category') category?: string,
    @Query('translation') translation?: string,
    @Query('search') search?: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
    @Query('seed') seed?: string,
  ) {
    return this.wordsService.findAll({
      category,
      translation,
      search,
      page: page ? parseInt(page, 10) : undefined,
      limit: limit ? parseInt(limit, 10) : undefined,
      seed: seed ? parseFloat(seed) : undefined,
    });
  }

  @Post('seed')
  async seedWords(@Body() body?: { force?: boolean }) {
    return this.wordsService.seedWords(body?.force ?? false);
  }

  @Post()
  async createWord(
    @Body()
    body: {
      referenceLabel: string;
      text?: string;
      verseMappings?: any;
      translation?: string;
      category?: string;
      backgroundPreset?: string;
      bookName?: string;
      chapter?: number;
      startVerse?: number;
      endVerse?: number;
      tags?: string[];
      isFeatured?: boolean;
    },
  ) {
    return this.wordsService.create(body);
  }

  @Delete(':id')
  async deleteWord(@Param('id') id: string) {
    return this.wordsService.remove(id);
  }

  @Post(':id/like')
  async likeWord(@Param('id') id: string) {
    return this.wordsService.like(id);
  }
}

