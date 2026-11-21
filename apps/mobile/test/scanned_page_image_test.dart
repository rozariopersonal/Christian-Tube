import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/widgets/scanned_page_image.dart';
import 'package:mobile/shared/services/reader_appearance.dart';

void main() {
  testWidgets('scanned page images support gesture zoom at narrow widths', (
    tester,
  ) async {
    final appearance = ReaderAppearance();
    addTearDown(appearance.dispose);

    for (final width in [320.0, 600.0, 840.0, 1400.0]) {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppTokens.light]),
          home: Scaffold(
            body: ScannedPageImage(
              imageUrl: 'https://example.invalid/page.jpg',
              tokens: AppTokens.light,
              appearance: appearance,
            ),
          ),
        ),
      );

      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(viewer.minScale, 1);
      expect(viewer.maxScale, 4);
      expect(tester.takeException(), isNull);
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
