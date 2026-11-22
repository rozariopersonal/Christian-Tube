import {
  Injectable,
  CanActivate,
  ExecutionContext,
  UnauthorizedException,
  Logger,
} from '@nestjs/common';
import { GoogleJwksService } from '../services/google-jwks.service';
import { SessionService } from './session.service';

@Injectable()
export class AuthGuard implements CanActivate {
  protected readonly logger = new Logger(AuthGuard.name);

  constructor(
    private readonly googleJwksService: GoogleJwksService,
    private readonly sessions: SessionService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const authHeader = request.headers?.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      this.logger.warn('Missing or invalid Authorization header');
      throw new UnauthorizedException('Authorization header required');
    }

    const token = authHeader.substring(7).trim();

    if (!token) {
      throw new UnauthorizedException('Token required');
    }

    if (token.startsWith('session_')) {
      const user = await this.sessions.authenticate(token);
      if (!user) throw new UnauthorizedException('Invalid or expired session');
      request.user = { ...user, role: 'USER' };
      return true;
    }

    if (this.googleJwksService.isGuestToken(token)) {
      const userId = this.googleJwksService.parseGuestToken(token);
      if (!userId) {
        throw new UnauthorizedException('Invalid guest token');
      }
      request.user = {
        userId,
        email: this.googleJwksService.parseGuestEmail(token),
        role: 'USER',
        isGuest: true,
      };
      return true;
    }

    try {
      const payload = await this.googleJwksService.verifyIdToken(token);
      request.user = {
        userId: payload.sub,
        email: payload.email as string,
        role: 'USER',
        isGoogle: true,
      };
      return true;
    } catch (error) {
      this.logger.warn(`Auth failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
      throw new UnauthorizedException('Invalid or expired token');
    }
  }
}