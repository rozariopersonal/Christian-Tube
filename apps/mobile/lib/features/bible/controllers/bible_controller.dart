import 'package:flutter/foundation.dart';

import '../../engines/scripture/services/bible_download_manager.dart';
import '../../engines/scripture/services/book_name_service.dart';
import '../../engines/scripture/services/local_bible_service.dart';
import '../models/bible_book.dart';
import '../models/bible_settings.dart';
import '../models/bible_verse.dart';
import '../models/bible_verse_counts.dart';
import '../models/bible_version.dart';
import '../models/bible_background_note.dart';
import '../models/cross_reference.dart';
import '../services/bible_bookmark_service.dart';
import '../services/bible_background_service.dart';
import '../services/bible_chapter_stream.dart';
import '../services/bible_settings_service.dart';
import '../services/bible_verse_counts_service.dart';
import '../services/bible_verse_index.dart';
import '../services/cross_reference_service.dart';
import '../../../shared/services/reader_appearance.dart';

/// Immutable snapshot of every field the Bible reader UI needs.
///
/// The controller replaces the entire object on every state change and calls
/// [notifyListeners].  Widgets must therefore read only from [BibleControllerState]
/// and never from the controller's private fields.
@immutable
class BibleControllerState {
  const BibleControllerState({
    this.versions = const [],
    this.selectedVersion,
    this.currentBook = 'Genesis',
    this.currentChapter = 1,
    this.isLoading = true,
    this.chapterEmpty = false,
    this.selectedVerses = const {},
    this.settings = const BibleSettings(),
    this.settingsLoaded = false,
    this.highlightedVerse,
    this.chapterCrossRefs = const {},
    this.crossRefTexts = const {},
    this.crossRefsInstalled = false,
    this.crossRefsLoading = false,
    this.chapterBackgrounds = const {},
    this.counts = const BibleVerseCounts([]),
    this.loadedChapters = const {},
    this.index,
  });

  final List<BibleVersion> versions;
  final BibleVersion? selectedVersion;
  final String currentBook;
  final int currentChapter;
  final bool isLoading;
  final bool chapterEmpty;
  final Set<int> selectedVerses;
  final BibleSettings settings;
  final bool settingsLoaded;
  final int? highlightedVerse;
  final Map<int, List<CrossReference>> chapterCrossRefs;
  final Map<String, String> crossRefTexts;
  final bool crossRefsInstalled;
  final bool crossRefsLoading;
  final Map<int, List<BibleBackgroundNote>> chapterBackgrounds;

  /// Per-chapter verse-row counts for the active version. Empty counts mean the
  /// reader degrades to a single-chapter list ([totalRows] from [verses]).
  final BibleVerseCounts counts;

  /// Chapters streamed into memory so far, keyed by [bibleChapterId].
  final Map<int, List<BibleVerse>> loadedChapters;

  /// Whole-Bible row index derived from [counts]; null when counts are absent.
  final BibleVerseIndex? index;

  // ── Derived helpers ────────────────────────────────────────────────────

  int bookNumber(String book) =>
      BookNameService.englishBookNames.indexOf(book) + 1;

  /// Rows of the currently visible chapter (reads from the stream buffer).
  List<BibleVerse> get verses =>
      loadedChapters[bibleChapterId(bookNumber(currentBook), currentChapter)] ??
      const [];

  /// Number of items the reader list should build: the whole canon when counts
  /// are available, otherwise just the current chapter's rows.
  int get totalRows => index?.totalVerses ?? verses.length;

  bool get canFetchPrev {
    if (isLoading || selectedVersion == null) return false;
    if (currentChapter > 1) return true;
    final books = bibleBooks.keys.toList();
    final currentIndex = books.indexOf(currentBook);
    return currentIndex > 0;
  }

  bool get canFetchNext {
    if (isLoading || selectedVersion == null) return false;
    final maxChapters = bibleBooks[currentBook] ?? 1;
    if (currentChapter < maxChapters) return true;
    final books = bibleBooks.keys.toList();
    final currentIndex = books.indexOf(currentBook);
    return currentIndex < books.length - 1;
  }

  String selectedText({String prefix = ''}) {
    if (selectedVerses.isEmpty) return '';
    return verses
        .where((v) => selectedVerses.contains(v.number))
        .map((v) => '$prefix[${v.number}] ${v.text}')
        .join('\n');
  }
}

/// Convenience extension to reduce per-call boilerplate when constructing
/// a new [BibleControllerState] that only changes one or two fields.
extension _StateCopy on BibleControllerState {
  BibleControllerState copyWith({
    List<BibleVersion>? versions,
    BibleVersion? selectedVersion,
    String? currentBook,
    int? currentChapter,
    bool? isLoading,
    bool? chapterEmpty,
    Set<int>? selectedVerses,
    BibleSettings? settings,
    bool? settingsLoaded,
    int? highlightedVerse,
    bool clearHighlighted = false,
    Map<int, List<CrossReference>>? chapterCrossRefs,
    Map<String, String>? crossRefTexts,
    bool? crossRefsInstalled,
    bool? crossRefsLoading,
    Map<int, List<BibleBackgroundNote>>? chapterBackgrounds,
    BibleVerseCounts? counts,
    Map<int, List<BibleVerse>>? loadedChapters,
    BibleVerseIndex? index,
  }) =>
      BibleControllerState(
        versions: versions ?? this.versions,
        selectedVersion: selectedVersion ?? this.selectedVersion,
        currentBook: currentBook ?? this.currentBook,
        currentChapter: currentChapter ?? this.currentChapter,
        isLoading: isLoading ?? this.isLoading,
        chapterEmpty: chapterEmpty ?? this.chapterEmpty,
        selectedVerses: selectedVerses ?? this.selectedVerses,
        settings: settings ?? this.settings,
        settingsLoaded: settingsLoaded ?? this.settingsLoaded,
        highlightedVerse: clearHighlighted ? null : (highlightedVerse ?? this.highlightedVerse),
        chapterCrossRefs: chapterCrossRefs ?? this.chapterCrossRefs,
        crossRefTexts: crossRefTexts ?? this.crossRefTexts,
        crossRefsInstalled: crossRefsInstalled ?? this.crossRefsInstalled,
        crossRefsLoading: crossRefsLoading ?? this.crossRefsLoading,
        chapterBackgrounds: chapterBackgrounds ?? this.chapterBackgrounds,
        counts: counts ?? this.counts,
        loadedChapters: loadedChapters ?? this.loadedChapters,
        index: index ?? this.index,
      );
}

/// The verse a caller wants the reader to land on once its chapter is loaded.
///
/// Holding book+chapter (not just a verse number) lets the screen wait until
/// the matching chapter has actually been loaded before scrolling, instead of
/// racing the async chapter fetch with a fixed retry count.
class BibleScrollTarget {
  final String book;
  final int chapter;
  final int verse;
  final bool highlight;

  const BibleScrollTarget({
    required this.book,
    required this.chapter,
    required this.verse,
    this.highlight = true,
  });
}

/// Encapsulates every business-logic operation for the Bible reader.
///
/// The screen is responsible for:
///   * scroll-to-verse (needs GlobalKeys / ScrollController)
///   * highlight timer (pure UI)
///   * navigation / route pushing (needs BuildContext)
///
/// Everything else — data loading, selection toggling, bookmark toggling,
/// chapter navigation — lives here.
class BibleController extends ChangeNotifier {
  BibleController({
    required this.initialVersionId,
    required this.initialBook,
    required this.initialChapter,
    required this.initialVerse,
    required this.saveProgress,
  })  : _scrollTarget = (initialVerse != null && initialBook != null)
            ? BibleScrollTarget(
                book: initialBook,
                chapter: (initialChapter != null && initialChapter >= 1)
                    ? initialChapter
                    : 1,
                verse: initialVerse,
                highlight: true,
              )
            : null,
        _currentBook = (initialBook != null && bibleBooks.containsKey(initialBook))
            ? initialBook
            : 'Genesis',
        _currentChapter =
            (initialChapter != null && initialChapter >= 1) ? initialChapter : 1;

  // ── Constructor-supplied launch parameters ─────────────────────────────

  final String? initialVersionId;
  final String? initialBook;
  final int? initialChapter;
  final int? initialVerse;
  final bool saveProgress;

  // ── Services ───────────────────────────────────────────────────────────

  final LocalBibleService _localBibleService = LocalBibleService();
  final BibleSettingsService _settingsService = BibleSettingsService();
  final BibleBookmarkService _bookmarkService = BibleBookmarkService();
  final BibleDownloadManager _downloadManager = BibleDownloadManager();
  final BookNameService _bookNames = BookNameService();
  final CrossReferenceService _crossRefService = CrossReferenceService();
  final BibleBackgroundService _backgroundService = BibleBackgroundService();
  final BibleVerseCountsService _countsService = BibleVerseCountsService();

  final ReaderAppearance appearance = ReaderAppearance();

  // ── Private mutable state (not exposed directly) ───────────────────────

  int _lastKnownInstalledCount = -1;
  bool _resumeApplied = false;
  bool _initialJumpPending = true;
  BibleScrollTarget? _scrollTarget;
  int _crossRefBookNumber = 0;
  int _crossRefChapter = 0;
  int _loadEpoch = 0;
  bool _downloadManagerBusy = false;
  bool _disposed = false;

  String _currentBook;
  int _currentChapter;

  BibleChapterStream? _stream;

  // ── Public state ───────────────────────────────────────────────────────

  BibleControllerState _state = const BibleControllerState();
  BibleControllerState get state => _state;

  /// Versions list (needed by the screen for version picker).
  List<BibleVersion> get versions => _state.versions;

  /// Selected version (needed by the screen for version picker / display).
  BibleVersion? get selectedVersion => _state.selectedVersion;

  /// Current book (needed for display in the screen's title).
  String get currentBook => _currentBook;

  /// Current chapter (needed for display in the screen's title).
  int get currentChapter => _currentChapter;

  /// Current verse — either the last highlighted verse or the first verse.
  int get currentVerse => _state.highlightedVerse ?? 1;

  /// Returns and clears the pending scroll target once its target chapter is
  /// buffered by the stream. Returns null while the chapter is still loading;
  /// callers should re-check after the next notify.
  ///
  /// Called by the screen when `state.isLoading == false`.
  BibleScrollTarget? consumeScrollTargetIfReady() {
    final target = _scrollTarget;
    if (target == null) return null;
    final bn = bookNumber(target.book);
    final stream = _stream;
    if (!BookNameService.englishBookNames.contains(target.book) ||
        stream == null ||
        !stream.contains(bn, target.chapter)) {
      return null;
    }
    _scrollTarget = null;
    return target;
  }

  // ── Book name helpers ──────────────────────────────────────────────────

  int bookNumber(String book) =>
      BookNameService.englishBookNames.indexOf(book) + 1;

  String displayBookName(String book) =>
      _bookNames.nameFor(_state.selectedVersion?.shortname ?? 'TAOBVSI', bookNumber(book));

  // ── Lifecycle ──────────────────────────────────────────────────────────

  Future<void> init() async {
    _downloadManager.addListener(_onDownloadManagerChanged);
    await _bookNames.ensureLoaded();
    await appearance.loadFromPrefs();
    appearance.addListener(notifyListeners);
    _loadSettings();
    await _fetchData();
    _checkCrossRefsInstalled();
  }

  @override
  void dispose() {
    _disposed = true;
    _downloadManager.removeListener(_onDownloadManagerChanged);
    appearance.removeListener(notifyListeners);
    super.dispose();
  }

  // ── Private helpers ────────────────────────────────────────────────────

  void _update(BibleControllerState Function(BibleControllerState) transform) {
    if (_disposed) return;
    _state = transform(_state);
    notifyListeners();
  }

  Future<void> _checkCrossRefsInstalled() async {
    try {
      final installed = await _crossRefService.isInstalled();
      _update((s) => s.copyWith(crossRefsInstalled: installed));
    } catch (e) {
      debugPrint('BibleController _checkCrossRefsInstalled error: $e');
    }
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _settingsService.loadSettings();
      _update((s) => s.copyWith(settings: settings, settingsLoaded: true));
      final applied = _applySavedProgress();
      if (applied && _state.selectedVersion != null) {
        await _loadChapter();
      }
    } catch (e, stack) {
      debugPrint('BibleController _loadSettings error: $e\n$stack');
      _update((s) => s.copyWith(settingsLoaded: true));
    }
  }

  bool _applySavedProgress() {
    if (_resumeApplied) return false;
    if (initialBook != null || initialVersionId != null) {
      _resumeApplied = true;
      return false;
    }
    if (!_state.settingsLoaded) return false;
    if (!_state.settings.hasProgress) {
      _resumeApplied = true;
      return false;
    }
    final savedBook = _state.settings.lastBook;
    final savedChapter = _state.settings.lastChapter;
    final savedVersion = _state.settings.lastVersion;
    if (savedBook == null) return false;
    BibleVersion? newVersion = _state.selectedVersion;
    if (_state.versions.any((v) => v.shortname == savedVersion)) {
      newVersion = _state.versions.firstWhere((v) => v.shortname == savedVersion);
    }
    _currentBook = savedBook;
    _currentChapter = savedChapter;
    _update((s) => s.copyWith(
          selectedVersion: newVersion,
          currentBook: _currentBook,
          currentChapter: _currentChapter,
        ));
    return true;
  }

  void _applyInitialJump() {
    if (!_initialJumpPending || _state.versions.isEmpty) return;
    _initialJumpPending = false;
    BibleVersion? newVersion = _state.selectedVersion;
    if (initialVersionId != null &&
        _state.versions.any((v) => v.shortname == initialVersionId)) {
      newVersion = _state.versions.firstWhere((v) => v.shortname == initialVersionId);
    }
    if (initialBook != null && bibleBooks.containsKey(initialBook)) {
      _currentBook = initialBook!;
    }
    if (initialChapter != null && initialChapter! >= 1) {
      _currentChapter = initialChapter!;
    }
    _update((s) => s.copyWith(
          selectedVersion: newVersion,
          currentBook: _currentBook,
          currentChapter: _currentChapter,
        ));
  }

  Future<void> _onDownloadManagerChanged() async {
    final count = _downloadManager.installedIds.length;
    if (count == _lastKnownInstalledCount) return;
    _lastKnownInstalledCount = count;
    if (_downloadManagerBusy) return;
    _downloadManagerBusy = true;

    try {
      final hadVersions = _state.versions.isNotEmpty;
      await _loadVersions();
      if (_disposed) return;
      if (_state.selectedVersion != null) {
        if (!hadVersions) _update((s) => s.copyWith(isLoading: true));
        await _loadChapter();
        if (!_disposed) _update((s) => s.copyWith(isLoading: false));
      } else {
        _update((s) => s.copyWith(isLoading: false));
      }
    } finally {
      _downloadManagerBusy = false;
    }
  }

  Future<void> _fetchData() async {
    _update((s) => s.copyWith(isLoading: true));
    try {
      await _localBibleService.initialize();
      await _loadVersions();
      if (_state.selectedVersion != null) {
        await _loadChapter();
      }
    } catch (e, stack) {
      debugPrint('BibleController _fetchData error: $e\n$stack');
    } finally {
      _update((s) => s.copyWith(isLoading: false));
    }
  }

  Future<void> _loadVersions() async {
    final installed = await _localBibleService.getInstalledVersions();
    final versions = installed.map((m) {
      final id = m['id'] as String;
      return BibleVersion(
        id: id,
        name: m['name'] as String? ?? id,
        shortname: id,
        description: m['language'] as String? ?? '',
        lang: m['language_code'] as String? ?? '',
      );
    }).toList();

    BibleVersion? selectedVersion = _state.selectedVersion;
    if (versions.isNotEmpty && selectedVersion == null) {
      selectedVersion = versions.firstWhere(
        (v) => v.shortname == BibleDownloadManager.defaultVersionId,
        orElse: () => versions.first,
      );
    } else if (selectedVersion != null &&
        !versions.any((v) => v.shortname == selectedVersion!.shortname)) {
      selectedVersion = versions.isNotEmpty ? versions.first : null;
    }

    _update((s) => s.copyWith(versions: versions, selectedVersion: selectedVersion));
    _applyInitialJump();
    _applySavedProgress();
  }

  Future<void> _loadCrossReferencesForChapter(int bookNumber, int chapter) async {
    if (_state.selectedVersion == null) return;
    final isNewChapter =
        bookNumber != _crossRefBookNumber || chapter != _crossRefChapter;
    if (_state.crossRefsLoading && isNewChapter) return;

    final epoch = _loadEpoch;
    _update((s) => s.copyWith(crossRefsLoading: true));
    Map<int, List<CrossReference>> chapterRefs;
    try {
      chapterRefs = await _crossRefService.getForChapter(
        bookNumber,
        chapter,
        allowOnline: !_state.crossRefsInstalled,
      );
    } catch (_) {
      chapterRefs = {};
    }
    if (epoch != _loadEpoch) return; // stale

    final passages = <(int, int, int, int?)>[];
    final seen = <String>{};
    for (final refs in chapterRefs.values) {
      for (final ref in refs) {
        if (seen.add(ref.textKey)) {
          passages.add((ref.bookNumber, ref.chapter, ref.verse, ref.endVerse));
        }
      }
    }
    Map<String, String> resolved = {};
    if (passages.isNotEmpty) {
      try {
        resolved = await _localBibleService.resolvePassages(
          versionId: _state.selectedVersion!.shortname,
          passages: passages,
        );
      } catch (_) {
        resolved = {};
      }
    }
    if (epoch != _loadEpoch) return; // stale

    _crossRefBookNumber = bookNumber;
    _crossRefChapter = chapter;
    _update((s) => s.copyWith(
          chapterCrossRefs: chapterRefs,
          crossRefTexts: resolved,
          crossRefsLoading: false,
        ));
  }

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

  /// (Re)builds the chapter stream and whole-Bible index for the active
  /// version, then buffers the chapter currently selected. Called on startup,
  /// version switch, and after installer changes.
  Future<void> _loadChapter() async {
    if (_state.selectedVersion == null) return;
    final epoch = ++_loadEpoch;
    final version = _state.selectedVersion!;
    _stream = BibleChapterStream(version.shortname);
    final counts = await _countsService.loadForVersion(version.shortname);
    if (epoch != _loadEpoch || _disposed) return;
    final index = counts.isLoaded ? BibleVerseIndex(counts) : null;
    _update((s) => s.copyWith(
          counts: counts,
          index: index,
          loadedChapters: const {},
          chapterEmpty: false,
        ));
    if (epoch != _loadEpoch || _disposed) return;
    await _ensureChapterLoaded(_currentBook, _currentChapter, epoch: epoch);
  }

  /// Buffers [book]/[chapter] into the stream and applies the resulting state.
  /// Marks the reader not-loading and detects empty chapters.
  Future<void> _ensureChapterLoaded(
    String book,
    int chapter, {
    required int epoch,
  }) async {
    final stream = _stream;
    final version = _state.selectedVersion;
    if (version == null || stream == null) return;
    if (!bibleBooks.containsKey(book)) return;
    final bn = bookNumber(book);
    final rows = await stream.ensureChapter(bn, chapter);
    if (epoch != _loadEpoch || _disposed) return;
    _fillChapterRows(rows, bn, chapter);
    _update((s) => s.copyWith(
          isLoading: false,
          chapterEmpty: s.index == null
              ? rows.isEmpty
              : s.index!.chapterRowCount(
                  bookNumber: bn,
                  chapter: chapter,
                ) == 0,
          clearHighlighted: true,
        ));
    stream.preloadAround(bn, chapter);
    _loadCrossReferencesForChapter(bn, chapter);
    _loadBackgroundsForChapter(bn, chapter);
    if (rows.isNotEmpty && saveProgress) {
      _settingsService.saveReadingProgress(version.shortname, book, chapter);
    }
  }

  /// Adds [rows] for `(bookNumber, chapter)` to the buffer without touching
  /// loading/empty state — used for background stream fills while scrolling.
  void _fillChapterRows(List<BibleVerse> rows, int bookNumber, int chapter) {
    final id = bibleChapterId(bookNumber, chapter);
    _update((s) {
      final loaded = Map<int, List<BibleVerse>>.from(s.loadedChapters);
      loaded[id] = rows;
      return s.copyWith(loadedChapters: loaded);
    });
  }

  /// Live tracking of the chapter the user is currently scrolled into. Updates
  /// the current book/chapter (title, nav bounds, saved progress), fills the
  /// visible chapter if needed, and warms the surrounding chapters.
  ///
  /// Called by the screen from the scroll item-positions listener.
  void updateVisibleChapter(int bookNumber, int chapter) {
    final stream = _stream;
    final version = _state.selectedVersion;
    if (version == null || stream == null) return;
    if (bookNumber < 1 ||
        bookNumber > BookNameService.englishBookNames.length) {
      return;
    }
    final book = BookNameService.englishBookNames[bookNumber - 1];
    if (book == _currentBook && chapter == _currentChapter) return;
    _currentBook = book;
    _currentChapter = chapter;
    _update((s) => s.copyWith(currentBook: book, currentChapter: chapter));
    final epoch = ++_loadEpoch;
    _fillChapterInBackground(bookNumber, chapter, epoch: epoch);
    stream.preloadAround(bookNumber, chapter);
    _loadCrossReferencesForChapter(bookNumber, chapter);
    _loadBackgroundsForChapter(bookNumber, chapter);
    if (saveProgress) {
      _settingsService.saveReadingProgress(version.shortname, book, chapter);
    }
  }

  Future<void> _fillChapterInBackground(int bookNumber, int chapter,
      {required int epoch}) async {
    final stream = _stream;
    if (stream == null) return;
    final rows = await stream.ensureChapter(bookNumber, chapter);
    if (epoch != _loadEpoch || _disposed) return;
    _fillChapterRows(rows, bookNumber, chapter);
  }

  Future<void> _loadBackgroundsForChapter(int bookNumber, int chapter) async {
    final epoch = _loadEpoch;
    try {
      var map = await _backgroundService.getBackgroundsForChapter(bookNumber, chapter);
      if (map.isEmpty) {
        map = await _backgroundService.fetchChapterOnline(bookNumber, chapter);
      }
      if (epoch != _loadEpoch) return; // stale
      _update((s) => s.copyWith(chapterBackgrounds: map));
    } catch (e) {
      debugPrint('BibleController _loadBackgroundsForChapter error: $e');
    }
  }

  // ── Public methods ─────────────────────────────────────────────────────

  Future<void> fetchData() => _fetchData();

  Future<void> selectVersion(BibleVersion version) async {
    if (_state.selectedVersion?.shortname == version.shortname &&
        _stream != null) {
      _update((s) => s.copyWith(selectedVersion: version));
      return;
    }
    _update((s) => s.copyWith(selectedVersion: version));
    await _loadChapter();
  }

  Future<void> fetchNextChapter() async {
    if (!_state.canFetchNext) return;

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
        return;
      }
    }

    await _navigateTo(nextBook, nextChapter, verse: null);
  }

  Future<void> fetchPrevChapter() async {
    if (!_state.canFetchPrev) return;

    String prevBook = _currentBook;
    int prevChapter = _currentChapter - 1;

    if (prevChapter < 1) {
      final books = bibleBooks.keys.toList();
      final currentIndex = books.indexOf(_currentBook);
      if (currentIndex > 0) {
        prevBook = books[currentIndex - 1];
        prevChapter = bibleBooks[prevBook] ?? 1;
      } else {
        return;
      }
    }

    await _navigateTo(prevBook, prevChapter, verse: null);
  }

  Future<void> goToBookAndChapter(String book, int chapter, {int? verse}) =>
      _navigateTo(book, chapter, verse: verse);

  /// Moves the reader to a chapter. A scroll target is armed so the screen
  /// lands on [verse] (falling back to verse 1 when navigating to a different
  /// chapter without an explicit verse). Navigating within an already-buffered
  /// chapter only refreshes the current selection.
  Future<void> _navigateTo(String book, int chapter, {int? verse}) async {
    if (!bibleBooks.containsKey(book)) return;
    final sameChapter = book == _currentBook && chapter == _currentChapter;
    final armVerse = verse ?? (sameChapter ? null : 1);
    final shouldHighlight = verse != null;
    _scrollTarget = armVerse == null
        ? null
        : BibleScrollTarget(
            book: book,
            chapter: chapter,
            verse: armVerse,
            highlight: shouldHighlight,
          );

    if (sameChapter && !_state.isLoading && _stream != null && _stream!.contains(bookNumber(book), chapter)) {
      _update((s) => s.copyWith(currentBook: book, currentChapter: chapter));
      return;
    }

    _currentBook = book;
    _currentChapter = chapter;
    _update((s) => s.copyWith(isLoading: true, currentBook: book, currentChapter: chapter));
    final epoch = ++_loadEpoch;
    await _ensureChapterLoaded(book, chapter, epoch: epoch);
    if (epoch != _loadEpoch || _disposed) return;
    _update((s) => s.copyWith(isLoading: false));
  }

  /// Fetches the verse list for a chapter without changing the current reader
  /// selection. Used by the book/chapter/verse selector to display verse
  /// numbers while the sheet is still open.
  Future<List<BibleVerse>> previewChapterVerses(String book, int chapter) async {
    final version = _state.selectedVersion;
    if (version == null) return const [];
    final chapterMap = await _fetchVersesForChapter(version, book, chapter);
    return chapterVersesFromRows(chapterMap, version.shortname);
  }

  void toggleVerseSelection(int verseNumber) {
    if (verseNumber == 0) return;
    final newSelected = Set<int>.from(_state.selectedVerses);
    if (newSelected.contains(verseNumber)) {
      newSelected.remove(verseNumber);
    } else {
      newSelected.add(verseNumber);
    }
    _update((s) => s.copyWith(selectedVerses: newSelected));
  }

  void clearSelection() {
    _update((s) => s.copyWith(selectedVerses: {}));
  }

  void updateSettings(BibleSettings newSettings) {
    _update((s) => s.copyWith(settings: newSettings));
    _settingsService.saveSettings(newSettings);
  }

  void setHighlight(int? verseNumber) {
    _update((s) => verseNumber == null
        ? s.copyWith(clearHighlighted: true)
        : s.copyWith(highlightedVerse: verseNumber));
  }

  Future<void> toggleBookmarkSelected() async {
    if (_state.selectedVerses.isEmpty || _state.selectedVersion == null) return;
    final selected = _state.verses
        .where((v) => _state.selectedVerses.contains(v.number))
        .toList();
    if (selected.isEmpty) return;

    try {
      var added = 0;
      var removed = 0;
      for (final v in selected) {
        final isNowBookmarked = await _bookmarkService.toggle(
          versionId: _state.selectedVersion!.shortname,
          book: _currentBook,
          chapter: _currentChapter,
          verse: v.number,
          text: v.text,
        );
        if (isNowBookmarked) added++;
        if (!isNowBookmarked) removed++;
      }
      clearSelection();
      _lastBookmarkMessage = added > removed
          ? '$added verse${added == 1 ? '' : 's'} bookmarked'
          : removed > added
              ? '$removed verse${removed == 1 ? '' : 's'} removed from bookmarks'
              : 'Bookmarks updated';
    } catch (e) {
      debugPrint('BibleController toggleBookmarkSelected error: $e');
      _lastBookmarkMessage = 'Failed to update bookmarks';
    }
  }

  /// After [toggleBookmarkSelected], read the message and clear it.
  String? consumeBookmarkMessage() {
    final m = _lastBookmarkMessage;
    _lastBookmarkMessage = null;
    return m;
  }

  String? _lastBookmarkMessage;

  Future<void> redownloadDefault() async {
    _update((s) => s.copyWith(isLoading: true, chapterEmpty: false));
    await BibleDownloadManager().forceRedownloadDefault();
  }
}
