import 'package:flutter/material.dart';
import '../../../core/models/video.dart';

class AddToWatchPlanBottomSheet extends StatelessWidget {
  final Video video;

  const AddToWatchPlanBottomSheet({super.key, required this.video});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add to Daily Devotion / Watch Plan',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.wb_sunny_outlined, color: Colors.orange),
            title: const Text('Morning Devotion (15 mins)'),
            subtitle: const Text('Streak: 5 days'),
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Added to Morning Devotion!')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.nights_stay_outlined, color: Colors.indigo),
            title: const Text('Evening Reflection'),
            subtitle: const Text('Streak: 3 days'),
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Added to Evening Reflection!')),
              );
            },
          ),
        ],
      ),
    );
  }
}
