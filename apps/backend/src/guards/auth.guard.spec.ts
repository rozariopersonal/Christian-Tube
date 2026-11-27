import { UnauthorizedException } from '@nestjs/common';
import { AuthGuard } from './auth.guard';

function makeContext(request: any): any {
  return { switchToHttp: () => ({ getRequest: () => request }) };
}

describe('AuthGuard', () => {
  const jwks = {
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
    });
    const guard = new AuthGuard(jwks, appJwt);
    const req: any = { headers: { authorization: 'Bearer app.valid.jwt' } };

    await expect(guard.canActivate(makeContext(req))).resolves.toBe(true);
    expect(req.user).toEqual({
      userId: 'user_1',
      email: 'u@example.com',
      role: 'USER',
      sessionId: 'sess_1',
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
      isGoogle: true,
    });
  });

  it('rejects legacy token_* guest tokens', async () => {
    jwks.verifyIdToken.mockRejectedValue(new Error('Invalid or expired token'));
    const guard = new AuthGuard(jwks, appJwt);
    const req: any = {
      headers: { authorization: 'Bearer token_guest_abc::admin@example.com' },
    };

    await expect(guard.canActivate(makeContext(req))).rejects.toThrow(
      UnauthorizedException,
    );
  });
});
