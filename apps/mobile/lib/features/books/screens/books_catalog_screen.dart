import 'package:flutter/material.dart';
import '../../../../core/layout/adaptivity.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../models/book.dart';
import '../models/user_reading_progress.dart';
import '../services/book_service.dart';
import '../widgets/book_card.dart';
import 'book_reader_screen.dart';

/// Screen displaying the Books Library grid with search and recent reading progress.
class BooksCatalogScreen extends StatefulWidget {
  const BooksCatalogScreen({super.key});

  @override
  State<BooksCatalogScreen> createState() => _BooksCatalogScreenState();
}

class _BooksCatalogScreenState extends State<BooksCatalogScreen> {
  final BookService _bookService = BookService.instance;
  final TextEditingController _searchController = TextEditingController();

  List<Book> _books = [];
  Map<String, UserReadingProgress> _progressMap = {};
  List<Book> _recentBooks = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() => _isLoading = true);
    await _bookService.initialize();

    final books = await _bookService.getBooks(query: _searchQuery);
    final recentProgress = await _bookService.getRecentProgress(limit: 5);

    final progressMap = <String, UserReadingProgress>{};
    for (final p in recentProgress) {
      progressMap[p.bookId] = p;
    }

    final recentBooks = <Book>[];
    for (final p in recentProgress) {
      final match = books.where((b) => b.id == p.bookId).firstOrNull;
      if (match != null) recentBooks.add(match);
    }

    if (mounted) {
      setState(() {
        _books = books;
        _progressMap = progressMap;
        _recentBooks = recentBooks;
        _isLoading = false;
      });
    }
  }

  void _openReader(Book book, {int? initialPage, int? initialLine}) async {
    final progress = _progressMap[book.id];
    final targetPage = initialPage ?? progress?.currentPage ?? 1;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookReaderScreen(
          bookId: book.id,
          initialPage: targetPage,
          highlightStartLine: initialLine,
          highlightEndLine: initialLine,
        ),
      ),
    );

    // Refresh progress on return
    _loadCatalog();
  }

  Widget _buildSearchBar(AppTokens tokens) {
    return Container(
      height: 46,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: tokens.onSurface, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search 38 books by Zac Poonen...',
          hintStyle: TextStyle(color: tokens.onSurfaceMuted, fontSize: 14),
          prefixIcon: Icon(Icons.search, color: tokens.onSurfaceMuted, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: tokens.onSurfaceMuted, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                    _loadCatalog();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        onChanged: (val) {
          setState(() => _searchQuery = val);
          _loadCatalog();
        },
      ),
    );
  }

  Widget _buildContinueReading(AppTokens tokens) {
    if (_recentBooks.isEmpty || _searchQuery.isNotEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Icon(Icons.history_rounded, size: 18, color: tokens.accent),
              const SizedBox(width: 6),
              Text(
                'Continue Reading',
                style: TextStyle(
                  color: tokens.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 125,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: _recentBooks.length,
            itemBuilder: (context, index) {
              final book = _recentBooks[index];
              final progress = _progressMap[book.id];
              final percent = progress?.completionPercent ?? 0.0;

              return Container(
                width: 250,
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tokens.surfaceVariant,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: tokens.surfaceBorder),
                ),
                child: InkWell(
                  onTap: () => _openReader(book),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          width: 50,
                          height: 75,
                          color: tokens.surface,
                          child: book.coverFile.isNotEmpty
                              ? Image.asset(
                                  'assets/books/covers/${book.coverFile}',
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Center(
                                    child: Icon(Icons.menu_book, color: tokens.accent, size: 24),
                                  ),
                                )
                              : Center(
                                  child: Icon(Icons.menu_book, color: tokens.accent, size: 24),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              book.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.onSurface,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'p. ${progress?.currentPage ?? 1} of ${book.totalPages}',
                              style: TextStyle(
                                color: tokens.onSurfaceMuted,
                                fontSize: 11.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: percent,
                                minHeight: 4,
                                backgroundColor: tokens.surface,
                                valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final screen = ScreenClass.of(context);

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: tokens.background,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Books Library',
              style: TextStyle(
                color: tokens.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              'Zac Poonen • CFC India',
              style: TextStyle(
                color: tokens.onSurfaceMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: tokens.onSurfaceMuted),
            tooltip: 'Refresh library',
            onPressed: _loadCatalog,
          ),
        ],
      ),
      body: MaxWidthBox(
        maxWidth: 1080,
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: tokens.accent),
                    const SizedBox(height: 16),
                    Text(
                      'Opening books library...',
                      style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 14),
                    ),
                  ],
                ),
              )
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _buildSearchBar(tokens),
                  ),
                  SliverToBoxAdapter(
                    child: _buildContinueReading(tokens),
                  ),
                  if (_books.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off_rounded, size: 48, color: tokens.onSurfaceMuted),
                            const SizedBox(height: 12),
                            Text(
                              'No books matching "$_searchQuery"',
                              style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: screen.isCompact ? 160 : 180,
                          childAspectRatio: 0.58,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 18,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final book = _books[index];
                            return BookCard(
                              book: book,
                              progress: _progressMap[book.id],
                              onTap: () => _openReader(book),
                            );
                          },
                          childCount: _books.length,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
