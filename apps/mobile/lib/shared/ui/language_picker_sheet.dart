import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../services/library_languages_controller.dart';
import 'language_list_tile.dart';
import 'language_meta.dart';

sealed class _PickerEntry {}

class _LanguageEntry extends _PickerEntry {
  final String code;
  _LanguageEntry(this.code);
}

class _HeaderEntry extends _PickerEntry {
  final String title;
  final IconData icon;
  _HeaderEntry(this.title, this.icon);
}

/// An adaptive modal sheet for selecting one or multiple catalog languages.
///
/// Shared across content types (books, songs, articles, audio). Features
/// multi-selection checkboxes, native script subtitles, per-language item
/// counts, quick-search filtering, "Select All", and an "Apply Selection"
/// confirmation action.
class LanguagePickerSheet extends StatefulWidget {
  final Set<String> selectedLanguages;
  final List<String> availableLanguages;
  final Map<String, int> itemCounts;
  final ValueChanged<Set<String>> onLanguagesSelected;
  final String itemNoun;
  final String headerTitle;
  final int searchThreshold;
  final VoidCallback? onDownloadAll;

  const LanguagePickerSheet({
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

  @override
  State<LanguagePickerSheet> createState() => _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends State<LanguagePickerSheet> {
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

      if (_isAllSelected()) {
        _currentSelection = {code};
        return;
      }

      final normalizedCode = code;
      if (_currentSelection.any(
          (l) => l.toLowerCase() == code.toLowerCase())) {
        _currentSelection.removeWhere(
            (l) => l.toLowerCase() == code.toLowerCase());
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

  int _calculateSelectedCount() {
    if (_isAllSelected()) {
      return widget.itemCounts['All'] ?? 0;
    }
    int total = 0;
    for (final code in _currentSelection) {
      total += widget.itemCounts[code] ?? 0;
    }
    return total;
  }

  String _selectionSubtitle() {
    if (_isAllSelected()) {
      final total = widget.itemCounts['All'] ?? 0;
      return 'All Languages ($total ${countNoun(widget.itemNoun, total)})';
    }
    final count = _currentSelection.length;
    final items = _calculateSelectedCount();
    return '$count ${count == 1 ? 'Language' : 'Languages'} selected • '
        '$items ${countNoun(widget.itemNoun, items)}';
  }

  void _applyAndClose() {
    widget.onLanguagesSelected(_currentSelection);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isAll = _isAllSelected();

    final filteredLanguages = widget.availableLanguages.where((code) {
      if (_filterQuery.isEmpty) return true;
      final meta = LanguageMeta.fromCode(code);
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
                    child: Icon(Icons.translate_rounded,
                        color: tokens.accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.headerTitle,
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
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
                    icon:
                        Icon(Icons.close, color: tokens.onSurfaceMuted, size: 20),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            if (widget.availableLanguages.length >= widget.searchThreshold) ...[
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
                    style:
                        TextStyle(color: tokens.onSurface, fontSize: 13.5),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search language or script...',
                      hintStyle: TextStyle(
                          color: tokens.onSurfaceMuted, fontSize: 13),
                      prefixIcon: Icon(Icons.search,
                          color: tokens.onSurfaceMuted, size: 18),
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
                              icon: Icon(Icons.clear,
                                  color: tokens.onSurfaceMuted, size: 16),
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
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: (val) =>
                        setState(() => _filterQuery = val.trim()),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 10),
            Divider(color: tokens.surfaceBorder, height: 1),

            Builder(
              builder: (context) {
                final List<_PickerEntry> entries = [];
                if (_filterQuery.isNotEmpty) {
                  for (final code in filteredLanguages) {
                    entries.add(_LanguageEntry(code));
                  }
                } else {
                  if (widget.availableLanguages.any((c) => c.toLowerCase() == 'all')) {
                    entries.add(_LanguageEntry('All'));
                  }

                  final langState = LibraryLanguagesController.instance.state;
                  final topCodes = <String>{};
                  for (final code in langState.recentLanguages) {
                    if (code.toLowerCase() != 'all' &&
                        widget.availableLanguages.any((c) => c.toLowerCase() == code.toLowerCase())) {
                      topCodes.add(code);
                    }
                  }
                  for (final code in langState.frequentlyUsedLanguages) {
                    if (code.toLowerCase() != 'all' &&
                        widget.availableLanguages.any((c) => c.toLowerCase() == code.toLowerCase())) {
                      topCodes.add(code);
                    }
                  }

                  if (topCodes.isNotEmpty) {
                    entries.add(_HeaderEntry('Frequently & Recently Used', Icons.history_rounded));
                    for (final code in topCodes) {
                      entries.add(_LanguageEntry(code));
                    }
                    entries.add(_HeaderEntry('All Languages', Icons.translate_rounded));
                  }

                  final remaining = widget.availableLanguages.where((code) {
                    if (code.toLowerCase() == 'all') return false;
                    return !topCodes.any((t) => t.toLowerCase() == code.toLowerCase());
                  }).toList()
                    ..sort();

                  for (final code in remaining) {
                    entries.add(_LanguageEntry(code));
                  }
                }

                if (entries.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Center(
                      child: Text(
                        'No matching language found',
                        style: TextStyle(
                            color: tokens.onSurfaceMuted, fontSize: 13),
                      ),
                    ),
                  );
                }

                return Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                        vertical: 6, horizontal: 8),
                    itemCount: entries.length,
                    separatorBuilder: (context, index) {
                      final curr = entries[index];
                      final next = index + 1 < entries.length ? entries[index + 1] : null;
                      if (curr is _HeaderEntry || next is _HeaderEntry) {
                        return const SizedBox.shrink();
                      }
                      return Divider(
                        color: tokens.surfaceBorder.withValues(alpha: 0.4),
                        height: 1,
                        indent: 56,
                        endIndent: 12,
                      );
                    },
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      if (entry is _HeaderEntry) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Row(
                            children: [
                              Icon(entry.icon, size: 14, color: tokens.accent),
                              const SizedBox(width: 6),
                              Text(
                                entry.title.toUpperCase(),
                                style: TextStyle(
                                  color: tokens.onSurfaceMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      final code = (entry as _LanguageEntry).code;
                      final isSelected = code.toLowerCase() == 'all'
                          ? isAll
                          : (!isAll &&
                              _currentSelection.any((l) =>
                                  l.toLowerCase() == code.toLowerCase()));
                      final count = widget.itemCounts[code] ?? 0;

                      return LanguageListTile(
                        code: code,
                        isSelected: isSelected,
                        itemCount: count,
                        itemNoun: widget.itemNoun,
                        onTap: () => _toggleLanguage(code),
                      );
                    },
                  ),
                );
              },
            ),

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
                            : 'Apply (${_currentSelection.length} Languages • '
                                '${_calculateSelectedCount()} '
                                '${_capitalize(countNoun(widget.itemNoun, _calculateSelectedCount()))})',
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

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}
