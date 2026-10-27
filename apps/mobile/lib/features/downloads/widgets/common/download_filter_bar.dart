import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';

/// Reusable search bar and category filter chips row for Downloads tabs.
class DownloadFilterBar extends StatelessWidget {
  final TextEditingController searchController;
  final String searchHint;
  final ValueChanged<String> onSearchChanged;
  final Iterable<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;
  final bool onlyInstalled;
  final VoidCallback onToggleOnlyInstalled;
  final String onlyInstalledLabel;

  const DownloadFilterBar({
    super.key,
    required this.searchController,
    required this.searchHint,
    required this.onSearchChanged,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
    required this.onlyInstalled,
    required this.onToggleOnlyInstalled,
    this.onlyInstalledLabel = 'Downloaded Only',
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search TextField
        TextField(
          controller: searchController,
          onChanged: onSearchChanged,
          style: TextStyle(color: tokens.onSurface, fontSize: 14),
          decoration: InputDecoration(
            hintText: searchHint,
            hintStyle: TextStyle(color: tokens.onSurfaceMuted, fontSize: 13),
            prefixIcon: Icon(Icons.search, color: tokens.onSurfaceMuted, size: 20),
            suffixIcon: searchController.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear, color: tokens.onSurfaceMuted, size: 18),
                    onPressed: () {
                      searchController.clear();
                      onSearchChanged('');
                    },
                  )
                : null,
            isDense: true,
            filled: true,
            fillColor: tokens.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: tokens.surfaceBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: tokens.surfaceBorder),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Horizontally Scrollable Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final cat in categories)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(cat),
                    selected: selectedCategory == cat,
                    onSelected: (_) => onCategorySelected(cat),
                    selectedColor: tokens.accent.withValues(alpha: 0.2),
                    checkmarkColor: tokens.accent,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: selectedCategory == cat
                          ? tokens.accent
                          : tokens.onSurfaceMuted,
                      fontWeight: selectedCategory == cat
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              FilterChip(
                avatar: Icon(
                  Icons.download_done_rounded,
                  size: 16,
                  color: onlyInstalled ? tokens.accent : tokens.onSurfaceMuted,
                ),
                label: Text(onlyInstalledLabel),
                selected: onlyInstalled,
                onSelected: (_) => onToggleOnlyInstalled(),
                selectedColor: tokens.accent.withValues(alpha: 0.2),
                checkmarkColor: tokens.accent,
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: onlyInstalled ? tokens.accent : tokens.onSurfaceMuted,
                  fontWeight: onlyInstalled ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
