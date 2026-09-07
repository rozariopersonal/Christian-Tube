import 'package:flutter/material.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../controllers/audio_player_controller.dart';
import '../controllers/audio_series_controller.dart';
import '../models/audio_series.dart';
import '../widgets/audio_series_header.dart';
import '../widgets/audio_track_list_tile.dart';

/// Displays the tracks of an audio series with "Play All", individual track
/// resume badges, live equalizers, and responsive layout constraints. Thin
/// assembler: all behavior lives in [AudioSeriesController], the sub-views are
/// presentational widgets.
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
  late final AudioSeriesController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AudioSeriesController(
      seriesId: widget.seriesId,
      initialSeries: widget.initialSeries,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final state = _controller.state;
        final series = state.series;

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
          body: state.isLoading && series == null
              ? const Center(child: CircularProgressIndicator())
              : MaxWidthBox(
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: AudioSeriesHeader(
                          series: series,
                          onPlayAll: series != null && series.tracks.isNotEmpty
                              ? () => AudioPlayerController.instance.playTrack(
                                    series.tracks.first,
                                    queue: series.tracks,
                                  )
                              : () {},
                        ),
                      ),

                      if (series != null)
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final track = series.tracks[index];
                              return AudioTrackListTile(
                                track: track,
                                index: index,
                                savedPositionSeconds:
                                    state.savedPositions[track.id] ?? 0,
                                queue: series.tracks,
                              );
                            },
                            childCount: series.tracks.length,
                          ),
                        ),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: 100),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}