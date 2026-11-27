import { Module } from '@nestjs/common';
import { SyncService } from './sync.service';
import { SyncController } from './sync.controller';
import { YoutubeModule } from '../youtube/youtube.module';
import { AdminAudioProcessorModule } from '../admin-audio-processor/admin-audio-processor.module';

@Module({
  imports: [YoutubeModule, AdminAudioProcessorModule],
  controllers: [SyncController],
  providers: [SyncService],
  exports: [SyncService],
})
export class SyncModule {}
