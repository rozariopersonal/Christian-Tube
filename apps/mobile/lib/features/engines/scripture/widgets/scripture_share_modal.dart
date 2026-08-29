import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/theme/app_tokens.dart';
import '../models/scripture_card.dart';
import '../services/file_saver.dart';

class ScriptureShareModal extends StatelessWidget {
  final Uint8List imageBytes;
  final ScriptureCard card;
  final String fileName;
  final String appName;

  const ScriptureShareModal({
    super.key,
    required this.imageBytes,
    required this.card,
    required this.fileName,
    this.appName = 'ChristianApp',
  });

  static Future<void> show(
    BuildContext context, {
    required Uint8List imageBytes,
    required ScriptureCard card,
    required String fileName,
    String appName = 'ChristianApp',
  }) {
    return showDialog(
      context: context,
      barrierColor: context.tokens.scrim,
      builder: (ctx) => ScriptureShareModal(
        imageBytes: imageBytes,
        card: card,
        fileName: fileName,
        appName: appName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: tokens.background,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: tokens.surfaceBorder),
          boxShadow: [
            BoxShadow(
              color: tokens.scrim.withValues(alpha: 0.87),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome,
                        color: tokens.accent, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Generated Graphic Card',
                      style: TextStyle(
                        color: tokens.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: tokens.onSurfaceMuted, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // High-Resolution Graphic Card Preview (9:16 Aspect Ratio)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 380),
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: tokens.accent.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: tokens.scrim.withValues(alpha: 0.54),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.memory(
                    imageBytes,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Action Buttons
            Row(
              children: [
                // Copy Text
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      Share.share(
                        '“${card.resolvedText ?? ""}”\n\n— ${card.referenceLabel}\n\nShared via $appName',
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy Text'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: tokens.onSurfaceMuted,
                      side: BorderSide(color: tokens.surfaceBorder),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Download / Save PNG Image
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        await saveOrDownloadFile(imageBytes, fileName);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Graphic image downloaded!'),
                              backgroundColor:
                                  Theme.of(context).colorScheme.inverseSurface,
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      } catch (e) {
                        debugPrint('Error saving file: $e');
                      }
                    },
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text(
                      'Download 9:16 PNG',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tokens.accent,
                      foregroundColor: tokens.scrim,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
