import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../controllers/audio_player_controller.dart';
import '../models/audio_series.dart';
import '../models/audio_track.dart';
import '../services/audio_catalog_service.dart';

/// Displays the tracks of an audio series.
class AudioSeriesScreen extends StatefulWidget {
  final String seriesId;
  final AudioSeries? initialSeries;

  const AudioSeriesScreen({
    super.key,
    required this.seriesId,
    this.initialSeries,
  });

  @override
  State<AudioSeriesScreen> createState() => _AudioSeriesScreenState();
}

class _AudioSeriesScreenState extends State<AudioSeriesScreen> {
  late final AudioCatalogService _catalogService;
  AudioSeries? _series;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _catalogService = AudioCatalogService();
    _series = widget.initialSeries;
    _loadSeries();
  }

  Future<void> _loadSeries() async {
    final series = await _catalogService.getSeries(widget.seriesId);
    if (mounted) {
      setState(() {
        if (series != null) _series = series;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);

    final series = _series;

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: tokens.background,
        elevation: 0,
        title: Text(
          series?.title ?? 'Series',
          style: theme.textTheme.titleMedium?.copyWith(
            color: tokens.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _isLoading && series == null
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // Header details
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cover Art
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 100,
                            height: 100,
                            color: tokens.surfaceVariant,
                            child: series?.coverUrl != null &&
                                    series!.coverUrl!.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: series.coverUrl!,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Icon(
                                      Icons.album,
                                      size: 40,
                                      color: theme.colorScheme.primary,
                                    ),
                                  )
                                : Icon(
                                    Icons.album,
                                    size: 40,
                                    color: theme.colorScheme.primary,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 16),

                        // Title & Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                series?.title ?? '',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: tokens.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${series?.speaker} • ${series?.trackCount ?? 0} Tracks',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: tokens.onSurfaceMuted,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                series?.description ?? '',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: tokens.onSurfaceMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Track list
                if (series != null)
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final track = series.tracks[index];
                        return _buildTrackTile(context, track, series.tracks, index);
                      },
                      childCount: series.tracks.length,
                    ),
                  ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: 100), // padding for mini-player
                ),
              ],
            ),
    );
  }

  Widget _buildTrackTile(
    BuildContext context,
    AudioTrack track,
    List<AudioTrack> allTracks,
    int index,
  ) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);

    return ListenableBuilder(
      listenable: AudioPlayerController.instance,
      builder: (context, _) {
        final state = AudioPlayerController.instance.state;
        final isCurrentTrack = state.currentTrack?.id == track.id;

        return ListTile(
          leading: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isCurrentTrack
                  ? theme.colorScheme.primary.withOpacity(0.15)
                  : tokens.surfaceVariant,
              shape: BoxShape.circle,
            ),
            child: isCurrentTrack && state.isPlaying
                ? Icon(
                    Icons.equalizer,
                    size: 18,
                    color: theme.colorScheme.primary,
                  )
                : Text(
                    '${index + 1}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isCurrentTrack
                          ? theme.colorScheme.primary
                          : tokens.onSurfaceMuted,
                    ),
                  ),
          ),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: isCurrentTrack ? FontWeight.bold : FontWeight.normal,
              color: isCurrentTrack
                  ? theme.colorScheme.primary
                  : tokens.onSurface,
            ),
          ),
          subtitle: Text(
            '${track.formattedDuration}${track.hasScripture ? " • ${track.scriptureRefText}" : ""}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.onSurfaceMuted,
            ),
          ),
          trailing: IconButton(
            icon: Icon(
              isCurrentTrack && state.isPlaying
                  ? Icons.pause_circle_outline
                  : Icons.play_circle_outline,
              color: isCurrentTrack
                  ? theme.colorScheme.primary
                  : tokens.onSurfaceMuted,
            ),
            onPressed: () {
              if (isCurrentTrack) {
                AudioPlayerController.instance.togglePlayPause();
              } else {
                AudioPlayerController.instance.playTrack(
                  track,
                  queue: allTracks,
                );
              }
            },
          ),
          onTap: () {
            AudioPlayerController.instance.playTrack(
              track,
              queue: allTracks,
            );
          },
        );
      },
    );
  }
}
