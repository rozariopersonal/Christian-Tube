import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/github_data_service.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/services/library_languages_controller.dart';
import '../../../shared/ui/language_dropdown.dart';
import '../../../shared/ui/language_meta.dart';
import '../../articles/models/wftw_index_entry.dart';
import '../../articles/services/wftw_index_service.dart';
import '../../articles/widgets/wftw_shelf.dart';
import '../../books/models/book.dart';
import '../../books/models/user_reading_progress.dart';
import '../../books/screens/book_reader_screen.dart';
import '../../songs/models/song.dart';
import '../../songs/services/songs_catalog_service.dart';
import '../../songs/widgets/song_shelf.dart';
import '../services/library_data_loader.dart';

/// Library hub — one scrolling landing for everything users read:
/// recent books (with progress), the Word-for-the-Week teachings, and the
/// multi-language Articles collection.
class LibraryScreen extends StatefulWidget {
  final LibraryDataLoader? loader;
  final WftwIndexLoader? wftwLoader;
  final ArticlesCatalogLoader? articlesLoader;
  final ArticlesLanguagesLoader? languagesLoader;
  final SongsCatalogLoader? songsLoader;

  const LibraryScreen({
    super.key,
    this.loader,
    this.wftwLoader,
    this.articlesLoader,
    this.languagesLoader,
    this.songsLoader,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final LibraryDataLoader _loader;
  late final WftwIndexLoader _wftwLoader;
  late final ArticlesCatalogLoader _articlesLoader;
  late final ArticlesLanguagesLoader _languagesLoader;
  late final SongsCatalogLoader _songsLoader;
  late final LibraryLanguagesController _langController;

  List<Book> _recentBooks = const [];
  List<Book> _allBooks = const [];
  Map<String, UserReadingProgress> _progressMap = const {};
  List<WftwIndexEntry> _wftwRecent = const [];
  List<WftwIndexEntry> _articlesRecent = const [];
  List<WftwIndexEntry> _allArticles = const [];
  List<Song> _songs = const [];
  List<Song> _allSongs = const [];
  Map<String, String> _langNameByCode = const {};
  List<String> _articleLangChips = const [];
  bool _loading = true;

  static const int _recentBookLimit = 10;
  static const int _wftwShelfCount = 8;
  static const int _songShelfCount = 10;

  @override
  void initState() {
    super.initState();
    _loader = widget.loader ?? BookServiceLibraryLoader();
    _wftwLoader =
        widget.wftwLoader ?? () => WftwIndexService().getIndex();
    _articlesLoader = widget.articlesLoader ??
        () => WftwIndexService().getArticlesIndex();
    _languagesLoader =
        widget.languagesLoader ?? WftwIndexService().getLanguages;
    _songsLoader = widget.songsLoader ??
        () => SongsCatalogService().getSongs();
    _langController = LibraryLanguagesController()
      ..addListener(_onLanguagesChanged);
    _loadData();
  }

  @override
  void dispose() {
    _langController.removeListener(_onLanguagesChanged);
    _langController.dispose();
    super.dispose();
  }

  void _onLanguagesChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _announceLanguages(
    List<Book> books,
    List<WftwIndexEntry> articles,
    List<Song> songs,
  ) {
    final codes = <String>{};
    for (final b in books) {
      if (b.language.isNotEmpty) codes.add(b.language);
    }
    for (final a in articles) {
      if (a.lang.isNotEmpty) codes.add(a.lang);
    }
    for (final s in songs) {
      if (s.language.isNotEmpty) codes.add(s.language);
    }
    _langController.announceLanguages(codes);
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

      final List<WftwIndexEntry> allArticles = [];
      Map<String, String> langNames = const {};
      try {
        allArticles.addAll(await _articlesLoader());
        final languages = await _languagesLoader();
        langNames = {
          for (final l in languages) l.code: l.name,
        };
        for (final l in languages) {
          if (l.code.isNotEmpty) {
            // Teach the shared language registry about catalog languages it
            // does not already know so codes are shown as names, never as raw
            // ISO codes.
            LanguageMeta.registerLanguage(l.code, englishName: l.name);
          }
        }
        _articleLangChips = languages.map((l) => l.name).take(6).toList();
      } catch (e) {
        debugPrint('Articles shelf unavailable: $e');
      }
      final articles = allArticles.length <= _wftwShelfCount
          ? allArticles
          : allArticles.sublist(0, _wftwShelfCount);

      List<WftwIndexEntry> index = const [];
      try {
        final loaded = await _wftwLoader();
        index = loaded.length <= _wftwShelfCount
            ? loaded
            : loaded.sublist(0, _wftwShelfCount);
      } catch (e) {
        debugPrint('Word for the Week shelf unavailable: $e');
      }

      final List<Song> allSongs = [];
      try {
        allSongs.addAll(await _songsLoader());
      } catch (e) {
        debugPrint('Songs shelf unavailable: $e');
      }
      final songs = allSongs.length <= _songShelfCount
          ? allSongs
          : allSongs.sublist(0, _songShelfCount);

      if (!mounted) return;
      _announceLanguages(books, allArticles, allSongs);
      setState(() {
        _recentBooks = recentBooks;
        _allBooks = books;
        _allArticles = allArticles;
        _allSongs = allSongs;
        _progressMap = progressMap;
        _wftwRecent = index;
        _articlesRecent = articles;
        _songs = songs;
        _langNameByCode = langNames;
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
              'Books • Songs • Teachings • Articles',
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
                      child: _buildLanguageFilter(tokens),
                    ),
                    SliverToBoxAdapter(
                      child: _buildBooksSection(tokens),
                    ),
                    if (_filteredSongs.isNotEmpty)
                      SliverToBoxAdapter(
                        child: SongShelf(
                          songs: _filteredSongs,
                          onViewAll: _openSongs,
                          onTapSong: _openSong,
                        ),
                      ),
                    if (_wftwRecent.isNotEmpty)
                      SliverToBoxAdapter(
                        child: WftwShelf(
                          entries: _wftwRecent,
                          onViewAll: _openTeachings,
                          onTapArticle: _openWftwArticle,
                        ),
                      ),
                    if (_articlesRecent.isNotEmpty)
                      SliverToBoxAdapter(
                        child: WftwShelf(
                          entries: _filteredArticles,
                          title: 'Articles',
                          icon: Icons.article_outlined,
                          langNames: _articleLangChips,
                          langLabelOf: _articleLangLabel,
                          onViewAll: _openArticles,
                          onTapArticle: _openArticle,
                        ),
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

  Widget _buildLanguageFilter(AppTokens tokens) {
    final state = _langController.state;
    if (state.availableLanguages.length <= 1) return const SizedBox.shrink();

    final itemCounts = <String, int>{'All': _allItemCount};
    for (final code in state.availableLanguages) {
      if (code.toLowerCase() == 'all') continue;
      itemCounts[code] = _booksForLang(code).length +
          _articlesForLang(code).length +
          _songsForLang(code).length;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: LanguageDropdown(
        selectedLanguages: state.selectedLanguages,
        availableLanguages: state.availableLanguages,
        itemCounts: itemCounts,
        onLanguagesSelected: _langController.selectLanguages,
        itemNoun: 'items',
        headerTitle: 'Library Languages',
      ),
    );
  }

  List<Book> _booksForLang(String code) => _allBooks
      .where((b) => _canonical(b.language) == code.toLowerCase())
      .toList();

  List<WftwIndexEntry> _articlesForLang(String code) => _allArticles
      .where((a) => _canonical(a.lang) == code.toLowerCase())
      .toList();

  List<Song> _songsForLang(String code) => _allSongs
      .where((s) => _canonical(s.language) == code.toLowerCase())
      .toList();

  String _canonical(String raw) => LanguageMeta.canonicalCode(raw);

  int get _allItemCount =>
      _allBooks.length + _allArticles.length + _allSongs.length;

  List<Book> get _filteredBooks {
    final state = _langController.state;
    if (state.isAllLanguages) return _recentBooks;
    return _recentBooks
        .where((b) => state.includes(b.language))
        .toList();
  }

  List<WftwIndexEntry> get _filteredArticles {
    final state = _langController.state;
    final filtered = state.isAllLanguages
        ? _allArticles
        : _allArticles.where((a) => state.includes(a.lang)).toList();
    return filtered.length <= _wftwShelfCount
        ? filtered
        : filtered.sublist(0, _wftwShelfCount);
  }

  List<Song> get _filteredSongs {
    final state = _langController.state;
    if (state.isAllLanguages) return _songs;
    return _songs.where((s) => state.includes(s.language)).toList();
  }

  Widget _buildBooksSection(AppTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          tokens,
          icon: Icons.collections_bookmark_outlined,
          title: 'Books',
          onViewAll: () => context.push(
            '/books',
            extra: {'langController': _langController},
          ),
        ),
        if (_filteredBooks.isNotEmpty)
          SizedBox(
            height: 140,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _filteredBooks.length,
              itemBuilder: (context, index) {
                final book = _filteredBooks[index];
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
                onTap: () => context.push(
                  '/books',
                  extra: {'langController': _langController},
                ),
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

  void _openTeachings() {
    context.push('/teachings');
  }

  void _openArticles() {
    context.push('/articles', extra: {'langController': _langController});
  }

  void _openSongs() {
    context.push('/songs', extra: {'langController': _langController});
  }

  void _openSong(Song song) {
    context.push('/song/${song.id}', extra: song);
  }

  void _openWftwArticle(WftwIndexEntry entry) {
    context.push('/article/${entry.id}', extra: {'title': entry.title});
  }

  void _openArticle(WftwIndexEntry entry) {
    final lang = entry.lang == 'en' ? null : entry.lang;
    context.push(
      '/article/${entry.id}',
      extra: {'title': entry.title, if (lang != null) 'lang': lang},
    );
  }

  String? _articleLangLabel(WftwIndexEntry entry) {
    if (entry.lang == 'en') return null;
    final name = _langNameByCode[entry.lang];
    if (name != null && name.isNotEmpty) return name;
    final meta = LanguageMeta.fromCode(entry.lang);
    if (meta.englishName.isNotEmpty &&
        meta.englishName.toLowerCase() != entry.lang.toLowerCase()) {
      return meta.englishName;
    }
    return entry.lang.length <= 3 ? entry.lang.toUpperCase() : entry.lang;
  }
}