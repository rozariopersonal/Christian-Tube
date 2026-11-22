import { UsersService } from './users.service';

describe('UsersService', () => {
  let service: UsersService;
  let prisma: any;
  let configService: any;

  beforeEach(() => {
    prisma = {
      user: {
        upsert: jest.fn(),
        findUnique: jest.fn(),
        findMany: jest.fn(),
        update: jest.fn(),
      },
      userPreference: {
        findUnique: jest.fn(),
        create: jest.fn(),
        upsert: jest.fn(),
      },
      channelSubscription: {
        findMany: jest.fn(),
        upsert: jest.fn(),
        deleteMany: jest.fn(),
      },
      userWatchItem: {
        findMany: jest.fn(),
        findFirst: jest.fn(),
        createMany: jest.fn(),
        updateMany: jest.fn(),
      },
      video: {
        findMany: jest.fn(),
      },
      userPlayback: {
        findFirst: jest.fn(),
        update: jest.fn(),
        upsert: jest.fn(),
      },
    };
    configService = {
      get: jest.fn().mockReturnValue(['admin@example.com']),
    };
    service = new UsersService(prisma, configService);
  });

  describe('syncUser', () => {
    it('upserts user and returns preference inclusion', async () => {
      const mockUser = {
        id: 'u1',
        email: 'user@example.com',
        displayName: 'Test User',
        role: 'USER',
        preference: {
          languages: ['en', 'ta'],
          hasCompletedOnboarding: true,
        },
      };
      prisma.user.upsert.mockResolvedValue(mockUser);

      const res = await service.syncUser({
        id: 'u1',
        email: 'user@example.com',
        displayName: 'Test User',
      });

      expect(prisma.user.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 'u1' },
          include: { preference: true },
        }),
      );
      expect(res).toEqual(mockUser);
    });
  });

  describe('getPreferences', () => {
    it('returns existing preferences if found', async () => {
      const mockPref = {
        userId: 'u1',
        languages: ['en', 'ta'],
        hasCompletedOnboarding: true,
      };
      prisma.userPreference.findUnique.mockResolvedValue(mockPref);

      const res = await service.getPreferences('u1');
      expect(res).toEqual(mockPref);
      expect(prisma.userPreference.create).not.toHaveBeenCalled();
    });

    it('creates default preferences if none found', async () => {
      prisma.userPreference.findUnique.mockResolvedValue(null);
      const defaultPref = {
        userId: 'u1',
        languages: ['en'],
        hasCompletedOnboarding: false,
      };
      prisma.userPreference.create.mockResolvedValue(defaultPref);

      const res = await service.getPreferences('u1');
      expect(prisma.userPreference.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            userId: 'u1',
            hasCompletedOnboarding: false,
          }),
        }),
      );
      expect(res).toEqual(defaultPref);
    });
  });

  describe('savePreferences', () => {
    it('upserts preferences without clobbering channel subscriptions', async () => {
      const savedPref = {
        userId: 'u1',
        languages: ['en', 'ta'],
        videoChannelIds: ['c1', 'c2'],
        shortsChannelIds: ['c2', 'c3'],
        primaryBibleVersionId: 'TAOBVSI',
        lockScreenWordFeedEnabled: true,
        lockScreenRefreshIntervalMinutes: 30,
        hasCompletedOnboarding: true,
      };
      prisma.userPreference.upsert.mockResolvedValue(savedPref);
      prisma.channelSubscription.upsert.mockResolvedValue({ id: 'sub1' });

      const res = await service.savePreferences('u1', {
        languages: ['en', 'ta'],
        videoChannelIds: ['c1', 'c2'],
        shortsChannelIds: ['c2', 'c3'],
        primaryBibleVersionId: 'TAOBVSI',
        lockScreenWordFeedEnabled: true,
        lockScreenRefreshIntervalMinutes: 30,
        hasCompletedOnboarding: true,
      });

      expect(prisma.userPreference.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { userId: 'u1' },
          update: expect.objectContaining({
            lockScreenWordFeedEnabled: true,
            lockScreenRefreshIntervalMinutes: 30,
          }),
        }),
      );
      expect(prisma.channelSubscription.upsert).not.toHaveBeenCalled();
      expect(prisma.channelSubscription.deleteMany).not.toHaveBeenCalled();
      expect(res).toEqual(savedPref);
    });
  });

  describe('savePlayback & getPlayback', () => {
    it('retrieves playback by userId or userEmail even when userId differs from email', async () => {
      prisma.userPlayback.findFirst.mockResolvedValue(null);
      prisma.userPlayback.upsert.mockResolvedValue({ id: 'pb1' });

      await service.savePlayback({
        userId: 'google-sub-123',
        userEmail: 'User@Example.com',
        mediaType: 'audio',
        trackId: 'track-1',
        positionSeconds: 42,
        durationSeconds: 300,
      });

      expect(prisma.userPlayback.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            userEmail_mediaType: {
              userEmail: 'user@example.com',
              mediaType: 'audio',
            },
          },
        }),
      );

      prisma.userPlayback.findFirst.mockResolvedValue({
        id: 'pb1',
        userId: 'google-sub-123',
        userEmail: 'user@example.com',
        mediaType: 'audio',
        trackId: 'track-1',
        positionSeconds: 42,
      });

      const found = await service.getPlayback({
        userId: 'google-sub-123',
        userEmail: 'user@example.com',
        mediaType: 'audio',
      });

      expect(prisma.userPlayback.findFirst).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            mediaType: 'audio',
            OR: [
              { userId: 'google-sub-123' },
              { userEmail: 'google-sub-123' },
              { userEmail: 'user@example.com' },
            ],
          },
        }),
      );
      expect(found?.trackId).toBe('track-1');
    });
  });

  describe('Direct DB preference reads & per-field LWW', () => {
    it('reads preferences directly from Postgres without stale 24h cache', async () => {
      const cache = {
        getOrSet: jest.fn(),
        invalidate: jest.fn().mockResolvedValue(undefined),
      };
      const cachedService = new UsersService(prisma, configService, cache as any);
      prisma.userPreference.findUnique.mockResolvedValue({ userId: 'u1', themeMode: 'dark' });

      const got = await cachedService.getPreferences('u1');
      expect(got).toEqual({ userId: 'u1', themeMode: 'dark' });
      expect(cache.getOrSet).not.toHaveBeenCalled();
    });

    it('rejects stale field updates using fieldTimestamps while accepting newer fields', async () => {
      prisma.userPreference.findUnique.mockResolvedValue({
        userId: 'u1',
        themeMode: 'dark',
        languages: ['ta'],
        fieldTimestamps: { themeMode: 2000, languages: 1000 },
      });
      prisma.userPreference.upsert.mockResolvedValue({ userId: 'u1' });

      await service.savePreferences('u1', {
        themeMode: 'light', // stale (1500 < 2000)
        languages: ['en'],  // newer (2500 > 1000)
        fieldTimestamps: { themeMode: 1500, languages: 2500 },
      });

      expect(prisma.userPreference.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          update: expect.objectContaining({
            languages: ['en'],
            fieldTimestamps: { themeMode: 2000, languages: 2500 },
          }),
        }),
      );
      const updateArg = prisma.userPreference.upsert.mock.calls[0][0].update;
      expect(updateArg.themeMode).toBeUndefined();
    });

    it('persists defaultPage preference via LWW', async () => {
      prisma.userPreference.findUnique.mockResolvedValue({
        userId: 'u1',
        defaultPage: 'feed',
        fieldTimestamps: { defaultPage: 1000 },
      });
      prisma.userPreference.upsert.mockResolvedValue({
        userId: 'u1',
        defaultPage: 'bible',
      });

      await service.savePreferences('u1', {
        defaultPage: 'bible',
        fieldTimestamps: { defaultPage: 2000 },
      });

      expect(prisma.userPreference.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          update: expect.objectContaining({
            defaultPage: 'bible',
            fieldTimestamps: { defaultPage: 2000 },
          }),
          create: expect.objectContaining({
            defaultPage: 'bible',
          }),
        }),
      );
    });
  });

  describe('upsertWatchItemsBatch & getSyncState', () => {
    it('returns per-op ok/rejected statuses and uses clientUpdatedAt LWW guard', async () => {
      const res = await service.upsertWatchItemsBatch('u1', 'u1@example.com', [
        { opId: 'op1', itemType: 'video_playhead', itemId: 'vid-1', positionSeconds: 55, clientUpdatedAt: 5000 },
        { opId: 'op2', itemType: 'invalid_type' as any, itemId: 'vid-2' },
      ]);

      expect(res.results).toEqual([
        { opId: 'op1', status: 'ok' },
        { opId: 'op2', status: 'rejected' },
      ]);
      expect(prisma.userWatchItem.createMany).toHaveBeenCalledTimes(1);
      expect(prisma.userWatchItem.updateMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            userId: 'u1',
            itemType: 'video_playhead',
            itemId: 'vid-1',
            clientUpdatedAt: { lte: new Date(5000) },
          }),
        }),
      );
    });

    it('returns bounded hydrated state from getSyncState', async () => {
      prisma.userPreference.findUnique.mockResolvedValue({ userId: 'u1', languages: ['en'] });
      prisma.channelSubscription.findMany.mockResolvedValue([
        { channelId: 'ch-1', isActive: true, clientUpdatedAt: new Date(1000) },
        { channelId: 'ch-2', isActive: false, clientUpdatedAt: new Date(2000) },
      ]);
      prisma.userWatchItem.findMany
        .mockResolvedValueOnce([{ itemId: 'v-wl', isDeleted: false, clientUpdatedAt: new Date(3000) }]) // watch_later
        .mockResolvedValueOnce([]) // video_history
        .mockResolvedValueOnce([{ itemId: 'v-wl', positionSeconds: 12, isDeleted: false, clientUpdatedAt: new Date(4000) }]); // video_playhead
      prisma.userWatchItem.findFirst.mockResolvedValue(null);
      prisma.video.findMany.mockResolvedValue([{ id: 'v-wl', title: 'Test Video' }]);

      const state = await service.getSyncState('u1', 'u1@example.com');
      expect(state.subscriptions).toEqual(['ch-1']);
      expect(state.subscriptionTombstones).toEqual({ 'ch-2': 2000 });
      expect(state.watchLater).toHaveLength(1);
      expect(state.videoPlayheads['v-wl']).toEqual({ positionSeconds: 12, updatedAt: 4000 });
    });
  });
});
