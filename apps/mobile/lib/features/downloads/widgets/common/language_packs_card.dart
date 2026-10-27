import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../controllers/downloads_controller.dart';

/// Interactive card showcasing 1-tap Language Offline Packs on the Overview tab.
class LanguagePacksCard extends StatelessWidget {
  final DownloadsController controller;

  const LanguagePacksCard({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    const packs = DownloadsController.languagePacks;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.language_rounded, color: tokens.accent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Language Offline Packs',
                      style: TextStyle(
                        color: tokens.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '1-tap downloads bundling Bible, dictionary, and articles for your language.',
                      style: TextStyle(
                        color: tokens.onSurfaceMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth < 420
                  ? double.infinity
                  : (constraints.maxWidth - 10) / 2;

              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final pack in packs)
                    _buildPackTile(
                      context,
                      pack: pack,
                      width: itemWidth,
                      tokens: tokens,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPackTile(
    BuildContext context, {
    required ({String code, String name, String nativeName, String bibleId, String? dictId, String? artLang, bool includeSongs, String sizeDisplay}) pack,
    required double width,
    required AppTokens tokens,
  }) {
    final isInstalled = controller.isLanguagePackInstalled(pack.code);
    final isDownloading = controller.isLanguagePackDownloading(pack.code);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isInstalled
              ? tokens.accent.withValues(alpha: 0.08)
              : tokens.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isInstalled
                ? tokens.accent.withValues(alpha: 0.3)
                : tokens.surfaceBorder,
          ),
        ),
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
                          pack.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        pack.sizeDisplay,
                        style: TextStyle(
                          color: tokens.onSurfaceMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    pack.nativeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.onSurfaceMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isDownloading)
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tokens.accent,
                ),
              )
            else if (isInstalled)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check, size: 12, color: tokens.accent),
                    const SizedBox(width: 4),
                    Text(
                      'Ready',
                      style: TextStyle(
                        color: tokens.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )
            else
              TextButton(
                onPressed: () => controller.downloadLanguagePack(pack.code),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: tokens.surface,
                  foregroundColor: tokens.accent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: BorderSide(color: tokens.surfaceBorder),
                  ),
                ),
                child: const Text('Get Pack', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }
}
