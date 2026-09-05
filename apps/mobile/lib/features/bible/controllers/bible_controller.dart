import 'package:flutter/foundation.dart';

import '../../engines/scripture/services/bible_download_manager.dart';
import '../../engines/scripture/services/book_name_service.dart';
import '../../engines/scripture/services/local_bible_service.dart';
import '../models/bible_book.dart';
import '../models/bible_settings.dart';
import '../models/bible_verse.dart';
import '../models/bible_version.dart';
import '../models/bible_background_note.dart';
import '../models/cross_reference.dart';
import '../services/bible_bookmark_service.dart';
import '../services/bible_background_service.dart';
import '../services/bible_settings_service.dart';
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
    this.verses = const [],
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
  });

  final List<BibleVersion> versions;
  final List<BibleVerse> verses;
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

  // ── Derived helpers ────────────────────────────────────────────────────

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
    List<BibleVerse>? verses,
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
  }) =>
      BibleControllerState(
        versions: versions ?? this.versions,
        verses: verses ?? this.verses,
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
      );
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
  })  : _pendingScrollVerse = initialVerse,
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

  final ReaderAppearance appearance = ReaderAppearance();

  // ── Private mutable state (not exposed directly) ───────────────────────

  int _lastKnownInstalledCount = -1;
  bool _resumeApplied = false;
  bool _initialJumpPending = true;
  int? _pendingScrollVerse;
  int _crossRefBookNumber = 0;
  int _crossRefChapter = 0;
  int _loadEpoch = 0;
  bool _downloadManagerBusy = false;
  bool _disposed = false;

  String _currentBook;
  int _currentChapter;

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

  /// The verse number the scroll controller should target, or null.
  /// Consumed and cleared by the screen's scroll-to-verse logic.
  int? consumePendingScrollVerse() {
    final v = _pendingScrollVerse;
    _pendingScrollVerse = null;
    return v;
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
        crossReferenceCount: _state.chapterCrossRefs[n]?.length ?? 0,
      ));
    }
    return verses;
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
          verses: s.verses.map((v) {
            if (v.isChapterHeader) return v;
            return BibleVerse(
              number: v.number,
              text: v.text,
              versionLabel: s.selectedVersion?.shortname ?? v.versionLabel,
              isSecondary: v.isSecondary,
              crossReferenceCount: chapterRefs[v.number]?.length ?? 0,
            );
          }).toList(),
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

  Future<void> _loadChapter() async {
    if (_state.selectedVersion == null) return;
    final epoch = ++_loadEpoch;
    final book = _currentBook;
    final chapter = _currentChapter;
    final version = _state.selectedVersion!;
    final primaryMap = await _fetchVersesForChapter(version, book, chapter);
    if (epoch != _loadEpoch) return; // stale — a newer load superseded this one
    final verses = _buildChapterVerses(primaryMap, version.shortname);
    _update((s) => s.copyWith(
          verses: verses,
          chapterEmpty: verses.isEmpty,
          clearHighlighted: true,
        ));

    _loadCrossReferencesForChapter(bookNumber(book), chapter);
    _loadBackgroundsForChapter(bookNumber(book), chapter);

    if (verses.isNotEmpty && saveProgress) {
      _settingsService.saveReadingProgress(version.shortname, book, chapter);
    }
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

    _currentBook = nextBook;
    _currentChapter = nextChapter;
    _update((s) => s.copyWith(isLoading: true, currentBook: _currentBook, currentChapter: _currentChapter));
    await _loadChapter();
    _update((s) => s.copyWith(isLoading: false));
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

    _currentBook = prevBook;
    _currentChapter = prevChapter;
    _update((s) => s.copyWith(isLoading: true, currentBook: _currentBook, currentChapter: _currentChapter));
    await _loadChapter();
    _update((s) => s.copyWith(isLoading: false));
  }

  Future<void> goToBookAndChapter(String book, int chapter, {int? verse}) async {
    _currentBook = book;
    _currentChapter = chapter;
    if (verse != null) _pendingScrollVerse = verse;
    _update((s) => s.copyWith(isLoading: true, currentBook: book, currentChapter: chapter));
    await _loadChapter();
    _update((s) => s.copyWith(isLoading: false));
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
