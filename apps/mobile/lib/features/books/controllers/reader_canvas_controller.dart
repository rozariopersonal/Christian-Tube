import 'package:flutter/widgets.dart';

class ReaderCanvasController extends TransformationController {
  static const minScale = 1.0;
  static const maxScale = 4.0;

  bool get isZoomed => value.getMaxScaleOnAxis() > minScale;

  void reset() {
    if (isZoomed) value = Matrix4.identity();
  }

  void applyGesture(Size viewport, Offset from, Offset to, double factor) {
    final currentScale = value.getMaxScaleOnAxis();
    final translation = value.getTranslation();
    final currentOffset = _bound(
      viewport,
      Offset(translation.x, translation.y),
      currentScale,
    );
    final scale = (currentScale * factor).clamp(minScale, maxScale).toDouble();
    final offset = _bound(
      viewport,
      to - (from - currentOffset) * (scale / currentScale),
      scale,
    );
    value = _matrix(scale, offset);
  }

  Matrix4 matrixForViewport(Size viewport, Matrix4 matrix) {
    final scale = matrix.getMaxScaleOnAxis();
    final translation = matrix.getTranslation();
    final offset = Offset(translation.x, translation.y);
    final bounded = _bound(viewport, offset, scale);
    return bounded == offset ? matrix : _matrix(scale, bounded);
  }

  Offset _bound(Size viewport, Offset offset, double scale) => Offset(
        offset.dx.clamp(viewport.width * (1 - scale), 0.0).toDouble(),
        offset.dy.clamp(viewport.height * (1 - scale), 0.0).toDouble(),
      );

  Matrix4 _matrix(double scale, Offset offset) =>
      Matrix4.diagonal3Values(scale, scale, 1)
        ..setTranslationRaw(offset.dx, offset.dy, 0);
}
