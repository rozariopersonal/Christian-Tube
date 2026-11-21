import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/shared/services/reader_appearance.dart';

/// Displays a scanned book page with gesture zoom and browser controls.
class ScannedPageImage extends StatefulWidget {
  const ScannedPageImage({
    super.key,
    required this.imageUrl,
    required this.tokens,
    required this.appearance,
    this.maxWidth = 720,
  });

  final String imageUrl;
  final AppTokens tokens;
  final ReaderAppearance appearance;
  final double maxWidth;

  @override
  State<ScannedPageImage> createState() => _ScannedPageImageState();
}

class _ScannedPageImageState extends State<ScannedPageImage> {
  static const _minScale = 1.0;
  static const _maxScale = 4.0;
  final TransformationController _transformationController =
      TransformationController();
  double _scale = _minScale;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _setScale(double scale) {
    final nextScale = scale.clamp(_minScale, _maxScale).toDouble();
    _transformationController.value = Matrix4.identity()..scale(nextScale);
    setState(() => _scale = nextScale);
  }

  Widget _buildImage() => CachedNetworkImage(
    imageUrl: widget.imageUrl,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
    fadeInDuration: const Duration(milliseconds: 120),
    placeholder: (context, _) => SizedBox(
      height: 160,
      child: Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            color: widget.tokens.accent,
            strokeWidth: 2.5,
          ),
        ),
      ),
    ),
    errorWidget: (context, _, __) => Container(
      height: 120,
      decoration: BoxDecoration(
        color: widget.appearance
            .surfaceVariant(widget.tokens)
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        'Page image unavailable',
        style: TextStyle(
          color: widget.appearance.mutedTextColor(widget.tokens),
          fontSize: 12,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth.clamp(0.0, widget.maxWidth).toDouble()
            : widget.maxWidth;
        return Center(
          child: SizedBox(
            width: width,
            child: Stack(
              alignment: Alignment.topRight,
              children: [
                InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: _minScale,
                  maxScale: _maxScale,
                  onInteractionEnd: (_) {
                    final scale = _transformationController.value
                        .getMaxScaleOnAxis()
                        .clamp(_minScale, _maxScale)
                        .toDouble();
                    setState(() => _scale = scale);
                  },
                  child: SizedBox(width: width, child: _buildImage()),
                ),
                if (kIsWeb)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Material(
                      color: widget.tokens.surface.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(12),
                      elevation: 2,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Zoom out',
                            onPressed: _scale <= _minScale
                                ? null
                                : () => _setScale(_scale / 1.25),
                            icon: const Icon(Icons.remove),
                          ),
                          IconButton(
                            tooltip: 'Reset zoom',
                            onPressed: _scale == _minScale
                                ? null
                                : () => _setScale(_minScale),
                            icon: const Icon(Icons.fit_screen),
                          ),
                          IconButton(
                            tooltip: 'Zoom in',
                            onPressed: _scale >= _maxScale
                                ? null
                                : () => _setScale(_scale * 1.25),
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
