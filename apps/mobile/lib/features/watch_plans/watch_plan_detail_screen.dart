import 'package:flutter/material.dart';
import '../../core/models/watch_plan.dart';
import '../../shared/ui/recommendation_video_card.dart';

class WatchPlanDetailScreen extends StatelessWidget {
  final WatchPlan plan;

  const WatchPlanDetailScreen({super.key, required this.plan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(plan.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            plan.title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (plan.description != null)
            Text(plan.description!, style: const TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 16),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStat('Daily Goal', '${plan.targetMinutesPerDay}m', theme.colorScheme.primary),
                  _buildStat('Streak', '${plan.streakDays} days', Colors.orange.shade800),
                  _buildStat('Completed', '${plan.completedVideosCount}', Colors.green.shade700),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Queued Videos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          if (plan.queuedVideos.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  Icon(Icons.video_library_outlined, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  const Text(
                    'No videos in queue yet.\nTap "Save to Watch Plan" on any video to queue it!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            )
          else
            ...plan.queuedVideos.map((v) => RecommendationVideoCard(video: v)),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
