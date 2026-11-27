import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader, Uint8List;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:mobile/core/api/github_data_service.dart';
import 'package:mobile/features/engines/scripture/models/scripture_theme_state.dart';
import 'package:mobile/shared/models/font_catalog.dart';

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
  FontCatalog? _catalog;
  Future<FontCatalog>? _catalogFuture;

  final Dio _dio = Dio();

  /// Loaded remote font catalog (null until [loadCatalog] completes).
  FontCatalog? get catalog => _catalog;

  bool get hasCatalog => _catalog != null && !_catalog!.isEmpty;

  /// Loads `fonts/catalog.json` from disk cache (if any) and refreshes from CDN.
  Future<FontCatalog> loadCatalog({bool forceRefresh = false}) {
    if (!forceRefresh && _catalog != null && !_catalog!.isEmpty) {
      return Future.value(_catalog!);
    }
    return _catalogFuture ??= _fetchAndCacheCatalog().whenComplete(() {
      _catalogFuture = null;
    });
  }

  Future<FontCatalog> _fetchAndCacheCatalog() async {
    if (_isTestEnvironment) {
      return _catalog ?? const FontCatalog();
    }
    // 1. Seed from disk cache for instant offline availability.
    if (!kIsWeb && _catalog == null) {
      try {
        final dir = await getApplicationSupportDirectory();
        final file = File(p.join(dir.path, 'reader_fonts', 'catalog.json'));
        if (await file.exists()) {
          final raw = await file.readAsString();
          final parsed = FontCatalog.fromJson(jsonDecode(raw) as Map<String, dynamic>);
          if (!parsed.isEmpty) {
            _catalog = parsed;
            notifyListeners();
          }
        }
      } catch (_) {}
    }

    // 2. Fetch fresh catalog from releases CDN.
    for (final url in GitHubDataService.fontCatalogUrls()) {
      try {
        final resp = await _dio.get<dynamic>(
          url,
          options: Options(
            responseType: ResponseType.json,
            receiveTimeout: const Duration(seconds: 20),
          ),
        );
        final data = resp.data;
        final Map<String, dynamic>? map = data is Map<String, dynamic>
            ? data
            : (data is String ? jsonDecode(data) as Map<String, dynamic> : null);
        if (map != null) {
          final parsed = FontCatalog.fromJson(map);
          if (!parsed.isEmpty) {
            _catalog = parsed;
            if (!kIsWeb) {
              unawaited(_writeCatalogCache(jsonEncode(map)));
            }
            notifyListeners();
            return parsed;
          }
        }
      } catch (_) {
        // try next mirror
      }
    }
    return _catalog ?? const FontCatalog();
  }

  Future<void> _writeCatalogCache(String rawJson) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'reader_fonts', 'catalog.json'));
      if (!await file.exists()) await file.create(recursive: true);
      await file.writeAsString(rawJson, flush: true);
    } catch (_) {}
  }

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
    final entry = _catalog?.findByIdOrLegacy(fontId);
    if (entry != null) {
      return ensureCatalogFont(entry);
    }
    final family = ScriptureThemeCatalog.resolveFontFamily(fontId, languageCode);
    if (family == null) return false;
    return ensureFamily(family);
  }

  /// Ensures all available weights for a [FontCatalogEntry] are downloaded,
  /// cached, and registered under `entry.family`.
  Future<bool> ensureCatalogFont(FontCatalogEntry entry) {
    final family = entry.family;
    if (_registered.contains(family)) return Future.value(true);
    return _inflight[family] ??= _loadCatalogEntry(entry);
  }

  /// Ensures [family] is registered. Concurrent callers share one download.
  Future<bool> ensureFamily(String family) {
    final entry = _catalog?.findByFamily(family);
    if (entry != null) {
      return ensureCatalogFont(entry);
    }
    return _inflight[family] ??= _load(family);
  }

  Future<bool> _loadCatalogEntry(FontCatalogEntry entry) async {
    final family = entry.family;
    _loading.add(family);
    notifyListeners();
    try {
      final files = entry.files.isNotEmpty
          ? entry.files
          : <String, String>{'regular': '${_slug(family)}-Regular.ttf'};
      final loader = FontLoader(family);
      var loadedCount = 0;

      for (final fileName in files.values) {
        try {
          final bytes = await _readNamedCache(fileName, family) ??
              await _downloadFile(fileName);
          if (bytes.isNotEmpty) {
            _memoryCache.putIfAbsent(fileName, () => bytes);
            loader.addFont(Future.value(ByteData.sublistView(bytes)));
            loadedCount++;
          }
        } catch (e) {
          debugPrint('ReaderFontsService: failed weight $fileName for $family: $e');
        }
      }

      if (loadedCount == 0) return false;
      await loader.load();
      _registered.add(family);
      _installedCache.add(family);
      return true;
    } catch (e) {
      debugPrint('ReaderFontsService: failed to load catalog font $family: $e');
      return false;
    } finally {
      _loading.remove(family);
      _inflight.remove(family);
      notifyListeners();
    }
  }

  Future<Uint8List?> _readNamedCache(String fileName, String family) async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      final folder = p.join(dir.path, 'reader_fonts');
      final exactFile = File(p.join(folder, fileName));
      if (await exactFile.exists()) {
        _installedCache.add(family);
        return await exactFile.readAsBytes();
      }
      final legacyFile = _cacheFile(folder, family);
      if (fileName.endsWith('-Regular.ttf') && await legacyFile.exists()) {
        _installedCache.add(family);
        return await legacyFile.readAsBytes();
      }
    } catch (_) {}
    return null;
  }

  Future<Uint8List> _downloadFile(String fileName) async {
    if (_isTestEnvironment) return Uint8List(0);
    final urls = GitHubDataService.readerFontFileUrls(fileName);
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
          unawaited(_writeNamedCache(fileName, bytes));
          return bytes;
        }
        lastError = StateError('Empty body for $url');
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? StateError('No font mirror for $fileName');
  }

  Future<void> _writeNamedCache(String fileName, Uint8List bytes) async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'reader_fonts', fileName));
      if (!await file.exists()) await file.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {}
  }

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