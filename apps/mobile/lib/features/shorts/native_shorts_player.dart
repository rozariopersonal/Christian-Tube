import 'package:flutter/material.dart';
import '../../core/models/short.dart';
import 'players/shorts_player.dart';

class NativeShortsPlayer extends StatelessWidget {
  final Short short;
  final bool isPlaying;
  final int slotIndex;
  final ValueChanged<int>? onStateChange;
  final void Function(double current, double total)? onProgress;

  const NativeShortsPlayer({
    super.key,
    required this.short,
    required this.isPlaying,
    this.slotIndex = 0,
    this.onStateChange,
    this.onProgress,
  });

  @override
  Widget build(BuildContext context) {
    return buildPlatformShortsPlayer(
      short: short,
      isPlaying: isPlaying,
      slotIndex: slotIndex,
      onStateChange: onStateChange,
      onProgress: onProgress,
    );
  }
}
