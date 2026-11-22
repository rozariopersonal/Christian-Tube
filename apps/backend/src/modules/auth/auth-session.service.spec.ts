import { ForbiddenException, UnauthorizedException } from '@nestjs/common';
import { createHash } from 'crypto';
import { AppJwtService } from './app-jwt.service';
import { AuthSessionService } from './auth-session.service';

function sha256(s: string) {
  return createHash('sha256').update(s).digest('hex');
}

function makeDeps() {
  const config = {
    get: jest.fn((key: string) => {
      if (key === 'auth.jwtKeysRaw') {
        return JSON.stringify({ v1: 'test-secret-32-bytes-minimum-key' });
      }
      if (key === 'adminEmails') return ['admin@example.com'];
      return undefined;
    }),
  } as any;

  const appJwt = new AppJwtService(config);
  const jwks = {
    verifyIdToken: jest.fn(async () => ({
      sub: 'google_sub_1',
      email: 'user@example.com',
      name: 'Arul',
      picture: 'https://example.com/a.png',
    })),
  } as any;

  const prisma = {
    user: {
      findUnique: jest.fn(),
      upsert: jest.fn(),
      create: jest.fn(),
    },
    userSession: {
      findMany: jest.fn().mockResolvedValue([]),
      findUnique: jest.fn(),
      create: jest.fn(),
      updateMany: jest.fn(),
      deleteMany: jest.fn(),
    },
  } as any;

  const service = new AuthSessionService(prisma, config, jwks, appJwt);
  return { service, prisma, jwks, appJwt };
}

describe('AuthSessionService', () => {
  it('rotates refresh token atomically with CAS on happy path', async () => {
    const { service, prisma } = makeDeps();
    const rawRefresh = 'initial-refresh-token';
    const future = new Date(Date.now() + 60_000_000);

    prisma.userSession.findUnique.mockResolvedValue({
      id: 'sess_1',
      userId: 'u_1',
      refreshTokenHash: sha256(rawRefresh),
      prevTokenHash: null,
      prevTokenGraceUntil: null,
      isGuest: false,
      expiresAt: future,
      revokedAt: null,
      user: { id: 'u_1', email: 'u@example.com', isBlocked: false, isGuest: false },
    });
    prisma.userSession.updateMany.mockResolvedValue({ count: 1 });

    const res = await service.refreshSession({
      sessionId: 'sess_1',
      refreshToken: rawRefresh,
    });

    expect(res.sessionId).toBe('sess_1');
    expect(res.refreshToken).not.toBe(rawRefresh);
    expect(res.accessToken).toBeTruthy();
    expect(prisma.userSession.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          id: 'sess_1',
          refreshTokenHash: sha256(rawRefresh),
          revokedAt: null,
        }),
      }),
    );
  });

  it('re-rotates when prevTokenHash matches within 60s grace window (CAS miss)', async () => {
    const { service, prisma } = makeDeps();
    const oldRefresh = 'old-refresh-token';
    const currentHash = sha256('current-refresh-token');
    const future = new Date(Date.now() + 60_000_000);
    const graceUntil = new Date(Date.now() + 30_000);

    prisma.userSession.findUnique
      .mockResolvedValueOnce({
        id: 'sess_1',
        userId: 'u_1',
        refreshTokenHash: currentHash,
        prevTokenHash: sha256(oldRefresh),
        prevTokenGraceUntil: graceUntil,
        isGuest: false,
        expiresAt: future,
        revokedAt: null,
        user: { id: 'u_1', email: 'u@example.com', isBlocked: false, isGuest: false },
      })
      .mockResolvedValueOnce({
        id: 'sess_1',
        userId: 'u_1',
        refreshTokenHash: currentHash,
        prevTokenHash: sha256(oldRefresh),
        prevTokenGraceUntil: graceUntil,
        isGuest: false,
        expiresAt: future,
        revokedAt: null,
      });

    prisma.userSession.updateMany.mockResolvedValue({ count: 1 });

    const res = await service.refreshSession({
      sessionId: 'sess_1',
      refreshToken: oldRefresh,
    });

    expect(res.refreshToken).not.toBe(oldRefresh);
    expect(prisma.userSession.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          id: 'sess_1',
          refreshTokenHash: currentHash,
        }),
      }),
    );
  });

  it('revokes session on token reuse outside grace window', async () => {
    const { service, prisma } = makeDeps();
    const reused = 'stale-token';
    const future = new Date(Date.now() + 60_000_000);

    prisma.userSession.findUnique.mockResolvedValue({
      id: 'sess_1',
      userId: 'u_1',
      refreshTokenHash: sha256('newer-token'),
      prevTokenHash: sha256(reused),
      prevTokenGraceUntil: new Date(Date.now() - 5_000), // expired grace
      isGuest: false,
      expiresAt: future,
      revokedAt: null,
      user: { id: 'u_1', email: 'u@example.com', isBlocked: false, isGuest: false },
    });
    prisma.userSession.updateMany.mockResolvedValue({ count: 1 });

    await expect(
      service.refreshSession({ sessionId: 'sess_1', refreshToken: reused }),
    ).rejects.toThrow(UnauthorizedException);

    expect(prisma.userSession.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'sess_1', revokedAt: null },
        data: expect.objectContaining({ revokeReason: 'reuse_detected' }),
      }),
    );
  });

  it('revokes and returns 403 when user is blocked', async () => {
    const { service, prisma } = makeDeps();
    const rawRefresh = 'valid-refresh';
    prisma.userSession.findUnique.mockResolvedValue({
      id: 'sess_1',
      userId: 'u_1',
      refreshTokenHash: sha256(rawRefresh),
      prevTokenHash: null,
      prevTokenGraceUntil: null,
      isGuest: false,
      expiresAt: new Date(Date.now() + 60_000_000),
      revokedAt: null,
      user: { id: 'u_1', email: 'u@example.com', isBlocked: true, isGuest: false },
    });
    prisma.userSession.updateMany.mockResolvedValue({ count: 1 });

    await expect(
      service.refreshSession({ sessionId: 'sess_1', refreshToken: rawRefresh }),
    ).rejects.toThrow(ForbiddenException);

    expect(prisma.userSession.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ revokeReason: 'blocked' }),
      }),
    );
  });

  it('evicts oldest sessions beyond 20-session cap on createGoogleSession', async () => {
    const { service, prisma } = makeDeps();
    prisma.user.findUnique.mockResolvedValue(null);
    prisma.user.upsert.mockResolvedValue({
      id: 'google_sub_1',
      email: 'user@example.com',
      displayName: 'Arul',
      photoUrl: null,
      isGuest: false,
    });
    prisma.userSession.create.mockResolvedValue({ id: 'sess_newest' });
    prisma.userSession.findMany.mockResolvedValue(
      Array.from({ length: 22 }, (_, i) => ({ id: `sess_${i}` })),
    );
    prisma.userSession.updateMany.mockResolvedValue({ count: 2 });

    const res = await service.createGoogleSession({
      idToken: 'google.id.token',
      deviceId: 'dev_1',
    });

    expect(res.sessionId).toBe('sess_newest');
    expect(prisma.userSession.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: { in: ['sess_20', 'sess_21'] }, revokedAt: null },
        data: expect.objectContaining({ revokeReason: 'evicted' }),
      }),
    );
  });

  it('creates server-minted guest session with null email and isGuest=true', async () => {
    const { service, prisma } = makeDeps();
    prisma.user.create.mockImplementation(async ({ data }: any) => ({
      id: data.id,
      displayName: data.displayName,
      photoUrl: null,
      isGuest: true,
    }));
    prisma.userSession.create.mockResolvedValue({ id: 'sess_guest' });

    const res = await service.createGuestSession({
      deviceId: 'dev_guest',
      displayName: 'Visitor',
    });

    expect(res.user.id).toMatch(/^guest_/);
    expect(res.user.isGuest).toBe(true);
    expect(res.user.email).toBeNull();
    expect(res.sessionId).toBe('sess_guest');
  });
});
