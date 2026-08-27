import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:android_package_installer/android_package_installer.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/app_config.dart';
import 'widgets/update_dialog.dart';

class UpdateService {
  static String get releasesApiUrl =>
      'https://api.github.com/repos/${AppConfig.releasesRepo}/releases/latest';

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
              'title': response.data['name'] ?? '${AppConfig.appName} $latestTag',
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

  static Future<void> openInBrowser(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  static Future<String> getApkSavePath() async {
    Directory? dir;
    try {
      final extDirs = await getExternalCacheDirectories();
      if (extDirs != null && extDirs.isNotEmpty) {
        dir = extDirs.first;
      }
    } catch (_) {}

    try {
      dir ??= await getExternalStorageDirectory();
    } catch (_) {}

    try {
      dir ??= await getApplicationDocumentsDirectory();
    } catch (_) {}

    dir ??= await getTemporaryDirectory();
    return '${dir.path}/${AppConfig.instanceId}-update.apk';
  }

  static Future<void> launchApkInstaller(String savePath, String downloadUrl) async {
    try {
      final statusCode = await AndroidPackageInstaller.installApk(apkFilePath: savePath);
      final status = statusCode != null ? PackageInstallerStatus.byCode(statusCode) : PackageInstallerStatus.unknown;

      if (status != PackageInstallerStatus.success) {
         debugPrint('Installer failed with status: $status, opening browser fallback...');
         await openInBrowser(downloadUrl);
      }
    } catch (e) {
      debugPrint('Direct installer invocation error: $e, opening browser fallback...');
      await openInBrowser(downloadUrl);
    }
  }

  static Future<void> downloadAndInstallApkWithProgress({
    required String downloadUrl,
    CancelToken? cancelToken,
    required Function(int received, int total) onProgress,
    required Function(String savePath) onComplete,
    required Function(String error) onError,
  }) async {
    try {
      final savePath = await getApkSavePath();

      final file = File(savePath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
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

      onComplete(savePath);

      // Automatically launch the Android OS Package Installer immediately
      await launchApkInstaller(savePath, downloadUrl);
    } catch (e) {
      if (CancelToken.isCancel(e as dynamic)) {
        return;
      }
      debugPrint('Direct install error: $e, opening browser fallback...');
      try {
        await openInBrowser(downloadUrl);
      } catch (_) {
        onError('Could not install automatically. Opening browser download...');
      }
    }
  }

  static Future<void> downloadAndInstallApk({
    required String downloadUrl,
    required Function(double progress) onProgress,
    required Function(String savePath) onComplete,
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
