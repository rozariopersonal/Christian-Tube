import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../models/audio_track.dart';
import '../services/audio_download_service.dart';

/// Per-track download / download-progress / remove control. Hidden on web
/// where the block-file downloader is unavailable.
class AudioTrackDownloadControl extends StatelessWidget {
  final AudioTrack track;
  final bool compact;

  const AudioTrackDownloadControl({
    super.key,
    required this.track,
    this.compact = false,
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

    final double iconSize = compact ? 17.0 : 21.0;
    final BoxConstraints? constraints = compact
        ? const BoxConstraints(minWidth: 26, minHeight: 26)
        : null;
    final EdgeInsetsGeometry padding = compact
        ? const EdgeInsets.all(2)
        : const EdgeInsets.all(8);

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
              icon: Icon(Icons.download_done, size: iconSize),
              color: theme.colorScheme.primary,
              constraints: constraints,
              padding: padding,
              visualDensity: compact ? VisualDensity.compact : null,
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
                width: iconSize,
                height: iconSize,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: compact ? 1.8 : 2.2,
                  color: theme.colorScheme.primary,
                ),
              ),
              constraints: constraints,
              padding: padding,
              visualDensity: compact ? VisualDensity.compact : null,
              tooltip: 'Downloading ${(progress * 100).round()}% · Tap to cancel',
              onPressed: () => downloadService.cancelDownload(track.id),
            );
          case AudioDownloadStatus.failed:
            return IconButton(
              icon: Icon(Icons.error_outline, size: iconSize),
              color: theme.colorScheme.error,
              constraints: constraints,
              padding: padding,
              visualDensity: compact ? VisualDensity.compact : null,
              tooltip: 'Download failed · Tap to retry',
              onPressed: () => downloadService.downloadTracks([track]),
            );
          case AudioDownloadStatus.id:
          default:
            // Not downloaded: show cloud-download icon.
            return IconButton(
              icon: Icon(Icons.download_outlined, size: iconSize),
              color: tokens.onSurfaceMuted,
              constraints: constraints,
              padding: padding,
              visualDensity: compact ? VisualDensity.compact : null,
              tooltip: 'Download for offline',
              onPressed: () => downloadService.downloadTracks([track]),
            );
        }
      },
    );
  }
}