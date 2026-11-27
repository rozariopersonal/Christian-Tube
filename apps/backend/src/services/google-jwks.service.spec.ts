import { GoogleJwksService } from './google-jwks.service';

function makeService(config: Record<string, unknown> = {}): GoogleJwksService {
  const configService = { get: jest.fn((key: string) => config[key]) };
  return new GoogleJwksService(configService as any);
}

describe('GoogleJwksService allowed client IDs', () => {
  it('combines and deduplicates googleClientIds array and comma-separated googleClientId', () => {
    const service = makeService({
      googleClientIds: ['id-a', ' id-b '],
      googleClientId: 'id-b, id-c',
    });

    expect(service.getAllowedClientIds()).toEqual(['id-a', 'id-b', 'id-c']);
  });

  it('throws when no client IDs are configured', async () => {
    const service = makeService();
    await expect(service.verifyIdToken('fake.jwt.token')).rejects.toThrow(
      'Google Client ID not configured',
    );
  });
});