import 'package:flutter/material.dart';
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
    final downloadManager = BibleDownloadManager();
    final installedIds = downloadManager.installedIds;
    final installedList = BibleDownloadManager.catalog
        .where((v) => installedIds.contains(v.id) && v.id != activeVersionId)
        .toList();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Compare With',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70, size: 20),
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
                  const Divider(color: Colors.white10, height: 1),
              itemBuilder: (context, index) {
                if (index == 0) {
                  final isSelected = currentComparisonId == null;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'None (single version)',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.normal,
                        fontSize: 15,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFFF59E0B),
                            size: 22,
                          )
                        : const Icon(
                            Icons.radio_button_unchecked,
                            color: Colors.white30,
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
                          ? const Color(0xFFF59E0B)
                          : Colors.white,
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
                          ? const Color(0xFFF59E0B).withOpacity(0.8)
                          : Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFFF59E0B),
                          size: 22,
                        )
                      : const Icon(
                          Icons.radio_button_unchecked,
                          color: Colors.white30,
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