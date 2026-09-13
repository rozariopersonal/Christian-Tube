import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/services/feedback_context_service.dart';

void main() {
  const service = FeedbackContextService();

  group('FeedbackContextService', () {
    test('resolves Bible route with book, chapter and verse', () {
      final context = service.resolveScreenContext(
        routePath: '/bible',
        queryParams: {
          'version': 'NASB',
          'book': 'John',
          'chapter': '3',
          'verse': '16',
        },
      );
      expect(context, 'Bible • John 3:16 (NASB)');
    });

    test('resolves Bible route without verse', () {
      final context = service.resolveScreenContext(
        routePath: '/bible',
        queryParams: {
          'version': 'ESV',
          'book': 'Genesis',
          'chapter': '1',
        },
      );
      expect(context, 'Bible • Genesis Ch 1 (ESV)');
    });

    test('resolves video player route with videoId', () {
      final context = service.resolveScreenContext(
        routePath: '/watch/xyz123',
      );
      expect(context, 'Video Player • ID: xyz123');
    });

    test('resolves standard screens correctly', () {
      expect(service.resolveScreenContext(routePath: '/shorts'), 'Shorts Feed');
      expect(service.resolveScreenContext(routePath: '/words'), 'Words Micro-Feed');
      expect(service.resolveScreenContext(routePath: '/books'), 'Book Reader');
      expect(service.resolveScreenContext(routePath: '/songs'), 'Songs Library');
      expect(service.resolveScreenContext(routePath: '/settings'), 'Settings & Customization');
      expect(service.resolveScreenContext(routePath: '/profile'), 'Profile & Account');
      expect(service.resolveScreenContext(routePath: '/feed'), 'Home Video Feed');
      expect(service.resolveScreenContext(routePath: '/'), 'Home Video Feed');
    });
  });
}
