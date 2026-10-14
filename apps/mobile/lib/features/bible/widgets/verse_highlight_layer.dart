import 'dart:ui' show BoxHeightStyle;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../services/verse_band_geometry.dart';

/// A render object widget that paints highlight bands and selection underlines
/// behind and under lines of text in its descendant [RenderParagraph], without
/// modifying or shifting the text layout at all.
class VerseHighlightLayer extends SingleChildRenderObjectWidget {
  final Color? highlightColor;
  final bool showUnderline;
  final Color? underlineColor;
  final bool isHovered;
  final Color? hoverColor;
  final BandWidthMode bandWidthMode;
  final double verticalBleed;

  const VerseHighlightLayer({
    super.key,
    super.child,
    this.highlightColor,
    this.showUnderline = false,
    this.underlineColor,
    this.isHovered = false,
    this.hoverColor,
    this.bandWidthMode = BandWidthMode.tightText,
    this.verticalBleed = 6.0,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderVerseHighlightLayer(
      highlightColor: highlightColor,
      showUnderline: showUnderline,
      underlineColor: underlineColor,
      isHovered: isHovered,
      hoverColor: hoverColor,
      bandWidthMode: bandWidthMode,
      verticalBleed: verticalBleed,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, RenderVerseHighlightLayer renderObject) {
    renderObject
      ..highlightColor = highlightColor
      ..showUnderline = showUnderline
      ..underlineColor = underlineColor
      ..isHovered = isHovered
      ..hoverColor = hoverColor
      ..bandWidthMode = bandWidthMode
      ..verticalBleed = verticalBleed;
  }
}

class RenderVerseHighlightLayer extends RenderProxyBox {
  Color? _highlightColor;
  bool _showUnderline;
  Color? _underlineColor;
  bool _isHovered;
  Color? _hoverColor;
  BandWidthMode _bandWidthMode;
  double _verticalBleed;

  RenderVerseHighlightLayer({
    Color? highlightColor,
    bool showUnderline = false,
    Color? underlineColor,
    bool isHovered = false,
    Color? hoverColor,
    BandWidthMode bandWidthMode = BandWidthMode.tightText,
    double verticalBleed = 6.0,
    RenderBox? child,
  })  : _highlightColor = highlightColor,
        _showUnderline = showUnderline,
        _underlineColor = underlineColor,
        _isHovered = isHovered,
        _hoverColor = hoverColor,
        _bandWidthMode = bandWidthMode,
        _verticalBleed = verticalBleed,
        super(child);

  Color? get highlightColor => _highlightColor;
  set highlightColor(Color? value) {
    if (_highlightColor == value) return;
    _highlightColor = value;
    markNeedsPaint();
  }

  bool get showUnderline => _showUnderline;
  set showUnderline(bool value) {
    if (_showUnderline == value) return;
    _showUnderline = value;
    markNeedsPaint();
  }

  Color? get underlineColor => _underlineColor;
  set underlineColor(Color? value) {
    if (_underlineColor == value) return;
    _underlineColor = value;
    markNeedsPaint();
  }

  bool get isHovered => _isHovered;
  set isHovered(bool value) {
    if (_isHovered == value) return;
    _isHovered = value;
    markNeedsPaint();
  }

  Color? get hoverColor => _hoverColor;
  set hoverColor(Color? value) {
    if (_hoverColor == value) return;
    _hoverColor = value;
    markNeedsPaint();
  }

  BandWidthMode get bandWidthMode => _bandWidthMode;
  set bandWidthMode(BandWidthMode value) {
    if (_bandWidthMode == value) return;
    _bandWidthMode = value;
    markNeedsPaint();
  }

  double get verticalBleed => _verticalBleed;
  set verticalBleed(double value) {
    if (_verticalBleed == value) return;
    _verticalBleed = value;
    markNeedsPaint();
  }

  RenderParagraph? _findParagraph(RenderObject? node) {
    if (node == null) return null;
    if (node is RenderParagraph) return node;
    RenderParagraph? result;
    node.visitChildren((child) {
      result ??= _findParagraph(child);
    });
    return result;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final paragraph = _findParagraph(child);

    if (paragraph != null && paragraph.hasSize) {
      final textLength = paragraph.text.toPlainText().length;
      if (textLength > 0) {
        final selection = TextSelection(baseOffset: 0, extentOffset: textLength);
        final rawBoxes = paragraph.getBoxesForSelection(
          selection,
          boxHeightStyle: BoxHeightStyle.max,
        );

        // Get offset of paragraph relative to this RenderObject
        final paragraphOffset = paragraph.localToGlobal(Offset.zero, ancestor: this);

        final columnWidth = size.width;
        final bands = VerseBandGeometry.computeLineBands(
          rawBoxes,
          mode: _bandWidthMode,
          columnWidth: columnWidth,
          horizontalBleed: 5.0,
          topBleed: _highlightColor != null ? _verticalBleed : 0.0,
          bottomBleed: _highlightColor != null ? _verticalBleed : 0.0,
        );

        final canvas = context.canvas;

        // 1. Draw Highlight Bands or Hover Background
        final fillColor = _highlightColor ?? (_isHovered ? _hoverColor : null);
        if (fillColor != null && bands.isNotEmpty) {
          final paint = Paint()
            ..color = fillColor
            ..style = PaintingStyle.fill;

          for (final band in bands) {
            final targetRect = band.shift(offset + paragraphOffset);
            final rrect = RRect.fromRectAndRadius(targetRect, const Radius.circular(3.0));
            canvas.drawRRect(rrect, paint);
          }
        }

        // 2. Paint Child Content (the text and icons)
        super.paint(context, offset);

        // 3. Draw Dotted / Dashed Underline for Selection
        if (_showUnderline && bands.isNotEmpty) {
          final uColor = _underlineColor ?? _highlightColor ?? const Color(0xFF2196F3);
          final underlinePaint = Paint()
            ..color = uColor
            ..strokeWidth = 2.0
            ..style = PaintingStyle.stroke;

          for (final band in bands) {
            final targetRect = band.shift(offset + paragraphOffset);
            final y = targetRect.bottom - 1.0;
            final startX = targetRect.left + 2.0;
            final endX = targetRect.right - 2.0;

            if (endX > startX) {
              // Draw dashed line (YouVersion-style)
              const dashWidth = 4.0;
              const dashSpace = 3.0;
              double currentX = startX;
              while (currentX < endX) {
                final nextX = (currentX + dashWidth).clamp(startX, endX);
                canvas.drawLine(
                  Offset(currentX, y),
                  Offset(nextX, y),
                  underlinePaint,
                );
                currentX += dashWidth + dashSpace;
              }
            }
          }
        }
        return;
      }
    }

    super.paint(context, offset);
  }
}
