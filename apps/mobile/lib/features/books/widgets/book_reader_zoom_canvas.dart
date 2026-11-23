import 'package:flutter/material.dart';

import '../controllers/reader_canvas_controller.dart';
import '../controllers/reader_canvas_gesture_recognizer.dart';

/// A fixed viewport whose content can be transformed by a canvas-wide pinch.
class BookReaderZoomCanvas extends StatelessWidget {
  const BookReaderZoomCanvas({
    super.key,
    required this.controller,
    required this.child,
  });

  final ReaderCanvasController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        return SizedBox.fromSize(
          size: viewport,
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              ReaderCanvasGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                      ReaderCanvasGestureRecognizer>(
                ReaderCanvasGestureRecognizer.new,
                (recognizer) {
                  recognizer.canPan = () => controller.isZoomed;
                  recognizer.onTransform = (from, to, factor) =>
                      controller.applyGesture(viewport, from, to, factor);
                },
              ),
            },
            child: ClipRect(
              child: ValueListenableBuilder<Matrix4>(
                valueListenable: controller,
                child: RepaintBoundary(child: child),
                builder: (context, matrix, content) => Transform(
                  transform: controller.matrixForViewport(viewport, matrix),
                  child: content,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
