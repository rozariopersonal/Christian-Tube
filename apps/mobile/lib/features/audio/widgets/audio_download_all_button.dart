import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../models/audio_track.dart';
import '../services/audio_download_service.dart';

/// Header "Download All" button. Shows aggregate state across the series and
/// downloads any tracks that are not already downloaded locally. Hidden on web
/// where the block-file downloader is unavailable.
class AudioDownloadAllButton extends StatelessWidget {
  final List<AudioTrack> tracks;

  const AudioDownloadAllButton({
    super.key,
    required this.tracks,
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
        var running = 0;
        var completed = 0;
        var failed = 0;
        for (final track in tracks) {
          final entry = downloadService.entryFor(track.id);
          switch (entry?.status) {
            case AudioDownloadStatus.completed:
              completed++;
              break;
            case AudioDownloadStatus.queued:
            case AudioDownloadStatus.downloading:
              running++;
              break;
            case AudioDownloadStatus.failed:
              failed++;
              break;
            default:
              break;
          }
        }

        final allDownloaded = completed == tracks.length && tracks.isNotEmpty;
        final anyRunning = running > 0;
        final anyFailed = failed > 0;

        IconData icon;
        String label;
        Color? bg;
        if (allDownloaded) {
          icon = Icons.download_done;
          label = 'Downloaded';
          bg = theme.colorScheme.primary.withValues(alpha: 0.12);
        } else if (anyRunning) {
          icon = Icons.downloading;
          label = 'Downloading…';
          bg = theme.colorScheme.primary.withValues(alpha: 0.12);
        } else if (anyFailed) {
          icon = Icons.refresh;
          label = 'Retry ($completed done)';
          bg = theme.colorScheme.errorContainer.withValues(alpha: 0.5);
        } else {
          icon = Icons.download_outlined;
          label = 'Download All';
        }

        return OutlinedButton.icon(
          onPressed: allDownloaded || anyRunning
              ? null
              : () => downloadService.downloadTracks(tracks),
          style: OutlinedButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: tokens.onSurface,
          ),
          icon: Icon(icon, size: 20),
          label: Text(label),
        );
      },
    );
  }
}