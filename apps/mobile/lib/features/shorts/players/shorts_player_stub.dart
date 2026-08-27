import 'package:flutter/material.dart';
import '../../../core/models/short.dart';

void stopAllPlatformShorts() {}

Widget buildPlatformShortsPlayer({
  required Short short,
  required bool isPlaying,
}) {
  return Container(
    color: Colors.black,
    child: const Center(
      child: Icon(Icons.movie_outlined, color: Colors.white54, size: 48),
    ),
  );
}
