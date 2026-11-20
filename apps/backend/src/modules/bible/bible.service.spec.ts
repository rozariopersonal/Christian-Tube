import { BibleService } from './bible.service';

function makeConfig(values: Record<string, unknown> = {}) {
  return {
    get: jest.fn((key: string) => values[key]),
  } as any;
}

describe('BibleService', () => {
  const savedEnv = { ...process.env };
  const originalFetch = global.fetch;

  beforeEach(() => {
    delete process.env.UPSTASH_VECTOR_REST_URL;
    delete process.env.UPSTASH_VECTOR_REST_TOKEN;
  });

  afterEach(() => {
    process.env = { ...savedEnv };
    global.fetch = originalFetch;
    jest.restoreAllMocks();
  });

  it('returns empty results cleanly when unconfigured or query is blank', async () => {
    const svc = new BibleService(makeConfig());
    expect(svc.isEnabled()).toBe(false);
    expect(svc.getStatus()).toEqual({ enabled: false, provider: 'none' });

    await expect(svc.search('love of God', 10)).resolves.toEqual({
      query: 'love of God',
      count: 0,
      results: [],
    });

    const configured = new BibleService(
      makeConfig({
        'upstashVector.restUrl': 'https://example-vector.upstash.io/',
        'upstashVector.restToken': 'vec-token',
      }),
    );
    expect(configured.isEnabled()).toBe(true);
    await expect(configured.search('   ')).resolves.toEqual({
      query: '',
      count: 0,
      results: [],
    });
  });

  it('queries both verse and windows namespaces, merges by score, and maps passage ranges', async () => {
    const fetchMock = jest.fn(async (url: string) => {
      if (url.endsWith('/query-data/windows')) {
        return {
          ok: true,
          json: async () => ({
            result: [
              {
                id: 'w:10:11:1-5',
                score: 0.95,
                metadata: {
                  b: 10,
                  n: '2 Samuel',
                  c: 11,
                  v: 1,
                  endV: 5,
                  kind: 'window',
                  text: 'God loved the world...',
                },
              },
            ],
          }),
        };
      }
      return {
        ok: true,
        json: async () => ({
          result: [
            {
              id: '43:3:16',
              score: 0.91,
              metadata: {
                b: 43,
                n: 'John',
                c: 3,
                v: 16,
                text: 'For God so loved the world...',
              },
            },
          ],
        }),
      };
    });
    global.fetch = fetchMock as any;

    const svc = new BibleService(
      makeConfig({
        'upstashVector.restUrl': 'https://example-vector.upstash.io/',
        'upstashVector.restToken': 'vec-token',
      }),
    );

    const res = await svc.search('God loved the world', 100);

    expect(fetchMock).toHaveBeenCalledWith(
      'https://example-vector.upstash.io/query-data',
      expect.objectContaining({
        method: 'POST',
        headers: expect.objectContaining({
          Authorization: 'Bearer vec-token',
        }),
        body: JSON.stringify({
          data: 'God loved the world',
          topK: 50,
          includeMetadata: true,
          queryMode: 'DENSE',
        }),
      }),
    );
    expect(fetchMock).toHaveBeenCalledWith(
      'https://example-vector.upstash.io/query-data/windows',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({
          data: 'God loved the world',
          topK: 50,
          includeMetadata: true,
          queryMode: 'DENSE',
        }),
      }),
    );
    expect(res).toEqual({
      query: 'God loved the world',
      count: 2,
      results: [
        {
          id: 'w:10:11:1-5',
          score: 0.95,
          kind: 'passage',
          bookNumber: 10,
          bookName: '2 Samuel',
          chapter: 11,
          verse: 1,
          endVerse: 5,
          reference: '2 Samuel 11:1-5',
          text: 'God loved the world...',
        },
        {
          id: '43:3:16',
          score: 0.91,
          kind: 'verse',
          bookNumber: 43,
          bookName: 'John',
          chapter: 3,
          verse: 16,
          endVerse: null,
          reference: 'John 3:16',
          text: 'For God so loved the world...',
        },
      ],
    });
  });

  it('prefers single verse over passage on equal score ties and falls back if windows fails', async () => {
    const fetchMock = jest.fn(async (url: string) => {
      if (url.endsWith('/query-data/windows')) {
        return {
          ok: true,
          json: async () => ({
            result: [
              {
                id: 'w:43:11:34-38',
                score: 0.9,
                metadata: {
                  b: 43,
                  n: 'John',
                  c: 11,
                  v: 34,
                  endV: 38,
                  kind: 'window',
                  text: '34. ... 35. Jesus wept.',
                },
              },
            ],
          }),
        };
      }
      return {
        ok: true,
        json: async () => ({
          result: [
            {
              id: '43:11:35',
              score: 0.9,
              metadata: {
                b: 43,
                n: 'John',
                c: 11,
                v: 35,
                text: 'Jesus wept.',
              },
            },
          ],
        }),
      };
    });
    global.fetch = fetchMock as any;

    const svc = new BibleService(
      makeConfig({
        'upstashVector.restUrl': 'https://example-vector.upstash.io',
        'upstashVector.restToken': 'vec-token',
      }),
    );

    const tied = await svc.search('jesus wept', 2);
    expect(tied.results.map((r) => r.reference)).toEqual([
      'John 11:35',
      'John 11:34-38',
    ]);

    fetchMock.mockImplementation(async (url: string) => {
      if (url.endsWith('/query-data/windows')) {
        throw new Error('windows timeout');
      }
      return {
        ok: true,
        json: async () => ({
          result: [
            {
              id: '43:11:35',
              score: 0.9,
              metadata: { b: 43, n: 'John', c: 11, v: 35, text: 'Jesus wept.' },
            },
          ],
        }),
      };
    });

    const fallback = await svc.search('jesus wept', 2);
    expect(fallback.results.map((r) => r.reference)).toEqual(['John 11:35']);
  });

  it('filters out low-score noise below minimum threshold and adaptive cutoff', async () => {
    global.fetch = jest.fn(async (url: string) => {
      if (url.endsWith('/query-data/windows')) {
        return { ok: true, json: async () => ({ result: [] }) };
      }
      return {
        ok: true,
        json: async () => ({
          result: [
            {
              id: '43:11:35',
              score: 0.89,
              metadata: { b: 43, n: 'John', c: 11, v: 35, text: 'Jesus wept.' },
            },
            {
              id: '41:10:47',
              score: 0.83,
              metadata: {
                b: 41,
                n: 'Mark',
                c: 10,
                v: 47,
                text: 'He began to cry out, Jesus have mercy on me!',
              },
            },
            {
              id: '1:1:1',
              score: 0.71,
              metadata: { b: 1, n: 'Genesis', c: 1, v: 1, text: 'In the beginning...' },
            },
          ],
        }),
      };
    }) as any;

    const svc = new BibleService(
      makeConfig({
        'upstashVector.restUrl': 'https://example-vector.upstash.io',
        'upstashVector.restToken': 'vec-token',
      }),
    );

    const res = await svc.search('jesus cried', 20);
    expect(res.results.map((r) => r.reference)).toEqual(['John 11:35']);
  });

  it('uses HYBRID rescue only when low-confidence DENSE returns 0 hits above floor', async () => {
    global.fetch = jest.fn(async (url: string, init?: any) => {
      const body = init?.body ? JSON.parse(init.body) : {};
      if (body.fusionAlgorithm === 'RRF') {
        return {
          ok: true,
          json: async () => ({
            result: url.endsWith('/windows')
              ? []
              : [
                  {
                    id: '42:19:4',
                    score: 0.0167,
                    metadata: {
                      b: 42,
                      n: 'Luke',
                      c: 19,
                      v: 4,
                      text: 'He climbed up into a sycamore tree to see him.',
                    },
                  },
                ],
          }),
        };
      }
      return {
        ok: true,
        json: async () => ({
          result: url.endsWith('/windows')
            ? []
            : [
                {
                  id: '42:19:4',
                  score: 0.73,
                  metadata: {
                    b: 42,
                    n: 'Luke',
                    c: 19,
                    v: 4,
                    text: 'He climbed up into a sycamore tree to see him.',
                  },
                },
              ],
        }),
      };
    }) as any;

    const svc = new BibleService(
      makeConfig({
        'upstashVector.restUrl': 'https://example-vector.upstash.io',
        'upstashVector.restToken': 'vec-token',
      }),
    );

    const rescued = await svc.search('zacchaeus climbs sycamore tree', 10);
    expect(rescued.results.map((r) => r.reference)).toEqual(['Luke 19:4']);
  });

  it('caches Bible search results in CacheService for 30 days', async () => {
    const fetchMock = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ result: [] }),
    });
    global.fetch = fetchMock as any;

    const cache = {
      getOrSet: jest.fn((_ns, _key, _ttl, fn) => fn()),
    };

    const svc = new BibleService(
      makeConfig({
        'upstashVector.restUrl': 'https://example-vector.upstash.io',
        'upstashVector.restToken': 'vec-token',
      }),
      cache as any,
    );

    await svc.search('  Peace  of   God ', 15);
    expect(cache.getOrSet).toHaveBeenCalledWith(
      'bible',
      'search:v4:15:peace of god',
      2592000,
      expect.any(Function),
    );
  });

  it('normalizes book typos + cardinals safely and deduplicates overlapping passages', async () => {
    const fetchMock = jest.fn(async (url: string, init?: any) => {
      const body = init?.body ? JSON.parse(init.body) : {};
      if (url.endsWith('/fetch')) {
        return {
          ok: true,
          json: async () => ({
            result: [
              {
                id: '40:6:33',
                metadata: {
                  b: 40,
                  n: 'Matthew',
                  c: 6,
                  v: 33,
                  text: "But seek first God's Kingdom...",
                },
              },
            ],
          }),
        };
      }
      if (url.endsWith('/query-data/windows')) {
        return {
          ok: true,
          json: async () => ({
            result: [
              {
                id: 'w:42:17:10-14',
                score: 0.795,
                metadata: {
                  b: 42,
                  n: 'Luke',
                  c: 17,
                  v: 10,
                  endV: 14,
                  kind: 'window',
                  text: '12. ten men who were lepers met him...',
                },
              },
              {
                id: 'w:42:17:13-17',
                score: 0.79,
                metadata: {
                  b: 42,
                  n: 'Luke',
                  c: 17,
                  v: 13,
                  endV: 17,
                  kind: 'window',
                  text: '13. Jesus, Master... 15. healed... 17. ten cleansed',
                },
              },
            ],
          }),
        };
      }
      return {
        ok: true,
        json: async () => ({
          result: [
            {
              id: '41:3:10',
              score: 0.801,
              metadata: {
                b: 41,
                n: 'Mark',
                c: 3,
                v: 10,
                text: 'For he had healed many...',
              },
            },
          ],
        }),
      };
    });
    global.fetch = fetchMock as any;

    const svc = new BibleService(
      makeConfig({
        'upstashVector.restUrl': 'https://example-vector.upstash.io',
        'upstashVector.restToken': 'vec-token',
      }),
    );

    const leporsRes = await svc.search('jesus healed the 10 lepors', 10);
    expect(fetchMock).toHaveBeenCalledWith(
      'https://example-vector.upstash.io/query-data',
      expect.objectContaining({
        body: expect.stringContaining('"jesus healed the ten lepors"'),
      }),
    );
    expect(leporsRes.results[0].reference).toBe('Luke 17:13-17');
    // Overlapping Luke 17:10-14 passage is collapsed once Luke 17:13-17 is picked.
    expect(leporsRes.results.map((r) => r.reference)).toEqual([
      'Luke 17:13-17',
      'Mark 3:10',
    ]);

    const typoRefRes = await svc.search('mathew 6:33', 5);
    expect(typoRefRes.results[0].reference).toBe('Matthew 6:33');
    expect(typoRefRes.results[0].score).toBe(1);
  });

  it('degrades gracefully without caching when Upstash Vector fails', async () => {
    global.fetch = jest.fn().mockRejectedValue(new Error('network down')) as any;
    const store = new Map<string, unknown>();
    const cache = {
      getOrSet: jest.fn(async (_ns, key, _ttl, fn) => {
        const val = await fn();
        store.set(key, val);
        return val;
      }),
    };

    const svc = new BibleService(
      makeConfig({
        'upstashVector.restUrl': 'https://example-vector.upstash.io',
        'upstashVector.restToken': 'vec-token',
      }),
      cache as any,
    );

    const res = await svc.search('hope');
    expect(res).toEqual({ query: 'hope', count: 0, results: [] });
    expect(store.size).toBe(0);
  });
});
