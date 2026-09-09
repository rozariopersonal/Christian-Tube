import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/link/deep_link_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../controllers/audio_player_controller.dart';
import '../models/audio_track.dart';
import '../models/playback_state.dart';
import 'full_player_bible_cta.dart';
import 'full_player_controls.dart';
import 'full_player_cover_art.dart';
import 'full_player_error_banner.dart';
import 'full_player_scrubber.dart';
import 'full_player_utility_chips.dart';
import 'playback_queue_sheet.dart';
import 'sleep_timer_sheet.dart';

/// Full-screen adaptive modal audio player adhering to Material 3, the design
/// mockup, and repository adaptive standards (capping width at 640dp on wide
/// viewports). Thin assembler: sub-views live in dedicated widgets.
class FullAudioPlayerSheet extends StatefulWidget {
  const FullAudioPlayerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showAdaptiveBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const FullAudioPlayerSheet(),
    );
  }

  @override
  State<FullAudioPlayerSheet> createState() => _FullAudioPlayerSheetState();
}

class _FullAudioPlayerSheetState extends State<FullAudioPlayerSheet> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);

    return ListenableBuilder(
      listenable: AudioPlayerController.instance,
      builder: (context, _) {
        final state = AudioPlayerController.instance.state;
        final track = state.currentTrack;
        if (track == null) return const SizedBox.shrink();

        final hasPrevious =
            state.queueIndex > 0 || state.position.inSeconds > 5;
        final hasNext = state.queueIndex >= 0 &&
            state.queueIndex < state.queue.length - 1;

        return Container(
          height: MediaQuery.sizeOf(context).height * 0.94,
          decoration: BoxDecoration(
            color: tokens.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              _buildTopBar(context, theme, tokens, track),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      if (state.status == AudioPlaybackStatus.error)
                        FullPlayerErrorBanner(
                          message: state.errorMessage,
                          onRetry: () {
                            AudioPlayerController.instance.playTrack(
                              track,
                              queue: state.queue,
                              resumePositionSec: state.position.inSeconds,
                            );
                          },
                        ),

                      FullPlayerCoverArt(track: track),
                      const SizedBox(height: 24),

                      Text(
                        track.title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: tokens.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${track.speaker} • ${track.seriesTitle}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: tokens.onSurfaceMuted,
                        ),
                      ),
                      const SizedBox(height: 18),

                      FullPlayerScrubber(
                        value: state.progress,
                        duration: state.duration,
                        onScrub: (position) =>
                            AudioPlayerController.instance.seek(position),
                      ),
                      const SizedBox(height: 14),

                      FullPlayerControls(
                        state: state,
                        hasPrevious: hasPrevious,
                        hasNext: hasNext,
                      ),
                      const SizedBox(height: 16),

                      FullPlayerUtilityChips(
                        state: state,
                        onSleepTimer: () => showSleepTimerSheet(context),
                        onQueue: () => showPlaybackQueueSheet(context, state),
                      ),
                      const SizedBox(height: 24),

                      if (track.hasScripture)
                        FullPlayerBibleCta(track: track),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    ThemeData theme,
    AppTokens tokens,
    AudioTrack track,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, size: 28),
            color: tokens.onSurface,
            tooltip: 'Minimize Player',
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              track.seriesTitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                color: tokens.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: tokens.onSurface),
            tooltip: 'More options',
            color: tokens.surfaceElevated,
            onSelected: (value) {
              switch (value) {
                case 'share':
                  final link = DeepLinkService.audioSeries(track.seriesId);
                  Share.share(
                    'Listening to "${track.title}" by ${track.speaker}\n'
                    'Open in ChristianApp: $link',
                    subject: '${track.title} — ${track.seriesTitle}',
                  );
                  break;
                case 'sleep_timer':
                  showSleepTimerSheet(context);
                  break;
                case 'view_series':
                  Navigator.of(context).pop();
                  context.push('/audio/series/${track.seriesId}');
                  break;
              }
            },
            itemBuilder: (ctx) => [
              _menuItem(ctx, tokens, Icons.share_outlined, 'Share Sermon', 'share'),
              _menuItem(ctx, tokens, Icons.bedtime_outlined, 'Sleep Timer', 'sleep_timer'),
              _menuItem(ctx, tokens, Icons.folder_open_outlined, 'View Series', 'view_series'),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
    BuildContext ctx,
    AppTokens tokens,
    IconData icon,
    String label,
    String value,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: tokens.onSurface),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: tokens.onSurface)),
        ],
      ),
    );
  }
}