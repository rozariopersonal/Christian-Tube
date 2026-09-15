import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/features/feedback/models/feedback_report.dart';
import 'package:mobile/features/feedback/services/feedback_submission_service.dart';

class SequenceAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<(int, String)> responses;

  SequenceAdapter(this.responses);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (!options.uri.path.contains('/repos/') ||
        !options.uri.path.endsWith('/issues')) {
      return ResponseBody.fromString(
        '{"message":"not found"}',
        404,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    final (status, body) = responses.removeAt(0);
    return ResponseBody.fromString(
      body,
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
  final service = FeedbackSubmissionService();

  group('FeedbackSubmissionService', () {
    test('deriveIssueTitle extracts first sentence', () {
      const text = 'Audio player stops in background. Please fix this soon.';
      final title = service.deriveIssueTitle(text, 'Bible • John 3:16');
      expect(title, '[Feedback] Audio player stops in background.');
    });

    test('deriveIssueTitle truncates very long descriptions', () {
      final longText = 'A' * 100;
      final title = service.deriveIssueTitle(longText, 'Home');
      expect(title.length, lessThanOrEqualTo(75));
      expect(title.endsWith('...'), isTrue);
    });

    test('deriveIssueTitle handles empty text fallback', () {
      final title = service.deriveIssueTitle('', 'Bible');
      expect(title, '[Feedback] User report on Bible');
    });

    test('formatMarkdownBody formats structured markdown', () {
      final report = FeedbackReport(
        text: 'The scripture font is too small on my tablet.',
        screenContext: 'Bible • Matthew 5',
        route: '/bible?book=Matthew&chapter=5',
        diagnostics: {
          'appName': 'ChristianApp',
          'appVersion': 'v1.32.0+50',
          'platform': 'android',
        },
      );

      final markdown = service.formatMarkdownBody(report);
      expect(markdown, contains('### 📝 User Feedback'));
      expect(markdown, contains('The scripture font is too small on my tablet.'));
      expect(markdown, contains('### 📍 Context'));
      expect(markdown, contains('Bible • Matthew 5'));
      expect(markdown, contains('### 📱 Diagnostics'));
      expect(markdown, contains('| **appName** | `ChristianApp` |'));
    });
  });

  group('FeedbackSubmissionService retry logic', () {
    setUp(() {
      AppConfig.feedbackRepo = 'test/repo';
      AppConfig.githubFeedbackToken = 'ghp_test_token';
    });

    tearDown(() {
      AppConfig.githubFeedbackToken = null;
    });

    test('retries on 5xx and eventually succeeds', () async {
      final adapter = SequenceAdapter([
        (500, '{"message":"server error"}'),
        (500, '{"message":"server error"}'),
        (
          201,
          jsonEncode({
            'number': 100,
            'html_url': 'https://github.com/test/issues/100',
          }),
        ),
      ]);
      final dio = Dio(BaseOptions(baseUrl: 'https://api.github.com'))
        ..httpClientAdapter = adapter;

      final svc = FeedbackSubmissionService(dio: dio);
      final result = await svc.submitFeedback(FeedbackReport(
        text: 'Test retry',
        screenContext: 'Home',
        route: '/',
        diagnostics: {},
      ));

      expect(result.isSuccess, isTrue);
      expect(result.issueNumber, '100');
      // Two 5xx failures were retried before a third attempt succeeded.
      expect(adapter.requests, hasLength(3));
    });

    test('returns error on non-retryable 403', () async {
      final adapter = SequenceAdapter([
        (
          403,
          jsonEncode({'message': 'API rate limit exceeded'}),
        ),
      ]);
      final dio = Dio(BaseOptions(baseUrl: 'https://api.github.com'))
        ..httpClientAdapter = adapter;

      final svc = FeedbackSubmissionService(dio: dio);
      final result = await svc.submitFeedback(FeedbackReport(
        text: 'Test 403',
        screenContext: 'Home',
        route: '/',
        diagnostics: {},
      ));

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('403'));
      expect(adapter.requests, hasLength(1));
    });
  });
}