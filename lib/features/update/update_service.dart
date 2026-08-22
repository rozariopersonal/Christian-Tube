import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'widgets/update_dialog.dart';

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
              'currentVersion': currentVersion,
              'latestVersion': latestTag,
              'title': response.data['name'] ?? 'ChristianTube $latestTag',
              'downloadUrl': apkAsset['browser_download_url'],
              'sizeBytes': apkAsset['size'] ?? 0,
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

  static Future<void> showUpdatePopup(BuildContext context, Map<String, dynamic> updateData) async {
    return UpdateDialog.show(context, updateData);
  }

  static Future<void> downloadAndInstallApkWithProgress({
    required String downloadUrl,
    CancelToken? cancelToken,
    required Function(int received, int total) onProgress,
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
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          onProgress(received, total);
        },
      );

      onComplete();
      await OpenFilex.open(savePath);
    } catch (e) {
      if (CancelToken.isCancel(e as dynamic)) {
        debugPrint('Download cancelled by user.');
        return;
      }
      onError('Failed to download update: $e');
    }
  }

  static Future<void> downloadAndInstallApk({
    required String downloadUrl,
    required Function(double progress) onProgress,
    required VoidCallback onComplete,
    required Function(String error) onError,
  }) async {
    return downloadAndInstallApkWithProgress(
      downloadUrl: downloadUrl,
      onProgress: (received, total) {
        if (total > 0) {
          onProgress(received / total);
        }
      },
      onComplete: onComplete,
      onError: onError,
    );
  }
}
