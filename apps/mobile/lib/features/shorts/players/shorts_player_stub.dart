import 'package:flutter/material.dart';
import '../../../core/models/short.dart';
import '../../../core/theme/app_tokens.dart';

void stopAllPlatformShorts() {}
void pausePlatformShorts() {}
void resumePlatformShorts() {}
void seekPlatformShort(int slotIndex, double seconds) {}
void loadPlatformShort(String videoId) {}

Widget buildPlatformShortsPlayer({
  required BuildContext context,
  required Short short,
  required bool isPlaying,
  int slotIndex = 0,
  ValueChanged<int>? onStateChange,
  void Function(double current, double total)? onProgress,
}) {
  final tokens = context.tokens;
  return Container(
    color: tokens.scrim,
    child: Center(
      child: Icon(Icons.movie_outlined, color: tokens.onScrimMuted, size: 48),
    ),
  );
}
