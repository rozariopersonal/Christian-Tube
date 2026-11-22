import { SyncService } from './sync.service';

function makeSyncService(config: Record<string, any> = {}) {
  const configService = {
    get: jest.fn((key: string) => config[key]),
  };
  const prisma = {
    channel: {
      findUnique: jest.fn(),
      update: jest.fn().mockResolvedValue({}),
      upsert: jest.fn().mockResolvedValue({}),
      findMany: jest.fn().mockResolvedValue([]),
    },
    video: {
      findUnique: jest.fn(),
      findMany: jest.fn().mockResolvedValue([]),
      upsert: jest.fn().mockResolvedValue({ id: 'v1' }),
      update: jest.fn().mockResolvedValue({ id: 'v1' }),
      deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
    },
    shortCreation: {
      upsert: jest.fn().mockResolvedValue({}),
      deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
    },
  };
  const youtubeService = {
    hasApiKey: jest.fn().mockReturnValue(true),
    fetchChannelMetadata: jest.fn().mockResolvedValue(null),
    fetchPlaylistItems: jest.fn(),
    verifyVideosVisibility: jest.fn(),
    parseIsoDuration: jest.fn().mockReturnValue('1:00'),
    parseIsoDurationSeconds: jest.fn().mockReturnValue(60),
    scrapeRssFeed: jest.fn().mockResolvedValue([]),
    scrapeChannelVideosTab: jest.fn().mockResolvedValue({ videos: [] }),
    scrapeChannelStreamsTab: jest.fn().mockResolvedValue({ videos: [] }),
    scrapeChannelShortsTab: jest.fn().mockResolvedValue({ videos: [] }),
  };
  const cache = {
    invalidate: jest.fn().mockResolvedValue(undefined),
  };

  const service = new SyncService(
    configService as any,
    prisma as any,
    youtubeService as any,
    cache as any,
  );
  return { service, prisma, youtubeService, cache, configService };
}

describe('SyncService private video safeguards', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('syncChannel / syncViaPlaylistApi', () => {
    it('upserts eligible (public/unlisted) videos, skips unavailable/error, and deletes confirmed private', async () => {
      const { service, prisma, youtubeService } = makeSyncService();
      prisma.channel.findUnique.mockResolvedValue({
        id: 'UC123',
        name: 'Test Channel',
        category: 'Sermons',
        syncStatus: 'COMPLETED',
        syncCursor: null,
      });
      youtubeService.fetchPlaylistItems.mockResolvedValue({
        items: [
          {
            contentDetails: { videoId: 'v_pub' },
            snippet: { title: 'Public', channelTitle: 'Test Channel' },
          },
          {
            contentDetails: { videoId: 'v_unl' },
            snippet: { title: 'Unlisted', channelTitle: 'Test Channel' },
          },
          {
            contentDetails: { videoId: 'v_unavail' },
            snippet: { title: 'Private video', channelTitle: 'Test Channel' },
          },
          {
            contentDetails: { videoId: 'v_err' },
            snippet: { title: 'Cached Title', channelTitle: 'Test Channel' },
          },
          {
            contentDetails: { videoId: 'v_priv' },
            snippet: { title: 'Secret Title', channelTitle: 'Test Channel' },
          },
        ],
        nextPageToken: undefined,
      });

      youtubeService.verifyVideosVisibility.mockResolvedValue(
        new Map([
          [
            'v_pub',
            {
              videoId: 'v_pub',
              status: 'eligible',
              item: {
                id: 'v_pub',
                snippet: { title: 'Public', description: '', channelTitle: 'Test Channel' },
                contentDetails: { duration: 'PT5M' },
                statistics: { viewCount: '10' },
              },
            },
          ],
          [
            'v_unl',
            {
              videoId: 'v_unl',
              status: 'eligible',
              item: {
                id: 'v_unl',
                snippet: { title: 'Unlisted', description: '', channelTitle: 'Test Channel' },
                contentDetails: { duration: 'PT5M' },
                statistics: { viewCount: '5' },
              },
            },
          ],
          ['v_unavail', { videoId: 'v_unavail', status: 'unavailable' }],
          ['v_err', { videoId: 'v_err', status: 'error', errorMessage: 'quotaExceeded' }],
          ['v_priv', { videoId: 'v_priv', status: 'private' }],
        ]),
      );
      prisma.video.deleteMany.mockResolvedValue({ count: 1 });

      await service.syncChannel('UC123', 'Sermons');

      // Only v_pub and v_unl are upserted; v_unavail and v_err do NOT fall back to playlist snippet
      expect(prisma.video.upsert).toHaveBeenCalledTimes(2);
      const upsertedIds = prisma.video.upsert.mock.calls.map((c) => c[0].where.id);
      expect(upsertedIds).toEqual(['v_pub', 'v_unl']);

      // Only confirmed private (v_priv) triggers deleteMany; v_unavail and v_err are NOT deleted
      expect(prisma.video.deleteMany).toHaveBeenCalledTimes(1);
      expect(prisma.video.deleteMany).toHaveBeenCalledWith({ where: { id: 'v_priv' } });
    });
  });

  describe('handleWebSubPushNotification', () => {
    const sampleXml = `
      <feed>
        <entry>
          <yt:videoId>vid_ws_1</yt:videoId>
          <yt:channelId>UC123</yt:channelId>
          <title>Confidential Private Sermon</title>
          <published>2026-11-22T10:00:00Z</published>
        </entry>
      </feed>
    `;

    it('fails closed without XML fallback when video is unavailable or API errors', async () => {
      const { service, prisma, youtubeService } = makeSyncService();
      prisma.channel.findUnique.mockResolvedValue({ id: 'UC123', name: 'Test', category: 'Sermons' });
      youtubeService.verifyVideosVisibility.mockResolvedValue(
        new Map([['vid_ws_1', { videoId: 'vid_ws_1', status: 'unavailable' }]]),
      );

      await service.handleWebSubPushNotification(sampleXml);

      expect(prisma.video.upsert).not.toHaveBeenCalled();
      expect(prisma.video.deleteMany).not.toHaveBeenCalled();
    });

    it('removes existing record when WebSub video is confirmed private and does not log private title', async () => {
      const { service, prisma, youtubeService } = makeSyncService();
      const logSpy = jest.spyOn((service as any).logger, 'log');
      const warnSpy = jest.spyOn((service as any).logger, 'warn');
      prisma.channel.findUnique.mockResolvedValue({ id: 'UC123', name: 'Test', category: 'Sermons' });
      prisma.video.deleteMany.mockResolvedValue({ count: 1 });
      youtubeService.verifyVideosVisibility.mockResolvedValue(
        new Map([['vid_ws_1', { videoId: 'vid_ws_1', status: 'private' }]]),
      );

      await service.handleWebSubPushNotification(sampleXml);

      expect(prisma.video.upsert).not.toHaveBeenCalled();
      expect(prisma.video.deleteMany).toHaveBeenCalledWith({ where: { id: 'vid_ws_1' } });
      const allLogs = [...logSpy.mock.calls, ...warnSpy.mock.calls].flat().join(' ');
      expect(allLogs).not.toContain('Confidential Private Sermon');
    });
  });

  describe('syncSingleVideo', () => {
    it('does not invoke scraper fallback and fails closed for unavailable or error statuses', async () => {
      const { service, prisma, youtubeService } = makeSyncService();
      prisma.video.findUnique.mockResolvedValue(null);
      youtubeService.verifyVideosVisibility.mockResolvedValue(
        new Map([['arbitrary_id', { videoId: 'arbitrary_id', status: 'unavailable' }]]),
      );

      const res = await service.syncSingleVideo('arbitrary_id');

      expect(res).toBeNull();
      expect(prisma.video.upsert).not.toHaveBeenCalled();
      expect(prisma.shortCreation.upsert).not.toHaveBeenCalled();
      expect(youtubeService.scrapeRssFeed).not.toHaveBeenCalled();
      expect(youtubeService.scrapeChannelVideosTab).not.toHaveBeenCalled();
    });

    it('deletes existing records when confirmed private', async () => {
      const { service, prisma, youtubeService } = makeSyncService();
      prisma.video.findUnique.mockResolvedValue({ channelId: 'UC_CUSTOM' });
      prisma.video.deleteMany.mockResolvedValue({ count: 1 });
      youtubeService.verifyVideosVisibility.mockResolvedValue(
        new Map([['priv_short', { videoId: 'priv_short', status: 'private' }]]),
      );

      const res = await service.syncSingleVideo('priv_short');

      expect(res).toBeNull();
      expect(prisma.video.upsert).not.toHaveBeenCalled();
      expect(prisma.video.deleteMany).toHaveBeenCalledWith({ where: { id: 'priv_short' } });
      expect(prisma.shortCreation.deleteMany).toHaveBeenCalledWith({
        where: { youtubeVideoId: 'priv_short' },
      });
    });
  });
});
