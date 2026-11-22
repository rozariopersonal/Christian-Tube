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

const GOOGLE_SUB_PATTERN = /^\d{18,30}$/;

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
          isGuest: claims.isGuest,
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
      request.user = { ...user, role: 'USER', isGuest: false };
      return true;
    }

    // 3. Legacy guest token (non-admin; ::email claim is ignored for authz)
    if (this.googleJwksService.isGuestToken(token)) {
      const userId = this.googleJwksService.parseGuestToken(token);
      if (!userId) {
        throw new UnauthorizedException('Invalid guest token');
      }

      this.logger.debug(JSON.stringify({ event: 'auth.legacy_guest_token', userId }));

      const looksLikeGoogleSub = GOOGLE_SUB_PATTERN.test(userId);
      let belongsToNonGuestUser = false;
      if (this.prisma) {
        try {
          const existing = await this.prisma.user.findUnique({
            where: { id: userId },
            select: { isGuest: true },
          });
          if (existing && existing.isGuest === false) {
            belongsToNonGuestUser = true;
          }
        } catch {
          // Non-fatal check failure
        }
      }

      if (looksLikeGoogleSub || belongsToNonGuestUser) {
        this.logger.warn(
          JSON.stringify({
            event: 'auth.legacy_guest_impersonation_detected',
            userId,
            looksLikeGoogleSub,
            belongsToNonGuestUser,
          }),
        );
        const rejectFlag =
          this.configService?.get<boolean>('auth.rejectLegacyGuestImpersonation') ??
          process.env.AUTH_REJECT_LEGACY_GUEST_IMPERSONATION === 'true';
        if (rejectFlag) {
          throw new UnauthorizedException('Legacy token rejected; please sign in again');
        }
      }

      request.user = {
        userId,
        email: '',
        role: 'USER',
        isGuest: true,
      };
      return true;
    }

    // 4. Legacy Google idToken (JWKS verification, sunset path)
    try {
      const payload = await this.googleJwksService.verifyIdToken(token);
      this.logger.debug(
        JSON.stringify({ event: 'auth.legacy_google_token', userId: payload.sub }),
      );
      request.user = {
        userId: payload.sub,
        email: (payload.email as string) || '',
        role: 'USER',
        isGuest: false,
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
