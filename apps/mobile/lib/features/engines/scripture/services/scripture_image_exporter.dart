import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import '../models/scripture_card.dart';
import '../models/scripture_theme_state.dart';
import 'bible_download_manager.dart';
import 'file_saver.dart';
import 'scripture_service.dart';

class ScriptureGraphicGenerator {
  /// Generates a pristine 1080x1920 (9:16 Story format) graphic card from content data
  static Future<Uint8List> generateStoryImage({
    required ScriptureCard card,
    required String activeVersionId,
    required String fontFamily,
    required double fontSizeScale,
    String textColorHex = '#FFFFFF',
    bool isBold = false,
    bool isItalic = false,
    String textAlign = 'center',
    int width = 1080,
    int height = 1920,
    String appName = 'ChristianApp',
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );

    // Ensure card text is strictly synced with activeVersionId
    if (card.resolvedVersion != activeVersionId) {
      await ScriptureService().resolveCardText(card, activeVersionId);
    }

    final w = width.toDouble();
    final h = height.toDouble();
    final preset = ScriptureThemeCatalog.getPreset(card.activeBackground);
    final versionMeta = BibleDownloadManager.getMeta(
        card.resolvedVersion ?? activeVersionId);

    // 1. Draw Background (High-Res Image or Procedural Gradient)
    ui.Image? loadedImage;
    if (!preset.isGradient && preset.imageUrl != null) {
      loadedImage = await _fetchUiImage(preset.imageUrl!);
    }

    if (loadedImage != null) {
      _drawImageCover(canvas, loadedImage, w, h);
    } else {
      final colors = preset.gradientColors ??
          const [Color(0xFF0F172A), Color(0xFF020617), Color(0xFF000000)];
      final bgPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(w, h),
          colors,
        );
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), bgPaint);
    }

    // 2. Draw Multi-Stop Readability Dark Scrim Overlay
    final scrimPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(0, h),
        [
          const Color(0xAA000000), // Top 67% black
          const Color(0x99000000), // Center 60% black
          const Color(0xBF000000), // Mid-bottom 75% black
          const Color(0xF2000000), // Bottom 95% black
        ],
        [0.0, 0.30, 0.65, 1.0],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), scrimPaint);

    // 3. Layout Verse Typography with TextPainter
    final verseText = card.resolvedText ??
        'Peace I leave with you; my peace I give you. Do not let your hearts be troubled.';
    
    final words = verseText.split(RegExp(r'\s+'));
    int maxWordLength = 0;
    for (final w in words) {
      if (w.length > maxWordLength) maxWordLength = w.length;
    }

    final length = verseText.length;
    double baseFontSize =
        (60.0 - (length / 22.0)).clamp(32.0, 60.0) * fontSizeScale;

    // Adapt font size for long compound words so they never break
    if (maxWordLength > 12) {
      final penalty = (maxWordLength - 12) * 1.4;
      baseFontSize = (baseFontSize - penalty).clamp(26.0, 60.0);
    }

    final textColor = ScriptureThemeCatalog.parseColor(textColorHex);
    final fontWeight = isBold ? FontWeight.w700 : FontWeight.w400;
    final fontStyle = isItalic ? FontStyle.italic : FontStyle.normal;

    final TextAlign align;
    switch (textAlign) {
      case 'left':
        align = TextAlign.left;
        break;
      case 'right':
        align = TextAlign.right;
        break;
      case 'center':
      default:
        align = TextAlign.center;
        break;
    }

    final textStyle = ScriptureThemeCatalog.getTextStyle(
      fontFamily: card.customFontFamily ?? fontFamily,
      languageCode: versionMeta.languageCode,
      baseSize: baseFontSize,
      color: textColor,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
    );

    // Opening Quote Mark TextPainter
    final quotePainter = TextPainter(
      text: const TextSpan(
        text: '“',
        style: TextStyle(
          fontSize: 96,
          fontFamily: 'serif',
          color: Color(0xFFF59E0B),
          height: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: w - 160);

    // Verse Body TextPainter
    final textPainter = TextPainter(
      text: TextSpan(
        text: verseText,
        style: textStyle.copyWith(
          height: 1.45,
          shadows: [
            const Shadow(
              color: Colors.black,
              blurRadius: 24,
              offset: Offset(0, 4),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      textWidthBasis: TextWidthBasis.parent,
    )..layout(maxWidth: w - 160);

    // Reference Badge TextPainter
    final refText =
        '— ${card.referenceLabel} (${card.resolvedVersion ?? activeVersionId}) —';
    final refPainter = TextPainter(
      text: TextSpan(
        text: refText,
        style: const TextStyle(
          color: Color(0xFFFBBF24),
          fontSize: 28,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: w - 240);

    // Calculate Vertical Centering
    final totalContentHeight = quotePainter.height +
        24 +
        textPainter.height +
        40 +
        refPainter.height +
        20;
    final startY = (h - totalContentHeight) / 2.0;

    // Draw Quote Mark
    quotePainter.paint(
      canvas,
      Offset((w - quotePainter.width) / 2.0, startY),
    );

    // Draw Verse Text
    final textX = (align == TextAlign.center)
        ? (w - textPainter.width) / 2.0
        : (align == TextAlign.left)
            ? 120.0
            : w - 120.0 - textPainter.width;

    textPainter.paint(
      canvas,
      Offset(textX, startY + quotePainter.height + 24),
    );

    // Draw Reference Badge Pill
    final badgeY =
        startY + quotePainter.height + 24 + textPainter.height + 40;
    final badgeWidth = refPainter.width + 48;
    final badgeHeight = refPainter.height + 20;
    final badgeX = (w - badgeWidth) / 2.0;

    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(badgeX, badgeY, badgeWidth, badgeHeight),
      const Radius.circular(30),
    );

    final badgeBgPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5);
    canvas.drawRRect(badgeRect, badgeBgPaint);

    final badgeBorderPaint = Paint()
      ..color = const Color(0xFFF59E0B).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRRect(badgeRect, badgeBorderPaint);

    refPainter.paint(
      canvas,
      Offset((w - refPainter.width) / 2.0, badgeY + 10),
    );

    // 4. Draw Official Brand Watermark
    final watermarkPainter = TextPainter(
      text: TextSpan(
        text: '✦  $appName Words',
        style: const TextStyle(
          color: Color(0xFFFBBF24),
          fontSize: 24,
          fontWeight: FontWeight.w600,
          letterSpacing: 2.5,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: w);

    watermarkPainter.paint(
      canvas,
      Offset((w - watermarkPainter.width) / 2.0, h - 90),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  static void _drawImageCover(
      Canvas canvas, ui.Image image, double targetW, double targetH) {
    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();

    final scale = (targetW / imgW > targetH / imgH)
        ? (targetW / imgW)
        : (targetH / imgH);
    final scaledW = imgW * scale;
    final scaledH = imgH * scale;

    final srcRect = Rect.fromLTWH(0, 0, imgW, imgH);
    final dstRect = Rect.fromLTWH(
      (targetW - scaledW) / 2.0,
      (targetH - scaledH) / 2.0,
      scaledW,
      scaledH,
    );

    canvas.drawImageRect(image, srcRect, dstRect, Paint());
  }

  static Future<ui.Image?> _fetchUiImage(String url) async {
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final codec = await ui.instantiateImageCodec(response.bodyBytes);
        final frame = await codec.getNextFrame();
        return frame.image;
      }
    } catch (_) {}
    return null;
  }
}

class ScriptureImageExporter {
  static Future<void> captureAndShare({
    BuildContext? context,
    required GlobalKey boundaryKey,
    required ScriptureCard card,
    String activeVersionId = 'WEB',
    String fontFamily = 'Playfair',
    double fontSizeScale = 1.0,
    String textColorHex = '#FFFFFF',
    bool isBold = false,
    bool isItalic = false,
    String textAlign = 'center',
    String appName = 'ChristianApp',
  }) async {
    try {
      final currentKey =
          '${card.id}_${activeVersionId}_${fontFamily}_${fontSizeScale}_${textColorHex}_${card.activeBackground}';

      // 1. Use pre-created image from memory (0ms instant) or generate if not ready
      Uint8List pngBytes;
      if (card.precomputedImageBytes != null &&
          card.precomputedImageKey == currentKey) {
        pngBytes = card.precomputedImageBytes!;
      } else {
        pngBytes = await ScriptureGraphicGenerator.generateStoryImage(
          card: card,
          activeVersionId: activeVersionId,
          fontFamily: fontFamily,
          fontSizeScale: fontSizeScale,
          textColorHex: textColorHex,
          isBold: isBold,
          isItalic: isItalic,
          textAlign: textAlign,
          appName: appName,
        );
        card.precomputedImageBytes = pngBytes;
        card.precomputedImageKey = currentKey;
      }

      final sanitizedRef =
          card.referenceLabel.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final fileName =
          'verse_${sanitizedRef}_${DateTime.now().millisecondsSinceEpoch}.png';
      final shareText =
          '“${card.resolvedText ?? ""}”\n\n— ${card.referenceLabel} (${card.resolvedVersion ?? activeVersionId})\n\nShared via $appName';

      // 2. Directly show the native / platform Share Dialog with the pre-created image!
      final xFile = XFile.fromData(
        pngBytes,
        mimeType: 'image/png',
        name: fileName,
      );

      final result = await Share.shareXFiles(
        [xFile],
        text: shareText,
        subject: card.referenceLabel,
      );

      // On Web desktop where native share API is unavailable or dismissed, provide direct seamless download & clipboard copy
      if (kIsWeb && result.status == ShareResultStatus.unavailable) {
        await saveOrDownloadFile(pngBytes, fileName);
        await Clipboard.setData(ClipboardData(text: shareText));
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved $fileName & copied text to clipboard!'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error triggering share dialog: $e');
      final sanitizedRef =
          card.referenceLabel.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final fileName =
          'verse_${sanitizedRef}_${DateTime.now().millisecondsSinceEpoch}.png';
      final pngBytes = card.precomputedImageBytes ??
          await ScriptureGraphicGenerator.generateStoryImage(
            card: card,
            activeVersionId: activeVersionId,
            fontFamily: fontFamily,
            fontSizeScale: fontSizeScale,
            textColorHex: textColorHex,
            isBold: isBold,
            isItalic: isItalic,
            textAlign: textAlign,
            appName: appName,
          );
      await saveOrDownloadFile(pngBytes, fileName);
    }
  }
}
