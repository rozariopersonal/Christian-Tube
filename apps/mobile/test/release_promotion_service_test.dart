import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/admin/services/release_promotion_service.dart';

class MockHttpClientAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) _handler;

  MockHttpClientAdapter(this._handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('ReleasePromotionService Tests', () {
    test('fetchStatus parses json and returns PromotionStatus', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockHttpClientAdapter((options) async {
        if (options.path == '/admin/releases/status') {
          final jsonMap = {
            'aheadCount': 3,
            'isBuilding': false,
            'canPromote': true,
            'latestProductionTag': 'v1.0.0',
            'commits': [
              {
                'sha': 'abcdef1',
                'message': 'feat: cool feature',
                'author': 'Tester',
              }
            ],
          };
          return ResponseBody.fromString(
            jsonEncode(jsonMap),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString('Not Found', 404);
      });

      final service = ReleasePromotionService(dio: dio);
      final status = await service.fetchStatus();

      expect(status.aheadCount, 3);
      expect(status.isBuilding, isFalse);
      expect(status.canPromote, isTrue);
      expect(status.latestProductionTag, 'v1.0.0');
      expect(status.commits.length, 1);
      expect(status.commits.first.sha, 'abcdef1');
      expect(status.commits.first.message, 'feat: cool feature');
      expect(status.commits.first.author, 'Tester');
    });

    test('fetchStatus handles error response properly', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockHttpClientAdapter((options) async {
        return ResponseBody.fromString(
          jsonEncode({'message': 'Unauthorized access'}),
          403,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final service = ReleasePromotionService(dio: dio);
      expect(
        () => service.fetchStatus(),
        throwsA(predicate((e) => e.toString().contains('Unauthorized access'))),
      );
    });

    test('promoteToProduction returns success message on 200', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockHttpClientAdapter((options) async {
        if (options.path == '/admin/releases/promote') {
          return ResponseBody.fromString(
            jsonEncode({
              'message': 'Successfully promoted develop to main! Workflow dispatched.'
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString('Not Found', 404);
      });

      final service = ReleasePromotionService(dio: dio);
      final msg = await service.promoteToProduction();

      expect(msg, 'Successfully promoted develop to main! Workflow dispatched.');
    });

    test('promoteToProduction throws exception when release is locked/in progress', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockHttpClientAdapter((options) async {
        return ResponseBody.fromString(
          jsonEncode({
            'message': 'Cannot promote: A production release workflow is already in progress'
          }),
          409,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final service = ReleasePromotionService(dio: dio);
      expect(
        () => service.promoteToProduction(),
        throwsA(predicate((e) => e.toString().contains('A production release workflow is already in progress'))),
      );
    });
  });
}
