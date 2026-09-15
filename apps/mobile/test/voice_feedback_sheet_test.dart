import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/feedback/controllers/feedback_controller.dart';
import 'package:mobile/features/feedback/models/feedback_report.dart';
import 'package:mobile/features/feedback/services/feedback_submission_service.dart';
import 'package:mobile/features/feedback/services/speech_recognition_service.dart';
import 'package:mobile/features/feedback/widgets/voice_feedback_sheet.dart';

class StubSpeechService extends SpeechRecognitionService {
  @override
  bool get isListening => false;

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

class StubSubmissionService extends FeedbackSubmissionService {
  @override
  Future<FeedbackSubmissionResult> submitFeedback(FeedbackReport report) async {
    return const FeedbackSubmissionResult(isSuccess: true, issueNumber: '99');
  }
}

class FailingSubmissionService extends FeedbackSubmissionService {
  @override
  Future<FeedbackSubmissionResult> submitFeedback(FeedbackReport report) async {
    return const FeedbackSubmissionResult(
      isSuccess: false,
      errorMessage: 'GitHub API error 403: rate limit exceeded',
    );
  }
}

class BlockingSubmissionService extends FeedbackSubmissionService {
  final Completer<FeedbackSubmissionResult> completer = Completer();

  @override
  Future<FeedbackSubmissionResult> submitFeedback(FeedbackReport report) {
    return completer.future;
  }
}

Widget buildTestWidget({
  required FeedbackController controller,
  required Size size,
  Brightness brightness = Brightness.dark,
}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      theme: ThemeData(
        brightness: brightness,
        extensions: const [AppTokens.dark],
      ),
      home: Scaffold(
        body: Center(
          child: VoiceFeedbackSheet(controller: controller),
        ),
      ),
    ),
  );
}

void main() {
  group('VoiceFeedbackSheet Widget Tests', () {
    late FeedbackController controller;

    setUp(() {
      controller = FeedbackController(
        speechService: StubSpeechService(),
        submissionService: StubSubmissionService(),
      );
      controller.initializeContext(
        screenContext: 'Bible • John 3:16 (NASB)',
        route: '/bible',
        diagnostics: {'appName': 'ChristianApp'},
      );
    });

    tearDown(() {
      controller.dispose();
    });

    for (final width in [320.0, 600.0, 840.0, 1400.0]) {
      testWidgets('renders without overflow at ${width.toInt()}dp viewport',
          (tester) async {
        final size = Size(width, 800.0);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          buildTestWidget(controller: controller, size: size),
        );
        await tester.pump();

        expect(find.text('Bible • John 3:16 (NASB)'), findsOneWidget);
        expect(find.text('Submit'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('typing in editor updates controller and enables Submit',
        (tester) async {
      const size = Size(360.0, 780.0);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestWidget(controller: controller, size: size),
      );
      await tester.pump();

      final textField = find.byType(TextField);
      await tester.enterText(textField, 'Audio playback stopped after lock');
      await tester.pump();

      expect(controller.text, 'Audio playback stopped after lock');
      expect(controller.canSubmit, isTrue);

      final submitBtn = find.widgetWithText(ElevatedButton, 'Submit');
      final elevatedBtn = tester.widget<ElevatedButton>(submitBtn);
      expect(elevatedBtn.onPressed, isNotNull);
    });

    testWidgets('shows error banner and Retry button on submit failure',
        (tester) async {
      final failController = FeedbackController(
        speechService: StubSpeechService(),
        submissionService: FailingSubmissionService(),
      );
      failController.initializeContext(
        screenContext: 'Home',
        route: '/',
        diagnostics: {},
      );
      failController.updateText('Bug report');

      const size = Size(360.0, 780.0);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestWidget(controller: failController, size: size),
      );
      await tester.pump();

      // Submit to trigger error
      final submitBtn = find.widgetWithText(ElevatedButton, 'Submit');
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Error banner visible
      expect(failController.submitState, FeedbackSubmitState.error);
      expect(find.text('GitHub API error 403: rate limit exceeded'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      // Retry resets to idle
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(failController.submitState, FeedbackSubmitState.idle);
      expect(find.text('GitHub API error 403: rate limit exceeded'), findsNothing);
      expect(find.text('Submit'), findsOneWidget);

      failController.dispose();
    });

    testWidgets('Submit button shows loading indicator while submitting',
        (tester) async {
      final blocking = BlockingSubmissionService();
      final loadingController = FeedbackController(
        speechService: StubSpeechService(),
        submissionService: blocking,
      );
      loadingController.initializeContext(
        screenContext: 'Home',
        route: '/',
        diagnostics: {},
      );

      const size = Size(360.0, 780.0);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestWidget(controller: loadingController, size: size),
      );
      await tester.pump();

      loadingController.updateText('Test loading');
      await tester.pump();

      final submitBtn = find.widgetWithText(ElevatedButton, 'Submit');
      await tester.tap(submitBtn);
      await tester.pump();

      // Submission is in-flight, so the button swaps to a spinner.
      expect(loadingController.submitState, FeedbackSubmitState.submitting);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Release the submission; sheet closes on success.
      blocking.completer.complete(
        const FeedbackSubmissionResult(isSuccess: true, issueNumber: '5'),
      );
      await tester.pumpAndSettle();
      expect(loadingController.submitState, FeedbackSubmitState.success);

      loadingController.dispose();
    });

    testWidgets('Cancel button is disabled during submission', (tester) async {
      final blocking = BlockingSubmissionService();
      final loadingController = FeedbackController(
        speechService: StubSpeechService(),
        submissionService: blocking,
      );
      loadingController.initializeContext(
        screenContext: 'Home',
        route: '/',
        diagnostics: {},
      );

      const size = Size(360.0, 780.0);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestWidget(controller: loadingController, size: size),
      );
      await tester.pump();

      loadingController.updateText('Test cancel disable');
      await tester.pump();

      final submitBtn = find.widgetWithText(ElevatedButton, 'Submit');
      await tester.tap(submitBtn);
      await tester.pump();

      final cancelBtn = find.widgetWithText(TextButton, 'Cancel');
      final textButton = tester.widget<TextButton>(cancelBtn);
      expect(textButton.onPressed, isNull);

      blocking.completer.complete(
        const FeedbackSubmissionResult(isSuccess: true, issueNumber: '5'),
      );
      await tester.pumpAndSettle();
      loadingController.dispose();
    });
  });
}
