import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/services/library_languages_controller.dart';
import '../../../shared/ui/language_dropdown.dart';
import '../controllers/songs_library_controller.dart';
import '../models/song_collection.dart';
import '../services/songs_catalog_service.dart';
import '../widgets/song_card.dart';

/// The unified songs browser: browse by album, author, or collection, filtered
/// by the shared library language selection.
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

  @override
  void initState() {
    super.initState();
    _controller = SongsLibraryController(
      service: widget.service,
      langController: widget.langController,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openSong(SongCollection collection, int index) {
    final song = collection.songs[index];
    context.push('/song/${song.id}', extra: song);
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
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: Text(
              'No songs found for the selected language.',
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 320,
                mainAxisExtent: 72,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => SongCard(
                  song: group.songs[i],
                  onTap: () => _openSong(group, i),
                ),
                childCount: group.songs.length,
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
