import 'dart:math' as math;
import 'package:flutter/painting.dart';

enum BandWidthMode {
  /// Each line's highlight band bounds exactly wrap the text in that line,
  /// with horizontal bleed applied.
  tightText,

  /// Each line's band spans the full available width of the column.
  fullWidth,
}

/// Geometry helper to convert [TextBox] list (from [RenderParagraph.getBoxesForSelection])
/// into clean, gap-free, continuous horizontal bands per line for highlights and selections.
class VerseBandGeometry {
  const VerseBandGeometry._();

  /// Groups raw [boxes] into per-line bands.
  ///
  /// - Lines are grouped based on vertical overlap.
  /// - Gaps between consecutive lines are bridged so highlights look continuous.
  /// - [horizontalBleed] extends left and right edges slightly for breathing room.
  /// - [topBleed] and [bottomBleed] extend the first and last line bands to meet adjacent verse rows.
  static List<Rect> computeLineBands(
    List<TextBox> boxes, {
    BandWidthMode mode = BandWidthMode.tightText,
    double columnWidth = 0.0,
    double horizontalBleed = 4.0,
    double topBleed = 0.0,
    double bottomBleed = 0.0,
  }) {
    if (boxes.isEmpty) return const [];

    // Filter out degenerate boxes
    final validBoxes = boxes.where((b) => b.toRect().width > 0 && b.toRect().height > 0).toList();
    if (validBoxes.isEmpty) return const [];

    // Group boxes into lines
    final lines = <List<Rect>>[];
    for (final box in validBoxes) {
      final rect = box.toRect();
      bool added = false;
      for (final line in lines) {
        final lineTop = line.first.top;
        final lineHeight = line.first.height;
        final midY = rect.top + rect.height / 2;
        if (midY >= lineTop && midY <= lineTop + lineHeight) {
          line.add(rect);
          added = true;
          break;
        }
      }
      if (!added) {
        lines.add([rect]);
      }
    }

    // Sort lines from top to bottom
    lines.sort((a, b) => a.first.top.compareTo(b.first.top));

    final bands = <Rect>[];
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      double minLeft = double.infinity;
      double maxRight = -double.infinity;
      double minTop = double.infinity;
      double maxBottom = -double.infinity;

      for (final r in line) {
        if (r.left < minLeft) minLeft = r.left;
        if (r.right > maxRight) maxRight = r.right;
        if (r.top < minTop) minTop = r.top;
        if (r.bottom > maxBottom) maxBottom = r.bottom;
      }

      if (mode == BandWidthMode.fullWidth && columnWidth > 0) {
        minLeft = 0;
        maxRight = columnWidth;
      } else {
        minLeft = math.max(0.0, minLeft - horizontalBleed);
        if (columnWidth > 0) {
          maxRight = math.min(columnWidth, maxRight + horizontalBleed);
        } else {
          maxRight = maxRight + horizontalBleed;
        }
      }

      bands.add(Rect.fromLTRB(minLeft, minTop, maxRight, maxBottom));
    }

    if (bands.isEmpty) return const [];

    // Close vertical gaps between consecutive lines so they touch smoothly
    final adjustedBands = <Rect>[];
    for (int i = 0; i < bands.length; i++) {
      var current = bands[i];
      double top = current.top;
      double bottom = current.bottom;

      if (i == 0) {
        top -= topBleed;
      }
      if (i > 0) {
        final prev = adjustedBands[i - 1];
        // Bridge gap between prev and current
        if (top > prev.bottom) {
          final mid = (top + prev.bottom) / 2;
          adjustedBands[i - 1] = Rect.fromLTRB(prev.left, prev.top, prev.right, mid);
          top = mid;
        }
      }
      if (i == bands.length - 1) {
        bottom += bottomBleed;
      }

      adjustedBands.add(Rect.fromLTRB(current.left, top, current.right, bottom));
    }

    return adjustedBands;
  }
}
