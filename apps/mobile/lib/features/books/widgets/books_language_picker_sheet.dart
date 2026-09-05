import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../models/book_language_meta.dart';

/// An adaptive modal sheet for selecting one or multiple languages in the Books Library.
///
/// Features multi-selection checkboxes, native script subtitles,
/// book count badges per language, quick-search filtering, "Select All",
/// and an "Apply Selection" confirmation action.
class BooksLanguagePickerSheet extends StatefulWidget {
  final Set<String> selectedLanguages;
  final List<String> availableLanguages;
  final Map<String, int> bookCounts;
  final ValueChanged<Set<String>> onLanguagesSelected;
  final VoidCallback? onDownloadAll;

  const BooksLanguagePickerSheet({
    super.key,
    required this.selectedLanguages,
    required this.availableLanguages,
    required this.bookCounts,
    required this.onLanguagesSelected,
    this.onDownloadAll,
  });

  @override
  State<BooksLanguagePickerSheet> createState() => _BooksLanguagePickerSheetState();
}

class _BooksLanguagePickerSheetState extends State<BooksLanguagePickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  late Set<String> _currentSelection;
  String _filterQuery = '';

  @override
  void initState() {
    super.initState();
    _currentSelection = widget.selectedLanguages.isNotEmpty
        ? Set<String>.from(widget.selectedLanguages)
        : {'All'};
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isAllSelected() {
    return _currentSelection.isEmpty ||
        _currentSelection.any((l) => l.toLowerCase() == 'all');
  }

  void _toggleLanguage(String code) {
    setState(() {
      if (code.toLowerCase() == 'all') {
        _currentSelection = {'All'};
        return;
      }

      // If 'All' was selected, clear it and add this specific language
      if (_isAllSelected()) {
        _currentSelection = {code};
        return;
      }

      final normalizedCode = code;
      if (_currentSelection.any((l) => l.toLowerCase() == code.toLowerCase())) {
        _currentSelection.removeWhere((l) => l.toLowerCase() == code.toLowerCase());
        // If everything was deselected, default back to 'All'
        if (_currentSelection.isEmpty) {
          _currentSelection = {'All'};
        }
      } else {
        _currentSelection.add(normalizedCode);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _currentSelection = {'All'};
    });
  }

  int _calculateSelectedBooksCount() {
    if (_isAllSelected()) {
      return widget.bookCounts['All'] ?? 0;
    }
    int total = 0;
    for (final code in _currentSelection) {
      total += widget.bookCounts[code] ?? 0;
    }
    return total;
  }

  String _selectionSubtitle() {
    if (_isAllSelected()) {
      final total = widget.bookCounts['All'] ?? 0;
      return 'All Languages ($total books)';
    }
    final count = _currentSelection.length;
    final books = _calculateSelectedBooksCount();
    return '$count ${count == 1 ? 'Language' : 'Languages'} selected • $books books';
  }

  void _applyAndClose() {
    widget.onLanguagesSelected(_currentSelection);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isAll = _isAllSelected();

    // Filter available languages based on search query
    final filteredLanguages = widget.availableLanguages.where((code) {
      if (_filterQuery.isEmpty) return true;
      final meta = BookLanguageMeta.fromCode(code);
      final q = _filterQuery.toLowerCase();
      return meta.englishName.toLowerCase().contains(q) ||
          meta.nativeName.toLowerCase().contains(q) ||
          code.toLowerCase().contains(q);
    }).toList();

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
                          'Library Languages',
                          style: TextStyle(
                            color: tokens.onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        Text(
                          _selectionSubtitle(),
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
                  if (!isAll)
                    TextButton(
                      onPressed: _selectAll,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Select All',
                        style: TextStyle(
                          color: tokens.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
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
                  height: 44,
                  decoration: BoxDecoration(
                    color: tokens.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: tokens.surfaceBorder),
                  ),
                  alignment: Alignment.center,
                  child: TextField(
                    controller: _searchController,
                    textAlignVertical: TextAlignVertical.center,
                    style: TextStyle(color: tokens.onSurface, fontSize: 13.5),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search language or script...',
                      hintStyle: TextStyle(color: tokens.onSurfaceMuted, fontSize: 13),
                      prefixIcon: Icon(Icons.search, color: tokens.onSurfaceMuted, size: 18),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      suffixIcon: _filterQuery.isNotEmpty
                          ? IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                              icon: Icon(Icons.clear, color: tokens.onSurfaceMuted, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _filterQuery = '');
                              },
                            )
                          : null,
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
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
                        final isSelected = code.toLowerCase() == 'all'
                            ? isAll
                            : (!isAll &&
                                _currentSelection.any(
                                    (l) => l.toLowerCase() == code.toLowerCase()));
                        final count = widget.bookCounts[code] ?? 0;

                        return Material(
                          color: isSelected
                              ? tokens.accent.withValues(alpha: 0.08)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _toggleLanguage(code),
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
                                      crossAxisAlignment: CrossAxisAlignment.start,
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
                                            padding: const EdgeInsets.only(top: 2),
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
                                  const SizedBox(width: 10),

                                  // Multi-select Checkbox Icon
                                  Icon(
                                    isSelected
                                        ? Icons.check_box_rounded
                                        : Icons.check_box_outline_blank_rounded,
                                    color: isSelected
                                        ? tokens.accent
                                        : tokens.onSurfaceDisabled.withValues(alpha: 0.6),
                                    size: 22,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Footer Action: Apply Selection Button
            Divider(color: tokens.surfaceBorder, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: tokens.accent,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _applyAndClose,
                      icon: const Icon(Icons.done_all_rounded, size: 18),
                      label: Text(
                        isAll
                            ? 'Apply (All Languages)'
                            : 'Apply (${_currentSelection.length} Languages • ${_calculateSelectedBooksCount()} Books)',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
