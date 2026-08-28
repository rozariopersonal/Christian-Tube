import 'package:flutter/material.dart';
import '../../../core/models/short.dart';

void stopAllPlatformShorts() {}
void pausePlatformShorts() {}
void resumePlatformShorts() {}
void seekPlatformShort(int slotIndex, double seconds) {}
void loadPlatformShort(String videoId) {}

Widget buildPlatformShortsPlayer({
  required Short short,
  required bool isPlaying,
  int slotIndex = 0,
  ValueChanged<int>? onStateChange,
  void Function(double current, double total)? onProgress,
}) {
  return Container(
    color: Colors.black,
    child: const Center(
      child: Icon(Icons.movie_outlined, color: Colors.white54, size: 48),
    ),
  );
}
