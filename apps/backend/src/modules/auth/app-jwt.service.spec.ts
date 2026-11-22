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
      isGuest: false,
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
      isGuest: false,
    });

    const tokenFromV2 = await svcV2.signAccessToken({
      sub: 'guest_9',
      sid: 'sid_9',
      email: null,
      isGuest: true,
    });
    const verifiedNew = await svcV2.verifyAccessToken(tokenFromV2);
    expect(verifiedNew.isGuest).toBe(true);
    expect(verifiedNew.email).toBeNull();
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
      isGuest: false,
    });
    await expect(svc.verifyAccessToken(token)).rejects.toThrow();
  });

  it('fails fast in production when AUTH_JWT_KEYS is missing', () => {
    process.env.NODE_ENV = 'production';
    const svc = makeService({});
    expect(() => svc.onModuleInit()).toThrow(/AUTH_JWT_KEYS/);
  });
});
