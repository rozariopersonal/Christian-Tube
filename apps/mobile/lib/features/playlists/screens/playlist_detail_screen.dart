import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/models/playlist.dart';
import '../../../core/models/video.dart';
import '../../../core/theme/app_tokens.dart';
import '../services/playlist_service.dart';

class PlaylistDetailScreen extends StatelessWidget {
  final String playlistId;
  final Playlist? initialPlaylist;
  final PlaylistService? playlistService;

  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
    this.initialPlaylist,
    this.playlistService,
  });

  PlaylistService get _service => playlistService ?? PlaylistService.instance;

  void _showSnack(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openVideo(BuildContext context, Playlist playlist, int index) {
    final video = playlist.videos[index];
    context.push(
      '/watch/${video.id}',
      extra: {
        'video': video,
        'playlist': playlist.videos,
        'playlistTitle': playlist.title,
        'initialIndex': index,
      },
    );
  }

  Future<void> _removeVideo(
    BuildContext context,
    Playlist playlist,
    Video video,
  ) async {
    await _service.removeVideoFromPlaylist(playlist.id, video.id);
    if (context.mounted) {
      _showSnack(context, 'Removed from ${playlist.title}');
    }
  }

  Future<void> _showEditDialog(BuildContext context, Playlist playlist) async {
    final result = await showDialog<({String title, String description})>(
      context: context,
      builder: (_) => _EditPlaylistDialog(
        initialTitle: playlist.title,
        initialDescription: playlist.description ?? '',
      ),
    );
    if (result == null) return;
    await _service.updatePlaylist(
      playlist.id,
      title: result.title,
      description: result.description,
    );
    if (context.mounted) {
      _showSnack(context, 'Updated playlist');
    }
  }

  Future<void> _showDeleteDialog(BuildContext context, Playlist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Playlist'),
        content: Text('Delete "${playlist.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _service.deletePlaylist(playlist.id);
      if (!context.mounted) return;
      _showSnack(context, 'Deleted "${playlist.title}"');
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        try {
          context.go('/playlists');
        } catch (_) {}
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final service = _service;

    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final playlist = service.getById(playlistId) ?? initialPlaylist;
        if (playlist == null) {
          return Scaffold(
            backgroundColor: tokens.background,
            appBar: AppBar(
              automaticallyImplyLeading: false,
              title: const Text('Playlist'),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Playlist not found',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: tokens.onSurfaceMuted,
                  ),
                ),
              ),
            ),
          );
        }

        final videos = playlist.videos;
        return Scaffold(
          backgroundColor: tokens.background,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text(
              playlist.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                tooltip: 'Playlist options',
                onSelected: (action) {
                  if (action == 'edit') _showEditDialog(context, playlist);
                  if (action == 'delete') _showDeleteDialog(context, playlist);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('Delete'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: MaxWidthBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              videos.length == 1
                                  ? '1 video'
                                  : '${videos.length} videos',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: tokens.onSurfaceMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (playlist.description != null &&
                                playlist.description!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                playlist.description!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: tokens.onSurfaceMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (videos.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: () => _openVideo(context, playlist, 0),
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                          label: const Text('Play All'),
                        ),
                      ],
                    ],
                  ),
                ),
                Divider(height: 1, color: tokens.surfaceBorder),
                Expanded(
                  child: videos.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'No videos in this playlist yet.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: tokens.onSurfaceMuted,
                              ),
                            ),
                          ),
                        )
                      : ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: videos.length,
                          onReorder: (oldIndex, newIndex) {
                            final targetIndex =
                                oldIndex < newIndex ? newIndex - 1 : newIndex;
                            service.reorderVideos(
                              playlist.id,
                              oldIndex,
                              targetIndex,
                            );
                          },
                          itemBuilder: (context, index) {
                            final video = videos[index];
                            return _PlaylistVideoRow(
                              key: ValueKey(video.id),
                              index: index,
                              video: video,
                              onTap: () => _openVideo(context, playlist, index),
                              onRemove: () =>
                                  _removeVideo(context, playlist, video),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlaylistVideoRow extends StatelessWidget {
  final int index;
  final Video video;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _PlaylistVideoRow({
    super.key,
    required this.index,
    required this.video,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);

    return Material(
      color: tokens.background,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.drag_handle_rounded,
                    size: 20,
                    color: tokens.onSurfaceMuted,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 108,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CachedNetworkImage(
                      imageUrl: video.thumbnailUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        color: tokens.surfaceVariant,
                        child: Icon(
                          Icons.play_circle_outline,
                          color: tokens.onSurfaceDisabled,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: tokens.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      video.channelTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: tokens.onSurfaceMuted,
                ),
                tooltip: 'Remove from playlist',
                onPressed: onRemove,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditPlaylistDialog extends StatefulWidget {
  final String initialTitle;
  final String initialDescription;

  const _EditPlaylistDialog({
    required this.initialTitle,
    required this.initialDescription,
  });

  @override
  State<_EditPlaylistDialog> createState() => _EditPlaylistDialogState();
}

class _EditPlaylistDialogState extends State<_EditPlaylistDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initialTitle);
    _descCtrl = TextEditingController(text: widget.initialDescription);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Playlist'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final title = _titleCtrl.text.trim();
            if (title.isEmpty) return;
            Navigator.pop(
              context,
              (title: title, description: _descCtrl.text.trim()),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
