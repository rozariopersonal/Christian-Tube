import 'package:flutter/material.dart';
import '../../core/models/video.dart';
import '../../shared/ui/search_video_card.dart';

class HistoryScreen extends StatelessWidget {
  final List<Video> history;

  const HistoryScreen({super.key, this.history = const []});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Watch History')),
      body: history.isEmpty
          ? const Center(child: Text('No watch history yet.'))
          : ListView.builder(
              itemCount: history.length,
              itemBuilder: (context, index) {
                return SearchVideoCard(video: history[index]);
              },
            ),
    );
  }
}
