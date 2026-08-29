import 'package:flutter/material.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_tokens.dart';

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
          Icon(Icons.movie_outlined, size: 64, color: context.tokens.onSurfaceMuted),
          const SizedBox(height: 12),
          Text(
            'No ${AppConfig.appName} Shorts available',
            style: TextStyle(color: context.tokens.onSurface),
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
