import { Injectable } from '@nestjs/common';
import { createHash, randomBytes } from 'crypto';
import { PrismaService } from '../modules/prisma/prisma.service';

const SESSION_PREFIX = 'session_';
const SESSION_DAYS = 90;

@Injectable()
export class SessionService {
  constructor(private readonly prisma: PrismaService) {}

  isSessionToken(token: string): boolean {
    return /^session_[A-Za-z0-9_-]{43}$/.test(token);
  }

  private hash(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }

  async create(userId: string, email: string): Promise<string> {
    const token = SESSION_PREFIX + randomBytes(32).toString('base64url');
    const hash = this.hash(token);
    await this.prisma.$executeRaw`
      INSERT INTO "WebSession" ("tokenHash", "userId", "email", "expiresAt")
      VALUES (${hash}, ${userId}, ${email}, NOW() + (${SESSION_DAYS} * INTERVAL '1 day'))
    `;
    return token;
  }

  async authenticate(token: string): Promise<{ userId: string; email: string } | null> {
    if (!this.isSessionToken(token)) return null;
    const hash = this.hash(token);
    const rows = await this.prisma.$queryRaw<{ userId: string; email: string }[]>`
      UPDATE "WebSession" SET "expiresAt" = NOW() + (${SESSION_DAYS} * INTERVAL '1 day')
      WHERE "tokenHash" = ${hash} AND "expiresAt" > NOW()
      RETURNING "userId", "email"
    `;
    return rows[0] ?? null;
  }

  async revoke(token: string): Promise<void> {
    if (!this.isSessionToken(token)) return;
    const hash = this.hash(token);
    await this.prisma.$executeRaw`DELETE FROM "WebSession" WHERE "tokenHash" = ${hash}`;
  }
}
