import 'package:flutter/material.dart';

void pausePlatformMainVideo() {}
void resumePlatformMainVideo() {}

Widget buildPlatformVideoPlayer({
  required String videoId,
  double? startSeconds,
  ValueChanged<Duration>? onPositionChanged,
  bool isFullScreen = false,
  VoidCallback? onToggleFullScreen,
  required Widget Function(BuildContext context, Widget player) builder,
}) {
  return Builder(
    builder: (context) => builder(
      context,
      Container(color: Colors.black),
    ),
  );
}
