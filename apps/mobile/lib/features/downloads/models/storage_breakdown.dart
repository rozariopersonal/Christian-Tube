import 'package:flutter/foundation.dart';

/// Represents a measured snapshot of offline storage consumption across all
/// download categories in Christian Tube.
@immutable
class StorageBreakdown {
  final int biblesBytes;
  final int dictionariesBytes;
  final int booksBytes;
  final int audioBytes;
  final int songsBytes;
  final int articlesBytes;
  final int studyDbBytes;

  final int biblesCount;
  final int dictsCount;
  final int booksCount;
  final int audioTracksCount;
  final int audioSeriesCount;
  final bool songsInstalled;
  final int articlesCount;
  final bool studyDbInstalled;

  const StorageBreakdown({
    this.biblesBytes = 0,
    this.dictionariesBytes = 0,
    this.booksBytes = 0,
    this.audioBytes = 0,
    this.songsBytes = 0,
    this.articlesBytes = 0,
    this.studyDbBytes = 0,
    this.biblesCount = 0,
    this.dictsCount = 0,
    this.booksCount = 0,
    this.audioTracksCount = 0,
    this.audioSeriesCount = 0,
    this.songsInstalled = false,
    this.articlesCount = 0,
    this.studyDbInstalled = false,
  });

  /// Total bytes consumed by all offline assets.
  int get totalBytes =>
      biblesBytes +
      dictionariesBytes +
      booksBytes +
      audioBytes +
      songsBytes +
      articlesBytes +
      studyDbBytes;

  /// Human-readable format of [bytes] (e.g. "14.2 MB", "1.1 GB").
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    final formatted = count.toStringAsFixed(count >= 100 || i == 0 ? 0 : 1);
    final clean = formatted.endsWith('.0') ? formatted.substring(0, formatted.length - 2) : formatted;
    return '$clean ${suffixes[i]}';
  }

  String get totalFormatted => formatBytes(totalBytes);
  String get biblesFormatted => formatBytes(biblesBytes);
  String get dictionariesFormatted => formatBytes(dictionariesBytes);
  String get booksFormatted => formatBytes(booksBytes);
  String get audioFormatted => formatBytes(audioBytes);
  String get songsFormatted => formatBytes(songsBytes);
  String get articlesFormatted => formatBytes(articlesBytes);
  String get studyDbFormatted => formatBytes(studyDbBytes);

  /// Fraction of total offline storage taken by [bytes] (0.0 to 1.0).
  double shareOf(int bytes) {
    if (totalBytes <= 0) return 0.0;
    return (bytes / totalBytes).clamp(0.0, 1.0);
  }
}
