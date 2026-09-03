import 'package:flutter/material.dart';
import '../../../core/models/short.dart';
import '../../../core/models/local_short_item.dart';
import '../../../core/theme/app_tokens.dart';
import 'short_action_bar.dart';
import 'short_bottom_details.dart';

class ShortPlayerOverlay extends StatelessWidget {
  final bool isNonPlayableLocalShort;
  final bool showPlayPauseOverlay;
  final bool playPauseOverlayPlaying;
  final VoidCallback onScreenTap;
  final Widget? topStatusChip;
  final bool areControlsVisible;
  
  final Short short;
  final LocalShortItem? localItem;
  
  final VoidCallback onShare;
  
  final bool isScrubbing;
  final double currentPosition;
  final double totalDuration;
  final VoidCallback onStopAllPlatformShorts;
  final Function(String route) onPushRoute;
  final VoidCallback onShowDetailsSheet;
  final Function(double pos) onPanStart;
  final Function(double pos) onPanUpdate;
  final Function(double pos) onPanEnd;
  
  final double verticalRailHeightFactor;

  const ShortPlayerOverlay({
    super.key,
    required this.isNonPlayableLocalShort,
    required this.showPlayPauseOverlay,
    required this.playPauseOverlayPlaying,
    required this.onScreenTap,
    this.topStatusChip,
    required this.areControlsVisible,
    required this.short,
    this.localItem,
    required this.onShare,
    required this.isScrubbing,
    required this.currentPosition,
    required this.totalDuration,
    required this.onStopAllPlatformShorts,
    required this.onPushRoute,
    required this.onShowDetailsSheet,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.verticalRailHeightFactor,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 2. Full-Screen Tap Arena (Dynamic HUD Auto-Hide & Play/Pause & Double-Tap Bless)
        if (!isNonPlayableLocalShort)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onScreenTap,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const SizedBox.expand(),
                  // Play/Pause Animated Feedback Overlay
                  if (showPlayPauseOverlay)
                    AnimatedOpacity(
                      opacity: showPlayPauseOverlay ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: context.tokens.scrim.withValues(alpha: 0.4),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          playPauseOverlayPlaying ? Icons.play_arrow_rounded : Icons.pause_rounded,
                          size: 64,
                          color: context.tokens.onScrim.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

        // 2.5 Floating Status Chip (One-Line Indicator)
        if (topStatusChip != null && !isNonPlayableLocalShort)
          Positioned(
            top: 60,
            left: 16,
            right: 16,
            child: Center(
              child: topStatusChip,
            ),
          ),

        // 4. Bottom Smoothed Masking Overlay (Masks YouTube bottom logo & houses Playhead)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ShortBottomDetails(
            short: short,
            localItem: localItem,
            areControlsVisible: areControlsVisible,
            isScrubbing: isScrubbing,
            currentPosition: currentPosition,
            totalDuration: totalDuration,
            onStopAllPlatformShorts: onStopAllPlatformShorts,
            onPushRoute: onPushRoute,
            onShowDetailsSheet: onShowDetailsSheet,
            onPanStart: onPanStart,
            onPanUpdate: onPanUpdate,
            onPanEnd: onPanEnd,
          ),
        ),

        // 3. Floating Right Action Bar (Save, Sound, Share)
        // Moved after ShortBottomDetails in the Stack to guarantee it sits on top (z-index)
        Positioned(
          right: 14,
          bottom: 220, // Increased from 92 to ensure it sits above the bottom details panel
          child: IgnorePointer(
            ignoring: !areControlsVisible,
            child: AnimatedOpacity(
              opacity: areControlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: ShortActionBar(
                short: short,
                onShare: onShare,
              ),
            ),
          ),
        ),

        // 5. Vertical Position Rail
        if (!isNonPlayableLocalShort)
          Positioned(
            right: 2,
            top: MediaQuery.of(context).padding.top + 60,
            bottom: 250,
            child: IgnorePointer(
              ignoring: !areControlsVisible,
              child: AnimatedOpacity(
                opacity: areControlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: context.tokens.surfaceBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.topCenter,
                    heightFactor: verticalRailHeightFactor,
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
