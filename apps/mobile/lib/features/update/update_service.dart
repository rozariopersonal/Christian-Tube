import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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
  static String get releasesApiUrl => AppConfig.isBeta
      ? 'https://api.github.com/repos/${AppConfig.releasesRepo}/releases?per_page=10'
      : 'https://api.github.com/repos/${AppConfig.releasesRepo}/releases/latest';

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

  /// Compares two semver strings (e.g. 'v1.28.1-beta.2' vs 'v1.28.1-beta.1' or '1.29.0' vs '1.29.0-beta.5').
  /// Complies with SemVer 2.0.0 precedence rules including pre-releases.
  /// Returns true if [latestVersion] is strictly newer than [currentVersion].
  static bool isNewerVersion(String latestVersion, String currentVersion) {
    try {
      final cleanLatest = latestVersion.trim().replaceAll(RegExp(r'^[vV]'), '');
      final cleanCurrent = currentVersion.trim().replaceAll(RegExp(r'^[vV]'), '');

      if (cleanLatest.isEmpty || cleanCurrent.isEmpty) return false;

      // Strip build metadata (+...)
      final latestNoBuild = cleanLatest.split('+').first.trim();
      final currentNoBuild = cleanCurrent.split('+').first.trim();

      // Split base (MAJOR.MINOR.PATCH) from prerelease (-beta.1)
      final latestDash = latestNoBuild.indexOf('-');
      final currentDash = currentNoBuild.indexOf('-');

      final latestBase = latestDash != -1 ? latestNoBuild.substring(0, latestDash) : latestNoBuild;
      final latestPre = latestDash != -1 ? latestNoBuild.substring(latestDash + 1) : null;

      final currentBase = currentDash != -1 ? currentNoBuild.substring(0, currentDash) : currentNoBuild;
      final currentPre = currentDash != -1 ? currentNoBuild.substring(currentDash + 1) : null;

      final latestParts = latestBase.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final currentParts = currentBase.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      final maxLen = latestParts.length > currentParts.length ? latestParts.length : currentParts.length;

      for (int i = 0; i < maxLen; i++) {
        final l = i < latestParts.length ? latestParts[i] : 0;
        final c = i < currentParts.length ? currentParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }

      // Base versions are equal.
      // SemVer Rule: A normal version has higher precedence than a pre-release version.
      if (latestPre == null && currentPre != null) {
        // e.g. latest is 1.29.0 (stable), current is 1.29.0-beta.2 -> latest is newer!
        return true;
      }
      if (latestPre != null && currentPre == null) {
        // e.g. latest is 1.29.0-beta.2, current is 1.29.0 (stable) -> latest is older.
        return false;
      }
      if (latestPre != null && currentPre != null) {
        // Both are prereleases. Compare prerelease dot-separated identifiers.
        final lSegments = latestPre.split('.');
        final cSegments = currentPre.split('.');
        final minLen = lSegments.length < cSegments.length ? lSegments.length : cSegments.length;

        for (int i = 0; i < minLen; i++) {
          final lSeg = lSegments[i];
          final cSeg = cSegments[i];
          if (lSeg == cSeg) continue;

          final lNum = int.tryParse(lSeg);
          final cNum = int.tryParse(cSeg);

          if (lNum != null && cNum != null) {
            return lNum > cNum;
          }
          if (lNum != null && cNum == null) {
            return false;
          }
          if (lNum == null && cNum != null) {
            return true;
          }
          return lSeg.compareTo(cSeg) > 0;
        }

        if (lSegments.length != cSegments.length) {
          return lSegments.length > cSegments.length;
        }
      }

      // If both base and prerelease are identical, check build numbers
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
    if (kIsWeb) return null;
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
        final rawData = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;

        final List<dynamic> releaseCandidates = rawData is List
            ? rawData
            : (rawData is Map ? [rawData] : []);

        for (final item in releaseCandidates) {
          if (item is! Map) continue;
          if (item['draft'] == true) continue;

          // If in production mode, skip pre-releases
          if (!AppConfig.isBeta && item['prerelease'] == true) {
            continue;
          }

          final latestTag = item['tag_name'] as String?;
          if (latestTag == null || !isNewerVersion(latestTag, currentVersion)) {
            continue;
          }

          final assets = item['assets'] as List<dynamic>? ?? [];
          dynamic apkAsset;

          // 1. Look for instance-configured APK name (e.g. christian-app-beta.apk or christian-app.apk)
          for (final a in assets) {
            if (a is Map) {
              final name = a['name']?.toString().toLowerCase() ?? '';
              if (name == AppConfig.apkFileName.toLowerCase()) {
                apkAsset = a;
                break;
              }
            }
          }

          // 2. Fallback matching channel:
          // If beta, look for asset containing 'beta' and ending with '.apk'
          // If prod, look for asset ending with '.apk' that does NOT contain 'beta'
          if (apkAsset == null) {
            for (final a in assets) {
              if (a is Map) {
                final name = a['name']?.toString().toLowerCase() ?? '';
                if (name.endsWith('.apk')) {
                  if (AppConfig.isBeta && name.contains('beta')) {
                    apkAsset = a;
                    break;
                  } else if (!AppConfig.isBeta && !name.contains('beta')) {
                    apkAsset = a;
                    break;
                  }
                }
              }
            }
          }

          if (apkAsset != null && apkAsset is Map) {
            return {
              'hasUpdate': true,
              'currentVersion': currentVersion.startsWith('v') ? currentVersion : 'v$currentVersion',
              'latestVersion': latestTag.startsWith('v') ? latestTag : 'v$latestTag',
              'title': item['name'] ?? '${AppConfig.appName} $latestTag',
              'downloadUrl': apkAsset['browser_download_url'] ?? '',
              'sizeBytes': apkAsset['size'] ?? 0,
              'releaseNotes': item['body'] ?? '',
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
    if (kIsWeb) return;
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
      dir = await getTemporaryDirectory();
    } catch (_) {}

    try {
      dir ??= await getApplicationDocumentsDirectory();
    } catch (_) {}

    try {
      dir ??= await getExternalStorageDirectory();
    } catch (_) {}

    final safeDir = dir?.path ?? '/sdcard/Download';
    return '$safeDir/${AppConfig.appName.toLowerCase().replaceAll(' ', '_')}_update.apk';
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

      if (Platform.isAndroid) {
        // 1. Check and request install unknown apps permission
        try {
          final status = await Permission.requestInstallPackages.status;
          if (!status.isGranted) {
            final res = await Permission.requestInstallPackages.request();
            debugPrint('Install packages permission requested: $res');
            if (res.isPermanentlyDenied) {
              await openAppSettings();
            }
          }
        } catch (e) {
          debugPrint('Permission.requestInstallPackages check error: $e');
        }

        // 2. Primary method: OpenFilex intent with FileProvider (invokes system package installer UI immediately)
        try {
          debugPrint('Launching system installer via OpenFilex for $savePath');
          final result = await OpenFilex.open(
            savePath,
            type: 'application/vnd.android.package-archive',
          );
          debugPrint('OpenFilex result type: ${result.type}, message: ${result.message}');
          if (result.type == ResultType.done) {
            return;
          }
        } catch (e) {
          debugPrint('OpenFilex error: $e, trying AndroidPackageInstaller fallback...');
        }

        // 3. Secondary method: AndroidPackageInstaller native session
        try {
          debugPrint('Attempting installation with AndroidPackageInstaller...');
          final code = await AndroidPackageInstaller.installApk(apkFilePath: savePath);
          debugPrint('AndroidPackageInstaller response code: $code');
          if (code == 0 || code == 1) {
            return;
          }
        } catch (e) {
          debugPrint('AndroidPackageInstaller failed: $e');
        }
      }

      // 4. Fallback method: Open in browser
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
