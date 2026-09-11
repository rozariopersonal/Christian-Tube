import { Module } from '@nestjs/common';
import { ChannelsController } from './channels.controller';
import { ChannelsService } from './channels.service';
import { SyncModule } from '../sync/sync.module';
import { GuardsModule } from '../../guards/guards.module';

@Module({
  imports: [SyncModule, GuardsModule],
  controllers: [ChannelsController],
  providers: [ChannelsService],
  exports: [ChannelsService],
})
export class ChannelsModule {}
