import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/engines/scripture/models/scripture_card.dart';
import 'package:mobile/features/engines/scripture/screens/scripture_screensaver_app.dart';
import 'package:mobile/features/engines/scripture/widgets/scripture_card_view.dart';

void main() {
  testWidgets(
      'ScriptureScreensaverApp renders without overflow at 320, 600, 840, and 1400px',
      (tester) async {
    final cards = [
      ScriptureCard(
        id: 'test_1',
        bookNumber: 43,
        bookName: 'John',
        chapter: 3,
        startVerse: 16,
        endVerse: 16,
        referenceLabel: 'John 3:16',
        backgroundPreset: 'mountain_dawn',
        resolvedText:
            'For God so loved the world, that He gave His only begotten Son.',
        resolvedVersion: 'NASB',
      ),
    ];

    for (final width in [320.0, 600.0, 840.0, 1400.0]) {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(ScriptureScreensaverApp(initialCards: cards));
      await tester.pump(const Duration(milliseconds: 700));

      expect(tester.takeException(), isNull);
      expect(find.byType(ScriptureCardView), findsOneWidget);
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
