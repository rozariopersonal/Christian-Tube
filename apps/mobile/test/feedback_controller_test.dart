import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/controllers/feedback_controller.dart';
import 'package:mobile/features/feedback/models/feedback_report.dart';
import 'package:mobile/features/feedback/services/feedback_submission_service.dart';
import 'package:mobile/features/feedback/services/speech_recognition_service.dart';

class FakeSpeechService extends SpeechRecognitionService {
  bool isListeningMock = false;

  @override
  bool get isListening => isListeningMock;

  @override
  Future<void> startListening({
    required void Function(String text, bool isFinal) onResult,
    void Function(double level)? onSoundLevelChange,
    String? localeId,
  }) async {
    isListeningMock = true;
    onResult('Sample voice text', true);
  }

  @override
  Future<void> stopListening() async {
    isListeningMock = false;
  }

  @override
  Future<void> cancelListening() async {
    isListeningMock = false;
  }
}

class FakeSubmissionService extends FeedbackSubmissionService {
  bool shouldSucceed = true;

  @override
  Future<FeedbackSubmissionResult> submitFeedback(FeedbackReport report) async {
    if (shouldSucceed) {
      return const FeedbackSubmissionResult(
        isSuccess: true,
        issueNumber: '42',
        issueUrl: 'https://github.com/rozariopersonal/Christian-Tube/issues/42',
      );
    } else {
      return const FeedbackSubmissionResult(
        isSuccess: false,
        errorMessage: 'Network timeout',
      );
    }
  }
}

void main() {
  group('FeedbackController', () {
    late FakeSpeechService speechService;
    late FakeSubmissionService submissionService;
    late FeedbackController controller;

  setUp(() {
    speechService = FakeSpeechService();
    submissionService = FakeSubmissionService();
    controller = FeedbackController(
      speechService: speechService,
      submissionService: submissionService,
    );
  });

  tearDown(() {
    controller.dispose();
  });

  test('cannot submit when text is empty', () {
    expect(controller.canSubmit, isFalse);
    controller.updateText('   ');
    expect(controller.canSubmit, isFalse);
    controller.updateText('Hello world');
    expect(controller.canSubmit, isTrue);
  });

  test('startListening captures recognized text', () async {
    await controller.startListening();
    expect(controller.text, 'Sample voice text');
    expect(controller.canSubmit, isTrue);
  });

  test('submit successfully updates submitState to success', () async {
    controller.updateText('Great app feedback');
    controller.initializeContext(
      screenContext: 'Bible • John 3',
      route: '/bible',
      diagnostics: {},
    );

    final ok = await controller.submit();
    expect(ok, isTrue);
    expect(controller.submitState, FeedbackSubmitState.success);
    expect(controller.submittedIssueNumber, '42');
  });

  test('submit failure updates submitState to error', () async {
    submissionService.shouldSucceed = false;
    controller.updateText('Bug report');

    final ok = await controller.submit();
    expect(ok, isFalse);
    expect(controller.submitState, FeedbackSubmitState.error);
    expect(controller.errorMessage, 'Network timeout');
  });
  });
}
