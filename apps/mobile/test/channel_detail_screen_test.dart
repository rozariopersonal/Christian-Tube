import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models/video.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/channels/channel_detail_screen.dart';
import 'package:mobile/features/channels/channel_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);
  final ResponseBody Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

Video _makeVideo({
  required String id,
  String? type = 'VIDEO',
  String? duration = '45:00',
  bool isLive = false,
}) {
  return Video(
    id: id,
    title: 'Title $id',
    description: '',
    thumbnailUrl: '',
    channelId: 'UC1',
    channelTitle: 'Grace Church',
    publishedAt: DateTime(2026, 1, 1),
    duration: duration,
    viewCount: 0,
    isLive: isLive,
    type: type,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('partitionChannelVideos', () {
    test('keeps 1-hour+ sermons in videos and partitions shorts & live streams exclusively', () {
      final result = partitionChannelVideos([
        _makeVideo(id: 'v_short_sermon', duration: '35:10'),
        _makeVideo(id: 'v_one_hour', duration: '1:15:00'),
        _makeVideo(id: 'v_two_hour', duration: '2:05:30'),
        _makeVideo(id: 's_1', type: 'SHORT', duration: '0:45'),
        _makeVideo(id: 's_lower', type: 'short', duration: '0:30'),
        _makeVideo(id: 'live_flag', isLive: true, duration: '1:10:00'),
        _makeVideo(id: 'live_dur', isLive: false, duration: 'Live'),
        _makeVideo(id: 'null_type', type: null, duration: '1:02:00'),
      ]);

      expect(
        result.videos.map((v) => v.id),
        unorderedEquals(['v_short_sermon', 'v_one_hour', 'v_two_hour', 'null_type']),
      );
      expect(
        result.shorts.map((v) => v.id),
        unorderedEquals(['s_1', 's_lower']),
      );
      expect(
        result.streams.map((v) => v.id),
        unorderedEquals(['live_flag', 'live_dur']),
      );
    });
  });

  group('ChannelDetailScreen widget states', () {
    Dio buildDio(ResponseBody Function(RequestOptions) handler) =>
        Dio(BaseOptions(baseUrl: 'http://localhost:3000'))
          ..httpClientAdapter = _StubAdapter(handler);

    Widget wrap(Widget child, Size size) => MediaQuery(
          data: MediaQueryData(size: size),
          child: MaterialApp(
            theme: ThemeData.light().copyWith(extensions: const [AppTokens.light]),
            home: child,
          ),
        );

    testWidgets('shows Channel not found and Retry when fetch returns 404',
        (tester) async {
      final dio = buildDio((opts) => throw DioException.badResponse(
            requestOptions: opts,
            statusCode: 404,
            response: Response(requestOptions: opts, statusCode: 404),
          ));
      final channelService = ChannelService.forTesting(dio: dio);

      await tester.pumpWidget(
        wrap(
          ChannelDetailScreen(
            channelId: 'missing',
            channelService: channelService,
            dio: dio,
          ),
          const Size(360, 800),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Channel not found'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final width in [320.0, 600.0, 840.0, 1400.0]) {
      testWidgets(
        'renders loaded channel without fabricated @handle or overflow at ${width.toInt()}dp',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final dio = buildDio((opts) {
            if (opts.path.contains('/videos')) {
              return ResponseBody.fromString('[]', 200, headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              });
            }
            return ResponseBody.fromString(
              jsonEncode({
                'id': 'UC1',
                'name': 'Grace Church',
                'description': 'Biblical teaching',
                'subscriberCount': 12500,
                'videoCount': 42,
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          });
          final channelService = ChannelService.forTesting(dio: dio);

          await tester.pumpWidget(
            wrap(
              ChannelDetailScreen(
                channelId: 'UC1',
                channelService: channelService,
                dio: dio,
              ),
              Size(width, 800),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('Grace Church'), findsOneWidget);
          expect(find.textContaining('@gracechurch'), findsNothing);
          expect(find.textContaining('42 videos'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
