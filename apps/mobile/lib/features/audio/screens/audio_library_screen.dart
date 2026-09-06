import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_tokens.dart';
import '../controllers/audio_player_controller.dart';
import '../models/audio_series.dart';
import '../models/audio_track.dart';
import '../services/audio_catalog_service.dart';
import '../services/audio_storage_service.dart';

/// Main Audio tab screen — browse sermon series, continue listening, and explore topics.
class AudioLibraryScreen extends StatefulWidget {
  const AudioLibraryScreen({super.key});

  @override
  State<AudioLibraryScreen> createState() => _AudioLibraryScreenState();
}

class _AudioLibraryScreenState extends State<AudioLibraryScreen> {
  final AudioCatalogService _catalogService = AudioCatalogService();
  final AudioStorageService _storageService = AudioStorageService();

  List<AudioSeries> _seriesList = [];
  AudioTrack? _lastPlayedTrack;
  int _lastPlayedSeconds = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final catalog = await _catalogService.getCatalog();
    final lastTrack = await _storageService.getLastTrack();
    int lastSec = 0;
    if (lastTrack != null) {
      lastSec = await _storageService.getPosition(lastTrack.id);
    }

    if (mounted) {
      setState(() {
        _seriesList = catalog;
        _lastPlayedTrack = lastTrack;
        _lastPlayedSeconds = lastSec;
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

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: tokens.background,
        elevation: 0,
        title: Text(
          'Audio Library',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: tokens.onSurface,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            color: tokens.onSurface,
            onPressed: () {},
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Chip(
              label: Text(
                'English',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.onSurface,
                ),
              ),
              backgroundColor: tokens.surfaceVariant,
              side: BorderSide.none,
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Featured Series Carousel
                    _buildSeriesCarousel(context, tokens, theme),
                    const SizedBox(height: 24),

                    // Continue Listening Card
                    if (_lastPlayedTrack != null)
                      _buildContinueListening(context, tokens, theme),

                    const SizedBox(height: 24),

                    // Topics Grid
                    _buildTopicsSection(context, tokens, theme),

                    // Space for persistent MiniPlayer
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSeriesCarousel(
    BuildContext context,
    AppTokens tokens,
    ThemeData theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Featured Series',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: tokens.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 220,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: _seriesList.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final series = _seriesList[index];
              return _buildSeriesCard(context, series, tokens, theme);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSeriesCard(
    BuildContext context,
    AudioSeries series,
    AppTokens tokens,
    ThemeData theme,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        context.push(
          '/audio/series/${series.id}',
          extra: series,
        );
      },
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 150,
                height: 150,
                color: tokens.surfaceVariant,
                child: series.coverUrl != null && series.coverUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: series.coverUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _buildCardFallback(theme),
                      )
                    : _buildCardFallback(theme),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              series.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: tokens.onSurface,
              ),
            ),
            Text(
              '${series.trackCount} Episodes',
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.onSurfaceMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardFallback(ThemeData theme) {
    return Center(
      child: Icon(
        Icons.headphones,
        size: 40,
        color: theme.colorScheme.primary,
      ),
    );
  }

  Widget _buildContinueListening(
    BuildContext context,
    AppTokens tokens,
    ThemeData theme,
  ) {
    final track = _lastPlayedTrack!;
    final progress = track.durationSeconds > 0
        ? (_lastPlayedSeconds / track.durationSeconds).clamp(0.0, 1.0)
        : 0.0;
    final percent = (progress * 100).round();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tokens.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tokens.surfaceBorder, width: 0.8),
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 54,
                height: 54,
                color: tokens.surfaceVariant,
                child: track.coverUrl != null && track.coverUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: track.coverUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Icon(
                          Icons.headphones,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : Icon(
                        Icons.headphones,
                        color: theme.colorScheme.primary,
                      ),
              ),
            ),
            const SizedBox(width: 14),

            // Track details & Progress
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Continue Listening',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tokens.onSurfaceMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: tokens.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      backgroundColor: tokens.surfaceVariant,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Resume Button
            FilledButton.tonal(
              onPressed: () {
                AudioPlayerController.instance.playTrack(
                  track,
                  resumePositionSec: _lastPlayedSeconds,
                );
              },
              child: Text(percent > 0 ? '$percent%' : 'Resume'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicsSection(
    BuildContext context,
    AppTokens tokens,
    ThemeData theme,
  ) {
    final topics = [
      {'title': 'Overcoming Sin', 'icon': Icons.shield_outlined},
      {'title': 'Holy Spirit', 'icon': Icons.local_fire_department_outlined},
      {'title': 'Family & Home', 'icon': Icons.home_outlined},
      {'title': 'Faith & Victory', 'icon': Icons.emoji_events_outlined},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Explore Topics',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: tokens.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: topics.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.2,
            ),
            itemBuilder: (context, index) {
              final topic = topics[index];
              return Material(
                color: tokens.surfaceElevated,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {},
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Icon(
                          topic['icon'] as IconData,
                          color: theme.colorScheme.primary,
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            topic['title'] as String,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: tokens.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
