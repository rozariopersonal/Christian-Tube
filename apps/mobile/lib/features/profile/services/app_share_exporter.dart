import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/config/app_config.dart';
import '../../engines/scripture/services/file_saver.dart';

/// Captures the promotional QR poster widget as a high-resolution PNG and
/// dispatches it via the native share sheet or Web download fallback.
class AppShareExporter {
  const AppShareExporter._();

  static Future<Uint8List?> capturePosterPng(
    GlobalKey boundaryKey, {
    double pixelRatio = 2.5,
  }) async {
    final boundary =
        boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  static Future<void> sharePosterAndLinks({
    required GlobalKey boundaryKey,
    required String languageCode,
    required String shareText,
    required String subject,
    BuildContext? context,
  }) async {
    try {
      final pngBytes = await capturePosterPng(boundaryKey);
      if (pngBytes == null) {
        throw Exception('Unable to capture promotional poster');
      }

      final sanitizedInstance =
          AppConfig.instanceId.replaceAll(' ', '_').toLowerCase();
      final fileName = '${sanitizedInstance}_promo_$languageCode.png';
      final xFile = XFile.fromData(
        pngBytes,
        mimeType: 'image/png',
        name: fileName,
      );

      Rect? sharePositionOrigin;
      if (boundaryKey.currentContext != null) {
        final box =
            boundaryKey.currentContext!.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          sharePositionOrigin = box.localToGlobal(Offset.zero) & box.size;
        }
      }

      final result = await Share.shareXFiles(
        [xFile],
        text: shareText,
        subject: subject,
        sharePositionOrigin: sharePositionOrigin,
      );

      if (kIsWeb && result.status == ShareResultStatus.unavailable) {
        await saveOrDownloadFile(pngBytes, fileName);
        await Clipboard.setData(ClipboardData(text: shareText));
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved $fileName & copied links to clipboard!'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Promo poster share failed: $e, falling back to text share.');
      await Share.share(shareText, subject: subject);
    }
  }
}
