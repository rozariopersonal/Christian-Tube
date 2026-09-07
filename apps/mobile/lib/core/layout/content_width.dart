import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'adaptivity.dart';

/// Preferred readable measure for scrollable list/grid content.
///
/// Screens fill the full viewport up to this width, then content grows
/// proportionally (see [adaptiveContentMaxWidth]) on wide and ultra-wide
/// displays instead of leaving large side gutters.
const double kContentMaxWidth = 1600;

/// Absolute ceiling for content width on ultra-wide monitors (e.g. 3440px).
const double kUltraContentMaxWidth = 3200;

/// How fast content width grows beyond [kContentMaxWidth] as the viewport
/// grows. 1.0 fills the viewport edge-to-edge; lower values keep side air.
const double kUltraWidthSlope = 0.8;

/// Max width for pure text-reading surfaces (Bible reader, book reader)
/// where very long line lengths hurt readability.
const double kReadingMaxWidth = 1080;

/// Resolves the content max-width for a given viewport width so screens
/// adapt to the window:
///
/// - `compact`/`medium` and any width up to [kContentMaxWidth]: fills the
///   viewport (no artificial cap).
/// - Beyond that, content grows at [kUltraWidthSlope] the rate of the
///   viewport so ultra-wide monitors stay filled with breathing room, capped
///   at [kUltraContentMaxWidth].
///
/// Example widths (viewport → content): 1920 → 1856, 2560 → 2368,
/// 3440 → 3072, 3840 → 3200.
double adaptiveContentMaxWidth(double viewportWidth) {
  if (viewportWidth <= kContentMaxWidth) return viewportWidth;
  final grown =
      kContentMaxWidth + (viewportWidth - kContentMaxWidth) * kUltraWidthSlope;
  return math.min(grown, kUltraContentMaxWidth);
}

/// Centered, viewport-adaptive width constraint for content lists so
/// cards/text fill the screen comfortably on phones, tablets, web windows,
/// and ultra-wide displays (see [adaptiveContentMaxWidth]).
///
/// When [maxWidth] is omitted it is resolved from the incoming layout
/// constraints via [adaptiveContentMaxWidth]. Pass an explicit value to
/// override (e.g. [kReadingMaxWidth] for text readers). Exempt surfaces
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
        final resolved =
            maxWidth ?? adaptiveContentMaxWidth(constraints.maxWidth);
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