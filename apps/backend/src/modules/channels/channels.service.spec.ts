import { NotFoundException } from '@nestjs/common';
import { ChannelsService } from './channels.service';

function makeService(cache?: { getOrSet: jest.Mock; invalidate: jest.Mock }) {
  const prisma = {
    channel: {
      findMany: jest.fn(),
      findUnique: jest.fn(),
      upsert: jest.fn(),
      delete: jest.fn(),
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