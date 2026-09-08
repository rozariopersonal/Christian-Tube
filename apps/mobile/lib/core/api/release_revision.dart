import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'github_data_service.dart';
import 'release_assets.dart';

/// Resolves the current dataset revision from the top-level releases
/// `manifest.json` (`revision` field) and applies it to [ReleaseAssets].
///
/// Every release-asset URL carries `?rv=<revision>` so that a data push
/// (e.g. replacing a book cover) produces a fresh URL — busting the
/// `CachedNetworkImage` disk cache and any CDN edge cache without requiring
/// an app release.
///
/// Resolution order (never throws):
/// 1. Last-known revision from SharedPreferences (instant, offline-safe).
/// 2. Live `manifest.json` from the releases repo (best effort, short timeout).
class ReleaseRevision {
  ReleaseRevision._();

  static const String _prefsKey = 'release_asset_revision';
  static const Duration _fetchTimeout = Duration(seconds: 6);
  static const Duration _perUrlTimeout = Duration(seconds: 3);

  static bool _loading = false;
  static Future<void>? _inflight;

  /// Loads the current dataset revision, updating [ReleaseAssets.revision].
  /// Safe to call multiple times; concurrent calls share one in-flight load.
  static Future<void> load() {
    return _inflight ??= _load();
  }

  static Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      // 1. Instant fallback from local prefs, so assets already work offline
      //    and don't flash empty revisions on every cold start.
      try {
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getString(_prefsKey);
        if (cached != null && cached.isNotEmpty) {
          ReleaseAssets.revision = cached;
        }
      } catch (e) {
        debugPrint('ReleaseRevision: prefs read failed: $e');
      }

      // 2. Refresh from the live manifest. Ignore the cache-bust query param
      //    when fetching the manifest itself.
      try {
        final client = http.Client();
        try {
          final stopwatch = Stopwatch()..start();
          Map<String, dynamic>? manifest;
          for (final url in GitHubDataService.manifestUrls()) {
            if (stopwatch.elapsed >= _fetchTimeout) break;
            final uri = Uri.parse(url);
            final cleanUri = uri.replace(queryParameters: null);
            try {
              final res = await client.get(cleanUri).timeout(_perUrlTimeout);
              if (res.statusCode == 200 && res.body.isNotEmpty) {
                manifest = jsonDecode(res.body) as Map<String, dynamic>;
                break;
              }
            } catch (_) {}
          }

          final parsed =
              manifest?['revision']?.toString().trim() ?? '';
          if (parsed.isNotEmpty && parsed != ReleaseAssets.revision) {
            ReleaseAssets.revision = parsed;
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(_prefsKey, parsed);
            } catch (e) {
              debugPrint('ReleaseRevision: prefs write failed: $e');
            }
            debugPrint('ReleaseRevision: applied dataset revision $parsed');
          }
        } finally {
          client.close();
        }
      } catch (e) {
        // Non-fatal: keep the cached revision (or empty) and continue.
        debugPrint('ReleaseRevision: manifest fetch skipped: $e');
      }
    } finally {
      _loading = false;
      _inflight = null;
    }
  }

  /// Test-only reset.
  @visibleForTesting
  static void reset() {
    _loading = false;
    _inflight = null;
  }
}