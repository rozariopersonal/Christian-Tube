import { Module } from '@nestjs/common';
import { UserItemsController } from './user-items.controller';
import { UserItemsService } from './user-items.service';

@Module({
  controllers: [UserItemsController],
  providers: [UserItemsService],
  exports: [UserItemsService],
})
export class UserItemsModule {}
