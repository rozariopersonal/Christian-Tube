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

function makeService(embedQuery: number[] | null = null) {
  const prisma = {
    video: { findMany: jest.fn(), findUnique: jest.fn(), upsert: jest.fn() },
    channel: { upsert: jest.fn() },
    $queryRawUnsafe: jest.fn(),
  };
  const configService = { get: jest.fn(() => undefined) };
  const embeddingService = {
    modelName: 'intfloat/multilingual-e5-small',
    modelVersion: 1,
    embedQuery: jest.fn().mockResolvedValue(embedQuery),
  };
  const service = new VideosService(prisma as any, configService as any, embeddingService as any);
  return { service, prisma, configService, embeddingService };
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

    it('falls back to ILIKE keyword terms when the embedding service is unavailable', async () => {
      const { service, prisma, embeddingService } = makeService(null);
      prisma.video.findMany.mockResolvedValue([row('v1')]);

      const out = await service.findAll({ search: 'love  God' });

      expect(embeddingService.embedQuery).toHaveBeenCalledWith('love  God');
      expect(prisma.$queryRawUnsafe).not.toHaveBeenCalled();
      expect(prisma.video.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            OR: [
              { title: { contains: 'love  God', mode: 'insensitive' } },
              { description: { contains: 'love  God', mode: 'insensitive' } },
              { channelName: { contains: 'love  God', mode: 'insensitive' } },
            ],
          }),
        }),
      );
      expect(out).toHaveLength(1);
    });

    it('runs the hybrid vector + keyword query when an embedding is produced', async () => {
      const { service, prisma, embeddingService } = makeService(
        new Array(DIM).fill(0.1),
      );
      prisma.$queryRawUnsafe.mockResolvedValue([{ id: 'v2' }, { id: 'v1' }]);
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

      // Default type filter is $1, then model/version/query vector follow
      expect(prisma.$queryRawUnsafe).toHaveBeenCalledTimes(1);
      const [sql, type, model, version, vec] = prisma.$queryRawUnsafe.mock.calls[0];
      expect(sql).toContain(' AND v.type = $1');
      expect(sql).toContain('ve."model" = $2');
      expect(sql).toContain('ve."version" = $3');
      expect(sql).toContain('ve.embedding <=> $4::vector');
      expect(type).toBe('VIDEO');
      expect(model).toBe('intfloat/multilingual-e5-small');
      expect(version).toBe(1);
      expect(vec).toEqual(new Array(DIM).fill(0.1));
      // RRF: v1 ranks above both v2 and v3
      expect(out.map((v: any) => v.id)).toEqual(['v1', 'v2', 'v3']);
    });

    it('pages through the fused result list with offset and limit', async () => {
      const { service, prisma } = makeService(new Array(DIM).fill(0.1));
      prisma.$queryRawUnsafe.mockResolvedValue([{ id: 'v2' }, { id: 'v1' }]);
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
          where: expect.objectContaining({ id: { in: ['v2'] } }),
        }),
      );
      expect(out.map((v: any) => v.id)).toEqual(['v2']);
    });

    it('degrades to keyword results when the vector query fails at the database', async () => {
      const { service, prisma } = makeService(new Array(DIM).fill(0.1));
      prisma.$queryRawUnsafe.mockRejectedValue(new Error('vector db down'));
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
        ' AND v.type = $1 AND v.category = $2 AND v."channelId" = $3',
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
            name: 'Christian-Tube',
            isActive: true,
          }),
        }),
      );
      const upsert = prisma.video.upsert.mock.calls[0][0];
      expect(upsert.update).toMatchObject({
        type: 'SHORT',
        embeddingStatus: 'pending',
        embeddingHash: null,
        category: 'Devotion',
      });
      expect(upsert.create).toMatchObject({ type: 'SHORT', channelId: 'UCSaJppP4zb2vivjxYfTqOKw' });
      expect(saved.id).toBe('short1');
    });
  });
});