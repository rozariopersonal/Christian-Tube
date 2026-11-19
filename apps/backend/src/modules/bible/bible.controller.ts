import { Controller, Get, Query } from '@nestjs/common';
import { BibleService } from './bible.service';

@Controller(['bible', 'api/bible'])
export class BibleController {
  constructor(private readonly bibleService: BibleService) {}

  @Get('search')
  async search(
    @Query('q') q?: string,
    @Query('limit') limit?: string,
  ) {
    const parsedLimit = limit ? parseInt(limit, 10) : undefined;
    return this.bibleService.search(q, parsedLimit);
  }

  @Get('search/status')
  getStatus() {
    return this.bibleService.getStatus();
  }
}
