import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';

void pausePlatformMainVideo() {}
void resumePlatformMainVideo() {}
void seekPlatformMainVideoTo(double seconds) {}

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
      Container(color: context.tokens.scrim),
    ),
  );
}
