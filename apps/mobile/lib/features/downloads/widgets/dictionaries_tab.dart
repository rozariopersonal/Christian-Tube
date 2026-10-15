import 'package:flutter/material.dart';
import '../../../../core/layout/adaptivity.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../dictionary/services/dictionary_download_manager.dart';
import '../controllers/downloads_controller.dart';

class DictionariesTab extends StatelessWidget {
  final DownloadsController controller;

  const DictionariesTab({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.state;
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
              .where((d) => controller.isDictInstalled(d.id))
              .toList();
        }

        final isWide = ScreenClass.of(context).isMediumOrExpanded;

        return MaxWidthBox(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Explanatory Banner
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

                    // Search Field
                    TextField(
                      controller: TextEditingController(text: state.dictSearch)
                        ..selection = TextSelection.collapsed(offset: state.dictSearch.length),
                      onChanged: controller.setDictSearch,
                      style: TextStyle(color: tokens.onSurface, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search dictionaries by language or name…',
                        hintStyle: TextStyle(color: tokens.onSurfaceMuted, fontSize: 13),
                        prefixIcon: Icon(Icons.search, color: tokens.onSurfaceMuted, size: 20),
                        suffixIcon: state.dictSearch.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear, color: tokens.onSurfaceMuted, size: 18),
                                onPressed: () => controller.setDictSearch(''),
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

                    // Category Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final opt in ['All', 'Biblical', 'Indian', 'Global'])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(opt),
                                selected: state.dictFilter == opt,
                                onSelected: (_) => controller.setDictFilter(opt),
                                selectedColor: tokens.accent.withValues(alpha: 0.2),
                                checkmarkColor: tokens.accent,
                                labelStyle: TextStyle(
                                  fontSize: 12,
                                  color: state.dictFilter == opt
                                      ? tokens.accent
                                      : tokens.onSurfaceMuted,
                                  fontWeight: state.dictFilter == opt
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
                            onSelected: (_) => controller.toggleOnlyInstalled(),
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

              // Dictionaries Grid / List
              if (isWide)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: GridExtents.bibleManager,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      mainAxisExtent: 130,
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
    final isInstalled = controller.isDictInstalled(dict.id);
    final isDownloading = controller.isDictDownloading(dict.id);
    final progress = controller.getDictProgress(dict.id);

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
                            dict.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                        if (dict.isBiblical) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: tokens.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'BIBLICAL',
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
                      '${dict.language} • ${dict.sizeDisplay}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 11.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dict.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isInstalled)
                IconButton(
                  icon: Icon(Icons.delete_outline, color: tokens.onSurfaceMuted, size: 20),
                  tooltip: 'Delete Dictionary',
                  onPressed: () async {
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
                      await controller.deleteDictionary(dict.id);
                    }
                  },
                )
              else if (isDownloading)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Text(
                    progress > 0 ? '${(progress * 100).toInt()}%' : 'Downloading…',
                    style: TextStyle(color: tokens.accent, fontWeight: FontWeight.bold, fontSize: 11.5),
                  ),
                )
              else
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => controller.downloadDictionary(dict.id),
                  child: const Text('Download', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          if (isDownloading) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress > 0 ? progress : null,
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
