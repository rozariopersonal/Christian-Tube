import { Module, Global } from '@nestjs/common';
import { GoogleJwksService } from '../services/google-jwks.service';
import { AuthGuard } from './auth.guard';
import { AdminGuard } from './admin.guard';

@Global()
@Module({
  providers: [GoogleJwksService, AuthGuard, AdminGuard],
  exports: [GoogleJwksService, AuthGuard, AdminGuard],
})
export class GuardsModule {}