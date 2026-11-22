import { Module, Global } from '@nestjs/common';
import { GoogleJwksService } from '../services/google-jwks.service';
import { AppJwtService } from '../modules/auth/app-jwt.service';
import { AuthGuard } from './auth.guard';
import { AdminGuard } from './admin.guard';

@Global()
@Module({
  providers: [GoogleJwksService, AppJwtService, AuthGuard, AdminGuard],
  exports: [GoogleJwksService, AppJwtService, AuthGuard, AdminGuard],
})
export class GuardsModule {}