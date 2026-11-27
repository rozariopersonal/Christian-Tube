import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/audio_processor_models.dart';
import 'admin_audio_job_store.dart';
import 'admin_audio_processor_api.dart';

class AudioExtractionOutcome {
  final String status; // completed | short | skipped | failed
  final String? error;
  final bool isExtractorError;

  const AudioExtractionOutcome({
    required this.status,
    this.error,
    this.isExtractorError = false,
  });
}

bool _looksLikeShort(PendingAudioVideo video, int durationSec) {
  final lowerTitle = video.title.toLowerCase();
  if (lowerTitle.contains('#short') || lowerTitle.contains('#shorts')) {
    return true;
  }
  if (!video.isSongChannel && durationSec > 0 && durationSec <= 90) {
    return true;
  }
  return false;
}

bool _isPermanentYouTubeError(String errorText, DateTime publishedAt) {
  // Never mark a very recent (<6h) video dead; livestreams/premieres take
  // time for YouTube to finalize VOD M4A streams.
  if (DateTime.now().toUtc().difference(publishedAt.toUtc()).inHours < 6) {
    return false;
  }
  final lower = errorText.toLowerCase();
  const markers = [
    'video unavailable',
    'private video',
    'video has been removed',
    'age-restricted',
    'copyright',
    'does not exist',
  ];
  return markers.any(lower.contains);
}

Future<void> sweepOrphanedAudioTempFiles() async {
  try {
    final tmpDir = await getTemporaryDirectory();
    await for (final entity in tmpDir.list()) {
      if (entity is File && p.basename(entity.path).startsWith('yt_proc_')) {
        await entity.delete().catchError((_) => entity);
      }
    }
  } catch (_) {}
}

Future<AudioExtractionOutcome> extractAndUploadVideo({
  required PendingAudioVideo video,
  required AdminAudioProcessorApi api,
  required AdminAudioJobStore jobStore,
}) async {
  // 1. Check if a previous run already succeeded PUT and only needs /complete
  final prior = await jobStore.getByVideoId(video.id);
  if (prior != null &&
      prior.putSucceeded &&
      prior.uploadSessionId != null &&
      DateTime.now().toUtc().difference(prior.updatedAt.toUtc()).inMinutes < 25) {
    try {
      await api.completeUpload(
        uploadSessionId: prior.uploadSessionId!,
        durationSeconds: prior.durationSeconds ?? 0,
        bytesUploaded: prior.bytesUploaded ?? 0,
      );
      await jobStore.upsert(
        LocalAudioJobRecord(
          videoId: video.id,
          title: video.title,
          channelName: video.channelName,
          status: 'completed',
          uploadSessionId: prior.uploadSessionId,
          putSucceeded: true,
          bytesUploaded: prior.bytesUploaded,
          durationSeconds: prior.durationSeconds,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      return const AudioExtractionOutcome(status: 'completed');
    } catch (_) {
      // Session may have expired; fall through to fresh claim + upload.
    }
  }

  // 2. Claim lock on backend (409 -> another admin phone is handling it)
  final claimed = await api.claimVideo(video.id);
  if (!claimed) {
    return const AudioExtractionOutcome(status: 'skipped');
  }

  final yt = YoutubeExplode();
  File? tempFile;
  try {
    // 3. Fetch metadata & check for Shorts BEFORE downloading bytes
    final ytVideo = await yt.videos.get(video.id);
    final durationSec = ytVideo.duration?.inSeconds ?? 0;
    if (_looksLikeShort(video, durationSec)) {
      await api.markShort(video.id);
      await jobStore.upsert(
        LocalAudioJobRecord(
          videoId: video.id,
          title: video.title,
          channelName: video.channelName,
          status: 'short',
          durationSeconds: durationSec,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      return const AudioExtractionOutcome(status: 'short');
    }

    // 4. Pick highest-bitrate MP4 (M4A/AAC) audio-only stream (zero FFmpeg!)
    final manifest = await yt.videos.streamsClient.getManifest(video.id);
    final mp4Streams = manifest.audioOnly
        .where((s) => s.container == StreamContainer.mp4)
        .toList();
    if (mp4Streams.isEmpty) {
      const msg = 'M4A stream not ready yet (transient)';
      await api.reportFailure(videoId: video.id, error: msg, permanent: false);
      await jobStore.upsert(
        LocalAudioJobRecord(
          videoId: video.id,
          title: video.title,
          channelName: video.channelName,
          status: 'failed',
          error: msg,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      return const AudioExtractionOutcome(status: 'failed', error: msg);
    }

    mp4Streams.sort((a, b) => b.bitrate.compareTo(a.bitrate));
    final bestStream = mp4Streams.first;

    // 5. Stream audio to temp file on disk
    final tmpDir = await getTemporaryDirectory();
    tempFile = File(p.join(tmpDir.path, 'yt_proc_${video.id}.m4a'));
    final sink = tempFile.openWrite();
    try {
      await yt.videos.streamsClient.get(bestStream).pipe(sink);
    } finally {
      await sink.flush();
      await sink.close();
    }

    final fileSize = await tempFile.length();
    if (fileSize <= 0) {
      throw StateError('Downloaded M4A file was empty');
    }

    // 6. Request opaque upload-session from backend (AUDIO_COM_TOKEN stays server-side)
    final session = await api.createUploadSession(
      videoId: video.id,
      mime: 'audio/mp4',
      size: fileSize,
    );

    await jobStore.upsert(
      LocalAudioJobRecord(
        videoId: video.id,
        title: video.title,
        channelName: video.channelName,
        status: 'uploading',
        uploadSessionId: session.uploadSessionId,
        putSucceeded: false,
        bytesUploaded: fileSize,
        durationSeconds: durationSec,
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    // 7. Stream M4A directly from disk to Audio.com presigned URL (zero OOM risk)
    final uploadDio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(minutes: 10),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    await uploadDio.put(
      session.uploadUrl,
      data: tempFile.openRead(),
      options: Options(
        headers: {
          Headers.contentLengthHeader: fileSize,
          Headers.contentTypeHeader: 'audio/mp4',
        },
      ),
    );

    // Record PUT success immediately so a network blip before /complete won't re-upload
    await jobStore.upsert(
      LocalAudioJobRecord(
        videoId: video.id,
        title: video.title,
        channelName: video.channelName,
        status: 'finalizing',
        uploadSessionId: session.uploadSessionId,
        putSucceeded: true,
        bytesUploaded: fileSize,
        durationSeconds: durationSec,
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    // 8. Notify backend to confirm Audio.com hook & write to Neon
    await api.completeUpload(
      uploadSessionId: session.uploadSessionId,
      durationSeconds: durationSec,
      bytesUploaded: fileSize,
    );

    await jobStore.upsert(
      LocalAudioJobRecord(
        videoId: video.id,
        title: video.title,
        channelName: video.channelName,
        status: 'completed',
        uploadSessionId: session.uploadSessionId,
        putSucceeded: true,
        bytesUploaded: fileSize,
        durationSeconds: durationSec,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    return const AudioExtractionOutcome(status: 'completed');
  } catch (e) {
    final err = e.toString();
    final isExtractorErr = e is YoutubeExplodeException ||
        err.toLowerCase().contains('youtube') ||
        err.toLowerCase().contains('manifest');
    final permanent = _isPermanentYouTubeError(err, video.publishedAt);
    try {
      await api.reportFailure(
        videoId: video.id,
        error: err,
        permanent: permanent,
      );
    } catch (_) {}
    await jobStore.upsert(
      LocalAudioJobRecord(
        videoId: video.id,
        title: video.title,
        channelName: video.channelName,
        status: permanent ? 'dead' : 'failed',
        error: err,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    return AudioExtractionOutcome(
      status: 'failed',
      error: err,
      isExtractorError: isExtractorErr,
    );
  } finally {
    yt.close();
    if (tempFile != null && await tempFile.exists()) {
      await tempFile.delete().catchError((_) => tempFile!);
    }
  }
}
