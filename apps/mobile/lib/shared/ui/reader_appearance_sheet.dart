import 'package:flutter/material.dart';
import 'package:mobile/core/layout/adaptivity.dart';
import 'package:mobile/core/layout/content_width.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/engines/scripture/models/scripture_theme_state.dart';
import 'package:mobile/shared/services/reader_appearance.dart';
import 'package:mobile/shared/services/reader_fonts_service.dart';

/// Shows the reading-appearance sheet (theme, font family, font size) for readers.
///
/// On `compact` screens this renders as a bottom sheet; on `medium`/`expanded`
/// as a centered dialog (per the Responsive & Adaptive UI Standard). The
/// [appearance] ChangeNotifier is mutated directly inside the sheet's own
/// local state so the preview updates live without rebuilding the whole reader.
void showReaderAppearanceSheet(BuildContext context, ReaderAppearance appearance) {
  final tokens = context.tokens;
  final screen = ScreenClass.of(context);

  Widget buildSheetContent(BuildContext ctx, StateSetter setModalState) {
    final textCol = appearance.textColor(tokens);
    final mutedCol = appearance.mutedTextColor(tokens);
    final borderCol = appearance.surfaceBorder(tokens);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: borderCol,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Reading Appearance',
                  style: TextStyle(
                    color: textCol,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (!screen.isCompact)
                  IconButton(
                    icon: Icon(Icons.close, size: 20, color: mutedCol),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: appearance.surfaceVariant(tokens),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderCol),
              ),
              child: Row(
                children: [
                  Icon(
                    tokens.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                    size: 20,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Theme',
                          style: TextStyle(
                            color: textCol,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tokens.isDark
                              ? (tokens.background == Colors.black
                                  ? 'Pure OLED Black (from App Settings)'
                                  : 'Dark Mode (from App Settings)')
                              : 'Light Mode (from App Settings)',
                          style: TextStyle(
                            color: mutedCol,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Text('Font Family', style: TextStyle(color: mutedCol, fontSize: 12)),
            const SizedBox(height: 8),
            ListenableBuilder(
              listenable: ReaderFontsService.instance,
              builder: (context, _) {
                final fonts =
                    ScriptureThemeCatalog.getFontsForLanguage(appearance.languageCode);
                return SizedBox(
                  height: 52,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: fonts.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final font = fonts[index];
                      final isSelected = font.id == appearance.fontFamily;
                      return _buildFontChip(
                          context, font, isSelected, setModalState, appearance);
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Font Size', style: TextStyle(color: mutedCol, fontSize: 12)),
                Text('${appearance.fontSize.toInt()} pt', style: TextStyle(color: textCol, fontWeight: FontWeight.bold)),
              ],
            ),
            Slider(
              value: appearance.fontSize,
              min: appearance.minFontSize,
              max: appearance.maxFontSize,
              divisions: 12,
              activeColor: tokens.accent,
              onChanged: (val) {
                setModalState(() => appearance.fontSize = val);
              },
            ),
          ],
        ),
      ),
    );
  }

  final sheetBg = appearance.surface(tokens);

  if (screen.isCompact) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => MaxWidthBox(
        maxWidth: 640,
        child: StatefulBuilder(builder: (context, setModalState) => buildSheetContent(ctx, setModalState)),
      ),
    );
  } else {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: sheetBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: StatefulBuilder(builder: (context, setModalState) => buildSheetContent(ctx, setModalState)),
        ),
      ),
    );
  }
}

Widget _buildFontChip(
  BuildContext context,
  ScriptureFontOption font,
  bool isSelected,
  StateSetter setModalState,
  ReaderAppearance appearance,
) {
  final tokens = context.tokens;
  final previewStyle = TextStyle(
    fontFamily: ScriptureThemeCatalog.resolveFontFamily(
      font.id,
      font.languageCode ?? appearance.languageCode,
    ),
    fontSize: 15,
    color: isSelected ? tokens.accent : tokens.onSurface,
    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
  );

  return GestureDetector(
    onTap: () {
      setModalState(() => appearance.fontFamily = font.id);
      ReaderFontsService.instance
          .ensureResolved(font.id, font.languageCode ?? appearance.languageCode);
    },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? tokens.accent.withValues(alpha: 0.22) : tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? tokens.accent : tokens.surfaceBorder,
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: tokens.scrim.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected
                    ? tokens.accent.withValues(alpha: 0.5)
                    : tokens.surfaceBorder,
                width: 0.8,
              ),
            ),
            child: Text(
              font.sampleGlyph,
              style: previewStyle.copyWith(
                fontSize: 13,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            font.name,
            style: TextStyle(
              color: isSelected ? tokens.accent : tokens.onSurface,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ],
      ),
    ),
  );
}
