import 'package:flutter/material.dart';
import 'adaptivity.dart';

/// Max readable measure for scrollable content lists.
const double kContentMaxWidth = 1080;

/// Max width for modal bottom sheets on `medium`+ screens.
const double kSheetMaxWidth = 640;

/// Centered width constraint for content lists so cards/text do not stretch
/// edge-to-edge on tablets and wide web windows.
///
/// Exempt surfaces (video players, shorts grids, scripture cards) must use
/// their own grid rules; this is for text/card lists.
class MaxWidthBox extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final AlignmentGeometry alignment;
  final double? heightFactor;

  const MaxWidthBox({
    super.key,
    required this.child,
    this.maxWidth = kContentMaxWidth,
    this.padding = EdgeInsets.zero,
    this.alignment = Alignment.topCenter,
    this.heightFactor,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      heightFactor: heightFactor,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

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