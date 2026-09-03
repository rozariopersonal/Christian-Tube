import 'package:flutter/foundation.dart';
import '../models/bible_background_note.dart';

/// Legacy service for Bible historical and cultural background notes.
///
/// Historical and cultural background notes have been superseded by unified
/// verse study concepts (`BibleStudyWebService` / `BibleStudyUpdater`).
/// This class is maintained as a stub so existing UI consumers continue to
/// function without errors.
class BibleBackgroundService extends ChangeNotifier {
  static final BibleBackgroundService _instance =
      BibleBackgroundService._internal();
  factory BibleBackgroundService() => _instance;
  BibleBackgroundService._internal();

  bool get isDownloading => false;
  bool get isIndeterminate => false;
  double get progress => 0.0;
  String? get lastError => null;

  /// Backgrounds are superseded by the study engine.
  Future<bool> isInstalled() async => false;

  Future<bool> downloadAndInstall() async => true;

  Future<Map<int, List<BibleBackgroundNote>>> getBackgroundsForChapter(
    int bookNumber,
    int chapter,
  ) async =>
      const {};

  Future<Map<int, List<BibleBackgroundNote>>> fetchChapterOnline(
    int bookNumber,
    int chapter,
  ) async =>
      const {};

  Future<void> removeAll() async {
    notifyListeners();
  }
}
