import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/config/app_config.dart';

class BibleStudyUpdater {
  static const String _dbFileName = 'study_ta_ovbsi.sqlite';
  static const String _lastUpdateKey = 'study_db_last_updated';

  /// Returns the path to the downloaded SQLite database if it exists, otherwise extracts it from assets.
  static Future<String?> getDatabasePath() async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/$_dbFileName';
      final file = File(path);
      
      // If a downloaded or previously extracted version exists, use it
      if (await file.exists()) {
        return path;
      }
      
      // Fallback: extract from assets (local testing / bundled version)
      try {
        final ByteData data = await rootBundle.load('assets/databases/$_dbFileName');
        final List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await file.writeAsBytes(bytes, flush: true);
        return path;
      } catch (assetError) {
        debugPrint('No study DB found in assets or documents: $assetError');
      }
    } catch (_) {}
    return null;
  }

  /// Checks if a newer database asset is available on GitHub Releases.
  static Future<bool> checkForUpdates() async {
    if (kIsWeb) return false;
    try {
      final dio = Dio();
      final response = await dio.get('https://api.github.com/repos/${AppConfig.releasesRepo}/releases/latest');
      
      if (response.statusCode == 200) {
        final assets = response.data['assets'] as List<dynamic>;
        for (final asset in assets) {
          if (asset['name'] == _dbFileName) {
            final String remoteUpdatedAtStr = asset['updated_at'];
            final remoteUpdatedAt = DateTime.parse(remoteUpdatedAtStr);

            final prefs = await SharedPreferences.getInstance();
            final localUpdatedAtStr = prefs.getString(_lastUpdateKey);

            if (localUpdatedAtStr == null) {
              return true; // No local DB yet
            }

            final localUpdatedAt = DateTime.parse(localUpdatedAtStr);
            if (remoteUpdatedAt.isAfter(localUpdatedAt)) {
              return true; // Update available
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking for study DB updates: $e');
    }
    return false;
  }

  /// Downloads the latest SQLite asset and replaces the local one.
  static Future<void> downloadUpdate(Function(double progress)? onProgress) async {
    if (kIsWeb) return;
    try {
      final dio = Dio();
      final response = await dio.get('https://api.github.com/repos/${AppConfig.releasesRepo}/releases/latest');
      
      if (response.statusCode == 200) {
        final assets = response.data['assets'] as List<dynamic>;
        for (final asset in assets) {
          if (asset['name'] == _dbFileName) {
            final downloadUrl = asset['browser_download_url'];
            final updatedAt = asset['updated_at'];

            final dir = await getApplicationDocumentsDirectory();
            final tempPath = '${dir.path}/${_dbFileName}.tmp';
            final finalPath = '${dir.path}/$_dbFileName';

            await dio.download(
              downloadUrl, 
              tempPath,
              onReceiveProgress: (received, total) {
                if (total > 0 && onProgress != null) {
                  onProgress(received / total);
                }
              },
            );

            // Hot swap
            final tempFile = File(tempPath);
            await tempFile.rename(finalPath);

            // Update timestamp
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_lastUpdateKey, updatedAt);
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Error downloading study DB update: $e');
      throw Exception('Failed to download study material.');
    }
  }
}
