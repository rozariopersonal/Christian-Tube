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
});