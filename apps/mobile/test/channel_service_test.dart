import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
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
    final service = ChannelService.forTesting(
      dio: testDio(adapter),
      authService: StubAuth(true),
    );

    service.toggleSubscribe('c1');
    await settle();

    expect(service.subscribedChannelIds, contains('c1'));
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.first.method, 'POST');
    expect(adapter.requests.first.path, '/api/channels/c1/subscribe');
  });

  test('authenticated second toggle unsubscribes via DELETE to the backend', () async {
    final adapter = StubAdapter();
    final service = ChannelService.forTesting(
      dio: testDio(adapter),
      authService: StubAuth(true),
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

  test('authenticated toggle reverts locally when the backend sync fails', () async {
    final adapter = StubAdapter(fail: true);
    final service = ChannelService.forTesting(
      dio: testDio(adapter),
      authService: StubAuth(true),
    );

    service.toggleSubscribe('c1');
    await settle();

    expect(service.subscribedChannelIds, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('subscribed_channel_ids'), isNot(contains('c1')));
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
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.first.path, '/api/channels/subscriptions');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('subscribed_channel_ids'), containsAll(['c1', 'c2']));
  });

  test('signed-out loadSubscriptions falls back to local preferences', () async {
    SharedPreferences.setMockInitialValues({
      'subscribed_channel_ids': ['c1'],
    });
    final adapter = StubAdapter();
    final service = ChannelService.forTesting(dio: testDio(adapter));

    await service.loadSubscriptions();

    expect(service.subscribedChannelIds, {'c1'});
    expect(adapter.requests, isEmpty);
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
  });
}