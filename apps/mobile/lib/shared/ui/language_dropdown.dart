import 'package:flutter/material.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import 'language_meta.dart';
import 'language_picker_sheet.dart';

/// Dropdown trigger widget for selecting one or multiple catalog languages.
///
/// Shared across content types (books, songs, articles, audio). Displays the
/// active language(s), native script if applicable, combined item count, and
/// opens an adaptive multi-select modal sheet.
class LanguageDropdown extends StatelessWidget {
  final Set<String> selectedLanguages;
  final List<String> availableLanguages;
  final Map<String, int> itemCounts;
  final ValueChanged<Set<String>> onLanguagesSelected;
  final String itemNoun;
  final String headerTitle;
  final int searchThreshold;
  final VoidCallback? onDownloadAll;

  const LanguageDropdown({
    super.key,
    required this.selectedLanguages,
    required this.availableLanguages,
    required this.itemCounts,
    required this.onLanguagesSelected,
    this.itemNoun = 'items',
    this.headerTitle = 'Library Languages',
    this.searchThreshold = 6,
    this.onDownloadAll,
  });

  bool get _isAllSelected {
    return selectedLanguages.isEmpty ||
        selectedLanguages.any((l) => l.toLowerCase() == 'all');
  }

  /// Languages this dropdown actually offers content for, so entries that only
  /// exist in another content type (zero item count and not currently
  /// selected) are not presented as empty, dead-end choices.
  List<String> _visibleLanguages() {
    if (availableLanguages.length <= 1) return availableLanguages;
    final result = <String>['All'];
    for (final code in availableLanguages) {
      if (code.toLowerCase() == 'all') continue;
      if ((itemCounts[code] ?? 0) > 0 ||
          selectedLanguages.any((s) => s.toLowerCase() == code.toLowerCase())) {
        result.add(code);
      }
    }
    return result;
  }

  void _showLanguagePicker(BuildContext context) {
    showAdaptiveBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => LanguagePickerSheet(
        selectedLanguages: selectedLanguages,
        availableLanguages: _visibleLanguages(),
        itemCounts: itemCounts,
        onLanguagesSelected: onLanguagesSelected,
        itemNoun: itemNoun,
        headerTitle: headerTitle,
        searchThreshold: searchThreshold,
        onDownloadAll: onDownloadAll,
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
      totalCount = itemCounts['All'] ?? 0;
    } else if (selectedLanguages.length == 1) {
      final code = selectedLanguages.first;
      final meta = LanguageMeta.fromCode(code);
      titleText = meta.englishName;
      if (meta.nativeName.isNotEmpty && meta.nativeName != meta.englishName) {
        subtitleText = meta.nativeName;
      }
      totalCount = itemCounts[code] ?? 0;
    } else {
      final metas =
          selectedLanguages.map((c) => LanguageMeta.fromCode(c)).toList();
      if (metas.length == 2) {
        titleText = '${metas[0].englishName}, ${metas[1].englishName}';
      } else {
        titleText =
            '${metas[0].englishName}, ${metas[1].englishName} +${metas.length - 2}';
      }
      subtitleText = '${selectedLanguages.length} Languages';
      totalCount = selectedLanguages.fold(
        0,
        (sum, code) => sum + (itemCounts[code] ?? 0),
      );
    }

    return Semantics(
      button: true,
      label:
          'Filter library by languages. Currently: $titleText ($totalCount $itemNoun)',
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

                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tokens.surfaceBorder),
                  ),
                  child: Text(
                    '$totalCount ${countNoun(itemNoun, totalCount)}',
                    style: TextStyle(
                      color: tokens.onSurfaceMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                const SizedBox(width: 4),

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
