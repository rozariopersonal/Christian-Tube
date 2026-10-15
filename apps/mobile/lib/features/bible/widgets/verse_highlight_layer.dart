import 'dart:ui' show BoxHeightStyle;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../services/verse_band_geometry.dart';

/// A render object widget that paints continuous highlight bands behind
/// lines of text in its descendant [RenderParagraph], with roundedness
/// around the 4 outer corners of the highlight, without modifying or shifting
/// the text layout at all.
class VerseHighlightLayer extends SingleChildRenderObjectWidget {
  final Color? highlightColor;
  final bool isHovered;
  final Color? hoverColor;
  final BandWidthMode bandWidthMode;
  final double verticalBleed;
  final double cornerRadius;

  const VerseHighlightLayer({
    super.key,
    super.child,
    this.highlightColor,
    this.isHovered = false,
    this.hoverColor,
    this.bandWidthMode = BandWidthMode.tightText,
    this.verticalBleed = 4.0,
    this.cornerRadius = 6.0,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderVerseHighlightLayer(
      highlightColor: highlightColor,
      isHovered: isHovered,
      hoverColor: hoverColor,
      bandWidthMode: bandWidthMode,
      verticalBleed: verticalBleed,
      cornerRadius: cornerRadius,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, RenderVerseHighlightLayer renderObject) {
    renderObject
      ..highlightColor = highlightColor
      ..isHovered = isHovered
      ..hoverColor = hoverColor
      ..bandWidthMode = bandWidthMode
      ..verticalBleed = verticalBleed
      ..cornerRadius = cornerRadius;
  }
}

class RenderVerseHighlightLayer extends RenderProxyBox {
  Color? _highlightColor;
  bool _isHovered;
  Color? _hoverColor;
  BandWidthMode _bandWidthMode;
  double _verticalBleed;
  double _cornerRadius;

  RenderVerseHighlightLayer({
    Color? highlightColor,
    bool isHovered = false,
    Color? hoverColor,
    BandWidthMode bandWidthMode = BandWidthMode.tightText,
    double verticalBleed = 4.0,
    double cornerRadius = 6.0,
    RenderBox? child,
  })  : _highlightColor = highlightColor,
        _isHovered = isHovered,
        _hoverColor = hoverColor,
        _bandWidthMode = bandWidthMode,
        _verticalBleed = verticalBleed,
        _cornerRadius = cornerRadius,
        super(child);

  Color? get highlightColor => _highlightColor;
  set highlightColor(Color? value) {
    if (_highlightColor == value) return;
    _highlightColor = value;
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
    _clearBandCache();
    markNeedsPaint();
  }

  double get verticalBleed => _verticalBleed;
  set verticalBleed(double value) {
    if (_verticalBleed == value) return;
    _verticalBleed = value;
    _clearBandCache();
    markNeedsPaint();
  }

  double get cornerRadius => _cornerRadius;
  set cornerRadius(double value) {
    if (_cornerRadius == value) return;
    _cornerRadius = value;
    markNeedsPaint();
  }

  List<Rect>? _cachedBands;
  RenderParagraph? _cachedParagraph;
  double? _cachedWidth;
  Offset? _cachedParagraphOffset;

  void _clearBandCache() {
    _cachedBands = null;
    _cachedParagraph = null;
    _cachedWidth = null;
    _cachedParagraphOffset = null;
  }

  @override
  void performLayout() {
    super.performLayout();
    _clearBandCache();
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
    // 0. Instant early exit: if not highlighted and not hovered, skip text extraction and geometry calculations entirely
    final fillColor = _highlightColor ?? (_isHovered ? _hoverColor : null);
    if (fillColor == null) {
      super.paint(context, offset);
      return;
    }

    final paragraph = _cachedParagraph ??= _findParagraph(child);

    if (paragraph != null && paragraph.hasSize) {
      final textLength = paragraph.text.toPlainText().length;
      if (textLength > 0) {
        final columnWidth = size.width;
        if (_cachedBands == null || _cachedWidth != columnWidth) {
          final selection = TextSelection(baseOffset: 0, extentOffset: textLength);
          final rawBoxes = paragraph.getBoxesForSelection(
            selection,
            boxHeightStyle: BoxHeightStyle.max,
          );

          // Get offset of paragraph relative to this RenderObject
          _cachedParagraphOffset = paragraph.localToGlobal(Offset.zero, ancestor: this);
          _cachedBands = VerseBandGeometry.computeLineBands(
            rawBoxes,
            mode: _bandWidthMode,
            columnWidth: columnWidth,
            horizontalBleed: 5.0,
            topBleed: _highlightColor != null ? _verticalBleed : 0.0,
            bottomBleed: _highlightColor != null ? _verticalBleed : 0.0,
          );
          _cachedWidth = columnWidth;
        }

        final bands = _cachedBands!;
        final paragraphOffset = _cachedParagraphOffset ?? Offset.zero;
        final canvas = context.canvas;

        // 1. Draw Highlight Bands or Hover Background with rounded outer corners
        if (bands.isNotEmpty) {
          final paint = Paint()
            ..color = fillColor
            ..style = PaintingStyle.fill;

          final radius = Radius.circular(_cornerRadius);

          for (int i = 0; i < bands.length; i++) {
            final targetRect = bands[i].shift(offset + paragraphOffset);
            final isFirst = i == 0;
            final isLast = i == bands.length - 1;

            final rrect = RRect.fromRectAndCorners(
              targetRect,
              topLeft: isFirst ? radius : Radius.zero,
              topRight: isFirst ? radius : (isLast ? radius : Radius.zero),
              bottomLeft: isLast ? radius : Radius.zero,
              bottomRight: isLast ? radius : Radius.zero,
            );
            canvas.drawRRect(rrect, paint);
          }
        }

        // 2. Paint Child Content (the text and icons)
        super.paint(context, offset);
        return;
      }
    }

    super.paint(context, offset);
  }
}
