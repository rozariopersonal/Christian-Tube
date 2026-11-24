import {
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron, CronExpression } from '@nestjs/schedule';
import { createHash, randomBytes, randomUUID, timingSafeEqual } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { GoogleJwksService } from '../../services/google-jwks.service';
import { AppJwtService } from './app-jwt.service';

export interface AuthSessionUser {
  id: string;
  email: string | null;
  displayName: string | null;
  photoUrl: string | null;
  isGuest: boolean;
}

export interface AuthSessionResponse {
  accessToken: string;
  refreshToken: string;
  sessionId: string;
  expiresIn: number;
  user: AuthSessionUser;
}

export interface RefreshSessionResponse {
  accessToken: string;
  refreshToken: string;
  sessionId: string;
  expiresIn: number;
}

@Injectable()
export class AuthSessionService {
  private readonly logger = new Logger(AuthSessionService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly configService: ConfigService,
    private readonly googleJwksService: GoogleJwksService,
    private readonly appJwtService: AppJwtService,
  ) {}

  private hashToken(raw: string): string {
    return createHash('sha256').update(raw).digest('hex');
  }

  private safeEqualHex(a: string | null | undefined, b: string | null | undefined): boolean {
    if (!a || !b || a.length !== b.length) return false;
    return timingSafeEqual(Buffer.from(a, 'utf8'), Buffer.from(b, 'utf8'));
  }

  private generateRefreshToken(): string {
    return randomBytes(32).toString('base64url');
  }

  private getRefreshTtlMs(): number {
    const days = this.configService.get<number>('auth.refreshTokenTtlDays') ?? 90;
    return days * 24 * 60 * 60 * 1000;
  }

  private getGraceWindowMs(): number {
    const sec = this.configService.get<number>('auth.graceWindowSec') ?? 60;
    return sec * 1000;
  }

  private getMaxSessionsPerUser(): number {
    return this.configService.get<number>('auth.maxSessionsPerUser') ?? 20;
  }

  private logEvent(event: string, data: Record<string, unknown>): void {
    this.logger.log(JSON.stringify({ event, ...data }));
  }

  private async enforceSessionCap(userId: string): Promise<void> {
    const max = this.getMaxSessionsPerUser();
    const active = await this.prisma.userSession.findMany({
      where: {
        userId,
        revokedAt: null,
        expiresAt: { gt: new Date() },
      },
      orderBy: [{ lastUsedAt: 'desc' }, { createdAt: 'desc' }],
      select: { id: true },
    });

    if (active.length <= max) return;

    const toEvict = active.slice(max).map((s) => s.id);
    await this.prisma.userSession.updateMany({
      where: { id: { in: toEvict }, revokedAt: null },
      data: { revokedAt: new Date(), revokeReason: 'evicted' },
    });
    this.logEvent('session.evicted', { userId, count: toEvict.length });
  }

  async createGoogleSession(params: {
    idToken: string;
    deviceId: string;
    deviceLabel?: string;
  }): Promise<AuthSessionResponse> {
    let payload: Awaited<ReturnType<GoogleJwksService['verifyIdToken']>>;
    try {
      payload = await this.googleJwksService.verifyIdToken(params.idToken);
    } catch {
      throw new UnauthorizedException('Invalid or expired Google token');
    }

    const userId = typeof payload.sub === 'string' ? payload.sub : '';
    const email = typeof payload.email === 'string' ? payload.email.trim().toLowerCase() : '';
    if (!userId || !email) {
      throw new UnauthorizedException('Google token missing subject or email');
    }

    const existing = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { isBlocked: true },
    });
    if (existing?.isBlocked) {
      throw new ForbiddenException('Account is blocked');
    }

    const displayName =
      typeof payload.name === 'string' && payload.name.trim().length > 0
        ? payload.name.trim()
        : email.split('@')[0];
    const photoUrl =
      typeof payload.picture === 'string' && payload.picture.trim().length > 0
        ? payload.picture.trim()
        : null;

    const adminEmails = this.configService.get<string[]>('adminEmails') || [];
    const role = adminEmails.includes(email) ? 'ADMIN' : 'USER';

    const user = await this.prisma.user.upsert({
      where: { id: userId },
      create: {
        id: userId,
        email,
        displayName,
        photoUrl,
        isGuest: false,
        role,
        lastLoginAt: new Date(),
      },
      update: {
        email,
        displayName,
        photoUrl,
        isGuest: false,
        role,
        lastLoginAt: new Date(),
      },
      select: {
        id: true,
        email: true,
        displayName: true,
        photoUrl: true,
        isGuest: true,
      },
    });

    const rawRefresh = this.generateRefreshToken();
    const now = new Date();
    const expiresAt = new Date(now.getTime() + this.getRefreshTtlMs());

    const session = await this.prisma.userSession.create({
      data: {
        userId: user.id,
        refreshTokenHash: this.hashToken(rawRefresh),
        deviceId: params.deviceId,
        deviceLabel: params.deviceLabel?.trim() || null,
        isGuest: false,
        expiresAt,
        lastUsedAt: now,
      },
      select: { id: true },
    });

    await this.enforceSessionCap(user.id);

    const accessToken = await this.appJwtService.signAccessToken({
      sub: user.id,
      sid: session.id,
      email: user.email,
      isGuest: false,
    });

    this.logEvent('session.created', {
      userId: user.id,
      sessionId: session.id,
      isGuest: false,
      deviceId: params.deviceId,
    });

    return {
      accessToken,
      refreshToken: rawRefresh,
      sessionId: session.id,
      expiresIn: this.appJwtService.getTtlSeconds(),
      user: {
        id: user.id,
        email: user.email,
        displayName: user.displayName,
        photoUrl: user.photoUrl,
        isGuest: false,
      },
    };
  }

  async createGuestSession(params: {
    deviceId: string;
    deviceLabel?: string;
    displayName?: string;
  }): Promise<AuthSessionResponse> {
    const userId = `guest_${randomUUID()}`;
    const displayName = params.displayName?.trim() || 'Guest User';
    const internalEmail = `${userId}@guest.local`;

    const user = await this.prisma.user.create({
      data: {
        id: userId,
        email: internalEmail,
        displayName,
        photoUrl: null,
        isGuest: true,
        role: 'USER',
        lastLoginAt: new Date(),
      },
      select: {
        id: true,
        displayName: true,
        photoUrl: true,
        isGuest: true,
      },
    });

    const rawRefresh = this.generateRefreshToken();
    const now = new Date();
    const expiresAt = new Date(now.getTime() + this.getRefreshTtlMs());

    const session = await this.prisma.userSession.create({
      data: {
        userId: user.id,
        refreshTokenHash: this.hashToken(rawRefresh),
        deviceId: params.deviceId,
        deviceLabel: params.deviceLabel?.trim() || null,
        isGuest: true,
        expiresAt,
        lastUsedAt: now,
      },
      select: { id: true },
    });

    await this.enforceSessionCap(user.id);

    const accessToken = await this.appJwtService.signAccessToken({
      sub: user.id,
      sid: session.id,
      email: null,
      isGuest: true,
    });

    this.logEvent('session.created', {
      userId: user.id,
      sessionId: session.id,
      isGuest: true,
      deviceId: params.deviceId,
    });

    return {
      accessToken,
      refreshToken: rawRefresh,
      sessionId: session.id,
      expiresIn: this.appJwtService.getTtlSeconds(),
      user: {
        id: user.id,
        email: null,
        displayName: user.displayName,
        photoUrl: user.photoUrl,
        isGuest: true,
      },
    };
  }

  async refreshSession(params: {
    sessionId: string;
    refreshToken: string;
  }): Promise<RefreshSessionResponse> {
    const now = new Date();
    const session = await this.prisma.userSession.findUnique({
      where: { id: params.sessionId },
      include: {
        user: {
          select: { id: true, email: true, isBlocked: true, isGuest: true },
        },
      },
    });

    if (!session || session.revokedAt) {
      throw new UnauthorizedException('Session revoked or not found');
    }

    if (session.expiresAt <= now) {
      this.logEvent('session.expired', {
        userId: session.userId,
        sessionId: session.id,
      });
      throw new UnauthorizedException('Session expired');
    }

    if (session.user.isBlocked) {
      await this.prisma.userSession.updateMany({
        where: { id: session.id, revokedAt: null },
        data: { revokedAt: now, revokeReason: 'blocked' },
      });
      this.logEvent('session.blocked', {
        userId: session.userId,
        sessionId: session.id,
      });
      throw new ForbiddenException('Account is blocked');
    }

    const presentedHash = this.hashToken(params.refreshToken);
    const nextRaw = this.generateRefreshToken();
    const nextHash = this.hashToken(nextRaw);
    const nextExpiresAt = new Date(now.getTime() + this.getRefreshTtlMs());
    const graceUntil = new Date(now.getTime() + this.getGraceWindowMs());

    // Primary path: atomic CAS on current refreshTokenHash
    if (this.safeEqualHex(presentedHash, session.refreshTokenHash)) {
      const updated = await this.prisma.userSession.updateMany({
        where: {
          id: session.id,
          refreshTokenHash: presentedHash,
          revokedAt: null,
        },
        data: {
          refreshTokenHash: nextHash,
          prevTokenHash: presentedHash,
          prevTokenGraceUntil: graceUntil,
          expiresAt: nextExpiresAt,
          lastUsedAt: now,
        },
      });

      if (updated.count === 1) {
        const accessToken = await this.appJwtService.signAccessToken({
          sub: session.userId,
          sid: session.id,
          email: session.isGuest ? null : session.user.email,
          isGuest: session.isGuest,
        });
        this.logEvent('session.refreshed', {
          userId: session.userId,
          sessionId: session.id,
        });
        return {
          accessToken,
          refreshToken: nextRaw,
          sessionId: session.id,
          expiresIn: this.appJwtService.getTtlSeconds(),
        };
      }
    }

    // Re-read after CAS miss or mismatch to check grace window
    const latest = await this.prisma.userSession.findUnique({
      where: { id: params.sessionId },
    });

    if (!latest || latest.revokedAt || latest.expiresAt <= now) {
      throw new UnauthorizedException('Session revoked or expired');
    }

    if (
      latest.prevTokenHash &&
      latest.prevTokenGraceUntil &&
      latest.prevTokenGraceUntil > now &&
      this.safeEqualHex(presentedHash, latest.prevTokenHash)
    ) {
      const graceUpdated = await this.prisma.userSession.updateMany({
        where: {
          id: latest.id,
          refreshTokenHash: latest.refreshTokenHash,
          revokedAt: null,
        },
        data: {
          refreshTokenHash: nextHash,
          prevTokenHash: latest.refreshTokenHash,
          prevTokenGraceUntil: graceUntil,
          expiresAt: nextExpiresAt,
          lastUsedAt: now,
        },
      });

      if (graceUpdated.count === 1) {
        const accessToken = await this.appJwtService.signAccessToken({
          sub: session.userId,
          sid: session.id,
          email: session.isGuest ? null : session.user.email,
          isGuest: session.isGuest,
        });
        this.logEvent('session.grace_hit', {
          userId: session.userId,
          sessionId: session.id,
        });
        return {
          accessToken,
          refreshToken: nextRaw,
          sessionId: session.id,
          expiresIn: this.appJwtService.getTtlSeconds(),
        };
      }

      throw new UnauthorizedException('Concurrent refresh conflict, please retry');
    }

    // Reuse outside grace window: revoke session
    await this.prisma.userSession.updateMany({
      where: { id: latest.id, revokedAt: null },
      data: { revokedAt: now, revokeReason: 'reuse_detected' },
    });
    this.logEvent('session.reuse_revoked', {
      userId: session.userId,
      sessionId: session.id,
    });
    throw new UnauthorizedException('Refresh token reuse detected; session revoked');
  }

  async revokeSession(
    sessionId: string | undefined,
    userId: string,
    reason = 'logout',
  ): Promise<{ ok: true }> {
    if (sessionId) {
      await this.prisma.userSession.updateMany({
        where: { id: sessionId, userId, revokedAt: null },
        data: { revokedAt: new Date(), revokeReason: reason },
      });
      this.logEvent('session.logout', { userId, sessionId, reason });
    }
    return { ok: true };
  }

  async listSessions(userId: string, currentSessionId?: string) {
    const rows = await this.prisma.userSession.findMany({
      where: {
        userId,
        revokedAt: null,
        expiresAt: { gt: new Date() },
      },
      orderBy: [{ lastUsedAt: 'desc' }],
      select: {
        id: true,
        deviceLabel: true,
        isGuest: true,
        createdAt: true,
        lastUsedAt: true,
      },
    });

    return rows.map((row) => ({
      id: row.id,
      deviceLabel: row.deviceLabel,
      isGuest: row.isGuest,
      createdAt: row.createdAt,
      lastUsedAt: row.lastUsedAt,
      current: row.id === currentSessionId,
    }));
  }

  async revokeUserSession(userId: string, targetSessionId: string): Promise<{ ok: true }> {
    const result = await this.prisma.userSession.updateMany({
      where: { id: targetSessionId, userId, revokedAt: null },
      data: { revokedAt: new Date(), revokeReason: 'user_revoked' },
    });
    if (result.count === 0) {
      throw new NotFoundException('Session not found');
    }
    this.logEvent('session.logout', {
      userId,
      sessionId: targetSessionId,
      reason: 'user_revoked',
    });
    return { ok: true };
  }

  @Cron(CronExpression.EVERY_DAY_AT_3AM)
  async cleanupExpiredSessions(): Promise<number> {
    const now = new Date();
    const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
    const result = await this.prisma.userSession.deleteMany({
      where: {
        OR: [
          { expiresAt: { lt: now } },
          { revokedAt: { not: null, lt: thirtyDaysAgo } },
        ],
      },
    });
    if (result.count > 0) {
      this.logEvent('session.cleanup', { deleted: result.count });
    }
    return result.count;
  }
}
