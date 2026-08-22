import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class ChannelAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String channelTitle;
  final double radius;

  const ChannelAvatar({
    super.key,
    this.avatarUrl,
    required this.channelTitle,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.grey.shade300,
        backgroundImage: CachedNetworkImageProvider(avatarUrl!),
      );
    }

    final initial = channelTitle.isNotEmpty ? channelTitle[0].toUpperCase() : 'C';
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        initial,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontSize: radius * 0.9,
        ),
      ),
    );
  }
}
