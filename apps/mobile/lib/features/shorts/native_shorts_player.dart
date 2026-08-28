import 'package:flutter/material.dart';
import '../../core/models/short.dart';
import 'players/shorts_player.dart';

class NativeShortsPlayer extends StatelessWidget {
  final Short short;
  final bool isPlaying;
  final ValueChanged<int>? onStateChange;

  const NativeShortsPlayer({
    super.key,
    required this.short,
    required this.isPlaying,
    this.onStateChange,
  });

  @override
  Widget build(BuildContext context) {
    return buildPlatformShortsPlayer(
      short: short,
      isPlaying: isPlaying,
      onStateChange: onStateChange,
    );
  }
}
