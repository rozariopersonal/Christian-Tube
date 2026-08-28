import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
                final video = playlist.videos[index];
                return VideoCard(
                  video: video,
                  onTap: () {
                    context.push('/watch/${video.id}', extra: {
                      'video': video,
                      'playlist': playlist.videos,
                      'playlistTitle': playlist.title,
                      'initialIndex': index,
                    });
                  },
                );
              },
            ),
    );
  }
}

