import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../services/bible_download_manager.dart';

class BibleVersionPickerModal extends StatelessWidget {
  final String activeVersionId;
  final ValueChanged<String> onSelectVersion;
  final VoidCallback onOpenManager;

  /// Optional override for the set of installed ids to display. When null,
  /// the modal falls back to [BibleDownloadManager.installedIds]. This allows
  /// callers that already have a vetted list (e.g. the Bible reader's
  /// controller.versions) to drive the picker without depending on the
  /// manager having been refreshed yet.
  final Set<String>? installedIdsOverride;

  const BibleVersionPickerModal({
    super.key,
    required this.activeVersionId,
    required this.onSelectVersion,
    required this.onOpenManager,
    this.installedIdsOverride,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final downloadManager = BibleDownloadManager();
    final effectiveIds = installedIdsOverride ?? downloadManager.installedIds;
    final installedList = BibleDownloadManager.catalog
        .where((v) => effectiveIds.contains(v.id))
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag Handle
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

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Bible Translation',
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

          // Installed Versions List
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: installedList.length,
              separatorBuilder: (context, index) =>
                  Divider(color: tokens.surfaceBorder, height: 1),
              itemBuilder: (context, index) {
                final meta = installedList[index];
                final isSelected = meta.id == activeVersionId;

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    meta.name,
                    style: TextStyle(
                      color: isSelected ? tokens.accent : tokens.onSurface,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
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
                    onSelectVersion(meta.id);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // Manage & Download Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onOpenManager();
              },
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Manage & Download More Translations'),
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.onSurface,
                side: BorderSide(color: tokens.surfaceBorder),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
