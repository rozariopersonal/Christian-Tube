import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';

/// Standard section header for shelves and grouped content across the Library.
class LibrarySectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback? onViewAll;
  final String viewAllText;

  const LibrarySectionHeader({
    super.key,
    required this.title,
    required this.icon,
    this.onViewAll,
    this.viewAllText = 'View all',
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: [
          Flexible(
            child: Row(
              children: [
                Icon(icon, color: tokens.accent, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: tokens.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (onViewAll != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onViewAll,
              style: TextButton.styleFrom(
                foregroundColor: tokens.accent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                viewAllText,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: tokens.accent,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
