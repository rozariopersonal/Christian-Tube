import 'package:flutter/material.dart';
import '../models/bible_version_meta.dart';
import '../services/bible_download_manager.dart';

class BibleVersionPickerModal extends StatelessWidget {
  final String activeVersionId;
  final ValueChanged<String> onSelectVersion;
  final VoidCallback onOpenManager;

  const BibleVersionPickerModal({
    super.key,
    required this.activeVersionId,
    required this.onSelectVersion,
    required this.onOpenManager,
  });

  @override
  Widget build(BuildContext context) {
    final downloadManager = BibleDownloadManager();
    final installedIds = downloadManager.installedIds;
    final installedList = BibleDownloadManager.catalog
        .where((v) => installedIds.contains(v.id))
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
          // Drag Handle
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

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Bible Translation',
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

          // Installed Versions List
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: installedList.length,
              separatorBuilder: (context, index) =>
                  const Divider(color: Colors.white10, height: 1),
              itemBuilder: (context, index) {
                final meta = installedList[index];
                final isSelected = meta.id == activeVersionId;

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    meta.name,
                    style: TextStyle(
                      color: isSelected ? const Color(0xFFF59E0B) : Colors.white,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
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
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
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
