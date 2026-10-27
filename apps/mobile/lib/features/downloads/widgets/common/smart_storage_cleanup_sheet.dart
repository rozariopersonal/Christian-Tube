import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../controllers/downloads_controller.dart';

/// Modal bottom sheet providing granular, 1-tap offline storage cleanup.
class SmartStorageCleanupSheet extends StatefulWidget {
  final DownloadsController controller;

  const SmartStorageCleanupSheet({
    super.key,
    required this.controller,
  });

  static Future<void> show(BuildContext context, DownloadsController controller) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SmartStorageCleanupSheet(controller: controller),
    );
  }

  @override
  State<SmartStorageCleanupSheet> createState() => _SmartStorageCleanupSheetState();
}

class _SmartStorageCleanupSheetState extends State<SmartStorageCleanupSheet> {
  bool _cleanAudio = false;
  bool _cleanFonts = false;
  bool _cleanArticles = false;
  bool _isCleaning = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colorScheme = Theme.of(context).colorScheme;
    final storage = widget.controller.state.storage;

    var reclaimBytes = 0;
    if (_cleanAudio) reclaimBytes += storage.audioBytes;
    if (_cleanFonts) reclaimBytes += storage.fontsBytes;
    if (_cleanArticles) reclaimBytes += storage.articlesBytes;

    final reclaimFormatted = reclaimBytes > 0
        ? '${(reclaimBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '0 MB';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Container(
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: MediaQuery.paddingOf(context).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.surfaceBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.error.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.cleaning_services_rounded, color: colorScheme.error, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Smart Storage Cleaner',
                          style: TextStyle(
                            color: tokens.onSurface,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Select cache categories to safely reclaim space on your device.',
                          style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Cleanup categories
              if (storage.audioBytes > 0)
                _buildCleanupOption(
                  title: 'Downloaded Audio Sermons',
                  subtitle: '${storage.audioTracksCount} tracks in ${storage.audioSeriesCount} series',
                  size: storage.audioFormatted,
                  icon: Icons.headphones_rounded,
                  value: _cleanAudio,
                  onChanged: (v) => setState(() => _cleanAudio = v ?? false),
                  tokens: tokens,
                ),

              if (storage.fontsBytes > 0)
                _buildCleanupOption(
                  title: 'Reader Typography Fonts',
                  subtitle: '${storage.fontsCount} downloaded reader fonts',
                  size: storage.fontsFormatted,
                  icon: Icons.font_download_rounded,
                  value: _cleanFonts,
                  onChanged: (v) => setState(() => _cleanFonts = v ?? false),
                  tokens: tokens,
                ),

              if (storage.articlesBytes > 0)
                _buildCleanupOption(
                  title: 'Offline Topical Articles',
                  subtitle: '${storage.articlesCount} languages cached',
                  size: storage.articlesFormatted,
                  icon: Icons.article_rounded,
                  value: _cleanArticles,
                  onChanged: (v) => setState(() => _cleanArticles = v ?? false),
                  tokens: tokens,
                ),

              if (storage.audioBytes == 0 && storage.fontsBytes == 0 && storage.articlesBytes == 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No non-essential caches present. Only core Bible and Dictionary databases are installed.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 13),
                    ),
                  ),
                ),

              const SizedBox(height: 20),

              // Action button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: reclaimBytes > 0 && !_isCleaning
                      ? () async {
                          setState(() => _isCleaning = true);
                          await widget.controller.smartClean(
                            clearAudio: _cleanAudio,
                            clearFonts: _cleanFonts,
                            clearArticles: _cleanArticles,
                          );
                          if (context.mounted) {
                            Navigator.pop(context);
                          }
                        }
                      : null,
                  icon: _isCleaning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.delete_sweep_rounded, size: 18),
                  label: Text(
                    reclaimBytes > 0 ? 'Clean Up $reclaimFormatted' : 'Select items to clean',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.error,
                    foregroundColor: colorScheme.onError,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCleanupOption({
    required String title,
    required String subtitle,
    required String size,
    required IconData icon,
    required bool value,
    required ValueChanged<bool?> onChanged,
    required AppTokens tokens,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: tokens.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value ? tokens.accent.withValues(alpha: 0.5) : tokens.surfaceBorder,
        ),
      ),
      child: CheckboxListTile(
        value: value,
        onChanged: onChanged,
        activeColor: tokens.accent,
        checkColor: tokens.background,
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: tokens.onSurface),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: tokens.onSurface,
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '$subtitle • $size',
          style: TextStyle(color: tokens.onSurfaceMuted, fontSize: 11.5),
        ),
      ),
    );
  }
}
