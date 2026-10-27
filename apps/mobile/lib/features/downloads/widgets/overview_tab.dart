import 'package:flutter/material.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../controllers/downloads_controller.dart';
import 'common/download_bundle_card.dart';

class OverviewTab extends StatelessWidget {
  final DownloadsController controller;
  final Function(int tabIndex) onNavigateToTab;

  const OverviewTab({
    super.key,
    required this.controller,
    required this.onNavigateToTab,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colorScheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.state;
        final storage = state.storage;

        return MaxWidthBox(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 1. Storage & Offline Readiness Dashboard
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [tokens.surface, tokens.surfaceElevated],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: tokens.surfaceBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: tokens.accent.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.offline_pin_rounded,
                            color: tokens.accent,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Offline Storage & Readiness',
                                style: TextStyle(
                                  color: tokens.onSurface,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${storage.totalFormatted} used for offline reading & listening.',
                                style: TextStyle(
                                  color: tokens.onSurfaceMuted,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.refresh, color: tokens.onSurfaceMuted),
                          tooltip: 'Recalculate Storage',
                          onPressed: controller.refreshAll,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    // Storage Proportion Bar
                    if (storage.totalBytes > 0) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          height: 8,
                          child: Row(
                            children: [
                              if (storage.biblesBytes > 0)
                                Expanded(
                                  flex: (storage.shareOf(storage.biblesBytes) * 100).toInt().clamp(1, 100),
                                  child: Container(color: colorScheme.primary),
                                ),
                              if (storage.dictionariesBytes > 0)
                                Expanded(
                                  flex: (storage.shareOf(storage.dictionariesBytes) * 100).toInt().clamp(1, 100),
                                  child: Container(color: colorScheme.secondary),
                                ),
                              if (storage.booksBytes > 0)
                                Expanded(
                                  flex: (storage.shareOf(storage.booksBytes) * 100).toInt().clamp(1, 100),
                                  child: Container(color: colorScheme.tertiary),
                                ),
                              if (storage.audioBytes > 0)
                                Expanded(
                                  flex: (storage.shareOf(storage.audioBytes) * 100).toInt().clamp(1, 100),
                                  child: Container(color: tokens.accent),
                                ),
                              if (storage.songsBytes > 0)
                                Expanded(
                                  flex: (storage.shareOf(storage.songsBytes) * 100).toInt().clamp(1, 100),
                                  child: Container(color: colorScheme.error.withValues(alpha: 0.8)),
                                ),
                              if (storage.fontsBytes > 0)
                                Expanded(
                                  flex: (storage.shareOf(storage.fontsBytes) * 100).toInt().clamp(1, 100),
                                  child: Container(color: colorScheme.outline),
                                ),
                              if (storage.studyDbBytes > 0)
                                Expanded(
                                  flex: (storage.shareOf(storage.studyDbBytes) * 100).toInt().clamp(1, 100),
                                  child: Container(color: colorScheme.inversePrimary),
                                ),
                              if (storage.articlesBytes > 0)
                                Expanded(
                                  flex: (storage.shareOf(storage.articlesBytes) * 100).toInt().clamp(1, 100),
                                  child: Container(color: colorScheme.primaryContainer),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Divider(color: tokens.surfaceBorder, height: 1),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _buildStatChip(
                          icon: Icons.menu_book_rounded,
                          label: '${storage.biblesCount} Bibles (${storage.biblesFormatted})',
                          isReady: storage.biblesCount > 0,
                          tokens: tokens,
                          onTap: () => onNavigateToTab(1),
                        ),
                        _buildStatChip(
                          icon: Icons.spellcheck_rounded,
                          label: '${storage.dictsCount} Dicts (${storage.dictionariesFormatted})',
                          isReady: storage.dictsCount > 0,
                          tokens: tokens,
                          onTap: () => onNavigateToTab(2),
                        ),
                        _buildStatChip(
                          icon: Icons.library_books_rounded,
                          label: '${storage.booksCount} Books (${storage.booksFormatted})',
                          isReady: storage.booksCount > 0 || state.booksBundleInstalled,
                          tokens: tokens,
                          onTap: () => onNavigateToTab(3),
                        ),
                        _buildStatChip(
                          icon: Icons.headphones_rounded,
                          label: '${storage.audioTracksCount} Audio (${storage.audioFormatted})',
                          isReady: storage.audioTracksCount > 0,
                          tokens: tokens,
                          onTap: () => onNavigateToTab(4),
                        ),
                        _buildStatChip(
                          icon: Icons.music_note_rounded,
                          label: storage.songsInstalled ? 'Songs (${storage.songsFormatted})' : 'Songs Offline',
                          isReady: storage.songsInstalled,
                          tokens: tokens,
                          onTap: () => onNavigateToTab(5),
                        ),
                        _buildStatChip(
                          icon: Icons.font_download_rounded,
                          label: '${storage.fontsCount} Fonts (${storage.fontsFormatted})',
                          isReady: storage.fontsCount > 0,
                          tokens: tokens,
                          onTap: () => onNavigateToTab(6),
                        ),
                        if (storage.studyDbBytes > 0 || state.studyDbInstalled)
                          _buildStatChip(
                            icon: Icons.hub_rounded,
                            label: 'Study DB (${storage.studyDbFormatted})',
                            isReady: true,
                            tokens: tokens,
                            onTap: () => onNavigateToTab(1),
                          ),
                        if (storage.articlesCount > 0)
                          _buildStatChip(
                            icon: Icons.article_rounded,
                            label: '${storage.articlesCount} Articles (${storage.articlesFormatted})',
                            isReady: true,
                            tokens: tokens,
                            onTap: () => onNavigateToTab(3),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 2. Core Study Essentials Bundle Card
              DownloadBundleCard(
                icon: Icons.stars_rounded,
                title: 'Core Study Essentials Bundle',
                description:
                    'Installs the foundational study package: Default Bible, Easton\'s 1897 Bible Dictionary, Strong\'s Concordance, and Complete Books & Commentaries (~15 MB total).',
                isDownloading: state.isCoreBundleDownloading,
                progress: state.coreBundleProgress > 0 ? state.coreBundleProgress : null,
                progressLabel: 'Downloading Bundle: ${(state.coreBundleProgress * 100).toInt()}%',
                actionWidget: FilledButton.icon(
                  onPressed: controller.downloadCoreBundle,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Download Core Study Bundle'),
                  style: FilledButton.styleFrom(
                    backgroundColor: tokens.accent,
                    foregroundColor: tokens.background,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 3. Quick Navigation Tiles
              _buildNavTile(
                title: 'Bible Translations & Study Tools',
                subtitle: 'English, Indian Languages, European translations, and word study concepts.',
                icon: Icons.menu_book_rounded,
                badge: '${storage.biblesCount} installed',
                tokens: tokens,
                onTap: () => onNavigateToTab(1),
              ),
              const SizedBox(height: 12),
              _buildNavTile(
                title: 'Offline Dictionaries (13 Available)',
                subtitle: 'Strong\'s Greek/Hebrew, Easton\'s Dictionary, Indian languages (Tamil, Telugu, Hindi) & global lexicons.',
                icon: Icons.spellcheck_rounded,
                badge: '${storage.dictsCount} installed',
                tokens: tokens,
                onTap: () => onNavigateToTab(2),
              ),
              const SizedBox(height: 12),
              _buildNavTile(
                title: 'Books & Verse Commentaries',
                subtitle: '181 books across 7 languages with pageless reading & verse commentaries in study.',
                icon: Icons.library_books_rounded,
                badge: state.booksBundleInstalled ? 'Full Library' : '${storage.booksCount} books',
                tokens: tokens,
                onTap: () => onNavigateToTab(3),
              ),
              const SizedBox(height: 12),
              _buildNavTile(
                title: 'Downloaded Audio Sermons',
                subtitle: 'Manage downloaded sermon tracks & series saved to disk for offline playback.',
                icon: Icons.headphones_rounded,
                badge: '${storage.audioTracksCount} tracks',
                tokens: tokens,
                onTap: () => onNavigateToTab(4),
              ),
              const SizedBox(height: 12),
              _buildNavTile(
                title: 'Songs & Hymnbook Catalog',
                subtitle: 'Offline FTS5 hymnbook database for instant title and lyrics search without internet.',
                icon: Icons.music_note_rounded,
                badge: storage.songsInstalled ? 'Installed' : 'Available',
                tokens: tokens,
                onTap: () => onNavigateToTab(5),
              ),
              const SizedBox(height: 12),
              _buildNavTile(
                title: 'Reader Fonts & Typography',
                subtitle: 'Offline long-form reading fonts and stylish card sharing fonts for all languages.',
                icon: Icons.font_download_rounded,
                badge: storage.fontsCount > 0 ? '${storage.fontsCount} fonts' : 'Available',
                tokens: tokens,
                onTap: () => onNavigateToTab(6),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required bool isReady,
    required AppTokens tokens,
    required VoidCallback onTap,
  }) {
    final color = isReady ? tokens.accent : tokens.onSurfaceMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isReady ? Icons.check_circle : icon, size: 15, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required String badge,
    required AppTokens tokens,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.surfaceBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: tokens.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: tokens.accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: tokens.onSurface,
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: tokens.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            color: tokens.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: tokens.onSurfaceMuted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: tokens.onSurfaceMuted, size: 20),
          ],
        ),
      ),
    );
  }
}
