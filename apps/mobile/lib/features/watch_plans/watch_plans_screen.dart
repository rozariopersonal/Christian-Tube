import 'package:flutter/material.dart';
import '../../core/models/watch_plan.dart';
import 'watch_plan_detail_screen.dart';

class WatchPlansScreen extends StatelessWidget {
  const WatchPlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final mockPlans = [
      WatchPlan(
        id: '1',
        title: 'Morning Prayer & Worship',
        description: 'Start your morning with inspiring praise & scripture meditation.',
        targetMinutesPerDay: 15,
        completedVideosCount: 12,
        streakDays: 7,
        createdAt: DateTime.now().subtract(const Duration(days: 7)),
      ),
      WatchPlan(
        id: '2',
        title: 'Through the Gospels (30-Day Series)',
        description: 'Deep dive into the life and teachings of Jesus Christ.',
        targetMinutesPerDay: 20,
        completedVideosCount: 5,
        streakDays: 3,
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devotion & Watch Plans'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: mockPlans.length,
        itemBuilder: (context, index) {
          final plan = mockPlans[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (ctx) => WatchPlanDetailScreen(plan: plan)),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            plan.title,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.local_fire_department, size: 16, color: Colors.orange),
                              const SizedBox(width: 4),
                              Text('${plan.streakDays}d streak', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.brown)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (plan.description != null)
                      Text(plan.description!, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.timer_outlined, size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Text('${plan.targetMinutesPerDay} mins/day', style: const TextStyle(fontSize: 12)),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (ctx) => WatchPlanDetailScreen(plan: plan)),
                            );
                          },
                          child: const Text('Continue Plan →'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
