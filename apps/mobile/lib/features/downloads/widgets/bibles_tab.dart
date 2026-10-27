import 'package:flutter/material.dart';
import '../../../../core/layout/adaptivity.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../engines/scripture/models/bible_version_meta.dart';
import '../../engines/scripture/services/bible_download_manager.dart';
import '../../engines/scripture/widgets/bible_version_info_sheet.dart';
import '../controllers/downloads_controller.dart';
import 'common/download_action_button.dart';
import 'common/download_empty_state.dart';
import 'common/download_filter_bar.dart';
import 'common/download_item_tile.dart';

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
  bool _isMultiSelect = false;
  final Set<String> _selectedIds = {};
  String _sortBy = 'default';

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
    final itemExtent = (120.0 * textScale.clamp(1.0, 2.2)).toDouble();

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

        // Sorting
        if (_sortBy == 'name') {
          bibles.sort((a, b) => a.name.compareTo(b.name));
        } else if (_sortBy == 'installed') {
          bibles.sort((a, b) {
            final aInst = widget.controller.isBibleInstalled(a.id) ? 0 : 1;
            final bInst = widget.controller.isBibleInstalled(b.id) ? 0 : 1;
            return aInst.compareTo(bInst);
          });
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
          child: Stack(
            children: [
              CustomScrollView(
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
                              _isMultiSelect
                                  ? 'SELECT BIBLES (${_selectedIds.length})'
                                  : 'BIBLE TRANSLATIONS',
                              style: TextStyle(
                                color: tokens.onSurfaceMuted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const Spacer(),
                            PopupMenuButton<String>(
                              icon: Icon(Icons.sort_rounded, size: 18, color: tokens.onSurfaceMuted),
                              tooltip: 'Sort translations',
                              onSelected: (val) => setState(() => _sortBy = val),
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(value: 'default', child: Text('Default Order')),
                                const PopupMenuItem(value: 'name', child: Text('Name (A–Z)')),
                                const PopupMenuItem(value: 'installed', child: Text('Installed First')),
                              ],
                            ),
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _isMultiSelect = !_isMultiSelect;
                                  if (!_isMultiSelect) _selectedIds.clear();
                                });
                              },
                              icon: Icon(_isMultiSelect ? Icons.close : Icons.checklist_rounded, size: 16),
                              label: Text(_isMultiSelect ? 'Done' : 'Select'),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                foregroundColor: tokens.accent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Search & Language Filter Bar
                        DownloadFilterBar(
                          searchController: _searchController,
                          searchHint: 'Search translations, language, abbreviation…',
                          onSearchChanged: widget.controller.setBibleSearch,
                          categories: const ['All', 'English', 'Indian', 'European'],
                          selectedCategory: state.bibleLanguageFilter,
                          onCategorySelected: widget.controller.setBibleLanguageFilter,
                          onlyInstalled: state.onlyInstalled,
                          onToggleOnlyInstalled: widget.controller.toggleOnlyInstalled,
                        ),
                        const SizedBox(height: 14),
                      ]),
                    ),
                  ),

                  // Empty state or Grid / List
                  if (bibles.isEmpty)
                    SliverToBoxAdapter(
                      child: DownloadEmptyState(
                        title: 'No translations found',
                        subtitle: 'Try adjusting your search query or language filter.',
                        onResetFilters: () {
                          _searchController.clear();
                          widget.controller.setBibleSearch('');
                          widget.controller.setBibleLanguageFilter('All');
                          if (widget.controller.state.onlyInstalled) {
                            widget.controller.toggleOnlyInstalled();
                          }
                        },
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
                  if (_isMultiSelect && _selectedIds.isNotEmpty)
                    const SliverToBoxAdapter(child: SizedBox(height: 80))
                  else
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
              if (_isMultiSelect && _selectedIds.isNotEmpty)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: _buildBatchActionBar(tokens, bibles),
                ),
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
              if (isInstalled)
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
                )
              else if (isDownloading)
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

    return DownloadItemTile(
      leading: _isMultiSelect
          ? Checkbox(
              value: _selectedIds.contains(bible.id),
              activeColor: tokens.accent,
              checkColor: tokens.background,
              onChanged: (val) {
                setState(() {
                  if (val == true) {
                    _selectedIds.add(bible.id);
                  } else {
                    _selectedIds.remove(bible.id);
                  }
                });
              },
            )
          : null,
      onTap: _isMultiSelect
          ? () {
              setState(() {
                if (_selectedIds.contains(bible.id)) {
                  _selectedIds.remove(bible.id);
                } else {
                  _selectedIds.add(bible.id);
                }
              });
            }
          : null,
      title: bible.name,
      badgeText: isDefault ? 'PROTECTED' : null,
      subtitle: '${bible.language} • ${bible.id} • ${bible.sizeDisplay}',
      onInfo: () => BibleVersionInfoSheet.show(context, bible),
      isDownloading: isDownloading,
      downloadProgress: progress,
      isIndeterminate: widget.controller.isBibleIndeterminate(bible.id),
      trailing: bible.isOnlineOnly
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: tokens.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: tokens.surfaceBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_outlined, size: 14, color: tokens.onSurfaceMuted),
                  const SizedBox(width: 5),
                  Text(
                    'Online Only',
                    style: TextStyle(
                      color: tokens.onSurfaceMuted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          : DownloadActionButton(
              isInstalled: isInstalled,
              isDownloading: isDownloading,
              progress: progress,
              isIndeterminate: widget.controller.isBibleIndeterminate(bible.id),
              isProtected: isDefault,
              onDownload: () => widget.controller.downloadBible(bible),
              onDelete: () async {
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
            ),
    );
  }

  Widget _buildBatchActionBar(AppTokens tokens, List<BibleVersionMeta> bibles) {
    final selectedBibles = bibles.where((b) => _selectedIds.contains(b.id)).toList();
    final downloadable = selectedBibles.where((b) => !b.isOnlineOnly && !widget.controller.isBibleInstalled(b.id)).toList();
    final deletable = selectedBibles.where((b) => widget.controller.isBibleInstalled(b.id) && b.id != BibleDownloadManager.defaultVersionId).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.surfaceBorder),
        boxShadow: [
          BoxShadow(
            color: tokens.scrim.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_selectedIds.length} selected',
              style: TextStyle(
                color: tokens.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          if (downloadable.isNotEmpty)
            FilledButton.icon(
              onPressed: () async {
                final toDownload = List<BibleVersionMeta>.from(downloadable);
                setState(() {
                  _isMultiSelect = false;
                  _selectedIds.clear();
                });
                await widget.controller.batchDownloadBibles(toDownload);
              },
              icon: const Icon(Icons.download_rounded, size: 16),
              label: Text('Download (${downloadable.length})'),
              style: FilledButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: tokens.background,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          if (downloadable.isNotEmpty && deletable.isNotEmpty)
            const SizedBox(width: 8),
          if (deletable.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () async {
                final toDelete = deletable.map((b) => b.id).toList();
                setState(() {
                  _isMultiSelect = false;
                  _selectedIds.clear();
                });
                await widget.controller.batchDeleteBibles(toDelete);
              },
              icon: const Icon(Icons.delete_outline, size: 16),
              label: Text('Delete (${deletable.length})'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: tokens.onSurfaceMuted,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
        ],
      ),
    );
  }
}
