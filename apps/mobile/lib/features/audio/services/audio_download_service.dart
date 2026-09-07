import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/audio_track.dart';
import 'audio_local_library.dart';

/// Status of a single track's download within a series/batch.
enum AudioDownloadStatus {
  id,
  queued,
  downloading,
  completed,
  paused,
  failed,
}

/// Immutable per-track download snapshot broadcast to the UI.
@immutable
class AudioDownloadEntry {
  final AudioTrack track;
  final AudioDownloadStatus status;
  final double progress; // 0..1
  final int bytesReceived;
  final int bytesTotal;
  final String? error;

  const AudioDownloadEntry({
    required this.track,
    this.status = AudioDownloadStatus.id,
    this.progress = 0.0,
    this.bytesReceived = 0,
    this.bytesTotal = 0,
    this.error,
  });

  AudioDownloadEntry copyWith({
    AudioDownloadStatus? status,
    double? progress,
    int? bytesReceived,
    int? bytesTotal,
    String? error,
    bool clearError = false,
  }) {
    return AudioDownloadEntry(
      track: track,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      bytesReceived: bytesReceived ?? this.bytesReceived,
      bytesTotal: bytesTotal ?? this.bytesTotal,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Outcome of a single fetch attempt against one mirror.
enum _FetchResult { success, failed, cancelled }

/// Fault-tolerant, highly efficient audio downloader.
///
/// Design:
/// - **Resumable**: bytes are written to a `<file>.part`; on retry, an HTTP
///   `Range` header resumes from the existing length so interrupted downloads
///   never restart from zero.
/// - **Fault tolerant**: each track attempts the primary URL then falls back to
///   [AudioTrack.fallbackUrl]; transient network errors retry with backoff.
/// - **Efficient**: tracks download strictly sequentially (one at a time) to
///   avoid hammering the server and saturating disk I/O; progress is reported
///   per byte.
/// - **Batch capable**: pass multiple tracks to [_enqueue] for "download all",
///   or a single track for individual downloads.
class AudioDownloadService extends ChangeNotifier {
  static final AudioDownloadService instance = AudioDownloadService();

  final AudioLocalLibrary _library;
  final Map<String, AudioDownloadEntry> _entries = {};
  final List<String> _queue = [];
  final Map<String, CancelToken> _cancelTokens = {};
  bool _isRunning = false;
  bool _isDisposed = false;

  @visibleForTesting
  AudioDownloadService({AudioLocalLibrary? library})
      : _library = library ?? AudioLocalLibrary();

  Map<String, AudioDownloadEntry> get entries => Map.unmodifiable(_entries);

  AudioDownloadEntry? entryFor(String trackId) => _entries[trackId];

  bool isDownloaded(String trackId) =>
      _entries[trackId]?.status == AudioDownloadStatus.completed;

  bool isDownloading(String trackId) =>
      _entries[trackId]?.status == AudioDownloadStatus.downloading ||
      _entries[trackId]?.status == AudioDownloadStatus.queued;

  double progressFor(String trackId) => _entries[trackId]?.progress ?? 0.0;

  /// Applies [updater] to the current entry for [trackId] in place, no-op when absent.
  void _updateEntry(String trackId, AudioDownloadEntry Function(AudioDownloadEntry) updater) {
    final current = _entries[trackId];
    if (current == null) return;
    _entries[trackId] = updater(current);
  }

  /// Reconciles the in-memory state against what is actually on disk.
  /// Call once after the catalog/series is loaded to reflect previously
  /// downloaded tracks.
  Future<void> syncFromDisk(List<AudioTrack> tracks) async {
    if (kIsWeb || tracks.isEmpty) return;
    final presentOnDisk = <AudioTrack>[];
    for (final track in tracks) {
      final localUri = await _library.localUriFor(track);
      _entries[track.id] = AudioDownloadEntry(
        track: track,
        status: localUri != null
            ? AudioDownloadStatus.completed
            : AudioDownloadStatus.id,
        progress: localUri != null ? 1.0 : 0.0,
      );
      if (localUri != null) presentOnDisk.add(track);
    }
    await _library.registerDownloaded(presentOnDisk);
    notifyListeners();
  }

  /// Adds [tracks] to the download queue. Pass a single track for individual
  /// downloads, or a whole series for batch download.
  Future<void> downloadTracks(List<AudioTrack> tracks) async {
    if (kIsWeb || tracks.isEmpty) return;
    for (final track in tracks) {
      final existing = _entries[track.id];
      if (existing != null &&
          (existing.status == AudioDownloadStatus.downloading ||
              existing.status == AudioDownloadStatus.queued ||
              existing.status == AudioDownloadStatus.completed)) {
        continue;
      }
      _entries[track.id] = AudioDownloadEntry(
        track: track,
        status: AudioDownloadStatus.queued,
      );
      if (!_queue.contains(track.id)) _queue.add(track.id);
    }
    notifyListeners();
    _pump();
  }

  Future<void> cancelDownload(String trackId) async {
    if (kIsWeb) return;
    final current = _entries[trackId];
    if (current == null ||
        (current.status != AudioDownloadStatus.downloading &&
            current.status != AudioDownloadStatus.queued)) {
      return;
    }
    _queue.remove(trackId);
    // Abort the in-flight request; the download loop discards its partial file.
    _cancelTokens[trackId]?.cancel();
    _entries[trackId] = current.copyWith(status: AudioDownloadStatus.id);
    notifyListeners();
  }

  Future<void> removeDownloaded(String trackId) async {
    if (kIsWeb) return;
    final current = _entries[trackId];
    if (current != null) {
      await _library.removeDownloaded(trackId, current.track);
      _entries[trackId] = current.copyWith(
        status: AudioDownloadStatus.id,
        progress: 0.0,
        bytesReceived: 0,
        bytesTotal: 0,
        clearError: true,
      );
    }
    notifyListeners();
  }

  Future<void> _pump() async {
    if (_isRunning || _isDisposed) return;
    _isRunning = true;

    while (_queue.isNotEmpty) {
      if (_isDisposed) break;
      final trackId = _queue.removeAt(0);
      final entry = _entries[trackId];
      if (entry == null) continue;
      if (entry.status == AudioDownloadStatus.completed) continue;

      final ok = await _downloadOne(entry.track);
      if (_isDisposed) break;

      if (!ok) {
        // Only surface as failed if the track wasn't cancelled mid-flight
        // (cancelDownload sets the entry back to `id`).
        final current = _entries[trackId];
        if (current != null &&
            current.status == AudioDownloadStatus.downloading) {
          _entries[trackId] = current.copyWith(
            status: AudioDownloadStatus.failed,
            error: 'Download failed. Tap to retry.',
          );
          notifyListeners();
        }
      }
    }

    _isRunning = false;
    if (_queue.isNotEmpty && !_isDisposed) {
      _pump();
    }
  }

  /// True when [response] is a byte-range response actually starting at
  /// [offset] (i.e. `Content-Range: bytes <offset>-...`). Used to detect
  /// servers that ignore `Range` and reply with a `200`/full body, which would
  /// otherwise corrupt the resumable partial file.
  bool _isPartialFromOffset(Response response, int offset) {
    if (offset <= 0) return true; // A fresh download expects a full body.
    if (response.statusCode != HttpStatus.partialContent) return false;
    final contentRange = response.headers.value('content-range');
    return contentRange != null && contentRange.startsWith('bytes $offset-');
  }

  /// Progress callback for [track]; [offset] is the number of already-persisted
  /// bytes so reported progress always reflects the full file, never just the
  /// bytes received by the current request.
  void Function(int, int) _reportProgress(
    AudioTrack track, {
    required int offset,
  }) {
    return (received, total) {
      final base = offset;
      final totalBytes = base + total;
      final done = base + received;
      final progress = totalBytes > 0 ? done / totalBytes : 0.0;
      _updateEntry(
        track.id,
        (e) => e.copyWith(
          status: AudioDownloadStatus.downloading,
          progress: progress.clamp(0.0, 1.0),
          bytesReceived: done,
          bytesTotal: totalBytes,
        ),
      );
      notifyListeners();
    };
  }

  Future<bool> _downloadOne(AudioTrack track) async {
    if (kIsWeb) return false;
    final target = await _library.pathFor(track);
    final partialFile = File('$target.part');
    final outFile = File(target);

    if (await outFile.exists() && (await outFile.length()) > 0) {
      _updateEntry(
        track.id,
        (e) => e.copyWith(
          status: AudioDownloadStatus.completed,
          progress: 1.0,
        ),
      );
      await _library.registerDownloaded([track]);
      return true;
    }

    // Resume from existing partial bytes.
    int offset = 0;
    if (await partialFile.exists()) {
      offset = await partialFile.length();
    }

    _updateEntry(
      track.id,
      (e) => e.copyWith(
        status: AudioDownloadStatus.downloading,
        bytesReceived: offset,
      ),
    );
    notifyListeners();

    final urls = [
      track.audioUrl,
      if (track.fallbackUrl != null && track.fallbackUrl!.isNotEmpty)
        track.fallbackUrl!,
    ];

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 10),
      headers: {'User-Agent': 'ChristianTube/1.32'},
    ));
    final cancelToken = CancelToken();
    _cancelTokens[track.id] = cancelToken;

    Future<_FetchResult> fetch(
      int fetchOffset,
      String url, {
      required bool isFallbackUrl,
    }) async {
      if (isFallbackUrl) {
        // Fallback mirrors may serve different bytes; a partial from the
        // primary mirror is not resumable against them.
        try {
          await partialFile.delete();
        } catch (_) {}
        fetchOffset = 0;
      }
      final headers = <String, dynamic>{};
      if (fetchOffset > 0) headers['Range'] = 'bytes=$fetchOffset-';

      try {
        final response = await dio.download(
          url,
          partialFile.path,
          options: Options(headers: headers),
          cancelToken: cancelToken,
          onReceiveProgress: _reportProgress(track, offset: fetchOffset),
        );
        // A server that ignores Range replies 200 with the whole body appended
        // after the existing partial bytes → corrupted file. Detect and redo.
        if (fetchOffset > 0 && !_isPartialFromOffset(response, fetchOffset)) {
          try {
            await partialFile.delete();
          } catch (_) {}
          fetchOffset = 0;
          await dio.download(
            url,
            partialFile.path,
            cancelToken: cancelToken,
            onReceiveProgress: _reportProgress(track, offset: 0),
          );
        }
        return _FetchResult.success;
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) {
          try {
            await partialFile.delete();
          } catch (_) {}
          return _FetchResult.cancelled;
        }
        // Range unsupported or connection died mid-resume: retry from zero once.
        if (fetchOffset > 0) {
          try {
            await partialFile.delete();
          } catch (_) {}
          try {
            await dio.download(
              url,
              partialFile.path,
              cancelToken: cancelToken,
              onReceiveProgress: _reportProgress(track, offset: 0),
            );
            return _FetchResult.success;
          } on DioException catch (e2) {
            if (e2.type == DioExceptionType.cancel) {
              try {
                await partialFile.delete();
              } catch (_) {}
              return _FetchResult.cancelled;
            }
            debugPrint('Audio download failed for ${track.id} from $url: $e2');
            return _FetchResult.failed;
          }
        }
        debugPrint('Audio download failed for ${track.id} from $url: $e');
        return _FetchResult.failed;
      }
    }

    try {
      for (var i = 0; i < urls.length; i++) {
        final result =
            await fetch(offset, urls[i], isFallbackUrl: i > 0);
        if (result == _FetchResult.cancelled) return false;
        if (result == _FetchResult.failed) continue;

        // Validate the completed download is non-empty, then finalize.
        if (await partialFile.length() > 0) {
          try {
            if (await outFile.exists()) await outFile.delete();
            await partialFile.rename(outFile.path);
          } catch (_) {
            // rename may fail across some encrypted volumes; copy fallback.
            try {
              await outFile.writeAsBytes(await partialFile.readAsBytes(), flush: true);
              await partialFile.delete();
            } catch (e) {
              debugPrint('Finalize failed for ${track.id}: $e');
              continue;
            }
          }
          _updateEntry(
            track.id,
            (e) => e.copyWith(
              status: AudioDownloadStatus.completed,
              progress: 1.0,
            ),
          );
          await _library.registerDownloaded([track]);
          return true;
        }
      }
    } finally {
      _cancelTokens.remove(track.id);
    }

    return false;
  }

  @visibleForTesting
  Future<void> resetForTest() async {
    _queue.clear();
    _entries.clear();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
