import 'package:flutter/material.dart';
import '../../../core/services/bottom_bar_visibility_service.dart';
import '../../../core/theme/app_tokens.dart';
import 'voice_feedback_sheet.dart';

class FloatingFeedbackButton extends StatefulWidget {
  const FloatingFeedbackButton({super.key});

  @override
  State<FloatingFeedbackButton> createState() => _FloatingFeedbackButtonState();
}

class _FloatingFeedbackButtonState extends State<FloatingFeedbackButton> {
  double? _top;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        VoiceFeedbackSheet.isSheetOpen,
        BottomBarVisibilityService.instance,
      ]),
      builder: (context, _) {
        if (VoiceFeedbackSheet.isSheetOpen.value ||
            BottomBarVisibilityService.instance.isShortPlaying ||
            BottomBarVisibilityService.instance.isExplicitlyHidden) {
          return const SizedBox.shrink();
        }

        final tokens = context.tokens;
        final size = MediaQuery.sizeOf(context);
        final defaultTop = size.height * 0.65;
        final topPos = _top ?? defaultTop;

        return Positioned(
          right: 12,
          top: topPos.clamp(80.0, size.height - 140.0),
          child: GestureDetector(
            onVerticalDragUpdate: (details) {
              setState(() {
                _top = (topPos + details.delta.dy).clamp(80.0, size.height - 140.0);
              });
            },
            child: Material(
              color: Colors.transparent,
              elevation: 6,
              shadowColor: tokens.scrim.withValues(alpha: 0.4),
              shape: const CircleBorder(),
              child: InkWell(
                onTap: () => VoiceFeedbackSheet.show(context),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tokens.surfaceVariant.withValues(alpha: 0.95),
                    border: Border.all(
                      color: tokens.accent.withValues(alpha: 0.7),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: tokens.accent.withValues(alpha: 0.25),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      Icons.mic,
                      color: tokens.accent,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
