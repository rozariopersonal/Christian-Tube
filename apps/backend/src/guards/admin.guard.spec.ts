import { ForbiddenException } from '@nestjs/common';
import { AdminGuard } from './admin.guard';
import { GoogleJwksService } from '../services/google-jwks.service';

const ADMIN_EMAIL = 'arul.rozario4@gmail.com';

function makeGuard(options?: {
  verifyPayload?: { sub: string; email: string };
  appJwtPayload?: { sub: string; sid: string; email: string | null; isGuest: boolean };
}) {
  const jwks = {
    isGuestToken: (token: string) => token.startsWith('token_'),
    parseGuestToken: (token: string) => {
      const id = token.split('::')[0].replace('token_', '');
      return id ? id : null;
    },
    parseGuestEmail: (token: string) => {
      const claim = token.split('::')[1];
      return claim && claim.trim() ? claim.trim() : null;
    },
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
  it('rejects guest tokens even when body.adminEmail matches an admin', async () => {
    const { guard, request } = makeGuard();
    request.headers = { authorization: 'Bearer token_user_123' };
    request.body = { adminEmail: ADMIN_EMAIL };

    await expect(guard.canActivate(makeContext(request))).rejects.toThrow(
      ForbiddenException,
    );
  });

  it('rejects guest tokens even when carrying ::adminEmail in the token string', async () => {
    const { guard, request } = makeGuard();
    request.headers = {
      authorization: `Bearer token_user_123::${ADMIN_EMAIL}`,
    };
    request.body = {};

    await expect(guard.canActivate(makeContext(request))).rejects.toThrow(
      ForbiddenException,
    );
  });

  it('rejects app-JWT guest sessions even if email claim is forged', async () => {
    const { guard, request } = makeGuard({
      appJwtPayload: {
        sub: 'guest_1',
        sid: 'sid_1',
        email: ADMIN_EMAIL,
        isGuest: true,
      },
    });
    request.headers = { authorization: 'Bearer app.guest.jwt' };
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

  it('accepts non-guest app-JWT users whose verified email matches an admin', async () => {
    const { guard, request } = makeGuard({
      appJwtPayload: {
        sub: 'google_sub',
        sid: 'sid_1',
        email: ADMIN_EMAIL,
        isGuest: false,
      },
    });
    request.headers = { authorization: 'Bearer app.admin.jwt' };
    request.body = {};

    await expect(guard.canActivate(makeContext(request))).resolves.toBe(true);
    expect(request.user.role).toBe('ADMIN');
    expect(request.user.sessionId).toBe('sid_1');
  });
});
