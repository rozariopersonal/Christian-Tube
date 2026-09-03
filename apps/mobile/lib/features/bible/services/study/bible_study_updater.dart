import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/core/api/github_data_service.dart';

/// Manages optional offline download of study SQLite databases.
///
/// Study data is organized by Bible version under:
///   `study/{versionId}/{versionId}.sqlite`
///
/// By default, study concepts are served live from GitHub per-chapter chunks
/// ([BibleStudyWebService]). This class handles the optional "download for
/// offline" path — users who want the full study DB can trigger a download
/// here. Version detection compares last-modified headers rather than calling
/// the GitHub Releases API (which is rate-limited).
class BibleStudyUpdater {
  static const String _lastUpdateKey = 'study_db_last_updated';

  static String _dbFileName(String versionId) => 'study_$versionId.sqlite';

  /// Returns the local path of the downloaded SQLite file for [versionId],
  /// or null if it has not been downloaded yet. Defaults to 'taobvsi'.
  static Future<String?> getDatabasePath([String versionId = 'taobvsi']) async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/${_dbFileName(versionId)}';
      if (await File(path).exists()) return path;
    } catch (_) {}
    return null;
  }

  static Future<bool> isDownloaded([String versionId = 'taobvsi']) async =>
      (await getDatabasePath(versionId)) != null;

  static Future<bool> checkForUpdates([String versionId = 'taobvsi']) async =>
      false;

  /// Downloads the study SQLite for [versionId] from the releases CDN.
  /// Reports progress via [onProgress] (0.0 → 1.0).
  static Future<void> downloadUpdate(
    Function(double progress)? onProgress, {
    String versionId = 'taobvsi',
  }) async {
    if (kIsWeb) return;
    try {
      final urls = GitHubDataService.studySqliteUrls(versionId);
      final dir = await getApplicationDocumentsDirectory();
      final tempPath = '${dir.path}/${_dbFileName(versionId)}.tmp';
      final finalPath = '${dir.path}/${_dbFileName(versionId)}';
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 10),
      ));

      bool downloaded = false;
      for (final url in urls) {
        try {
          await dio.download(
            url,
            tempPath,
            onReceiveProgress: (received, total) {
              if (total > 0 && onProgress != null) {
                onProgress(received / total);
              }
            },
          );
          downloaded = true;
          break;
        } catch (e) {
          debugPrint('BibleStudyUpdater: failed $url — $e');
        }
      }

      if (!downloaded) throw Exception('Failed to download study material.');

      await File(tempPath).rename(finalPath);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _lastUpdateKey, DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('Error downloading study DB: $e');
      rethrow;
    }
  }

  /// Deletes the locally downloaded SQLite for [versionId].
  static Future<void> removeDownload([String versionId = 'taobvsi']) async {
    if (kIsWeb) return;
    try {
      final path = await getDatabasePath(versionId);
      if (path != null) await File(path).delete();
    } catch (_) {}
  }
}

