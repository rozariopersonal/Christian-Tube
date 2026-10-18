import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:mobile/core/layout/adaptivity.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/shared/services/reader_appearance.dart';
import 'widgets/font_browser_view.dart';
import 'widgets/font_family_tile.dart';
import 'widgets/font_size_stepper_slider.dart';
import 'widgets/line_spacing_selector.dart';
import 'widgets/text_formatting_bar.dart';

/// Shows the streamlined reading appearance sheet with formatting controls and
/// drill-down typography browser.
///
/// On `compact` screens this renders as a content-hugging bottom sheet (capped at 640px); on
/// `medium`/`expanded` as a centered dialog (per the Responsive & Adaptive UI Standard).
void showReaderAppearanceSheet(BuildContext context, ReaderAppearance appearance) {
  final tokens = context.tokens;
  final screen = ScreenClass.of(context);
  final sheetBg = appearance.surface(tokens);

  Widget buildSheetContent(BuildContext ctx, StateSetter setModalState, _SheetFlowState flowState) {
    final textCol = appearance.textColor(tokens);
    final mutedCol = appearance.mutedTextColor(tokens);
    final borderCol = appearance.surfaceBorder(tokens);

    final screenHeight = MediaQuery.sizeOf(ctx).height;
    final level2Height = math.min(
      screenHeight * 0.82,
      math.min(620.0, math.max(screenHeight * 0.70, 280.0)),
    );

    return SafeArea(
      top: false,
      bottom: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Anchored drag handle for compact screens (static across drill-down transitions)
            if (screen.isCompact) ...[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: borderCol,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],

            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.topCenter,
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                ),
                transitionBuilder: (child, animation) {
                  final isLevel2 = child.key == const ValueKey('level2');
                  final inFromRight = flowState.isDrillDown ? isLevel2 : !isLevel2;
                  final offset = inFromRight
                      ? Tween<Offset>(begin: const Offset(0.12, 0), end: Offset.zero)
                      : Tween<Offset>(begin: const Offset(-0.12, 0), end: Offset.zero);
                  return FadeTransition(
                    opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
                    child: SlideTransition(
                      position: offset.animate(
                        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                      ),
                      child: child,
                    ),
                  );
                },
                child: flowState.isDrillDown
                    ? SizedBox(
                        key: const ValueKey('level2'),
                        height: level2Height,
                        child: FontBrowserView(
                          appearance: appearance,
                          onBack: () => setModalState(() => flowState.isDrillDown = false),
                        ),
                      )
                    : SingleChildScrollView(
                        key: const ValueKey('level1'),
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Text(
                                    'Reading Appearance',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: textCol,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                if (!screen.isCompact)
                                  IconButton(
                                    icon: Icon(Icons.close, size: 20, color: mutedCol),
                                    onPressed: () => Navigator.of(ctx).pop(),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Formatting Bar: [ B ] [ I ] [ U ]
                            TextFormattingBar(appearance: appearance),
                            const SizedBox(height: 16),

                            // Font Family Tile (Level 1 Drill-Down Trigger)
                            FontFamilyTile(
                              appearance: appearance,
                              onTap: () => setModalState(() => flowState.isDrillDown = true),
                            ),
                            const SizedBox(height: 16),

                            // Font Size Stepper + Slider
                            FontSizeStepperSlider(appearance: appearance),
                            const SizedBox(height: 16),

                            // Line Spacing Selector (Tight, Standard, Relaxed)
                            LineSpacingSelector(appearance: appearance),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  final flowState = _SheetFlowState();

  if (screen.isCompact) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Center(
        heightFactor: 1.0,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 640,
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.90,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) => buildSheetContent(ctx, setModalState, flowState),
          ),
        ),
      ),
    );
  } else {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final screenHeight = MediaQuery.sizeOf(ctx).height;
        return Dialog(
          backgroundColor: sheetBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: math.min(screenHeight * 0.88, 620.0),
            ),
            child: StatefulBuilder(
              builder: (context, setModalState) => buildSheetContent(ctx, setModalState, flowState),
            ),
          ),
        );
      },
    );
  }
}

class _SheetFlowState {
  bool isDrillDown = false;
}
