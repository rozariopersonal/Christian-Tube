import { VideosService } from './videos.service';

const DIM = 384;

function row(id: string) {
  return {
    id,
    title: `Title ${id}`,
    description: `Description ${id}`,
    type: 'VIDEO',
    channel: { id: 'c1', name: `Channel ${id}`, thumbnail: null },
    publishedAt: new Date(),
  };
}

function makeService(
  vectorIds: string[] | null = null,
  config: Record<string, unknown> = {},
  cache?: { getOrSet: jest.Mock; invalidate: jest.Mock },
  youtubeOrDegraded?: { verifyVideosVisibility: jest.Mock } | boolean,
) {
  const vectorDegraded = typeof youtubeOrDegraded === 'boolean' ? youtubeOrDegraded : false;
  const youtubeServiceOverride =
    typeof youtubeOrDegraded === 'object' ? youtubeOrDegraded : undefined;
  const prisma = {
    video: { findMany: jest.fn(), findUnique: jest.fn(), upsert: jest.fn(), deleteMany: jest.fn().mockResolvedValue({ count: 0 }) },
    channel: { upsert: jest.fn(), findMany: jest.fn().mockResolvedValue([]) },
    shortCreation: { deleteMany: jest.fn().mockResolvedValue({ count: 0 }) },
    $queryRawUnsafe: jest.fn(),
    $executeRawUnsafe: jest.fn().mockResolvedValue(1),
  };
  const configService = { get: jest.fn((key: string) => config[key]) };
  const embeddingService = {
    modelName: 'intfloat/multilingual-e5-small',
    modelVersion: 1,
    embedQuery: jest.fn().mockResolvedValue(null),
  };
  const youtubeService = youtubeServiceOverride || {
    verifyVideosVisibility: jest.fn().mockImplementation(async (ids: string[]) =>
      new Map(
        ids.map((id) => [
          id,
          {
            videoId: id,
            status: 'eligible',
            item: {
              id,
              snippet: { title: `Verified ${id}`, description: '' },
              contentDetails: { duration: 'PT45S' },
              status: { privacyStatus: 'public' },
            },
          },
        ]),
      ),
    ),
  };
  const videoVector =
    vectorIds !== null
      ? {
          isEnabled: jest.fn().mockReturnValue(true),
          query: jest.fn().mockResolvedValue({ ids: vectorIds, degraded: vectorDegraded }),
          upsertVideos: jest.fn().mockResolvedValue({ upserted: 1, skipped: 0 }),
          deleteIds: jest.fn().mockResolvedValue(0),
        }
      : {
          isEnabled: jest.fn().mockReturnValue(false),
          query: jest.fn().mockResolvedValue({ ids: [], degraded: false }),
          upsertVideos: jest.fn().mockResolvedValue({ upserted: 0, skipped: 0 }),
          deleteIds: jest.fn().mockResolvedValue(0),
        };
  const service = new VideosService(
    prisma as any,
    configService as any,
    embeddingService as any,
    cache as any,
    youtubeService as any,
    videoVector as any,
  );
  return { service, prisma, configService, embeddingService, videoVector, cache, youtubeService };
}

describe('VideosService', () => {
  describe('findAll', () => {
    it('uses keyword-only query when no search term is provided', async () => {
      const { service, prisma } = makeService();
      prisma.video.findMany.mockResolvedValue([row('v1'), row('v2')]);

      const out = await service.findAll({});

      expect(prisma.video.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({ channel: { isActive: true }, type: 'VIDEO' }),
          take: 50,
          skip: 0,
        }),
      );
      expect(prisma.$queryRawUnsafe).not.toHaveBeenCalled();
      expect(out).toHaveLength(2);
      expect(out[0]).toMatchObject({
        id: 'v1',
        channelName: 'Channel v1',
        channelTitle: 'Channel v1',
      });
    });

    it('falls back to lexical search when Upstash VideoVector is disabled', async () => {
      const { service, prisma, videoVector } = makeService(null);
      prisma.video.findMany.mockImplementation((args: any) => {
        if (args.where?.id?.in) {
          return Promise.resolve(args.where.id.in.map((id: string) => row(id)));
        }
        if (args.where?.OR) {
          return Promise.resolve([{ id: 'v1' }]);
        }
        return Promise.resolve([]);
      });

      const out = await service.findAll({ search: 'love  God' });

      expect(videoVector.query).not.toHaveBeenCalled();
      expect(out).toHaveLength(1);
      expect(out[0].id).toBe('v1');
    });

    it('runs hybrid Upstash Vector + lexical RRF search when VideoVector is enabled', async () => {
      const { service, prisma, videoVector } = makeService(['v2', 'v1']);
      prisma.video.findMany.mockImplementation((args: any) => {
        if (args.where?.id?.in) {
          return Promise.resolve(args.where.id.in.map((id: string) => row(id)));
        }
        if (args.where?.OR) {
          return Promise.resolve([{ id: 'v1' }, { id: 'v3' }]);
        }
        return Promise.resolve([]);
      });

      const out = await service.findAll({ search: 'grace', limit: 5, offset: 0 });

      expect(videoVector.query).toHaveBeenCalledWith(
        'grace',
        expect.objectContaining({ type: 'VIDEO' }),
        100,
      );
      // RRF: v1 appears in both lexical and vector lists so it ranks #1
      expect(out.map((v: any) => v.id)).toEqual(['v1', 'v2', 'v3']);
    });

    it('pages through the fused result list with offset and limit', async () => {
      const { service, prisma } = makeService(['v2', 'v1']);
      prisma.video.findMany.mockImplementation((args: any) => {
        if (args.where?.id?.in) {
          return Promise.resolve(args.where.id.in.map((id: string) => row(id)));
        }
        if (args.where?.OR) {
          return Promise.resolve([{ id: 'v1' }, { id: 'v3' }]);
        }
        return Promise.resolve([]);
      });

      const out = await service.findAll({ search: 'grace', limit: 1, offset: 1 });

      expect(prisma.video.findMany).toHaveBeenLastCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            id: { in: ['v2'] },
            channel: { isActive: true },
          }),
        }),
      );
      expect(out.map((v: any) => v.id)).toEqual(['v2']);
    });

    it('degrades to lexical results and marks degraded=true when Upstash Vector fails', async () => {
      const cache = {
        getOrSet: jest.fn((_ns, _k, _ttl, fn, opts) => {
          return fn().then((val: any) => {
            expect(opts?.shouldCache?.(val)).toBe(false);
            return val;
          });
        }),
        invalidate: jest.fn().mockResolvedValue(undefined),
      };
      const { service, prisma } = makeService([], {}, cache, true);
      prisma.video.findMany.mockImplementation((args: any) => {
        if (args.where?.id?.in) {
          return Promise.resolve(args.where.id.in.map((id: string) => row(id)));
        }
        if (args.where?.OR) {
          return Promise.resolve([{ id: 'v1' }, { id: 'v2' }]);
        }
        return Promise.resolve([]);
      });

      const out = await service.findAll({ search: 'grace' });

      expect(out.map((v: any) => v.id)).toEqual(['v1', 'v2']);
      expect(cache.getOrSet).toHaveBeenCalledWith(
        'video-search',
        expect.stringContaining('q=grace'),
        6 * 3600,
        expect.any(Function),
        expect.objectContaining({ shouldCache: expect.any(Function) }),
      );
    });

    it('pins exact YouTube ID/URL matches at position #1 and clamps extreme limits', async () => {
      const { service, prisma } = makeService(['v2']);
      prisma.video.findMany.mockImplementation((args: any) => {
        if (args.where?.id?.in) {
          return Promise.resolve(args.where.id.in.map((id: string) => row(id)));
        }
        return Promise.resolve([]);
      });

      const out = await service.findAll({
        search: 'https://youtu.be/dQw4w9WgXcQ',
        limit: 99999,
        offset: -5,
      });

      expect(out[0].id).toBe('dQw4w9WgXcQ');
      expect((service as any).clampLimit(99999)).toBe(100);
      expect((service as any).clampOffset(-5)).toBe(0);
    });

    it('includes sort in Redis cache keys so relevance, latest, and popular never collide', async () => {
      const cache = {
        getOrSet: jest.fn((_ns, _k, _ttl, fn) => fn()),
        invalidate: jest.fn().mockResolvedValue(undefined),
      };
      const { service, prisma } = makeService(null, {}, cache);
      prisma.video.findMany.mockResolvedValue([]);

      await service.findAll({ search: 'grace', sort: 'latest' });
      await service.findAll({ search: 'grace', sort: 'popular' });

      const keys = cache.getOrSet.mock.calls.map((c: any[]) => c[1]);
      expect(keys[0]).toContain('sort=latest');
      expect(keys[1]).toContain('sort=popular');
      expect(keys[0]).not.toBe(keys[1]);
    });
  });

  describe('fuseRanks (RRF over vector + keyword lists)', () => {
    it('ranks ids present in both lists above ids present in only one', () => {
      const { service } = makeService();
      const fused = (service as any).fuseRanks([['a', 'b', 'c'], ['b', 'c', 'd']]);
      expect(fused[0]).toBe('b');
      expect(fused[1]).toBe('c');
      expect(fused).toContain('a');
      expect(fused).toContain('d');
    });

    it('deduplicates ids across lists', () => {
      const { service } = makeService();
      const fused = (service as any).fuseRanks([['a', 'b'], ['b', 'a']]);
      expect(fused).toHaveLength(2);
      expect(new Set(fused).size).toBe(2);
    });

    it('returns an empty list when given no candidates', () => {
      const { service } = makeService();
      expect((service as any).fuseRanks([[]])).toEqual([]);
    });
  });

  describe('buildBaseFilterSql', () => {
    it('renders type, category and single channel as positional parameters', () => {
      const { service } = makeService();
      const sql = (service as any).buildBaseFilterSql({
        type: 'SHORT',
        category: 'Worship',
        channelId: 'c1',
      });
      expect(sql.clause).toBe(
        ' AND v.type = $1::"VideoType" AND v.category = $2 AND v."channelId" = $3',
      );
      expect(sql.params).toEqual(['SHORT', 'Worship', 'c1']);
    });

    it('renders a channel-id list as an ANY() clause', () => {
      const { service } = makeService();
      const sql = (service as any).buildBaseFilterSql({
        type: 'ALL',
        channelIds: 'c1, c2',
      });
      expect(sql.clause).toBe(' AND v."channelId" = ANY($1::text[])');
      expect(sql.params).toEqual([['c1', 'c2']]);
    });

    it('returns an empty clause for unfiltered queries', () => {
      const { service } = makeService();
      expect((service as any).buildBaseFilterSql({ type: 'ALL' })).toEqual({
        clause: '',
        params: [],
      });
    });
  });

  describe('importShortVideo', () => {
    it('upserts a SHORT and marks new embeddings as pending', async () => {
      const { service, prisma, configService } = makeService();
      prisma.channel.upsert.mockResolvedValue({});
      prisma.video.upsert.mockResolvedValue({ id: 'short1', title: 'My Short' });

      const saved = await service.importShortVideo({
        youtubeVideoId: 'short1',
        title: 'My Short',
        description: 'A short word',
        category: 'Devotion',
      });

      expect(configService.get).toHaveBeenCalled();
      expect(prisma.channel.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          create: expect.objectContaining({
            id: 'UCSaJppP4zb2vivjxYfTqOKw',
            name: 'ChristianApp',
            isActive: true,
          }),
        }),
      );
      const upsert = prisma.video.upsert.mock.calls[0][0];
      expect(upsert.update).toMatchObject({
        type: 'SHORT',
        category: 'Devotion',
      });
      expect(upsert.create).toMatchObject({ type: 'SHORT', channelId: 'UCSaJppP4zb2vivjxYfTqOKw' });
      // Pipeline status is upserted separately via the shared status table
      expect(prisma.$executeRawUnsafe).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO "VideoPipelineStatus"'),
        'short1',
      );
      expect(saved.id).toBe('short1');
    });

    it('invalidates videos and channels caches when importing a short', async () => {
      const cache = {
        getOrSet: jest.fn((_ns, _k, _ttl, fn) => fn()),
        invalidate: jest.fn().mockResolvedValue(undefined),
      };
      const { service, prisma } = makeService(null, {}, cache);
      prisma.channel.upsert.mockResolvedValue({});
      prisma.video.upsert.mockResolvedValue({ id: 'short2', title: 'Short 2' });

      await service.importShortVideo({ youtubeVideoId: 'short2', title: 'Short 2' });

      expect(cache.invalidate).toHaveBeenCalledWith('videos', 'channels', 'video-search');
    });

    it('rejects private videos without upserting caller-supplied metadata', async () => {
      const youtubeService = {
        verifyVideosVisibility: jest.fn().mockResolvedValue(
          new Map([['priv1', { videoId: 'priv1', status: 'private' }]]),
        ),
      };
      const { service, prisma } = makeService(null, {}, undefined, youtubeService);

      await expect(
        service.importShortVideo({ youtubeVideoId: 'priv1', title: 'Caller Private Title' }),
      ).rejects.toThrow('Private videos cannot be imported');

      expect(prisma.channel.upsert).not.toHaveBeenCalled();
      expect(prisma.video.upsert).not.toHaveBeenCalled();
      expect(prisma.video.deleteMany).toHaveBeenCalledWith({ where: { id: 'priv1' } });
    });

    it('fails closed when YouTube cannot verify visibility (unavailable or error)', async () => {
      const youtubeService = {
        verifyVideosVisibility: jest
          .fn()
          .mockResolvedValueOnce(
            new Map([['unavail1', { videoId: 'unavail1', status: 'unavailable' }]]),
          )
          .mockResolvedValueOnce(
            new Map([['err1', { videoId: 'err1', status: 'error', errorMessage: 'quota' }]]),
          ),
      };
      const { service, prisma } = makeService(null, {}, undefined, youtubeService);

      await expect(
        service.importShortVideo({ youtubeVideoId: 'unavail1', title: 'Caller Title' }),
      ).rejects.toThrow('Video visibility could not be verified on YouTube');
      await expect(
        service.importShortVideo({ youtubeVideoId: 'err1', title: 'Caller Title' }),
      ).rejects.toThrow('Unable to verify video visibility with YouTube');

      expect(prisma.channel.upsert).not.toHaveBeenCalled();
      expect(prisma.video.upsert).not.toHaveBeenCalled();
      expect(prisma.video.deleteMany).not.toHaveBeenCalled();
    });
  });

  describe('Upstash cache integration', () => {
    it('routes findAll and findOne through CacheService when provided', async () => {
      const cache = {
        getOrSet: jest.fn((_ns, _k, _ttl, fn) => fn()),
        invalidate: jest.fn().mockResolvedValue(undefined),
      };
      const { service, prisma } = makeService(null, {}, cache);
      prisma.video.findMany.mockResolvedValue([row('v1')]);
      prisma.video.findUnique.mockResolvedValue(row('v1'));

      await service.findAll({ category: 'Sermons', limit: 20, offset: 0 });
      await service.findOne('v1');

      expect(cache.getOrSet).toHaveBeenCalledWith(
        'videos',
        expect.stringContaining('cat=Sermons'),
        86400,
        expect.any(Function),
      );
      expect(cache.getOrSet).toHaveBeenCalledWith(
        'videos',
        'detail:v1',
        86400,
        expect.any(Function),
      );
    });
  });
});
