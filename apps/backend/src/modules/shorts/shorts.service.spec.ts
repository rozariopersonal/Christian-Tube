import { BadRequestException, ServiceUnavailableException } from '@nestjs/common';
import { ShortsService } from './shorts.service';

function makeShortsService(config: Record<string, any> = {}) {
  const configService = {
    get: jest.fn((key: string) => config[key]),
  };
  const prisma = {
    dailyQuotaLog: {
      findUnique: jest.fn().mockResolvedValue({ date: '2026-11-22', unitsConsumed: 0, unitsLimit: 10000 }),
      create: jest.fn(),
      update: jest.fn().mockResolvedValue({}),
    },
    shortCreation: {
      upsert: jest.fn().mockResolvedValue({ id: 'sc1', youtubeVideoId: 'short_ok' }),
      deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      findMany: jest.fn().mockResolvedValue([]),
    },
    video: {
      findUnique: jest.fn().mockResolvedValue(null),
      upsert: jest.fn().mockResolvedValue({ id: 'short_ok' }),
      deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      findMany: jest.fn().mockResolvedValue([]),
    },
    channel: {
      upsert: jest.fn().mockResolvedValue({}),
    },
  };
  const youtubeService = {
    verifyVideosVisibility: jest.fn(),
  };
  const cache = {
    invalidate: jest.fn().mockResolvedValue(undefined),
  };

  const service = new ShortsService(
    configService as any,
    prisma as any,
    youtubeService as any,
    cache as any,
  );
  return { service, prisma, youtubeService, cache };
}

describe('ShortsService.recordCreation', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('rejects private Short before writing ShortCreation, Video, or incrementing quota', async () => {
    const { service, prisma, youtubeService } = makeShortsService();
    youtubeService.verifyVideosVisibility.mockResolvedValue(
      new Map([['priv_short', { videoId: 'priv_short', status: 'private' }]]),
    );

    await expect(
      service.recordCreation({
        youtubeVideoId: 'priv_short',
        title: 'Private Short Title',
        userId: 'u1',
      }),
    ).rejects.toThrow(BadRequestException);

    expect(prisma.shortCreation.upsert).not.toHaveBeenCalled();
    expect(prisma.video.upsert).not.toHaveBeenCalled();
    expect(prisma.dailyQuotaLog.update).not.toHaveBeenCalled();
    expect(prisma.video.deleteMany).toHaveBeenCalledWith({ where: { id: 'priv_short' } });
    expect(prisma.shortCreation.deleteMany).toHaveBeenCalledWith({
      where: { youtubeVideoId: 'priv_short' },
    });
  });

  it('rejects unavailable Short without deleting existing records or writing new ones', async () => {
    const { service, prisma, youtubeService } = makeShortsService();
    youtubeService.verifyVideosVisibility.mockResolvedValue(
      new Map([['missing_short', { videoId: 'missing_short', status: 'unavailable' }]]),
    );

    await expect(
      service.recordCreation({
        youtubeVideoId: 'missing_short',
        title: 'Missing Short',
      }),
    ).rejects.toThrow(BadRequestException);

    expect(prisma.shortCreation.upsert).not.toHaveBeenCalled();
    expect(prisma.video.upsert).not.toHaveBeenCalled();
    expect(prisma.video.deleteMany).not.toHaveBeenCalled();
  });

  it('fails closed with ServiceUnavailableException on YouTube API error', async () => {
    const { service, prisma, youtubeService } = makeShortsService();
    youtubeService.verifyVideosVisibility.mockResolvedValue(
      new Map([['err_short', { videoId: 'err_short', status: 'error', errorMessage: 'timeout' }]]),
    );

    await expect(
      service.recordCreation({
        youtubeVideoId: 'err_short',
        title: 'Error Short',
      }),
    ).rejects.toThrow(ServiceUnavailableException);

    expect(prisma.shortCreation.upsert).not.toHaveBeenCalled();
    expect(prisma.video.upsert).not.toHaveBeenCalled();
    expect(prisma.video.deleteMany).not.toHaveBeenCalled();
  });

  it('writes ShortCreation and Video when video is verified eligible (public or unlisted)', async () => {
    const { service, prisma, youtubeService } = makeShortsService();
    youtubeService.verifyVideosVisibility.mockResolvedValue(
      new Map([
        [
          'short_ok',
          {
            videoId: 'short_ok',
            status: 'eligible',
            item: { id: 'short_ok', status: { privacyStatus: 'unlisted' }, snippet: { title: 'Ok' } },
          },
        ],
      ]),
    );

    const res = await service.recordCreation({
      youtubeVideoId: 'short_ok',
      title: 'Ok',
      userId: 'u1',
    });

    expect(youtubeService.verifyVideosVisibility).toHaveBeenCalledWith(['short_ok'], {
      allowShortsOAuth: true,
    });
    expect(prisma.shortCreation.upsert).toHaveBeenCalledTimes(1);
    expect(prisma.video.upsert).toHaveBeenCalledTimes(1);
    expect(res).toEqual({ id: 'sc1', youtubeVideoId: 'short_ok' });
  });
});

describe('ShortsService.getMyCreations', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('queries shortCreation with userId/userEmail and video with creatorUserId/creatorEmail', async () => {
    const { service, prisma } = makeShortsService();
    prisma.shortCreation.findMany.mockResolvedValue([
      {
        youtubeVideoId: 'yt_short_1',
        title: 'My Short',
        sourceVideoId: 'src_1',
        clipStartTime: 10,
        clipEndTime: 40,
        cropOffsetX: 0,
        privacyStatus: 'unlisted',
        createdAt: new Date('2026-11-26T00:00:00Z'),
      },
    ]);
    prisma.video.findMany.mockResolvedValue([]);

    const res = await service.getMyCreations('u1', 'u1@example.com');

    expect(prisma.shortCreation.findMany).toHaveBeenCalledWith({
      where: {
        OR: [{ userId: 'u1' }, { userEmail: 'u1@example.com' }],
      },
      orderBy: { createdAt: 'desc' },
    });
    expect(prisma.video.findMany).toHaveBeenCalledWith({
      where: {
        type: 'SHORT',
        OR: [{ creatorUserId: 'u1' }, { creatorEmail: 'u1@example.com' }],
      },
      orderBy: { createdAt: 'desc' },
    });
    expect(res).toHaveLength(1);
    expect(res[0].youtubeVideoId).toBe('yt_short_1');
  });
});
