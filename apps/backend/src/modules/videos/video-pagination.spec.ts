import { VideosService } from './videos.service';

describe('channel video pagination', () => {
  const publishedAt = new Date('2026-11-10T12:00:00Z');
  const video = { id: 'middle', channelId: 'channel', publishedAt };
  let prisma: any;
  let service: VideosService;

  beforeEach(() => {
    prisma = { video: { findUnique: jest.fn().mockResolvedValue(video), count: jest.fn(), findMany: jest.fn().mockResolvedValue([]) } };
    service = new VideosService(prisma, {} as any, {} as any);
  });

  it('counts newer and older videos within the same active channel, including timestamp ties', async () => {
    prisma.video.count.mockResolvedValueOnce(17).mockResolvedValueOnce(3);
    await expect(service.getChannelPosition('middle')).resolves.toEqual({ newer: 17, older: 3 });
    expect(prisma.video.count).toHaveBeenNthCalledWith(1, { where: {
      channelId: 'channel', type: 'VIDEO', channel: { isActive: true },
      OR: [{ publishedAt: { gt: publishedAt } }, { publishedAt, id: { gt: 'middle' } }],
    } });
    expect(prisma.video.count).toHaveBeenNthCalledWith(2, { where: {
      channelId: 'channel', type: 'VIDEO', channel: { isActive: true },
      OR: [{ publishedAt: { lt: publishedAt } }, { publishedAt, id: { lt: 'middle' } }],
    } });
  });

  it('requests newer videos nearest first and older videos newest first', async () => {
    await service.findAll({ channelId: 'channel', sort: 'oldest', publishedAfter: publishedAt.toISOString(), afterId: 'middle', limit: 16 });
    expect(prisma.video.findMany).toHaveBeenLastCalledWith(expect.objectContaining({
      orderBy: [{ publishedAt: 'asc' }, { id: 'asc' }],
      where: expect.objectContaining({ AND: [{ OR: [
        { publishedAt: { gt: publishedAt } }, { publishedAt, id: { gt: 'middle' } },
      ] }] }),
    }));
    await service.findAll({ channelId: 'channel', sort: 'latest', publishedBefore: publishedAt.toISOString(), beforeId: 'middle', limit: 16 });
    expect(prisma.video.findMany).toHaveBeenLastCalledWith(expect.objectContaining({
      orderBy: [{ publishedAt: 'desc' }, { id: 'desc' }],
      where: expect.objectContaining({ AND: [{ OR: [
        { publishedAt: { lt: publishedAt } }, { publishedAt, id: { lt: 'middle' } },
      ] }] }),
    }));
  });
});
