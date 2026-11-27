import { SignJWT } from 'jose';
import { AppJwtService } from './app-jwt.service';

function makeService(configValues: Record<string, unknown>) {
  const config = { get: jest.fn((k: string) => configValues[k]) } as any;
  return new AppJwtService(config);
}

describe('AppJwtService', () => {
  const origEnv = process.env.NODE_ENV;

  afterEach(() => {
    process.env.NODE_ENV = origEnv;
  });

  it('signs with the newest kid and verifies tokens across rotated keys', async () => {
    const keysV1 = JSON.stringify({ v1: 'secret-one-32-bytes-minimum-1234' });
    const svcV1 = makeService({ 'auth.jwtKeysRaw': keysV1 });
    const tokenFromV1 = await svcV1.signAccessToken({
      sub: 'user_1',
      sid: 'sid_1',
      email: 'a@b.com',
    });

    const keysV2 = JSON.stringify({
      v1: 'secret-one-32-bytes-minimum-1234',
      v2: 'secret-two-32-bytes-minimum-5678',
    });
    const svcV2 = makeService({ 'auth.jwtKeysRaw': keysV2 });
    expect(svcV2.getActiveKid()).toBe('v2');

    const verifiedOld = await svcV2.verifyAccessToken(tokenFromV1);
    expect(verifiedOld).toEqual({
      sub: 'user_1',
      sid: 'sid_1',
      email: 'a@b.com',
    });

    const tokenFromV2 = await svcV2.signAccessToken({
      sub: 'user_9',
      sid: 'sid_9',
      email: 'user9@example.com',
    });
    const verifiedNew = await svcV2.verifyAccessToken(tokenFromV2);
    expect(verifiedNew.sub).toBe('user_9');
    expect(verifiedNew.email).toBe('user9@example.com');
  });

  it('rejects legacy guest JWTs and tokens with empty or null email', async () => {
    const secret = 'secret-one-32-bytes-minimum-1234';
    const svc = makeService({
      'auth.jwtKeysRaw': JSON.stringify({ v1: secret }),
    });

    const guestToken = await new SignJWT({
      sid: 'sid_guest',
      email: 'guest@guest.local',
      guest: true,
      typ: 'access',
    })
      .setProtectedHeader({ alg: 'HS256', kid: 'v1' })
      .setIssuer('christian-tube')
      .setAudience('christian-tube-api')
      .setSubject('guest_123')
      .setIssuedAt()
      .setExpirationTime('15m')
      .sign(new TextEncoder().encode(secret));

    await expect(svc.verifyAccessToken(guestToken)).rejects.toThrow();

    const nullEmailToken = await svc.signAccessToken({
      sub: 'u_null',
      sid: 's_null',
      email: null,
    });
    await expect(svc.verifyAccessToken(nullEmailToken)).rejects.toThrow();

    const emptyEmailToken = await svc.signAccessToken({
      sub: 'u_empty',
      sid: 's_empty',
      email: '   ',
    });
    await expect(svc.verifyAccessToken(emptyEmailToken)).rejects.toThrow();
  });

  it('rejects expired tokens', async () => {
    const svc = makeService({
      'auth.jwtKeysRaw': JSON.stringify({ v1: 'secret-one-32-bytes-minimum-1234' }),
      'auth.accessTokenTtlSec': -60,
    });
    const token = await svc.signAccessToken({
      sub: 'u1',
      sid: 's1',
      email: 'a@b.com',
    });
    await expect(svc.verifyAccessToken(token)).rejects.toThrow();
  });

  it('fails fast in production when AUTH_JWT_KEYS is missing', () => {
    process.env.NODE_ENV = 'production';
    const svc = makeService({});
    expect(() => svc.onModuleInit()).toThrow(/AUTH_JWT_KEYS/);
  });
});
