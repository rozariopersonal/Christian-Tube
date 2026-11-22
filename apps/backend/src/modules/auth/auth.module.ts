import { Module } from '@nestjs/common';
import { ThrottlerModule } from '@nestjs/throttler';
import { GuardsModule } from '../../guards/guards.module';
import { AuthSessionService } from './auth-session.service';
import { AuthThrottlerGuard } from './auth-throttler.guard';
import { AuthController } from './auth.controller';

@Module({
  imports: [
    GuardsModule,
    ThrottlerModule.forRoot([
      {
        ttl: 60000,
        limit: 10,
      },
    ]),
  ],
  controllers: [AuthController],
  providers: [AuthSessionService, AuthThrottlerGuard],
  exports: [AuthSessionService],
})
export class AuthModule {}
