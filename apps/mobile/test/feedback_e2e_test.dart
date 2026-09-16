import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/features/feedback/controllers/feedback_controller.dart';
import 'package:mobile/features/feedback/models/feedback_report.dart';
import 'package:mobile/features/feedback/services/feedback_submission_service.dart';
import 'package:mobile/features/feedback/services/speech_recognition_service.dart';

/// [HttpClientAdapter] that intercepts outbound requests without touching the
/// network. It records the exact request (URL, headers, body) and returns a
/// GitHub-flavored 201 response. This lets the test exercise the *real*
/// submission code path end-to-end: controller -> service -> HTTP request that
/// GitHub would receive.
class RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<String> requestBodies = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);

    var body = '';
    if (requestStream != null) {
      body = await requestStream
          .map(utf8.decode)
          .join();
    }
    requestBodies.add(body);

    // Only the GitHub Issues REST endpoint is considered reachable; any other
    // host (e.g. the backend proxy fallback) is treated as offline.
    if (!options.path.contains('/repos/') || !options.path.endsWith('/issues')) {
      return ResponseBody.fromString('', 404);
    }

    final payload = jsonDecode(body) as Map<String, dynamic>;

    // Mirror a GitHub success response for a freshly created issue.
    final outbound = jsonEncode({
      'url': 'https://api.github.com/repos/test/repo/issues/42',
      'html_url': 'https://github.com/rozariopersonal/Christian-Tube/issues/42',
      'number': 42,
      'title': payload['title'],
      'body': payload['body'],
      'labels': payload['labels'] ?? [],
    });

    return ResponseBody.fromString(
      outbound,
      201,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class NoopSpeechService extends SpeechRecognitionService {
  @override
  Future<void> startListening({
    required void Function(String text, bool isFinal) onResult,
    void Function(double level)? onSoundLevelChange,
    String? localeId,
  }) async {}

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> cancelListening() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const repo = 'rozariopersonal/Christian-Tube';

  setUp(() {
    // Simulate a release build configured with the feedback token. This is the
    // same path `--dart-define=GITHUB_FEEDBACK_TOKEN=...` takes.
    AppConfig.feedbackRepo = repo;
    AppConfig.githubFeedbackToken = 'ghp_dummy_token_for_e2e';
  });

  tearDown(() {
    AppConfig.githubFeedbackToken = null;
  });

  test('E2E: feedback submission reaches the GitHub issues endpoint', () async {
    final adapter = RecordingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.github.com'))
      ..httpClientAdapter = adapter;

    final service = FeedbackSubmissionService(dio: dio);
    final report = FeedbackReport(
      text: 'Audio playback stops after locking the screen on my tablet.',
      screenContext: 'Audio Player • Worship Medley',
      route: '/audio',
      diagnostics: {
        'appName': 'ChristianApp',
        'platform': 'android',
        'screenClass': 'expanded',
      },
    );

    final result = await service.submitFeedback(report);

    // The service parsed the created issue correctly.
    expect(result.isSuccess, isTrue);
    expect(result.issueNumber, '42');
    expect(result.issueUrl,
        'https://github.com/rozariopersonal/Christian-Tube/issues/42');

    // Exactly one request hit the GitHub Issues REST endpoint.
    expect(adapter.requests, hasLength(1));
    final opts = adapter.requests.single;
    expect(opts.uri.path, '/repos/$repo/issues');
    expect(opts.method, 'POST');

    // Correct auth + API headers.
    expect(opts.headers['Authorization'], 'Bearer ghp_dummy_token_for_e2e');
    expect(opts.headers['Accept'], 'application/vnd.github+json');
    expect(opts.headers['User-Agent'], 'ChristianApp');

    // The body carries title, markdown body, and the user-feedback label.
    final payload =
        jsonDecode(adapter.requestBodies.single) as Map<String, dynamic>;
    expect(payload['title'], startsWith('[Feedback]'));
    expect(payload['labels'], contains('user-feedback'));
    final body = payload['body'] as String;
    expect(body, contains('Audio playback stops after locking'));
    expect(body, contains('### 📍 Context'));
    expect(body, contains('Audio Player • Worship Medley'));
    expect(body, contains('| **platform** | `android` |'));
  });

  test('E2E: feedback controller submits through the real service', () async {
    final adapter = RecordingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.github.com'))
      ..httpClientAdapter = adapter;
    final service = FeedbackSubmissionService(dio: dio);

    final controller = FeedbackController(
      speechService: NoopSpeechService(),
      submissionService: service,
    );
    controller.initializeContext(
      screenContext: 'Bible • John 3:16 (NASB)',
      route: '/bible',
      diagnostics: {'book': 'John'},
    );
    controller.updateText('The verse font is hard to read at night.');

    final ok = await controller.submit();

    expect(ok, isTrue);
    expect(controller.submitState, FeedbackSubmitState.success);
    expect(controller.submittedIssueNumber, '42');
    expect(controller.submittedIssueUrl,
        'https://github.com/rozariopersonal/Christian-Tube/issues/42');

    final payload =
        jsonDecode(adapter.requestBodies.single) as Map<String, dynamic>;
    expect(payload['title'], '[Feedback] The verse font is hard to read at night.');
    expect(payload['body'], contains('Bible • John 3:16 (NASB)'));
    controller.dispose();
  });

  test('E2E: missing token falls back to backend proxy', () async {
    AppConfig.githubFeedbackToken = null;

    final adapter = RecordingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.github.com'))
      ..httpClientAdapter = adapter;
    final service = FeedbackSubmissionService(dio: dio);

    final report = FeedbackReport(
      text: 'Shorts grid stutters on web.',
      screenContext: 'Home Video Feed',
      route: '/',
      diagnostics: {},
    );

    final result = await service.submitFeedback(report);

    // No direct GitHub call was made; the single request went to the backend
    // proxy, which the mock treats as offline. The service reports a failure
    // rather than silently marking success.
    expect(adapter.requests, hasLength(1));
    expect(
      adapter.requests.single.uri.host,
      'christianapp-zjdh.onrender.com',
    );
    expect(result.isSuccess, isFalse);
    expect(result.errorMessage, isNotNull);
  });
}