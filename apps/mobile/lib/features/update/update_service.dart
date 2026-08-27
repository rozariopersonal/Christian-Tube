import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:android_package_installer/android_package_installer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/app_config.dart';
import 'widgets/update_dialog.dart';

class UpdateService {
  static String get releasesApiUrl =>
      'https://api.github.com/repos/${AppConfig.releasesRepo}/releases/latest';

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _notificationsInitialized = false;

  static Future<void> _initNotifications() async {
    if (_notificationsInitialized) return;
    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);
      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) async {
          final apkPath = response.payload;
          if (apkPath != null && apkPath.isNotEmpty) {
            await launchApkInstaller(apkPath, '');
          }
        },
      );
      _notificationsInitialized = true;
    } catch (e) {
      debugPrint('Notifications init failed: $e');
    }
  }

  static Future<void> _showInstallReadyNotification(String apkPath) async {
    try {
      await _initNotifications();
      const androidDetails = AndroidNotificationDetails(
        'update_channel',
        'App Updates',
        channelDescription: 'Notifies when an update is ready to install',
        importance: Importance.high,
        priority: Priority.high,
        ongoing: false,
        autoCancel: true,
        icon: '@mipmap/ic_launcher',
      );
      const details = NotificationDetails(android: androidDetails);
      await _notifications.show(
        42,
        '${AppConfig.appName} update ready to install',
        'Tap to install the downloaded update.',
        details,
        payload: apkPath,
      );
    } catch (e) {
      debugPrint('Notification display failed: $e');
    }
  }

  /// Compares two semver strings (e.g. 'v1.58.0' or '1.58.0' vs 'v1.28.0' or '1.28.0').
  /// Returns true if [latestVersion] is strictly newer than [currentVersion].
  static bool isNewerVersion(String latestVersion, String currentVersion) {
    try {
      final cleanLatest = latestVersion
          .trim()
          .replaceAll(RegExp(r'^[vV]'), '')
          .split('+')
          .first
          .split('-')
          .first
          .trim();
      final cleanCurrent = currentVersion
          .trim()
          .replaceAll(RegExp(r'^[vV]'), '')
          .split('+')
          .first
          .split('-')
          .first
          .trim();

      if (cleanLatest.isEmpty || cleanCurrent.isEmpty) {
        return false;
      }

      final latestParts = cleanLatest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final currentParts = cleanCurrent.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      final maxLen = latestParts.length > currentParts.length
          ? latestParts.length
          : currentParts.length;

      for (int i = 0; i < maxLen; i++) {
        final l = i < latestParts.length ? latestParts[i] : 0;
        final c = i < currentParts.length ? currentParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }

      // If base semver is identical, check build numbers if available
      final latestBuild = _extractBuildNumber(latestVersion);
      final currentBuild = _extractBuildNumber(currentVersion);
      if (latestBuild != null && currentBuild != null) {
        return latestBuild > currentBuild;
      }

      return false;
    } catch (_) {
      return latestVersion.trim() != currentVersion.trim();
    }
  }

  static int? _extractBuildNumber(String version) {
    if (version.contains('+')) {
      final part = version.split('+').last.trim();
      return int.tryParse(part);
    }
    return null;
  }

  static Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      String currentVersion = AppConfig.version;
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        if (packageInfo.version.isNotEmpty) {
          currentVersion = packageInfo.version;
        }
      } catch (e) {
        debugPrint('PackageInfo error: $e');
      }

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          headers: {
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': '${AppConfig.appName}/$currentVersion (Android)',
          },
        ),
      );

      final response = await dio.get(releasesApiUrl);

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;

        if (data is Map) {
          final latestTag = data['tag_name'] as String?;
          if (latestTag != null && isNewerVersion(latestTag, currentVersion)) {
            // Find APK asset
            final assets = data['assets'] as List<dynamic>? ?? [];
            dynamic apkAsset;

            // 1. Look for instance-configured APK name (e.g. christian-tube.apk)
            for (final a in assets) {
              if (a is Map) {
                final name = a['name']?.toString().toLowerCase() ?? '';
                if (name == AppConfig.apkFileName.toLowerCase()) {
                  apkAsset = a;
                  break;
                }
              }
            }

            // 2. Fallback to any asset ending with .apk
            if (apkAsset == null) {
              for (final a in assets) {
                if (a is Map) {
                  final name = a['name']?.toString().toLowerCase() ?? '';
                  if (name.endsWith('.apk')) {
                    apkAsset = a;
                    break;
                  }
                }
              }
            }

            if (apkAsset != null && apkAsset is Map) {
              return {
                'hasUpdate': true,
                'currentVersion': currentVersion.startsWith('v') ? currentVersion : 'v$currentVersion',
                'latestVersion': latestTag.startsWith('v') ? latestTag : 'v$latestTag',
                'title': data['name'] ?? '${AppConfig.appName} $latestTag',
                'downloadUrl': apkAsset['browser_download_url'] ?? '',
                'sizeBytes': apkAsset['size'] ?? 0,
                'releaseNotes': data['body'] ?? '',
              };
            }
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
    if (url.isEmpty) return;
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Failed to open browser URL: $e');
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
      final file = File(savePath);
      if (!await file.exists() || await file.length() == 0) {
        debugPrint('Downloaded APK file not found at $savePath');
        if (downloadUrl.isNotEmpty) {
          await openInBrowser(downloadUrl);
        }
        return;
      }

      // Check / request install unknown apps permission on Android
      if (Platform.isAndroid) {
        try {
          final status = await Permission.requestInstallPackages.status;
          if (!status.isGranted) {
            final res = await Permission.requestInstallPackages.request();
            debugPrint('Install packages permission result: $res');
          }
        } catch (e) {
          debugPrint('Permission.requestInstallPackages check error: $e');
        }

        // 1. Primary method: AndroidPackageInstaller native session
        try {
          debugPrint('Attempting installation with AndroidPackageInstaller...');
          final code = await AndroidPackageInstaller.installApk(apkFilePath: savePath);
          debugPrint('AndroidPackageInstaller response code: $code');
          // 0 = STATUS_SUCCESS, 1 = STATUS_PENDING_USER_ACTION
          if (code == 0 || code == 1 || code == null) {
            return;
          }
        } catch (e) {
          debugPrint('AndroidPackageInstaller failed ($e), trying OpenFilex fallback...');
        }
      }

      // 2. Fallback method: OpenFilex intent
      try {
        debugPrint('Attempting installation with OpenFilex...');
        final result = await OpenFilex.open(
          savePath,
          type: 'application/vnd.android.package-archive',
        );
        debugPrint('OpenFilex result type: ${result.type}, message: ${result.message}');
        if (result.type == ResultType.done) {
          return;
        }
      } catch (e) {
        debugPrint('OpenFilex failed: $e');
      }

      // 3. Fallback method: Open in browser
      if (downloadUrl.isNotEmpty) {
        debugPrint('Direct installer failed, opening browser fallback: $downloadUrl');
        await openInBrowser(downloadUrl);
      }
    } catch (e) {
      debugPrint('Direct installer error: $e, opening browser fallback...');
      if (downloadUrl.isNotEmpty) {
        await openInBrowser(downloadUrl);
      }
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

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(minutes: 5),
          headers: {
            'User-Agent': '${AppConfig.appName}/${AppConfig.version} (Android)',
          },
        ),
      );

      await dio.download(
        downloadUrl,
        savePath,
        cancelToken: cancelToken,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          onProgress(received, total);
        },
      );

      onComplete(savePath);

      // Safe notification show (never crashes or aborts installer)
      try {
        await _showInstallReadyNotification(savePath);
      } catch (notifErr) {
        debugPrint('Could not post notification: $notifErr');
      }

      // Launch installer immediately
      await launchApkInstaller(savePath, downloadUrl);
    } catch (e) {
      if (CancelToken.isCancel(e as dynamic)) {
        return;
      }
      debugPrint('Direct install download error: $e, opening browser fallback...');
      onError('Installation error: $e. You can download the update directly.');
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
