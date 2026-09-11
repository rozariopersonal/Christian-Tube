import {
  Injectable,
  CanActivate,
  ExecutionContext,
  UnauthorizedException,
  Logger,
} from '@nestjs/common';
import { GoogleJwksService } from '../services/google-jwks.service';

@Injectable()
export class AuthGuard implements CanActivate {
  protected readonly logger = new Logger(AuthGuard.name);

  constructor(private readonly googleJwksService: GoogleJwksService) {}

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

    if (this.googleJwksService.isGuestToken(token)) {
      const userId = this.googleJwksService.parseGuestToken(token);
      if (!userId) {
        throw new UnauthorizedException('Invalid guest token');
      }
      request.user = {
        userId,
        email: null,
        role: 'USER',
      };
      return true;
    }

    try {
      const payload = await this.googleJwksService.verifyIdToken(token);
      request.user = {
        userId: payload.sub,
        email: payload.email as string,
        role: 'USER',
      };
      return true;
    } catch (error) {
      this.logger.warn(`Auth failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
      throw new UnauthorizedException('Invalid or expired token');
    }
  }
}