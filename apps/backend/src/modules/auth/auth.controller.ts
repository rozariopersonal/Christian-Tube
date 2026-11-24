import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { AuthGuard } from '../../guards/auth.guard';
import {
  CurrentUser,
  CurrentUser as CurrentUserType,
} from '../../guards/current-user.decorator';
import { AuthSessionService } from './auth-session.service';
import { AuthThrottlerGuard } from './auth-throttler.guard';
import { GoogleAuthDto, GuestAuthDto, RefreshAuthDto } from './dto/auth.dto';

@Controller(['auth', 'api/auth'])
export class AuthController {
  constructor(private readonly authSessionService: AuthSessionService) {}

  @UseGuards(AuthThrottlerGuard)
  @Throttle({ default: { limit: 10, ttl: 60000 } })
  @HttpCode(HttpStatus.OK)
  @Post('google')
  async googleLogin(@Body() dto: GoogleAuthDto) {
    return this.authSessionService.createGoogleSession(dto);
  }

  @UseGuards(AuthThrottlerGuard)
  @Throttle({ default: { limit: 10, ttl: 60000 } })
  @HttpCode(HttpStatus.OK)
  @Post('guest')
  async guestLogin(@Body() dto: GuestAuthDto) {
    return this.authSessionService.createGuestSession(dto);
  }

  @UseGuards(AuthThrottlerGuard)
  @Throttle({ default: { limit: 10, ttl: 60000 } })
  @HttpCode(HttpStatus.OK)
  @Post('refresh')
  async refresh(@Body() dto: RefreshAuthDto) {
    return this.authSessionService.refreshSession(dto);
  }

  @UseGuards(AuthGuard)
  @HttpCode(HttpStatus.OK)
  @Post('logout')
  async logout(@CurrentUser() user: CurrentUserType) {
    return this.authSessionService.revokeSession(user.sessionId, user.userId, 'logout');
  }

  @UseGuards(AuthGuard)
  @Get('sessions')
  async listSessions(@CurrentUser() user: CurrentUserType) {
    return this.authSessionService.listSessions(user.userId, user.sessionId);
  }

  @UseGuards(AuthGuard)
  @Delete('sessions/:id')
  async revokeSession(
    @CurrentUser() user: CurrentUserType,
    @Param('id') id: string,
  ) {
    return this.authSessionService.revokeUserSession(user.userId, id);
  }
}
