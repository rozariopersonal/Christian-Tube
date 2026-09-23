import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/api/api_client.dart';
import 'package:mobile/features/shorts/services/community_shorts_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Intercepts outbound requests, records them, and replays canned JSON bodies
/// in order (one response body per request, `[]` when exhausted).
class RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  RecordingAdapter(this.responses);

  final List<String> responses;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final body = responses.isNotEmpty ? responses.removeAt(0) : '[]';
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _short(String id, String channelId) => {
      'id': id,
      'title': 'Short $id',
      'videoUrl': 'https://www.youtube.com/shorts/$id',
      'duration': '0:45',
      'type': 'SHORT',
      'channelId': channelId,
      'channelTitle': 'Creator $channelId',
      'publishedAt': '2026-01-01T00:00:00.000Z',
      'viewCount': 1,
    };

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late RecordingAdapter adapter;
  late ApiClient apiClient;

  CommunityShortsController buildController({List<String>? responses}) {
    adapter = RecordingAdapter(responses ?? []);
    apiClient = ApiClient();
    apiClient.dio.httpClientAdapter = adapter;
    return CommunityShortsController(apiClient: apiClient);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CommunityShortsController subscriptions filter', () {
    test('fetchShorts queries all shorts when not signed in', () async {
      final controller =
          buildController(responses: ['[${jsonEncode(_short('s1', 'c1'))}]']);
      await _settle();

      await controller.fetchShorts();

      expect(adapter.requests, hasLength(1));
      final params = adapter.requests.single.queryParameters;
      expect(params['type'], 'SHORT');
      expect(params['channelIds'], isNull);
      expect(controller.shorts, hasLength(1));
    });

    test('no filter request when signed out even with subscriptions', () async {
      final controller = buildController(responses: []);
      await _settle();

      await controller.updateSubscriptionContext(
        isAuthenticated: false,
        subscribedChannelIds: {'enA'},
      );

      // Effective mode is unchanged (all → all), so no refetch happens.
      expect(adapter.requests, isEmpty);
    });

    test('fetchShorts filters to subscribed channels only', () async {
      final controller = buildController(responses: ['[]']);
      await _settle();

      await controller.updateSubscriptionContext(
        isAuthenticated: true,
        subscribedChannelIds: {'enA'},
      );

      expect(adapter.requests, hasLength(1));
      final ids =
          adapter.requests.single.queryParameters['channelIds'] as String;
      expect(ids.split(','), ['enA']);
    });

    test('loadMoreShorts keeps the active subscriptions filter', () async {
      final controller = buildController(responses: [
        '[${jsonEncode(_short('s1', 'enA'))}]',
        '[${jsonEncode(_short('s2', 'enB'))}]',
      ]);
      await _settle();

      await controller.updateSubscriptionContext(
        isAuthenticated: true,
        subscribedChannelIds: {'enA'},
      );
      expect(controller.shorts, hasLength(1));
      final firstIds =
          adapter.requests[0].queryParameters['channelIds'] as String;

      await controller.loadMoreShorts();

      expect(adapter.requests, hasLength(2));
      final secondIds =
          adapter.requests[1].queryParameters['channelIds'] as String;
      expect(secondIds, firstIds);
      expect(controller.shorts, hasLength(2));
    });

    test('switching to signed-in mode resets and avoids stale all cache', () async {
      SharedPreferences.setMockInitialValues({
        'ct_cached_community_shorts':
            jsonEncode([_short('cached', 'x')]),
      });
      final controller = buildController(responses: ['[]']);
      await _settle();

      // Constructed signed-out: the "all" cache fills the feed instantly.
      expect(controller.activeCacheKey, 'ct_cached_community_shorts');
      expect(controller.shorts, hasLength(1));

      await controller.updateSubscriptionContext(
        isAuthenticated: true,
        subscribedChannelIds: {'enA'},
      );

      // Feed cleared, filter-scoped cache loaded (none), then refetched —
      // never the stale "all" snapshot.
      expect(controller.shorts, isEmpty);
      expect(controller.activeCacheKey,
          startsWith('ct_cached_community_shorts_sub_'));
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.queryParameters['channelIds'],
          isNotNull);
    });

    test('activeCacheKey is scoped by the active filter', () async {
      final controller = buildController(responses: ['[]', '[]']);
      await _settle();
      expect(controller.activeCacheKey, 'ct_cached_community_shorts');

      await controller.updateSubscriptionContext(
        isAuthenticated: true,
        subscribedChannelIds: {'enA'},
      );
      final filteredKey = controller.activeCacheKey;
      expect(filteredKey, startsWith('ct_cached_community_shorts_sub_'));
      expect(filteredKey, isNot('ct_cached_community_shorts'));

      await controller.updateSubscriptionContext(
        isAuthenticated: false,
        subscribedChannelIds: {},
      );
      expect(controller.activeCacheKey, 'ct_cached_community_shorts');
    });

    test('subscription change recomputes candidates and refetches', () async {
      final controller = buildController(responses: ['[]', '[]']);
      await _settle();

      await controller.updateSubscriptionContext(
        isAuthenticated: true,
        subscribedChannelIds: {'enA'},
      );
      final first = adapter.requests[0].queryParameters['channelIds'] as String;
      expect(first.split(','), ['enA']);

      await controller.updateSubscriptionContext(
        isAuthenticated: true,
        subscribedChannelIds: {'enA', 'taC'},
      );
      final second =
          adapter.requests[1].queryParameters['channelIds'] as String;
      expect(second.split(','), containsAll(['enA', 'taC']));
      expect(second, isNot(first));
    });

    test('signing out switches back to the all-shorts feed', () async {
      final controller = buildController(responses: ['[]', '[]']);
      await _settle();

      await controller.updateSubscriptionContext(
        isAuthenticated: true,
        subscribedChannelIds: {'enA'},
      );
      expect(adapter.requests[0].queryParameters['channelIds'], isNotNull);

      await controller.updateSubscriptionContext(
        isAuthenticated: false,
        subscribedChannelIds: {'enA'},
      );
      expect(controller.activeCacheKey, 'ct_cached_community_shorts');
      expect(adapter.requests[1].queryParameters['channelIds'], isNull);
    });
  });
}