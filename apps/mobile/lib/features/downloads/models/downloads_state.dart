import 'package:flutter/foundation.dart';
import '../../books/models/book.dart';
import '../../dictionary/services/dictionary_download_manager.dart';
import '../../engines/scripture/models/bible_version_meta.dart';
import '../../engines/scripture/services/bible_download_manager.dart';
import 'storage_breakdown.dart';

/// Summary of an audio series currently present on disk.
@immutable
class AudioDownloadedSeriesItem {
  final String seriesId;
  final String title;
  final int trackCount;
  final int totalBytes;

  const AudioDownloadedSeriesItem({
    required this.seriesId,
    required this.title,
    required this.trackCount,
    required this.totalBytes,
  });

  String get sizeFormatted => StorageBreakdown.formatBytes(totalBytes);
}

/// Immutable snapshot representing the entire state of the downloads feature.
@immutable
class DownloadsState {
  final StorageBreakdown storage;
  final bool isLoading;

  // Catalog data
  final List<BibleVersionMeta> bibles;
  final List<DictionaryMeta> dictionaries;
  final List<Book> books;
  final Set<String> installedBookIds;
  final List<AudioDownloadedSeriesItem> audioSeries;

  // Global bundle & study state
  final bool booksBundleInstalled;
  final bool isBooksBundleDownloading;
  final double booksBundleProgress;

  final Set<String> installedArticleLanguages;
  final Set<String> downloadingArticleLanguages;

  final bool songsInstalled;
  final bool isSongsDownloading;
  final double songsProgress;

  final bool studyDbInstalled;
  final bool isStudyDbDownloading;
  final double studyDbProgress;

  final bool isCoreBundleDownloading;
  final double coreBundleProgress;

  // Search & Filter state
  final String bibleSearch;
  final String bibleLanguageFilter;
  final String dictSearch;
  final String dictFilter;
  final String bookSearch;
  final String bookLanguageFilter;
  final bool onlyInstalled;

  const DownloadsState({
    this.storage = const StorageBreakdown(),
    this.isLoading = false,
    this.bibles = BibleDownloadManager.catalog,
    this.dictionaries = DictionaryDownloadManager.catalog,
    this.books = const [],
    this.installedBookIds = const {},
    this.audioSeries = const [],
    this.booksBundleInstalled = false,
    this.isBooksBundleDownloading = false,
    this.booksBundleProgress = 0.0,
    this.installedArticleLanguages = const {},
    this.downloadingArticleLanguages = const {},
    this.songsInstalled = false,
    this.isSongsDownloading = false,
    this.songsProgress = 0.0,
    this.studyDbInstalled = false,
    this.isStudyDbDownloading = false,
    this.studyDbProgress = 0.0,
    this.isCoreBundleDownloading = false,
    this.coreBundleProgress = 0.0,
    this.bibleSearch = '',
    this.bibleLanguageFilter = 'All',
    this.dictSearch = '',
    this.dictFilter = 'All',
    this.bookSearch = '',
    this.bookLanguageFilter = 'All',
    this.onlyInstalled = false,
  });

  DownloadsState copyWith({
    StorageBreakdown? storage,
    bool? isLoading,
    List<BibleVersionMeta>? bibles,
    List<DictionaryMeta>? dictionaries,
    List<Book>? books,
    Set<String>? installedBookIds,
    List<AudioDownloadedSeriesItem>? audioSeries,
    bool? booksBundleInstalled,
    bool? isBooksBundleDownloading,
    double? booksBundleProgress,
    Set<String>? installedArticleLanguages,
    Set<String>? downloadingArticleLanguages,
    bool? songsInstalled,
    bool? isSongsDownloading,
    double? songsProgress,
    bool? studyDbInstalled,
    bool? isStudyDbDownloading,
    double? studyDbProgress,
    bool? isCoreBundleDownloading,
    double? coreBundleProgress,
    String? bibleSearch,
    String? bibleLanguageFilter,
    String? dictSearch,
    String? dictFilter,
    String? bookSearch,
    String? bookLanguageFilter,
    bool? onlyInstalled,
  }) {
    return DownloadsState(
      storage: storage ?? this.storage,
      isLoading: isLoading ?? this.isLoading,
      bibles: bibles ?? this.bibles,
      dictionaries: dictionaries ?? this.dictionaries,
      books: books ?? this.books,
      installedBookIds: installedBookIds ?? this.installedBookIds,
      audioSeries: audioSeries ?? this.audioSeries,
      booksBundleInstalled: booksBundleInstalled ?? this.booksBundleInstalled,
      isBooksBundleDownloading:
          isBooksBundleDownloading ?? this.isBooksBundleDownloading,
      booksBundleProgress: booksBundleProgress ?? this.booksBundleProgress,
      installedArticleLanguages:
          installedArticleLanguages ?? this.installedArticleLanguages,
      downloadingArticleLanguages:
          downloadingArticleLanguages ?? this.downloadingArticleLanguages,
      songsInstalled: songsInstalled ?? this.songsInstalled,
      isSongsDownloading: isSongsDownloading ?? this.isSongsDownloading,
      songsProgress: songsProgress ?? this.songsProgress,
      studyDbInstalled: studyDbInstalled ?? this.studyDbInstalled,
      isStudyDbDownloading: isStudyDbDownloading ?? this.isStudyDbDownloading,
      studyDbProgress: studyDbProgress ?? this.studyDbProgress,
      isCoreBundleDownloading:
          isCoreBundleDownloading ?? this.isCoreBundleDownloading,
      coreBundleProgress: coreBundleProgress ?? this.coreBundleProgress,
      bibleSearch: bibleSearch ?? this.bibleSearch,
      bibleLanguageFilter: bibleLanguageFilter ?? this.bibleLanguageFilter,
      dictSearch: dictSearch ?? this.dictSearch,
      dictFilter: dictFilter ?? this.dictFilter,
      bookSearch: bookSearch ?? this.bookSearch,
      bookLanguageFilter: bookLanguageFilter ?? this.bookLanguageFilter,
      onlyInstalled: onlyInstalled ?? this.onlyInstalled,
    );
  }
}
