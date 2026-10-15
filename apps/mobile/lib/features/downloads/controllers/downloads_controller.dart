import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../articles/services/articles_download_manager.dart';
import '../../audio/services/audio_download_service.dart';
import '../../audio/services/audio_local_library.dart';
import '../../bible/services/study/bible_study_updater.dart';
import '../../books/services/book_service.dart';
import '../../dictionary/services/dictionary_download_manager.dart';
import '../../engines/scripture/models/bible_version_meta.dart';
import '../../engines/scripture/services/bible_download_manager.dart';
import '../../songs/services/songs_download_manager.dart';
import '../../../shared/services/reader_fonts_service.dart';
import '../models/downloads_state.dart';
import '../services/storage_calculator_service.dart';

/// Central controller managing the state, operations, and disk accounting
/// across all offline download resources in Christian Tube.
class DownloadsController extends ChangeNotifier {
  final BibleDownloadManager _bibleManager;
  final DictionaryDownloadManager _dictManager;
  final BookService _bookService;
  final SongsDownloadManager _songsManager;
  final ArticlesDownloadManager _articlesManager;
  final AudioLocalLibrary _audioLibrary;
  final AudioDownloadService _audioDownloadService;
  final StorageCalculatorService _storageService;

  DownloadsState _state = const DownloadsState(isLoading: true);
  DownloadsState get state => _state;

  bool _isDisposed = false;

  DownloadsController({
    BibleDownloadManager? bibleManager,
    DictionaryDownloadManager? dictManager,
    BookService? bookService,
    SongsDownloadManager? songsManager,
    ArticlesDownloadManager? articlesManager,
    AudioLocalLibrary? audioLibrary,
    AudioDownloadService? audioDownloadService,
    StorageCalculatorService? storageService,
  })  : _bibleManager = bibleManager ?? BibleDownloadManager(),
        _dictManager = dictManager ?? DictionaryDownloadManager(),
        _bookService = bookService ?? BookService.instance,
        _songsManager = songsManager ?? SongsDownloadManager(),
        _articlesManager = articlesManager ?? ArticlesDownloadManager(),
        _audioLibrary = audioLibrary ?? AudioLocalLibrary(),
        _audioDownloadService =
            audioDownloadService ?? AudioDownloadService.instance,
        _storageService = storageService ?? StorageCalculatorService.instance {
    _init();
  }

  void _init() {
    _bibleManager.addListener(_onServiceNotification);
    _dictManager.addListener(_onServiceNotification);
    _bookService.addListener(_onServiceNotification);
    _songsManager.addListener(_onServiceNotification);
    _articlesManager.addListener(_onServiceNotification);
    _audioDownloadService.addListener(_onServiceNotification);
    ReaderFontsService.instance.addListener(_onServiceNotification);

    unawaited(refreshAll());
  }

  @override
  void dispose() {
    _isDisposed = true;
    _bibleManager.removeListener(_onServiceNotification);
    _dictManager.removeListener(_onServiceNotification);
    _bookService.removeListener(_onServiceNotification);
    _songsManager.removeListener(_onServiceNotification);
    _articlesManager.removeListener(_onServiceNotification);
    _audioDownloadService.removeListener(_onServiceNotification);
    ReaderFontsService.instance.removeListener(_onServiceNotification);
    super.dispose();
  }

  void _onServiceNotification() {
    if (_isDisposed) return;
    _syncServiceProgress();
    notifyListeners();
  }

  void _syncServiceProgress() {
    _state = _state.copyWith(
      booksBundleInstalled: _state.booksBundleInstalled,
      isBooksBundleDownloading: _bookService.isDownloading,
      booksBundleProgress: _bookService.downloadProgress,
      installedArticleLanguages: _articlesManager.installedLanguages,
      songsInstalled: _songsManager.isInstalled,
      isSongsDownloading: _songsManager.isDownloading,
      songsProgress: _songsManager.downloadProgress,
    );
  }

  /// Full refresh of installed states, disk accounting, and catalogs.
  Future<void> refreshAll() async {
    _state = _state.copyWith(isLoading: true);
    notifyListeners();

    _bibleManager.refreshInstalledList();
    await _dictManager.initialize();
    await _bookService.initialize();
    await _songsManager.initialize();
    await _articlesManager.initialize();

    final books = await _bookService.isInstalled();
    final studyDb = await BibleStudyUpdater.isDownloaded();
    final installedBookIds = await _bookService.getInstalledBookIds();
    final catalog = await _bookService.getCatalogFromAsset();

    final storage = await _storageService.calculateBreakdown(
      bibleManager: _bibleManager,
      dictManager: _dictManager,
      bookService: _bookService,
      songsManager: _songsManager,
      articlesManager: _articlesManager,
    );
    final audioSeries = await _storageService.scanDownloadedAudioSeries();

    if (_isDisposed) return;
    _state = _state.copyWith(
      isLoading: false,
      storage: storage,
      bibles: BibleDownloadManager.catalog,
      dictionaries: DictionaryDownloadManager.catalog,
      books: catalog,
      installedBookIds: installedBookIds,
      audioSeries: audioSeries,
      booksBundleInstalled: books,
      isBooksBundleDownloading: _bookService.isDownloading,
      booksBundleProgress: _bookService.downloadProgress,
      installedArticleLanguages: _articlesManager.installedLanguages,
      songsInstalled: _songsManager.isInstalled,
      isSongsDownloading: _songsManager.isDownloading,
      songsProgress: _songsManager.downloadProgress,
      studyDbInstalled: studyDb,
    );
    notifyListeners();
  }

  // --- Filtering & Search ---

  void setBibleSearch(String q) {
    _state = _state.copyWith(bibleSearch: q);
    notifyListeners();
  }

  void setBibleLanguageFilter(String lang) {
    _state = _state.copyWith(bibleLanguageFilter: lang);
    notifyListeners();
  }

  void setDictSearch(String q) {
    _state = _state.copyWith(dictSearch: q);
    notifyListeners();
  }

  void setDictFilter(String f) {
    _state = _state.copyWith(dictFilter: f);
    notifyListeners();
  }

  void setBookSearch(String q) {
    _state = _state.copyWith(bookSearch: q);
    notifyListeners();
  }

  void setBookLanguageFilter(String lang) {
    _state = _state.copyWith(bookLanguageFilter: lang);
    notifyListeners();
  }

  void toggleOnlyInstalled() {
    _state = _state.copyWith(onlyInstalled: !_state.onlyInstalled);
    notifyListeners();
  }

  // --- Bible Operations ---

  bool isBibleInstalled(String id) => _bibleManager.isInstalled(id);
  bool isBibleDownloading(String id) => _bibleManager.isDownloading(id);
  double getBibleProgress(String id) => _bibleManager.getProgress(id);
  bool isBibleIndeterminate(String id) => _bibleManager.isIndeterminate(id);

  Future<void> downloadBible(BibleVersionMeta bible) async {
    await _bibleManager.downloadVersion(bible);
    await refreshAll();
  }

  /// Removes an installed Bible. Returns false if attempting to delete the
  /// protected base translation.
  Future<bool> deleteBible(String id) async {
    if (id.toUpperCase() == BibleDownloadManager.defaultVersionId.toUpperCase()) {
      return false;
    }
    await _bibleManager.removeVersion(id);
    await refreshAll();
    return true;
  }

  // --- Dictionary Operations ---

  bool isDictInstalled(String id) => _dictManager.isInstalled(id);
  bool isDictDownloading(String id) => _dictManager.isDownloading(id);
  double getDictProgress(String id) => _dictManager.getProgress(id);

  Future<void> downloadDictionary(String id) async {
    await _dictManager.downloadDictionary(id);
    await refreshAll();
  }

  Future<void> deleteDictionary(String id) async {
    await _dictManager.deleteDictionary(id);
    await refreshAll();
  }

  // --- Book Operations ---

  bool isBookInstalled(String id) =>
      _state.installedBookIds.contains(id) || _state.booksBundleInstalled;
  bool isBookDownloading(String id) => _bookService.isBookDownloading(id);

  Future<void> downloadBooksBundle() async {
    await _bookService.downloadAndInstall();
    await refreshAll();
  }

  Future<void> downloadSingleBook(String id, {String? language}) async {
    await _bookService.downloadSingleBook(id, language: language);
    await refreshAll();
  }

  Future<void> deleteBook(String id) async {
    await _bookService.removeBookDownload(id);
    await refreshAll();
  }

  // --- Songs Operations ---

  Future<void> downloadSongs({String? language}) async {
    await _songsManager.download(language: language);
    await refreshAll();
  }

  Future<void> deleteSongs() async {
    await _songsManager.delete();
    await refreshAll();
  }

  // --- Article Operations ---

  bool isArticleLanguageInstalled(String lang) =>
      _articlesManager.isInstalled(lang);

  bool isArticleLanguageDownloading(String lang) =>
      _articlesManager.isDownloading(lang);

  double getArticleLanguageProgress(String lang) =>
      _articlesManager.getProgress(lang);

  Future<void> downloadArticlesLanguage(String lang) async {
    await _articlesManager.downloadLanguage(lang);
    await refreshAll();
  }

  Future<void> deleteArticlesLanguage(String lang) async {
    await _articlesManager.deleteLanguage(lang);
    await refreshAll();
  }

  // --- Study DB Operations ---

  Future<void> downloadStudyDb({String versionId = 'taobvsi'}) async {
    _state = _state.copyWith(
      isStudyDbDownloading: true,
      studyDbProgress: 0.0,
    );
    notifyListeners();

    try {
      await BibleStudyUpdater.downloadUpdate((progress) {
        if (!_isDisposed) {
          _state = _state.copyWith(studyDbProgress: progress);
          notifyListeners();
        }
      }, versionId: versionId);

      _state = _state.copyWith(
        isStudyDbDownloading: false,
        studyDbInstalled: true,
      );
    } catch (_) {
      _state = _state.copyWith(isStudyDbDownloading: false);
    }
    await refreshAll();
  }

  Future<void> deleteStudyDb({String versionId = 'taobvsi'}) async {
    await BibleStudyUpdater.removeDownload(versionId);
    await refreshAll();
  }

  // --- Audio Operations ---

  Future<void> deleteAudioSeries(String seriesId) async {
    await _audioLibrary.removeSeries(seriesId);
    await refreshAll();
  }

  Future<void> clearAllAudio() async {
    await _audioLibrary.removeAll();
    await refreshAll();
  }

  // --- Core Study Bundle Orchestrator ---

  Future<void> downloadCoreBundle() async {
    if (_state.isCoreBundleDownloading) return;

    _state = _state.copyWith(
      isCoreBundleDownloading: true,
      coreBundleProgress: 0.05,
    );
    notifyListeners();

    try {
      // 1. Default Bible
      final defaultMeta =
          BibleDownloadManager.getMeta(BibleDownloadManager.defaultVersionId);
      if (!_bibleManager.isInstalled(defaultMeta.id)) {
        await _bibleManager.downloadVersion(defaultMeta);
      }
      _state = _state.copyWith(coreBundleProgress: 0.35);
      notifyListeners();

      // 2. Easton's & Strong's
      if (!_dictManager.isInstalled('eastons')) {
        await _dictManager.downloadDictionary('eastons');
      }
      _state = _state.copyWith(coreBundleProgress: 0.55);
      notifyListeners();

      if (!_dictManager.isInstalled('strongs')) {
        await _dictManager.downloadDictionary('strongs');
      }
      _state = _state.copyWith(coreBundleProgress: 0.75);
      notifyListeners();

      // 3. Books & Commentaries Bundle
      if (!_state.booksBundleInstalled) {
        await _bookService.downloadAndInstall();
      }
      _state = _state.copyWith(
        coreBundleProgress: 1.0,
        isCoreBundleDownloading: false,
      );
    } catch (_) {
      _state = _state.copyWith(isCoreBundleDownloading: false);
    }
    await refreshAll();
  }
}
