import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../models/audio_series.dart';
import 'audio_series_card.dart';

/// Renders grouped collections (by Category, by Speaker, or Alphabetical)
/// with expandable / collapsible headers, cover-art previews in the collapsed
/// state, a smooth [AnimatedCrossFade] transition, and an accent strip.
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
  final Set<String> _expandedGroups = {};

  void _toggleGroup(String key) {
    setState(() {
      if (_expandedGroups.contains(key)) {
        _expandedGroups.remove(key);
      } else {
        _expandedGroups.add(key);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    if (widget.groups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.headphones_outlined, size: 48, color: tokens.onSurfaceDisabled),
              const SizedBox(height: 12),
              Text(
                widget.emptyMessage,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: tokens.onSurfaceMuted),
              ),
            ],
          ),
        ),
      );
    }

    final groupKeys = widget.groups.keys.toList();

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: groupKeys.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final key = groupKeys[index];
        final seriesList = widget.groups[key] ?? [];
        final isExpanded = _expandedGroups.contains(key);
        return _GroupSection(
          groupKey: key,
          seriesList: seriesList,
          isExpanded: isExpanded,
          onToggle: () => _toggleGroup(key),
          onOpenSeries: widget.onOpenSeries,
          theme: theme,
          tokens: tokens,
        );
      },
    );
  }
}

class _GroupSection extends StatelessWidget {
  final String groupKey;
  final List<AudioSeries> seriesList;
  final bool isExpanded;
  final VoidCallback onToggle;
  final ValueChanged<AudioSeries> onOpenSeries;
  final ThemeData theme;
  final AppTokens tokens;

  const _GroupSection({
    required this.groupKey,
    required this.seriesList,
    required this.isExpanded,
    required this.onToggle,
    required this.onOpenSeries,
    required this.theme,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: tokens.isDark ? 0.25 : 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left accent strip
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
              ),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: onToggle,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          groupKey,
                                          style: theme.textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: tokens.onSurface,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primary.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          '${seriesList.length}',
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (!isExpanded && seriesList.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    _CoverPreviewRow(
                                      series: seriesList.take(5).toList(),
                                      tokens: tokens,
                                      theme: theme,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            AnimatedRotation(
                              turns: isExpanded ? 0.5 : 0.0,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOut,
                              child: Icon(Icons.keyboard_arrow_down_rounded, color: tokens.onSurfaceMuted),
                            ),
                          ],
                        ),
                      ),
                    ),
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 280),
                      sizeCurve: Curves.easeInOut,
                      firstChild: const SizedBox.shrink(),
                      secondChild: Column(
                        children: [
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: tokens.surfaceBorder.withValues(alpha: 0.5),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                // Intrinsic-height passes can lay this
                                // shrink-wrap grid out at zero width; a grid
                                // with no horizontal space must not be built.
                                if (constraints.maxWidth <= 0) {
                                  return const SizedBox.shrink();
                                }
                                return GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: seriesList.length,
                                  gridDelegate:
                                      const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 160,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                    childAspectRatio: 1.0,
                                  ),
                                  itemBuilder: (context, idx) {
                                    final series = seriesList[idx];
                                    return AudioSeriesCard(
                                      series: series,
                                      onTap: () => onOpenSeries(series),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      crossFadeState: isExpanded
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverPreviewRow extends StatelessWidget {
  final List<AudioSeries> series;
  final AppTokens tokens;
  final ThemeData theme;

  const _CoverPreviewRow({
    required this.series,
    required this.tokens,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    const thumbSize = 32.0;
    const overlap = 10.0;

    return SizedBox(
      height: thumbSize,
      child: Stack(
        children: [
          for (var i = 0; i < series.length; i++)
            Positioned(
              left: i * (thumbSize - overlap),
              child: Container(
                width: thumbSize,
                height: thumbSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: tokens.surface, width: 1.5),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: series[i].coverUrl != null && series[i].coverUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: series[i].coverUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: tokens.surfaceVariant,
                            child: Icon(Icons.headphones_rounded, size: 14,
                                color: theme.colorScheme.primary.withValues(alpha: 0.6)),
                          ),
                        )
                      : Container(
                          color: tokens.surfaceVariant,
                          child: Icon(Icons.headphones_rounded, size: 14,
                              color: theme.colorScheme.primary.withValues(alpha: 0.6)),
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
