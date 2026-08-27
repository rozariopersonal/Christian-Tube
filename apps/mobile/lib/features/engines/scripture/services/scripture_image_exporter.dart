import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
      final sanitizedRef = card.referenceLabel.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final fileName = 'verse_${sanitizedRef}_${DateTime.now().millisecondsSinceEpoch}.png';

      // XFile.fromData is 100% compatible across Mobile and Web!
      await Share.shareXFiles(
        [XFile.fromData(pngBytes, mimeType: 'image/png', name: fileName)],
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
