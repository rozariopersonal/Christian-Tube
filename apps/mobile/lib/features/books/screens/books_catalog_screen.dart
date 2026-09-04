import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../models/book.dart';
import '../models/user_reading_progress.dart';
import '../services/book_service.dart';
import '../widgets/book_card.dart';
import 'book_reader_screen.dart';
import '../../downloads/screens/downloads_manager_screen.dart';

/// Screen displaying the Books Library organized by subject groups with search,
/// individual book on-demand downloading, and recent reading progress.
class BooksCatalogScreen extends StatefulWidget {
  const BooksCatalogScreen({super.key});

  @override
  State<BooksCatalogScreen> createState() => _BooksCatalogScreenState();
}

class _BooksCatalogScreenState extends State<BooksCatalogScreen> {
  final BookService _bookService = BookService.instance;
  final TextEditingController _searchController = TextEditingController();

  List<Book> _books = [];
  Map<String, List<Book>> _booksBySubject = {};
  Map<String, UserReadingProgress> _progressMap = {};
  List<Book> _recentBooks = [];
  Set<String> _installedBookIds = {};
  List<String> _subjects = ['All'];
  List<String> _languages = ['All'];
  int _totalBooksCount = 0;

  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedSubject = 'All';
  String _selectedLanguage = 'All';
  bool _viewBySubjects = true;

  static const Map<String, String> _languageNames = {
    'all': 'All Languages',
    'en': 'English',
    'ta': 'Tamil',
    'hi': 'Hindi',
    'te': 'Telugu',
    'kn': 'Kannada',
    'ml': 'Malayalam',
    'de': 'German',
    'ro': 'Romanian',
    'pt': 'Portuguese',
    'si': 'Sinhala',
    'es': 'Spanish',
    'fr': 'French',
    'pl': 'Polish',
    'ru': 'Russian',
    'mr': 'Marathi',
  };

  @override
  void initState() {
    super.initState();
    _bookService.addListener(_onServiceUpdate);
    _loadCatalog();
  }

  @override
  void dispose() {
    _bookService.removeListener(_onServiceUpdate);
    _searchController.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCatalog() async {
    setState(() => _isLoading = true);
    await _bookService.initialize();

    final installedIds = await _bookService.getInstalledBookIds();
    final books = await _bookService.getBooks(
      query: _searchQuery,
      subject: _selectedSubject,
      language: _selectedLanguage,
    );
    final allBooks = await _bookService.getBooks();
    final recentProgress = await _bookService.getRecentProgress(limit: 5);
    final subjects = await _bookService.getSubjects();

    // Derive languages present in catalog
    final langCodes = <String>{};
    for (final b in allBooks) {
      if (b.language.isNotEmpty) langCodes.add(b.language.toLowerCase());
    }
    final sortedLangs = langCodes.toList()..sort();
    final languages = ['All', ...sortedLangs];

    // Group matching books by subject
    final map = <String, List<Book>>{};
    for (final b in allBooks) {
      if (_selectedLanguage != 'All' && b.language.toLowerCase() != _selectedLanguage.toLowerCase()) {
        continue;
      }
      final s = b.subject.isNotEmpty ? b.subject : 'Christian Living';
      map.putIfAbsent(s, () => []).add(b);
    }

    final progressMap = <String, UserReadingProgress>{};
    for (final p in recentProgress) {
      progressMap[p.bookId] = p;
    }

    final recentBooks = <Book>[];
    for (final p in recentProgress) {
      final match = allBooks.where((b) => b.id == p.bookId).firstOrNull;
      if (match != null) recentBooks.add(match);
    }

    if (mounted) {
      setState(() {
        _installedBookIds = installedIds;
        _books = books;
        _booksBySubject = map;
        _progressMap = progressMap;
        _recentBooks = recentBooks;
        _subjects = subjects;
        _languages = languages;
        _totalBooksCount = allBooks.length;
        _isLoading = false;
      });
    }
  }

  Future<void> _promptDownloadSingleBook(Book book) async {
    final tokens = context.tokens;
    final sizeText = book.downloadSizeFormatted.isNotEmpty
        ? book.downloadSizeFormatted
        : 'under 100 KB';

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: tokens.surfaceBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 44,
                      height: 64,
                      color: tokens.surfaceVariant,
                      child: book.coverFile.isNotEmpty
                          ? Image.asset(
                              'assets/books/covers/${book.coverFile}',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(Icons.menu_book, color: tokens.accent),
                            )
                          : Icon(Icons.menu_book, color: tokens.accent),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${book.author} • ${book.subject}',
                          style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${book.totalPages} pages • $sizeText',
                          style: TextStyle(color: tokens.accent, fontSize: 11.5, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Download this book for instant offline reading. Fast download (~$sizeText).',
                style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: tokens.accent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text('Download & Read ($sizeText)'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: () {
                    Navigator.of(ctx).pop(false);
                    _startDownloadAll(language: _selectedLanguage);
                  },
                  icon: Icon(Icons.all_inclusive_rounded, color: tokens.onSurfaceMuted, size: 16),
                  label: Text(
                    (_selectedLanguage == 'All')
                        ? 'Download All 181 Books (~13.4 MB)'
                        : 'Download All ${_languageNames[_selectedLanguage.toLowerCase()] ?? _selectedLanguage} Books',
                    style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true && mounted) {
      final success = await _bookService.downloadSingleBook(book.id, language: book.language);
      if (success && mounted) {
        setState(() {
          _installedBookIds.add(book.id);
        });
        _openReader(book);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to download "${book.title}". Please check internet connection.')),
        );
      }
    }
  }

  Future<void> _startDownloadAll({String? language}) async {
    final success = await _bookService.downloadAndInstall(language: language);
    if (success) {
      await _loadCatalog();
      if (mounted) {
        final count = _installedBookIds.length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Books library installed offline ($count books)!')),
        );
      }
    } else if (mounted && _bookService.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: ${_bookService.lastError}')),
      );
    }
  }

  void _showBookOptions(Book book) {
    final tokens = context.tokens;
    final isInstalled = _installedBookIds.contains(book.id);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: tokens.surfaceBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                book.title,
                style: TextStyle(
                  color: tokens.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'By ${book.author} • ${book.subject}',
                style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              if (!kIsWeb)
                if (isInstalled)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                    title: const Text('Remove Download', style: TextStyle(color: Colors.redAccent)),
                    subtitle: Text(
                      'Frees storage. Notes and reading progress are preserved.',
                      style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 11.5),
                    ),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await _bookService.removeBookDownload(book.id);
                      setState(() {
                        _installedBookIds.remove(book.id);
                      });
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Removed "${book.title}" from storage.')),
                        );
                      }
                    },
                  )
                else
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.download_rounded, color: tokens.accent),
                    title: Text('Download Book (${book.downloadSizeFormatted})', style: TextStyle(color: tokens.onSurface)),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _promptDownloadSingleBook(book);
                    },
                  ),
            ],
          ),
        ),
      ),
    );
  }

  void _openReader(Book book, {int? initialPage, int? initialLine}) async {
    final isInstalled = _installedBookIds.contains(book.id);
    if (!kIsWeb && !isInstalled) {
      _promptDownloadSingleBook(book);
      return;
    }

    final progress = _progressMap[book.id];
    int targetPage = 1;

    if (initialPage != null) {
      targetPage = initialPage;
    } else if (progress != null && progress.currentPage > 1) {
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

      if (shouldResume == null) return; // User cancelled
      targetPage = shouldResume ? progress.currentPage : 1;
    }

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

  Widget _buildLanguageFilterChips(AppTokens tokens) {
    if (_languages.length <= 1) return const SizedBox.shrink();

    return SizedBox(
      height: 40,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _languages.length,
        itemBuilder: (context, index) {
          final lang = _languages[index];
          final isSelected = _selectedLanguage.toLowerCase() == lang.toLowerCase();
          final label = _languageNames[lang.toLowerCase()] ?? lang.toUpperCase();

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              avatar: lang == 'All'
                  ? Icon(Icons.language_rounded, size: 15, color: isSelected ? Colors.white : tokens.accent)
                  : null,
              label: Text(label),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedLanguage = lang;
                  });
                  _loadCatalog();
                }
              },
              backgroundColor: tokens.surfaceVariant,
              selectedColor: tokens.accent,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : tokens.onSurface,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              side: BorderSide(
                color: isSelected ? tokens.accent : tokens.surfaceBorder,
                width: 0.8,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSubjectFilterChips(AppTokens tokens) {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _subjects.length,
        itemBuilder: (context, index) {
          final s = _subjects[index];
          final isSelected = _selectedSubject == s;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(s),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedSubject = s;
                  });
                  _loadCatalog();
                }
              },
              backgroundColor: tokens.surfaceVariant,
              selectedColor: tokens.accent,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : tokens.onSurface,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12.5,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              side: BorderSide(
                color: isSelected ? tokens.accent : tokens.surfaceBorder,
                width: 0.8,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchBar(AppTokens tokens) {
    return Container(
      height: 44,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      decoration: BoxDecoration(
        color: tokens.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: tokens.onSurface, fontSize: 13.5),
        decoration: InputDecoration(
          hintText: _totalBooksCount > 0
              ? 'Search $_totalBooksCount books by title, author, or subject...'
              : 'Search books by title, author, or subject...',
          hintStyle: TextStyle(color: tokens.onSurfaceMuted, fontSize: 13),
          prefixIcon: Icon(Icons.search, color: tokens.onSurfaceMuted, size: 19),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: tokens.onSurfaceMuted, size: 17),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                    _loadCatalog();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 11),
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Icon(Icons.history_rounded, size: 17, color: tokens.accent),
              const SizedBox(width: 6),
              Text(
                'Continue Reading',
                style: TextStyle(
                  color: tokens.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 14.5,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 120,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: _recentBooks.length,
            itemBuilder: (context, index) {
              final book = _recentBooks[index];
              final progress = _progressMap[book.id];
              final percent = progress?.completionPercent ?? 0.0;

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
                                  imageUrl: 'https://raw.githubusercontent.com/${AppConfig.releasesRepo}/main/books/covers/${book.coverFile}',
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) => Icon(Icons.menu_book, color: tokens.accent, size: 22),
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
                                value: percent,
                                minHeight: 3.5,
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
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildSubjectShelf(String subject, List<Book> books, AppTokens tokens) {
    if (books.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Text(
                subject,
                style: TextStyle(
                  color: tokens.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${books.length}',
                  style: TextStyle(
                    color: tokens.accent,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 255,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: books.length,
            itemBuilder: (context, index) {
              final book = books[index];
              final isInstalled = _installedBookIds.contains(book.id);
              final isDownloading = _bookService.isBookDownloading(book.id);

              return Container(
                width: 140,
                margin: const EdgeInsets.only(right: 12),
                child: BookCard(
                  book: book,
                  progress: _progressMap[book.id],
                  isInstalled: isInstalled,
                  isDownloading: isDownloading,
                  onTap: () => _openReader(book),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
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
              'Books Library',
              style: TextStyle(
                color: tokens.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              _totalBooksCount > 0
                  ? '$_totalBooksCount Books • Zac Poonen'
                  : 'Books Library • Zac Poonen',
              style: TextStyle(
                color: tokens.onSurfaceMuted,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.download_for_offline_rounded,
              color: tokens.onSurfaceMuted,
              size: 21,
            ),
            tooltip: 'Offline Downloads & Commentaries',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DownloadsManagerScreen(initialTab: 3),
                ),
              ).then((_) => _loadCatalog());
            },
          ),
          IconButton(
            icon: Icon(
              _viewBySubjects ? Icons.grid_view_rounded : Icons.view_agenda_rounded,
              color: tokens.onSurfaceMuted,
              size: 21,
            ),
            tooltip: _viewBySubjects ? 'Show flat grid' : 'Group by subjects',
            onPressed: () {
              setState(() => _viewBySubjects = !_viewBySubjects);
            },
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: tokens.onSurfaceMuted, size: 21),
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
                      'Loading books catalog...',
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
                    child: _buildLanguageFilterChips(tokens),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 6),
                  ),
                  SliverToBoxAdapter(
                    child: _buildSubjectFilterChips(tokens),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 4),
                  ),
                  SliverToBoxAdapter(
                    child: _buildContinueReading(tokens),
                  ),

                  // If browsing all books with subjects view enabled:
                  if (_viewBySubjects && _selectedSubject == 'All' && _searchQuery.isEmpty) ...[
                    for (final entry in _booksBySubject.entries)
                      SliverToBoxAdapter(
                        child: _buildSubjectShelf(entry.key, entry.value, tokens),
                      ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 40),
                    ),
                  ] else ...[
                    // Filtered or Flat Grid view
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 170,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.58,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final book = _books[index];
                            final isInstalled = _installedBookIds.contains(book.id);
                            final isDownloading = _bookService.isBookDownloading(book.id);

                            return GestureDetector(
                              onLongPress: () => _showBookOptions(book),
                              child: BookCard(
                                book: book,
                                progress: _progressMap[book.id],
                                isInstalled: isInstalled,
                                isDownloading: isDownloading,
                                onTap: () => _openReader(book),
                              ),
                            );
                          },
                          childCount: _books.length,
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
