import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/playlist.dart';
import 'package:mobile/core/models/video.dart';
import 'package:mobile/core/services/user_sync_service.dart';
import 'package:mobile/features/playlists/services/playlist_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Video _video(String id, {String title = 'Sermon'}) => Video(
      id: id,
      title: title,
      thumbnailUrl: 'https://img.youtube.com/vi/$id/hqdefault.jpg',
      channelId: 'ch1',
      channelTitle: 'Grace Church',
      publishedAt: DateTime(2025, 1, 1),
      duration: '10:00',
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Playlist model parses clientUpdatedAt from int and ISO string and supports copyWith', () {
    final fromInt = Playlist.fromJson({
      'id': 'p1',
      'title': 'Favorites',
      'clientUpdatedAt': 1700000000000,
      'items': [
        {'video': _video('v1').toJson()},
      ],
    });
    expect(fromInt.clientUpdatedAt, 1700000000000);
    expect(fromInt.videos.length, 1);
    expect(fromInt.toJson()['clientUpdatedAt'], 1700000000000);

    final fromIso = Playlist.fromJson({
      'id': 'p2',
      'title': 'Study',
      'client_updated_at': '2025-01-01T00:00:00.000Z',
    });
    expect(
      fromIso.clientUpdatedAt,
      DateTime.parse('2025-01-01T00:00:00.000Z').millisecondsSinceEpoch,
    );

    final copied = fromInt.copyWith(title: 'Updated', description: 'Notes');
    expect(copied.title, 'Updated');
    expect(copied.description, 'Notes');
    expect(copied.copyWith(clearDescription: true).description, isNull);
  });

  test('CRUD, add/remove/reorder videos, queries, and per-user persistence', () async {
    final sync = UserSyncService.forTesting(
      dio: Dio(),
      canSyncCheck: () => false,
    );
    sync.setActiveUserForTesting('u1');

    var counter = 0;
    final service = PlaylistService.forTesting(
      syncService: sync,
      userId: 'u1',
      idGenerator: () => 'pl-${++counter}',
    );
    await service.init();

    final created = await service.createPlaylist(
      'Sunday Sermons',
      description: 'Weekly messages',
      initialVideo: _video('v1', title: 'One'),
    );
    expect(created.id, 'pl-1');
    expect(service.playlists.length, 1);
    expect(service.getById('pl-1')?.videos.length, 1);
    expect(service.isVideoInAnyPlaylist('v1'), isTrue);
    expect(service.playlistsContainingVideo('v1').length, 1);

    await service.addVideoToPlaylist('pl-1', _video('v2', title: 'Two'));
    await service.addVideoToPlaylist('pl-1', _video('v3', title: 'Three'));
    expect(service.getById('pl-1')!.videos.map((v) => v.id).toList(), ['v1', 'v2', 'v3']);

    await service.reorderVideos('pl-1', 0, 2);
    expect(service.getById('pl-1')!.videos.map((v) => v.id).toList(), ['v2', 'v3', 'v1']);

    await service.updatePlaylist('pl-1', title: 'Renamed Sermons', description: '');
    expect(service.getById('pl-1')!.title, 'Renamed Sermons');
    expect(service.getById('pl-1')!.description, isNull);

    await service.removeVideoFromPlaylist('pl-1', 'v3');
    expect(service.getById('pl-1')!.videos.map((v) => v.id).toList(), ['v2', 'v1']);

    // Verify persistence
    final reloaded = PlaylistService.forTesting(syncService: sync, userId: 'u1');
    await reloaded.init();
    expect(reloaded.getById('pl-1')?.title, 'Renamed Sermons');
    expect(reloaded.getById('pl-1')?.videos.length, 2);

    await service.deletePlaylist('pl-1');
    expect(service.playlists, isEmpty);
    expect(service.isVideoInAnyPlaylist('v1'), isFalse);

    service.dispose();
    reloaded.dispose();
  });

  test('remoteState merge respects tombstones and preserves playlists with pending ops', () async {
    final sync = UserSyncService.forTesting(
      dio: Dio(),
      canSyncCheck: () => false,
    );
    sync.setActiveUserForTesting('u1');

    final service = PlaylistService.forTesting(
      syncService: sync,
      userId: 'u1',
      idGenerator: () => 'pl-local',
    );
    await service.init();

    // Create local optimistic playlist (has pending op)
    await service.createPlaylist('Local Optimistic');
    // Also enqueue a pending delete for pl-deleted
    await sync.enqueuePlaylistOp(opType: 'delete', playlistId: 'pl-deleted');

    sync.setRemoteStateForTesting({
      'playlists': [
        {
          'id': 'pl-remote',
          'title': 'Remote Playlist',
          'videos': [_video('v9').toJson()],
        },
        {
          'id': 'pl-tombstoned',
          'title': 'Tombstoned',
        },
        {
          'id': 'pl-deleted',
          'title': 'Locally Deleted',
        },
        {
          'id': 'pl-local',
          'title': 'Stale Remote Title',
        },
      ],
      'playlistTombstones': {
        'pl-tombstoned': 99999,
      },
    });

    final ids = service.playlists.map((p) => p.id).toList();
    expect(ids, ['pl-local', 'pl-remote']);
    expect(service.getById('pl-local')?.title, 'Local Optimistic');

    await service.clearLocalState();
    expect(service.playlists, isEmpty);

    service.dispose();
  });

  test('migrates pre-auth guest playlists when real user loads', () async {
    final sync = UserSyncService.forTesting(
      dio: Dio(),
      canSyncCheck: () => false,
    );
    final guestService = PlaylistService.forTesting(
      syncService: sync,
      userId: 'guest',
      idGenerator: () => 'pl-guest-1',
    );
    await guestService.init();
    await guestService.createPlaylist(
      'Offline Playlist',
      description: 'Saved before auth',
      initialVideo: _video('v1'),
    );
    guestService.dispose();

    sync.setActiveUserForTesting('u_signed_in');
    final signedInService = PlaylistService.forTesting(
      syncService: sync,
      userId: 'u_signed_in',
    );
    await signedInService.init();

    expect(signedInService.getById('pl-guest-1')?.title, 'Offline Playlist');
    expect(signedInService.getById('pl-guest-1')?.videos.length, 1);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('playlists_v1_guest'), isNull);

    signedInService.dispose();
  });
}
