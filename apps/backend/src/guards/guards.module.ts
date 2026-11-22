import { Module, Global } from '@nestjs/common';
import { GoogleJwksService } from '../services/google-jwks.service';
import { AuthGuard } from './auth.guard';
import { AdminGuard } from './admin.guard';
import { SessionService } from './session.service';
import { SessionController } from './session.controller';
import { PrismaModule } from '../modules/prisma/prisma.module';

@Global()
@Module({
  imports: [PrismaModule],
  controllers: [SessionController],
  providers: [GoogleJwksService, SessionService, AuthGuard, AdminGuard],
  exports: [GoogleJwksService, AuthGuard, AdminGuard],
})
export class GuardsModule {}