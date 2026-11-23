import { Module, Global } from '@nestjs/common';
import { GoogleJwksService } from '../services/google-jwks.service';
import { AppJwtService } from '../modules/auth/app-jwt.service';
import { AuthGuard } from './auth.guard';
import { AdminGuard } from './admin.guard';
import { SessionService } from './session.service';

@Global()
@Module({
  providers: [
    GoogleJwksService,
    AppJwtService,
    SessionService,
    AuthGuard,
    AdminGuard,
  ],
  exports: [
    GoogleJwksService,
    AppJwtService,
    SessionService,
    AuthGuard,
    AdminGuard,
  ],
})
export class GuardsModule {}
