import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { ChannelsService } from './channels.service';

function makeService(cache?: { getOrSet: jest.Mock; invalidate: jest.Mock }) {
  const prisma = {
    channel: {
      findMany: jest.fn().mockResolvedValue([]),
      findFirst: jest.fn().mockResolvedValue(null),
      findUnique: jest.fn(),
      upsert: jest.fn(),
      delete: jest.fn(),
    },
    channelRequest: {
      findMany: jest.fn().mockResolvedValue([]),
      findFirst: jest.fn().mockResolvedValue(null),
      findUnique: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
    },
    channelSubscription: {
      findMany: jest.fn(),
      upsert: jest.fn(),
      updateMany: jest.fn(),
      deleteMany: jest.fn(),
    },
    user: {
      upsert: jest.fn(),
    },
    video: {
      deleteMany: jest.fn(),
    },
  };
  const configService = { get: jest.fn((key: string) => undefined) };
  const syncService = {
    syncChannel: jest.fn().mockResolvedValue(undefined),
    subscribeChannelToWebSub: jest.fn().mockResolvedValue(undefined),
  };
  const service = new ChannelsService(
    prisma as any,
    configService as any,
    syncService as any,
    cache as any,
  );
  return { service, prisma, configService, syncService, cache };
}

function subscriptionRow(userId: string, channelId: string) {
  return {
    id: 'sub_1',
    userId,
    channelId,
    createdAt: new Date('2026-01-01'),
    channel: {
      id: channelId,
      name: `Channel ${channelId}`,
      description: null,
      thumbnail: `thumb-${channelId}`,
      subscriberCount: '100',
      isActive: true,
      _count: { videos: 7 },
    },
  };
}

describe('ChannelsService subscriptions', () => {
  describe('listSubscriptions', () => {
    it('returns the user channel ids and hydrated channel rows', async () => {
      const { service, prisma } = makeService();
      prisma.channelSubscription.findMany.mockResolvedValue([
        subscriptionRow('u1', 'c1'),
        subscriptionRow('u1', 'c2'),
      ]);

      const out = await service.listSubscriptions('u1');

      expect(prisma.channelSubscription.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { userId: 'u1', isActive: true },
          include: {
            channel: { include: { _count: { select: { videos: true } } } },
          },
          orderBy: { createdAt: 'desc' },
        }),
      );
      expect(out.channelIds).toEqual(['c1', 'c2']);
      expect(out.channels).toHaveLength(2);
      expect(out.channels[0]).toMatchObject({
        id: 'c1',
        name: 'Channel c1',
        videoCount: 7,
        isSubscribed: true,
      });
    });

    it('returns empty lists when the user has no subscriptions', async () => {
      const { service, prisma } = makeService();
      prisma.channelSubscription.findMany.mockResolvedValue([]);

      const out = await service.listSubscriptions('u1');

      expect(out).toEqual({ channelIds: [], channels: [] });
    });
  });

  describe('subscribe', () => {
    it('ensures the user exists and upserts the subscription', async () => {
      const { service, prisma } = makeService();
      prisma.channel.findUnique.mockResolvedValue({ id: 'c1', name: 'Channel c1' });
      prisma.user.upsert.mockResolvedValue({ id: 'u1', email: 'u@example.com' });
      prisma.channelSubscription.upsert.mockResolvedValue({
        id: 'sub_1',
        userId: 'u1',
        channelId: 'c1',
      });

      const out = await service.subscribe({ userId: 'u1', email: 'u@example.com' }, 'c1');

      expect(prisma.channel.findUnique).toHaveBeenCalledWith({ where: { id: 'c1' } });
      expect(prisma.user.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 'u1' },
          create: expect.objectContaining({ id: 'u1', email: 'u@example.com' }),
        }),
      );
      expect(prisma.channelSubscription.upsert).toHaveBeenCalledWith({
        where: { userId_channelId: { userId: 'u1', channelId: 'c1' } },
        update: expect.objectContaining({ isActive: true, clientUpdatedAt: expect.any(Date) }),
        create: expect.objectContaining({ userId: 'u1', channelId: 'c1', isActive: true, clientUpdatedAt: expect.any(Date) }),
      });
      expect(out).toMatchObject({ status: 'subscribed', channelId: 'c1' });
    });

    it('creates a synthetic guest email when the token has no email', async () => {
      const { service, prisma } = makeService();
      prisma.channel.findUnique.mockResolvedValue({ id: 'c1' });
      prisma.user.upsert.mockResolvedValue({ id: 'guest_1' });
      prisma.channelSubscription.upsert.mockResolvedValue({ id: 'sub_1' });

      await service.subscribe({ userId: 'guest_1', email: null }, 'c1');

      expect(prisma.user.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          create: expect.objectContaining({ id: 'guest_1', email: 'guest_guest_1@christianapp.local' }),
        }),
      );
    });

    it('throws NotFoundException when the channel does not exist', async () => {
      const { service, prisma } = makeService();
      prisma.channel.findUnique.mockResolvedValue(null);

      await expect(
        service.subscribe({ userId: 'u1', email: 'u@example.com' }, 'missing'),
      ).rejects.toThrow(NotFoundException);
      expect(prisma.channelSubscription.upsert).not.toHaveBeenCalled();
    });
  });

  describe('unsubscribe', () => {
    it('tombstones the user+channel subscription row with LWW timestamp', async () => {
      const { service, prisma } = makeService();
      prisma.channelSubscription.updateMany.mockResolvedValue({ count: 1 });

      const out = await service.unsubscribe('u1', 'c1');

      expect(prisma.channelSubscription.updateMany).toHaveBeenCalledWith({
        where: { userId: 'u1', channelId: 'c1', clientUpdatedAt: { lte: expect.any(Date) } },
        data: { isActive: false, clientUpdatedAt: expect.any(Date) },
      });
      expect(out).toMatchObject({ status: 'unsubscribed', channelId: 'c1' });
    });

    it('is idempotent when the subscription does not exist', async () => {
      const { service, prisma } = makeService();
      prisma.channelSubscription.updateMany.mockResolvedValue({ count: 0 });

      await expect(service.unsubscribe('u1', 'c1')).resolves.toMatchObject({
        status: 'unsubscribed',
        channelId: 'c1',
      });
    });
  });

  describe('Direct DB subscription reads (no stale 24h Redis cache)', () => {
    it('reads active subscriptions directly from Postgres', async () => {
      const cache = {
        getOrSet: jest.fn(),
        invalidate: jest.fn().mockResolvedValue(undefined),
      };
      const { service, prisma } = makeService(cache);
      prisma.channelSubscription.findMany.mockResolvedValue([subscriptionRow('u1', 'c1')]);

      const out = await service.listSubscriptions('u1');
      expect(out.channelIds).toEqual(['c1']);
      expect(cache.getOrSet).not.toHaveBeenCalled();
    });
  });
});

describe('ChannelsService channel requests & search', () => {
  describe('createRequest', () => {
    it('rejects empty channelUrl with BadRequestException', async () => {
      const { service } = makeService();
      await expect(service.createRequest({ channelUrl: '   ' })).rejects.toThrow(
        BadRequestException,
      );
    });

    it('rejects when channel already exists in the platform', async () => {
      const { service, prisma } = makeService();
      prisma.channel.findFirst.mockResolvedValue({ id: 'UC1234567890123456789012', name: 'Grace TV' });

      await expect(
        service.createRequest({
          channelUrl: 'https://www.youtube.com/channel/UC1234567890123456789012/videos',
          channelName: 'Grace TV',
        }),
      ).rejects.toThrow(ConflictException);
      expect(prisma.channelRequest.create).not.toHaveBeenCalled();
    });

    it('rejects duplicate pending request after URL normalization', async () => {
      const { service, prisma } = makeService();
      jest.spyOn(service, 'resolveChannelInfo').mockResolvedValue(null);
      prisma.channelRequest.findFirst.mockResolvedValue({ id: 'req_existing' });

      await expect(
        service.createRequest({
          channelUrl: 'https://m.youtube.com/@GraceFellowship/videos',
          channelName: 'Grace Fellowship',
        }),
      ).rejects.toThrow(ConflictException);
    });

    it('rejects @handle when resolved UC channel ID already exists in platform', async () => {
      const { service, prisma } = makeService();
      jest.spyOn(service, 'resolveChannelInfo').mockResolvedValue({
        id: 'UC1234567890123456789012',
        name: 'Grace Fellowship',
        thumbnail: null,
        description: null,
        subscriberCount: null,
      });
      prisma.channel.findFirst.mockResolvedValue({
        id: 'UC1234567890123456789012',
        name: 'Grace Fellowship',
      });

      await expect(
        service.createRequest({ channelUrl: 'https://youtube.com/@GraceFellowship' }),
      ).rejects.toThrow(ConflictException);
      expect(prisma.channel.findFirst).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            id: {
              in: expect.arrayContaining(['@GraceFellowship', 'UC1234567890123456789012']),
            },
          },
        }),
      );
    });

    it('stores normalized channelUrl, channelName, notes, and submittedBy', async () => {
      const { service, prisma } = makeService();
      jest.spyOn(service, 'resolveChannelInfo').mockResolvedValue(null);
      prisma.channelRequest.create.mockImplementation(async ({ data }: any) => ({
        id: 'req_1',
        ...data,
      }));

      const created = await service.createRequest({
        channelUrl: 'https://www.youtube.com/@GraceFellowship/featured',
        channelName: 'Grace Fellowship',
        notes: 'Great Sunday sermons',
        submittedBy: 'user@example.com',
      });

      expect(created).toMatchObject({
        channelUrl: '@GraceFellowship',
        channelName: 'Grace Fellowship',
        notes: 'Great Sunday sermons',
        submittedBy: 'user@example.com',
        status: 'PENDING',
      });
    });
  });

  describe('approveRequest & rejectRequest', () => {
    it('passes channelName (never notes) to addChannel on approve', async () => {
      const { service, prisma } = makeService();
      prisma.channelRequest.findUnique.mockResolvedValue({
        id: 'req_1',
        channelUrl: '@GraceFellowship',
        channelName: 'Grace Fellowship',
        notes: 'User reason that must not become the title',
        status: 'PENDING',
      });
      const addSpy = jest.spyOn(service, 'addChannel').mockResolvedValue({
        status: 'success',
        message: 'ok',
        channel: { id: 'UC_grace', name: 'Grace Fellowship' } as any,
      });
      prisma.channelRequest.update.mockResolvedValue({
        id: 'req_1',
        status: 'APPROVED',
      });

      const res = await service.approveRequest('req_1', 'admin@example.com');

      expect(addSpy).toHaveBeenCalledWith({
        channelUrl: '@GraceFellowship',
        name: 'Grace Fellowship',
        adminEmail: 'admin@example.com',
      });
      expect(res.status).toBe('success');
    });

    it('rejects approving or rejecting a non-PENDING request with ConflictException', async () => {
      const { service, prisma } = makeService();
      prisma.channelRequest.findUnique.mockResolvedValue({
        id: 'req_done',
        channelUrl: '@Done',
        status: 'APPROVED',
      });

      await expect(service.approveRequest('req_done')).rejects.toThrow(ConflictException);
      await expect(service.rejectRequest('req_done', 'nope')).rejects.toThrow(ConflictException);
    });
  });

  describe('searchYouTube', () => {
    it('returns empty array for queries shorter than 2 characters', async () => {
      const { service } = makeService();
      await expect(service.searchYouTube('a')).resolves.toEqual([]);
      await expect(service.searchYouTube('   ')).resolves.toEqual([]);
    });

    it('tags remote results with fresh isExisting from Postgres even when cached', async () => {
      const cache = {
        getOrSet: jest.fn(async (_ns: string, _key: string, _ttl: number, fn: () => Promise<any>) => [
          { id: 'UC_existing', name: 'Existing Channel', handle: '@existing' },
          { id: 'UC_new', name: 'New Channel', handle: '@new' },
        ]),
        invalidate: jest.fn(),
      };
      const { service, prisma } = makeService(cache);
      prisma.channel.findMany
        .mockResolvedValueOnce([{ id: 'UC_existing' }]) // existing check
        .mockResolvedValueOnce([]); // local search

      const results = await service.searchYouTube('channel');

      expect(results).toHaveLength(2);
      expect(results[0]).toMatchObject({ id: 'UC_existing', isExisting: true });
      expect(results[1]).toMatchObject({ id: 'UC_new', isExisting: false });
    });
  });
});