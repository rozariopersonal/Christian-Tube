import 'package:flutter/material.dart';
import '../../../core/models/short.dart';

void stopAllPlatformShorts() {}
void pausePlatformShorts() {}
void resumePlatformShorts() {}
void loadPlatformShort(String videoId) {}

Widget buildPlatformShortsPlayer({
  required Short short,
  required bool isPlaying,
  ValueChanged<int>? onStateChange,
}) {
  return Container(
    color: Colors.black,
    child: const Center(
      child: Icon(Icons.movie_outlined, color: Colors.white54, size: 48),
    ),
  );
}
