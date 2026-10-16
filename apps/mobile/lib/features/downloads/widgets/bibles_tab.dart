import 'package:flutter/material.dart';
import '../../../../core/layout/adaptivity.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../engines/scripture/models/bible_version_meta.dart';
import '../../engines/scripture/services/bible_download_manager.dart';
import '../../engines/scripture/widgets/bible_version_info_sheet.dart';
import '../controllers/downloads_controller.dart';

class BiblesTab extends StatefulWidget {
  final DownloadsController controller;

  const BiblesTab({
    super.key,
    required this.controller,
  });

  @override
  State<BiblesTab> createState() => _BiblesTabState();
}

class _BiblesTabState extends State<BiblesTab> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.controller.state.bibleSearch);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final itemExtent = (112.0 * textScale.clamp(1.0, 1.6)).toDouble();

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        var bibles = state.bibles.toList();

        // Language Filter
        if (state.bibleLanguageFilter != 'All') {
          bibles = bibles.where((b) {
            if (state.bibleLanguageFilter == 'English') {
              return b.language.toLowerCase() == 'english';
            }
            if (state.bibleLanguageFilter == 'Indian') {
              return [
                'tamil',
                'malayalam',
                'telugu',
                'kannada',
                'hindi'
              ].contains(b.language.toLowerCase());
            }
            if (state.bibleLanguageFilter == 'European') {
              return ![
                'english',
                'tamil',
                'malayalam',
                'telugu',
                'kannada',
                'hindi'
              ].contains(b.language.toLowerCase());
            }
            return true;
          }).toList();
        }

        // Search Filter
        if (state.bibleSearch.trim().isNotEmpty) {
          final q = state.bibleSearch.trim().toLowerCase();
          bibles = bibles
              .where((b) =>
                  b.name.toLowerCase().contains(q) ||
                  b.id.toLowerCase().contains(q) ||
                  b.language.toLowerCase().contains(q))
              .toList();
        }

        // Only Installed Filter
        if (state.onlyInstalled) {
          bibles = bibles
              .where((b) => widget.controller.isBibleInstalled(b.id))
              .toList();
        }

        final isWide = ScreenClass.of(context).isMediumOrExpanded;

        // Keep local search controller in sync if cleared externally
        if (_searchController.text != state.bibleSearch) {
          _searchController.value = TextEditingValue(
            text: state.bibleSearch,
            selection: TextSelection.collapsed(offset: state.bibleSearch.length),
          );
        }

        return MaxWidthBox(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // 1. Study Datasets Header
                    Text(
                      'STUDY DATASETS',
                      style: TextStyle(
                        color: tokens.onSurfaceMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Cross-References Card (Streamed On-Demand)
                    _buildCrossRefsCard(tokens),
                    const SizedBox(height: 10),

                    // Theological Concepts (Study DB)
                    _buildStudyDbCard(context, tokens),
                    const SizedBox(height: 24),

                    // 2. Translations Header & Controls
                    Row(
                      children: [
                        Text(
                          'BIBLE TRANSLATIONS',
                          style: TextStyle(
                            color: tokens.onSurfaceMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${bibles.length} Available',
                          style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 11.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Search Field
                    TextField(
                      controller: _searchController,
                      onChanged: widget.controller.setBibleSearch,
                      style: TextStyle(color: tokens.onSurface, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search translations, language, abbreviation…',
                        hintStyle: TextStyle(color: tokens.onSurfaceMuted, fontSize: 13),
                        prefixIcon: Icon(Icons.search, color: tokens.onSurfaceMuted, size: 20),
                        suffixIcon: state.bibleSearch.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear, color: tokens.onSurfaceMuted, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  widget.controller.setBibleSearch('');
                                },
                              )
                            : null,
                        isDense: true,
                        filled: true,
                        fillColor: tokens.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: tokens.surfaceBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: tokens.surfaceBorder),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Filter Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final opt in ['All', 'English', 'Indian', 'European'])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(opt),
                                selected: state.bibleLanguageFilter == opt,
                                onSelected: (_) => widget.controller.setBibleLanguageFilter(opt),
                                selectedColor: tokens.accent.withValues(alpha: 0.2),
                                checkmarkColor: tokens.accent,
                                labelStyle: TextStyle(
                                  fontSize: 12,
                                  color: state.bibleLanguageFilter == opt
                                      ? tokens.accent
                                      : tokens.onSurfaceMuted,
                                  fontWeight: state.bibleLanguageFilter == opt
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          FilterChip(
                            avatar: Icon(Icons.download_done_rounded,
                                size: 16,
                                color: state.onlyInstalled ? tokens.accent : tokens.onSurfaceMuted),
                            label: const Text('Downloaded Only'),
                            selected: state.onlyInstalled,
                            onSelected: (_) => widget.controller.toggleOnlyInstalled(),
                            selectedColor: tokens.accent.withValues(alpha: 0.2),
                            checkmarkColor: tokens.accent,
                            labelStyle: TextStyle(
                              fontSize: 12,
                              color: state.onlyInstalled ? tokens.accent : tokens.onSurfaceMuted,
                              fontWeight: state.onlyInstalled ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ]),
                ),
              ),

              // Empty state or Grid / List
              if (bibles.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off_rounded,
                              size: 48, color: tokens.onSurfaceMuted.withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          Text(
                            'No translations found',
                            style: TextStyle(
                                color: tokens.onSurface,
                                fontWeight: FontWeight.bold,
                                fontSize: 15),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Try adjusting your search query or language filter.',
                            style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () {
                              _searchController.clear();
                              widget.controller.setBibleSearch('');
                              widget.controller.setBibleLanguageFilter('All');
                              if (widget.controller.state.onlyInstalled) {
                                widget.controller.toggleOnlyInstalled();
                              }
                            },
                            child: const Text('Reset Filters'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (isWide)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: GridExtents.bibleManager,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      mainAxisExtent: itemExtent,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildBibleItem(context, bibles[index], tokens),
                      childCount: bibles.length,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildBibleItem(context, bibles[index], tokens),
                      ),
                      childCount: bibles.length,
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCrossRefsCard(AppTokens tokens) {
    return Container(
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
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: tokens.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.alt_route_rounded, color: tokens.accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Treasury of Scripture Knowledge Cross-References',
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '344,000+ bidirectional verse cross-references. Streamed on demand per chapter and cached in memory for zero storage impact.',
                  style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12, height: 1.35),
                ),
                const SizedBox(height: 6),
                Text(
                  'Status: Active (Streamed)',
                  style: TextStyle(color: tokens.accent, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudyDbCard(BuildContext context, AppTokens tokens) {
    final state = widget.controller.state;
    final isInstalled = state.studyDbInstalled;
    final isDownloading = state.isStudyDbDownloading;
    final progress = state.studyDbProgress;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isInstalled ? tokens.accent.withValues(alpha: 0.15) : tokens.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isInstalled ? Icons.check_circle : Icons.dataset_rounded,
                  color: isInstalled ? tokens.accent : tokens.onSurfaceMuted,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Words & Theological Concepts (Tamil OV)',
                      style: TextStyle(
                        color: tokens.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Study dataset for deep dive into Hebrew/Greek word meanings and concepts in the verse study sheet.',
                      style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12, height: 1.35),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Size: ~3.5 MB',
                      style: TextStyle(color: tokens.onSurfaceDisabled, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isInstalled) ...[
                IconButton(
                  icon: Icon(Icons.delete_outline, color: tokens.onSurfaceMuted, size: 20),
                  tooltip: 'Delete Study Database',
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete Study Database?'),
                        content: const Text('This offline study database will be removed from your device.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await widget.controller.deleteStudyDb();
                    }
                  },
                ),
              ] else if (isDownloading)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                    progress > 0 ? '${(progress * 100).toInt()}%' : 'Downloading…',
                    style: TextStyle(color: tokens.accent, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                )
              else
                FilledButton.tonal(
                  onPressed: () => widget.controller.downloadStudyDb(),
                  child: const Text('Download'),
                ),
            ],
          ),
          if (isDownloading) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                backgroundColor: tokens.surfaceVariant,
                color: tokens.accent,
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBibleItem(BuildContext context, BibleVersionMeta bible, AppTokens tokens) {
    final isInstalled = widget.controller.isBibleInstalled(bible.id);
    final isDownloading = widget.controller.isBibleDownloading(bible.id);
    final progress = widget.controller.getBibleProgress(bible.id);
    final isDefault = bible.id == BibleDownloadManager.defaultVersionId;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            bible.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                        if (isDefault) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: tokens.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'PROTECTED',
                              style: TextStyle(
                                color: tokens.accent,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${bible.language} • ${bible.id} • ${bible.sizeDisplay}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.info_outline, color: tokens.onSurfaceMuted, size: 18),
                tooltip: 'Version Details & License',
                onPressed: () => BibleVersionInfoSheet.show(context, bible),
              ),
              if (isDefault)
                Tooltip(
                  message: 'Protected base translation (cannot be deleted)',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.verified_user_rounded, color: tokens.accent, size: 20),
                  ),
                )
              else if (isInstalled)
                IconButton(
                  icon: Icon(Icons.delete_outline, color: tokens.onSurfaceMuted, size: 20),
                  tooltip: 'Delete Translation',
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text('Delete ${bible.name}?'),
                        content: const Text('This Bible translation will be removed from your device.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await widget.controller.deleteBible(bible.id);
                    }
                  },
                )
              else if (isDownloading)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Text(
                    (!widget.controller.isBibleIndeterminate(bible.id) && progress > 0)
                        ? '${(progress * 100).toInt()}%'
                        : 'Downloading…',
                    style: TextStyle(color: tokens.accent, fontWeight: FontWeight.bold, fontSize: 11.5),
                  ),
                )
              else
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => widget.controller.downloadBible(bible),
                  child: const Text('Download', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          if (isDownloading) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: widget.controller.isBibleIndeterminate(bible.id)
                    ? null
                    : (progress > 0 ? progress : null),
                backgroundColor: tokens.surfaceVariant,
                color: tokens.accent,
                minHeight: 3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
