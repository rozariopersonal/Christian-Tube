import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_tokens.dart';

/// Adds one zoomable canvas around all content in the book reader viewport.
class BookReaderZoomCanvas extends StatelessWidget {
  const BookReaderZoomCanvas({
    super.key,
    required this.controller,
    required this.tokens,
    required this.child,
  });

  static const minScale = 1.0;
  static const maxScale = 4.0;

  final TransformationController controller;
  final AppTokens tokens;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        InteractiveViewer(
          transformationController: controller,
          minScale: minScale,
          maxScale: maxScale,
          child: child,
        ),
        if (kIsWeb)
          Positioned(
            top: 12,
            right: 12,
            child: _BookReaderZoomControls(
              controller: controller,
              tokens: tokens,
            ),
          ),
      ],
    );
  }
}

class _BookReaderZoomControls extends StatelessWidget {
  const _BookReaderZoomControls({
    required this.controller,
    required this.tokens,
  });

  final TransformationController controller;
  final AppTokens tokens;

  void _setScale(double scale) {
    final nextScale = scale
        .clamp(BookReaderZoomCanvas.minScale, BookReaderZoomCanvas.maxScale)
        .toDouble();
    controller.value = Matrix4.diagonal3Values(
      nextScale,
      nextScale,
      nextScale,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Matrix4>(
      valueListenable: controller,
      builder: (context, transform, _) {
        final scale = transform
            .getMaxScaleOnAxis()
            .clamp(BookReaderZoomCanvas.minScale, BookReaderZoomCanvas.maxScale)
            .toDouble();
        return Material(
          color: tokens.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(12),
          elevation: 2,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Zoom out',
                onPressed: scale <= BookReaderZoomCanvas.minScale
                    ? null
                    : () => _setScale(scale / 1.25),
                icon: const Icon(Icons.remove),
              ),
              IconButton(
                tooltip: 'Reset zoom',
                onPressed: scale == BookReaderZoomCanvas.minScale
                    ? null
                    : () => _setScale(BookReaderZoomCanvas.minScale),
                icon: const Icon(Icons.fit_screen),
              ),
              IconButton(
                tooltip: 'Zoom in',
                onPressed: scale >= BookReaderZoomCanvas.maxScale
                    ? null
                    : () => _setScale(scale * 1.25),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        );
      },
    );
  }
}
