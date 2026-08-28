import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { PrismaModule } from '../prisma/prisma.module';
import { ShortsController } from './shorts.controller';
import { ShortsService } from './shorts.service';

@Module({
  imports: [ConfigModule, PrismaModule],
  controllers: [ShortsController],
  providers: [ShortsService],
  exports: [ShortsService],
})
export class ShortsModule {}
