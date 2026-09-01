import 'package:flutter/material.dart';
import '../../../../core/layout/adaptivity.dart';
import '../../../../core/theme/app_tokens.dart';
import '../models/bible_version_meta.dart';

class BibleVersionInfoSheet extends StatelessWidget {
  final BibleVersionMeta meta;

  const BibleVersionInfoSheet({
    super.key,
    required this.meta,
  });

  static Future<void> show(BuildContext context, BibleVersionMeta meta) {
    final screenClass = ScreenClass.of(context);
    if (screenClass.isMediumOrExpanded) {
      return showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Material(
                color: context.tokens.surface,
                child: BibleVersionInfoSheet(meta: meta),
              ),
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: context.tokens.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: BibleVersionInfoSheet(meta: meta),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colorScheme = Theme.of(context).colorScheme;

    final isPublicDomain = meta.license.toLowerCase().contains('public domain');
    final isCreativeCommons = meta.license.toLowerCase().contains('cc');

    final badgeColor = isCreativeCommons
        ? colorScheme.tertiary
        : isPublicDomain
            ? tokens.accent
            : colorScheme.secondary;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle for bottom sheet
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: tokens.onSurfaceDisabled,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.name,
                      style: TextStyle(
                        color: tokens.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${meta.language} • ${meta.id} • ${meta.sizeDisplay}',
                      style: TextStyle(
                        color: tokens.onSurfaceMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: tokens.onSurfaceMuted, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Close',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // License Tag & Status Pill
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isCreativeCommons
                          ? Icons.share_rounded
                          : isPublicDomain
                              ? Icons.verified_user_outlined
                              : Icons.lock_clock_outlined,
                      color: badgeColor,
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      meta.license,
                      style: TextStyle(
                        color: badgeColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (meta.isDefaultBundled)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: tokens.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: tokens.accent.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    'Default Translation',
                    style: TextStyle(
                      color: tokens.accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // Description Section
          _buildSection(
            tokens: tokens,
            title: 'Description',
            child: Text(
              meta.description,
              style: TextStyle(
                color: tokens.onSurface,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Copyright & Rights Holder
          if (meta.copyrightHolder != null && meta.copyrightHolder!.isNotEmpty) ...[
            _buildSection(
              tokens: tokens,
              title: 'Rights Holder & Publisher',
              child: Text(
                meta.copyrightHolder!,
                style: TextStyle(
                  color: tokens.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Legal Attribution Statement
          if (meta.attributionText != null && meta.attributionText!.isNotEmpty) ...[
            _buildSection(
              tokens: tokens,
              title: 'Attribution & Copyright Notice',
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tokens.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: tokens.surfaceBorder),
                ),
                child: Text(
                  meta.attributionText!,
                  style: TextStyle(
                    color: tokens.onSurfaceMuted,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Source / URL Info
          if (meta.sourceUrl != null && meta.sourceUrl!.isNotEmpty) ...[
            _buildSection(
              tokens: tokens,
              title: 'Source / Reference',
              child: Text(
                meta.sourceUrl!,
                style: TextStyle(
                  color: tokens.accent,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSection({
    required AppTokens tokens,
    required String title,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: tokens.onSurfaceMuted,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
