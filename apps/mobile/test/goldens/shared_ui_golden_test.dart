import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/shared/ui/bible_version_pill.dart';

/// Allows minor cross-OS font anti-aliasing variance (<= 2%) between local
/// Windows/macOS runs and Linux CI runners.
class _TolerantGoldenComparator extends LocalFileComparator {
  _TolerantGoldenComparator(super.testFile);

  final double maxDiffRatio = 0.02;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (!result.passed && result.diffPercent <= maxDiffRatio) {
      return true;
    }
    if (!result.passed) {
      final error = await generateFailureOutput(result, golden, basedir);
      throw FlutterError(error);
    }
    return result.passed;
  }
}

void main() {
  setUpAll(() {
    goldenFileComparator = _TolerantGoldenComparator(
      Uri.parse('test/goldens/shared_ui_golden_test.dart'),
    );
  });

  Widget buildHarness({required AppTokens tokens, required Brightness brightness}) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: brightness,
        colorScheme: ColorScheme.fromSeed(
          seedColor: tokens.accent,
          brightness: brightness,
        ),
        extensions: [tokens],
      ),
      home: Scaffold(
        backgroundColor: tokens.background,
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: BibleVersionPill(activeVersionId: 'bsb'),
          ),
        ),
      ),
    );
  }

  testWidgets('BibleVersionPill light theme golden', (tester) async {
    tester.view.physicalSize = const Size(320, 120);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      buildHarness(
        tokens: AppTokens.light.copyWith(accent: const Color(0xFFF59E0B)),
        brightness: Brightness.light,
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('bible_version_pill_light.png'),
    );
  });

  testWidgets('BibleVersionPill dark theme golden', (tester) async {
    tester.view.physicalSize = const Size(320, 120);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      buildHarness(
        tokens: AppTokens.dark.copyWith(accent: const Color(0xFFF59E0B)),
        brightness: Brightness.dark,
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('bible_version_pill_dark.png'),
    );
  });
}
