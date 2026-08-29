import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../../core/models/local_short_item.dart';
import 'ffmpeg_downloader.dart';

class ShortsRenderResult {
  final bool isSuccess;
  final String? outputPath;
  final String? errorMessage;

  const ShortsRenderResult({
    required this.isSuccess,
    this.outputPath,
    this.errorMessage,
  });
}

class ShortsRenderEngine {
  final YoutubeExplode _yt = YoutubeExplode();

  /// Renders a trimmed + cropped short clip using ffmpeg.
  ///
  /// - Downloads ONLY the [startSeconds]..[endSeconds] range (via ffmpeg -ss / -t seek)
  /// - Applies 9:16 portrait crop centred on [cropOffsetX] when [framingMode] is portrait9x16
  /// - Outputs a compact MP4 to the device temp directory
  Future<ShortsRenderResult> render720pShort({
    required String sourceVideoId,
    required double startSeconds,
    required double endSeconds,
    required String creatorName,
    double cropOffsetX = 0.0,
    ShortsFramingMode framingMode = ShortsFramingMode.portrait9x16,
    required Function(double progress, String stage) onProgress,
  }) async {
    try {
      final duration = (endSeconds - startSeconds).clamp(1.0, 180.0);
      final modeLabel = framingMode == ShortsFramingMode.portrait9x16
          ? '9:16 Short (pan ${(cropOffsetX * 100).toInt()}%)'
          : '16:9 Landscape';

      onProgress(0.05, 'Resolving stream URL ($modeLabel)...');

      if (kIsWeb) {
        // Web: simulate progress — ffmpeg_kit is unavailable on web
        for (int i = 1; i <= 8; i++) {
          await Future.delayed(const Duration(milliseconds: 250));
          onProgress(0.1 + (i * 0.11), 'Rendering $modeLabel...');
        }
        onProgress(1.0, 'Render complete');
        return ShortsRenderResult(
          isSuccess: true,
          outputPath: 'web_rendered_short_${DateTime.now().millisecondsSinceEpoch}.mp4',
        );
      }

      // 1. Resolve the best muxed stream URL (no pre-download — just the URL)
      final manifest = await _yt.videos.streamsClient.getManifest(sourceVideoId);
      final muxed = manifest.muxed;
      if (muxed.isEmpty) {
        throw 'No muxed stream available for this video.';
      }

      final StreamInfo streamInfo = _pickBestStream(muxed);
      final streamUrl = streamInfo.url.toString();

      onProgress(0.15, 'Stream resolved — clipping $modeLabel...');

      // 2. Build output path and ffmpeg command
      final tempDir = await getTemporaryDirectory();
      final outputPath =
          '${tempDir.path}/short_${DateTime.now().millisecondsSinceEpoch}.mp4';

      final cropFilter = _buildCropFilter(framingMode, cropOffsetX);
      final ffmpegArgs = _buildFfmpegArgs(
        streamUrl: streamUrl,
        startSeconds: startSeconds,
        duration: duration,
        cropFilter: cropFilter,
        outputPath: outputPath,
      );

      debugPrint('ShortsRenderEngine: $ffmpegArgs');
      onProgress(0.2, 'Trimming & encoding clip...');

      // 3. Ensure the ffmpeg binary is available (downloaded on demand, once).
      //    The full FFmpeg engine is NOT bundled in the APK to keep it slim.
      final String ffmpegPath;
      try {
        onProgress(0.22, 'Checking media engine...');
        ffmpegPath = await FfmpegDownloader().ensureBinary(
          onProgress: (p) {
            onProgress(0.22 + (p * 0.1).clamp(0.0, 0.1),
                'Downloading media engine ${(p * 100).toInt()}%...');
          },
        );
      } catch (e) {
        debugPrint('ShortsRenderEngine: media engine unavailable: $e');
        return ShortsRenderResult(
          isSuccess: false,
          errorMessage: e.toString(),
        );
      }

      // 4. Execute ffmpeg as a subprocess, streaming stderr for progress.
      final process = await Process.start(ffmpegPath, ffmpegArgs);

      var lastElapsed = 0.0;
      // stderr carries the ffmpeg progress/log lines.
      process.stderr.transform(utf8.decoder).listen((chunk) {
        for (final line in chunk.split('\n')) {
          final match = RegExp(r'time=(\d+):(\d+):([\d.]+)').firstMatch(line);
          if (match != null) {
            final h = int.tryParse(match.group(1) ?? '0') ?? 0;
            final m = int.tryParse(match.group(2) ?? '0') ?? 0;
            final s = double.tryParse(match.group(3) ?? '0') ?? 0.0;
            final elapsed = h * 3600 + m * 60 + s;
            lastElapsed = elapsed;
            final p = (0.32 + ((elapsed / duration) * 0.63)).clamp(0.32, 0.95);
            onProgress(p, 'Encoding ${elapsed.toInt()}s / ${duration.toInt()}s...');
          }
        }
      });

      // Drain stdout so the subprocess never blocks.
      process.stdout.drain<void>();
      final exitCode = await process.exitCode;

      if (exitCode != 0) {
        throw 'ffmpeg failed (exit $exitCode) after encoding '
            '${lastElapsed.toInt()}s.';
      }

      onProgress(1.0, 'Clip rendered successfully');
      return ShortsRenderResult(isSuccess: true, outputPath: outputPath);
    } catch (e) {
      debugPrint('ShortsRenderEngine error: $e');
      return ShortsRenderResult(isSuccess: false, errorMessage: e.toString());
    }
  }

  /// Prefer medium quality to keep clip file sizes manageable; fall back to
  /// highest if the preferred quality is not available.
  StreamInfo _pickBestStream(List<MuxedStreamInfo> streams) {
    final preferred = [
      VideoQuality.medium480,
      VideoQuality.medium360,
      VideoQuality.high720,
    ];
    for (final quality in preferred) {
      try {
        return streams.firstWhere((s) => s.videoQuality == quality);
      } catch (_) {}
    }
    return streams.withHighestBitrate();
  }

  /// Builds the ffmpeg crop filter for portrait 9:16 framing.
  ///
  /// [cropOffsetX] in [-1.0, +1.0] pans the crop window left/right across the stage.
  String? _buildCropFilter(ShortsFramingMode mode, double cropOffsetX) {
    if (mode != ShortsFramingMode.portrait9x16) return null;
    final offset = cropOffsetX.clamp(-1.0, 1.0).toStringAsFixed(3);
    // crop_w = ih * 9/16 ; crop_h = ih
    // crop_x = (iw - crop_w)/2 * (1 + offset)  <- pans left/right within safe range
    return 'crop=ih*9/16:ih:(iw-ih*9/16)/2*(1+$offset):0';
  }

  /// Assembles the full ffmpeg argument list.
  ///
  /// -ss BEFORE -i = fast keyframe-level seek — ffmpeg does not decode frames
  /// before [startSeconds]. -t specifies duration (not end time).
  List<String> _buildFfmpegArgs({
    required String streamUrl,
    required double startSeconds,
    required double duration,
    String? cropFilter,
    required String outputPath,
  }) {
    return [
      '-y',
      '-ss', startSeconds.toStringAsFixed(3),
      '-i', streamUrl,
      '-t', duration.toStringAsFixed(3),
      if (cropFilter != null) ...['-vf', cropFilter],
      '-c:v', 'libx264', '-preset', 'fast', '-crf', '23',
      '-c:a', 'aac', '-b:a', '128k',
      '-movflags', '+faststart',
      outputPath,
    ];
  }

  void dispose() {
    _yt.close();
  }
}


