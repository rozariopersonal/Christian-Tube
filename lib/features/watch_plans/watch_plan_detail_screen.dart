import 'package:flutter/material.dart';
import '../../core/models/watch_plan.dart';

class WatchPlanDetailScreen extends StatelessWidget {
  final WatchPlan plan;

  const WatchPlanDetailScreen({super.key, required this.plan});

  @override
  Widget build(BuildContext context) {
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
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStat('Daily Goal', '${plan.targetMinutesPerDay}m'),
                  _buildStat('Streak', '${plan.streakDays} days'),
                  _buildStat('Completed', '${plan.completedVideosCount}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Queued Devotionals', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          if (plan.queuedVideos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No videos in queue. Add videos from the Home feed!')),
            ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
