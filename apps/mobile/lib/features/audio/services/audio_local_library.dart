import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/audio_track.dart';

/// Resolves and persists locally-downloaded audio files.
///
/// Audio files are stored under `downloads/audio/<seriesId>/<trackId>.<ext>`
/// in the application documents directory. A registry (SharedPreferences)
/// records which tracks are fully downloaded so the UI and playback layer can
/// prefer the local file over streaming without re-scanning the filesystem.
class AudioLocalLibrary {
  static const _registryKey = 'audio_downloaded_tracks_v1';
  static const _registrySeriesKey = 'audio_downloaded_series_v1';

  final Directory Function()? _overrideBaseDir;

  AudioLocalLibrary({Directory Function()? overrideBaseDir})
      : _overrideBaseDir = overrideBaseDir;

  Future<Directory> _baseDir() async {
    final override = _overrideBaseDir;
    if (override != null) return override();
    if (kIsWeb) throw UnsupportedError('Local audio downloads require a file system.');
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'downloads', 'audio'));
  }

  /// Collapses arbitrary catalog-provided segments into safe, single-directory
  /// names so a malformed `id`/`seriesId` cannot escape the downloads folder.
  static String _safeSegment(String input) =>
      input.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  Future<Directory> _seriesDir(String seriesId) async {
    final base = await _baseDir();
    final dir = Directory(p.join(base.path, _safeSegment(seriesId)));
    await dir.create(recursive: true);
    return dir;
  }

  /// Extension derived from the track's audio URL path (defaults to `mp3`).
  String _extensionFor(AudioTrack track) {
    try {
      final path = Uri.parse(track.audioUrl).path;
      final lastSegment = path.split('/').last;
      final dot = lastSegment.lastIndexOf('.');
      if (dot > 0 && dot < lastSegment.length - 1) {
        return lastSegment.substring(dot + 1).toLowerCase();
      }
    } catch (_) {}
    return 'mp3';
  }

  /// Full on-disk path where [track] should be (or is) stored.
  Future<String> pathFor(AudioTrack track) async {
    final dir = await _seriesDir(track.seriesId);
    final ext = _extensionFor(track);
    return p.join(dir.path, '${_safeSegment(track.id)}.$ext');
  }

  /// Absolute local file URI for [track], or null when unavailable/web.
  Future<String?> localUriFor(AudioTrack track) async {
    if (kIsWeb) return null;
    try {
      final file = File(await pathFor(track));
      if (await file.exists() && (await file.length()) > 0) {
        return file.uri.toString();
      }
    } catch (_) {}
    return null;
  }

  Future<bool> isDownloaded(String trackId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_registryKey) ?? []).contains(trackId);
  }

  Future<Set<String>> downloadedIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_registryKey) ?? []).toSet();
  }

  Future<Set<String>> downloadedSeriesIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_registrySeriesKey) ?? []).toSet();
  }

  /// Marks all [tracks]' series as having local copies and records each track id.
  Future<void> registerDownloaded(List<AudioTrack> tracks) async {
    if (tracks.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_registryKey) ?? [];
    final series = prefs.getStringList(_registrySeriesKey) ?? [];
    for (final t in tracks) {
      if (!ids.contains(t.id)) ids.add(t.id);
      if (t.seriesId.isNotEmpty && !series.contains(t.seriesId)) {
        series.add(t.seriesId);
      }
    }
    await prefs.setStringList(_registryKey, ids);
    await prefs.setStringList(_registrySeriesKey, series);
  }

  /// Removes a track from the registry and deletes its file from disk.
  Future<void> removeDownloaded(String trackId, AudioTrack track) async {
    final file = File(await pathFor(track));
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
    final temp = File('${file.path}.part');
    try {
      if (await temp.exists()) await temp.delete();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_registryKey) ?? [];
    ids.remove(trackId);
    await prefs.setStringList(_registryKey, ids);
  }
}
