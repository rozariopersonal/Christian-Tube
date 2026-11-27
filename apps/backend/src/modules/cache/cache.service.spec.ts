import { CacheService } from './cache.service';

function makeConfig(values: Record<string, unknown> = {}) {
  return {
    get: jest.fn((key: string) => values[key]),
  } as any;
}

describe('CacheService', () => {
  const savedEnv = { ...process.env };
  const originalFetch = global.fetch;

  beforeEach(() => {
    delete process.env.UPSTASH_REDIS_REST_URL;
    delete process.env.UPSTASH_REDIS_REST_TOKEN;
    delete process.env.REDIS_URL;
    delete process.env.UPSTASH_REDIS_URL;
  });

  afterEach(() => {
    process.env = { ...savedEnv };
    global.fetch = originalFetch;
    jest.restoreAllMocks();
  });

  it('passes through directly to loader when Upstash/Redis is not configured', async () => {
    const svc = new CacheService(makeConfig({ instanceId: 'christian_tube' }));
    expect(svc.isEnabled()).toBe(false);
    expect(svc.getStatus()).toEqual({
      enabled: false,
      provider: 'none',
      prefix: 'ct:christian_tube',
    });

    const loader = jest.fn().mockResolvedValue([{ id: 'v1' }]);
    const res1 = await svc.getOrSet('videos', 'feed:1', 300, loader);
    const res2 = await svc.getOrSet('videos', 'feed:1', 300, loader);

    expect(res1).toEqual([{ id: 'v1' }]);
    expect(res2).toEqual([{ id: 'v1' }]);
    expect(loader).toHaveBeenCalledTimes(2);
    await expect(svc.invalidate('videos')).resolves.toBeUndefined();
  });

  it('uses Upstash REST API for getOrSet (miss then hit) and versioned invalidation', async () => {
    const store = new Map<string, string>();
    const fetchMock = jest.fn(async (_url: string, init: any) => {
      const args = JSON.parse(init.body) as (string | number)[];
      const cmd = String(args[0]).toUpperCase();
      if (cmd === 'GET') {
        const key = String(args[1]);
        return {
          ok: true,
          json: async () => ({ result: store.get(key) ?? null }),
        } as any;
      }
      if (cmd === 'SET') {
        const key = String(args[1]);
        const val = String(args[2]);
        store.set(key, val);
        return {
          ok: true,
          json: async () => ({ result: 'OK' }),
        } as any;
      }
      if (cmd === 'INCR') {
        const key = String(args[1]);
        const next = Number(store.get(key) ?? '0') + 1;
        store.set(key, String(next));
        return {
          ok: true,
          json: async () => ({ result: next }),
        } as any;
      }
      throw new Error(`Unexpected command ${cmd}`);
    });
    global.fetch = fetchMock as any;

    const svc = new CacheService(
      makeConfig({
        instanceId: 'christian_tube',
        'redis.upstashRestUrl': 'https://example-upstash.upstash.io/',
        'redis.upstashRestToken': 'secret-token',
      }),
    );

    expect(svc.isEnabled()).toBe(true);
    expect(svc.getStatus().provider).toBe('upstash-rest');

    const loader = jest
      .fn()
      .mockResolvedValueOnce([{ id: 'v1' }])
      .mockResolvedValueOnce([{ id: 'v2' }]);

    // 1. Miss -> calls loader, populates Upstash
    const first = await svc.getOrSet('videos', 'feed:default', 300, loader);
    expect(first).toEqual([{ id: 'v1' }]);
    expect(loader).toHaveBeenCalledTimes(1);

    // 2. Hit -> returns cached data without calling loader
    const second = await svc.getOrSet('videos', 'feed:default', 300, loader);
    expect(second).toEqual([{ id: 'v1' }]);
    expect(loader).toHaveBeenCalledTimes(1);

    // 3. Invalidate -> bumps namespace version, next read calls loader
    await svc.invalidate('videos');
    const third = await svc.getOrSet('videos', 'feed:default', 300, loader);
    expect(third).toEqual([{ id: 'v2' }]);
    expect(loader).toHaveBeenCalledTimes(2);
  });

  it('degrades gracefully to DB loader if Upstash REST fails', async () => {
    global.fetch = jest.fn().mockRejectedValue(new Error('network timeout')) as any;

    const svc = new CacheService(
      makeConfig({
        instanceId: 'christian_tube',
        'redis.upstashRestUrl': 'https://example-upstash.upstash.io',
        'redis.upstashRestToken': 'secret-token',
      }),
    );

    const loader = jest.fn().mockResolvedValue({ ok: true });
    const result = await svc.getOrSet('channels', 'list:ALL', 600, loader);

    expect(result).toEqual({ ok: true });
    expect(loader).toHaveBeenCalledTimes(1);
    await expect(svc.invalidate('channels')).resolves.toBeUndefined();
  });

  it('does not write null or undefined loader results into cache', async () => {
    const fetchMock = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ result: null }),
    });
    global.fetch = fetchMock as any;

    const svc = new CacheService(
      makeConfig({
        instanceId: 'christian_tube',
        'redis.upstashRestUrl': 'https://example-upstash.upstash.io',
        'redis.upstashRestToken': 'secret-token',
      }),
    );

    const out = await svc.getOrSet('audio', 'yt:missing', 900, async () => null);
    expect(out).toBeNull();
    const commands = fetchMock.mock.calls.map((c: any) => JSON.parse(c[1].body)[0]);
    expect(commands).not.toContain('SET');
  });

  it('skips caching when shouldCache returns false and deduplicates concurrent misses', async () => {
    const fetchMock = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ result: null }),
    });
    global.fetch = fetchMock as any;

    const svc = new CacheService(
      makeConfig({
        instanceId: 'christian_tube',
        'redis.upstashRestUrl': 'https://example-upstash.upstash.io',
        'redis.upstashRestToken': 'secret-token',
      }),
    );

    let calls = 0;
    const loader = jest.fn(async () => {
      calls++;
      await new Promise((r) => setTimeout(r, 20));
      return { ids: ['v1'], degraded: true };
    });

    const [a, b] = await Promise.all([
      svc.getOrSet('video-search', 'cand:grace', 3600, loader, {
        shouldCache: (v) => !v.degraded,
      }),
      svc.getOrSet('video-search', 'cand:grace', 3600, loader, {
        shouldCache: (v) => !v.degraded,
      }),
    ]);

    expect(a).toEqual({ ids: ['v1'], degraded: true });
    expect(b).toEqual({ ids: ['v1'], degraded: true });
    expect(calls).toBe(1);
    const commands = fetchMock.mock.calls.map((c: any) => JSON.parse(c[1].body)[0]);
    expect(commands).not.toContain('SET');
  });
});
