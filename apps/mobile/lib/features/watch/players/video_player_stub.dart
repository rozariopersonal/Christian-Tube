import 'package:flutter/material.dart';

Widget buildPlatformVideoPlayer({
  required String videoId,
  required Widget Function(BuildContext context, Widget player) builder,
}) {
  return Builder(
    builder: (context) => builder(
      context,
      Container(color: Colors.black),
    ),
  );
}
