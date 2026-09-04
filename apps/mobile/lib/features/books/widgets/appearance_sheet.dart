import 'package:flutter/material.dart';
import 'package:mobile/core/layout/adaptivity.dart';
import 'package:mobile/core/layout/content_width.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/books/services/book_reader_appearance.dart';

/// Shows the reading-appearance sheet (theme, font family, font size) for the
/// book reader.
///
/// On `compact` screens this renders as a bottom sheet; on `medium`/`expanded`
/// as a centered dialog (per the Responsive & Adaptive UI Standard). The
/// [appearance] ChangeNotifier is mutated directly inside the sheet's own
/// local state so the preview updates live without rebuilding the whole reader.
void showBookReaderAppearanceSheet(BuildContext context, BookReaderAppearance appearance) {
  final tokens = context.tokens;
  final screen = ScreenClass.of(context);

  Widget buildSheetContent(BuildContext ctx, StateSetter setModalState) {
    return SafeArea(
      child: Padding(
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
                  color: tokens.surfaceBorder,
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
                    color: tokens.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (!screen.isCompact)
                  IconButton(
                    icon: Icon(Icons.close, size: 20, color: tokens.onSurfaceMuted),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            Text('Theme', style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildThemeChip(ctx, 'Paper', ReaderThemeMode.paper, const Color(0xFFFAF9F6), const Color(0xFF1A1A1A), setModalState, appearance),
                const SizedBox(width: 8),
                _buildThemeChip(ctx, 'Sepia', ReaderThemeMode.sepia, const Color(0xFFFBF0D9), const Color(0xFF3B2F2F), setModalState, appearance),
                const SizedBox(width: 8),
                _buildThemeChip(ctx, 'Dark', ReaderThemeMode.dark, const Color(0xFF1E212B), const Color(0xFFE6EDF3), setModalState, appearance),
                const SizedBox(width: 8),
                _buildThemeChip(ctx, 'AMOLED', ReaderThemeMode.amoled, const Color(0xFF000000), const Color(0xFFFFFFFF), setModalState, appearance),
              ],
            ),
            const SizedBox(height: 20),

            Text('Font Family', style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: appearance.useSerifFont ? tokens.accent.withValues(alpha: 0.15) : null,
                      side: BorderSide(color: appearance.useSerifFont ? tokens.accent : tokens.surfaceBorder),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      setModalState(() => appearance.useSerifFont = true);
                    },
                    child: Text(
                      'Serif (Book)',
                      style: TextStyle(
                        fontFamily: 'serif',
                        color: appearance.useSerifFont ? tokens.accent : tokens.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: !appearance.useSerifFont ? tokens.accent.withValues(alpha: 0.15) : null,
                      side: BorderSide(color: !appearance.useSerifFont ? tokens.accent : tokens.surfaceBorder),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      setModalState(() => appearance.useSerifFont = false);
                    },
                    child: Text(
                      'Sans-Serif (Modern)',
                      style: TextStyle(
                        color: !appearance.useSerifFont ? tokens.accent : tokens.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Font Size', style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12)),
                Text('${appearance.fontSize.toInt()} pt', style: TextStyle(color: tokens.onSurface, fontWeight: FontWeight.bold)),
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

  if (screen.isCompact) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: tokens.surface,
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
        backgroundColor: tokens.surface,
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

Widget _buildThemeChip(
  BuildContext context,
  String label,
  ReaderThemeMode mode,
  Color bg,
  Color text,
  StateSetter setModalState,
  BookReaderAppearance appearance,
) {
  final tokens = context.tokens;
  final isSelected = appearance.themeMode == mode;

  return Expanded(
    child: GestureDetector(
      onTap: () {
        setModalState(() => appearance.themeMode = mode);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? tokens.accent : tokens.surfaceBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: text,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    ),
  );
}
