import 'package:flutter/material.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/models/playlist.dart';
import '../../../core/models/video.dart';
import '../../../core/theme/app_tokens.dart';
import '../services/playlist_service.dart';
import '../services/watch_later_service.dart';

class SaveToPlaylistSheet extends StatefulWidget {
  final Video video;
  final WatchLaterService? watchLaterService;
  final PlaylistService? playlistService;

  const SaveToPlaylistSheet({
    super.key,
    required this.video,
    this.watchLaterService,
    this.playlistService,
  });

  static Future<void> show(
    BuildContext context, {
    required Video video,
    WatchLaterService? watchLaterService,
    PlaylistService? playlistService,
  }) {
    final tokens = context.tokens;
    return showAdaptiveBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SaveToPlaylistSheet(
        video: video,
        watchLaterService: watchLaterService,
        playlistService: playlistService,
      ),
    );
  }

  @override
  State<SaveToPlaylistSheet> createState() => _SaveToPlaylistSheetState();
}

class _SaveToPlaylistSheetState extends State<SaveToPlaylistSheet> {
  final TextEditingController _titleController = TextEditingController();
  bool _showNewForm = false;
  String? _statusMessage;

  WatchLaterService get _watchLater =>
      widget.watchLaterService ?? WatchLaterService.instance;
  PlaylistService get _playlists =>
      widget.playlistService ?? PlaylistService.instance;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    setState(() => _statusMessage = message);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _toggleWatchLater() async {
    final saved = await _watchLater.toggleWatchLater(widget.video);
    _showSnack(saved ? 'Saved to Watch Later' : 'Removed from Watch Later');
  }

  Future<void> _togglePlaylist(Playlist playlist, bool currentlyIn) async {
    if (currentlyIn) {
      await _playlists.removeVideoFromPlaylist(playlist.id, widget.video.id);
      _showSnack('Removed from ${playlist.title}');
    } else {
      await _playlists.addVideoToPlaylist(playlist.id, widget.video);
      _showSnack('Added to ${playlist.title}');
    }
  }

  Future<void> _createPlaylist() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    await _playlists.createPlaylist(title, initialVideo: widget.video);
    _titleController.clear();
    if (mounted) {
      setState(() => _showNewForm = false);
    }
    _showSnack('Created "$title" and added video');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge([_watchLater, _playlists]),
      builder: (context, _) {
        final inWatchLater = _watchLater.isWatchLater(widget.video.id);
        final allPlaylists = _playlists.playlists;

        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: tokens.onSurfaceDisabled.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Save video to...',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: tokens.onSurface,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _showNewForm = !_showNewForm),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('New Playlist'),
                    ),
                  ],
                ),
                if (_showNewForm) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _titleController,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _createPlaylist(),
                    decoration: const InputDecoration(
                      labelText: 'Playlist title',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          _titleController.clear();
                          setState(() => _showNewForm = false);
                        },
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _createPlaylist,
                        child: const Text('Create'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                if (_statusMessage != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: context.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline_rounded,
                          size: 16,
                          color: context.accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _statusMessage!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: tokens.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Divider(height: 1, color: tokens.surfaceBorder),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: inWatchLater,
                  onChanged: (_) => _toggleWatchLater(),
                  secondary: Icon(
                    inWatchLater
                        ? Icons.watch_later_rounded
                        : Icons.watch_later_outlined,
                    color: inWatchLater ? context.accent : tokens.onSurfaceMuted,
                  ),
                  title: Text(
                    'Watch Later',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: tokens.onSurface,
                    ),
                  ),
                ),
                if (allPlaylists.isNotEmpty) ...[
                  Divider(height: 1, color: tokens.surfaceBorder),
                  ...allPlaylists.map((playlist) {
                    final checked = playlist.videos
                        .any((v) => v.id == widget.video.id);
                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: checked,
                      onChanged: (_) => _togglePlaylist(playlist, checked),
                      secondary: Icon(
                        Icons.playlist_play_rounded,
                        color: checked ? context.accent : tokens.onSurfaceMuted,
                      ),
                      title: Text(
                        playlist.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: tokens.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        playlist.videoCount == 1
                            ? '1 video'
                            : '${playlist.videoCount} videos',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.onSurfaceMuted,
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
