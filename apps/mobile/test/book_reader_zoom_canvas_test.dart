import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/books/controllers/reader_canvas_controller.dart';
import 'package:mobile/features/books/widgets/book_reader_zoom_canvas.dart';

void main() {
  testWidgets(
      'canvas pinch wins over page and vertical scrolling from a gutter',
      (tester) async {
    final zoom = ReaderCanvasController();
    final pages = PageController();
    final scroll = ScrollController();
    addTearDown(zoom.dispose);
    addTearDown(pages.dispose);
    addTearDown(scroll.dispose);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final scan = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8A'
      'AwsB/ax/TaUAAAAASUVORK5CYII=',
    );
    final canvas = find.byType(BookReaderZoomCanvas);
    for (final size in const [
      Size(320, 640),
      Size(600, 400),
      Size(840, 650),
      Size(1400, 800),
    ]) {
      tester.view.physicalSize = size;
      zoom.value = Matrix4.identity();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookReaderZoomCanvas(
              controller: zoom,
              child: PageView(
                controller: pages,
                children: [
                  SingleChildScrollView(
                    controller: scroll,
                    child: SizedBox(
                      height: 1400,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Image.memory(scan, width: 60, height: 60),
                      ),
                    ),
                  ),
                  const Center(child: Text('Next page')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(canvas), size);
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Zoom in'), findsNothing);

      final center = tester.getCenter(canvas);
      final first = await tester.startGesture(center - const Offset(30, 0));
      final second = await tester.startGesture(center + const Offset(30, 0));
      // Large first move would exceed the child PageView's drag threshold.
      await first.moveBy(const Offset(-40, 0));
      await second.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(zoom.value.getMaxScaleOnAxis(), closeTo(140 / 60, 0.001));
      expect(zoom.toScene(center).dx, closeTo(center.dx, 0.01));
      expect(zoom.toScene(center).dy, closeTo(center.dy, 0.01));
      expect(pages.page, 0);
      expect(scroll.offset, 0);
      await first.up();
      await second.up();
      await tester.pump();

      final beforePan = zoom.value.getTranslation();
      await tester.dragFrom(center, const Offset(-30, -40));
      expect(zoom.value.getTranslation().x, lessThan(beforePan.x));
      expect(zoom.value.getTranslation().y, lessThan(beforePan.y));
      expect(scroll.offset, 0);
      expect(pages.page, 0);

      final inwardLeft =
          await tester.startGesture(center - const Offset(70, 0));
      final inwardRight =
          await tester.startGesture(center + const Offset(70, 0));
      await inwardLeft.moveBy(const Offset(45, 0));
      await inwardRight.moveBy(const Offset(-45, 0));
      await inwardLeft.up();
      await inwardRight.up();
      await tester.pump();
      expect(zoom.value, Matrix4.identity());
    }

    await tester.drag(canvas, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    final trackpad =
        await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await trackpad.panZoomStart(tester.getCenter(canvas));
    await trackpad.panZoomUpdate(tester.getCenter(canvas), scale: 1.5);
    expect(zoom.value.getMaxScaleOnAxis(), 1.5);
    await trackpad.panZoomEnd();
    zoom.reset();
    await tester.pump();

    await tester.fling(canvas, const Offset(-450, 0), 1600);
    await tester.pumpAndSettle();
    expect(pages.page, 1);
    expect(find.text('Next page'), findsOneWidget);
  });
}
