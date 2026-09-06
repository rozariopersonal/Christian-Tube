import 'package:flutter/material.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../books/models/book_language_meta.dart';
import 'audio_language_picker_sheet.dart';

/// Dropdown trigger widget for selecting one or multiple catalog languages
/// in the Audio Library.
///
/// Displays the active language(s), native script if applicable, combined track count,
/// and opens an adaptive multi-select modal sheet.
class AudioLanguageDropdown extends StatelessWidget {
  final Set<String> selectedLanguages;
  final List<String> availableLanguages;
  final Map<String, int> trackCounts;
  final ValueChanged<Set<String>> onLanguagesSelected;

  const AudioLanguageDropdown({
    super.key,
    required this.selectedLanguages,
    required this.availableLanguages,
    required this.trackCounts,
    required this.onLanguagesSelected,
  });

  bool get _isAllSelected {
    return selectedLanguages.isEmpty ||
        selectedLanguages.any((l) => l.toLowerCase() == 'all');
  }

  void _showLanguagePicker(BuildContext context) {
    showAdaptiveBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => AudioLanguagePickerSheet(
        selectedLanguages: selectedLanguages,
        availableLanguages: availableLanguages,
        trackCounts: trackCounts,
        onLanguagesSelected: onLanguagesSelected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isAll = _isAllSelected;

    String titleText;
    String? subtitleText;
    int totalCount;

    if (isAll) {
      titleText = 'All Languages';
      subtitleText = null;
      totalCount = trackCounts['All'] ?? 0;
    } else if (selectedLanguages.length == 1) {
      final code = selectedLanguages.first;
      final meta = BookLanguageMeta.fromCode(code);
      titleText = meta.englishName;
      if (meta.nativeName.isNotEmpty && meta.nativeName != meta.englishName) {
        subtitleText = meta.nativeName;
      }
      totalCount = trackCounts[code] ?? trackCounts[meta.englishName] ?? 0;
    } else {
      final metas = selectedLanguages
          .map((c) => BookLanguageMeta.fromCode(c))
          .toList();
      if (metas.length == 2) {
        titleText = '${metas[0].englishName}, ${metas[1].englishName}';
      } else {
        titleText =
            '${metas[0].englishName}, ${metas[1].englishName} +${metas.length - 2}';
      }
      subtitleText = '${selectedLanguages.length} Languages';
      totalCount = selectedLanguages.fold(
        0,
        (sum, code) {
          final meta = BookLanguageMeta.fromCode(code);
          return sum + (trackCounts[code] ?? trackCounts[meta.englishName] ?? 0);
        },
      );
    }

    return Semantics(
      button: true,
      label: 'Filter audio by languages. Currently: $titleText ($totalCount tracks)',
      child: Material(
        color: tokens.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showLanguagePicker(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tokens.surfaceBorder),
            ),
            child: Row(
              children: [
                // Globe / Language Icon Badge
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: tokens.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.language_rounded,
                    color: tokens.accent,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),

                // Language Name & Native Name / Count
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          titleText,
                          style: TextStyle(
                            color: tokens.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (subtitleText != null) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            subtitleText,
                            style: TextStyle(
                              color: tokens.onSurfaceMuted,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Track count badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tokens.surfaceBorder),
                  ),
                  child: Text(
                    '$totalCount ${totalCount == 1 ? 'track' : 'tracks'}',
                    style: TextStyle(
                      color: tokens.onSurfaceMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                const SizedBox(width: 4),

                // Dropdown Chevron Indicator
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: tokens.onSurfaceMuted,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
