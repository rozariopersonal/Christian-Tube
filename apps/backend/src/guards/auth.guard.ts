import {
  Injectable,
  CanActivate,
  ExecutionContext,
  UnauthorizedException,
  Logger,
  Optional,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { GoogleJwksService } from '../services/google-jwks.service';
import { AppJwtService } from '../modules/auth/app-jwt.service';
import { PrismaService } from '../modules/prisma/prisma.service';
import { SessionService } from './session.service';

@Injectable()
export class AuthGuard implements CanActivate {
  protected readonly logger = new Logger(AuthGuard.name);

  constructor(
    private readonly googleJwksService: GoogleJwksService,
    @Optional() private readonly appJwtService?: AppJwtService,
    @Optional() private readonly prisma?: PrismaService,
    @Optional() protected readonly configService?: ConfigService,
    @Optional() private readonly sessions?: SessionService,
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

    // 1. App-signed access JWT (fastest, primary path)
    if (this.appJwtService && this.appJwtService.isAppJwt(token)) {
      try {
        const claims = await this.appJwtService.verifyAccessToken(token);
        request.user = {
          userId: claims.sub,
          email: claims.email ?? '',
          role: 'USER',
          sessionId: claims.sid,
        };
        return true;
      } catch (error) {
        this.logger.warn(
          `App JWT failed: ${error instanceof Error ? error.message : 'Unknown error'}`,
        );
        throw new UnauthorizedException('Invalid or expired token');
      }
    }

    // 2. Legacy WebSession token (`session_*`)
    if (token.startsWith('session_') && this.sessions) {
      const user = await this.sessions.authenticate(token);
      if (!user) throw new UnauthorizedException('Invalid or expired session');
      request.user = { ...user, role: 'USER' };
      return true;
    }

    // 3. Legacy Google idToken (JWKS verification, sunset path)
    try {
      const payload = await this.googleJwksService.verifyIdToken(token);
      this.logger.debug(
        JSON.stringify({ event: 'auth.legacy_google_token', userId: payload.sub }),
      );
      request.user = {
        userId: payload.sub,
        email: (payload.email as string) || '',
        role: 'USER',
        isGoogle: true,
      };
      return true;
    } catch (error) {
      this.logger.warn(
        `Auth failed: ${error instanceof Error ? error.message : 'Unknown error'}`,
      );
      throw new UnauthorizedException('Invalid or expired token');
    }
  }
}
