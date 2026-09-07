import 'dart:collection';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:mobile/core/api/github_data_service.dart';
import 'package:mobile/features/engines/scripture/models/scripture_theme_state.dart';

/// Downloads and registers reader font families on demand from the releases
/// repository, instead of bundling font files with the app.
///
/// Fonts are NOT packaged in the APK/web bundle. When a family is needed it
/// is fetched live via [GitHubDataService] (CDN-first, raw GitHub fallback),
/// registered with the engine through [FontLoader], and cached as a file in
/// the application-support directory so subsequent reads are offline.
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

  /// Families already registered with the engine.
  Set<String> get registered => UnmodifiableSetView(_registered);

  /// Families currently being downloaded.
  Set<String> get loading => UnmodifiableSetView(_loading);

  bool isReady(String family) => _registered.contains(family);

  bool isLoading(String family) => _loading.contains(family);

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

  Future<Uint8List> _download(String family) async {
    final urls = GitHubDataService.readerFontUrls(_slug(family));
    final dio = Dio();
    Object? lastError;
    for (final url in urls) {
      try {
        final response = await dio.get<List<int>>(
          url,
          options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(seconds: 60),
          ),
        );
        final data = response.data;
        if (data != null && data.isNotEmpty) {
          _writeCache(family, Uint8List.fromList(data));
          return Uint8List.fromList(data);
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
      final file = _cacheFile(dir.path, family);
      if (await file.exists()) return await file.readAsBytes();
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
    } catch (_) {}
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