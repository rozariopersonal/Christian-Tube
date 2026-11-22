import { UnauthorizedException } from '@nestjs/common';
import { AuthGuard } from './auth.guard';

function makeContext(request: any): any {
  return { switchToHttp: () => ({ getRequest: () => request }) };
}

describe('AuthGuard', () => {
  const jwks = {
    isGuestToken: (token: string) => token.startsWith('token_'),
    parseGuestToken: (token: string) => token.split('::')[0].replace('token_', '') || null,
    verifyIdToken: jest.fn(),
  } as any;

  const appJwt = {
    isAppJwt: (token: string) => token.startsWith('app.'),
    verifyAccessToken: jest.fn(),
  } as any;

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('verifies app JWTs locally without calling Google JWKS', async () => {
    appJwt.verifyAccessToken.mockResolvedValue({
      sub: 'user_1',
      sid: 'sess_1',
      email: 'u@example.com',
      isGuest: false,
    });
    const guard = new AuthGuard(jwks, appJwt);
    const req: any = { headers: { authorization: 'Bearer app.valid.jwt' } };

    await expect(guard.canActivate(makeContext(req))).resolves.toBe(true);
    expect(req.user).toEqual({
      userId: 'user_1',
      email: 'u@example.com',
      role: 'USER',
      sessionId: 'sess_1',
      isGuest: false,
    });
    expect(jwks.verifyIdToken).not.toHaveBeenCalled();
  });

  it('rejects expired/invalid app JWTs without falling back to JWKS', async () => {
    appJwt.verifyAccessToken.mockRejectedValue(new Error('jwt expired'));
    const guard = new AuthGuard(jwks, appJwt);
    const req: any = { headers: { authorization: 'Bearer app.expired.jwt' } };

    await expect(guard.canActivate(makeContext(req))).rejects.toThrow(
      UnauthorizedException,
    );
    expect(jwks.verifyIdToken).not.toHaveBeenCalled();
  });

  it('falls back to legacy Google idToken verification', async () => {
    jwks.verifyIdToken.mockResolvedValue({
      sub: 'google_123',
      email: 'user@gmail.com',
    });
    const guard = new AuthGuard(jwks, appJwt);
    const req: any = { headers: { authorization: 'Bearer google.rs256.jwt' } };

    await expect(guard.canActivate(makeContext(req))).resolves.toBe(true);
    expect(req.user).toEqual({
      userId: 'google_123',
      email: 'user@gmail.com',
      role: 'USER',
      isGuest: false,
    });
  });

  it('ignores ::email claim on legacy guest tokens', async () => {
    const guard = new AuthGuard(jwks, appJwt);
    const req: any = {
      headers: { authorization: 'Bearer token_guest_abc::admin@example.com' },
    };

    await expect(guard.canActivate(makeContext(req))).resolves.toBe(true);
    expect(req.user).toEqual({
      userId: 'guest_abc',
      email: '',
      role: 'USER',
      isGuest: true,
    });
  });

  it('rejects guest tokens impersonating a Google sub when reject flag is enabled', async () => {
    const prisma = {
      user: { findUnique: jest.fn().mockResolvedValue({ isGuest: false }) },
    } as any;
    const config = {
      get: jest.fn((k: string) =>
        k === 'auth.rejectLegacyGuestImpersonation' ? true : undefined,
      ),
    } as any;
    const guard = new AuthGuard(jwks, appJwt, prisma, config);
    const req: any = {
      headers: { authorization: 'Bearer token_109876543210987654321' },
    };

    await expect(guard.canActivate(makeContext(req))).rejects.toThrow(
      UnauthorizedException,
    );
  });

  it('logs but allows legacy guest impersonation pattern when reject flag is false', async () => {
    const prisma = {
      user: { findUnique: jest.fn().mockResolvedValue({ isGuest: false }) },
    } as any;
    const config = {
      get: jest.fn((k: string) =>
        k === 'auth.rejectLegacyGuestImpersonation' ? false : undefined,
      ),
    } as any;
    const guard = new AuthGuard(jwks, appJwt, prisma, config);
    const req: any = {
      headers: { authorization: 'Bearer token_109876543210987654321' },
    };

    await expect(guard.canActivate(makeContext(req))).resolves.toBe(true);
    expect(req.user.isGuest).toBe(true);
    expect(req.user.email).toBe('');
  });
});
