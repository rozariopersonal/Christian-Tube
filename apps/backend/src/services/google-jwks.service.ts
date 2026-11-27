import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createRemoteJWKSet, jwtVerify, JWTPayload } from 'jose';

@Injectable()
export class GoogleJwksService {
  private readonly logger = new Logger(GoogleJwksService.name);
  private jwks: ReturnType<typeof createRemoteJWKSet> | null = null;

  constructor(private readonly configService: ConfigService) {}

  getAllowedClientIds(): string[] {
    const rawIds = this.configService.get<string[] | string>('googleClientIds');
    const rawSingle = this.configService.get<string>('googleClientId');
    const candidates: string[] = [];

    if (Array.isArray(rawIds)) {
      candidates.push(...rawIds);
    } else if (typeof rawIds === 'string') {
      candidates.push(rawIds);
    }
    if (typeof rawSingle === 'string') {
      candidates.push(rawSingle);
    }

    return Array.from(
      new Set(
        candidates
          .flatMap((entry) => entry.split(',').map((id) => id.trim()))
          .filter(Boolean),
      ),
    );
  }

  private getJwks() {
    if (!this.jwks) {
      if (this.getAllowedClientIds().length === 0) {
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
    const allowedClientIds = this.getAllowedClientIds();

    if (allowedClientIds.length === 0) {
      throw new Error('Google Client ID not configured');
    }

    try {
      const { payload } = await jwtVerify(token, jwks, {
        issuer: ['https://accounts.google.com', 'accounts.google.com'],
        audience: allowedClientIds.length === 1 ? allowedClientIds[0] : allowedClientIds,
        clockTolerance: 30,
      });

      this.logger.debug(`Token verified for user: ${payload.sub}`);
      return payload;
    } catch (error: any) {
      this.logger.warn(`Token verification failed: ${error.message}`);
      throw new Error('Invalid or expired token');
    }
  }
}
