import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader, Uint8List;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:mobile/core/api/github_data_service.dart';
import 'package:mobile/features/engines/scripture/models/scripture_theme_state.dart';

/// Downloads, registers, and manages reader font families on demand from the
/// releases repository, instead of bundling large font files with the app.
///
/// Fonts are NOT packaged in the APK/web bundle. When a family is needed it
/// is fetched live via [GitHubDataService] (CDN-first, raw GitHub fallback),
/// registered with the engine through [FontLoader], and cached as a file in
/// the `reader_fonts` directory so subsequent reads work completely offline.
///
/// The `fontFamily` written into reader text styles is the resolved Google
/// Fonts family name ([ScriptureThemeCatalog.resolveFontFamily]); once the
/// family is registered here, the engine repaints existing text using it.
class ReaderFontsService extends ChangeNotifier {
  ReaderFontsService._();

  static final ReaderFontsService instance = ReaderFontsService._();

  final Set<String> _registered = <String>{};
  final Set<String> _loading = <String>{};
  final Map<String, Future<bool>> _inflight = <String, Future<bool>>{};
  final Map<String, Uint8List> _memoryCache = <String, Uint8List>{};
  final Set<String> _installedCache = <String>{};
  bool _installedScanned = false;

  final Dio _dio = Dio();

  /// Families already registered with the engine.
  Set<String> get registered => UnmodifiableSetView(_registered);

  /// Families currently being downloaded.
  Set<String> get loading => UnmodifiableSetView(_loading);

  bool isReady(String family) => _registered.contains(family);

  bool isLoading(String family) => _loading.contains(family);

  /// Synchronously or cached check if a family is registered or cached.
  bool isFamilyInstalledSync(String family) {
    return _registered.contains(family) ||
        _memoryCache.containsKey(family) ||
        _installedCache.contains(family);
  }

  /// Checks if [family] is installed on disk or in memory.
  Future<bool> isInstalled(String family) async {
    if (isFamilyInstalledSync(family)) return true;
    if (kIsWeb) return false;
    try {
      final dir = await getApplicationSupportDirectory();
      final folder = p.join(dir.path, 'reader_fonts');
      final file = _cacheFile(folder, family);
      final exists = await file.exists();
      if (exists) {
        _installedCache.add(family);
      }
      return exists;
    } catch (_) {
      return false;
    }
  }

  /// Scans disk cache to populate [_installedCache].
  Future<void> scanInstalledFonts() async {
    if (kIsWeb || _installedScanned) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final folder = Directory(p.join(dir.path, 'reader_fonts'));
      if (await folder.exists()) {
        final entities = folder.listSync();
        for (final entity in entities) {
          if (entity is File && entity.path.endsWith('.ttf')) {
            final basename = p.basenameWithoutExtension(entity.path);
            final family = basename.replaceAll('_', ' ');
            _installedCache.add(family);
          }
        }
      }
      _installedScanned = true;
    } catch (_) {}
  }

  /// Resolves [fontId] for [languageCode] and ensures that family is ready,
  /// downloading + registering it if necessary. Returns false when the font
  /// cannot be resolved or no mirror serves it (caller should keep the
  /// fallback theme font).
  Future<bool> ensureResolved(String fontId, String? languageCode) async {
    final family = ScriptureThemeCatalog.resolveFontFamily(fontId, languageCode);
    if (family == null) return false;
    return ensureFamily(family);
  }

  /// Ensures [family] is registered. Concurrent callers share one download.
  Future<bool> ensureFamily(String family) =>
      _inflight[family] ??= _load(family);

  Future<bool> _load(String family) async {
    _loading.add(family);
    notifyListeners();
    try {
      final Uint8List bytes = await _readCache(family) ?? await _download(family);
      if (bytes.isEmpty) return false;
      final Uint8List cached =
          _memoryCache.putIfAbsent(family, () => bytes);
      await _register(family, ByteData.sublistView(cached));
      _registered.add(family);
      _installedCache.add(family);
      return true;
    } catch (e) {
      debugPrint('ReaderFontsService: failed to load font $family: $e');
      return false;
    } finally {
      _loading.remove(family);
      _inflight.remove(family);
      notifyListeners();
    }
  }

  bool get _isTestEnvironment {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  Future<Uint8List> _download(String family) async {
    if (_isTestEnvironment) {
      return Uint8List(0);
    }
    final urls = GitHubDataService.readerFontUrls(family);
    Object? lastError;
    for (final url in urls) {
      try {
        final response = await _dio.get<List<int>>(
          url,
          options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(seconds: 45),
            sendTimeout: const Duration(seconds: 15),
          ),
        );
        final data = response.data;
        if (data != null && data.isNotEmpty) {
          final bytes = Uint8List.fromList(data);
          unawaited(_writeCache(family, bytes));
          return bytes;
        }
        lastError = StateError('Empty body for $url');
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? StateError('No font mirror for $family');
  }

  Future<Uint8List?> _readCache(String family) async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      final folder = p.join(dir.path, 'reader_fonts');
      final file = _cacheFile(folder, family);
      if (await file.exists()) {
        _installedCache.add(family);
        return await file.readAsBytes();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _writeCache(String family, Uint8List bytes) async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final folder = p.join(dir.path, 'reader_fonts');
      final file = _cacheFile(folder, family);
      if (!await file.exists()) await file.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      _installedCache.add(family);
    } catch (_) {}
  }

  /// Deletes a cached font file from disk.
  Future<void> deleteFont(String family) async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final folder = p.join(dir.path, 'reader_fonts');
      final file = _cacheFile(folder, family);
      if (await file.exists()) {
        await file.delete();
      }
      _memoryCache.remove(family);
      _installedCache.remove(family);
      notifyListeners();
    } catch (e) {
      debugPrint('ReaderFontsService: failed to delete font $family: $e');
    }
  }

  /// Removes all downloaded font files from disk.
  Future<void> removeAllDownloadedFonts() async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final folder = Directory(p.join(dir.path, 'reader_fonts'));
      if (await folder.exists()) {
        final entities = folder.listSync();
        for (final entity in entities) {
          if (entity is File && entity.path.endsWith('.ttf')) {
            await entity.delete();
          }
        }
      }
      _memoryCache.clear();
      _installedCache.clear();
      notifyListeners();
    } catch (e) {
      debugPrint('ReaderFontsService: failed to clear fonts: $e');
    }
  }

  /// Downloads all fonts for a specific [languageCode] concurrently.
  Future<void> downloadAllForLanguage(String languageCode, {String? category}) async {
    final fonts = ScriptureThemeCatalog.getFontsForLanguage(languageCode);
    final futures = <Future<bool>>[];
    for (final opt in fonts) {
      final family = ScriptureThemeCatalog.resolveFontFamily(opt.id, languageCode);
      if (family != null) {
        futures.add(ensureFamily(family));
      }
    }
    await Future.wait(futures);
  }

  /// Calculates total on-disk byte size of downloaded reader fonts.
  Future<int> getInstalledFontsSizeBytes() async {
    if (kIsWeb) return 0;
    try {
      final dir = await getApplicationSupportDirectory();
      final folder = Directory(p.join(dir.path, 'reader_fonts'));
      if (!await folder.exists()) return 0;
      int total = 0;
      final entities = folder.listSync();
      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.ttf')) {
          total += await entity.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Counts the total number of installed reader fonts.
  Future<int> getInstalledFontsCount() async {
    if (kIsWeb) return _registered.length;
    try {
      final dir = await getApplicationSupportDirectory();
      final folder = Directory(p.join(dir.path, 'reader_fonts'));
      if (!await folder.exists()) return 0;
      int count = 0;
      final entities = folder.listSync();
      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.ttf')) {
          count++;
        }
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  File _cacheFile(String folderPath, String family) =>
      File(p.join(folderPath, '${_slug(family)}.ttf'));

  static String _slug(String family) => family.replaceAll(' ', '_');

  Future<void> _register(String family, ByteData data) async {
    try {
      final loader = FontLoader(family)..addFont(Future.value(data));
      await loader.load();
    } catch (e) {
      debugPrint('ReaderFontsService: FontLoader failed for $family: $e');
    }
  }
}