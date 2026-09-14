import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { GoogleJwksService } from '../../services/google-jwks.service';
import { AdminReleaseController } from './admin-release.controller';
import { AdminReleaseService } from './admin-release.service';

@Module({
  imports: [ConfigModule],
  controllers: [AdminReleaseController],
  providers: [AdminReleaseService, GoogleJwksService],
  exports: [AdminReleaseService],
})
export class AdminReleaseModule {}
