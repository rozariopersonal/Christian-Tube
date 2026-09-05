import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../models/bible_book.dart';
import '../models/bible_verse.dart';

class BookChapterSelector extends StatefulWidget {
  final String currentBook;
  final int currentChapter;
  final int currentVerse;
  final Function(String book, int chapter, int verse) onSelection;
  final String Function(String canonicalBook, int bookNumber)? displayNameOf;

  /// Loads the verse list for a book+chapter on demand so the verses tab can
  /// be populated while the sheet is still open. If null, the verses tab is
  /// disabled.
  final Future<List<BibleVerse>> Function(String book, int chapter)? loadVerses;

  const BookChapterSelector({
    super.key,
    required this.currentBook,
    required this.currentChapter,
    this.currentVerse = 1,
    required this.onSelection,
    this.displayNameOf,
    this.loadVerses,
  });

  @override
  State<BookChapterSelector> createState() => _BookChapterSelectorState();
}

class _BookChapterSelectorState extends State<BookChapterSelector> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late ScrollController _booksScrollController;
  late String _selectedBook;
  late int _selectedChapter;
  late int _selectedVerse;
  List<BibleVerse>? _chapterVerses;
  bool _loadingVerses = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _selectedBook = widget.currentBook;
    _selectedChapter = widget.currentChapter;
    _selectedVerse = widget.currentVerse;
    final bookIndex = bibleBooks.keys.toList().indexOf(_selectedBook);
    final initialOffset = (bookIndex > 3) ? (bookIndex - 2) * 52.0 : 0.0;
    _booksScrollController = ScrollController(initialScrollOffset: initialOffset);
    if (widget.loadVerses != null) _loadVersesForSelection();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _booksScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: context.tokens.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.tokens.onSurfaceDisabled,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          TabBar(
            controller: _tabController,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: context.tokens.onSurfaceMuted,
            indicatorColor: theme.colorScheme.primary,
            tabs: const [
              Tab(text: 'BOOKS'),
              Tab(text: 'CHAPTERS'),
              Tab(text: 'VERSES'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Books List
                ListView.builder(
                  controller: _booksScrollController,
                  itemCount: bibleBooks.length,
                  itemBuilder: (context, index) {
                    final book = bibleBooks.keys.elementAt(index);
                    final bookNumber = index + 1;
                    final isSelected = book == _selectedBook;
                    final displayName =
                        widget.displayNameOf?.call(book, bookNumber) ?? book;
                    return ListTile(
                      title: Text(
                        displayName,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? theme.colorScheme.primary : null,
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          _selectedBook = book;
                        });
                        _tabController.animateTo(1);
                      },
                    );
                  },
                ),
                // Chapters Grid
                GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 64,
                    childAspectRatio: 1.0,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: bibleBooks[_selectedBook] ?? 1,
                  itemBuilder: (context, index) {
                    final chapter = index + 1;
                    final isSelected = chapter == _selectedChapter && _selectedBook == widget.currentBook;
                    return InkWell(
                      onTap: () {
                        _selectChapter(chapter);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected 
                            ? theme.colorScheme.primary 
                            : context.tokens.surfaceVariant,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          chapter.toString(),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected 
                              ? theme.colorScheme.onPrimary 
                              : context.tokens.onSurface,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // Verses Grid
                _buildVersesView(theme),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  void _selectChapter(int chapter) {
    setState(() {
      _selectedChapter = chapter;
      _chapterVerses = null;
      _loadingVerses = widget.loadVerses != null;
    });
    _tabController.animateTo(2);
    if (widget.loadVerses != null) _loadVersesForSelection();
  }

  Future<void> _loadVersesForSelection() async {
    final loader = widget.loadVerses;
    if (loader == null) return;
    final book = _selectedBook;
    final chapter = _selectedChapter;
    setState(() => _loadingVerses = true);
    try {
      final verses = await loader(book, chapter);
      if (!mounted || book != _selectedBook || chapter != _selectedChapter) return;
      setState(() {
        _chapterVerses = verses.isEmpty ? null : verses;
        _loadingVerses = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _chapterVerses = null;
        _loadingVerses = false;
      });
    }
  }

  Widget _buildVersesView(ThemeData theme) {
    final versions = _chapterVerses;
    if (_loadingVerses) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (versions == null || versions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            widget.loadVerses == null
                ? 'Open the chapter grid, pick a chapter, then choose a verse.'
                : 'No verses found for this chapter.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.tokens.onSurfaceMuted,
                ),
          ),
        ),
      );
    }
    final maxVerse = versions.map((v) => v.number).fold<int>(0, (a, b) => a > b ? a : b);
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 64,
        childAspectRatio: 1.0,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: maxVerse,
      itemBuilder: (context, index) {
        final verse = index + 1;
        final isSelected = verse == _selectedVerse &&
            _selectedBook == widget.currentBook &&
            _selectedChapter == widget.currentChapter;
        return InkWell(
          onTap: () {
            setState(() => _selectedVerse = verse);
            widget.onSelection(_selectedBook, _selectedChapter, verse);
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.primary
                  : context.tokens.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              verse.toString(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : context.tokens.onSurface,
              ),
            ),
          ),
        );
      },
    );
  }
}
