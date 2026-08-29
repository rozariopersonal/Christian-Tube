import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/bible_version.dart';
import '../../engines/scripture/services/bible_download_manager.dart';
import '../../engines/scripture/services/book_name_service.dart';
import '../../engines/scripture/services/local_bible_service.dart';
import '../../engines/scripture/widgets/bible_version_picker_modal.dart';
import '../../engines/scripture/widgets/compare_version_picker_sheet.dart';
import '../../engines/scripture/screens/bible_manager_screen.dart';
import 'package:flutter/services.dart';
import '../widgets/verse_text.dart';
import '../widgets/book_chapter_selector.dart';
import '../widgets/reading_settings_sheet.dart';
import '../widgets/verse_action_bar.dart';
import '../widgets/bible_search_sheet.dart';
import '../screens/bible_bookmarks_screen.dart';
import '../../../core/theme/app_tokens.dart';
import '../models/bible_verse.dart';
import '../models/bible_book.dart';
import '../models/bible_settings.dart';
import '../services/bible_settings_service.dart';
import '../services/bible_bookmark_service.dart';

class BibleScreen extends StatefulWidget {
  const BibleScreen({super.key});

  @override
  State<BibleScreen> createState() => _BibleScreenState();
}

class _BibleScreenState extends State<BibleScreen> {
  final LocalBibleService _localBibleService = LocalBibleService();
  final BibleSettingsService _settingsService = BibleSettingsService();
  final BibleBookmarkService _bookmarkService = BibleBookmarkService();
  final BibleDownloadManager _downloadManager = BibleDownloadManager();
  final BookNameService _bookNames = BookNameService();
  final ScrollController _scrollController = ScrollController();

  List<BibleVersion> _versions = [];
  List<BibleVerse> _verses = [];
  BibleVersion? _selectedVersion;
  BibleVersion? _secondaryVersion;
  String _currentBook = 'Genesis';
  int _currentChapter = 1;
  bool _isLoading = true;
  bool _isFetchingNextChapter = false;
  int _transitionDirection = 1;
  int _lastKnownInstalledCount = -1;
  bool _chapterEmpty = false;

  final Set<int> _selectedVerses = {};
  BibleSettings _settings = const BibleSettings();
  bool _settingsLoaded = false;
  bool _resumeApplied = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _downloadManager.addListener(_onDownloadManagerChanged);
    _bookNames.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    _loadSettings();
    _fetchData();
  }

  int _bookNumber(String book) =>
      BookNameService.englishBookNames.indexOf(book) + 1;

  String _displayBookName(String book) =>
      _bookNames.nameFor(_selectedVersion?.shortname ?? 'TAOBVSI', _bookNumber(book));

  Future<void> _loadSettings() async {
    final settings = await _settingsService.loadSettings();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _settingsLoaded = true;
    });
    final applied = _applySavedProgress();
    if (applied && _selectedVersion != null) {
      await _loadChapter();
    }
  }

  /// Restores the user's last reading position. Returns true when a saved
  /// location was applied (and therefore the chapter should be re-loaded).
  bool _applySavedProgress() {
    if (_resumeApplied || !_settingsLoaded || !_settings.hasProgress) return false;
    _resumeApplied = true;
    final savedBook = _settings.lastBook;
    final savedChapter = _settings.lastChapter;
    final savedVersion = _settings.lastVersion;
    if (savedBook == null) return false;
    if (_versions.any((v) => v.shortname == savedVersion)) {
      _selectedVersion =
          _versions.firstWhere((v) => v.shortname == savedVersion);
    }
    _currentBook = savedBook;
    _currentChapter = savedChapter;
    return true;
  }

  @override
  void dispose() {
    _downloadManager.removeListener(_onDownloadManagerChanged);
    _scrollController.dispose();
    super.dispose();
  }

  // Reacts only to install/uninstall transitions (not to per-chunk download
  // progress notifications) so the page fills in automatically when the
  // default bible finishes downloading in the background.
  Future<void> _onDownloadManagerChanged() async {
    if (!mounted) return;
    final count = _downloadManager.installedIds.length;
    if (count == _lastKnownInstalledCount) return;
    _lastKnownInstalledCount = count;

    final hadVersions = _versions.isNotEmpty;
    await _loadVersions();
    if (!mounted) return;
    if (_selectedVersion != null) {
      if (!hadVersions) setState(() => _isLoading = true);
      await _loadChapter();
      if (mounted) setState(() => _isLoading = false);
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pushManager() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BibleManagerScreen()),
    );
    // Refetch versions after returning from the manager screen
    _lastKnownInstalledCount = _downloadManager.installedIds.length;
    await _fetchData();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 500 && !_isFetchingNextChapter) {
      _fetchNextChapter(append: true);
    }
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    await _loadVersions();
    if (!mounted) return;
    if (_selectedVersion != null) {
      await _loadChapter();
      if (mounted) setState(() => _isLoading = false);
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadVersions() async {
    final versionIds = await _localBibleService.getInstalledVersionIds();
    if (!mounted) return;
    _versions = versionIds.map((id) {
      final meta = BibleDownloadManager.getMeta(id);
      return BibleVersion(
        id: id,
        name: meta.id == id ? meta.name : id,
        shortname: id,
        description: meta.description,
        lang: meta.languageCode,
      );
    }).toList();
    if (_versions.isNotEmpty && _selectedVersion == null) {
      _selectedVersion = _versions.firstWhere(
        (v) => v.shortname == BibleDownloadManager.defaultVersionId,
        orElse: () => _versions.first,
      );
    } else if (_selectedVersion != null &&
        !_versions.any((v) => v.shortname == _selectedVersion!.shortname)) {
      // Previously selected version was removed; fall back to the default.
      _selectedVersion =
          _versions.isNotEmpty ? _versions.first : null;
    }
    _applySavedProgress();
  }

  /// Merges the primary and (optional) secondary chapter verse maps into a
  /// single stacked list aligned by verse number: for each verse, the primary
  /// rendering is followed by the secondary rendering when the sources differ.
  List<BibleVerse> _mergeChapterVerses(
    List<Map<String, dynamic>> primaryMap,
    List<Map<String, dynamic>>? secondaryMap,
    String primaryId,
    String? secondaryId,
  ) {
    final primaryByNum = {
      for (final m in primaryMap) m['verse'] as int: m['text'] as String,
    };
    final secondaryByNum = secondaryMap == null
        ? null
        : {
            for (final m in secondaryMap) m['verse'] as int: m['text'] as String,
          };

    final verseNumbers = <int>{...primaryByNum.keys, ...?secondaryByNum?.keys}.toList()
      ..sort((a, b) => a.compareTo(b));

    final merged = <BibleVerse>[];
    for (final n in verseNumbers) {
      final primaryText = primaryByNum[n];
      if (primaryText != null) {
        merged.add(BibleVerse(
          number: n,
          text: primaryText,
          versionLabel: primaryId,
        ));
      }
      final secondaryText = secondaryByNum?[n];
      if (secondaryText != null && secondaryText != primaryText) {
        merged.add(BibleVerse(
          number: n,
          text: secondaryText,
          versionLabel: secondaryId,
          isSecondary: true,
        ));
      }
    }
    return merged;
  }

  /// Fetches [book] [chapter] for both the primary and secondary versions.
  Future<List<Map<String, dynamic>>> _fetchVersesForChapter(
    BibleVersion version,
    String book,
    int chapter,
  ) async {
    try {
      return await _localBibleService.getChapter(version.shortname, book, chapter);
    } catch (_) {
      return [];
    }
  }

  Future<void> _loadChapter() async {
    if (_selectedVersion == null) return;
    final primaryMap = await _fetchVersesForChapter(
        _selectedVersion!, _currentBook, _currentChapter);
    List<Map<String, dynamic>>? secondaryMap;
    if (_secondaryVersion != null) {
      secondaryMap = await _fetchVersesForChapter(
          _secondaryVersion!, _currentBook, _currentChapter);
    }
    if (!mounted) return;
    final merged = _mergeChapterVerses(
      primaryMap,
      secondaryMap,
      _selectedVersion!.shortname,
      _secondaryVersion?.shortname,
    );
    setState(() {
      _verses = merged;
      _chapterEmpty = merged.isEmpty;
      _selectedVerses.clear();
    });
    // Scroll to top when data is re-fetched completely
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    if (merged.isNotEmpty) {
      _settingsService.saveReadingProgress(
        _selectedVersion!.shortname,
        _currentBook,
        _currentChapter,
      );
    }
  }

  Future<void> _fetchNextChapter({bool append = false}) async {
    if (_isFetchingNextChapter || _selectedVersion == null) return;
    
    setState(() {
      _isFetchingNextChapter = true;
      if (!append) _transitionDirection = 1;
    });
    
    int maxChapters = bibleBooks[_currentBook] ?? 1;
    String nextBook = _currentBook;
    int nextChapter = _currentChapter + 1;

    if (nextChapter > maxChapters) {
      final books = bibleBooks.keys.toList();
      final currentIndex = books.indexOf(_currentBook);
      if (currentIndex < books.length - 1) {
        nextBook = books[currentIndex + 1];
        nextChapter = 1;
      } else {
        // End of Bible
        setState(() => _isFetchingNextChapter = false);
        return;
      }
    }

    final primaryMap =
        await _fetchVersesForChapter(_selectedVersion!, nextBook, nextChapter);
    List<Map<String, dynamic>>? secondaryMap;
    if (_secondaryVersion != null) {
      secondaryMap = await _fetchVersesForChapter(
          _secondaryVersion!, nextBook, nextChapter);
    }

    final newVerses = _mergeChapterVerses(
      primaryMap,
      secondaryMap,
      _selectedVersion!.shortname,
      _secondaryVersion?.shortname,
    );

    if (mounted) {
      setState(() {
        _currentBook = nextBook;
        _currentChapter = nextChapter;
        
        if (append) {
          _verses.add(BibleVerse(
            number: 0,
            text: '',
            isChapterHeader: true,
            chapterTitle: '${_displayBookName(nextBook)} $nextChapter',
          ));
          _verses.addAll(newVerses);
        } else {
          _verses = newVerses;
          _selectedVerses.clear();
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(0);
          }
        }
        _isFetchingNextChapter = false;
      });
    }
  }

  Future<void> _fetchPrevChapter() async {
    if (_selectedVersion == null) return;

    String prevBook = _currentBook;
    int prevChapter = _currentChapter - 1;

    if (prevChapter < 1) {
      final books = bibleBooks.keys.toList();
      final currentIndex = books.indexOf(_currentBook);
      if (currentIndex > 0) {
        prevBook = books[currentIndex - 1];
        prevChapter = bibleBooks[prevBook] ?? 1;
      } else {
        // Beginning of Bible
        return;
      }
    }

    setState(() {
      _currentBook = prevBook;
      _currentChapter = prevChapter;
      _transitionDirection = -1;
      _isLoading = true;
    });

    await _fetchData();
  }

  void _showVersionSelector() {
    if (_selectedVersion == null) return;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BibleVersionPickerModal(
        activeVersionId: _selectedVersion!.shortname,
        onSelectVersion: (versionId) {
          final version = _versions.firstWhere(
            (v) => v.shortname == versionId,
            orElse: () {
              final meta = BibleDownloadManager.getMeta(versionId);
              return BibleVersion(
                id: versionId,
                name: meta.name,
                shortname: versionId,
                description: meta.description,
                lang: meta.languageCode,
              );
            },
          );
          setState(() {
            _selectedVersion = version;
          });
          _fetchData();
        },
        onOpenManager: _pushManager,
      ),
    );
  }

  void _showSecondaryVersionSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CompareVersionPickerSheet(
        activeVersionId: _selectedVersion?.shortname ?? 'TAOBVSI',
        currentComparisonId: _secondaryVersion?.shortname,
        onSelectComparison: (versionId) {
          setState(() {
            _secondaryVersion = versionId == null
                ? null
                : _versions.firstWhere(
                    (v) => v.shortname == versionId,
                    orElse: () {
                      final meta = BibleDownloadManager.getMeta(versionId);
                      return BibleVersion(
                        id: versionId,
                        name: meta.name,
                        shortname: versionId,
                        description: meta.description,
                        lang: meta.languageCode,
                      );
                    },
                  );
          });
          _loadChapter();
        },
      ),
    );
  }

  void _showBookChapterSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BookChapterSelector(
        currentBook: _currentBook,
        currentChapter: _currentChapter,
        displayNameOf: (canonicalBook, bookNumber) => _bookNames.nameFor(
          _selectedVersion?.shortname ?? 'TAOBVSI',
          bookNumber,
        ),
        onSelection: (book, chapter) {
          setState(() {
            _currentBook = book;
            _currentChapter = chapter;
          });
          Navigator.pop(context);
          _fetchData();
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    final isDownloading = _downloadManager.isDownloading(
        BibleDownloadManager.defaultVersionId);
    final progress = _downloadManager.getProgress(
        BibleDownloadManager.defaultVersionId);

    if (isDownloading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Downloading the Tamil Bible (${BibleDownloadManager.defaultVersionId})…',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No Bibles installed yet.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Download one from the Bible Translations page.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pushManager,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Manage Bibles'),
            ),
          ],
        ),
      ),
    );
  }

  void _showReadingSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return ReadingSettingsSheet(
            settings: _settings,
            onSettingsChanged: (newSettings) {
              setModalState(() => _settings = newSettings);
              setState(() => _settings = newSettings);
              _settingsService.saveSettings(newSettings);
            },
          );
        },
      ),
    );
  }

  void _jumpToReference(String book, int chapter) {
    setState(() {
      _currentBook = book;
      _currentChapter = chapter;
      _selectedVerses.clear();
    });
    _fetchData();
  }

  void _showSearch() {
    if (_selectedVersion == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BibleSearchSheet(
        versionId: _selectedVersion!.shortname,
        onJumpTo: _jumpToReference,
      ),
    );
  }

  void _openBookmarks() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BibleBookmarksScreen(
          onJumpTo: _jumpToReference,
        ),
      ),
    );
  }

  void _toggleVerseSelection(int verseNumber) {
    if (verseNumber == 0) return; // Ignore headers
    setState(() {
      if (_selectedVerses.contains(verseNumber)) {
        _selectedVerses.remove(verseNumber);
      } else {
        _selectedVerses.add(verseNumber);
      }
    });
  }

  String _selectedText({String prefix = ''}) {
    if (_selectedVerses.isEmpty) return '';
    return _verses
        .where((v) => _selectedVerses.contains(v.number))
        .map((v) => '$prefix[${v.number}] ${v.text}')
        .join('\n');
  }

  void _copySelectedVerses() {
    if (_selectedVerses.isEmpty) return;
    final selectedTexts = _selectedText();
    Clipboard.setData(ClipboardData(text: selectedTexts)).then((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verses copied to clipboard')),
        );
        setState(() => _selectedVerses.clear());
      }
    });
  }

  void _shareSelectedVerses() {
    if (_selectedVerses.isEmpty) return;
    final header = _selectedVersion != null
        ? '$_currentBook $_currentChapter · ${_selectedVersion!.shortname}'
        : '$_currentBook $_currentChapter';
    final text = _selectedText();
    final shareBody = text.isEmpty
        ? header
        : '$header\n$text\n\n— Christian Tube Bible';
    Share.share(shareBody);
    setState(() => _selectedVerses.clear());
  }

  Future<void> _bookmarkSelectedVerses() async {
    if (_selectedVerses.isEmpty || _selectedVersion == null) return;
    final selected = _verses
        .where((v) => _selectedVerses.contains(v.number))
        .toList();
    if (selected.isEmpty) return;

    var added = 0;
    var removed = 0;
    for (final v in selected) {
      final isNowBookmarked = await _bookmarkService.toggle(
        versionId: _selectedVersion!.shortname,
        book: _currentBook,
        chapter: _currentChapter,
        verse: v.number,
        text: v.text,
      );
      if (isNowBookmarked) {
        added++;
      } else {
        removed++;
      }
    }
    if (!mounted) return;
    setState(() => _selectedVerses.clear());
    final message = added > removed
        ? '$added verse${added == 1 ? '' : 's'} bookmarked'
        : removed > added
            ? '$removed verse${removed == 1 ? '' : 's'} removed from bookmarks'
            : 'Bookmarks updated';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _redownloadDefault() async {
    setState(() {
      _chapterEmpty = false;
      _isLoading = true;
    });
    await BibleDownloadManager().forceRedownloadDefault();
  }

  Widget _buildContent() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_versions.isEmpty) return _buildEmptyState();
    if (_chapterEmpty) return _buildChapterEmptyState();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) {
        final inAnimation = Tween<Offset>(
                begin: Offset(_transitionDirection.toDouble(), 0.0),
                end: Offset.zero)
            .animate(animation);
        final outAnimation = Tween<Offset>(
                begin: Offset(-_transitionDirection.toDouble(), 0.0),
                end: Offset.zero)
            .animate(animation);

        if (child.key == ValueKey('$_currentBook-$_currentChapter')) {
          return SlideTransition(position: inAnimation, child: child);
        } else {
          return SlideTransition(position: outAnimation, child: child);
        }
      },
      child: ListView.builder(
        key: ValueKey('$_currentBook-$_currentChapter'),
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 16),
        itemCount: _verses.length + (_isFetchingNextChapter ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _verses.length) {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return VerseText(
            verse: _verses[index],
            isSelected: _selectedVerses.contains(_verses[index].number),
            fontSize: _settings.fontSize,
            onTap: () => _toggleVerseSelection(_verses[index].number),
          );
        },
      ),
    );
  }

  Widget _buildChapterEmptyState() {
    if (_downloadManager
        .isDownloading(BibleDownloadManager.defaultVersionId)) {
      return _buildEmptyState();
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined,
                size: 40,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'No verses found for ${_displayBookName(_currentBook)} $_currentChapter.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'The offline copy of this translation may be incomplete.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _redownloadDefault,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Re-download Tamil Bible'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _showBookChapterSelector,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_displayBookName(_currentBook)} $_currentChapter',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
        actions: [
          if (_selectedVersion != null)
            PopupMenuButton<String>(
              tooltip: 'Versions',
              onSelected: (value) {
                if (value == 'primary') {
                  _showVersionSelector();
                } else if (value == 'secondary') {
                  _showSecondaryVersionSelector();
                } else if (value == 'none') {
                  setState(() => _secondaryVersion = null);
                  _loadChapter();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'primary',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text('Primary: ${_selectedVersion!.shortname}'),
                    ],
                  ),
                ),
                if (_secondaryVersion != null)
                  PopupMenuItem<String>(
                    value: 'secondary',
                    child:
                        Text('Edit secondary: ${_secondaryVersion!.shortname}'),
                  )
                else
                  const PopupMenuItem<String>(
                    value: 'secondary',
                    child: Text('Add secondary version…'),
                  ),
                const PopupMenuItem<String>(
                  value: 'none',
                  child: Text('No secondary version'),
                ),
              ],
              child: Container(
                margin: const EdgeInsets.only(right: 2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: _secondaryVersion == null ? 0.12 : 0.18),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _secondaryVersion == null
                        ? context.tokens.surfaceBorder
                        : Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  _secondaryVersion?.shortname ?? '+ Compare',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: _secondaryVersion == null
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Search Bible',
            icon: const Icon(Icons.search),
            onPressed: _showSearch,
          ),
          IconButton(
            tooltip: 'Bookmarks',
            icon: const Icon(Icons.bookmark_border),
            onPressed: _openBookmarks,
          ),
          IconButton(
            tooltip: 'Reading settings',
            icon: const Icon(Icons.text_format),
            onPressed: _showReadingSettings,
          ),
          if (_selectedVersion != null)
            TextButton(
              onPressed: _showVersionSelector,
              child: Text(
                _selectedVersion!.shortname,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _buildContent(),
          ),
          if (_selectedVerses.isNotEmpty)
            VerseActionBar(
              selectedCount: _selectedVerses.length,
              onCopy: _copySelectedVerses,
              onShare: _shareSelectedVerses,
              onBookmark: _bookmarkSelectedVerses,
              onClear: () => setState(() => _selectedVerses.clear()),
            )
          else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: context.tokens.background,
              boxShadow: [
                BoxShadow(
                  color: context.tokens.scrim.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: _fetchPrevChapter,
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Prev'),
                ),
                TextButton.icon(
                  onPressed: () => _fetchNextChapter(append: false),
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('Next'),
                  iconAlignment: IconAlignment.end,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
