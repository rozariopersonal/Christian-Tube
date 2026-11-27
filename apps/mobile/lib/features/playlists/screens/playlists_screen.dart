import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/models/playlist.dart';
import '../../../core/theme/app_tokens.dart';
import '../services/playlist_service.dart';

class PlaylistsScreen extends StatelessWidget {
  final PlaylistService? playlistService;

  const PlaylistsScreen({super.key, this.playlistService});

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

  Future<void> _showCreateDialog(BuildContext context) async {
    final result = await showDialog<({String title, String description})>(
      context: context,
      builder: (_) => const _PlaylistFormDialog(
        dialogTitle: 'New Playlist',
        confirmLabel: 'Create',
      ),
    );
    if (result == null) return;
    await _service.createPlaylist(
      result.title,
      description: result.description,
    );
    if (context.mounted) {
      _showSnack(context, 'Created "${result.title}"');
    }
  }

  Future<void> _showRenameDialog(BuildContext context, Playlist playlist) async {
    final result = await showDialog<({String title, String description})>(
      context: context,
      builder: (_) => _PlaylistFormDialog(
        dialogTitle: 'Rename Playlist',
        confirmLabel: 'Save',
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
      _showSnack(context, 'Renamed playlist to "${result.title}"');
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
      if (context.mounted) {
        _showSnack(context, 'Deleted "${playlist.title}"');
      }
    }
  }

  void _playAll(BuildContext context, Playlist playlist) {
    if (playlist.videos.isEmpty) return;
    final first = playlist.videos.first;
    context.push(
      '/watch/${first.id}',
      extra: {
        'video': first,
        'playlist': playlist.videos,
        'playlistTitle': playlist.title,
        'initialIndex': 0,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final service = _service;

    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final playlists = service.playlists;
        return Scaffold(
          backgroundColor: tokens.background,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: const Text(
              'Playlists',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'New Playlist',
                onPressed: () => _showCreateDialog(context),
              ),
            ],
          ),
          body: MaxWidthBox(
            child: playlists.isEmpty
                ? _buildEmptyState(context, theme, tokens)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: playlists.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: tokens.surfaceBorder),
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      return _PlaylistTile(
                        playlist: playlist,
                        onTap: () => context.push(
                          '/playlists/${playlist.id}',
                          extra: playlist,
                        ),
                        onPlayAll: playlist.videos.isNotEmpty
                            ? () => _playAll(context, playlist)
                            : null,
                        onRename: () => _showRenameDialog(context, playlist),
                        onDelete: () => _showDeleteDialog(context, playlist),
                      );
                    },
                  ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ThemeData theme,
    AppTokens tokens,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.playlist_play_rounded,
              size: 56,
              color: tokens.onSurfaceMuted,
            ),
            const SizedBox(height: 16),
            Text(
              'No playlists yet',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: tokens.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Organize your favorite sermons and teachings into personal playlists.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.onSurfaceMuted,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _showCreateDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Create Playlist'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;
  final VoidCallback? onPlayAll;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _PlaylistTile({
    required this.playlist,
    required this.onTap,
    this.onPlayAll,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final thumb = playlist.thumbnailUrl ??
        (playlist.videos.isNotEmpty ? playlist.videos.first.thumbnailUrl : null);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 80,
                height: 48,
                child: thumb != null && thumb.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: thumb,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _placeholderThumb(tokens),
                      )
                    : _placeholderThumb(tokens),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: tokens.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    playlist.videoCount == 1
                        ? '1 video'
                        : '${playlist.videoCount} videos',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.onSurfaceMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (onPlayAll != null)
              IconButton(
                icon: Icon(Icons.play_arrow_rounded, color: context.accent),
                tooltip: 'Play All',
                onPressed: onPlayAll,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 20, color: tokens.onSurfaceMuted),
              tooltip: 'Playlist options',
              onSelected: (action) {
                if (action == 'rename') onRename();
                if (action == 'delete') onDelete();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'rename',
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Rename'),
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
      ),
    );
  }

  Widget _placeholderThumb(AppTokens tokens) {
    return Container(
      color: tokens.surfaceVariant,
      child: Icon(
        Icons.playlist_play_rounded,
        color: tokens.onSurfaceMuted,
      ),
    );
  }
}

class _PlaylistFormDialog extends StatefulWidget {
  final String dialogTitle;
  final String confirmLabel;
  final String initialTitle;
  final String initialDescription;

  const _PlaylistFormDialog({
    required this.dialogTitle,
    required this.confirmLabel,
    this.initialTitle = '',
    this.initialDescription = '',
  });

  @override
  State<_PlaylistFormDialog> createState() => _PlaylistFormDialogState();
}

class _PlaylistFormDialogState extends State<_PlaylistFormDialog> {
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
      title: Text(widget.dialogTitle),
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
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
