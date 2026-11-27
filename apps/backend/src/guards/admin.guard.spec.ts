import { ForbiddenException } from '@nestjs/common';
import { AdminGuard } from './admin.guard';
import { GoogleJwksService } from '../services/google-jwks.service';

const ADMIN_EMAIL = 'arul.rozario4@gmail.com';

function makeGuard(options?: {
  verifyPayload?: { sub: string; email: string };
  appJwtPayload?: { sub: string; sid: string; email: string | null };
}) {
  const jwks = {
    verifyIdToken: jest.fn(async () => options?.verifyPayload),
  } as any;

  const appJwt = options?.appJwtPayload
    ? ({
        isAppJwt: (token: string) => token.startsWith('app.'),
        verifyAccessToken: jest.fn(async () => options.appJwtPayload),
      } as any)
    : undefined;

  const config = {
    get: jest.fn((key: string) =>
      key === 'adminEmails' ? [ADMIN_EMAIL] : undefined,
    ),
  };

  return {
    guard: new AdminGuard(jwks as GoogleJwksService, config as any, appJwt),
    request: {} as any,
  };
}

function makeContext(request: any): any {
  return { switchToHttp: () => ({ getRequest: () => request }) };
}

describe('AdminGuard', () => {
  it('rejects app-JWT users whose email is not in adminEmails', async () => {
    const { guard, request } = makeGuard({
      appJwtPayload: {
        sub: 'user_1',
        sid: 'sid_1',
        email: 'someone@else.com',
      },
    });
    request.headers = { authorization: 'Bearer app.user.jwt' };
    request.body = {};

    await expect(guard.canActivate(makeContext(request))).rejects.toThrow(
      ForbiddenException,
    );
  });

  it('does not apply body.adminEmail fallback to verified Google users', async () => {
    const { guard, request } = makeGuard({
      verifyPayload: { sub: 'google_sub', email: 'someone@else.com' },
    });
    request.headers = { authorization: 'Bearer real.google.jwt' };
    request.body = { adminEmail: ADMIN_EMAIL };

    await expect(guard.canActivate(makeContext(request))).rejects.toThrow(
      ForbiddenException,
    );
  });

  it('accepts verified Google users whose token email matches an admin', async () => {
    const { guard, request } = makeGuard({
      verifyPayload: { sub: 'google_sub', email: ADMIN_EMAIL },
    });
    request.headers = { authorization: 'Bearer real.google.jwt' };
    request.body = {};

    await expect(guard.canActivate(makeContext(request))).resolves.toBe(true);
    expect(request.user.role).toBe('ADMIN');
  });

  it('accepts app-JWT users whose verified email matches an admin', async () => {
    const { guard, request } = makeGuard({
      appJwtPayload: {
        sub: 'google_sub',
        sid: 'sid_1',
        email: ADMIN_EMAIL,
      },
    });
    request.headers = { authorization: 'Bearer app.admin.jwt' };
    request.body = {};

    await expect(guard.canActivate(makeContext(request))).resolves.toBe(true);
    expect(request.user.role).toBe('ADMIN');
    expect(request.user.sessionId).toBe('sid_1');
  });
});
