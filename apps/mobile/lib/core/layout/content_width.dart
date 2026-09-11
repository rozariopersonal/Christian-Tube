import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'adaptivity.dart';

/// Preferred readable measure for scrollable list/grid content.
///
/// Lists and card grids are constrained to this width, centered, per the
/// Responsive & Adaptive UI Standard (max content width 1080px).
const double kContentMaxWidth = 1080;

/// Absolute ceiling for exempt wide surfaces (video players, shorts grids)
/// that explicitly opt into wide fill on ultra-wide monitors (e.g. 3440px).
const double kUltraContentMaxWidth = 1600;

/// How fast content width grows beyond [kContentMaxWidth] as the viewport
/// grows. 1.0 fills the viewport edge-to-edge; lower values keep side air.
const double kUltraWidthSlope = 0.5;

/// Max width for pure text-reading surfaces (Bible reader, book reader)
/// where very long line lengths hurt readability.
const double kReadingMaxWidth = 1080;

/// Resolves an optional wide-fill content width for exempt surfaces
/// (video players, shorts grids) that explicitly opt into filling wide/ultra-
/// wide monitors instead of the [kContentMaxWidth] readable cap.
///
/// - Widths up to [kContentMaxWidth]: fills the viewport (no artificial cap).
/// - Beyond that, content grows at [kUltraWidthSlope] the rate of the
///   viewport so ultra-wide monitors stay filled with breathing room, capped
///   at [kUltraContentMaxWidth].
///
/// Example widths (viewport → content): 1920 → 1500, 2560 → 1600 (capped),
/// 3440 → 1600 (capped), 3840 → 1600 (capped).
double adaptiveContentMaxWidth(double viewportWidth) {
  if (viewportWidth <= kContentMaxWidth) return viewportWidth;
  final grown =
      kContentMaxWidth + (viewportWidth - kContentMaxWidth) * kUltraWidthSlope;
  return math.min(grown, kUltraContentMaxWidth);
}

/// Centered, [kContentMaxWidth]-capped width constraint for content lists so
/// cards/text fill the screen on phones and tablets while staying readable on
/// wide/ultra-wide displays.
///
/// When [maxWidth] is omitted the readable cap [kContentMaxWidth] applies.
/// Pass an explicit value to override (e.g. [kReadingMaxWidth] for text
/// readers, [adaptiveContentMaxWidth] for exempt surfaces). Exempt surfaces
/// (video players, shorts grids, scripture cards) must use their own grid
/// rules; this is for text/card lists.
class MaxWidthBox extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsetsGeometry padding;
  final AlignmentGeometry alignment;
  final double? heightFactor;

  const MaxWidthBox({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding = EdgeInsets.zero,
    this.alignment = Alignment.topCenter,
    this.heightFactor,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final resolved = maxWidth ?? kContentMaxWidth;
        return Align(
          alignment: alignment,
          heightFactor: heightFactor,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: resolved),
            child: Padding(padding: padding, child: child),
          ),
        );
      },
    );
  }
}

/// Max width for modal bottom sheets on `medium`+ screens.
const double kSheetMaxWidth = 640;

/// `showModalBottomSheet` that honors the adaptive rule: on `compact` the
/// sheet behaves exactly as before; on `medium`/`expanded` the sheet body is
/// capped at [kSheetMaxWidth] and centered over the viewport.
///
/// Call this wherever a bottom sheet is shown from shared content so the
/// app-wide rule is applied consistently.
Future<T?> showAdaptiveBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  Color? backgroundColor,
  Color? barrierColor,
  ShapeBorder? shape,
  bool isDismissible = true,
  bool isEnableDrag = true,
}) {
  if (ScreenClass.of(context).isCompact) {
    return showModalBottomSheet<T>(
      context: context,
      builder: builder,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      backgroundColor: backgroundColor,
      barrierColor: barrierColor,
      shape: shape,
      isDismissible: isDismissible,
      enableDrag: isEnableDrag,
    );
  }

  return showModalBottomSheet<T>(
    context: context,
    builder: (sheetContext) {
      final child = Builder(builder: builder);
      return Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kSheetMaxWidth),
          child: child,
        ),
      );
    },
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    backgroundColor: backgroundColor,
    barrierColor: barrierColor,
    shape: shape,
    isDismissible: isDismissible,
    enableDrag: isEnableDrag,
  );
}
