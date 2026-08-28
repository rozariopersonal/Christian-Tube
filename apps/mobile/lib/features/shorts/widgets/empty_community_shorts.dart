import 'package:flutter/material.dart';
import '../../../core/config/app_config.dart';

class EmptyCommunityShorts extends StatelessWidget {
  final VoidCallback onRefresh;

  const EmptyCommunityShorts({
    super.key,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.movie_outlined, size: 64, color: Colors.white54),
          const SizedBox(height: 12),
          Text(
            'No ${AppConfig.appName} Shorts available',
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: onRefresh,
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}
