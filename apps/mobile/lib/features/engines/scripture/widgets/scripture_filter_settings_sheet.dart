import 'package:flutter/material.dart';
import '../../../../core/layout/adaptive_sheet_frame.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../models/scripture_filter_state.dart';
import 'books_filter_sheet.dart';

class ScriptureFilterSettingsSheet extends StatefulWidget {
  final ScriptureFilterState filterState;
  final ValueChanged<ScriptureFilterState> onApply;

  const ScriptureFilterSettingsSheet({
    super.key,
    required this.filterState,
    required this.onApply,
  });

  static const List<Map<String, dynamic>> categoryDefinitions = [
    {
      'id': 'comfort',
      'label': 'Peace & Comfort',
      'icon': Icons.spa_rounded,
    },
    {
      'id': 'wisdom',
      'label': 'Wisdom & Guidance',
      'icon': Icons.lightbulb_outline_rounded,
    },
    {
      'id': 'faith',
      'label': 'Faith & Trust',
      'icon': Icons.favorite_border_rounded,
    },
    {
      'id': 'salvation',
      'label': 'Salvation & Grace',
      'icon': Icons.all_inclusive_rounded,
    },
    {
      'id': 'prayer',
      'label': 'Prayer & Consecration',
      'icon': Icons.self_improvement_rounded,
    },
    {
      'id': 'courage',
      'label': 'Courage & Strength',
      'icon': Icons.shield_outlined,
    },
    {
      'id': 'praise',
      'label': 'Praise & Worship',
      'icon': Icons.celebration_outlined,
    },
    {
      'id': 'doctrine',
      'label': 'Doctrine & Truth',
      'icon': Icons.menu_book_rounded,
    },
  ];

  static const List<String> tagDefinitions = [
    'anxiety_fear',
    'courage',
    'faith',
    'god_character',
    'comfort',
    'praise',
    'wisdom',
    'prayer',
    'doctrine',
    'consecration',
    'promises',
    'hope',
    'healing',
    'forgiveness',
    'patience',
  ];

  @override
  State<ScriptureFilterSettingsSheet> createState() =>
      _ScriptureFilterSettingsSheetState();
}

class _ScriptureFilterSettingsSheetState
    extends State<ScriptureFilterSettingsSheet> {
  late String _readingOrder;
  late String? _testamentFilter;
  late String? _bookFilter;
  late List<String> _selectedCategories;
  late List<String> _selectedTags;
  late double _fontSizeScale;

  final TextEditingController _bookSearchController = TextEditingController();
  String _bookQuery = '';

  @override
  void initState() {
    super.initState();
    _readingOrder = widget.filterState.readingOrder;
    _testamentFilter = widget.filterState.testamentFilter;
    _bookFilter = widget.filterState.bookFilter;
    _selectedCategories = List.from(widget.filterState.selectedCategories);
    _selectedTags = List.from(widget.filterState.selectedTags);
    _fontSizeScale = widget.filterState.fontSizeScale;

    _bookSearchController.addListener(() {
      final q = _bookSearchController.text.trim().toLowerCase();
      if (q != _bookQuery) {
        setState(() => _bookQuery = q);
      }
    });
  }

  @override
  void dispose() {
    _bookSearchController.dispose();
    super.dispose();
  }

  int get _currentActiveCount {
    int count = 0;
    if (_readingOrder != 'random') count++;
    if (_testamentFilter != null && _testamentFilter != 'All') count++;
    if (_bookFilter != null && _bookFilter != 'All Books') count++;
    count += _selectedCategories.length;
    count += _selectedTags.length;
    return count;
  }

  void _resetAll() {
    setState(() {
      _readingOrder = 'random';
      _testamentFilter = null;
      _bookFilter = null;
      _selectedCategories.clear();
      _selectedTags.clear();
      _bookSearchController.clear();
      _bookQuery = '';
    });
  }

  void _applyAndClose() {
    final newState = widget.filterState.copyWith(
      readingOrder: _readingOrder,
      testamentFilter: _testamentFilter,
      bookFilter: _bookFilter,
      clearTestamentFilter: _testamentFilter == null || _testamentFilter == 'All',
      clearBookFilter: _bookFilter == null || _bookFilter == 'All Books',
      selectedCategories: _selectedCategories,
      selectedTags: _selectedTags,
      fontSizeScale: _fontSizeScale,
    );
    widget.onApply(newState);
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  List<String> _getBooksForSegment() {
    if (_testamentFilter == 'Old Testament') {
      return BooksFilterSheet.otBooks;
    } else if (_testamentFilter == 'New Testament') {
      return BooksFilterSheet.ntBooks;
    } else {
      return [...BooksFilterSheet.otBooks, ...BooksFilterSheet.ntBooks];
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    final books = _getBooksForSegment();
    final filteredBooks = _bookQuery.isEmpty
        ? books
        : books.where((b) => b.toLowerCase().contains(_bookQuery)).toList();

    final activeCount = _currentActiveCount;

    return AdaptiveSheetFrame(
      maxHeightFactor: 0.88,
      maxWidth: kSheetMaxWidth,
      showDragHandle: false,
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Drag Handle
          Center(
            child: Container(
              width: 38,
              height: 4,
                        decoration: BoxDecoration(
                          color: tokens.onSurfaceDisabled.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 2. Header Row
                    Row(
                      children: [
                        Icon(Icons.tune_rounded, color: tokens.accent, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  'Filter & Settings',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: tokens.onSurface,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (activeCount > 0) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: tokens.accent.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: tokens.accent.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Text(
                                    '$activeCount Active',
                                    style: TextStyle(
                                      color: tokens.accent,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (activeCount > 0)
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: _resetAll,
                            child: Text(
                              'Reset All',
                              style: TextStyle(
                                color: tokens.accent,
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        IconButton(
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(),
                          icon: Icon(Icons.close_rounded,
                              color: tokens.onSurfaceMuted, size: 20),
                          tooltip: 'Close',
                          onPressed: () {
                            if (Navigator.of(context).canPop()) {
                              Navigator.of(context).pop();
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Divider(color: tokens.surfaceBorder, height: 1),
                    const SizedBox(height: 12),

                    // 3. Scrollable Settings Sections
                    Flexible(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Section A: Reading Order
                            _buildSectionHeader('READING ORDER', tokens),
                            const SizedBox(height: 8),
                            _buildOrderSelector(tokens),
                            const SizedBox(height: 18),

                            // Section B: Scope & Testament
                            _buildSectionHeader('SCOPE & TESTAMENT', tokens),
                            const SizedBox(height: 8),
                            _buildTestamentSelector(tokens),
                            const SizedBox(height: 18),

                            // Section C: Filter by Book
                            _buildSectionHeader('FILTER BY BOOK', tokens),
                            const SizedBox(height: 8),
                            _buildBookSearch(tokens),
                            const SizedBox(height: 10),
                            _buildBooksWrap(filteredBooks, tokens),
                            const SizedBox(height: 18),

                            // Section D: Categories
                            _buildSectionHeader('CATEGORIES (SELECT ANY)', tokens),
                            const SizedBox(height: 8),
                            _buildCategoriesGrid(tokens),
                            const SizedBox(height: 18),

                            // Section E: Tags & Life Situations
                            _buildSectionHeader('TAGS & SITUATIONS', tokens),
                            const SizedBox(height: 8),
                            _buildTagsWrap(tokens),
                            const SizedBox(height: 18),

                            // Section F: Font Size
                            _buildSectionHeader('FONT SIZE ADJUSTMENT', tokens),
                            const SizedBox(height: 8),
                            _buildFontSizeStudio(tokens),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                    Divider(color: tokens.surfaceBorder, height: 1),
                    const SizedBox(height: 12),

                    // 4. Primary Apply Action Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: tokens.accent,
                          foregroundColor: tokens.background,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        onPressed: _applyAndClose,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_circle_outline_rounded,
                                size: 19),
                            const SizedBox(width: 8),
                            Text(
                              activeCount > 0
                                  ? 'Apply Filters ($activeCount Active)'
                                  : 'Apply Settings',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
          ],
        ),
    );
  }

  Widget _buildSectionHeader(String title, AppTokens tokens) {
    return Text(
      title,
      style: TextStyle(
        color: tokens.onSurfaceMuted,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.0,
      ),
    );
  }

  // --- Reading Order Selector ---
  Widget _buildOrderSelector(AppTokens tokens) {
    final orders = [
      {'id': 'random', 'label': 'Shuffle / Random', 'icon': Icons.shuffle_rounded},
      {'id': 'canonical', 'label': 'Canonical (Gen → Rev)', 'icon': Icons.format_list_numbered_rounded},
      {'id': 'bookmarked', 'label': 'Bookmarked Only', 'icon': Icons.bookmark_rounded},
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: orders.map((o) {
        final id = o['id'] as String;
        final isSelected = _readingOrder == id;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _readingOrder = id),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? tokens.accent.withValues(alpha: 0.18)
                    : tokens.surfaceVariant.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? tokens.accent : tokens.surfaceBorder,
                  width: isSelected ? 1.4 : 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    o['icon'] as IconData,
                    size: 15,
                    color: isSelected ? tokens.accent : tokens.onSurfaceMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    o['label'] as String,
                    style: TextStyle(
                      color: isSelected ? tokens.accent : tokens.onSurface,
                      fontSize: 12.5,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // --- Testament Selector ---
  Widget _buildTestamentSelector(AppTokens tokens) {
    final segments = [
      {'val': null, 'label': 'All (66)'},
      {'val': 'Old Testament', 'label': 'Old Testament (39)'},
      {'val': 'New Testament', 'label': 'New Testament (27)'},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: segments.map((s) {
          final val = s['val'];
          final isSelected = _testamentFilter == val;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  setState(() {
                    _testamentFilter = val;
                    // Reset book if selected book doesn't belong to newly selected testament
                    if (_bookFilter != null && val != null) {
                      final ot = BooksFilterSheet.otBooks.contains(_bookFilter);
                      if (val == 'Old Testament' && !ot) _bookFilter = null;
                      if (val == 'New Testament' && ot) _bookFilter = null;
                    }
                  });
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? tokens.accent.withValues(alpha: 0.18)
                        : tokens.surfaceVariant.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? tokens.accent : tokens.surfaceBorder,
                      width: isSelected ? 1.4 : 1.0,
                    ),
                  ),
                  child: Text(
                    s['label'] as String,
                    style: TextStyle(
                      color: isSelected ? tokens.accent : tokens.onSurface,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // --- Book Search ---
  Widget _buildBookSearch(AppTokens tokens) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: tokens.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: tokens.onSurfaceMuted, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _bookSearchController,
              style: TextStyle(color: tokens.onSurface, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search 66 books...',
                hintStyle:
                    TextStyle(color: tokens.onSurfaceMuted, fontSize: 12.5),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_bookQuery.isNotEmpty)
            GestureDetector(
              onTap: () {
                _bookSearchController.clear();
                setState(() => _bookQuery = '');
              },
              child: Icon(Icons.close_rounded,
                  color: tokens.onSurfaceMuted, size: 16),
            ),
        ],
      ),
    );
  }

  // --- Books Wrap ---
  Widget _buildBooksWrap(List<String> books, AppTokens tokens) {
    final isAllSelected = _bookFilter == null || _bookFilter == 'All Books';

    return SizedBox(
      height: 96,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (_bookQuery.isEmpty)
              _buildBookChip(
                'All Books',
                isSelected: isAllSelected,
                tokens: tokens,
                onTap: () => setState(() => _bookFilter = null),
              ),
            for (final book in books)
              _buildBookChip(
                book,
                isSelected: _bookFilter == book,
                tokens: tokens,
                onTap: () => setState(() => _bookFilter = book),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookChip(
    String book, {
    required bool isSelected,
    required AppTokens tokens,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected
                ? tokens.accent.withValues(alpha: 0.20)
                : tokens.surfaceVariant.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? tokens.accent : tokens.surfaceBorder,
              width: isSelected ? 1.4 : 1.0,
            ),
          ),
          child: Text(
            book,
            style: TextStyle(
              color: isSelected ? tokens.accent : tokens.onSurface,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  // --- Categories Grid ---
  Widget _buildCategoriesGrid(AppTokens tokens) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ScriptureFilterSettingsSheet.categoryDefinitions.map((cat) {
        final id = cat['id'] as String;
        final label = cat['label'] as String;
        final icon = cat['icon'] as IconData;
        final isSelected = _selectedCategories.contains(id);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() {
                if (isSelected) {
                  _selectedCategories.remove(id);
                } else {
                  _selectedCategories.add(id);
                }
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected
                    ? tokens.accent.withValues(alpha: 0.20)
                    : tokens.surfaceVariant.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? tokens.accent : tokens.surfaceBorder,
                  width: isSelected ? 1.4 : 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: isSelected ? tokens.accent : tokens.onSurfaceMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? tokens.accent : tokens.onSurface,
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // --- Tags & Situations ---
  Widget _buildTagsWrap(AppTokens tokens) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: ScriptureFilterSettingsSheet.tagDefinitions.map((tag) {
        final isSelected = _selectedTags.contains(tag);
        final display = '#${tag.replaceAll('_', ' ')}';

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() {
                if (isSelected) {
                  _selectedTags.remove(tag);
                } else {
                  _selectedTags.add(tag);
                }
              });
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isSelected
                    ? tokens.accent.withValues(alpha: 0.18)
                    : tokens.surfaceVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? tokens.accent : tokens.surfaceBorder,
                  width: isSelected ? 1.3 : 1.0,
                ),
              ),
              child: Text(
                display,
                style: TextStyle(
                  color: isSelected ? tokens.accent : tokens.onSurfaceMuted,
                  fontSize: 11.5,
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // --- Font Size Studio ---
  Widget _buildFontSizeStudio(AppTokens tokens) {
    final pct = (_fontSizeScale * 100).round();

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.remove_rounded, size: 20),
          color: tokens.onSurface,
          tooltip: 'Smaller Font',
          onPressed: _fontSizeScale > 0.8
              ? () => setState(() =>
                  _fontSizeScale = (_fontSizeScale - 0.1).clamp(0.8, 1.5))
              : null,
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: tokens.accent,
              inactiveTrackColor: tokens.surfaceVariant,
              thumbColor: tokens.accent,
              trackHeight: 3,
            ),
            child: Slider(
              value: _fontSizeScale,
              min: 0.8,
              max: 1.5,
              divisions: 7,
              label: '$pct%',
              onChanged: (val) => setState(() => _fontSizeScale = val),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_rounded, size: 20),
          color: tokens.onSurface,
          tooltip: 'Larger Font',
          onPressed: _fontSizeScale < 1.5
              ? () => setState(() =>
                  _fontSizeScale = (_fontSizeScale + 0.1).clamp(0.8, 1.5))
              : null,
        ),
        Container(
          width: 50,
          alignment: Alignment.centerRight,
          child: Text(
            '$pct%',
            style: TextStyle(
              color: tokens.accent,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}
