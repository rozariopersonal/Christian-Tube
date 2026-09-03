import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile/core/api/github_data_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Downloads a standalone `ffmpeg` executable on demand and caches it locally
/// so it is fetched exactly once per install and never re-downloaded.
///
/// This keeps the full ~60MB+ FFmpeg native bundle OUT of the APK; the binary
/// is pulled from the public releases repo the first time a user creates a
/// short, and reused for all subsequent renders.
class FfmpegDownloader {
  FfmpegDownloader._internal();
  static final FfmpegDownloader _instance = FfmpegDownloader._internal();
  factory FfmpegDownloader() => _instance;

  /// Bump if the hosted ffmpeg binary changes; forces a one-time re-download.
  static const String binaryVersion = '1';

  /// Relative path (in the releases repo) of the exported ffmpeg payload.
  /// The asset may be either a raw executable or a zip containing `ffmpeg`.
  static const String assetPath = 'ffmpeg/ffmpeg_arm64';

  Completer<String>? _inFlight;

  /// Expected executable name inside the downloaded payload.
  static const String binaryName = 'ffmpeg';

  /// Whether ffmpeg has already been fetched and cached on this device.
  Future<bool> get isDownloaded async => (await _cachedPath()) != null;

  /// Returns the cached binary path, or null if it has not been downloaded yet.
  Future<String?> _cachedPath() async {
    try {
      final dir = await _binaryDir();
      final bin = File(p.join(dir.path, binaryName));
      final sentinel = File(p.join(dir.path, '.version'));
      if (bin.existsSync() && sentinel.existsSync()) {
        final version = sentinel.readAsStringSync().trim();
        if (version == binaryVersion) {
          return bin.path;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<Directory> _binaryDir() async {
    // Android app support directory persists across app restarts (until the
    // user clears app data), which is exactly the "download once" scope we want.
    final base = await getApplicationSupportDirectory();
    return Directory(p.join(base.path, 'ffmpeg_bin'));
  }

  /// Ensures the ffmpeg binary is available locally, downloading it from the
  /// releases repo on first use. Safe to call concurrently.
  ///
  /// Returns the absolute path to the cached `ffmpeg` executable, or throws if
  /// it could not be obtained (offline, or no binary hosted yet).
  Future<String> ensureBinary({
    Function(double progress)? onProgress,
  }) async {
    if (!kIsWeb) {
      final cached = await _cachedPath();
      if (cached != null) return cached;
    }

    if (_inFlight != null) return _inFlight!.future;

    final completer = Completer<String>();
    _inFlight = completer;
    try {
      final path = await _download(onProgress: onProgress);
      completer.complete(path);
      return path;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _inFlight = null;
    }
  }

  Future<String> _download({Function(double progress)? onProgress}) async {
    final tempDir = await getTemporaryDirectory();
    final fileName = 'ffmpeg_pkg_${DateTime.now().millisecondsSinceEpoch}';
    final downloadPath = p.join(tempDir.path, fileName);

    // Try each mirror (CDN first, then raw GitHub).
    String? payload;
    for (final url in GitHubDataService.ffmpegBinaryUrls(assetPath)) {
      try {
        await Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(minutes: 5),
            headers: {'Accept': 'application/octet-stream'},
          ),
        ).download(
          url,
          downloadPath,
          deleteOnError: true,
          onReceiveProgress: (received, total) {
            onProgress?.call(total > 0 ? received / total : 0.0);
          },
        );
        payload = downloadPath;
        break;
      } catch (e) {
        debugPrint('FfmpegDownloader: failed to fetch from $url: $e');
      }
    }

    if (payload == null) {
      throw 'Could not download the media engine. Please check your '
          'connection and try creating the short again.';
    }
    final String finalPayload = payload;

    try {
      final finalPath = await _extractOrLike(finalPayload, binaryName);
      _rememberCached(finalPath);
      return finalPath;
    } finally {
      try {
        final f = File(finalPayload);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      // Clean up any leftover extracted temp assets.
      try {
        final dir = Directory(p.join(tempDir.path, binaryName));
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Extracts [ffmpeg] (from a nested zip if the payload is an archive),
  /// or reuses the payload directly if it is already the executable.
  Future<String> _extractOrLike(String payloadPath, String name) async {
    final payloadFile = File(payloadPath);

    // Decide whether to treat the payload as an executable or an archive.
    if (_looksLikeExecutable(payloadFile)) {
      final binDir = await _binaryDir();
      await binDir.create(recursive: true);
      final target = File(p.join(binDir.path, name));
      await payloadFile.copy(target.path);
      _markExecutable(target);
      return target.path;
    }

    // Treat as a zip archive containing the executable.
    final extractedRoot = await _extractZip(payloadFile);
    final candidate = p.join(extractedRoot.path, name);
    if (!await File(candidate).exists()) {
      // Binaries are often nested one level deep.
      final nested = File(p.join(extractedRoot.path, 'ffmpeg', name));
      if (await nested.exists()) {
        return _storeBinary(nested);
      }
      throw 'Downloaded media engine payload did not contain an ffmpeg binary.';
    }
    return _storeBinary(File(candidate));
  }

  Future<String> _storeBinary(File source) async {
    final binDir = await _binaryDir();
    await binDir.create(recursive: true);
    final target = File(p.join(binDir.path, binaryName));
    await source.copy(target.path);
    _markExecutable(target);
    return target.path;
  }

  void _markExecutable(File f) {
    if (!Platform.isWindows) {
      try {
        Process.run('chmod', ['+x', f.path]);
      } catch (_) {}
    }
  }

  bool _looksLikeExecutable(File f) {
    // A real ELF binary starts with 0x7F 'ELF'. A zip starts with 'PK'.
    try {
      final bytes = f.openSync().readSync(4);
      return bytes.isNotEmpty && bytes[0] == 0x7F && bytes[1] == 0x45;
    } catch (_) {
      return false;
    }
  }

  Future<Directory> _extractZip(File archive) async {
    final tempDir = await getTemporaryDirectory();
    final outDir = Directory(p.join(tempDir.path,
        'ffmpeg_x_${DateTime.now().millisecondsSinceEpoch}'));
    await outDir.create(recursive: true);
    try {
      await Process.run('unzip', ['-o', archive.path, '-d', outDir.path]);
    } catch (e) {
      debugPrint('FfmpegDownloader: unzip failed: $e');
      throw 'Could not unpack the media engine.';
    }
    return outDir;
  }

  void _rememberCached(String binaryPath) {
    try {
      final dir = Directory(p.dirname(binaryPath));
      dir.createSync(recursive: true);
      File(p.join(dir.path, '.version')).writeAsStringSync(binaryVersion);
    } catch (_) {}
  }

  /// Removes the cached binary (e.g. for tests or to force a fresh download).
  Future<void> clearCache() async {
    try {
      final dir = await _binaryDir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }
}
