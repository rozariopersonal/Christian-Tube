import 'dart:ui';
import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import 'bible_version_native_names.dart';
import 'bible_version_picker_sheet.dart';

/// An accent-themed pill trigger that displays the original Bible version code
/// alongside its native language script (e.g. `TAOBVSI தமிழ்`, `BSB English`,
/// `HIN_IRV हिन्दी`, `TEL_IRV తెలుగు`).
///
/// Features:
/// - Solid accent-colored border with a subtle lighter accent background fill.
/// - The canonical original version code in bold accent typography.
/// - The native language script in its own language (from [BibleVersionNativeNames]).
/// - Optional frosted glass styling for overlay media/feed surfaces.
/// - One-tap invocation of the global [BibleVersionPickerSheet].
class BibleVersionPill extends StatelessWidget {
  final String activeVersionId;
  final ValueChanged<String>? onSelectVersion;
  final VoidCallback? onOpenManager;
  final Set<String>? installedIdsOverride;
  final bool showAllCatalog;
  final bool isFrosted;
  final bool showLeadingIcon;
  final bool showDropdownChevron;
  final bool showNativeScript;
  final double fontSize;
  final EdgeInsetsGeometry padding;
  final double borderWidth;

  const BibleVersionPill({
    super.key,
    required this.activeVersionId,
    this.onSelectVersion,
    this.onOpenManager,
    this.installedIdsOverride,
    this.showAllCatalog = true,
    this.isFrosted = false,
    this.showLeadingIcon = true,
    this.showDropdownChevron = true,
    this.showNativeScript = true,
    this.fontSize = 12.5,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    this.borderWidth = 1.2,
  });

  void _openSheet(BuildContext context) {
    BibleVersionPickerSheet.show(
      context,
      activeVersionId: activeVersionId,
      onSelectVersion: onSelectVersion,
      onOpenManager: onOpenManager,
      installedIdsOverride: installedIdsOverride,
      showAllCatalog: showAllCatalog,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isDark = context.isDark;
    final accent = tokens.accent;

    final nativeScript = showNativeScript
        ? BibleVersionNativeNames.getNativeScript(activeVersionId)
        : '';

    final pillFill = isFrosted
        ? (isDark
            ? tokens.scrim.withValues(alpha: 0.50)
            : tokens.surface.withValues(alpha: 0.85))
        : accent.withValues(alpha: isDark ? 0.14 : 0.08);

    final Widget pillContent = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: pillFill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accent,
          width: borderWidth,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLeadingIcon) ...[
            Icon(
              Icons.menu_book_rounded,
              size: 14,
              color: accent,
            ),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              activeVersionId,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.bold,
                fontSize: fontSize,
                letterSpacing: 0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (nativeScript.isNotEmpty) ...[
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                nativeScript,
                style: TextStyle(
                  color: accent.withValues(alpha: 0.85),
                  fontSize: (fontSize - 1.5).clamp(9.5, 12.0),
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (showDropdownChevron) ...[
            const SizedBox(width: 3),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: accent,
            ),
          ],
        ],
      ),
    );

    final tooltipMsg = nativeScript.isNotEmpty
        ? 'Bible Translation: $activeVersionId ($nativeScript)'
        : 'Bible Translation: $activeVersionId';

    return Semantics(
      button: true,
      label: tooltipMsg,
      child: Tooltip(
        message: tooltipMsg,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _openSheet(context),
            child: isFrosted
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: pillContent,
                    ),
                  )
                : pillContent,
          ),
        ),
      ),
    );
  }
}
