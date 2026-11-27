import { Module } from '@nestjs/common';
import { AdminAudioProcessorController } from './admin-audio-processor.controller';
import { AdminAudioProcessorService } from './admin-audio-processor.service';
import { AudioComApiService } from './audio-com-api.service';
import { AdminPushService } from './admin-push.service';
import { AuthModule } from '../auth/auth.module';

@Module({
  imports: [AuthModule],
  controllers: [AdminAudioProcessorController],
  providers: [
    AdminAudioProcessorService,
    AudioComApiService,
    AdminPushService,
  ],
  exports: [AdminAudioProcessorService, AudioComApiService, AdminPushService],
})
export class AdminAudioProcessorModule {}
