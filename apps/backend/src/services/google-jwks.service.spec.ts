import { GoogleJwksService } from './google-jwks.service';

function makeService(): GoogleJwksService {
  const configService = { get: jest.fn(() => undefined) };
  return new GoogleJwksService(configService as any);
}

describe('GoogleJwksService guest tokens', () => {
  const service = makeService();

  it('detects guest tokens by the token_ prefix', () => {
    expect(service.isGuestToken('token_user_123')).toBe(true);
    expect(service.isGuestToken('token_user_123::admin@example.com')).toBe(true);
    expect(service.isGuestToken('not-a-guest-token')).toBe(false);
    expect(service.isGuestToken('')).toBe(false);
  });

  it('parses the identity id from legacy and email-embedding tokens', () => {
    expect(service.parseGuestToken('token_user_123')).toBe('user_123');
    expect(service.parseGuestToken('token_user_123::admin@example.com')).toBe('user_123');
    expect(service.parseGuestToken('token_')).toBeNull();
    expect(service.parseGuestToken('regular-token')).toBeNull();
  });

  it('returns the claimed email when present and null otherwise', () => {
    expect(service.parseGuestEmail('token_user_123::admin@example.com')).toBe('admin@example.com');
    expect(service.parseGuestEmail('token_user_123:: admin@example.com ')).toBe('admin@example.com');
    expect(service.parseGuestEmail('token_user_123')).toBeNull();
    expect(service.parseGuestEmail('token_user_123::')).toBeNull();
    expect(service.parseGuestEmail('regular-token')).toBeNull();
  });
});