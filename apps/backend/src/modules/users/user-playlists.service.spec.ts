import {
  BadRequestException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';
import { UserPlaylistsService } from './user-playlists.service';

describe('UserPlaylistsService', () => {
  let service: UserPlaylistsService;
  let prisma: any;

  const baseDate = new Date('2026-11-27T00:00:00.000Z');
  const sampleVideoA = {
    id: 'vid-a',
    type: 'VIDEO',
    title: 'Sermon A',
    description: 'Desc A',
    thumbnail: 'https://img.example.com/a.jpg',
    channelId: 'ch-1',
    channelName: 'Grace Church',
    channelThumbnail: 'https://img.example.com/ch1.jpg',
    channelSubscriberCount: '10K',
    viewCount: 120,
    publishedAt: baseDate,
    duration: '12:34',
  };
  const sampleVideoB = {
    id: 'vid-b',
    type: 'VIDEO',
    title: 'Sermon B',
    description: 'Desc B',
    thumbnail: 'https://img.example.com/b.jpg',
    channelId: 'ch-1',
    channelName: 'Grace Church',
    viewCount: 45,
    publishedAt: '2026-11-26T00:00:00.000Z',
    duration: '08:10',
  };

  beforeEach(() => {
    prisma = {
      user: {
        upsert: jest.fn().mockResolvedValue({ id: 'u1' }),
        findUnique: jest.fn().mockResolvedValue({ id: 'u1' }),
        update: jest.fn().mockResolvedValue({ id: 'u1' }),
      },
      userPlaylist: {
        findMany: jest.fn(),
        findFirst: jest.fn(),
        findUnique: jest.fn(),
        create: jest.fn(),
        update: jest.fn(),
      },
      userPlaylistItem: {
        create: jest.fn(),
        update: jest.fn(),
        updateMany: jest.fn(),
        deleteMany: jest.fn(),
      },
      video: {
        findMany: jest.fn().mockResolvedValue([]),
      },
      $transaction: jest.fn(async (cb: any) => cb(prisma)),
    };
    service = new UserPlaylistsService(prisma);
  });

  describe('listPlaylists', () => {
    it('lists active playlists ordered by updatedAt desc and batch-hydrates videos in one query', async () => {
      prisma.userPlaylist.findMany.mockResolvedValue([
        {
          id: 'pl-1',
          userId: 'u1',
          title: 'Favorites',
          description: 'My favs',
          isDeleted: false,
          clientUpdatedAt: new Date(5000),
          createdAt: baseDate,
          updatedAt: baseDate,
          items: [
            { id: 'i2', videoId: 'vid-b', position: 1 },
            { id: 'i1', videoId: 'vid-a', position: 0 },
            { id: 'i3', videoId: 'vid-missing', position: 2 },
          ],
        },
        {
          id: 'pl-2',
          userId: 'u1',
          title: 'Empty',
          description: null,
          isDeleted: false,
          clientUpdatedAt: new Date(4000),
          createdAt: baseDate,
          updatedAt: baseDate,
          items: [],
        },
      ]);
      prisma.video.findMany.mockResolvedValue([sampleVideoA, sampleVideoB]);

      const res = await service.listPlaylists('u1');

      expect(prisma.userPlaylist.findMany).toHaveBeenCalledWith({
        where: { userId: 'u1', isDeleted: false },
        include: { items: { orderBy: { position: 'asc' } } },
        orderBy: { updatedAt: 'desc' },
      });
      expect(prisma.video.findMany).toHaveBeenCalledTimes(1);
      expect(res).toHaveLength(2);
      expect(res[0]).toEqual(
        expect.objectContaining({
          id: 'pl-1',
          title: 'Favorites',
          description: 'My favs',
          thumbnailUrl: 'https://img.example.com/a.jpg',
          videoCount: 2,
          clientUpdatedAt: 5000,
        }),
      );
      expect(res[0].videos.map((v) => v.id)).toEqual(['vid-a', 'vid-b']);
      expect(res[1].thumbnailUrl).toBeNull();
      expect(res[1].videoCount).toBe(0);
    });
  });

  describe('getPlaylist', () => {
    it('returns hydrated playlist for owner', async () => {
      prisma.userPlaylist.findFirst.mockResolvedValue({
        id: 'pl-1',
        userId: 'u1',
        title: 'Study',
        description: null,
        isDeleted: false,
        clientUpdatedAt: new Date(3000),
        createdAt: baseDate,
        updatedAt: baseDate,
        items: [{ id: 'i1', videoId: 'vid-a', position: 0 }],
      });
      prisma.video.findMany.mockResolvedValue([sampleVideoA]);

      const res = await service.getPlaylist('u1', 'pl-1');
      expect(res.id).toBe('pl-1');
      expect(res.videoCount).toBe(1);
      expect(res.videos[0].channelTitle).toBe('Grace Church');
    });

    it('throws NotFoundException when missing, deleted, or not owned', async () => {
      prisma.userPlaylist.findFirst.mockResolvedValue(null);
      await expect(service.getPlaylist('u1', 'missing')).rejects.toThrow(
        NotFoundException,
      );
    });
  });

  describe('createPlaylist', () => {
    it('ensures user, validates & trims fields, and creates playlist', async () => {
      prisma.userPlaylist.create.mockResolvedValue({
        id: 'pl-new',
        userId: 'u_abc',
        title: 'Morning Devotion',
        description: 'Daily',
        isDeleted: false,
        clientUpdatedAt: new Date(10000),
        createdAt: baseDate,
        updatedAt: baseDate,
        items: [],
      });

      const res = await service.createPlaylist(
        { userId: 'u_abc', email: 'u_abc@example.com' },
        { title: '  Morning Devotion  ', description: '  Daily  ', clientUpdatedAt: 10000 },
      );

      expect(prisma.user.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 'u_abc' },
          create: expect.objectContaining({
            id: 'u_abc',
            email: 'u_abc@example.com',
          }),
        }),
      );
      expect(res.title).toBe('Morning Devotion');
      expect(res.description).toBe('Daily');
      expect(res.thumbnailUrl).toBeNull();
    });

    it('rejects creating a user when email is missing instead of synthesizing a guest email', async () => {
      prisma.user.findUnique.mockResolvedValueOnce(null);

      await expect(
        service.createPlaylist(
          { userId: 'u_missing', email: '' },
          { title: 'Sunday' },
        ),
      ).rejects.toThrow('Valid email is required to create user');
      expect(prisma.user.upsert).not.toHaveBeenCalled();
    });

    it('updates existing user on P2002 email collision during ensureUser', async () => {
      prisma.user.upsert.mockRejectedValueOnce({ code: 'P2002' });
      prisma.user.findUnique.mockResolvedValueOnce({ id: 'u2' });
      prisma.user.update.mockResolvedValueOnce({ id: 'u2' });
      prisma.userPlaylist.create.mockResolvedValue({
        id: 'pl-2',
        userId: 'u2',
        title: 'Sunday',
        description: null,
        isDeleted: false,
        clientUpdatedAt: baseDate,
        createdAt: baseDate,
        updatedAt: baseDate,
        items: [],
      });

      const res = await service.createPlaylist(
        { userId: 'u2', email: 'taken@example.com' },
        { title: 'Sunday' },
      );
      expect(prisma.user.upsert).toHaveBeenCalledTimes(1);
      expect(prisma.user.update).toHaveBeenCalledTimes(1);
      expect(res.id).toBe('pl-2');
    });

    it('rethrows non-P2002 errors from ensureUser', async () => {
      prisma.user.upsert.mockRejectedValueOnce(new Error('DB down'));
      await expect(
        service.createPlaylist({ userId: 'u1', email: 'u1@example.com' }, { title: 'Test' }),
      ).rejects.toThrow('DB down');
    });

    it('supports idempotent client-supplied id for same owner (update when newer, keep when stale)', async () => {
      const existing = {
        id: 'client-id-1',
        userId: 'u1',
        title: 'Old Title',
        description: null,
        isDeleted: false,
        clientUpdatedAt: new Date(5000),
        createdAt: baseDate,
        updatedAt: baseDate,
        items: [],
      };
      prisma.userPlaylist.findUnique.mockResolvedValue(existing);
      prisma.userPlaylist.update.mockResolvedValue({
        ...existing,
        title: 'Updated Title',
        clientUpdatedAt: new Date(6000),
      });

      const updated = await service.createPlaylist(
        { userId: 'u1', email: 'u1@example.com' },
        { id: 'client-id-1', title: 'Updated Title', clientUpdatedAt: 6000 },
      );
      expect(prisma.userPlaylist.update).toHaveBeenCalledTimes(1);
      expect(updated.title).toBe('Updated Title');

      prisma.userPlaylist.update.mockClear();
      const stale = await service.createPlaylist(
        { userId: 'u1', email: 'u1@example.com' },
        { id: 'client-id-1', title: 'Stale Title', clientUpdatedAt: 1000 },
      );
      expect(prisma.userPlaylist.update).not.toHaveBeenCalled();
      expect(stale.title).toBe('Old Title');
    });

    it('throws ForbiddenException when client-supplied id is owned by another user', async () => {
      prisma.userPlaylist.findUnique.mockResolvedValue({
        id: 'client-id-1',
        userId: 'other-user',
        title: 'Secret',
        isDeleted: false,
        clientUpdatedAt: new Date(5000),
        createdAt: baseDate,
        updatedAt: baseDate,
        items: [],
      });

      await expect(
        service.createPlaylist(
          { userId: 'u1' },
          { id: 'client-id-1', title: 'Hijack' },
        ),
      ).rejects.toThrow(ForbiddenException);
    });

    it('rejects empty, whitespace, non-string, or >120 char titles and >1000 char descriptions', async () => {
      await expect(
        service.createPlaylist({ userId: 'u1' }, { title: '   ' }),
      ).rejects.toThrow(BadRequestException);
      await expect(
        service.createPlaylist({ userId: 'u1' }, { title: null as any }),
      ).rejects.toThrow(BadRequestException);
      await expect(
        service.createPlaylist({ userId: 'u1' }, { title: 'a'.repeat(121) }),
      ).rejects.toThrow(BadRequestException);
      await expect(
        service.createPlaylist(
          { userId: 'u1' },
          { title: 'Valid', description: 'b'.repeat(1001) },
        ),
      ).rejects.toThrow(BadRequestException);
      await expect(
        service.createPlaylist(
          { userId: 'u1' },
          { title: 'Valid', description: 123 as any },
        ),
      ).rejects.toThrow(BadRequestException);
    });

    it('clamps future clientUpdatedAt timestamps to +60s', async () => {
      const farFuture = Date.now() + 3_600_000;
      prisma.userPlaylist.create.mockImplementation(async (args: any) => ({
        id: 'pl-skew',
        userId: 'u1',
        title: args.data.title,
        description: null,
        isDeleted: false,
        clientUpdatedAt: args.data.clientUpdatedAt,
        createdAt: baseDate,
        updatedAt: baseDate,
        items: [],
      }));

      const res = await service.createPlaylist(
        { userId: 'u1' },
        { title: 'Skew Test', clientUpdatedAt: farFuture },
      );
      expect(res.clientUpdatedAt).toBeLessThanOrEqual(Date.now() + 61_000);
      expect(res.clientUpdatedAt).toBeLessThan(farFuture);
    });
  });

  describe('updatePlaylist', () => {
    it('throws NotFoundException when playlist does not exist or not owned', async () => {
      prisma.userPlaylist.findFirst.mockResolvedValue(null);
      await expect(
        service.updatePlaylist('u1', 'pl-missing', { title: 'New' }),
      ).rejects.toThrow(NotFoundException);
    });

    it('applies LWW update when clientUpdatedAt is newer and skips when stale', async () => {
      const existing = {
        id: 'pl-1',
        userId: 'u1',
        title: 'Original',
        description: 'Old desc',
        isDeleted: false,
        clientUpdatedAt: new Date(5000),
        createdAt: baseDate,
        updatedAt: baseDate,
        items: [],
      };
      prisma.userPlaylist.findFirst.mockResolvedValue(existing);
      prisma.userPlaylist.update.mockResolvedValue({
        ...existing,
        title: 'Renamed',
        description: null,
        clientUpdatedAt: new Date(6000),
      });

      const updated = await service.updatePlaylist('u1', 'pl-1', {
        title: 'Renamed',
        description: '',
        clientUpdatedAt: '6000',
      });
      expect(prisma.userPlaylist.update).toHaveBeenCalledTimes(1);
      expect(updated.title).toBe('Renamed');
      expect(updated.description).toBeNull();

      prisma.userPlaylist.update.mockClear();
      const stale = await service.updatePlaylist('u1', 'pl-1', {
        title: 'Stale Rename',
        clientUpdatedAt: 2000,
      });
      expect(prisma.userPlaylist.update).not.toHaveBeenCalled();
      expect(stale.title).toBe('Original');
    });
  });

  describe('deletePlaylist', () => {
    it('throws NotFoundException if missing or owned by another user', async () => {
      prisma.userPlaylist.findUnique.mockResolvedValue(null);
      await expect(service.deletePlaylist('u1', 'pl-1')).rejects.toThrow(
        NotFoundException,
      );

      prisma.userPlaylist.findUnique.mockResolvedValue({
        id: 'pl-1',
        userId: 'other',
        isDeleted: false,
        clientUpdatedAt: new Date(1000),
      });
      await expect(service.deletePlaylist('u1', 'pl-1')).rejects.toThrow(
        NotFoundException,
      );
    });

    it('soft-deletes active playlist and is idempotent when already deleted', async () => {
      prisma.userPlaylist.findUnique.mockResolvedValue({
        id: 'pl-1',
        userId: 'u1',
        isDeleted: false,
        clientUpdatedAt: new Date(1000),
      });
      prisma.userPlaylist.update.mockResolvedValue({});

      const res = await service.deletePlaylist('u1', 'pl-1', 2000);
      expect(res).toEqual({ status: 'deleted', id: 'pl-1' });
      expect(prisma.userPlaylist.update).toHaveBeenCalledWith({
        where: { id: 'pl-1' },
        data: { isDeleted: true, clientUpdatedAt: new Date(2000) },
      });

      prisma.userPlaylist.update.mockClear();
      prisma.userPlaylist.findUnique.mockResolvedValue({
        id: 'pl-1',
        userId: 'u1',
        isDeleted: true,
        clientUpdatedAt: new Date(2000),
      });
      const res2 = await service.deletePlaylist('u1', 'pl-1', 3000);
      expect(res2).toEqual({ status: 'deleted', id: 'pl-1' });
      expect(prisma.userPlaylist.update).not.toHaveBeenCalled();
    });
  });

  describe('addItem', () => {
    it('validates videoId and ownership', async () => {
      await expect(
        service.addItem('u1', 'pl-1', { videoId: '  ' }),
      ).rejects.toThrow(BadRequestException);

      prisma.userPlaylist.findFirst.mockResolvedValue(null);
      await expect(
        service.addItem('u1', 'pl-1', { videoId: 'vid-a' }),
      ).rejects.toThrow(NotFoundException);
    });

    it('is idempotent when videoId already exists in playlist', async () => {
      prisma.userPlaylist.findFirst.mockResolvedValue({
        id: 'pl-1',
        userId: 'u1',
        title: 'Study',
        description: null,
        isDeleted: false,
        clientUpdatedAt: new Date(1000),
        createdAt: baseDate,
        updatedAt: baseDate,
        items: [{ id: 'i1', videoId: 'vid-a', position: 0 }],
      });
      prisma.video.findMany.mockResolvedValue([sampleVideoA]);

      const res = await service.addItem('u1', 'pl-1', { videoId: 'vid-a' });
      expect(prisma.userPlaylistItem.create).not.toHaveBeenCalled();
      expect(res.videoCount).toBe(1);
    });

    it('inserts at explicit position and shifts subsequent items', async () => {
      prisma.userPlaylist.findFirst.mockResolvedValue({
        id: 'pl-1',
        userId: 'u1',
        title: 'Study',
        description: null,
        isDeleted: false,
        clientUpdatedAt: new Date(1000),
        createdAt: baseDate,
        updatedAt: baseDate,
        items: [{ id: 'i1', videoId: 'vid-a', position: 0 }],
      });
      prisma.userPlaylist.update.mockResolvedValue({
        id: 'pl-1',
        userId: 'u1',
        title: 'Study',
        description: null,
        isDeleted: false,
        clientUpdatedAt: new Date(2000),
        createdAt: baseDate,
        updatedAt: baseDate,
        items: [
          { id: 'i2', videoId: 'vid-b', position: 0 },
          { id: 'i1', videoId: 'vid-a', position: 1 },
        ],
      });
      prisma.video.findMany.mockResolvedValue([sampleVideoA, sampleVideoB]);

      const res = await service.addItem('u1', 'pl-1', {
        videoId: 'vid-b',
        position: 0,
        clientUpdatedAt: 2000,
      });

      expect(prisma.userPlaylistItem.updateMany).toHaveBeenCalledWith({
        where: { playlistId: 'pl-1', position: { gte: 0 } },
        data: { position: { increment: 1 } },
      });
      expect(prisma.userPlaylistItem.create).toHaveBeenCalledWith({
        data: { playlistId: 'pl-1', videoId: 'vid-b', position: 0 },
      });
      expect(res.videos.map((v) => v.id)).toEqual(['vid-b', 'vid-a']);
    });
  });

  describe('removeItem', () => {
    it('throws NotFoundException when playlist is missing', async () => {
      prisma.userPlaylist.findFirst.mockResolvedValue(null);
      await expect(service.removeItem('u1', 'pl-1', 'vid-a')).rejects.toThrow(
        NotFoundException,
      );
    });

    it('is idempotent when videoId is not in playlist', async () => {
      prisma.userPlaylist.findFirst.mockResolvedValue({
        id: 'pl-1',
        userId: 'u1',
        title: 'Study',
        description: null,
        isDeleted: false,
        clientUpdatedAt: new Date(1000),
        createdAt: baseDate,
        updatedAt: baseDate,
        items: [{ id: 'i1', videoId: 'vid-a', position: 0 }],
      });
      prisma.video.findMany.mockResolvedValue([sampleVideoA]);

      const res = await service.removeItem('u1', 'pl-1', 'vid-absent');
      expect(prisma.userPlaylistItem.deleteMany).not.toHaveBeenCalled();
      expect(res.videoCount).toBe(1);
    });

    it('removes item and compacts remaining positions to 0..n-1', async () => {
      prisma.userPlaylist.findFirst.mockResolvedValue({
        id: 'pl-1',
        userId: 'u1',
        title: 'Study',
        description: null,
        isDeleted: false,
        clientUpdatedAt: new Date(1000),
        createdAt: baseDate,
        updatedAt: baseDate,
        items: [
          { id: 'i1', videoId: 'vid-a', position: 0 },
          { id: 'i2', videoId: 'vid-b', position: 1 },
        ],
      });
      prisma.userPlaylist.update.mockResolvedValue({
        id: 'pl-1',
        userId: 'u1',
        title: 'Study',
        description: null,
        isDeleted: false,
        clientUpdatedAt: new Date(2000),
        createdAt: baseDate,
        updatedAt: baseDate,
        items: [{ id: 'i2', videoId: 'vid-b', position: 0 }],
      });
      prisma.video.findMany.mockResolvedValue([sampleVideoB]);

      const res = await service.removeItem('u1', 'pl-1', 'vid-a');
      expect(prisma.userPlaylistItem.deleteMany).toHaveBeenCalledWith({
        where: { playlistId: 'pl-1', videoId: 'vid-a' },
      });
      expect(prisma.userPlaylistItem.update).toHaveBeenCalledWith({
        where: { id: 'i2' },
        data: { position: 0 },
      });
      expect(res.videos.map((v) => v.id)).toEqual(['vid-b']);
    });
  });

  describe('reorderItems', () => {
    it('throws NotFoundException when playlist is missing', async () => {
      prisma.userPlaylist.findFirst.mockResolvedValue(null);
      await expect(
        service.reorderItems('u1', 'pl-1', { videoIds: ['vid-a'] }),
      ).rejects.toThrow(NotFoundException);
    });

    it('reorders listed items and appends unlisted existing items at the end', async () => {
      prisma.userPlaylist.findFirst.mockResolvedValue({
        id: 'pl-1',
        userId: 'u1',
        title: 'Study',
        description: null,
        isDeleted: false,
        clientUpdatedAt: new Date(1000),
        createdAt: baseDate,
        updatedAt: baseDate,
        items: [
          { id: 'i1', videoId: 'vid-a', position: 0 },
          { id: 'i2', videoId: 'vid-b', position: 1 },
          { id: 'i3', videoId: 'vid-c', position: 2 },
        ],
      });
      prisma.userPlaylist.update.mockResolvedValue({
        id: 'pl-1',
        userId: 'u1',
        title: 'Study',
        description: null,
        isDeleted: false,
        clientUpdatedAt: new Date(3000),
        createdAt: baseDate,
        updatedAt: baseDate,
        items: [
          { id: 'i2', videoId: 'vid-b', position: 0 },
          { id: 'i1', videoId: 'vid-a', position: 1 },
          { id: 'i3', videoId: 'vid-c', position: 2 },
        ],
      });
      prisma.video.findMany.mockResolvedValue([sampleVideoA, sampleVideoB]);

      const res = await service.reorderItems('u1', 'pl-1', {
        videoIds: ['vid-b', 'vid-b', 'unknown-id'],
        clientUpdatedAt: 3000,
      });

      expect(prisma.userPlaylistItem.update).toHaveBeenCalledWith({
        where: { id: 'i2' },
        data: { position: 0 },
      });
      expect(prisma.userPlaylistItem.update).toHaveBeenCalledWith({
        where: { id: 'i1' },
        data: { position: 1 },
      });
      // i3 stayed at position 2 so no update needed
      expect(prisma.userPlaylistItem.update).toHaveBeenCalledTimes(2);
      expect(res.videos.map((v) => v.id)).toEqual(['vid-b', 'vid-a']);
    });
  });

  describe('getPlaylistsSyncSlice', () => {
    it('returns active playlists and tombstones while reusing existingVideoMap', async () => {
      prisma.userPlaylist.findMany.mockResolvedValue([
        {
          id: 'pl-active',
          userId: 'u1',
          title: 'Active',
          description: null,
          isDeleted: false,
          clientUpdatedAt: new Date(5000),
          createdAt: baseDate,
          updatedAt: baseDate,
          items: [{ id: 'i1', videoId: 'vid-a', position: 0 }],
        },
        {
          id: 'pl-deleted',
          userId: 'u1',
          title: 'Deleted',
          description: null,
          isDeleted: true,
          clientUpdatedAt: new Date(7000),
          createdAt: baseDate,
          updatedAt: baseDate,
          items: [],
        },
      ]);

      const preHydrated = new Map<string, any>([['vid-a', sampleVideoA]]);
      const slice = await service.getPlaylistsSyncSlice('u1', preHydrated);

      expect(prisma.video.findMany).not.toHaveBeenCalled();
      expect(slice.playlists).toHaveLength(1);
      expect(slice.playlists[0].id).toBe('pl-active');
      expect(slice.playlists[0].videoCount).toBe(1);
      expect(slice.playlistTombstones).toEqual({ 'pl-deleted': 7000 });
    });

    it('returns empty slice when userPlaylist delegate is unavailable', async () => {
      const minimalService = new UserPlaylistsService({} as any);
      const slice = await minimalService.getPlaylistsSyncSlice('u1');
      expect(slice).toEqual({ playlists: [], playlistTombstones: {} });
    });
  });

  describe('concurrency P2002 race handling', () => {
    it('returns existing playlist idempotently when createPlaylist hits P2002 for same owner', async () => {
      const existing = {
        id: 'pl-race',
        userId: 'u1',
        title: 'Race Playlist',
        description: null,
        isDeleted: false,
        clientUpdatedAt: baseDate,
        createdAt: baseDate,
        updatedAt: baseDate,
        items: [],
      };
      prisma.userPlaylist.findUnique
        .mockResolvedValueOnce(null)
        .mockResolvedValueOnce(existing);
      prisma.userPlaylist.create.mockRejectedValueOnce({ code: 'P2002' });

      const res = await service.createPlaylist(
        { userId: 'u1', email: 'a@b.com' },
        { id: 'pl-race', title: 'Race Playlist' },
      );
      expect(res.id).toBe('pl-race');
    });

    it('throws ForbiddenException when createPlaylist hits P2002 for another user', async () => {
      prisma.userPlaylist.findUnique
        .mockResolvedValueOnce(null)
        .mockResolvedValueOnce({
          id: 'pl-race',
          userId: 'other-user',
          title: 'Other',
          items: [],
        });
      prisma.userPlaylist.create.mockRejectedValueOnce({ code: 'P2002' });

      await expect(
        service.createPlaylist(
          { userId: 'u1', email: 'a@b.com' },
          { id: 'pl-race', title: 'Race Playlist' },
        ),
      ).rejects.toThrow(ForbiddenException);
    });

    it('returns playlist idempotently when addItem hits P2002 duplicate race', async () => {
      const existing = {
        id: 'pl-1',
        userId: 'u1',
        title: 'Sermons',
        description: null,
        isDeleted: false,
        clientUpdatedAt: baseDate,
        createdAt: baseDate,
        updatedAt: baseDate,
        items: [],
      };
      const withItem = {
        ...existing,
        items: [{ id: 'i1', videoId: 'vid-a', position: 0 }],
      };
      prisma.userPlaylist.findFirst
        .mockResolvedValueOnce(existing)
        .mockResolvedValueOnce(withItem);
      prisma.userPlaylistItem.create.mockRejectedValueOnce({ code: 'P2002' });
      prisma.video.findMany.mockResolvedValueOnce([sampleVideoA]);

      const res = await service.addItem('u1', 'pl-1', { videoId: 'vid-a' });
      expect(res.videoCount).toBe(1);
      expect(res.videos[0].id).toBe('vid-a');
    });
  });
});
