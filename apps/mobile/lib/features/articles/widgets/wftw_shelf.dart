import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../models/wftw_index_entry.dart';

/// Horizontal "Word for the Week" teaching shelf for the Books library.
/// Renders the newest [entries] as tappable cards plus a "View all" entry
/// point into the full teaching browser. Reused for the multi-language
/// Articles section (custom [title] and [icon]).
class WftwShelf extends StatelessWidget {
  final List<WftwIndexEntry> entries;
  final VoidCallback onViewAll;
  final ValueChanged<WftwIndexEntry> onTapArticle;
  final String title;
  final IconData icon;

  const WftwShelf({
    super.key,
    required this.entries,
    required this.onViewAll,
    required this.onTapArticle,
    this.title = 'Word for the Week',
    this.icon = Icons.auto_stories_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Row(
            children: [
              Flexible(
                child: Row(
                  children: [
                    Icon(icon, color: tokens.accent, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onViewAll,
                style: TextButton.styleFrom(
                  foregroundColor: tokens.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('View all', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 150,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: SizedBox(
                  width: 210,
                  child: _WftwShelfTile(
                    entry: entry,
                    tokens: tokens,
                    onTap: () => onTapArticle(entry),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WftwShelfTile extends StatelessWidget {
  final WftwIndexEntry entry;
  final AppTokens tokens;
  final VoidCallback onTap;

  const _WftwShelfTile({
    required this.entry,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.surfaceBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: tokens.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.menu_book_rounded, color: tokens.accent, size: 16),
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_outward_rounded, color: tokens.onSurfaceMuted, size: 16),
                ],
              ),
              const Spacer(),
              Text(
                entry.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                formatWftwDate(entry.date),
                style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}