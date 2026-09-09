import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../models/song.dart';

/// Horizontal songs shelf for the Library hub. Shows up to a fixed count of
/// songs as compact cards plus a "View all" entry point into the full browser.
class SongShelf extends StatelessWidget {
  final List<Song> songs;
  final VoidCallback onViewAll;
  final ValueChanged<Song> onTapSong;

  const SongShelf({
    super.key,
    required this.songs,
    required this.onViewAll,
    required this.onTapSong,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Row(
            children: [
              Flexible(
                child: Row(
                  children: [
                    Icon(Icons.music_note_rounded, color: tokens.accent, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Songs',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: tokens.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onViewAll,
                style: TextButton.styleFrom(
                  foregroundColor: tokens.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text('View all', style: theme.textTheme.labelMedium),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 132,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: SizedBox(
                  width: 220,
                  child: _SongShelfTile(
                    song: song,
                    tokens: tokens,
                    onTap: () => onTapSong(song),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SongShelfTile extends StatelessWidget {
  final Song song;
  final AppTokens tokens;
  final VoidCallback onTap;

  const _SongShelfTile({
    required this.song,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.surfaceBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.music_note_rounded, color: tokens.accent, size: 17),
              ),
              const Spacer(),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: tokens.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      song.author ?? song.collection ?? 'Song',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
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
    );
  }
}
