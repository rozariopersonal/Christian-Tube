import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../models/wftw_index_entry.dart';

/// One tappable article row in a teaching/articles browser list. When
/// [langLabel] is provided, a small language badge is shown next to the title
/// (used by the multi-language articles browser and the Library shelf).
class ArticleRow extends StatelessWidget {
  final WftwIndexEntry entry;
  final VoidCallback onTap;
  final String? langLabel;

  const ArticleRow({
    super.key,
    required this.entry,
    required this.onTap,
    this.langLabel,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: tokens.surfaceBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.auto_stories_rounded, color: tokens.accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: Text(
                            entry.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (langLabel != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            margin: const EdgeInsets.only(top: 2),
                            decoration: BoxDecoration(
                              color: tokens.accent.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              langLabel!,
                              style: TextStyle(
                                color: tokens.accent,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      formatWftwDate(entry.date),
                      style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: tokens.onSurfaceMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}