import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/engines/scripture/models/scripture_theme_state.dart';
import 'package:mobile/shared/services/reader_appearance.dart';
import 'package:mobile/shared/services/reader_fonts_service.dart';

/// Interactive Level 1 tile showing the currently selected font and a drill-down
/// indicator to the full font browser.
class FontFamilyTile extends StatelessWidget {
  final ReaderAppearance appearance;
  final VoidCallback onTap;

  const FontFamilyTile({
    super.key,
    required this.appearance,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final textCol = appearance.textColor(tokens);
    final mutedCol = appearance.mutedTextColor(tokens);
    final borderCol = appearance.surfaceBorder(tokens);
    final bgCol = appearance.surfaceVariant(tokens);

    return ListenableBuilder(
      listenable: Listenable.merge([appearance, ReaderFontsService.instance]),
      builder: (context, _) {
        final fonts = ScriptureThemeCatalog.getFontsForLanguage(appearance.languageCode);
        final currentOption = fonts.firstWhere(
          (f) => f.id == appearance.fontFamily,
          orElse: () => fonts.isNotEmpty
              ? fonts.first
              : ScriptureFontOption(
                  id: appearance.fontFamily,
                  name: appearance.fontFamily,
                  subtitle: 'Custom Font',
                ),
        );

        final resolvedName = ScriptureThemeCatalog.resolveFontFamily(
          currentOption.id,
          currentOption.languageCode ?? appearance.languageCode,
        );

        final isDownloaded = resolvedName != null &&
            ReaderFontsService.instance.isFamilyInstalledSync(resolvedName);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Font Family',
                      style: TextStyle(
                        color: mutedCol,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        'Browse all fonts',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: bgCol,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderCol),
                  ),
                  child: Row(
                    children: [
                      // Glyph preview pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: tokens.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: borderCol),
                        ),
                        child: Text(
                          currentOption.sampleGlyph,
                          style: TextStyle(
                            fontFamily: resolvedName,
                            fontSize: 14,
                            fontWeight: appearance.fontWeight,
                            fontStyle: appearance.fontStyle,
                            decoration: appearance.textDecoration,
                            color: tokens.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Font details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentOption.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: textCol,
                                fontWeight: FontWeight.bold,
                                fontStyle: appearance.fontStyle,
                                fontSize: 14,
                                fontFamily: resolvedName,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    currentOption.subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: mutedCol,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ),
                                if (isDownloaded) ...[
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 13,
                                    color: tokens.accent,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    'Installed',
                                    style: TextStyle(
                                      color: tokens.accent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Chevron drilldown
                      Icon(
                        Icons.chevron_right_rounded,
                        color: mutedCol,
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
