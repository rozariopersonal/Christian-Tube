import { UserItemsService } from './user-items.service';

describe('UserItemsService', () => {
  let service: UserItemsService;
  let prisma: any;

  beforeEach(() => {
    prisma = {
      user: {
        upsert: jest.fn().mockResolvedValue({ id: 'u1' }),
      },
      userItem: {
        findMany: jest.fn().mockResolvedValue([]),
        createMany: jest.fn().mockResolvedValue({ count: 1 }),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
    };
    service = new UserItemsService(prisma);
  });

  it('upserts valid bible/book/article items with LWW clientUpdatedAt guard and rejects invalid types', async () => {
    const res = await service.upsertBatch('u1', 'u1@example.com', [
      {
        id: 'range-1',
        itemType: 'text_range',
        feature: 'book',
        targetId: 'book:b1:0:3',
        startOffset: 5,
        endOffset: 18,
        color: '#FEF08A',
        text: 'grace alone',
        updatedAt: 5000,
      },
      {
        id: 'bad-1',
        itemType: 'unknown_type',
        feature: 'book',
      },
    ]);

    expect(res.results).toEqual([
      { id: 'range-1', status: 'ok' },
      { id: 'bad-1', status: 'rejected' },
    ]);
    expect(prisma.user.upsert).toHaveBeenCalledTimes(1);
    expect(prisma.userItem.createMany).toHaveBeenCalledTimes(1);
    expect(prisma.userItem.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          userId: 'u1',
          id: 'range-1',
          clientUpdatedAt: { lte: new Date(5000) },
        }),
      }),
    );
  });

  it('lists items filtered by feature and after cursor', async () => {
    prisma.userItem.findMany.mockResolvedValue([
      {
        id: 'hl-1',
        userId: 'u1',
        itemType: 'highlight',
        feature: 'bible',
        targetId: 'GEN:1:1',
        book: 'GEN',
        chapter: 1,
        verseStart: 1,
        verseEnd: 1,
        colorIndex: 0,
        text: 'In the beginning',
        isDeleted: false,
        clientUpdatedAt: new Date('2026-11-20T10:00:00.000Z'),
        createdAt: new Date('2026-11-20T09:00:00.000Z'),
      },
    ]);

    const res = await service.listItems('u1', {
      feature: 'bible',
      after: '2026-11-20T08:00:00.000Z',
    });

    expect(prisma.userItem.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          userId: 'u1',
          feature: 'bible',
          clientUpdatedAt: { gt: new Date('2026-11-20T08:00:00.000Z') },
        },
      }),
    );
    expect(res.items).toHaveLength(1);
    expect(res.items[0]).toMatchObject({
      id: 'hl-1',
      itemType: 'highlight',
      feature: 'bible',
      deleted: false,
    });
  });

  it('accepts video and short note items and rejects unknown features', async () => {
    const res = await service.upsertBatch('u1', 'u1@example.com', [
      {
        id: 'note-v1',
        itemType: 'note',
        feature: 'video',
        targetId: 'vid-123',
        text: 'Key sermon point at 12:30',
        contextText: 'Grace Channel',
        updatedAt: 6000,
      },
      {
        id: 'note-s1',
        itemType: 'note',
        feature: 'short',
        targetId: 'short-456',
        text: 'Remember this verse',
        updatedAt: 6001,
      },
      {
        id: 'bad-feature',
        itemType: 'note',
        feature: 'unknown_feature',
        targetId: 'x',
        text: 'nope',
      },
    ]);

    expect(res.results).toEqual([
      { id: 'note-v1', status: 'ok' },
      { id: 'note-s1', status: 'ok' },
      { id: 'bad-feature', status: 'rejected' },
    ]);
  });
});
