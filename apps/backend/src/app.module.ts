import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ScheduleModule } from '@nestjs/schedule';
import configuration from './config/configuration';
import { PrismaModule } from './modules/prisma/prisma.module';
import { UsersModule } from './modules/users/users.module';
import { UserItemsModule } from './modules/user-items/user-items.module';
import { VideosModule } from './modules/videos/videos.module';
import { ChannelsModule } from './modules/channels/channels.module';
import { YoutubeModule } from './modules/youtube/youtube.module';
import { SyncModule } from './modules/sync/sync.module';
import { CacheModule } from './modules/cache/cache.module';
import { EmbeddingModule } from './modules/embedding/embedding.module';
import { StorageModule } from './modules/storage/storage.module';
import { HealthModule } from './modules/health/health.module';
import { WordsModule } from './modules/words/words.module';
import { ShortsModule } from './modules/shorts/shorts.module';
import { FeedbackModule } from './modules/feedback/feedback.module';
import { AdminReleaseModule } from './modules/admin-release/admin-release.module';
import { AudioModule } from './modules/audio/audio.module';
import { BibleModule } from './modules/bible/bible.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      load: [configuration],
    }),
    ScheduleModule.forRoot(),
    CacheModule,
    HealthModule,
    PrismaModule,
    UsersModule,
    UserItemsModule,
    StorageModule,
    VideosModule,
    ChannelsModule,
    YoutubeModule,
    SyncModule,
    EmbeddingModule,
    WordsModule,
    ShortsModule,
    FeedbackModule,
    AdminReleaseModule,
    AudioModule,
    BibleModule,
  ],
})
export class AppModule {}
