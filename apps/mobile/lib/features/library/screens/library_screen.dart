import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/github_data_service.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../../articles/models/wftw_index_entry.dart';
import '../../articles/services/wftw_index_service.dart';
import '../../articles/widgets/wftw_shelf.dart';
import '../../books/models/book.dart';
import '../../books/models/user_reading_progress.dart';
import '../../books/screens/book_reader_screen.dart';
import '../services/library_data_loader.dart';

/// Library hub — one scrolling landing for everything users read:
/// recent books (with progress), the Word-for-the-Week teachings, and a
/// placeholder for a future Articles collection.
class LibraryScreen extends StatefulWidget {
  final LibraryDataLoader? loader;
  final WftwIndexLoader? wftwLoader;

  const LibraryScreen({super.key, this.loader, this.wftwLoader});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final LibraryDataLoader _loader;
  late final WftwIndexLoader _wftwLoader;

  List<Book> _recentBooks = const [];
  Map<String, UserReadingProgress> _progressMap = const {};
  List<WftwIndexEntry> _wftwRecent = const [];
  bool _loading = true;

  static const int _recentBookLimit = 10;
  static const int _wftwShelfCount = 8;

  @override
  void initState() {
    super.initState();
    _loader = widget.loader ?? BookServiceLibraryLoader();
    _wftwLoader =
        widget.wftwLoader ?? () => WftwIndexService().getIndex();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      await _loader.initialize();

      final books = await _loader.getBooks();
      final recentProgress = await _loader.getRecentProgress(
        limit: _recentBookLimit,
      );

      final progressMap = <String, UserReadingProgress>{};
      final recentBooks = <Book>[];
      for (final p in recentProgress) {
        progressMap[p.bookId] = p;
        final match = books.where((b) => b.id == p.bookId).firstOrNull;
        if (match != null) recentBooks.add(match);
      }

      List<WftwIndexEntry> index = const [];
      try {
        final loaded = await _wftwLoader();
        index = loaded.length <= _wftwShelfCount
            ? loaded
            : loaded.sublist(0, _wftwShelfCount);
      } catch (e) {
        debugPrint('Word for the Week shelf unavailable: $e');
      }

      if (!mounted) return;
      setState(() {
        _recentBooks = recentBooks;
        _progressMap = progressMap;
        _wftwRecent = index;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Library load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openReader(Book book) async {
    final progress = _progressMap[book.id];
    int targetPage = 1;
    int? targetLine;

    if (progress != null && progress.currentPage > 1) {
      final tokens = context.tokens;
      final shouldResume = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: tokens.surface,
          title: Text('Resume Reading?', style: TextStyle(color: tokens.onSurface)),
          content: Text(
            'You were previously on page ${progress.currentPage}. Would you like to resume from where you left off or start over from the beginning?',
            style: TextStyle(color: tokens.onSurfaceMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Start Over', style: TextStyle(color: tokens.onSurfaceMuted)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(backgroundColor: tokens.accent),
              child: const Text('Resume'),
            ),
          ],
        ),
      );

      if (shouldResume == null) return;
      targetPage = shouldResume ? progress.currentPage : 1;
      targetLine = shouldResume ? progress.currentLine : 1;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookReaderScreen(
          bookId: book.id,
          initialPage: targetPage,
          highlightStartLine: targetLine,
          highlightEndLine: targetLine,
        ),
      ),
    );
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: tokens.background,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Library',
              style: TextStyle(
                color: tokens.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              'Books • Teachings • Articles',
              style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 11.5),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: tokens.onSurfaceMuted, size: 21),
            tooltip: 'Refresh library',
            onPressed: _loadData,
          ),
        ],
      ),
      body: MaxWidthBox(
        maxWidth: 1080,
        child: _loading
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: tokens.accent),
                    const SizedBox(height: 16),
                    Text(
                      'Loading library...',
                      style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 14),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _loadData,
                color: tokens.accent,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _buildBooksSection(tokens),
                    ),
                    if (_wftwRecent.isNotEmpty)
                      SliverToBoxAdapter(
                        child: WftwShelf(
                          entries: _wftwRecent,
                          onViewAll: _openTeachings,
                          onTapArticle: _openWftwArticle,
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: _buildArticlesPlaceholder(tokens),
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 40),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildBooksSection(AppTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          tokens,
          icon: Icons.collections_bookmark_outlined,
          title: 'Books',
          onViewAll: () => context.push('/books'),
        ),
        if (_recentBooks.isNotEmpty)
          SizedBox(
            height: 140,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _recentBooks.length,
              itemBuilder: (context, index) {
                final book = _recentBooks[index];
                final progress = _progressMap[book.id];
                return Container(
                  width: 240,
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: tokens.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: tokens.surfaceBorder),
                  ),
                  child: InkWell(
                    onTap: () => _openReader(book),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            width: 48,
                            height: 72,
                            color: tokens.surface,
                            child: book.coverFile.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl:
                                        GitHubDataService.bookCoverUrl(book.coverFile),
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) =>
                                        Container(color: tokens.surface),
                                    errorWidget: (context, url, error) => Icon(
                                        Icons.menu_book, color: tokens.accent, size: 22),
                                  )
                                : Icon(Icons.menu_book, color: tokens.accent, size: 22),
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
                                  fontSize: 12.5,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${book.author} • p. ${progress?.currentPage ?? 1}/${book.totalPages}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: tokens.onSurfaceMuted,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 5),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: progress?.completionPercent ?? 0.0,
                                  minHeight: 3.5,
                                  backgroundColor: tokens.surface,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(tokens.accent),
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
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Material(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => context.push('/books'),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 56,
                        decoration: BoxDecoration(
                          color: tokens.accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.menu_book_rounded,
                            color: tokens.accent, size: 24),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'Explore the Books library',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          color: tokens.onSurfaceMuted, size: 22),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSectionHeader(
    AppTokens tokens, {
    required IconData icon,
    required String title,
    required VoidCallback onViewAll,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: [
          Flexible(
            child: Row(
              children: [
                Icon(icon, color: tokens.accent, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onViewAll,
            style: TextButton.styleFrom(
              foregroundColor: tokens.accent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('View all', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildArticlesPlaceholder(AppTokens tokens) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Material(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Articles are coming soon.'),
                backgroundColor: tokens.onSurface,
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        tokens.accent.withValues(alpha: 0.22),
                        tokens.accent.withValues(alpha: 0.08),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.article_outlined, color: tokens.accent, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Articles',
                        style: TextStyle(
                          color: tokens.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Devotionals, magazine & study articles — coming soon.',
                        style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.schedule_rounded, color: tokens.onSurfaceMuted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openTeachings() {
    context.push('/teachings');
  }

  void _openWftwArticle(WftwIndexEntry entry) {
    context.push('/article/${entry.id}', extra: {'title': entry.title});
  }
}