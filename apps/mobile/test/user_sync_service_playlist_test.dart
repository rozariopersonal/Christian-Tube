import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/user_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingAdapter implements HttpClientAdapter {
  final List<String> calls = [];
  final int Function(RequestOptions options)? statusOverride;

  _RecordingAdapter({this.statusOverride});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add('${options.method} ${options.path}');
    final status = statusOverride?.call(options) ?? 200;
    return ResponseBody.fromString(
      jsonEncode({'ok': status < 400}),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('flushes playlist_op entries strictly FIFO across all 6 op types', () async {
    final adapter = _RecordingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final sync = UserSyncService.forTesting(dio: dio, canSyncCheck: () => false);
    sync.setActiveUserForTesting('u1');

    await sync.enqueuePlaylistOp(
      opType: 'create',
      playlistId: 'p1',
      payload: {'title': 'My List', 'description': 'Desc'},
    );
    await sync.enqueuePlaylistOp(
      opType: 'add_item',
      playlistId: 'p1',
      payload: {'videoId': 'v1'},
    );
    await sync.enqueuePlaylistOp(
      opType: 'reorder',
      playlistId: 'p1',
      payload: {'videoIds': ['v1']},
    );
    await sync.enqueuePlaylistOp(
      opType: 'update',
      playlistId: 'p1',
      payload: {'title': 'Renamed'},
    );
    await sync.enqueuePlaylistOp(
      opType: 'remove_item',
      playlistId: 'p1',
      payload: {'videoId': 'v1'},
    );
    await sync.enqueuePlaylistOp(
      opType: 'delete',
      playlistId: 'p1',
    );

    expect(sync.hasPendingPlaylistOps('p1'), isTrue);

    // Enable sync via a second instance reading the same SharedPreferences
    final flushingSync = UserSyncService.forTesting(dio: dio, canSyncCheck: () => true);
    flushingSync.setActiveUserForTesting('u1');
    await flushingSync.flushOutbox();

    expect(adapter.calls, [
      'POST /api/user/playlists',
      'POST /api/user/playlists/p1/items',
      'PUT /api/user/playlists/p1/items/reorder',
      'PATCH /api/user/playlists/p1',
      'DELETE /api/user/playlists/p1/items/v1',
      'DELETE /api/user/playlists/p1',
    ]);
    expect(flushingSync.hasPendingPlaylistOps('p1'), isFalse);
  });

  test('stops FIFO loop on transient 500 error and retains failing + subsequent ops', () async {
    final adapter = _RecordingAdapter(
      statusOverride: (opts) => opts.path.endsWith('/items') ? 503 : 200,
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final sync = UserSyncService.forTesting(dio: dio, canSyncCheck: () => false);
    sync.setActiveUserForTesting('u1');

    await sync.enqueuePlaylistOp(opType: 'create', playlistId: 'p1', payload: {'title': 'A'});
    await sync.enqueuePlaylistOp(opType: 'add_item', playlistId: 'p1', payload: {'videoId': 'v1'});
    await sync.enqueuePlaylistOp(opType: 'update', playlistId: 'p1', payload: {'title': 'B'});

    final flushingSync = UserSyncService.forTesting(dio: dio, canSyncCheck: () => true);
    flushingSync.setActiveUserForTesting('u1');
    await flushingSync.flushOutbox();

    // Create succeeded, add_item hit 503 -> stopped before update!
    expect(adapter.calls, [
      'POST /api/user/playlists',
      'POST /api/user/playlists/p1/items',
    ]);
    expect(flushingSync.pendingOps.length, 2);
    expect(flushingSync.hasPendingPlaylistOps('p1'), isTrue);
  });

  test('drops permanent 404/400 op so queue never deadlocks', () async {
    final adapter = _RecordingAdapter(
      statusOverride: (opts) => opts.path.endsWith('/items/v_missing') ? 404 : 200,
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final sync = UserSyncService.forTesting(dio: dio, canSyncCheck: () => false);
    sync.setActiveUserForTesting('u1');

    await sync.enqueuePlaylistOp(
      opType: 'remove_item',
      playlistId: 'p1',
      payload: {'videoId': 'v_missing'},
    );
    await sync.enqueuePlaylistOp(
      opType: 'update',
      playlistId: 'p1',
      payload: {'title': 'Still Runs'},
    );

    final flushingSync = UserSyncService.forTesting(dio: dio, canSyncCheck: () => true);
    flushingSync.setActiveUserForTesting('u1');
    await flushingSync.flushOutbox();

    expect(adapter.calls, [
      'DELETE /api/user/playlists/p1/items/v_missing',
      'PATCH /api/user/playlists/p1',
    ]);
    expect(flushingSync.pendingOps, isEmpty);
  });

  test('clearAllDeviceData wipes playlist and watch later caches', () async {
    final dio = Dio()..httpClientAdapter = _RecordingAdapter();
    final sync = UserSyncService.forTesting(dio: dio, canSyncCheck: () => false);

    await sync.onUserChanged('signed_1');
    await sync.enqueuePlaylistOp(opType: 'create', playlistId: 'p1', payload: {'title': 'My List'});
    await sync.enqueuePlaylistOp(opType: 'add_item', playlistId: 'p1', payload: {'videoId': 'v1'});
    expect(sync.pendingOps.values.map((o) => o.itemType).toList(), ['create', 'add_item']);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('watch_later_v1_signed_1', '[]');
    await prefs.setString('playlists_v1_signed_1', '[]');

    await sync.clearAllDeviceData();
    expect(prefs.getString('watch_later_v1_signed_1'), isNull);
    expect(prefs.getString('playlists_v1_signed_1'), isNull);
  });
}
