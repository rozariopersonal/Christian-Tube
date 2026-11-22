import 'package:flutter/material.dart';

/// Adds one zoomable canvas around all content in the book reader viewport.
class BookReaderZoomCanvas extends StatelessWidget {
  const BookReaderZoomCanvas({
    super.key,
    required this.controller,
    required this.child,
  });

  static const minScale = 1.0;
  static const maxScale = 4.0;

  final TransformationController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: controller,
      minScale: minScale,
      maxScale: maxScale,
      trackpadScrollCausesScale: true,
      child: child,
    );
  }
}
