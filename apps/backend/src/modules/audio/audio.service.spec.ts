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
    $queryRaw: jest.fn(),
    channel: {
      findMany: jest.fn().mockResolvedValue([]),
    },
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

    it('backfills channelId from a matching Channel row by slug-of-name', async () => {
      const { service, prisma } = makeService();
      global.fetch = jest.fn()
        // manifest.json
        .mockResolvedValueOnce(jsonResponse({ revision: 'abc123' }))
        // catalog.json
        .mockResolvedValueOnce(jsonResponse([
          {
            id: 'chennai_cfc',
            title: 'CHENNAI CFC',
            speaker: 'Zac Poonen',
            category: 'YouTube',
            trackCount: 3,
          },
        ]))
        // series JSON for chennai_cfc
        .mockResolvedValueOnce(jsonResponse({
          id: 'chennai_cfc',
          tracks: [
            { id: 't1' }, { id: 't2' }, { id: 't3' },
          ],
        }));

      // The seeded Channel row whose YouTube id is the authoritative key.
      prisma.channel.findMany.mockResolvedValue([
        {
          id: 'UCjOBTIP3cKg-F2MDsG8s5Og',
          name: 'CHENNAI CFC',
          thumbnail: 'http://thumbs/chennai.jpg',
        },
      ]);
      prisma.audioSeries.findUnique.mockResolvedValue({
        id: 'chennai_cfc',
        trackCount: 3,
      });
      prisma.audioSeries.upsert.mockResolvedValue({ id: 'chennai_cfc' });
      prisma.audioTrack.createMany.mockResolvedValue({ count: 3 });
      prisma.audioSeries.update.mockResolvedValue({ id: 'chennai_cfc', trackCount: 3 });

      await service.syncCatalogFromGitHub();

      expect(prisma.channel.findMany).toHaveBeenCalled();
      expect(prisma.audioSeries.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          create: expect.objectContaining({
            channelId: 'UCjOBTIP3cKg-F2MDsG8s5Og',
          }),
        }),
      );
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

    it('stores track publishedAt and derives series latestPublishedAt', async () => {
      const { service, prisma } = makeService();
      const tracks = [
        { id: 't1', publishedAt: '2026-09-01T00:00:00Z' },
        { id: 't2', publishedAt: '2026-09-20T06:30:00Z' },
        { id: 't3', publishedAt: '2026-09-10T12:00:00Z' },
      ];
      global.fetch = jest.fn()
        .mockResolvedValueOnce(jsonResponse({ revision: 'abc123' }))
        .mockResolvedValueOnce(jsonResponse([
          { id: 's1', title: 'S1', speaker: 'ZP', category: 'X', trackCount: 3 },
        ]))
        .mockResolvedValueOnce(jsonResponse({ id: 's1', tracks }));

      prisma.audioSeries.findUnique.mockResolvedValue({
        id: 's1',
        trackCount: 1,
      });
      prisma.audioSeries.upsert.mockResolvedValue({ id: 's1' });
      prisma.audioTrack.createMany.mockResolvedValue({ count: 3 });
      prisma.audioSeries.update.mockResolvedValue({ id: 's1', trackCount: 3 });

      await service.syncCatalogFromGitHub();

      const createData = prisma.audioTrack.createMany.mock.calls[0][0].data;
      expect(createData[0].publishedAt).toEqual(new Date('2026-09-01T00:00:00Z'));
      expect(prisma.audioSeries.update).toHaveBeenCalledWith({
        where: { id: 's1' },
        data: {
          trackCount: 3,
          latestPublishedAt: new Date('2026-09-20T06:30:00Z'),
        },
      });
    });

    it('backfills latestPublishedAt for legacy series without wiping newer values', async () => {
      const { service, prisma } = makeService();
      global.fetch = jest.fn()
        .mockResolvedValueOnce(jsonResponse({ revision: 'abc123' }))
        .mockResolvedValueOnce(jsonResponse([
          { id: 's1', title: 'S1', speaker: 'ZP', category: 'X', trackCount: 7 },
        ]))
        // backfill fetch for the legacy series (no catalog recency field)
        .mockResolvedValueOnce(jsonResponse({
          id: 's1',
          tracks: [
            { id: 't1', publishedAt: '2025-01-01T00:00:00Z' },
            { id: 't2', publishedAt: '2026-03-15T09:00:00Z' },
          ],
        }));

      prisma.audioSeries.findUnique.mockResolvedValue({
        id: 's1',
        trackCount: 7,
        latestPublishedAt: null,
      });
      prisma.audioSeries.upsert.mockResolvedValue({ id: 's1' });
      // No track re-sync needed: count matches. findMany drives the backfill.
      prisma.audioSeries.findMany.mockResolvedValue([{ id: 's1' }]);

      await service.syncCatalogFromGitHub();

      expect(prisma.audioTrack.deleteMany).not.toHaveBeenCalled();
      // Only one series update: the backfill (count matched, so no track sync).
      expect(prisma.audioSeries.update).toHaveBeenCalledTimes(1);
      expect(prisma.audioSeries.update).toHaveBeenCalledWith({
        where: { id: 's1' },
        data: { latestPublishedAt: new Date('2026-03-15T09:00:00Z') },
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
          channelId: null,
          channel: null,
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
          channelId: 'UCjOBTIP3cKg-F2MDsG8s5Og',
          channel: {
            name: 'CHENNAI CFC',
            thumbnail: 'http://thumbs/chennai.jpg',
          },
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
      expect(catalog[0].channelId).toBeNull();
      expect(catalog[1].channelId).toBe('UCjOBTIP3cKg-F2MDsG8s5Og');
      expect(catalog[1].channelName).toBe('CHENNAI CFC');
      expect(catalog[1].channelThumbnail).toBe('http://thumbs/chennai.jpg');
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
        channelId: 'UCjOBTIP3cKg-F2MDsG8s5Og',
        channel: {
          name: 'CHENNAI CFC',
          thumbnail: 'http://thumbs/chennai.jpg',
        },
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
        include: { tracks: true, channel: true },
      });
      expect(series).not.toBeNull();
      expect(series!.id).toBe('s1');
      expect(series!.tracks).toHaveLength(1);
      expect(series!.tracks[0].seriesTitle).toBe('Sermon One');
      expect(series!.tracks[0].coverUrl).toBe('http://covers/t1.jpg');
      expect(series!.channelId).toBe('UCjOBTIP3cKg-F2MDsG8s5Og');
      expect(series!.channelName).toBe('CHENNAI CFC');
    });

    it('returns null for a missing series', async () => {
      const { service, prisma } = makeService();
      prisma.audioSeries.findUnique.mockResolvedValue(null);

      const series = await service.getSeries('does_not_exist');
      expect(series).toBeNull();
    });
  });

  describe('searchCatalog (fuzzy)', () => {
    const seriesRow = {
      id: 's1',
      title: 'Ministry of a Deliverer',
      description: 'Series about deliverance',
      speaker: 'Zac Poonen',
      coverUrl: 'http://covers/s1.jpg',
      trackCount: 4,
      category: 'General',
      language: 'English',
      score: 2.51,
    };

    const trackRow = {
      seriesId: 's1',
      title: 'Ministry of a Deliverer',
      description: 'Series about deliverance',
      speaker: 'Zac Poonen',
      coverUrl: 'http://covers/s1.jpg',
      trackCount: 4,
      category: 'General',
      language: 'English',
      trackId: 't1',
      trackTitle: 'The Deliverer Speaks',
      trackSpeaker: 'Zac Poonen',
      trackDurationSeconds: 100,
      trackAudioUrl: 'https://audio.com/12345',
      trackStreamUrl: null,
      trackFallbackUrl: null,
      trackCoverUrl: 'http://covers/t1.jpg',
      trackThumbnailUrl: null,
      trackYoutubeVideoId: 'abc',
      trackScriptureBook: 'GEN',
      trackScriptureChapter: 1,
      trackScriptureVerse: 1,
    };

    it('groups fuzzy series and track matches with inline derived tracks', async () => {
      const { service, prisma } = makeService();
      prisma.$queryRaw
        .mockResolvedValueOnce([seriesRow])
        .mockResolvedValueOnce([trackRow]);

      const out = await service.searchCatalog('delvirer');

      expect(prisma.$queryRaw).toHaveBeenCalledTimes(2);
      expect(out).toHaveLength(1);
      expect(out[0].id).toBe('s1');
      expect(out[0].title).toBe('Ministry of a Deliverer');
      // Track match carried its series inline with the matched track only.
      expect(out[0].tracks).toHaveLength(1);
      expect(out[0].tracks[0].id).toBe('t1');
      expect(out[0].tracks[0].seriesTitle).toBe('Ministry of a Deliverer');
      expect(out[0].tracks[0].coverUrl).toBe('http://covers/t1.jpg');
      expect(out[0].tracks[0].speaker).toBe('Zac Poonen');
    });

    it('returns an empty array for a blank query without hitting the database', async () => {
      const { service, prisma } = makeService();
      const out = await service.searchCatalog('   ');
      expect(out).toEqual([]);
      expect(prisma.$queryRaw).not.toHaveBeenCalled();
      expect(prisma.audioSeries.findMany).not.toHaveBeenCalled();
    });

    it('uses substring search (not trigram) for terms shorter than 3 chars', async () => {
      const { service, prisma } = makeService();
      prisma.audioSeries.findMany.mockResolvedValue([]);
      prisma.audioTrack.findMany.mockResolvedValue([]);

      const out = await service.searchCatalog('zz');

      expect(prisma.$queryRaw).not.toHaveBeenCalled();
      expect(prisma.audioSeries.findMany).toHaveBeenCalled();
      expect(out).toEqual([]);
    });

    it('falls back to substring search when the trigram query fails', async () => {
      const { service, prisma } = makeService();
      prisma.$queryRaw.mockRejectedValue(
        new Error('function word_similarity(text, text) does not exist'),
      );
      prisma.audioSeries.findMany.mockResolvedValue([
        {
          id: 's1',
          title: 'Ministry of a Deliverer',
          description: 'desc',
          speaker: 'Zac Poonen',
          coverUrl: null,
          trackCount: 4,
          category: 'General',
          language: 'English',
        },
      ]);
      prisma.audioTrack.findMany.mockResolvedValue([]);

      const out = await service.searchCatalog('deliverance');

      expect(prisma.audioSeries.findMany).toHaveBeenCalled();
      expect(out).toHaveLength(1);
      expect(out[0].id).toBe('s1');
      expect(out[0].tracks).toEqual([]);
    });

    it('substring fallback merges track matches into the matching series', async () => {
      const { service, prisma } = makeService();
      prisma.audioSeries.findMany.mockResolvedValue([]);
      prisma.audioTrack.findMany.mockResolvedValue([
        {
          id: 't1',
          seriesId: 's1',
          title: 'The Deliverer Speaks',
          speaker: 'Zac Poonen',
          series: {
            id: 's1',
            title: 'Ministry of a Deliverer',
            description: 'desc',
            speaker: 'Zac Poonen',
            coverUrl: null,
            trackCount: 4,
            category: 'General',
            language: 'English',
          },
        },
      ]);

      const out = await service.searchCatalog('the robber', 5);

      expect(out).toHaveLength(1);
      expect(out[0].id).toBe('s1');
      expect(out[0].tracks).toHaveLength(1);
      expect(out[0].tracks[0].id).toBe('t1');
    });
  });
});