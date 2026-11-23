import { Module } from '@nestjs/common';
import { EmbeddingModule } from '../embedding/embedding.module';
import { YoutubeModule } from '../youtube/youtube.module';
import { VideosController } from './videos.controller';
import { VideosService } from './videos.service';
import { SearchController } from './search.controller';

@Module({
  imports: [EmbeddingModule, YoutubeModule],
  controllers: [VideosController, SearchController],
  providers: [VideosService],
  exports: [VideosService],
})
export class VideosModule {}