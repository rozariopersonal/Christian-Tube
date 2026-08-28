import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/models/short.dart';
import '../../../core/models/local_short_item.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/ui/channel_avatar.dart';

class ShortBottomDetails extends StatelessWidget {
  final Short short;
  final LocalShortItem? localItem;
  final bool areControlsVisible;
  final bool isScrubbing;
  final double currentPosition;
  final double totalDuration;
  final VoidCallback onStopAllPlatformShorts;
  final Function(String) onPushRoute;
  final VoidCallback onShowDetailsSheet;
  final Function(double) onPanStart;
  final Function(double) onPanUpdate;
  final Function(double) onPanEnd;

  const ShortBottomDetails({
    super.key,
    required this.short,
    this.localItem,
    required this.areControlsVisible,
    required this.isScrubbing,
    required this.currentPosition,
    required this.totalDuration,
    required this.onStopAllPlatformShorts,
    required this.onPushRoute,
    required this.onShowDetailsSheet,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !areControlsVisible && !isScrubbing,
      child: AnimatedOpacity(
        opacity: areControlsVisible || isScrubbing ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 20, top: 40),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Color(0xFA000000),
                Color(0xDD000000),
                Color(0x99000000),
                Color(0x88000000),
                Color(0x00000000),
              ],
              stops: [0.0, 0.50, 0.70, 0.88, 1.0],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Watch Full Sermon Deep Link Button
              if (short.sourceVideoId != null && short.sourceVideoId!.isNotEmpty) ...[
                GestureDetector(
                  onTap: () {
                    onStopAllPlatformShorts();
                    onPushRoute(
                      '/watch/${short.sourceVideoId}?start=${(short.clipStartTime ?? 0).toInt()}',
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_circle_fill, size: 16, color: Colors.black),
                        SizedBox(width: 6),
                        Text(
                          'Watch Full Sermon',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios, size: 10, color: Colors.black),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // Channel & Creator Attribution
              Row(
                children: [
                  ChannelAvatar(
                    avatarUrl: short.channelAvatarUrl,
                    channelTitle: short.channelTitle,
                    radius: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '@${short.channelTitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            shadows: [
                              Shadow(color: Colors.black, blurRadius: 4),
                            ],
                          ),
                        ),
                        if (short.creatorName != null && short.creatorName!.isNotEmpty)
                          Text(
                            '✂️ Clipped by ${short.creatorName}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              shadows: const [
                                Shadow(color: Colors.black, blurRadius: 4),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: onShowDetailsSheet,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        short.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          shadows: [
                            Shadow(color: Colors.black, blurRadius: 6),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'More',
                            style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(width: 2),
                          Icon(Icons.expand_more_rounded, size: 12, color: Colors.white70),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Mobile Interactive Playhead Track
              LayoutBuilder(
                builder: (context, constraints) {
                  final totalWidth = constraints.maxWidth;
                  final effectiveDuration = totalDuration > 0
                      ? totalDuration
                      : (short.durationSeconds > 0
                          ? short.durationSeconds.toDouble()
                          : 60.0);
                  final progressRatio = effectiveDuration > 0
                      ? (currentPosition / effectiveDuration).clamp(0.0, 1.0)
                      : 0.0;
                  final double thumbSize = isScrubbing ? 22.0 : 16.0;
                  final double trackHeight = isScrubbing ? 6.0 : 4.0;

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) {
                      HapticFeedback.selectionClick();
                      final localX = details.localPosition.dx.clamp(0.0, totalWidth);
                      onPanStart((localX / totalWidth) * effectiveDuration);
                    },
                    onPanUpdate: (details) {
                      final localX = details.localPosition.dx.clamp(0.0, totalWidth);
                      onPanUpdate((localX / totalWidth) * effectiveDuration);
                    },
                    onPanEnd: (details) {
                      HapticFeedback.lightImpact();
                      onPanEnd(currentPosition);
                    },
                    child: SizedBox(
                      height: 52,
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        clipBehavior: Clip.none,
                        children: [
                          // Floating Live Seek Time Bubble
                          if (isScrubbing)
                            Positioned(
                              left: (totalWidth * progressRatio - 28)
                                  .clamp(0.0, totalWidth - 56),
                              top: -24,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black54,
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  Formatters.formatDuration(
                                    Duration(seconds: currentPosition.toInt()),
                                  ),
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),

                          // Inactive Base Rail
                          Container(
                            height: trackHeight,
                            width: totalWidth,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),

                          // Active Played Progress Rail
                          AnimatedContainer(
                            duration: isScrubbing
                                ? Duration.zero
                                : const Duration(milliseconds: 100),
                            height: trackHeight,
                            width: totalWidth * progressRatio,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFFFBBF24),
                                  Color(0xFFF59E0B),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(3),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFF59E0B)
                                      .withValues(alpha: 0.6),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),

                          // Glowing Mobile Playhead Thumb
                          Positioned(
                            left: (totalWidth * progressRatio - (thumbSize / 2))
                                .clamp(0.0, totalWidth - thumbSize),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: thumbSize,
                              height: thumbSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                border: Border.all(
                                  color: const Color(0xFFF59E0B),
                                  width: isScrubbing ? 3.5 : 2.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFF59E0B).withValues(
                                      alpha: isScrubbing ? 0.8 : 0.4,
                                    ),
                                    blurRadius: isScrubbing ? 10 : 6,
                                    spreadRadius: isScrubbing ? 2 : 0,
                                  ),
                                  const BoxShadow(
                                    color: Colors.black54,
                                    blurRadius: 4,
                                    offset: Offset(0, 1),
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
              ),
              const SizedBox(height: 2),

              // Timestamps (Current / Total)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    Formatters.formatDuration(
                      Duration(seconds: currentPosition.toInt()),
                    ),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    Formatters.formatDuration(
                      Duration(
                        seconds: (totalDuration > 0
                                ? totalDuration
                                : (short.durationSeconds > 0
                                    ? short.durationSeconds.toDouble()
                                    : 60.0))
                            .toInt(),
                      ),
                    ),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
