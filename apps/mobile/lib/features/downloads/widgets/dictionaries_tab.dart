import 'package:flutter/material.dart';
import '../../../../core/layout/adaptivity.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../dictionary/services/dictionary_download_manager.dart';
import '../controllers/downloads_controller.dart';
import 'common/download_action_button.dart';
import 'common/download_empty_state.dart';
import 'common/download_filter_bar.dart';
import 'common/download_item_tile.dart';

class DictionariesTab extends StatefulWidget {
  final DownloadsController controller;

  const DictionariesTab({
    super.key,
    required this.controller,
  });

  @override
  State<DictionariesTab> createState() => _DictionariesTabState();
}

class _DictionariesTabState extends State<DictionariesTab> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.controller.state.dictSearch);
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
    final itemExtent = (150.0 * textScale.clamp(1.0, 2.2)).toDouble();

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        var dicts = state.dictionaries.toList();

        // Category Filter
        if (state.dictFilter == 'Biblical') {
          dicts = dicts.where((d) => d.isBiblical).toList();
        } else if (state.dictFilter == 'Indian') {
          dicts = dicts
              .where((d) => ['ta', 'ml', 'te', 'kn', 'hi'].contains(d.id))
              .toList();
        } else if (state.dictFilter == 'Global') {
          dicts = dicts
              .where((d) =>
                  !d.isBiblical &&
                  !['ta', 'ml', 'te', 'kn', 'hi'].contains(d.id))
              .toList();
        }

        // Search Filter
        if (state.dictSearch.trim().isNotEmpty) {
          final q = state.dictSearch.trim().toLowerCase();
          dicts = dicts
              .where((d) =>
                  d.name.toLowerCase().contains(q) ||
                  d.language.toLowerCase().contains(q) ||
                  d.description.toLowerCase().contains(q))
              .toList();
        }

        // Installed Only Filter
        if (state.onlyInstalled) {
          dicts = dicts
              .where((d) => widget.controller.isDictInstalled(d.id))
              .toList();
        }

        final isWide = ScreenClass.of(context).isMediumOrExpanded;

        // Keep local search controller in sync if cleared externally
        if (_searchController.text != state.dictSearch) {
          _searchController.value = TextEditingValue(
            text: state.dictSearch,
            selection: TextSelection.collapsed(offset: state.dictSearch.length),
          );
        }

        return MaxWidthBox(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // 1. Explanatory Banner
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: tokens.surfaceVariant,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: tokens.surfaceBorder),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.spellcheck_rounded, color: tokens.accent, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Installed dictionaries power instant "Define" popovers in both the Bible Reader and Book Reader without an internet connection.',
                              style: TextStyle(
                                color: tokens.onSurface,
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 2. Search & Category Filter Bar
                    DownloadFilterBar(
                      searchController: _searchController,
                      searchHint: 'Search dictionaries by language or name…',
                      onSearchChanged: widget.controller.setDictSearch,
                      categories: const ['All', 'Biblical', 'Indian', 'Global'],
                      selectedCategory: state.dictFilter,
                      onCategorySelected: widget.controller.setDictFilter,
                      onlyInstalled: state.onlyInstalled,
                      onToggleOnlyInstalled: widget.controller.toggleOnlyInstalled,
                    ),
                    const SizedBox(height: 14),
                  ]),
                ),
              ),

              // Empty state or Dictionaries Grid / List
              if (dicts.isEmpty)
                SliverToBoxAdapter(
                  child: DownloadEmptyState(
                    title: 'No dictionaries found',
                    subtitle: 'Try adjusting your search query or category filter.',
                    onResetFilters: () {
                      _searchController.clear();
                      widget.controller.setDictSearch('');
                      widget.controller.setDictFilter('All');
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
                      (context, index) => _buildDictionaryItem(context, dicts[index], tokens),
                      childCount: dicts.length,
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
                        child: _buildDictionaryItem(context, dicts[index], tokens),
                      ),
                      childCount: dicts.length,
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

  Widget _buildDictionaryItem(BuildContext context, DictionaryMeta dict, AppTokens tokens) {
    final isInstalled = widget.controller.isDictInstalled(dict.id);
    final isDownloading = widget.controller.isDictDownloading(dict.id);
    final progress = widget.controller.getDictProgress(dict.id);

    return DownloadItemTile(
      title: dict.name,
      badgeText: dict.isBiblical ? 'BIBLICAL' : null,
      subtitle: '${dict.language} • ${dict.sizeDisplay}',
      description: dict.description,
      isDownloading: isDownloading,
      downloadProgress: progress,
      trailing: DownloadActionButton(
        isInstalled: isInstalled,
        isDownloading: isDownloading,
        progress: progress,
        onDownload: () => widget.controller.downloadDictionary(dict.id),
        onDelete: () async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('Delete ${dict.name}?'),
              content: const Text('This dictionary will be removed from your device.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
              ],
            ),
          );
          if (confirm == true) {
            await widget.controller.deleteDictionary(dict.id);
          }
        },
      ),
    );
  }
}
