import 'package:flutter/material.dart';
import '../../core/models/playlist.dart';
import '../../shared/ui/video_card.dart';

class PlaylistDetailScreen extends StatelessWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(playlist.title)),
      body: playlist.videos.isEmpty
          ? const Center(child: Text('No videos in this playlist yet.'))
          : ListView.builder(
              itemCount: playlist.videos.length,
              itemBuilder: (context, index) {
                return VideoCard(video: playlist.videos[index]);
              },
            ),
    );
  }
}
