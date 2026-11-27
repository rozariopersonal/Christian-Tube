import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/video.dart';
import 'package:mobile/core/services/user_sync_service.dart';
import 'package:mobile/features/playlists/services/watch_later_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Video _video(String id, {String title = 'Sermon'}) => Video(
      id: id,
      title: title,
      thumbnailUrl: 'https://img.youtube.com/vi/$id/hqdefault.jpg',
      channelId: 'ch1',
      channelTitle: 'Grace Church',
      publishedAt: DateTime(2025, 1, 1),
      duration: '12:30',
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('toggleWatchLater adds, persists per-user, enqueues sync op, and removes', () async {
    final sync = UserSyncService.forTesting(
      dio: Dio(),
      canSyncCheck: () => false,
    );
    sync.setActiveUserForTesting('user_a');

    final service = WatchLaterService.forTesting(
      syncService: sync,
      userId: 'user_a',
    );
    await service.init();

    expect(service.count, 0);
    expect(service.isWatchLater('v1'), isFalse);

    final added = await service.toggleWatchLater(_video('v1', title: 'First'));
    expect(added, isTrue);
    expect(service.count, 1);
    expect(service.isWatchLater('v1'), isTrue);

    // Wait briefly for unawaited enqueueWatchItem
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final addOp = sync.pendingOps['${UserSyncService.watchLaterType}:v1'];
    expect(addOp, isNotNull);
    expect(addOp!.isDeleted, isFalse);

    // Reload in a fresh service instance for same user -> restored from prefs
    final reloaded = WatchLaterService.forTesting(
      syncService: sync,
      userId: 'user_a',
    );
    await reloaded.init();
    expect(reloaded.count, 1);
    expect(reloaded.videos.first.id, 'v1');

    // Different user has isolated storage
    final otherUser = WatchLaterService.forTesting(
      syncService: sync,
      userId: 'user_b',
    );
    await otherUser.init();
    expect(otherUser.count, 0);

    // Toggle off removes and enqueues tombstone
    final afterRemove = await service.toggleWatchLater(_video('v1'));
    expect(afterRemove, isFalse);
    expect(service.count, 0);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final delOp = sync.pendingOps['${UserSyncService.watchLaterType}:v1'];
    expect(delOp, isNotNull);
    expect(delOp!.isDeleted, isTrue);

    service.dispose();
    reloaded.dispose();
    otherUser.dispose();
  });

  test('merges remote watchLater and tombstones while respecting pending ops', () async {
    final sync = UserSyncService.forTesting(
      dio: Dio(),
      canSyncCheck: () => false,
    );
    sync.setActiveUserForTesting('u1');

    final service = WatchLaterService.forTesting(
      syncService: sync,
      userId: 'u1',
    );
    await service.init();

    // Add v_pending locally (pending add op)
    await service.toggleWatchLater(_video('v_pending', title: 'Pending Local'));
    // Remove v_deleted locally (pending delete op)
    await service.removeFromWatchLater('v_deleted');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // Push remote state containing v_remote, v_tombstoned, and v_deleted
    sync.setRemoteStateForTesting({
      'watchLater': [
        {'video': _video('v_remote', title: 'Remote Video').toJson()},
        {'video': _video('v_tombstoned', title: 'Tombstoned').toJson()},
        {'video': _video('v_deleted', title: 'Deleted Locally').toJson()},
      ],
      'watchLaterTombstones': {
        'v_tombstoned': 12345,
      },
    });

    final ids = service.videos.map((v) => v.id).toList();
    expect(ids, ['v_pending', 'v_remote']);

    await service.clearLocalState();
    expect(service.count, 0);

    service.dispose();
  });

  test('migrates pre-auth guest watch later items when real user loads', () async {
    final sync = UserSyncService.forTesting(
      dio: Dio(),
      canSyncCheck: () => false,
    );
    final guestService = WatchLaterService.forTesting(
      syncService: sync,
      userId: 'guest',
    );
    await guestService.init();
    await guestService.toggleWatchLater(_video('v_offline', title: 'Offline Video'));
    guestService.dispose();

    sync.setActiveUserForTesting('u_signed_in');
    final signedInService = WatchLaterService.forTesting(
      syncService: sync,
      userId: 'u_signed_in',
    );
    await signedInService.init();

    expect(signedInService.isWatchLater('v_offline'), isTrue);
    expect(signedInService.count, 1);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('watch_later_v1_guest'), isNull);

    signedInService.dispose();
  });
}
