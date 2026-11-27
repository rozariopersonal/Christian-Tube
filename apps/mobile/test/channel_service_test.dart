import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/channel_request.dart';
import 'package:mobile/core/services/user_preference_service.dart';
import 'package:mobile/core/services/user_sync_service.dart';
import 'package:mobile/features/auth/auth_service.dart';
import 'package:mobile/features/channels/channel_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [HttpClientAdapter] stub that never touches the network. It records outbound
/// requests and lets the test control the response per request.
class StubAdapter implements HttpClientAdapter {
  StubAdapter({this.onFetch, this.fail = false});

  final List<RequestOptions> requests = [];
  ResponseBody Function(RequestOptions options)? onFetch;
  bool fail;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (fail) {
      throw DioException.connectionError(requestOptions: options, reason: 'offline');
    }
    if (onFetch != null) {
      return onFetch!(options);
    }
    return ResponseBody.fromString('{}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// Control auth without exercising Google Sign-In.
class StubAuth extends AuthService {
  StubAuth(this._authenticated) : super();

  final bool _authenticated;

  @override
  bool get isAuthenticated => _authenticated;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Dio testDio(StubAdapter adapter) =>
      Dio(BaseOptions(baseUrl: 'http://localhost:3000'))
        ..httpClientAdapter = adapter;

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  test('guest toggleSubscribe is device-local and makes no network calls', () async {
    final adapter = StubAdapter();
    final service = ChannelService.forTesting(dio: testDio(adapter));

    service.toggleSubscribe('c1');
    await settle();

    expect(service.subscribedChannelIds, contains('c1'));
    expect(adapter.requests, isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('subscribed_channel_ids'), contains('c1'));
  });

  test('authenticated toggleSubscribe subscribes via POST to the backend', () async {
    final adapter = StubAdapter();
    final dio = testDio(adapter);
    final syncService = UserSyncService.forTesting(dio: dio)
      ..setActiveUserForTesting('u1');
    final service = ChannelService.forTesting(
      dio: dio,
      authService: StubAuth(true),
      syncService: syncService,
    );

    service.toggleSubscribe('c1');
    await settle();

    expect(service.subscribedChannelIds, contains('c1'));
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.first.method, 'POST');
    expect(adapter.requests.first.path, '/api/channels/c1/subscribe');
  });

  test('successful follow and unfollow update the cached server snapshot', () async {
    final adapter = StubAdapter(onFetch: (request) {
      final body = request.path == '/api/user/state'
          ? {'subscriptions': <String>[]}
          : {};
      return ResponseBody.fromString(jsonEncode(body), 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
    });
    final dio = testDio(adapter);
    final sync = UserSyncService.forTesting(dio: dio)
      ..setActiveUserForTesting('u1');
    final service = ChannelService.forTesting(
      dio: dio,
      authService: StubAuth(true),
      syncService: sync,
    );
    addTearDown(service.dispose);
    await sync.pullAndFlush(force: true);

    service.toggleFollow('c1');
    await settle();
    expect(sync.pendingOps, isEmpty);
    expect(sync.remoteState?['subscriptions'], ['c1']);
    expect(service.followedChannelIds, {'c1'});

    service.toggleFollow('c1');
    await settle();
    expect(sync.pendingOps, isEmpty);
    expect(sync.remoteState?['subscriptions'], isEmpty);
    expect(service.followedChannelIds, isEmpty);
  });

  test('onboarding selection persists additions and removes cleared follows', () async {
    final adapter = StubAdapter();
    final service = ChannelService.forTesting(dio: testDio(adapter));
    addTearDown(service.dispose);
    service.seedSubscribedIds({'old'});
    await service.saveChannelSelections({'old'}, {'video', 'shorts'});
    expect(service.followedChannelIds, {'video', 'shorts'});

    final restored = ChannelService.forTesting(dio: testDio(adapter));
    addTearDown(restored.dispose);
    await restored.loadFollowing();
    expect(restored.followedChannelIds, {'video', 'shorts'});
  });

  test('overlapping onboarding writes retain every pending field and channel', () async {
    final sync = UserSyncService.forTesting(dio: testDio(StubAdapter(fail: true)))
      ..setActiveUserForTesting('onboarding-user');
    await Future.wait([
      sync.enqueuePreferences({
        'videoChannelIds': ['video'],
        'shortsChannelIds': <String>[],
      }),
      sync.enqueueSubscriptions({'video': true, 'old': false}),
      sync.enqueuePreference('hasCompletedOnboarding', true),
    ]);

    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(
      prefs.getString('mobile_sync_pending_v2_onboarding-user')!,
    ) as Map<String, dynamic>;
    expect(saved.keys, unorderedEquals([
      'pref:videoChannelIds',
      'pref:shortsChannelIds',
      'sub:video',
      'sub:old',
      'pref:hasCompletedOnboarding',
    ]));
  });

  test('authenticated second toggle unsubscribes via DELETE to the backend', () async {
    final adapter = StubAdapter();
    final dio = testDio(adapter);
    final syncService = UserSyncService.forTesting(dio: dio)
      ..setActiveUserForTesting('u1');
    final service = ChannelService.forTesting(
      dio: dio,
      authService: StubAuth(true),
      syncService: syncService,
    );

    service.toggleSubscribe('c1');
    await settle();
    service.toggleSubscribe('c1');
    await settle();

    expect(service.subscribedChannelIds, isEmpty);
    expect(adapter.requests, hasLength(2));
    expect(adapter.requests[1].method, 'DELETE');
    expect(adapter.requests[1].path, '/api/channels/c1/subscribe');
  });

  test('authenticated toggle keeps optimistic state in outbox when the backend sync fails', () async {
    final adapter = StubAdapter(fail: true);
    final dio = testDio(adapter);
    final syncService = UserSyncService.forTesting(dio: dio)
      ..setActiveUserForTesting('u1');
    final service = ChannelService.forTesting(
      dio: dio,
      authService: StubAuth(true),
      syncService: syncService,
    );

    service.toggleSubscribe('c1');
    await settle();

    expect(service.subscribedChannelIds, contains('c1'));
    expect(syncService.pendingOps.containsKey('sub:c1'), isTrue);
  });

  test('authenticated loadSubscriptions pulls the authoritative list from the backend', () async {
    final adapter = StubAdapter(
      onFetch: (_) => ResponseBody.fromString(
        jsonEncode({
          'channelIds': ['c1', 'c2'],
          'channels': [
            {'id': 'c1', 'name': 'Channel One'},
            {'id': 'c2', 'name': 'Channel Two'},
          ],
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    );
    final service = ChannelService.forTesting(
      dio: testDio(adapter),
      authService: StubAuth(true),
    );

    await service.loadSubscriptions();

    expect(service.subscribedChannelIds, {'c1', 'c2'});
    expect(service.subscribedChannelNames, {'Channel One', 'Channel Two'});
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.first.path, '/api/channels/subscriptions');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('subscribed_channel_ids'), containsAll(['c1', 'c2']));
    expect(prefs.getString('subscribed_channel_names'), contains('Channel One'));
  });

  test('signed-out loadSubscriptions falls back to local preferences', () async {
    SharedPreferences.setMockInitialValues({
      'subscribed_channel_ids': ['c1'],
      'subscribed_channel_names':
          '{"c1":"Channel One","c2":"Stale Channel"}',
    });
    final adapter = StubAdapter();
    final service = ChannelService.forTesting(dio: testDio(adapter));

    await service.loadSubscriptions();

    expect(service.subscribedChannelIds, {'c1'});
    // Only the subscribed id's name surfaces; the stale entry is ignored.
    expect(service.subscribedChannelNames, {'Channel One'});
    expect(adapter.requests, isEmpty);
  });

  test('guest subscriptions persist channel names across reloads', () async {
    final adapter = StubAdapter(
      onFetch: (_) => ResponseBody.fromString(
        jsonEncode([
          {'id': 'c1', 'name': 'Channel One'},
        ]),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    );
    final service = ChannelService.forTesting(dio: testDio(adapter));

    await service.fetchChannels();
    expect(service.channels, hasLength(1));

    service.toggleSubscribe('c1');
    await settle();
    expect(service.subscribedChannelNames, {'Channel One'});

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('subscribed_channel_names'), contains('Channel One'));

    // A fresh service reads the persisted names back without any network call.
    final second = ChannelService.forTesting(dio: testDio(StubAdapter()));
    await second.loadSubscriptions();
    expect(second.subscribedChannelNames, {'Channel One'});

    // Unsubscribing drops the name too.
    second.toggleSubscribe('c1');
    await settle();
    expect(second.subscribedChannelNames, isEmpty);
  });

  group('addChannel', () {
    ResponseBody jsonResponse(String body, int status) => ResponseBody.fromString(
          body,
          status,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );

    DioException serverError(RequestOptions options, int status) =>
        DioException.badResponse(
          requestOptions: options,
          statusCode: status,
          response: Response(requestOptions: options, statusCode: status),
        );

    test('returns true and refetches when /api/channels accepts the channel', () async {
      final adapter = StubAdapter(
        onFetch: (options) {
          if (options.method == 'GET') {
            return jsonResponse(jsonEncode([
              {'id': 'UC1', 'name': 'New Channel', 'isActive': true},
            ]), 200);
          }
          return jsonResponse(
            jsonEncode({'status': 'success'}),
            201,
          );
        },
      );
      final service = ChannelService.forTesting(dio: testDio(adapter));

      final ok = await service.addChannel(channelUrl: 'https://youtube.com/@test');

      expect(ok, isTrue);
      expect(service.channels.map((c) => c.id), contains('UC1'));
      expect(adapter.requests, hasLength(2));
    });

    test('falls back to /channels when the /api/channels POST errors', () async {
      final adapter = StubAdapter(
        onFetch: (options) {
          if (options.method == 'POST' && options.path == '/api/channels') {
            throw serverError(options, 500);
          }
          if (options.method == 'GET') {
            return jsonResponse('[]', 200);
          }
          return jsonResponse(
            jsonEncode({'status': 'success'}),
            200,
          );
        },
      );
      final service = ChannelService.forTesting(dio: testDio(adapter));

      final ok = await service.addChannel(channelUrl: '@test');

      expect(ok, isTrue);
      final postedPaths = adapter.requests
          .where((r) => r.method == 'POST')
          .map((r) => r.path)
          .toList();
      expect(postedPaths, ['/api/channels', '/channels']);
    });

    test('returns false when both POST routes reject the channel', () async {
      final adapter = StubAdapter(
        onFetch: (options) {
          if (options.method == 'POST') {
            throw serverError(options, 403);
          }
          return jsonResponse('[]', 200);
        },
      );
      final service = ChannelService.forTesting(dio: testDio(adapter));

      final ok = await service.addChannel(channelUrl: '@test');

      expect(ok, isFalse);
      expect(service.channels, isEmpty);
    });

    test('shortsChannels filters to only channels with hasShorts true', () async {
      final adapter = StubAdapter(
        onFetch: (options) {
          if (options.path.contains('/channels')) {
            return jsonResponse(
              jsonEncode([
                {
                  'id': 'c1',
                  'title': 'Long Sermons Only',
                  'avatarUrl': 'https://example.com/1.png',
                  'hasShorts': false,
                },
                {
                  'id': 'c2',
                  'title': 'Short Devotionals Channel',
                  'avatarUrl': 'https://example.com/2.png',
                  'hasShorts': true,
                },
              ]),
              200,
            );
          }
          return jsonResponse('{}', 200);
        },
      );
      final service = ChannelService.forTesting(dio: testDio(adapter));
      await service.fetchChannels();

      expect(service.channels, hasLength(2));
      expect(service.shortsChannels, hasLength(1));
      expect(service.shortsChannels.first.id, 'c2');
      expect(service.shortsChannels.first.hasShorts, isTrue);
    });

    test('seedSubscribedIds merges new channels and notifies listeners', () async {
      final adapter = StubAdapter();
      final service = ChannelService.forTesting(dio: testDio(adapter));
      int notifyCount = 0;
      service.addListener(() => notifyCount++);

      service.seedSubscribedIds({'c1', 'c2'});
      expect(service.subscribedChannelIds, {'c1', 'c2'});
      expect(notifyCount, 1);

      // Calling with existing IDs does not trigger another notification
      service.seedSubscribedIds({'c1'});
      expect(notifyCount, 1);
    });

    test('toggleSubscribe syncs follow state to UserPreference', () async {
      final adapter = StubAdapter();
      final service = ChannelService.forTesting(dio: testDio(adapter));

      service.toggleSubscribe('c1');
      await settle();

      final pref = UserPreferenceService.instance.preferences;
      expect(pref.videoChannelIds, contains('c1'));
      expect(pref.shortsChannelIds, contains('c1'));

      service.toggleSubscribe('c1');
      await settle();

      final updatedPref = UserPreferenceService.instance.preferences;
      expect(updatedPref.videoChannelIds, isNot(contains('c1')));
      expect(updatedPref.shortsChannelIds, isNot(contains('c1')));
    });

    test('loadSubscriptions merges backend IDs with existing local IDs without wiping them', () async {
      final adapter = StubAdapter();
      adapter.onFetch = (options) {
        if (options.path.contains('/subscriptions')) {
          return ResponseBody.fromString(
            jsonEncode({'channelIds': ['backend_c1']}),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString('{}', 200, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        });
      };

      final auth = StubAuth(true);
      final dio = testDio(adapter);
      final syncService = UserSyncService.forTesting(dio: dio)
        ..setActiveUserForTesting('u1');
      final service = ChannelService.forTesting(
        dio: dio,
        authService: auth,
        syncService: syncService,
      );

      service.seedSubscribedIds({'local_c1'});
      expect(service.subscribedChannelIds, {'local_c1'});

      await service.loadSubscriptions();
      expect(service.subscribedChannelIds, containsAll(['local_c1', 'backend_c1']));
    });
  });

  group('channel requests & search', () {
    ResponseBody jsonResponse(String body, int status) => ResponseBody.fromString(
          body,
          status,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );

    test('submitChannelRequest posts to /api/channels/request and skips fetchRequests for non-admins', () async {
      final adapter = StubAdapter(
        onFetch: (options) => jsonResponse(jsonEncode({'id': 'req_1'}), 201),
      );
      final service = ChannelService.forTesting(
        dio: testDio(adapter),
        authService: StubAuth(true),
      );

      final ok = await service.submitChannelRequest(
        ChannelRequest(
          channelUrl: '@GraceTV',
          channelName: 'Grace TV',
          language: 'en',
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      expect(ok, isTrue);
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.first.path, '/api/channels/request');
    });

    test('submitChannelRequest does not retry /channels/request on 409 Conflict and exposes server message', () async {
      final adapter = StubAdapter(
        onFetch: (options) {
          throw DioException.badResponse(
            requestOptions: options,
            statusCode: 409,
            response: Response(
              requestOptions: options,
              statusCode: 409,
              data: {'message': 'A pending request for this channel already exists.'},
            ),
          );
        },
      );
      final service = ChannelService.forTesting(
        dio: testDio(adapter),
        authService: StubAuth(true),
      );

      final ok = await service.submitChannelRequest(
        ChannelRequest(
          channelUrl: '@GraceTV',
          channelName: 'Grace TV',
          language: 'en',
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      expect(ok, isFalse);
      expect(adapter.requests, hasLength(1));
      expect(
        service.lastRequestError,
        'A pending request for this channel already exists.',
      );
    });

    test('fetchRequests skips network call for non-admins', () async {
      final adapter = StubAdapter();
      final service = ChannelService.forTesting(
        dio: testDio(adapter),
        authService: StubAuth(false),
      );

      await service.fetchRequests();

      expect(adapter.requests, isEmpty);
    });
  });
}