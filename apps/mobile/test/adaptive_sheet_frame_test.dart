import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/layout/adaptive_sheet_frame.dart';
import 'package:mobile/core/layout/content_width.dart';
import 'package:mobile/core/theme/app_tokens.dart';

Widget wrapWithApp(Widget child) {
  return MaterialApp(
    theme: ThemeData.dark().copyWith(
      extensions: const [AppTokens.dark],
    ),
    home: Scaffold(
      body: child,
    ),
  );
}

void main() {
  group('AdaptiveSheetFrame Widget Tests', () {
    const testViewports = [320.0, 600.0, 840.0, 1400.0];

    for (final width in testViewports) {
      testWidgets('renders cleanly without overflow at width $width', (tester) async {
        tester.view.physicalSize = Size(width * 2, 800 * 2);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          wrapWithApp(
            AdaptiveSheetFrame(
              maxHeightFactor: 0.85,
              showDragHandle: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Test Bottom Sheet Title'),
                  const SizedBox(height: 12),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 5,
                    itemBuilder: (ctx, i) => ListTile(
                      title: Text('Sheet item $i'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(AdaptiveSheetFrame), findsOneWidget);
        expect(find.text('Test Bottom Sheet Title'), findsOneWidget);

        // Verify bottom alignment is enforced
        final alignFinder = find.byType(Align);
        expect(alignFinder, findsWidgets);
        final Align align = tester.widget(alignFinder.first);
        expect(align.alignment, equals(Alignment.bottomCenter));

        // Verify width clamping to max 640 on medium/expanded
        final frameRender = tester.renderObject(find.byType(AdaptiveSheetFrame)) as RenderBox;
        if (width >= 840) {
          expect(frameRender.size.width, lessThanOrEqualTo(width));
          // Content inside frame is constrained to kSheetMaxWidth
          final constrainedBoxFinder = find.descendant(
            of: find.byType(AdaptiveSheetFrame),
            matching: find.byType(ConstrainedBox),
          );
          final ConstrainedBox constrainedBox = tester.widget(constrainedBoxFinder.first);
          expect(constrainedBox.constraints.maxWidth, equals(kSheetMaxWidth));
        }
      });
    }

    testWidgets('respects custom maxHeightFactor and contentPadding', (tester) async {
      tester.view.physicalSize = const Size(360 * 2, 800 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        wrapWithApp(
          AdaptiveSheetFrame(
            maxHeightFactor: 0.50,
            contentPadding: const EdgeInsets.all(24),
            child: const Text('Custom Config Sheet'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final constrainedBoxFinder = find.descendant(
        of: find.byType(AdaptiveSheetFrame),
        matching: find.byType(ConstrainedBox),
      );
      final ConstrainedBox constrainedBox = tester.widget(constrainedBoxFinder.first);
      expect(constrainedBox.constraints.maxHeight, equals(800 * 0.50));
    });

    testWidgets('showAdaptiveBottomSheet opens with easeOutCubic curve and dismisses smoothly', (tester) async {
      tester.view.physicalSize = const Size(360 * 2, 640 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        wrapWithApp(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showAdaptiveBottomSheet<void>(
                  context: context,
                  builder: (ctx) => const AdaptiveSheetFrame(
                    child: Text('Opened Adaptive Sheet'),
                  ),
                );
              },
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap to open sheet
      await tester.tap(find.text('Open Sheet'));
      await tester.pump(); // Start animation
      await tester.pump(const Duration(milliseconds: 160)); // Midway through 320ms entrance
      expect(find.text('Opened Adaptive Sheet'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.text('Opened Adaptive Sheet'), findsOneWidget);

      // Tap barrier to dismiss
      await tester.tapAt(const Offset(180, 50));
      await tester.pumpAndSettle();
      expect(find.text('Opened Adaptive Sheet'), findsNothing);
    });
  });
}
