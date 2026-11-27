import { Module } from '@nestjs/common';
import { UsersService } from './users.service';
import { UserPlaylistsService } from './user-playlists.service';
import { UsersController } from './users.controller';
import { PrismaModule } from '../prisma/prisma.module';
import { GuardsModule } from '../../guards/guards.module';

@Module({
  imports: [PrismaModule, GuardsModule],
  controllers: [UsersController],
  providers: [UsersService, UserPlaylistsService],
  exports: [UsersService, UserPlaylistsService],
})
export class UsersModule {}
