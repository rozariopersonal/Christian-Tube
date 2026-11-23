import { Controller, Delete, ForbiddenException, Post, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from './auth.guard';
import { SessionService } from './session.service';

@Controller('api/auth/session')
export class SessionController {
  constructor(private readonly sessions: SessionService) {}

  @Post()
  @UseGuards(AuthGuard)
  async create(@Req() request: any): Promise<{ token: string }> {
    if (!request.user.isGoogle || !request.user.userId || !request.user.email) {
      throw new ForbiddenException('A verified Google sign-in is required');
    }
    return { token: await this.sessions.create(request.user.userId, request.user.email) };
  }

  @Delete()
  @UseGuards(AuthGuard)
  async revoke(@Req() request: any): Promise<void> {
    await this.sessions.revoke(request.headers.authorization.substring(7).trim());
  }
}
