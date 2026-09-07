import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';

/// Horizontally scrollable category filter chips for the Audio Library.
class AudioCategoryChips extends StatelessWidget {
  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelected;

  const AudioCategoryChips({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);

    return SizedBox(
      height: 40,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = selected == cat;
          return FilterChip(
            label: Text(cat),
            selected: isSelected,
            labelStyle: theme.textTheme.bodySmall?.copyWith(
              color: isSelected ? theme.colorScheme.onPrimary : tokens.onSurface,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
            selectedColor: theme.colorScheme.primary,
            backgroundColor: tokens.surfaceElevated,
            checkmarkColor: theme.colorScheme.onPrimary,
            side: BorderSide(
              color: isSelected ? theme.colorScheme.primary : tokens.surfaceBorder,
              width: 0.8,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            onSelected: (_) => onSelected(cat),
          );
        },
      ),
    );
  }
}