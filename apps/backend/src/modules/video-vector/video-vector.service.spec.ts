import { VideoVectorService } from './video-vector.service';

function makeConfig(values: Record<string, unknown> = {}) {
  return {
    get: jest.fn((key: string) => values[key]),
  } as any;
}

describe('VideoVectorService', () => {
  const originalFetch = global.fetch;
  const savedEnv = { ...process.env };

  beforeEach(() => {
    delete process.env.UPSTASH_VIDEO_VECTOR_REST_URL;
    delete process.env.UPSTASH_VIDEO_VECTOR_REST_TOKEN;
    delete process.env.UPSTASH_VECTOR_REST_URL;
    delete process.env.UPSTASH_VECTOR_REST_TOKEN;
  });

  afterEach(() => {
    global.fetch = originalFetch;
    process.env = { ...savedEnv };
    jest.restoreAllMocks();
  });

  it('scrubs CT_META comments, URLs, emails, handles, and hashtag walls', () => {
    const svc = new VideoVectorService(makeConfig());
    const doc = svc.buildDocument({
      id: 'abc12345678',
      title: 'Finding Peace in the Storm',
      channelId: 'UC123',
      channelName: 'CFC India',
      category: 'Sermons',
      tags: ['#Shorts', 'grace', 'peace'],
      description:
        '<!-- CT_META: {"sourceVideoId":"xyz"} --> A message about trusting God in trials. Visit https://example.org/donate or email info@example.org @cfcindia #faith #hope #love #sermon',
      metadata: { speaker: 'Zac Poonen' },
    });

    expect(doc.data).toContain('Finding Peace in the Storm');
    expect(doc.data).toContain('CFC India');
    expect(doc.data).toContain('Zac Poonen');
    expect(doc.data).toContain('A message about trusting God in trials.');
    expect(doc.data).not.toContain('CT_META');
    expect(doc.data).not.toContain('https://example.org');
    expect(doc.data).not.toContain('info@example.org');
    expect(doc.data).not.toContain('@cfcindia');
    expect(doc.data).not.toContain('#faith');
    expect(doc.metadata).toMatchObject({
      type: 'VIDEO',
      channelId: 'UC123',
      category: 'Sermons',
    });
  });

  it('skips Upstash query for <2 char queries and applies cosine floor + adaptive cutoff', async () => {
    const fetchMock = jest.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        result: [
          { id: 'v1', score: 0.88 },
          { id: 'v2', score: 0.78 },
          { id: 'v3', score: 0.42 }, // below cutoff -> rejected
        ],
      }),
    });
    global.fetch = fetchMock as any;

    const svc = new VideoVectorService(
      makeConfig({
        'upstashVideoVector.restUrl': 'https://vec.upstash.io',
        'upstashVideoVector.restToken': 'tok',
        'upstashVideoVector.namespace': 'videos',
        'upstashVideoVector.minScore': 0.6,
      }),
    );

    const shortRes = await svc.query('a');
    expect(shortRes).toEqual({ ids: [], degraded: false });
    expect(fetchMock).not.toHaveBeenCalled();

    const res = await svc.query('peace in storm', { type: 'VIDEO' }, 50);
    expect(res).toEqual({ ids: ['v1', 'v2'], degraded: false });
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe('https://vec.upstash.io/query-data/videos');
    const body = JSON.parse(init.body);
    expect(body.queryMode).toBe('DENSE');
    expect(body.filter).toBe("type = 'VIDEO'");
  });

  it('opens circuit breaker on 429 and returns degraded=true without re-calling Upstash', async () => {
    const fetchMock = jest.fn().mockResolvedValue({
      ok: false,
      status: 429,
      text: async () => 'Daily limit reached',
    });
    global.fetch = fetchMock as any;

    const svc = new VideoVectorService(
      makeConfig({
        'upstashVideoVector.restUrl': 'https://vec.upstash.io',
        'upstashVideoVector.restToken': 'tok',
      }),
    );

    const first = await svc.query('grace');
    const second = await svc.query('mercy');

    expect(first).toEqual({ ids: [], degraded: true });
    expect(second).toEqual({ ids: [], degraded: true });
    expect(svc.isCircuitOpen()).toBe(true);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('skips unchanged videos via VideoPipelineStatus upstashHash check', async () => {
    const fetchMock = jest.fn().mockResolvedValue({ ok: true, status: 200 });
    global.fetch = fetchMock as any;

    const svc = new VideoVectorService(
      makeConfig({
        'upstashVideoVector.restUrl': 'https://vec.upstash.io',
        'upstashVideoVector.restToken': 'tok',
      }),
    );

    const v1 = { id: 'v1', title: 'Same', channelId: 'c1', channelName: 'Ch' };
    const v2 = { id: 'v2', title: 'New', channelId: 'c1', channelName: 'Ch' };
    const hash1 = svc.buildDocument(v1).hash;

    const prisma = {
      $queryRawUnsafe: jest.fn().mockResolvedValue([{ videoId: 'v1', upstashHash: hash1 }]),
      $executeRawUnsafe: jest.fn().mockResolvedValue(1),
    };
    const svcWithPrisma = new VideoVectorService(
      makeConfig({
        'upstashVideoVector.restUrl': 'https://vec.upstash.io',
        'upstashVideoVector.restToken': 'tok',
      }),
      prisma as any,
    );

    const out = await svcWithPrisma.upsertVideos([v1, v2]);
    expect(out).toEqual({ upserted: 1, skipped: 1 });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const body = JSON.parse(fetchMock.mock.calls[0][1].body);
    expect(body).toHaveLength(1);
    expect(body[0].id).toBe('v2');
  });

  it('sends DELETE with { ids } payload in deleteIds and respects maxInlineOps cap', async () => {
    const fetchMock = jest.fn().mockResolvedValue({ ok: true, status: 200 });
    global.fetch = fetchMock as any;

    const svc = new VideoVectorService(
      makeConfig({
        'upstashVideoVector.restUrl': 'https://vec.upstash.io',
        'upstashVideoVector.restToken': 'tok',
        'upstashVideoVector.namespace': 'videos',
        'upstashVideoVector.maxInlineOps': 2,
      }),
    );

    const deleted = await svc.deleteIds(['id1', 'id2', 'id3']);
    expect(deleted).toBe(2);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe('https://vec.upstash.io/delete/videos');
    expect(init.method).toBe('DELETE');
    expect(JSON.parse(init.body)).toEqual({ ids: ['id1', 'id2'] });
  });

  it('auto-falls back to omitting queryMode when a pure-dense index rejects it with 400', async () => {
    const fetchMock = jest
      .fn()
      .mockResolvedValueOnce({
        ok: false,
        status: 400,
        text: async () => 'queryMode is only supported on hybrid indexes',
      })
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({ result: [{ id: 'v1', score: 0.85 }] }),
      });
    global.fetch = fetchMock as any;

    const svc = new VideoVectorService(
      makeConfig({
        'upstashVideoVector.restUrl': 'https://vec.upstash.io',
        'upstashVideoVector.restToken': 'tok',
      }),
    );

    const res = await svc.query('grace');
    expect(res).toEqual({ ids: ['v1'], degraded: false });
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(JSON.parse(fetchMock.mock.calls[1][1].body).queryMode).toBeUndefined();
  });

  it('blocks upserts and deletes when readOnly is true (staging safety)', async () => {
    const fetchMock = jest.fn();
    global.fetch = fetchMock as any;

    const svc = new VideoVectorService(
      makeConfig({
        'upstashVideoVector.restUrl': 'https://vec.upstash.io',
        'upstashVideoVector.restToken': 'tok',
        'upstashVideoVector.readOnly': true,
      }),
    );

    const upserted = await svc.upsertVideos([
      { id: 'v1', title: 'Test', channelId: 'c1', channelName: 'Ch' },
    ]);
    const deleted = await svc.deleteIds(['v1']);

    expect(upserted).toEqual({ upserted: 0, skipped: 1 });
    expect(deleted).toBe(0);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
