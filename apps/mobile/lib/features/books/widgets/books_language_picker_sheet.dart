import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../models/book_language_meta.dart';

/// An adaptive modal sheet for selecting a language in the Books Library.
///
/// Features native script subtitles, book count badges per language,
/// optional quick-search filtering, and a batch download action.
class BooksLanguagePickerSheet extends StatefulWidget {
  final String selectedLanguage;
  final List<String> availableLanguages;
  final Map<String, int> bookCounts;
  final ValueChanged<String> onLanguageSelected;
  final VoidCallback? onDownloadAll;

  const BooksLanguagePickerSheet({
    super.key,
    required this.selectedLanguage,
    required this.availableLanguages,
    required this.bookCounts,
    required this.onLanguageSelected,
    this.onDownloadAll,
  });

  @override
  State<BooksLanguagePickerSheet> createState() => _BooksLanguagePickerSheetState();
}

class _BooksLanguagePickerSheetState extends State<BooksLanguagePickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _filterQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final selectedLower = widget.selectedLanguage.toLowerCase();

    // Filter available languages based on search query
    final filteredLanguages = widget.availableLanguages.where((code) {
      if (_filterQuery.isEmpty) return true;
      final meta = BookLanguageMeta.fromCode(code);
      final q = _filterQuery.toLowerCase();
      return meta.englishName.toLowerCase().contains(q) ||
          meta.nativeName.toLowerCase().contains(q) ||
          code.toLowerCase().contains(q);
    }).toList();

    final activeMeta = BookLanguageMeta.fromCode(widget.selectedLanguage);
    final activeCount = widget.bookCounts[widget.selectedLanguage] ?? 0;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            // Drag Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: tokens.surfaceBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Header Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: tokens.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.translate_rounded, color: tokens.accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Library Language',
                          style: TextStyle(
                            color: tokens.onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        Text(
                          'Active: ${activeMeta.displayName} ($activeCount books)',
                          style: TextStyle(
                            color: tokens.onSurfaceMuted,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: tokens.onSurfaceMuted, size: 20),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Search filter if at least 6 languages
            if (widget.availableLanguages.length >= 6) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: tokens.surfaceVariant,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tokens.surfaceBorder),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: tokens.onSurface, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search language or script...',
                      hintStyle: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12.5),
                      prefixIcon: Icon(Icons.search, color: tokens.onSurfaceMuted, size: 17),
                      suffixIcon: _filterQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, color: tokens.onSurfaceMuted, size: 15),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _filterQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 9),
                    ),
                    onChanged: (val) => setState(() => _filterQuery = val.trim()),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 10),
            Divider(color: tokens.surfaceBorder, height: 1),

            // Languages List
            Flexible(
              child: filteredLanguages.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      child: Center(
                        child: Text(
                          'No matching language found',
                          style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 13),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      itemCount: filteredLanguages.length,
                      separatorBuilder: (_, __) => Divider(
                        color: tokens.surfaceBorder.withValues(alpha: 0.4),
                        height: 1,
                        indent: 56,
                        endIndent: 12,
                      ),
                      itemBuilder: (context, index) {
                        final code = filteredLanguages[index];
                        final meta = BookLanguageMeta.fromCode(code);
                        final isSelected = code.toLowerCase() == selectedLower;
                        final count = widget.bookCounts[code] ?? 0;

                        return Material(
                          color: isSelected
                              ? tokens.accent.withValues(alpha: 0.08)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              widget.onLanguageSelected(code);
                              Navigator.of(context).pop();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  // Language Code Badge
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? tokens.accent
                                          : tokens.surfaceVariant,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isSelected
                                            ? tokens.accent
                                            : tokens.surfaceBorder,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: code == 'All'
                                        ? Icon(
                                            Icons.all_inclusive_rounded,
                                            size: 18,
                                            color: isSelected
                                                ? Colors.white
                                                : tokens.onSurface,
                                          )
                                        : Text(
                                            code.toUpperCase(),
                                            style: TextStyle(
                                              color: isSelected
                                                  ? Colors.white
                                                  : tokens.onSurface,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                  ),
                                  const SizedBox(width: 14),

                                  // Language Names
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          meta.englishName,
                                          style: TextStyle(
                                            color: isSelected
                                                ? tokens.accent
                                                : tokens.onSurface,
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : FontWeight.w600,
                                            fontSize: 14.5,
                                          ),
                                        ),
                                        if (code != 'All' &&
                                            meta.nativeName.isNotEmpty &&
                                            meta.nativeName != meta.englishName)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2),
                                            child: Text(
                                              meta.nativeName,
                                              style: TextStyle(
                                                color: tokens.onSurfaceMuted,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),

                                  // Book count pill badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? tokens.accent.withValues(alpha: 0.15)
                                          : tokens.surfaceVariant,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected
                                            ? tokens.accent.withValues(alpha: 0.3)
                                            : tokens.surfaceBorder,
                                      ),
                                    ),
                                    child: Text(
                                      '$count books',
                                      style: TextStyle(
                                        color: isSelected
                                            ? tokens.accent
                                            : tokens.onSurfaceMuted,
                                        fontSize: 11,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Selection checkmark
                                  Icon(
                                    isSelected
                                        ? Icons.check_circle_rounded
                                        : Icons.circle_outlined,
                                    color: isSelected
                                        ? tokens.accent
                                        : tokens.onSurfaceDisabled.withValues(alpha: 0.5),
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Optional Download All action footer
            if (widget.onDownloadAll != null) ...[
              Divider(color: tokens.surfaceBorder, height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tokens.accent,
                    side: BorderSide(color: tokens.accent.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onDownloadAll!();
                  },
                  icon: const Icon(Icons.download_for_offline_outlined, size: 18),
                  label: Text(
                    widget.selectedLanguage == 'All'
                        ? 'Download All $activeCount Books Offline'
                        : 'Download All ${activeMeta.englishName} Books Offline',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
