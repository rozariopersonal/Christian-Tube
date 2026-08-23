import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ScheduleModule } from '@nestjs/schedule';
import configuration from './config/configuration';
import { PrismaModule } from './modules/prisma/prisma.module';
import { UsersModule } from './modules/users/users.module';
import { VideosModule } from './modules/videos/videos.module';
import { ChannelsModule } from './modules/channels/channels.module';
import { YoutubeModule } from './modules/youtube/youtube.module';
import { TranscriptionModule } from './modules/transcription/transcription.module';
import { StorageModule } from './modules/storage/storage.module';
import { HealthModule } from './modules/health/health.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      load: [configuration],
    }),
    ScheduleModule.forRoot(),
    HealthModule,
    PrismaModule,
    UsersModule,
    StorageModule,
    VideosModule,
    ChannelsModule,
    YoutubeModule,
    TranscriptionModule,
  ],
})
export class AppModule {}
