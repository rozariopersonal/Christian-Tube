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
  });
}
