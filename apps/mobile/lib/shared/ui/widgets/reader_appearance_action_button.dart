import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/shared/services/reader_appearance.dart';
import 'package:mobile/shared/ui/reader_appearance_sheet.dart';

/// Reusable standardized 'Aa' trigger button used in AppBars across Bible,
/// Books, Articles, Songs, and Verse Study screens.
class ReaderAppearanceActionButton extends StatelessWidget {
  final ReaderAppearance appearance;
  final Color? color;
  final double fontSize;
  final VoidCallback? onBeforeOpen;
  final String? tooltip;

  const ReaderAppearanceActionButton({
    super.key,
    required this.appearance,
    this.color,
    this.fontSize = 16.0,
    this.onBeforeOpen,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.maybeOf(context);
    final fg = color ?? appearance.textColor(tokens);

    return IconButton(
      tooltip: tooltip ?? l10n?.appearance ?? 'Appearance Settings',
      icon: Text(
        'Aa',
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.bold,
          fontSize: fontSize,
          letterSpacing: -0.5,
        ),
      ),
      onPressed: () {
        onBeforeOpen?.call();
        showReaderAppearanceSheet(context, appearance);
      },
    );
  }
}

/// Standardized 'Aa' menu item for AppBars that use overflow popup menus.
class ReaderAppearanceMenuItem extends StatelessWidget {
  final ReaderAppearance appearance;
  final VoidCallback? onSelected;

  const ReaderAppearanceMenuItem({
    super.key,
    required this.appearance,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.maybeOf(context);

    return InkWell(
      onTap: () {
        onSelected?.call();
        showReaderAppearanceSheet(context, appearance);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(
              'Aa',
              style: TextStyle(
                color: tokens.accent,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n?.appearance ?? 'Reading Appearance',
                style: TextStyle(
                  color: tokens.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
