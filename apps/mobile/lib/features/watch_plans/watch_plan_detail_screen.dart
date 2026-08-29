import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/video.dart';
import '../../core/models/watch_plan.dart';
import '../../core/api/api_client.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/ui/recommendation_video_card.dart';

class WatchPlanDetailScreen extends StatefulWidget {
  final WatchPlan plan;

  const WatchPlanDetailScreen({super.key, required this.plan});

  @override
  State<WatchPlanDetailScreen> createState() => _WatchPlanDetailScreenState();
}

class _WatchPlanDetailScreenState extends State<WatchPlanDetailScreen> {
  final ApiClient _apiClient = ApiClient();
  late List<Video> _videos;
  bool _isLoadingAutoVideos = false;

  @override
  void initState() {
    super.initState();
    _videos = List.from(widget.plan.queuedVideos);
    if (_videos.isEmpty) {
      _loadDefaultPlaylistVideos();
    }
  }

  Future<void> _loadDefaultPlaylistVideos() async {
    setState(() => _isLoadingAutoVideos = true);
    try {
      final response = await _apiClient.dio.get('/videos', queryParameters: {'limit': 10, 'type': 'VIDEO'});
      if (response.statusCode == 200 && response.data != null) {
        final dynamic raw = response.data;
        final List<dynamic> list = raw is List ? raw : (raw['videos'] ?? raw['data'] ?? []);
        if (mounted) {
          setState(() {
            _videos = list.whereType<Map<String, dynamic>>().map((v) => Video.fromJson(v)).toList();
          });
        }
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _isLoadingAutoVideos = false);
    }
  }

  void _startPlaylistPlayback(int startIndex) {
    if (_videos.isEmpty) return;
    final targetVideo = _videos[startIndex];
    context.push('/watch/${targetVideo.id}', extra: {
      'video': targetVideo,
      'playlist': _videos,
      'playlistTitle': widget.plan.title,
      'initialIndex': startIndex,
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(widget.plan.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.plan.title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (widget.plan.description != null)
            Text(widget.plan.description!, style: TextStyle(fontSize: 14, color: context.tokens.onSurfaceMuted)),
          const SizedBox(height: 16),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStat('Daily Goal', '${widget.plan.targetMinutesPerDay}m', theme.colorScheme.primary),
                  _buildStat('Streak', '${widget.plan.streakDays} days', context.tokens.accent),
                  _buildStat('Videos', '${_videos.length}', theme.colorScheme.tertiary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Play All as Playlist Button
          if (_videos.isNotEmpty)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => _startPlaylistPlayback(0),
              icon: const Icon(Icons.play_arrow_rounded, size: 24),
              label: Text(
                'Play All (${_videos.length} Videos)',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),

          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Playlist Queue', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text('${_videos.length} items', style: TextStyle(color: context.tokens.onSurfaceMuted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),

          if (_isLoadingAutoVideos)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          else if (_videos.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: context.tokens.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.tokens.surfaceBorder),
              ),
              child: Column(
                children: [
                  Icon(Icons.video_library_outlined, size: 48, color: context.tokens.onSurfaceDisabled),
                  const SizedBox(height: 8),
                  Text(
                    'No videos in playlist queue.\nTap "Save" on any video to add it here!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.tokens.onSurfaceMuted, fontSize: 13),
                  ),
                ],
              ),
            )
          else
            ..._videos.asMap().entries.map((entry) {
              final idx = entry.key;
              final v = entry.value;
              return RecommendationVideoCard(
                video: v,
                onTap: () => _startPlaylistPlayback(idx),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: context.tokens.onSurfaceMuted)),
      ],
    );
  }
}
