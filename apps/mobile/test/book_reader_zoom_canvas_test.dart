import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/widgets/book_reader_zoom_canvas.dart';

void main() {
  testWidgets('reader zoom applies to the whole canvas at supported widths',
      (tester) async {
    final controller = TransformationController();
    addTearDown(controller.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final width in [320.0, 600.0, 840.0, 1400.0]) {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppTokens.light]),
          home: Scaffold(
            body: BookReaderZoomCanvas(
              controller: controller,
              child: const Column(
                children: [
                  Text('Book text'),
                  SizedBox(height: 24),
                  Icon(Icons.image),
                ],
              ),
            ),
          ),
        ),
      );

      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(viewer.minScale, BookReaderZoomCanvas.minScale);
      expect(viewer.maxScale, BookReaderZoomCanvas.maxScale);
      expect(viewer.transformationController, same(controller));
      expect(
        find.descendant(
          of: find.byType(InteractiveViewer),
          matching: find.text('Book text'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(InteractiveViewer),
          matching: find.byIcon(Icons.image),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }

    controller.value = Matrix4.diagonal3Values(2.0, 2.0, 2.0);
    await tester.pump();
    expect(controller.value.getMaxScaleOnAxis(), 2.0);
  });

  testWidgets('pinch gestures zoom the complete reader canvas', (tester) async {
    final controller = TransformationController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppTokens.light]),
        home: Scaffold(
          body: BookReaderZoomCanvas(
            controller: controller,
            child: const Column(
              children: [
                Text('Book text'),
                SizedBox(height: 24),
                Icon(Icons.image),
              ],
            ),
          ),
        ),
      ),
    );

    final firstFinger =
        await tester.startGesture(const Offset(120, 400), pointer: 1);
    final secondFinger =
        await tester.startGesture(const Offset(200, 400), pointer: 2);
    await firstFinger.moveTo(const Offset(80, 400));
    await secondFinger.moveTo(const Offset(240, 400));
    await tester.pump();

    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1.0));

    await firstFinger.up();
    await secondFinger.up();
    await tester.pump();
  });

  testWidgets('reader zoom controls are not displayed', (tester) async {
    final controller = TransformationController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppTokens.light]),
        home: Scaffold(
          body: BookReaderZoomCanvas(
            controller: controller,
            child: const Center(child: Text('Book text')),
          ),
        ),
      ),
    );

    expect(find.byTooltip('Zoom in'), findsNothing);
    expect(find.byTooltip('Zoom out'), findsNothing);
    expect(find.byTooltip('Reset zoom'), findsNothing);
  });
}
