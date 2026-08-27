import { Body, Controller, Delete, Get, Param, Post, Query } from '@nestjs/common';
import { WordsService } from './words.service';

@Controller(['words', 'api/words', 'micro-feed', 'api/micro-feed'])
export class WordsController {
  constructor(private readonly wordsService: WordsService) {}

  @Get()
  async getWords(
    @Query('category') category?: string,
    @Query('translation') translation?: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    return this.wordsService.findAll({
      category,
      translation,
      page: page ? parseInt(page, 10) : undefined,
      limit: limit ? parseInt(limit, 10) : undefined,
    });
  }

  @Post()
  async createWord(
    @Body()
    body: {
      referenceLabel: string;
      text: string;
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
