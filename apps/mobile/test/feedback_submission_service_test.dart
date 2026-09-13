import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/models/feedback_report.dart';
import 'package:mobile/features/feedback/services/feedback_submission_service.dart';

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

    test('formatMarkdownBody formats structured markdown with context and diagnostics', () {
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
}
