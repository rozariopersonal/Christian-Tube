import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/bible_version.dart';
import '../../engines/scripture/services/bible_download_manager.dart';
import '../../engines/scripture/services/book_name_service.dart';
import '../../engines/scripture/services/local_bible_service.dart';
import '../../downloads/screens/downloads_manager_screen.dart';
import 'package:flutter/services.dart';
import '../widgets/verse_item.dart';
import '../widgets/book_chapter_selector.dart';
import '../widgets/reading_settings_sheet.dart';
import '../models/bible_verse.dart';
import '../widgets/bible_search_sheet.dart';
import '../screens/bible_bookmarks_screen.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/layout/content_width.dart';
import '../models/bible_verse.dart';
import '../models/bible_book.dart';
import '../models/bible_settings.dart';
import '../models/cross_reference.dart';
import '../models/bible_background_note.dart';
import '../services/bible_settings_service.dart';
import '../services/bible_bookmark_service.dart';
import '../services/cross_reference_service.dart';
import '../services/bible_background_service.dart';
import '../screens/verse_study_screen.dart';
import '../../books/services/book_service.dart';
import '../../books/screens/books_catalog_screen.dart';

class BibleScreen extends StatefulWidget {
  const BibleScreen({
    super.key,
    this.initialVersionId,
    this.initialBook,
    this.initialChapter,
    this.initialVerse,
  });

  /// When launching the reader from the Words feed, [initialVersionId] activates
  /// the feed's version, [initialBook]/[initialChapter] position the reader at
  /// the passage, and [initialVerse] scrolls to / highlights the verse.
  final String? initialVersionId;
  final String? initialBook;
  final int? initialChapter;
  final int? initialVerse;

  @override
  State<BibleScreen> createState() => _BibleScreenState();
}

class _BibleScreenState extends State<BibleScreen> {
  final LocalBibleService _localBibleService = LocalBibleService();
  final BibleSettingsService _settingsService = BibleSettingsService();
  final BibleBookmarkService _bookmarkService = BibleBookmarkService();
  final BibleDownloadManager _downloadManager = BibleDownloadManager();
  final BookNameService _bookNames = BookNameService();
  final CrossReferenceService _crossRefService = CrossReferenceService();
  final BibleBackgroundService _backgroundService = BibleBackgroundService();
  final ScrollController _scrollController = ScrollController();

  List<BibleVersion> _versions = [];
  List<BibleVerse> _verses = [];
  BibleVersion? _selectedVersion;
  String _currentBook = 'Genesis';
  int _currentChapter = 1;
  bool _isLoading = true;
  bool _isFetchingNextChapter = false;
  int _lastKnownInstalledCount = -1;
  bool _chapterEmpty = false;

  final Set<int> _selectedVerses = {};
  BibleSettings _settings = const BibleSettings();
  bool _settingsLoaded = false;
  bool _resumeApplied = false;
  bool _initialJumpPending = true;

  // Per-verse GlobalKeys for pixel-perfect Scrollable.ensureVisible.
  final Map<int, GlobalKey> _verseKeys = {};
  int? _highlightedVerse;
  Timer? _highlightTimer;

  // Cross-reference state.
  final Set<int> _expandedCrossRefVerses = {};
  Map<int, List<CrossReference>> _chapterCrossRefs = {};
  Map<String, String> _crossRefTexts = {};
  bool _crossRefsInstalled = false;
  bool _crossRefsLoading = false;
  int _crossRefBookNumber = 0;
  int _crossRefChapter = 0;

  // Historical & cultural background state.
  Map<int, List<BibleBackgroundNote>> _chapterBackgrounds = {};

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
    _checkCrossRefsInstalled();
  }

  Future<void> _checkCrossRefsInstalled() async {
    try {
      final installed = await _crossRefService.isInstalled();
      if (!mounted) return;
      setState(() => _crossRefsInstalled = installed);
    } catch (e) {
      debugPrint('BibleScreen _checkCrossRefsInstalled error: $e');
    }
  }

  int _bookNumber(String book) =>
      BookNameService.englishBookNames.indexOf(book) + 1;

  String _displayBookName(String book) =>
      _bookNames.nameFor(_selectedVersion?.shortname ?? 'TAOBVSI', _bookNumber(book));

  Future<void> _loadSettings() async {
    try {
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
    } catch (e, stack) {
      debugPrint('BibleScreen _loadSettings error: $e\n$stack');
      if (mounted) {
        setState(() {
          _settingsLoaded = true;
        });
      }
    }
  }

  /// Restores the user's last reading position. Returns true when a saved
  /// location was applied (and therefore the chapter should be re-loaded).
  bool _applySavedProgress() {
    if (_resumeApplied) return false;
    _resumeApplied = true;
    // When launched from the Words feed, honor the requested passage/version
    // instead of the saved reading position.
    if (widget.initialBook != null || widget.initialVersionId != null) {
      return false;
    }
    if (!_settingsLoaded || !_settings.hasProgress) return false;
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

  /// Applies the reader-launch target (version + book + chapter + verse) once
  /// the installed versions are known.
  void _applyInitialJump() {
    if (!_initialJumpPending || _versions.isEmpty) return;
    final targetVersionId = widget.initialVersionId;
    if (targetVersionId != null &&
        _versions.any((v) => v.shortname == targetVersionId)) {
      _selectedVersion =
          _versions.firstWhere((v) => v.shortname == targetVersionId);
    }
    final targetBook = widget.initialBook;
    if (targetBook != null && bibleBooks.containsKey(targetBook)) {
      _currentBook = targetBook;
    }
    final targetChapter = widget.initialChapter;
    if (targetChapter != null && targetChapter >= 1) {
      _currentChapter = targetChapter;
    }
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
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
      MaterialPageRoute(builder: (context) => const DownloadsManagerScreen(initialTab: 1)),
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
    try {
      await _localBibleService.initialize();
      await _loadVersions();
      if (!mounted) return;
      if (_selectedVersion != null) {
        await _loadChapter();
      }
    } catch (e, stack) {
      debugPrint('BibleScreen _fetchData error: $e\n$stack');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
    _applyInitialJump();
    _applySavedProgress();
  }

  /// Builds the verse list for a single version's chapter, tagged with the
  /// version label so each row shows which translation it came from. Attaches
  /// each verse's cross-reference count from [_chapterCrossRefs] when the
  /// cross-reference data has been loaded for this chapter.
  List<BibleVerse> _buildChapterVerses(
    List<Map<String, dynamic>> chapterMap,
    String versionId,
  ) {
    final numbers = chapterMap.map((m) => (m['verse'] as num).toInt()).toList()
      ..sort((a, b) => a.compareTo(b));
    final verses = <BibleVerse>[];
    for (final n in numbers) {
      final text = chapterMap
          .firstWhere((m) => (m['verse'] as num).toInt() == n, orElse: () => const {})['text'];
      if (text == null) continue;
      verses.add(BibleVerse(
        number: n,
        text: text as String,
        versionLabel: versionId,
        crossReferenceCount: _chapterCrossRefs[n]?.length ?? 0,
      ));
    }
    return verses;
  }

  /// Loads cross-references for the chapter identified by [bookNumber] and
  /// [chapter], resolves their verse text in the selected version, and applies
  /// the results to the current reader state.
  ///
  /// When the bundled dataset is not installed, [CrossReferenceService] falls
  /// back to fetching the chapter on demand from the online `open-cross-ref`
  /// API so references still appear without the large download.
  Future<void> _loadCrossReferencesForChapter(
    int bookNumber,
    int chapter,
  ) async {
    if (_selectedVersion == null) return;
    final isNewChapter =
        bookNumber != _crossRefBookNumber || chapter != _crossRefChapter;
    if (_crossRefsLoading && isNewChapter) return;

    setState(() => _crossRefsLoading = true);
    Map<int, List<CrossReference>> chapterRefs;
    try {
      chapterRefs = await _crossRefService.getForChapter(
        bookNumber,
        chapter,
        // When installed, the local copy is authoritative (identical data);
        // otherwise pull the chapter from the network on demand.
        allowOnline: !_crossRefsInstalled,
      );
    } catch (_) {
      chapterRefs = {};
    }
    if (!mounted) return;

    // Resolve verse text for every distinct reference in this chapter.
    final passages = <(int, int, int, int?)>[];
    final seen = <String>{};
    for (final refs in chapterRefs.values) {
      for (final ref in refs) {
        if (seen.add(ref.textKey)) {
          passages.add((
            ref.bookNumber,
            ref.chapter,
            ref.verse,
            ref.endVerse,
          ));
        }
      }
    }
    Map<String, String> resolved = {};
    if (passages.isNotEmpty) {
      try {
        resolved = await _localBibleService.resolvePassages(
          versionId: _selectedVersion!.shortname,
          passages: passages,
        );
      } catch (_) {
        resolved = {};
      }
    }

    setState(() {
      _crossRefBookNumber = bookNumber;
      _crossRefChapter = chapter;
      _chapterCrossRefs = chapterRefs;
      _crossRefTexts = resolved;

      // Rebuild the verse rows so crossReferenceCount reflects the new data.
      _verses = _verses.map((v) {
        if (v.isChapterHeader) return v;
        return BibleVerse(
          number: v.number,
          text: v.text,
          versionLabel: v.versionLabel,
          isSecondary: v.isSecondary,
          crossReferenceCount: chapterRefs[v.number]?.length ?? 0,
        );
      }).toList();

      // Auto-expand verses with references when the user has the "expand all"
      // preference on. Verses with more than two references are left as a
      // badge that opens the dedicated references page, so they stay collapsed
      // here even with the preference enabled.
      if (_settings.expandCrossReferences) {
        _expandedCrossRefVerses.addAll(
          chapterRefs.keys.where((v) => (chapterRefs[v]?.length ?? 0) <= 2),
        );
      }
      _crossRefsLoading = false;
    });
  }

  /// Fetches [book] [chapter] for [version].
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
    if (!mounted) return;
    final verses = _buildChapterVerses(primaryMap, _selectedVersion!.shortname);
    setState(() {
      _verses = verses;
      _chapterEmpty = verses.isEmpty;
      _selectedVerses.clear();
      _verseKeys.clear(); // fresh chapter — old keys are no longer valid
      _highlightedVerse = null;
      _expandedCrossRefVerses.clear();
      _chapterCrossRefs = {};
      _crossRefTexts = {};
      _crossRefBookNumber = 0;
      _crossRefChapter = 0;
      _chapterBackgrounds = {};
    });
    // Kick off cross-reference and cultural background loading for this chapter.
    _loadCrossReferencesForChapter(_bookNumber(_currentBook), _currentChapter);
    _loadBackgroundsForChapter(_bookNumber(_currentBook), _currentChapter);
    // Scroll to the launched verse (when present) or top when re-fetched.
    final shouldScrollToVerse = widget.initialVerse != null;
    if (shouldScrollToVerse) {
      _initialJumpPending = false;
      final targetVerse = widget.initialVerse!;
      // Wait two frames: one for setState to finish, one for the list to lay out.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToVerse(targetVerse);
        });
      });
    } else if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    if (verses.isNotEmpty) {
      _settingsService.saveReadingProgress(
        _selectedVersion!.shortname,
        _currentBook,
        _currentChapter,
      );
    }
  }

  /// Scrolls the reader so a target verse is near the top of the viewport,
  /// then highlights it for 5 seconds.
  void _scrollToVerse(int verseNumber) {
    // Resolve which key to use: exact match or nearest verse.
    GlobalKey? key = _verseKeys[verseNumber];
    if (key == null) {
      // Find the closest verse number that has a key.
      int best = -1;
      for (final k in _verseKeys.keys) {
        if (best == -1 || (k - verseNumber).abs() < (best - verseNumber).abs()) {
          best = k;
        }
      }
      if (best != -1) key = _verseKeys[best];
    }

    final BuildContext? ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
        alignment: 0.1, // show near top of viewport
      );
    }

    // Start 5-second highlight.
    _highlightTimer?.cancel();
    setState(() => _highlightedVerse = verseNumber);
    _highlightTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _highlightedVerse = null);
    });
  }

  Future<void> _fetchNextChapter({bool append = false}) async {
    if (_isFetchingNextChapter || _selectedVersion == null) return;
    
    setState(() {
      _isFetchingNextChapter = true;
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

    final newVerses =
        _buildChapterVerses(primaryMap, _selectedVersion!.shortname);

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

    // Now load cross-references asynchronously in the background.
    _loadCrossReferencesForAppendedChapter(nextBook, nextChapter, newVerses);
  }

  Future<void> _loadCrossReferencesForAppendedChapter(String book, int chapter, List<BibleVerse> appendedVerses) async {
    if (!mounted || _selectedVersion == null) return;
    
    Map<int, List<CrossReference>> nextRefs = {};
    Map<String, String> nextTexts = {};
    try {
      nextRefs = await _crossRefService.getForChapter(
        _bookNumber(book),
        chapter,
        allowOnline: !_crossRefsInstalled,
      );
    } catch (_) {
      return;
    }
    
    if (nextRefs.isEmpty) return;

    final passages = <(int, int, int, int?)>[];
    final seen = <String>{};
    for (final refs in nextRefs.values) {
      for (final ref in refs) {
        if (seen.add(ref.textKey)) {
          passages.add((ref.bookNumber, ref.chapter, ref.verse, ref.endVerse));
        }
      }
    }
    if (passages.isNotEmpty) {
      try {
        nextTexts = await _localBibleService.resolvePassages(
          versionId: _selectedVersion!.shortname,
          passages: passages,
        );
      } catch (_) {}
    }

    if (!mounted) return;

    setState(() {
      _chapterCrossRefs.addAll(nextRefs);
      _crossRefTexts.addAll(nextTexts);
      if (_settings.expandCrossReferences) {
        _expandedCrossRefVerses.addAll(
          nextRefs.keys
              .where((v) => (nextRefs[v]?.length ?? 0) <= 2),
        );
      }
      
      _verses = _verses.map((v) {
        if (v.isChapterHeader) return v;
        return BibleVerse(
          number: v.number,
          text: v.text,
          versionLabel: v.versionLabel,
          isSecondary: v.isSecondary,
          crossReferenceCount: _chapterCrossRefs[v.number]?.length ?? 0,
        );
      }).toList();
    });
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
      _isLoading = true;
    });

    await _fetchData();
  }

  void _showBookChapterSelector() {
    showAdaptiveBottomSheet(
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
    final indeterminate = _downloadManager.isIndeterminate(
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: indeterminate ? null : progress,
                    minHeight: 4,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Downloading the Tamil Bible (${BibleDownloadManager.defaultVersionId})…',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                indeterminate
                    ? 'Downloading…'
                    : '${(progress * 100).toStringAsFixed(0)}%',
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
    showAdaptiveBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return ReadingSettingsSheet(
            settings: _settings,
            onSettingsChanged: (newSettings) {
              // Re-apply auto-expansion when the toggle flips: turning it on
              // expands every verse that has up to two refs (larger sets stay
              // as badges that open the dedicated references page); turning it
              // off collapses all.
              if (newSettings.expandCrossReferences !=
                  _settings.expandCrossReferences) {
                setState(() {
                  if (newSettings.expandCrossReferences) {
                    _expandedCrossRefVerses.addAll(
                      _chapterCrossRefs.keys
                          .where((v) => (_chapterCrossRefs[v]?.length ?? 0) <= 2),
                    );
                  } else {
                    _expandedCrossRefVerses.clear();
                  }
                });
              }
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
    showAdaptiveBottomSheet(
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

  /// Handles tapping a cross-reference card: scrolls to the target verse when
  /// it lives in the same chapter, otherwise jumps to that book/chapter first.
  Future<void> _onReferenceTap(CrossReference ref) async {
    final targetBook = ref.bookNumber >= 1 &&
            ref.bookNumber <= BookNameService.englishBookNames.length
        ? BookNameService.englishBookNames[ref.bookNumber - 1]
        : _currentBook;
    final sameChapter = ref.bookNumber == _bookNumber(_currentBook) &&
        ref.chapter == _currentChapter;

    if (sameChapter) {
      // Clear any existing expansion selection, then scroll/highlight.
      if (mounted) {
        _scrollToVerse(ref.verse);
      }
      return;
    }

    // Cross-chapter jump: select the book/chapter, reload, then focus the verse.
    _currentBook = targetBook;
    _currentChapter = ref.chapter;
    if (mounted) setState(() {});
    await _loadChapter();
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToVerse(ref.verse);
      });
    }
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

  Widget _buildVerseItem(BibleVerse verse) {
    // Register a GlobalKey per real verse (not headers) for
    // Scrollable.ensureVisible in _scrollToVerse.
    final Key? itemKey = verse.isChapterHeader
        ? null
        : (_verseKeys[verse.number] ??= GlobalKey());

    final verseCrossRefs = _chapterCrossRefs[verse.number] ?? const [];
    final verseBackgrounds = _chapterBackgrounds[verse.number] ?? const [];

    return VerseItem(
      key: itemKey,
      verse: verse,
      isSelected: _selectedVerses.contains(verse.number),
      isHighlighted: _highlightedVerse == verse.number,
      fontSize: _settings.fontSize,
      onVerseTap: () => _toggleVerseSelection(verse.number),
      crossReferences: verseCrossRefs,
      backgroundNotes: verseBackgrounds,
      resolvedTexts: _crossRefTexts,
      selectedCount: _selectedVerses.length,
      onCopy: _copySelectedVerses,
      onShare: _shareSelectedVerses,
      onBookmark: _bookmarkSelectedVerses,
      onClear: () => setState(() => _selectedVerses.clear()),
      onOpenStudyPage: (initialTab) =>
          _openVerseStudyScreen(verse.number, initialTab: initialTab),
    );
  }

  Future<void> _openVerseStudyScreen(int verseNumber, {int initialTab = 0}) async {
    final verse = _verses.firstWhere(
      (v) => v.number == verseNumber,
      orElse: () => _verses.isNotEmpty
          ? _verses.first
          : BibleVerse(
              number: verseNumber,
              text: '',
            ),
    );
    final verseLabel =
        '${_displayBookName(_currentBook)} $_currentChapter:$verseNumber';

    final refs = _chapterCrossRefs[verseNumber] ?? const [];
    var notes = _chapterBackgrounds[verseNumber] ?? const [];
    if (notes.isEmpty && _chapterBackgrounds[0] != null) {
      notes = _chapterBackgrounds[0]!;
    }

    final bookNum = _bookNumber(_currentBook);
    final bookCommentariesFuture = BookService.instance.getCommentariesForVerse(
      bookNum,
      _currentChapter,
      verseNumber,
    );

    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VerseStudyScreen(
          verseText: verse.text,
          verseLabel: verseLabel,
          versionLabel: _selectedVersion?.name,
          references: refs,
          resolvedTexts: _crossRefTexts,
          commentaryNotes: notes,
          bookCommentariesFuture: bookCommentariesFuture,
          baseFontSize: _settings.fontSize,
          initialTab: initialTab,
          onTapReference: _onReferenceTap,
        ),
      ),
    );
  }

  Future<void> _loadBackgroundsForChapter(int bookNumber, int chapter) async {
    try {
      var map = await _backgroundService.getBackgroundsForChapter(
        bookNumber,
        chapter,
      );
      if (map.isEmpty) {
        map = await _backgroundService.fetchChapterOnline(bookNumber, chapter);
      }
      if (mounted) {
        setState(() => _chapterBackgrounds = map);
      }
    } catch (_) {}
  }

  Widget _buildContent() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_versions.isEmpty) return _buildEmptyState();
    if (_chapterEmpty) return _buildChapterEmptyState();
    return MaxWidthBox(
      child: ListView(
        // No ValueKey here — using one caused the list to be destroyed and
        // recreated (resetting scroll to 0) whenever _currentBook/_currentChapter
        // changed, including during the infinite-scroll append path.
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 16),
        // Each chapter is intentionally a small, eagerly-built list. This
        // keeps every verse key mounted, so a Words-feed deep link can use
        // Scrollable.ensureVisible even when its verse starts off-screen.
        children: [
          ..._verses.map(_buildVerseItem),
          if (_isFetchingNextChapter)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
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
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  '${_displayBookName(_currentBook)} $_currentChapter',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 2),
                child: Icon(Icons.arrow_drop_down, size: 20),
              ),
            ],
          ),
        ),
        actions: [
          if (_selectedVersion != null)
            PopupMenuButton<String>(
              tooltip: 'Version',
              offset: const Offset(0, 40),
              onSelected: (value) {
                if (value == '__manage__') {
                  _pushManager();
                } else {
                  final version = _versions.firstWhere(
                    (v) => v.shortname == value,
                    orElse: () {
                      final meta = BibleDownloadManager.getMeta(value);
                      return BibleVersion(
                        id: value,
                        name: meta.name,
                        shortname: value,
                        description: meta.description,
                        lang: meta.languageCode,
                      );
                    },
                  );
                  setState(() => _selectedVersion = version);
                  _fetchData();
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  enabled: false,
                  child: Text(
                    _selectedVersion!.shortname,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 13,
                    ),
                  ),
                ),
                const PopupMenuDivider(height: 1),
                ..._versions.map((v) => PopupMenuItem(
                      value: v.shortname,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              v.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (v.shortname == _selectedVersion!.shortname)
                            Icon(Icons.check,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary),
                        ],
                      ),
                    )),
                if (!kIsWeb) ...[
                  const PopupMenuDivider(height: 1),
                  const PopupMenuItem(
                    value: '__manage__',
                    child: Text('Manage translations…'),
                  ),
                ],
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _selectedVersion!.shortname,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(left: 2),
                      child: Icon(Icons.arrow_drop_down, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          IconButton(
            tooltip: 'Books Library',
            icon: const Icon(Icons.auto_stories_rounded),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const BooksCatalogScreen(),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Search Bible',
            icon: const Icon(Icons.search),
            onPressed: _showSearch,
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) {
              switch (value) {
                case 'books':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const BooksCatalogScreen(),
                    ),
                  );
                case 'downloads':
                  _pushManager();
                case 'bookmarks':
                  _openBookmarks();
                case 'settings':
                  _showReadingSettings();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'downloads',
                child: Row(
                  children: [
                    Icon(Icons.download_for_offline_rounded, size: 18),
                    SizedBox(width: 10),
                    Text('Offline Library & Downloads'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'books',
                child: Row(
                  children: [
                    Icon(Icons.library_books_rounded, size: 18),
                    SizedBox(width: 10),
                    Text('Books Library'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'bookmarks',
                child: Text('Bookmarks'),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Text('Reading settings'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _buildContent(),
          ),
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
