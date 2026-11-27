import { ValidationPipe } from '@nestjs/common';
import { UsersController } from './users.controller';
import {
  AddPlaylistItemDto,
  CreatePlaylistDto,
  DeletePlaylistDto,
  ReorderPlaylistItemsDto,
  UpdatePlaylistDto,
} from './dto/playlist.dto';

describe('UsersController (playlists & DTO validation)', () => {
  let controller: UsersController;
  let usersService: any;
  let userPlaylistsService: any;

  const authedUser = {
    userId: 'u1',
    email: 'u1@example.com',
    role: 'USER',
    isGuest: false,
  };

  beforeEach(() => {
    usersService = {
      getSyncState: jest.fn(),
    };
    userPlaylistsService = {
      listPlaylists: jest.fn().mockResolvedValue([]),
      getPlaylist: jest.fn().mockResolvedValue({ id: 'pl-1' }),
      createPlaylist: jest.fn().mockResolvedValue({ id: 'pl-1' }),
      updatePlaylist: jest.fn().mockResolvedValue({ id: 'pl-1' }),
      deletePlaylist: jest.fn().mockResolvedValue({ status: 'deleted', id: 'pl-1' }),
      addItem: jest.fn().mockResolvedValue({ id: 'pl-1' }),
      removeItem: jest.fn().mockResolvedValue({ id: 'pl-1' }),
      reorderItems: jest.fn().mockResolvedValue({ id: 'pl-1' }),
    };
    controller = new UsersController(usersService, userPlaylistsService);
  });

  it('delegates all playlist endpoints to UserPlaylistsService', async () => {
    await controller.listPlaylists(authedUser);
    expect(userPlaylistsService.listPlaylists).toHaveBeenCalledWith('u1');

    await controller.getPlaylist(authedUser, 'pl-1');
    expect(userPlaylistsService.getPlaylist).toHaveBeenCalledWith('u1', 'pl-1');

    await controller.createPlaylist(authedUser, { title: 'My List' });
    expect(userPlaylistsService.createPlaylist).toHaveBeenCalledWith(
      { userId: 'u1', email: 'u1@example.com' },
      { title: 'My List' },
    );

    await controller.createPlaylist(
      { ...authedUser, isGuest: true },
      { title: 'Guest List' },
    );
    expect(userPlaylistsService.createPlaylist).toHaveBeenLastCalledWith(
      { userId: 'u1', email: '' },
      { title: 'Guest List' },
    );

    await controller.updatePlaylist(authedUser, 'pl-1', { title: 'Updated' });
    expect(userPlaylistsService.updatePlaylist).toHaveBeenCalledWith('u1', 'pl-1', {
      title: 'Updated',
    });

    await controller.deletePlaylist(authedUser, 'pl-1', '5000', undefined);
    expect(userPlaylistsService.deletePlaylist).toHaveBeenCalledWith(
      'u1',
      'pl-1',
      '5000',
    );

    await controller.deletePlaylist(authedUser, 'pl-1', undefined, {
      clientUpdatedAt: 6000,
    });
    expect(userPlaylistsService.deletePlaylist).toHaveBeenLastCalledWith(
      'u1',
      'pl-1',
      6000,
    );

    await controller.addPlaylistItem(authedUser, 'pl-1', {
      videoId: 'vid-1',
      position: 0,
    });
    expect(userPlaylistsService.addItem).toHaveBeenCalledWith('u1', 'pl-1', {
      videoId: 'vid-1',
      position: 0,
    });

    await controller.removePlaylistItem(authedUser, 'pl-1', 'vid-1');
    expect(userPlaylistsService.removeItem).toHaveBeenCalledWith(
      'u1',
      'pl-1',
      'vid-1',
    );

    await controller.reorderPlaylistItems(authedUser, 'pl-1', {
      videoIds: ['vid-2', 'vid-1'],
    });
    expect(userPlaylistsService.reorderItems).toHaveBeenCalledWith('u1', 'pl-1', {
      videoIds: ['vid-2', 'vid-1'],
    });
  });

  it('preserves all DTO fields under NestJS global ValidationPipe (whitelist + transform)', async () => {
    const pipe = new ValidationPipe({ whitelist: true, transform: true });

    const created = await pipe.transform(
      {
        id: 'pl-1',
        title: 'Sermons',
        description: 'Weekly',
        clientUpdatedAt: 123456,
        unknownField: 'strip-me',
      },
      { type: 'body', metatype: CreatePlaylistDto },
    );
    expect(created).toEqual({
      id: 'pl-1',
      title: 'Sermons',
      description: 'Weekly',
      clientUpdatedAt: 123456,
    });

    const updated = await pipe.transform(
      { title: 'Renamed', description: null, clientUpdatedAt: '2026-11-27T00:00:00Z' },
      { type: 'body', metatype: UpdatePlaylistDto },
    );
    expect(updated).toEqual({
      title: 'Renamed',
      description: null,
      clientUpdatedAt: '2026-11-27T00:00:00Z',
    });

    const added = await pipe.transform(
      { videoId: 'vid-1', position: 2, clientUpdatedAt: 9999 },
      { type: 'body', metatype: AddPlaylistItemDto },
    );
    expect(added).toEqual({
      videoId: 'vid-1',
      position: 2,
      clientUpdatedAt: 9999,
    });

    const reordered = await pipe.transform(
      { videoIds: ['vid-2', 'vid-1'], clientUpdatedAt: 9999 },
      { type: 'body', metatype: ReorderPlaylistItemsDto },
    );
    expect(reordered).toEqual({
      videoIds: ['vid-2', 'vid-1'],
      clientUpdatedAt: 9999,
    });

    const deleted = await pipe.transform(
      { clientUpdatedAt: 7777 },
      { type: 'body', metatype: DeletePlaylistDto },
    );
    expect(deleted).toEqual({ clientUpdatedAt: 7777 });
  });
});
