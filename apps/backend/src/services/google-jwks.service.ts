import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createRemoteJWKSet, jwtVerify, JWTPayload } from 'jose';

@Injectable()
export class GoogleJwksService {
  private readonly logger = new Logger(GoogleJwksService.name);
  private jwks: ReturnType<typeof createRemoteJWKSet> | null = null;

  constructor(private readonly configService: ConfigService) {}

  private getJwks() {
    if (!this.jwks) {
      const clientId = this.configService.get<string>('googleClientId');
      if (!clientId) {
        this.logger.warn('Google Client ID not configured — token verification will fail');
      }
      this.jwks = createRemoteJWKSet(
        new URL('https://www.googleapis.com/oauth2/v3/certs'),
        {
          cacheMaxAge: 60 * 60 * 1000,
          cooldownDuration: 60 * 1000,
        },
      );
    }
    return this.jwks;
  }

  async verifyIdToken(token: string): Promise<JWTPayload> {
    const jwks = this.getJwks();
    const clientId = this.configService.get<string>('googleClientId');

    if (!clientId) {
      throw new Error('Google Client ID not configured');
    }

    try {
      const { payload } = await jwtVerify(token, jwks, {
        issuer: ['https://accounts.google.com', 'accounts.google.com'],
        audience: clientId,
        clockTolerance: 30,
      });

      this.logger.debug(`Token verified for user: ${payload.sub}`);
      return payload;
    } catch (error: any) {
      this.logger.warn(`Token verification failed: ${error.message}`);
      throw new Error('Invalid or expired token');
    }
  }

  isGuestToken(token: string): boolean {
    return token.startsWith('token_');
  }

  parseGuestToken(token: string): string | null {
    if (!this.isGuestToken(token)) return null;
    return token.replace('token_', '');
  }
}