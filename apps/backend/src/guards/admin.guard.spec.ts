import { ForbiddenException } from '@nestjs/common';
import { AdminGuard } from './admin.guard';
import { GoogleJwksService } from '../services/google-jwks.service';

const ADMIN_EMAIL = 'arul.rozario4@gmail.com';

function makeGuard(verifyPayload?: { sub: string; email: string }) {
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
    verifyIdToken: jest.fn(async () => verifyPayload),
  } as any;

  const config = { get: jest.fn((key: string) => (key === 'adminEmails' ? [ADMIN_EMAIL] : undefined)) };

  return { guard: new AdminGuard(jwks as GoogleJwksService, config as any), request: {} as any };
}

function makeContext(request: any): any {
  return { switchToHttp: () => ({ getRequest: () => request }) };
}

describe('AdminGuard', () => {
  it('rejects legacy guest tokens when no email claim and no body email match', async () => {
    const { guard, request } = makeGuard();
    request.headers = { authorization: 'Bearer token_user_123' };
    request.body = { adminEmail: 'someone@else.com' };

    await expect(guard.canActivate(makeContext(request))).rejects.toThrow(ForbiddenException);
  });

  it('rejects legacy guest tokens without a body email', async () => {
    const { guard, request } = makeGuard();
    request.headers = { authorization: 'Bearer token_user_123' };
    request.body = {};

    await expect(guard.canActivate(makeContext(request))).rejects.toThrow(ForbiddenException);
  });

  it('accepts legacy guest tokens whose body email matches an admin', async () => {
    const { guard, request } = makeGuard();
    request.headers = { authorization: 'Bearer token_user_123' };
    request.body = { adminEmail: `  ${ADMIN_EMAIL}  ` };

    await expect(guard.canActivate(makeContext(request))).resolves.toBe(true);
    expect(request.user.role).toBe('ADMIN');
  });

  it('accepts guest tokens carrying the email claim in the token', async () => {
    const { guard, request } = makeGuard();
    request.headers = { authorization: `Bearer token_user_123::${ADMIN_EMAIL}` };
    request.body = {};

    await expect(guard.canActivate(makeContext(request))).resolves.toBe(true);
    expect(request.user.role).toBe('ADMIN');
  });

  it('prefers the token email claim over a conflicting body email', async () => {
    const { guard, request } = makeGuard();
    request.headers = { authorization: `Bearer token_user_123::${ADMIN_EMAIL}` };
    request.body = { adminEmail: 'someone@else.com' };

    await expect(guard.canActivate(makeContext(request))).resolves.toBe(true);
  });

  it('does not apply the body fallback to verified Google users', async () => {
    const { guard, request } = makeGuard({ sub: 'google_sub', email: 'someone@else.com' });
    request.headers = { authorization: 'Bearer real.google.jwt' };
    request.body = { adminEmail: ADMIN_EMAIL };

    await expect(guard.canActivate(makeContext(request))).rejects.toThrow(ForbiddenException);
  });

  it('accepts verified Google users whose token email matches an admin', async () => {
    const { guard, request } = makeGuard({ sub: 'google_sub', email: ADMIN_EMAIL });
    request.headers = { authorization: 'Bearer real.google.jwt' };
    request.body = {};

    await expect(guard.canActivate(makeContext(request))).resolves.toBe(true);
    expect(request.user.role).toBe('ADMIN');
  });
});