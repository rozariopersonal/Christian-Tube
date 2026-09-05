import 'package:flutter/material.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../models/book_language_meta.dart';
import 'books_language_picker_sheet.dart';

/// Special dropdown trigger widget for selecting a catalog language
/// in the Books Library.
///
/// Replaces horizontally scrolling chips with an elegant, compact
/// dropdown selector displaying the current language, native script,
/// active book count, and an adaptive bottom sheet selector.
class BooksLanguageDropdown extends StatelessWidget {
  final String selectedLanguage;
  final List<String> availableLanguages;
  final Map<String, int> bookCounts;
  final ValueChanged<String> onLanguageSelected;
  final VoidCallback? onDownloadAll;

  const BooksLanguageDropdown({
    super.key,
    required this.selectedLanguage,
    required this.availableLanguages,
    required this.bookCounts,
    required this.onLanguageSelected,
    this.onDownloadAll,
  });

  void _showLanguagePicker(BuildContext context) {
    showAdaptiveBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => BooksLanguagePickerSheet(
        selectedLanguage: selectedLanguage,
        availableLanguages: availableLanguages,
        bookCounts: bookCounts,
        onLanguageSelected: onLanguageSelected,
        onDownloadAll: onDownloadAll,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final meta = BookLanguageMeta.fromCode(selectedLanguage);
    final count = bookCounts[selectedLanguage] ?? 0;

    return Semantics(
      button: true,
      label: 'Change Books Library language. Currently selected: ${meta.displayName}',
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

                // Current Language Name & Native Name
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          meta.englishName,
                          style: TextStyle(
                            color: tokens.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (selectedLanguage != 'All' &&
                          meta.nativeName.isNotEmpty &&
                          meta.nativeName != meta.englishName) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            meta.nativeName,
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

                // Book count badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tokens.surfaceBorder),
                  ),
                  child: Text(
                    '$count ${count == 1 ? 'book' : 'books'}',
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
