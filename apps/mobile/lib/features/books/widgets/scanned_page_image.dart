import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/shared/services/reader_appearance.dart';

/// Renders a scanned book page inside the reader-wide zoom canvas.
class ScannedPageImage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
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
                  color: tokens.accent,
                  strokeWidth: 2.5,
                ),
              ),
            ),
          ),
          errorWidget: (context, _, __) => Container(
            height: 120,
            decoration: BoxDecoration(
              color: appearance.surfaceVariant(tokens).withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              'Page image unavailable',
              style: TextStyle(
                color: appearance.mutedTextColor(tokens),
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
