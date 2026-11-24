import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { PrismaModule } from '../prisma/prisma.module';
import { ShortsController } from './shorts.controller';
import { ShortsService } from './shorts.service';
import { GuardsModule } from '../../guards/guards.module';
import { YoutubeModule } from '../youtube/youtube.module';

@Module({
  imports: [ConfigModule, PrismaModule, GuardsModule, YoutubeModule],
  controllers: [ShortsController],
  providers: [ShortsService],
  exports: [ShortsService],
})
export class ShortsModule {}
