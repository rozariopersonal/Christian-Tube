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
    it('upserts preferences and syncs channel subscriptions', async () => {
      const savedPref = {
        userId: 'u1',
        languages: ['en', 'ta'],
        videoChannelIds: ['c1', 'c2'],
        shortsChannelIds: ['c2', 'c3'],
        primaryBibleVersionId: 'TAOBVSI',
        hasCompletedOnboarding: true,
      };
      prisma.userPreference.upsert.mockResolvedValue(savedPref);
      prisma.channelSubscription.upsert.mockResolvedValue({ id: 'sub1' });

      const res = await service.savePreferences('u1', {
        languages: ['en', 'ta'],
        videoChannelIds: ['c1', 'c2'],
        shortsChannelIds: ['c2', 'c3'],
        primaryBibleVersionId: 'TAOBVSI',
        hasCompletedOnboarding: true,
      });

      expect(prisma.userPreference.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { userId: 'u1' },
        }),
      );
      expect(prisma.channelSubscription.upsert).toHaveBeenCalledTimes(3); // c1, c2, c3 unique
      expect(res).toEqual(savedPref);
    });
  });
});
