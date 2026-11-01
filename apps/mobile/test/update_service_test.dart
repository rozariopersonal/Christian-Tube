import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/update/update_service.dart';

void main() {
  group('UpdateService.isNewerVersion', () {
    test('standard major/minor/patch upgrades', () {
      expect(UpdateService.isNewerVersion('v1.29.0', 'v1.28.0'), isTrue);
      expect(UpdateService.isNewerVersion('1.29.0', '1.28.9'), isTrue);
      expect(UpdateService.isNewerVersion('2.0.0', '1.99.99'), isTrue);
      expect(UpdateService.isNewerVersion('v1.28.1', 'v1.28.0'), isTrue);

      expect(UpdateService.isNewerVersion('v1.28.0', 'v1.29.0'), isFalse);
      expect(UpdateService.isNewerVersion('v1.28.0', 'v1.28.0'), isFalse);
    });

    test('beta pre-release progression', () {
      // beta.2 is newer than beta.1
      expect(UpdateService.isNewerVersion('v1.29.0-beta.2', 'v1.29.0-beta.1'), isTrue);
      expect(UpdateService.isNewerVersion('1.29.0-beta.10', '1.29.0-beta.2'), isTrue);

      // Same or older beta
      expect(UpdateService.isNewerVersion('v1.29.0-beta.1', 'v1.29.0-beta.2'), isFalse);
      expect(UpdateService.isNewerVersion('v1.29.0-beta.1', 'v1.29.0-beta.1'), isFalse);
    });

    test('stable release is newer than any beta with same base version', () {
      // 1.29.0 stable is strictly newer than 1.29.0-beta.5
      expect(UpdateService.isNewerVersion('v1.29.0', 'v1.29.0-beta.5'), isTrue);
      expect(UpdateService.isNewerVersion('1.29.0', '1.29.0-beta.1'), isTrue);

      // 1.29.0-beta.1 is NOT newer than 1.29.0 stable
      expect(UpdateService.isNewerVersion('v1.29.0-beta.1', 'v1.29.0'), isFalse);
    });

    test('newer base version with beta is newer than older stable', () {
      // 1.30.0-beta.1 is newer than 1.29.0 stable
      expect(UpdateService.isNewerVersion('v1.30.0-beta.1', 'v1.29.0'), isTrue);

      // Older base version with beta is not newer than newer stable
      expect(UpdateService.isNewerVersion('v1.28.0-beta.9', 'v1.29.0'), isFalse);
    });

    test('build number fallback', () {
      expect(UpdateService.isNewerVersion('1.29.0+50', '1.29.0+49'), isTrue);
      expect(UpdateService.isNewerVersion('1.29.0+49', '1.29.0+50'), isFalse);
    });
  });

  group('UpdateService.downloadAndInstallApkWithProgress', () {
    test('retries silently on network failures and yields clean user error after timeout', () async {
      final dio = Dio();
      final adapter = _MockFailingHttpClientAdapter(failUntilAttempt: 999);
      dio.httpClientAdapter = adapter;

      bool retryStateReported = false;
      String? reportedError;

      await UpdateService.downloadAndInstallApkWithProgress(
        downloadUrl: 'https://example.com/test.apk',
        dioOverride: dio,
        maxRetryDuration: const Duration(milliseconds: 400),
        retryDelay: const Duration(milliseconds: 10),
        onProgress: (_, __) {},
        onComplete: (_) {},
        onError: (err) {
          reportedError = err;
        },
        onRetryStateChange: (isRetrying) {
          if (isRetrying) retryStateReported = true;
        },
      );

      // Verify that silent retries occurred
      expect(adapter.attempts, greaterThan(1));
      expect(retryStateReported, isTrue);

      // Verify clean user error, with NO raw Dio/stack log dump
      expect(reportedError, isNotNull);
      expect(reportedError, contains('Download could not be completed'));
      expect(reportedError, isNot(contains('DioException')));
      expect(reportedError, isNot(contains('HttpException')));
    });

    test('terminates immediately without error when cancelled', () async {
      final dio = Dio();
      dio.httpClientAdapter = _MockFailingHttpClientAdapter(failUntilAttempt: 999);

      final cancelToken = CancelToken();
      String? reportedError;
      bool completed = false;

      // Cancel before starting
      cancelToken.cancel('User cancelled');

      await UpdateService.downloadAndInstallApkWithProgress(
        downloadUrl: 'https://example.com/test.apk',
        dioOverride: dio,
        cancelToken: cancelToken,
        onProgress: (_, __) {},
        onComplete: (_) {
          completed = true;
        },
        onError: (err) {
          reportedError = err;
        },
      );

      expect(reportedError, isNull);
      expect(completed, isFalse);
    });
  });
}

class _MockFailingHttpClientAdapter implements HttpClientAdapter {
  int attempts = 0;
  final int failUntilAttempt;

  _MockFailingHttpClientAdapter({required this.failUntilAttempt});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    attempts++;
    if (attempts <= failUntilAttempt) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'Network connection lost',
      );
    }
    return ResponseBody.fromBytes([], 200);
  }

  @override
  void close({bool force = false}) {}
}
