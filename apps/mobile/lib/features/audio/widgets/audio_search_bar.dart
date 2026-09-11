import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';

/// Inline real-time search bar for the Audio Library.
class AudioSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final String hintText;

  const AudioSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
    this.hintText = 'Search sermons, topics, speakers...',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);

    final hasQuery = controller.text.isNotEmpty;

    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: tokens.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: tokens.surfaceBorder.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: tokens.onSurface,
        ),
        textInputAction: TextInputAction.search,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: InputBorder.none,
          hintText: hintText,
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            color: tokens.onSurfaceMuted,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: tokens.onSurfaceMuted,
          ),
          suffixIcon: hasQuery
              ? IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: tokens.onSurfaceMuted,
                  ),
                  tooltip: 'Clear search',
                  onPressed: () {
                    controller.clear();
                    onClear();
                  },
                )
              : null,
        ),
      ),
    );
  }
}
