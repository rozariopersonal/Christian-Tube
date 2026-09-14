import { EmbeddingService } from './embedding.service';

const DIM = 384;
const vector = () => new Array(DIM).fill(0.5);

function makeService(
  overrides: {
    enabled?: boolean;
    serviceUrl?: string;
    authToken?: string;
    dim?: number;
    version?: number;
  } = {},
) {
  const values: Record<string, any> = {
    'embedding.enabled': overrides.enabled ?? true,
    'embedding.serviceUrl': overrides.serviceUrl ?? 'http://embed.test',
    'embedding.authToken': overrides.authToken ?? 'tok',
    'embedding.model': 'intfloat/multilingual-e5-small',
    'embedding.dim': overrides.dim ?? DIM,
    'embedding.version': overrides.version ?? 1,
  };
  const configService = { get: jest.fn((key: string) => values[key]) };
  const prisma = { $executeRawUnsafe: jest.fn().mockResolvedValue(0) };
  const service = new EmbeddingService(configService as any, prisma as any);
  return { service, configService, prisma, values };
}

function okResponse(embedding: number[] = vector()) {
  return {
    ok: true,
    json: async () => ({
      embedding,
      dim: DIM,
      model: 'intfloat/multilingual-e5-small',
      version: 1,
    }),
  };
}

describe('EmbeddingService', () => {
  afterEach(() => {
    jest.useRealTimers();
    (globalThis as any).fetch = undefined;
  });

  describe('e5 prefix contract', () => {
    it('queryText prefixes queries with "query: " and trims whitespace', () => {
      const { service } = makeService();
      expect(service.queryText('  trust God through trials  ')).toBe(
        'query: trust God through trials',
      );
      expect(service.queryText('')).toBe('query: ');
    });

    it('passageText prefixes with "passage: " and joins title + description', () => {
      const { service } = makeService();
      expect(service.passageText('Grace Alone', undefined)).toBe(
        'passage: Grace Alone',
      );
      expect(service.passageText('Grace Alone', null)).toBe('passage: Grace Alone');
      expect(service.passageText('Grace Alone', '  Ephesians 2:8  ')).toBe(
        'passage: Grace Alone Ephesians 2:8',
      );
      expect(service.passageText('', 'Only description')).toBe(
        'passage: Only description',
      );
    });
  });

  describe('configuration', () => {
    it('falls back to the shared contract defaults when env is absent', () => {
      const configService = { get: jest.fn(() => undefined) };
      const prisma = { $executeRawUnsafe: jest.fn() };
      const service = new EmbeddingService(configService as any, prisma as any);
      expect(service.modelName).toBe('intfloat/multilingual-e5-small');
      expect(service.modelVersion).toBe(1);
      expect(service.embeddingDim).toBe(DIM);
      expect(service.isEnabled).toBe(false);
    });

    it('isEnabled requires both enabled flag and a service URL', () => {
      const { service } = makeService({ enabled: false });
      expect(service.isEnabled).toBe(false);
      const { service: noUrl } = makeService({ serviceUrl: '' });
      expect(noUrl.isEnabled).toBe(false);
    });
  });

  describe('contentHash', () => {
    it('is deterministic for identical content and unique for different content', () => {
      const { service } = makeService();
      expect(service.contentHash('a', 'b')).toBe(service.contentHash('a', 'b'));
      expect(service.contentHash('a', 'b')).not.toBe(service.contentHash('a', 'c'));
      expect(service.contentHash('a', 'b')).not.toBe(service.contentHash('b', 'a'));
    });
  });

  describe('embedQuery', () => {
    it('returns null without calling the service when disabled', async () => {
      const fetchMock = jest.fn();
      (globalThis as any).fetch = fetchMock;
      const { service } = makeService({ enabled: false });
      await expect(service.embedQuery('anything')).resolves.toBeNull();
      expect(fetchMock).not.toHaveBeenCalled();
    });

    it('calls /embed with Bearer auth and the query: prefix, returning the vector', async () => {
      const fetchMock = jest.fn().mockResolvedValue(okResponse());
      (globalThis as any).fetch = fetchMock;
      const { service } = makeService({ authToken: 'secret' });

      const result = await service.embedQuery('love');
      expect(result).toEqual(vector());
      expect(fetchMock).toHaveBeenCalledWith(
        'http://embed.test/embed',
        expect.objectContaining({
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: 'Bearer secret',
          },
          body: JSON.stringify({ text: 'query: love' }),
        }),
      );
    });

    it('caches results within the TTL so the service is not re-hit', async () => {
      const fetchMock = jest.fn().mockResolvedValue(okResponse());
      (globalThis as any).fetch = fetchMock;
      const { service } = makeService();

      await service.embedQuery('grace');
      await service.embedQuery('grace');
      expect(fetchMock).toHaveBeenCalledTimes(1);
    });

    it('cache lookup is case-insensitive', async () => {
      const fetchMock = jest.fn().mockResolvedValue(okResponse());
      (globalThis as any).fetch = fetchMock;
      const { service } = makeService();

      await service.embedQuery('Heaven');
      await service.embedQuery('heaven');
      expect(fetchMock).toHaveBeenCalledTimes(1);
    });

    it('evicts the least-recently-used entry beyond the cache bound', async () => {
      const fetchMock = jest
        .fn()
        .mockResolvedValue(okResponse(new Array(DIM).fill(0.25)));
      (globalThis as any).fetch = fetchMock;
      const { service } = makeService();
      (service as any).maxCacheEntries = 2;

      await service.embedQuery('a');
      await service.embedQuery('b');
      await service.embedQuery('c'); // evicts 'a'
      await service.embedQuery('a'); // refetch, evicts 'b'
      expect(fetchMock).toHaveBeenCalledTimes(4);
    });

    it('returns null when the service responds with a non-2xx status', async () => {
      (globalThis as any).fetch = jest.fn().mockResolvedValue({ ok: false, status: 500 });
      const { service } = makeService();
      await expect(service.embedQuery('x')).resolves.toBeNull();
    });

    it('returns null when the vector has the wrong dimension', async () => {
      (globalThis as any).fetch = jest.fn().mockResolvedValue(okResponse([1, 2, 3]));
      const { service } = makeService();
      await expect(service.embedQuery('x')).resolves.toBeNull();
    });

    it('returns null when the response has no embedding array', async () => {
      (globalThis as any).fetch = jest
        .fn()
        .mockResolvedValue({ ok: true, json: async () => ({ dim: DIM }) });
      const { service } = makeService();
      await expect(service.embedQuery('x')).resolves.toBeNull();
    });

    it('returns null when the network request fails', async () => {
      (globalThis as any).fetch = jest
        .fn()
        .mockRejectedValue(new Error('ECONNREFUSED'));
      const { service } = makeService();
      await expect(service.embedQuery('x')).resolves.toBeNull();
    });

    it('returns null when the service exceeds the timeout', async () => {
      jest.useFakeTimers();
      const fetchMock = jest.fn(
        (_url: string, init: any) =>
          new Promise((_resolve, reject) => {
            init.signal.addEventListener('abort', () =>
              reject(new Error('The operation was aborted')),
            );
          }),
      );
      (globalThis as any).fetch = fetchMock;
      const { service } = makeService();

      const pending = service.embedQuery('slow');
      await jest.advanceTimersByTimeAsync(1600);
      await expect(pending).resolves.toBeNull();
    });
  });

  describe('reconcilePendingEmbeddings', () => {
    it('re-queues completed embeddings whose version does not match', async () => {
      const { service, prisma } = makeService();
      prisma.$executeRawUnsafe.mockResolvedValue(7);
      await service.reconcilePendingEmbeddings();
      expect(prisma.$executeRawUnsafe).toHaveBeenCalledTimes(1);
      const [sql, version] = prisma.$executeRawUnsafe.mock.calls[0];
      expect(sql).toContain(`SET "embeddingStatus" = 'pending'`);
      expect(sql).toContain('"embeddingVersion" <> $1');
      expect(version).toBe(1);
    });

    it('does nothing when disabled', async () => {
      const { service, prisma } = makeService({ enabled: false });
      await service.reconcilePendingEmbeddings();
      expect(prisma.$executeRawUnsafe).not.toHaveBeenCalled();
    });

    it('swallows database errors so the cron cannot crash the app', async () => {
      const { service, prisma } = makeService();
      prisma.$executeRawUnsafe.mockRejectedValue(new Error('connection lost'));
      await expect(service.reconcilePendingEmbeddings()).resolves.toBeUndefined();
    });
  });
});