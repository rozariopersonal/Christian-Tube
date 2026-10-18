import 'dart:ui';
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'content_width.dart';

/// Unified bottom sheet shell adhering to the repository's Responsive & Adaptive
/// UI standard and M3 token system.
///
/// Features:
/// - Guaranteed bottom anchoring via `Align(alignment: Alignment.bottomCenter, heightFactor: 1.0)`
///   (prevents sheets from flying to the top of the viewport or expanding to 100% height).
/// - Clamped width (max 640dp on tablets/desktop, 100% on phones).
/// - Clamped height (max [maxHeightFactor] of screen height, default 88%).
/// - Automatic keyboard avoidance via [AnimatedPadding].
/// - Consistent glassmorphic frosted surface, 24dp top radius, and accessible drag handle.
class AdaptiveSheetFrame extends StatelessWidget {
  final Widget child;
  final Widget? header;
  final double maxHeightFactor;
  final double maxWidth;
  final bool showDragHandle;
  final EdgeInsetsGeometry contentPadding;
  final Color? backgroundColor;

  const AdaptiveSheetFrame({
    super.key,
    required this.child,
    this.header,
    this.maxHeightFactor = 0.88,
    this.maxWidth = kSheetMaxWidth,
    this.showDragHandle = true,
    this.contentPadding = EdgeInsets.zero,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isDark = context.isDark;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    final sheetBg = backgroundColor ??
        (isDark
            ? tokens.surface.withValues(alpha: 0.95)
            : tokens.surface.withValues(alpha: 0.98));

    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1.0,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: screenHeight * maxHeightFactor,
        ),
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(bottom: keyboardInset),
          child: Container(
            decoration: BoxDecoration(
              color: sheetBg,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(color: tokens.surfaceBorder, width: 1.0),
                left: BorderSide(color: tokens.surfaceBorder, width: 0.5),
                right: BorderSide(color: tokens.surfaceBorder, width: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: tokens.scrim
                      .withValues(alpha: isDark ? 0.40 : 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: contentPadding,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showDragHandle)
                          Center(
                            child: Container(
                              width: 38,
                              height: 4,
                              margin: const EdgeInsets.only(top: 12, bottom: 8),
                              decoration: BoxDecoration(
                                color: tokens.onSurfaceDisabled
                                    .withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        if (header != null) header!,
                        Flexible(child: child),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
