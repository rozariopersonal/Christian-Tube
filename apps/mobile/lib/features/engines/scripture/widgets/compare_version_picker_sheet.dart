import 'package:flutter/material.dart';
import '../../../../core/layout/adaptive_sheet_frame.dart';
import '../../../../core/theme/app_tokens.dart';
import '../services/bible_download_manager.dart';

/// Lets the user pick (or clear) the secondary version shown alongside the
/// active version on the Words feed cards. Only installed versions can be picked.
class CompareVersionPickerSheet extends StatelessWidget {
  final String activeVersionId;
  final String? currentComparisonId;
  final ValueChanged<String?> onSelectComparison;

  const CompareVersionPickerSheet({
    super.key,
    required this.activeVersionId,
    required this.currentComparisonId,
    required this.onSelectComparison,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final downloadManager = BibleDownloadManager();
    final installedIds = downloadManager.installedIds;
    final installedList = BibleDownloadManager.catalog
        .where((v) => installedIds.contains(v.id) && v.id != activeVersionId)
        .toList();

    return AdaptiveSheetFrame(
      maxHeightFactor: 0.70,
      showDragHandle: true,
      contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Compare With',
                style: TextStyle(
                  color: tokens.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: tokens.onSurfaceMuted, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: installedList.length + 1,
              separatorBuilder: (context, index) =>
                  Divider(color: tokens.surfaceBorder, height: 1),
              itemBuilder: (context, index) {
                if (index == 0) {
                  final isSelected = currentComparisonId == null;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'None (single version)',
                      style: TextStyle(
                        color: tokens.onSurface,
                        fontWeight: FontWeight.normal,
                        fontSize: 15,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(
                            Icons.check_circle_rounded,
                            color: tokens.accent,
                            size: 22,
                          )
                        : Icon(
                            Icons.radio_button_unchecked,
                            color: tokens.onSurfaceDisabled,
                            size: 22,
                          ),
                    onTap: () {
                      onSelectComparison(null);
                      Navigator.pop(context);
                    },
                  );
                }
                final meta = installedList[index - 1];
                final isSelected = meta.id == currentComparisonId;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    meta.name,
                    style: TextStyle(
                      color: isSelected
                          ? tokens.accent
                          : tokens.onSurface,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    '${meta.language} • ${meta.sizeDisplay}',
                    style: TextStyle(
                      color: isSelected
                          ? tokens.accent.withValues(alpha: 0.8)
                          : tokens.onSurfaceMuted,
                      fontSize: 12,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(
                          Icons.check_circle_rounded,
                          color: tokens.accent,
                          size: 22,
                        )
                      : Icon(
                          Icons.radio_button_unchecked,
                          color: tokens.onSurfaceDisabled,
                          size: 22,
                        ),
                  onTap: () {
                    onSelectComparison(meta.id);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}