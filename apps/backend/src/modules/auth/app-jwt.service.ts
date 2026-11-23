import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomBytes } from 'crypto';
import { SignJWT, decodeProtectedHeader, jwtVerify } from 'jose';

export interface AccessTokenClaims {
  sub: string;
  sid: string;
  email: string | null;
  isGuest: boolean;
}

const ISSUER = 'christian-tube';
const AUDIENCE = 'christian-tube-api';

@Injectable()
export class AppJwtService implements OnModuleInit {
  private readonly logger = new Logger(AppJwtService.name);
  private keys = new Map<string, Uint8Array>();
  private keyOrder: string[] = [];
  private initialized = false;

  constructor(private readonly configService: ConfigService) {}

  onModuleInit(): void {
    this.ensureInitialized();
  }

  private ensureInitialized(): void {
    if (this.initialized) return;

    const rawJson =
      this.configService.get<string>('auth.jwtKeysRaw') ??
      process.env.AUTH_JWT_KEYS ??
      '';
    const fallbackSecret =
      this.configService.get<string>('auth.jwtSecretFallback') ??
      process.env.AUTH_JWT_SECRET ??
      '';

    const parsed = new Map<string, Uint8Array>();

    if (rawJson.trim().length > 0) {
      let obj: unknown;
      try {
        obj = JSON.parse(rawJson);
      } catch (err) {
        throw new Error(
          `Invalid AUTH_JWT_KEYS JSON: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
      if (!obj || typeof obj !== 'object' || Array.isArray(obj)) {
        throw new Error('AUTH_JWT_KEYS must be a JSON object mapping kid -> secret');
      }
      for (const [kid, secret] of Object.entries(obj as Record<string, unknown>)) {
        if (typeof secret === 'string' && secret.trim().length > 0) {
          parsed.set(kid, new TextEncoder().encode(secret));
        }
      }
    } else if (fallbackSecret.trim().length > 0) {
      parsed.set('v1', new TextEncoder().encode(fallbackSecret));
    }

    if (parsed.size === 0) {
      const nodeEnv = process.env.NODE_ENV || 'development';
      if (nodeEnv === 'production') {
        throw new Error(
          'AUTH_JWT_KEYS (or AUTH_JWT_SECRET) must be configured in production',
        );
      }
      const ephemeral = randomBytes(32).toString('hex');
      parsed.set('dev-ephemeral', new TextEncoder().encode(ephemeral));
      this.logger.warn(
        'AUTH_JWT_KEYS not set; using ephemeral in-memory dev key (tokens will not survive restart)',
      );
    }

    this.keys = parsed;
    this.keyOrder = Array.from(parsed.keys());
    this.initialized = true;
  }

  getActiveKid(): string {
    this.ensureInitialized();
    return this.keyOrder[this.keyOrder.length - 1];
  }

  getTtlSeconds(): number {
    return this.configService.get<number>('auth.accessTokenTtlSec') ?? 900;
  }

  async signAccessToken(claims: AccessTokenClaims): Promise<string> {
    this.ensureInitialized();
    const kid = this.getActiveKid();
    const key = this.keys.get(kid)!;
    const ttlSec = this.getTtlSeconds();

    return new SignJWT({
      sid: claims.sid,
      email: claims.email,
      guest: claims.isGuest,
      typ: 'access',
    })
      .setProtectedHeader({ alg: 'HS256', kid })
      .setIssuer(ISSUER)
      .setAudience(AUDIENCE)
      .setSubject(claims.sub)
      .setIssuedAt()
      .setExpirationTime(`${ttlSec}s`)
      .sign(key);
  }

  async verifyAccessToken(token: string): Promise<AccessTokenClaims> {
    this.ensureInitialized();
    const header = decodeProtectedHeader(token);
    if (header.alg !== 'HS256') {
      throw new Error('Unexpected JWT algorithm');
    }

    const candidates: Uint8Array[] = [];
    if (typeof header.kid === 'string' && this.keys.has(header.kid)) {
      candidates.push(this.keys.get(header.kid)!);
    } else {
      for (const kid of [...this.keyOrder].reverse()) {
        candidates.push(this.keys.get(kid)!);
      }
    }

    let lastError: unknown = new Error('Invalid token');
    for (const key of candidates) {
      try {
        const { payload } = await jwtVerify(token, key, {
          issuer: ISSUER,
          audience: AUDIENCE,
          clockTolerance: 15,
        });
        if (
          payload.typ !== 'access' ||
          typeof payload.sub !== 'string' ||
          typeof payload.sid !== 'string'
        ) {
          throw new Error('Malformed access token claims');
        }
        return {
          sub: payload.sub,
          sid: payload.sid,
          email: typeof payload.email === 'string' ? payload.email : null,
          isGuest: payload.guest === true,
        };
      } catch (err) {
        lastError = err;
      }
    }

    throw lastError instanceof Error ? lastError : new Error('Invalid token');
  }

  isAppJwt(token: string): boolean {
    try {
      const header = decodeProtectedHeader(token);
      return header.alg === 'HS256';
    } catch {
      return false;
    }
  }
}
