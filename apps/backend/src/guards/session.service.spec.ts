import { createHash } from 'crypto';
import { SessionService } from './session.service';
import { SessionController } from './session.controller';
import { AuthGuard } from './auth.guard';

describe('renewable web sessions', () => {
  const prisma = { $executeRaw: jest.fn(), $queryRaw: jest.fn() };
  let sessions: SessionService;

  beforeEach(() => {
    jest.resetAllMocks();
    prisma.$executeRaw.mockResolvedValue(1);
    prisma.$queryRaw.mockResolvedValue([]);
    sessions = new SessionService(prisma as any);
  });

  it('stores only a hash of a random session token', async () => {
    const token = await sessions.create('google-id', 'user@example.com');
    expect(token).toMatch(/^session_[A-Za-z0-9_-]{43}$/);
    const args = prisma.$executeRaw.mock.calls[0];
    expect(args).toContain(createHash('sha256').update(token).digest('hex'));
    expect(args).not.toContain(token);
  });

  it('renews only an unexpired session and preserves its verified identity', async () => {
    const token = `session_${'a'.repeat(43)}`;
    prisma.$queryRaw.mockResolvedValueOnce([{ userId: 'u1', email: 'u@example.com' }]);
    await expect(sessions.authenticate(token)).resolves.toEqual({ userId: 'u1', email: 'u@example.com' });
    const sql = prisma.$queryRaw.mock.calls[0][0].join(' ');
    expect(sql).toContain('"expiresAt" > NOW()');
    expect(sql).toContain('UPDATE "WebSession"');
    await expect(sessions.authenticate(token)).resolves.toBeNull();
    await sessions.revoke(token);
    expect(prisma.$executeRaw.mock.calls[0][0].join(' ')).toContain('DELETE FROM "WebSession"');
  });

  it('requires a verified Google identity to create a session', async () => {
    const controller = new SessionController(sessions);
    await expect(controller.create({ user: { userId: 'u', email: 'x' } })).rejects.toThrow();
    expect(prisma.$executeRaw).not.toHaveBeenCalled();
  });

  it('rejects expired sessions instead of treating them as Google credentials', async () => {
    const google = { verifyIdToken: jest.fn() };
    const guard = new AuthGuard(google as any, undefined, undefined, undefined, sessions);
    const request = { headers: { authorization: `Bearer session_${'a'.repeat(43)}` } };
    const context = { switchToHttp: () => ({ getRequest: () => request }) };
    await expect(guard.canActivate(context as any)).rejects.toThrow('Invalid or expired session');
    expect(google.verifyIdToken).not.toHaveBeenCalled();
  });
});
