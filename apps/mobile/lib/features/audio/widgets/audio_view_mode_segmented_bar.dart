import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../controllers/audio_library_controller.dart';

/// Segmented view mode selector for browsing the Audio Library.
class AudioViewModeSegmentedBar extends StatelessWidget {
  final AudioViewMode currentMode;
  final ValueChanged<AudioViewMode> onModeChanged;

  const AudioViewModeSegmentedBar({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);

    final items = [
      (AudioViewMode.featured, 'Featured', Icons.auto_awesome_rounded),
      (AudioViewMode.byCategory, 'Categories', Icons.grid_view_rounded),
      (AudioViewMode.bySpeaker, 'Speakers', Icons.person_outline_rounded),
      (AudioViewMode.alphabetical, 'A–Z', Icons.sort_by_alpha_rounded),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: items.map((item) {
          final isSelected = currentMode == item.$1;
          final fgColor = isSelected
              ? theme.colorScheme.onPrimary
              : tokens.onSurfaceMuted;
          final bgColor = isSelected
              ? theme.colorScheme.primary
              : tokens.surfaceVariant;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: bgColor,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => onModeChanged(item.$1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(item.$3, size: 16, color: fgColor),
                      const SizedBox(width: 6),
                      Text(
                        item.$2,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: fgColor,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
