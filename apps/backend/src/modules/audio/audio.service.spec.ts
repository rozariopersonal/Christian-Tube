import { AudioService } from './audio.service';

function makeService() {
  const prisma = {
    audioSeries: {
      findUnique: jest.fn(),
      upsert: jest.fn(),
      update: jest.fn(),
      findMany: jest.fn(),
    },
    audioTrack: {
      deleteMany: jest.fn(),
      createMany: jest.fn(),
      findMany: jest.fn(),
    },
    $transaction: jest.fn((ops: any[]) => Promise.all(ops)),
  };
  const service = new AudioService(prisma as any);
  return { service, prisma };
}

afterEach(() => {
  // Restore the real global fetch (Node >= 18) so other suites aren't leaked.
  const realFetch = (global as any).__originalFetch;
  if (realFetch) {
    (global as any).fetch = realFetch;
  }
  jest.restoreAllMocks();
});

function jsonResponse(body: unknown, ok = true, statusText = 'OK') {
  return {
    ok,
    statusText,
    json: jest.fn().mockResolvedValue(body),
  } as any;
}

describe('AudioService', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('syncCatalogFromGitHub', () => {
    it('re-syncs a series when the published trackCount DECREASED (removed tracks)', async () => {
      const { service, prisma } = makeService();
      global.fetch = jest.fn()
        // manifest.json
        .mockResolvedValueOnce(jsonResponse({ revision: 'abc123' }))
        // catalog.json
        .mockResolvedValueOnce(jsonResponse([
          { id: 's1', title: 'S1', speaker: 'ZP', category: 'X', trackCount: 3 },
        ]))
        // series JSON for s1 (fewer tracks than DB currently has)
        .mockResolvedValueOnce(jsonResponse({
          id: 's1',
          tracks: [
            { id: 't1' }, { id: 't2' }, { id: 't3' },
          ],
        }));

      prisma.audioSeries.findUnique.mockResolvedValue({
        id: 's1',
        trackCount: 10,
      });
      prisma.audioSeries.upsert.mockResolvedValue({ id: 's1' });
      prisma.audioTrack.createMany.mockResolvedValue({ count: 3 });
      prisma.audioSeries.update.mockResolvedValue({ id: 's1', trackCount: 3 });

      await service.syncCatalogFromGitHub();

      // The old code skipped when count decreased; now it must sync.
      expect(prisma.audioTrack.deleteMany).toHaveBeenCalledWith({
        where: { seriesId: 's1' },
      });
      expect(prisma.audioTrack.createMany).toHaveBeenCalled();
      expect(prisma.audioSeries.update).toHaveBeenCalledWith({
        where: { id: 's1' },
        data: { trackCount: 3 },
      });
    });

    it('re-syncs a series when the published trackCount INCREASED', async () => {
      const { service, prisma } = makeService();
      global.fetch = jest.fn()
        .mockResolvedValueOnce(jsonResponse({ revision: 'abc123' }))
        .mockResolvedValueOnce(jsonResponse([
          { id: 's1', title: 'S1', speaker: 'ZP', category: 'X', trackCount: 12 },
        ]))
        .mockResolvedValueOnce(jsonResponse({
          id: 's1',
          tracks: Array.from({ length: 12 }, (_, i) => ({ id: `t${i + 1}` })),
        }));

      prisma.audioSeries.findUnique.mockResolvedValue({
        id: 's1',
        trackCount: 5,
      });
      prisma.audioSeries.upsert.mockResolvedValue({ id: 's1' });
      prisma.audioTrack.createMany.mockResolvedValue({ count: 12 });
      prisma.audioSeries.update.mockResolvedValue({ id: 's1', trackCount: 12 });

      await service.syncCatalogFromGitHub();

      expect(prisma.audioTrack.deleteMany).toHaveBeenCalledWith({
        where: { seriesId: 's1' },
      });
      expect(prisma.audioSeries.update).toHaveBeenCalledWith({
        where: { id: 's1' },
        data: { trackCount: 12 },
      });
    });

    it('SKIPS re-syncing when the stored count matches the published count', async () => {
      const { service, prisma } = makeService();
      global.fetch = jest.fn()
        .mockResolvedValueOnce(jsonResponse({ revision: 'abc123' }))
        .mockResolvedValueOnce(jsonResponse([
          { id: 's1', title: 'S1', speaker: 'ZP', category: 'X', trackCount: 7 },
        ]));

      prisma.audioSeries.findUnique.mockResolvedValue({
        id: 's1',
        trackCount: 7,
      });
      prisma.audioSeries.upsert.mockResolvedValue({ id: 's1' });

      await service.syncCatalogFromGitHub();

      expect(prisma.audioTrack.deleteMany).not.toHaveBeenCalled();
      expect(prisma.audioTrack.createMany).not.toHaveBeenCalled();
      expect(prisma.audioSeries.update).not.toHaveBeenCalled();
    });

    it('prunes all existing tracks when a series shrinks to zero tracks', async () => {
      const { service, prisma } = makeService();
      global.fetch = jest.fn()
        .mockResolvedValueOnce(jsonResponse({ revision: 'abc123' }))
        .mockResolvedValueOnce(jsonResponse([
          { id: 's1', title: 'S1', speaker: 'ZP', category: 'X', trackCount: 0 },
        ]))
        .mockResolvedValueOnce(jsonResponse({ id: 's1', tracks: [] }));

      prisma.audioSeries.findUnique.mockResolvedValue({
        id: 's1',
        trackCount: 9,
      });
      prisma.audioSeries.upsert.mockResolvedValue({ id: 's1' });
      prisma.audioSeries.update.mockResolvedValue({ id: 's1', trackCount: 0 });

      await service.syncCatalogFromGitHub();

      // deleteMany must run even when there are zero upstream tracks.
      expect(prisma.audioTrack.deleteMany).toHaveBeenCalledWith({
        where: { seriesId: 's1' },
      });
      expect(prisma.audioTrack.createMany).not.toHaveBeenCalled();
      expect(prisma.audioSeries.update).toHaveBeenCalledWith({
        where: { id: 's1' },
        data: { trackCount: 0 },
      });
    });
  });

  describe('getSyncData', () => {
    it('includes series changed by metadata/count even without new track rows', async () => {
      const { service, prisma } = makeService();
      const since = new Date('2026-01-01T00:00:00Z').getTime();

      prisma.audioSeries.findMany.mockResolvedValue([
        {
          id: 's1',
          title: 'S1',
          trackCount: 8,
          updatedAt: new Date('2026-02-01T00:00:00Z'),
        },
      ]);
      prisma.audioTrack.findMany.mockResolvedValue([]);

      const out = await service.getSyncData(since);

      expect(prisma.audioSeries.findMany).toHaveBeenCalled();
      expect(out).toHaveLength(1);
      expect(out[0].id).toBe('s1');
      expect(out[0].trackCount).toBe(8);
      expect(out[0].tracks).toEqual([]);
    });
  });

  describe('getCatalog (DB-first read)', () => {
    it('returns series projections ordered by title ascending without tracks', async () => {
      const { service, prisma } = makeService();
      prisma.audioSeries.findMany.mockResolvedValue([
        {
          id: 's2',
          title: 'Sermon B',
          description: 'B',
          speaker: 'ZP',
          coverUrl: 'http://covers/b.jpg',
          trackCount: 3,
          category: 'General',
          language: 'English',
        },
        {
          id: 's1',
          title: 'Sermon A',
          description: 'A',
          speaker: 'ZP',
          coverUrl: 'http://covers/a.jpg',
          trackCount: 5,
          category: 'General',
          language: 'English',
        },
      ]);

      const catalog = await service.getCatalog();

      expect(prisma.audioSeries.findMany).toHaveBeenCalledWith({
        orderBy: { title: 'asc' },
        select: expect.objectContaining({ id: true, trackCount: true }),
      });
      expect(catalog).toHaveLength(2);
      expect(catalog[0].id).toBe('s2');
      expect(catalog[0]).not.toHaveProperty('tracks');
    });
  });

  describe('getSeries (DB-first read)', () => {
    it('maps a series row with inline tracks incl derived seriesTitle and coverUrl', async () => {
      const { service, prisma } = makeService();
      prisma.audioSeries.findUnique.mockResolvedValue({
        id: 's1',
        title: 'Sermon One',
        description: 'desc',
        speaker: 'ZP',
        coverUrl: 'http://covers/s1.jpg',
        trackCount: 1,
        category: 'General',
        language: 'English',
        tracks: [
          {
            id: 't1',
            seriesId: 's1',
            title: 'Track 1',
            speaker: 'ZP',
            durationSeconds: 100,
            audioUrl: 'https://audio.com/12345',
            streamUrl: null,
            fallbackUrl: null,
            coverUrl: null,
            ifCoverUrl: 'http://covers/t1.jpg',
            thumbnailUrl: null,
            youtubeVideoId: 'abc',
            scriptureBook: 'GEN',
            scriptureChapter: 1,
            scriptureVerse: 1,
          },
        ],
      });

      const series = await service.getSeries('s1');

      expect(prisma.audioSeries.findUnique).toHaveBeenCalledWith({
        where: { id: 's1' },
        include: { tracks: true },
      });
      expect(series).not.toBeNull();
      expect(series!.id).toBe('s1');
      expect(series!.tracks).toHaveLength(1);
      expect(series!.tracks[0].seriesTitle).toBe('Sermon One');
      expect(series!.tracks[0].coverUrl).toBe('http://covers/t1.jpg');
    });

    it('returns null for a missing series', async () => {
      const { service, prisma } = makeService();
      prisma.audioSeries.findUnique.mockResolvedValue(null);

      const series = await service.getSeries('does_not_exist');
      expect(series).toBeNull();
    });
  });
});