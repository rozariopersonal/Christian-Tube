import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/services/library_languages_controller.dart';
import '../../../shared/ui/language_dropdown.dart';
import '../controllers/songs_library_controller.dart';
import '../models/song_collection.dart';
import '../services/songs_catalog_service.dart';
import '../services/songs_download_manager.dart';
import '../widgets/song_card.dart';

/// The unified songs browser: browse by album, author, or collection, filtered
/// by the shared library language selection. On native platforms an optional
/// offline SQLite package can be downloaded via the AppBar action.
class SongsLibraryScreen extends StatefulWidget {
  final SongsCatalogService? service;
  final LibraryLanguagesController? langController;

  const SongsLibraryScreen({
    super.key,
    this.service,
    this.langController,
  });

  @override
  State<SongsLibraryScreen> createState() => _SongsLibraryScreenState();
}

class _SongsLibraryScreenState extends State<SongsLibraryScreen> {
  late final SongsLibraryController _controller;
  final TextEditingController _searchController = TextEditingController();
  final SongsDownloadManager _downloadManager = SongsDownloadManager();

  @override
  void initState() {
    super.initState();
    _controller = SongsLibraryController(
      service: widget.service,
      langController: widget.langController,
    );
    unawaited(_downloadManager.initialize());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _openSong(SongCollection collection, int index) {
    final song = collection.songs[index];
    context.push('/song/${song.id}', extra: song);
  }

  /// AppBar control for the optional offline songs package: shows a progress
  /// spinner while downloading, an offline-ready badge once installed, and a
  /// download button otherwise. Hidden on web (no sqflite there).
  Widget _buildOfflineAction() {
    return ListenableBuilder(
      listenable: _downloadManager,
      builder: (context, _) {
        final tokens = context.tokens;
        if (_downloadManager.isDownloading) {
          return Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                value: _downloadManager.downloadProgress > 0
                    ? _downloadManager.downloadProgress
                    : null,
                color: tokens.accent,
              ),
            ),
          );
        }
        if (_downloadManager.isInstalled) {
          return IconButton(
            icon: Icon(Icons.offline_pin_rounded, color: tokens.accent),
            tooltip: 'Songs saved for offline — tap to remove',
            onPressed: () => _onRemoveOffline(context),
          );
        }
        return IconButton(
          icon: Icon(Icons.download_outlined, color: tokens.onSurfaceMuted),
          tooltip: 'Download songs for offline use',
          onPressed: () => _onDownloadOffline(context),
        );
      },
    );
  }

  Future<void> _onDownloadOffline(BuildContext context) async {
    final ok = await _downloadManager.download();
    if (!mounted) return;
    if (ok) {
      await _controller.load(forceRefresh: false);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not download songs. Check your connection and try again.',
          ),
        ),
      );
    }
  }

  Future<void> _onRemoveOffline(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.tokens.surface,
        title: Text(
          'Remove offline songs?',
          style: TextStyle(color: context.tokens.onSurface),
        ),
        content: Text(
          'Songs will stream from the internet again.',
          style: TextStyle(color: context.tokens.onSurfaceMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.tokens.onSurface),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: context.tokens.accent),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _downloadManager.delete();
    await _controller.load(forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final state = _controller.state;
        final tokens = context.tokens;
        return Scaffold(
          backgroundColor: tokens.background,
          appBar: AppBar(
            backgroundColor: tokens.background,
            elevation: 0,
            title: Text(
              'Songs',
              style: TextStyle(color: tokens.onSurface, fontWeight: FontWeight.bold),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.refresh, color: tokens.onSurfaceMuted, size: 21),
                tooltip: 'Refresh songs',
                onPressed: () => _controller.load(forceRefresh: true),
              ),
              if (!kIsWeb) _buildOfflineAction(),
            ],
          ),
          body: MaxWidthBox(
            maxWidth: 1080,
            child: state.isLoading
                ? Center(
                    child: CircularProgressIndicator(color: tokens.accent),
                  )
                : RefreshIndicator(
                    onRefresh: () => _controller.load(forceRefresh: true),
                    color: tokens.accent,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: _buildSearchField(tokens),
                        ),
                        SliverToBoxAdapter(
                          child: _buildLanguageFilter(tokens),
                        ),
                        SliverToBoxAdapter(
                          child: _buildSegmentControl(tokens),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          sliver: _buildGroupList(tokens),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildSearchField(AppTokens tokens) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: TextField(
        controller: _searchController,
        onChanged: _controller.setSearchQuery,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search songs, authors, lyrics…',
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            color: tokens.onSurfaceMuted,
          ),
          prefixIcon: Icon(Icons.search, color: tokens.onSurfaceMuted),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _searchController,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: Icon(Icons.clear, color: tokens.onSurfaceMuted),
                tooltip: 'Clear search',
                onPressed: () {
                  _searchController.clear();
                  _controller.setSearchQuery('');
                },
              );
            },
          ),
          filled: true,
          fillColor: tokens.surfaceVariant,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageFilter(AppTokens tokens) {
    final langState = _controller.languageController.state;
    if (langState.availableLanguages.length <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: LanguageDropdown(
        selectedLanguages: langState.selectedLanguages,
        availableLanguages: langState.availableLanguages,
        itemCounts: _controller.languageCounts,
        onLanguagesSelected: _controller.languageController.selectLanguages,
        itemNoun: 'songs',
        headerTitle: 'Songs by Language',
      ),
    );
  }

  Widget _buildSegmentControl(AppTokens tokens) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: SegmentedButton<SongGroupMode>(
        segments: const [
          ButtonSegment(
            value: SongGroupMode.albums,
            label: Text('Albums'),
            icon: Icon(Icons.album_outlined),
          ),
          ButtonSegment(
            value: SongGroupMode.authors,
            label: Text('Authors'),
            icon: Icon(Icons.person_outline),
          ),
          ButtonSegment(
            value: SongGroupMode.collections,
            label: Text('Collections'),
            icon: Icon(Icons.library_music_outlined),
          ),
        ],
        selected: {_controller.state.groupMode},
        onSelectionChanged: (sel) =>
            _controller.setGroupMode(sel.first),
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? tokens.accent
                  : tokens.onSurface),
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? tokens.accent.withValues(alpha: 0.12)
                  : tokens.surfaceVariant),
        ),
      ),
    );
  }

  Widget _buildGroupList(AppTokens tokens) {
    final groups = _controller.groupedSongs;
    if (groups.isEmpty) {
      final query = _controller.state.query;
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: Text(
              query.isNotEmpty
                  ? 'No songs found for "$query".'
                  : 'No songs found for the selected language.',
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.onSurfaceMuted),
            ),
          ),
        ),
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        for (final group in groups) ...[
          _buildGroupHeader(tokens, group),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            sliver: SliverList.builder(
              itemCount: group.songs.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SongCard(
                  song: group.songs[i],
                  onTap: () => _openSong(group, i),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGroupHeader(AppTokens tokens, SongCollection group) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              group.label,
              style: TextStyle(
                color: tokens.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            if (group.subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  group.subtitle!,
                  style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
