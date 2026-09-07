import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../models/audio_track.dart';
import '../services/audio_download_service.dart';

/// Per-track download / download-progress / remove control. Hidden on web
/// where the block-file downloader is unavailable.
class AudioTrackDownloadControl extends StatelessWidget {
  final AudioTrack track;

  const AudioTrackDownloadControl({
    super.key,
    required this.track,
  });

  @override
  Widget build(BuildContext context) {
    // Downloads require a real file system; hide the affordance on web.
    if (kIsWeb) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);
    final downloadService = AudioDownloadService.instance;

    return ListenableBuilder(
      listenable: downloadService,
      builder: (context, _) {
        final entry = downloadService.entryFor(track.id);
        final status = entry?.status ?? AudioDownloadStatus.id;
        final progress = entry?.progress ?? 0.0;

        switch (status) {
          case AudioDownloadStatus.completed:
            // Downloaded: allow removal.
            return IconButton(
              icon: const Icon(Icons.download_done, size: 21),
              color: theme.colorScheme.primary,
              tooltip: 'Downloaded · Tap to remove',
              onPressed: () async {
                await downloadService.removeDownloaded(track.id);
              },
            );
          case AudioDownloadStatus.queued:
          case AudioDownloadStatus.downloading:
            // In progress: show a circular progress ring + cancel on tap.
            return IconButton(
              icon: SizedBox(
                width: 21,
                height: 21,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2.2,
                  color: theme.colorScheme.primary,
                ),
              ),
              tooltip: 'Downloading ${(progress * 100).round()}% · Tap to cancel',
              onPressed: () => downloadService.cancelDownload(track.id),
            );
          case AudioDownloadStatus.failed:
            return IconButton(
              icon: const Icon(Icons.error_outline, size: 21),
              color: theme.colorScheme.error,
              tooltip: 'Download failed · Tap to retry',
              onPressed: () => downloadService.downloadTracks([track]),
            );
          case AudioDownloadStatus.id:
          default:
            // Not downloaded: show cloud-download icon.
            return IconButton(
              icon: const Icon(Icons.download_outlined, size: 21),
              color: tokens.onSurfaceMuted,
              tooltip: 'Download for offline',
              onPressed: () => downloadService.downloadTracks([track]),
            );
        }
      },
    );
  }
}