import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/scripture_card.dart';

class ScriptureImageExporter {
  static Future<void> captureAndShare({
    required GlobalKey boundaryKey,
    required ScriptureCard card,
    String appName = 'ChristianTube',
  }) async {
    try {
      final boundary = boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;

      if (boundary == null) {
        // Fallback to text sharing if render boundary is not ready
        await Share.share(
          '${card.resolvedText ?? ""}\n\n— ${card.referenceLabel} (${card.resolvedVersion ?? "WEB"})\n\nShared via $appName',
        );
        return;
      }

      // Capture at 3.0x pixel ratio for ultra-crisp 1080x1920 / 4K resolution
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) return;

      final pngBytes = byteData.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final sanitizedRef = card.referenceLabel.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final filePath =
          '${tempDir.path}/verse_${sanitizedRef}_${DateTime.now().millisecondsSinceEpoch}.png';

      final file = File(filePath);
      await file.writeAsBytes(pngBytes);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: '“${card.referenceLabel}” — Shared from $appName',
      );
    } catch (e) {
      debugPrint('Error in ScriptureImageExporter: $e');
      // Fallback to text sharing
      await Share.share(
        '${card.resolvedText ?? ""}\n\n— ${card.referenceLabel}\n\nShared via $appName',
      );
    }
  }
}
