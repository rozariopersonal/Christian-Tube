import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';

/// Reusable empty state view for search and filter results in Downloads tabs.
class DownloadEmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onResetFilters;
  final IconData icon;

  const DownloadEmptyState({
    super.key,
    this.title = 'No items found',
    this.subtitle = 'Try adjusting your search query or filter.',
    required this.onResetFilters,
    this.icon = Icons.search_off_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 48,
              color: tokens.onSurfaceMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                color: tokens.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: tokens.onSurfaceMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onResetFilters,
              child: const Text('Reset Filters'),
            ),
          ],
        ),
      ),
    );
  }
}
