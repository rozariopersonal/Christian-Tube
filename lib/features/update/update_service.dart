import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateService {
  static const String releasesApiUrl =
      'https://api.github.com/repos/rozariopersonal/Christian-Tube-Releases/releases/latest';

  static Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = 'v${packageInfo.version}';

      final response = await Dio().get(
        releasesApiUrl,
        options: Options(headers: {'Accept': 'application/vnd.github.v3+json'}),
      );

      if (response.statusCode == 200 && response.data != null) {
        final latestTag = response.data['tag_name'] as String?;
        if (latestTag != null && latestTag != currentVersion) {
          // Find APK asset
          final assets = response.data['assets'] as List<dynamic>? ?? [];
          final apkAsset = assets.firstWhere(
            (a) => a['name'].toString().endsWith('.apk'),
            orElse: () => null,
          );

          if (apkAsset != null) {
            return {
              'hasUpdate': true,
              'latestVersion': latestTag,
              'downloadUrl': apkAsset['browser_download_url'],
              'releaseNotes': response.data['body'] ?? '',
            };
          }
        }
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
    return null;
  }

  static Future<void> downloadAndInstallApk({
    required String downloadUrl,
    required Function(double progress) onProgress,
    required VoidCallback onComplete,
    required Function(String error) onError,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final savePath = '${tempDir.path}/christian-tube-update.apk';

      // Remove existing file if present
      final file = File(savePath);
      if (await file.exists()) {
        await file.delete();
      }

      final dio = Dio();
      await dio.download(
        downloadUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            onProgress(received / total);
          }
        },
      );

      onComplete();
      await OpenFile.open(savePath);
    } catch (e) {
      onError('Failed to download update: $e');
    }
  }
}
