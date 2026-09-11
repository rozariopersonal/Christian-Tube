import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../models/audio_series.dart';
import 'audio_series_card.dart';

/// Renders grouped collections (by Category, by Speaker, or Alphabetical)
/// with expandable / collapsible headers and responsive grids.
class AudioGroupedSections extends StatefulWidget {
  final Map<String, List<AudioSeries>> groups;
  final ValueChanged<AudioSeries> onOpenSeries;
  final String emptyMessage;

  const AudioGroupedSections({
    super.key,
    required this.groups,
    required this.onOpenSeries,
    this.emptyMessage = 'No audio series found.',
  });

  @override
  State<AudioGroupedSections> createState() => _AudioGroupedSectionsState();
}

class _AudioGroupedSectionsState extends State<AudioGroupedSections> {
  // Store collapsed states; default first 3 open
  final Set<String> _collapsedGroups = {};

  void _toggleGroup(String key) {
    setState(() {
      if (_collapsedGroups.contains(key)) {
        _collapsedGroups.remove(key);
      } else {
        _collapsedGroups.add(key);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light);

    if (widget.groups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(
            widget.emptyMessage,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.onSurfaceMuted,
            ),
          ),
        ),
      );
    }

    final groupKeys = widget.groups.keys.toList();

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: groupKeys.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final key = groupKeys[index];
        final seriesList = widget.groups[key] ?? [];
        final isCollapsed = _collapsedGroups.contains(key);

        return Container(
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: tokens.surfaceBorder.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: isCollapsed
                    ? BorderRadius.circular(16)
                    : const BorderRadius.vertical(top: Radius.circular(16)),
                onTap: () => _toggleGroup(key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                key,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: tokens.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.surfaceVariant,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${seriesList.length}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: tokens.onSurfaceMuted,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        isCollapsed
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_up_rounded,
                        color: tokens.onSurfaceMuted,
                      ),
                    ],
                  ),
                ),
              ),
              if (!isCollapsed) ...[
                const Divider(height: 1, thickness: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: seriesList.length,
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 16,
                      childAspectRatio: 0.72,
                    ),
                    itemBuilder: (context, idx) {
                      final series = seriesList[idx];
                      return AudioSeriesCard(
                        series: series,
                        onTap: () => widget.onOpenSeries(series),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
