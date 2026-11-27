import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { UserPlaylistsService } from './user-playlists.service';
import { UsersService } from './users.service';

describe('UserPlaylistsService & UsersService (Postgres integration)', () => {
  let prisma: PrismaService;
  let playlistsService: UserPlaylistsService;
  let usersService: UsersService;

  const runSuffix = randomUUID().slice(0, 8);
  const guestUserId = `guest_int_${runSuffix}`;
  const otherUserId = `other_int_${runSuffix}`;
  const channelId = `ch_int_${runSuffix}`;
  const videoAId = `vid_a_${runSuffix}`;
  const videoBId = `vid_b_${runSuffix}`;
  const videoCId = `vid_c_${runSuffix}`;

  beforeAll(async () => {
    prisma = new PrismaService();
    await prisma.$connect();

    const configService = {
      get: () => [],
    } as unknown as ConfigService;

    playlistsService = new UserPlaylistsService(prisma);
    usersService = new UsersService(
      prisma,
      configService,
      undefined,
      playlistsService,
    );

    await prisma.channel.create({
      data: {
        id: channelId,
        name: 'Integration Test Channel',
        thumbnail: 'https://img.example.com/ch.jpg',
      },
    });

    const now = new Date();
    await prisma.video.createMany({
      data: [
        {
          id: videoAId,
          title: 'Video A',
          description: 'Desc A',
          thumbnail: 'https://img.example.com/a.jpg',
          channelId,
          channelName: 'Integration Test Channel',
          publishedAt: now,
          duration: '10:00',
        },
        {
          id: videoBId,
          title: 'Video B',
          description: 'Desc B',
          thumbnail: 'https://img.example.com/b.jpg',
          channelId,
          channelName: 'Integration Test Channel',
          publishedAt: now,
          duration: '11:00',
        },
        {
          id: videoCId,
          title: 'Video C',
          description: 'Desc C',
          thumbnail: 'https://img.example.com/c.jpg',
          channelId,
          channelName: 'Integration Test Channel',
          publishedAt: now,
          duration: '12:00',
        },
      ],
    });
  });

  afterAll(async () => {
    await prisma.user.deleteMany({
      where: { id: { in: [guestUserId, otherUserId] } },
    });
    await prisma.video.deleteMany({
      where: { id: { in: [videoAId, videoBId, videoCId] } },
    });
    await prisma.channel.deleteMany({
      where: { id: channelId },
    });
    await prisma.$disconnect();
  });

  it('supports fresh guest ensureUser, full playlist CRUD, reorder, owner isolation, watch_later batch sync, and getSyncState', async () => {
    const clientPlaylistId = randomUUID();
    const t0 = Date.now() - 5000;

    // 1. Fresh guest user creates playlist with client-supplied id (no prior User row)
    const created = await playlistsService.createPlaylist(
      { userId: guestUserId, email: '' },
      {
        id: clientPlaylistId,
        title: 'Sunday Sermons',
        description: 'To study',
        clientUpdatedAt: t0,
      },
    );
    expect(created.id).toBe(clientPlaylistId);
    expect(created.title).toBe('Sunday Sermons');
    expect(created.videoCount).toBe(0);
    expect(created.thumbnailUrl).toBeNull();

    // 2. Owner isolation: another user cannot hijack id, read, update, or delete
    await expect(
      playlistsService.createPlaylist(
        { userId: otherUserId, email: `${otherUserId}@example.com` },
        { id: clientPlaylistId, title: 'Hijack' },
      ),
    ).rejects.toThrow(ForbiddenException);
    await expect(
      playlistsService.getPlaylist(otherUserId, clientPlaylistId),
    ).rejects.toThrow(NotFoundException);
    await expect(
      playlistsService.updatePlaylist(otherUserId, clientPlaylistId, {
        title: 'Hack',
      }),
    ).rejects.toThrow(NotFoundException);
    await expect(
      playlistsService.deletePlaylist(otherUserId, clientPlaylistId),
    ).rejects.toThrow(NotFoundException);

    // 3. Add items, verify idempotency & hydration
    await playlistsService.addItem(guestUserId, clientPlaylistId, {
      videoId: videoAId,
    });
    await playlistsService.addItem(guestUserId, clientPlaylistId, {
      videoId: videoBId,
    });
    await playlistsService.addItem(guestUserId, clientPlaylistId, {
      videoId: videoCId,
    });
    const dupAdd = await playlistsService.addItem(guestUserId, clientPlaylistId, {
      videoId: videoAId,
    });
    expect(dupAdd.videoCount).toBe(3);
    expect(dupAdd.videos.map((v) => v.id)).toEqual([videoAId, videoBId, videoCId]);
    expect(dupAdd.thumbnailUrl).toBe('https://img.example.com/a.jpg');

    // 4. Reorder items (partial list preserves unlisted items at end)
    const reordered = await playlistsService.reorderItems(
      guestUserId,
      clientPlaylistId,
      { videoIds: [videoCId, videoAId] },
    );
    expect(reordered.videos.map((v) => v.id)).toEqual([
      videoCId,
      videoAId,
      videoBId,
    ]);
    expect(reordered.thumbnailUrl).toBe('https://img.example.com/c.jpg');

    // 5. Remove item & compact positions
    const afterRemove = await playlistsService.removeItem(
      guestUserId,
      clientPlaylistId,
      videoAId,
    );
    expect(afterRemove.videos.map((v) => v.id)).toEqual([videoCId, videoBId]);

    // 6. Update playlist metadata with LWW
    const updated = await playlistsService.updatePlaylist(
      guestUserId,
      clientPlaylistId,
      { title: 'Sunday Sermons Updated', clientUpdatedAt: Date.now() },
    );
    expect(updated.title).toBe('Sunday Sermons Updated');

    // 7. Batch sync watch_later and verify unified /api/user/state payload
    const batchRes = await usersService.upsertWatchItemsBatch(guestUserId, '', [
      {
        opId: 'wl-1',
        itemType: 'watch_later',
        itemId: videoAId,
        clientUpdatedAt: Date.now(),
      },
    ]);
    expect(batchRes.results).toEqual([{ opId: 'wl-1', status: 'ok' }]);

    const state = await usersService.getSyncState(guestUserId, '');
    expect(state.watchLater.map((w: any) => w.video.id)).toContain(videoAId);
    expect(state.playlists).toHaveLength(1);
    expect(state.playlists[0].id).toBe(clientPlaylistId);
    expect(state.playlists[0].videos.map((v) => v.id)).toEqual([
      videoCId,
      videoBId,
    ]);

    // 8. Soft-delete playlist and verify tombstone in getSyncState
    const delRes = await playlistsService.deletePlaylist(
      guestUserId,
      clientPlaylistId,
      Date.now(),
    );
    expect(delRes).toEqual({ status: 'deleted', id: clientPlaylistId });

    const stateAfterDelete = await usersService.getSyncState(guestUserId, '');
    expect(stateAfterDelete.playlists).toHaveLength(0);
    expect(stateAfterDelete.playlistTombstones[clientPlaylistId]).toBeGreaterThan(
      0,
    );
  });
});
