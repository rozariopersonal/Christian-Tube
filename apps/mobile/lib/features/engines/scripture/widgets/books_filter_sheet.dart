import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';

class BooksFilterSheet extends StatefulWidget {
  final String? activeBook;
  final String? activeTestament;
  final ValueChanged<String?> onSelectBook;

  const BooksFilterSheet({
    super.key,
    required this.activeBook,
    required this.activeTestament,
    required this.onSelectBook,
  });

  static const List<String> otBooks = [
    'Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy', 'Joshua',
    'Judges', 'Ruth', '1 Samuel', '2 Samuel', '1 Kings', '2 Kings',
    '1 Chronicles', '2 Chronicles', 'Ezra', 'Nehemiah', 'Esther', 'Job',
    'Psalms', 'Proverbs', 'Ecclesiastes', 'Song of Solomon', 'Isaiah',
    'Jeremiah', 'Lamentations', 'Ezekiel', 'Daniel', 'Hosea', 'Joel', 'Amos',
    'Obadiah', 'Jonah', 'Micah', 'Nahum', 'Habakkuk', 'Zephaniah', 'Haggai',
    'Zechariah', 'Malachi'
  ];

  static const List<String> ntBooks = [
    'Matthew', 'Mark', 'Luke', 'John', 'Acts', 'Romans', '1 Corinthians',
    '2 Corinthians', 'Galatians', 'Ephesians', 'Philippians', 'Colossians',
    '1 Thessalonians', '2 Thessalonians', '1 Timothy', '2 Timothy', 'Titus',
    'Philemon', 'Hebrews', 'James', '1 Peter', '2 Peter', '1 John', '2 John',
    '3 John', 'Jude', 'Revelation'
  ];

  @override
  State<BooksFilterSheet> createState() => _BooksFilterSheetState();
}

class _BooksFilterSheetState extends State<BooksFilterSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedSegment = 'All'; // 'All', 'Old Testament', 'New Testament'
  String _query = '';

  @override
  void initState() {
    super.initState();
    if (widget.activeTestament != null) {
      _selectedSegment = widget.activeTestament!;
    }
    _searchController.addListener(() {
      final text = _searchController.text.trim().toLowerCase();
      if (text != _query) {
        setState(() => _query = text);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> _getBooksForSegment() {
    if (_selectedSegment == 'Old Testament') {
      return BooksFilterSheet.otBooks;
    } else if (_selectedSegment == 'New Testament') {
      return BooksFilterSheet.ntBooks;
    } else {
      return [...BooksFilterSheet.otBooks, ...BooksFilterSheet.ntBooks];
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isDark = context.isDark;
    final screenHeight = MediaQuery.sizeOf(context).height;

    final books = _getBooksForSegment();
    final filtered = _query.isEmpty
        ? books
        : books.where((b) => b.toLowerCase().contains(_query)).toList();

    final isAllSelected = widget.activeBook == null || widget.activeBook == 'All Books';

    return MaxWidthBox(
      maxWidth: kSheetMaxWidth,
      child: Container(
        constraints: BoxConstraints(maxHeight: screenHeight * 0.85),
        decoration: BoxDecoration(
          color: isDark
              ? tokens.surface.withValues(alpha: 0.94)
              : tokens.surface.withValues(alpha: 0.98),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: tokens.surfaceBorder, width: 1.0),
            left: BorderSide(color: tokens.surfaceBorder, width: 0.5),
            right: BorderSide(color: tokens.surfaceBorder, width: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: tokens.scrim.withValues(alpha: isDark ? 0.45 : 0.12),
              blurRadius: 20,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
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

                    // 2. Header
                    Row(
                      children: [
                        Icon(Icons.auto_stories_rounded,
                            color: tokens.accent, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Filter by Book',
                            style: TextStyle(
                              color: tokens.onSurface,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (!isAllSelected)
                          TextButton(
                            onPressed: () {
                              widget.onSelectBook(null);
                              Navigator.pop(context);
                            },
                            child: Text(
                              'Reset to All',
                              style: TextStyle(
                                color: tokens.accent,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        IconButton(
                          icon: Icon(Icons.close_rounded,
                              color: tokens.onSurfaceMuted, size: 20),
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // 3. Search Bar
                    Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: tokens.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: tokens.surfaceBorder),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          Icon(Icons.search_rounded,
                              color: tokens.onSurfaceMuted, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              style: TextStyle(
                                color: tokens.onSurface,
                                fontSize: 13.5,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Search 66 books...',
                                hintStyle: TextStyle(
                                  color: tokens.onSurfaceMuted,
                                  fontSize: 13,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          if (_query.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(4.0),
                                child: Icon(Icons.close_rounded,
                                    color: tokens.onSurfaceMuted, size: 16),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 4. Segmented Division Tabs (All, Old Testament, New Testament)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _buildSegmentChip('All', 'All (66)', tokens),
                          const SizedBox(width: 8),
                          _buildSegmentChip('Old Testament', 'Old Testament (39)', tokens),
                          const SizedBox(width: 8),
                          _buildSegmentChip('New Testament', 'New Testament (27)', tokens),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 5. Scrollable Chips Grid
                    Flexible(
                      child: filtered.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Text(
                                  'No books matched "$_query"',
                                  style: TextStyle(
                                      color: tokens.onSurfaceMuted,
                                      fontSize: 14),
                                ),
                              ),
                            )
                          : SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  // 'All Books' chip at the top when viewing All
                                  if (_query.isEmpty)
                                    _buildBookChip(
                                      'All Books',
                                      isSelected: isAllSelected,
                                      tokens: tokens,
                                      onTap: () {
                                        widget.onSelectBook(null);
                                        Navigator.pop(context);
                                      },
                                    ),
                                  for (final book in filtered)
                                    _buildBookChip(
                                      book,
                                      isSelected: widget.activeBook == book,
                                      tokens: tokens,
                                      onTap: () {
                                        widget.onSelectBook(book);
                                        Navigator.pop(context);
                                      },
                                    ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentChip(String value, String label, AppTokens tokens) {
    final isSelected = _selectedSegment == value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedSegment = value),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? tokens.accent.withValues(alpha: 0.16)
                : tokens.surfaceVariant,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? tokens.accent : tokens.surfaceBorder,
              width: 1.0,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? tokens.accent : tokens.onSurfaceMuted,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              fontSize: 12,
            ),
          ),
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
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? tokens.accent.withValues(alpha: 0.18)
                : tokens.surfaceVariant.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? tokens.accent : tokens.surfaceBorder,
              width: isSelected ? 1.4 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: tokens.accent.withValues(alpha: 0.25),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: Text(
            book,
            style: TextStyle(
              color: isSelected ? tokens.accent : tokens.onSurface,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
