import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/layout/content_width.dart';

class AppShareDialog extends StatefulWidget {
  final String? customVersion;

  const AppShareDialog({super.key, this.customVersion});

  static Future<void> show(BuildContext context, {String? version}) {
    return showAdaptiveBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AppShareDialog(customVersion: version),
    );
  }

  @override
  State<AppShareDialog> createState() => _AppShareDialogState();
}

class _AppShareDialogState extends State<AppShareDialog> {
  final GlobalKey _qrCardKey = GlobalKey();
  bool _isSharing = false;
  bool _isCopied = false;

  String get _appVersion => widget.customVersion ?? AppConfig.version;

  String get _downloadUrl {
    if (AppConfig.releasesRepo.isNotEmpty && AppConfig.apkFileName.isNotEmpty) {
      return 'https://github.com/${AppConfig.releasesRepo}/releases/latest/download/${AppConfig.apkFileName}';
    }
    return '${AppConfig.apiBaseUrl}/download';
  }

  String get _releasePageUrl {
    if (AppConfig.releasesRepo.isNotEmpty) {
      return 'https://github.com/${AppConfig.releasesRepo}/releases/latest';
    }
    return _downloadUrl;
  }

  String get _shareText =>
      'Download ${AppConfig.appName} (v$_appVersion) for Android to watch high quality Christian videos, shorts, devotions and words:\n$_downloadUrl';

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _downloadUrl));
    if (!mounted) return;
    setState(() => _isCopied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_outline, color: Theme.of(context).colorScheme.onPrimary, size: 18),
            const SizedBox(width: 8),
            Text(
              'Download link copied to clipboard!',
              style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isCopied = false);
    });
  }

  Future<void> _shareQrImageAndLink() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);

    try {
      final boundary =
          _qrCardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Unable to capture QR card');
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Image encoding failed');

      final pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final sanitizedInstance = AppConfig.instanceId.replaceAll(' ', '_').toLowerCase();
      final filePath = '${tempDir.path}/share_${sanitizedInstance}_qr.png';
      final file = File(filePath);
      await file.writeAsBytes(pngBytes);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: _shareText,
        subject: 'Download ${AppConfig.appName}',
      );
    } catch (e) {
      debugPrint('QR image share failed: $e, falling back to text share.');
      await Share.share(_shareText, subject: 'Download ${AppConfig.appName}');
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _shareTextLink() async {
    await Share.share(_shareText, subject: 'Download ${AppConfig.appName}');
  }

  Future<void> _openReleaseInBrowser() async {
    final uri = Uri.parse(_releasePageUrl);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error opening release url: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: context.tokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: context.tokens.scrim.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: context.tokens.surfaceBorder,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 16),

            // Header Title
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.qr_code_2_rounded,
                        color: theme.colorScheme.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Share ${AppConfig.appName}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Scan QR or share release link',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.tokens.onSurfaceMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 16),

            // BRANDED QR CARD (Surrounded by RepaintBoundary for high-res snapshotting)
            RepaintBoundary(
              key: _qrCardKey,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.grey.shade200,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Card Brand Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset(
                            'assets/logo.png',
                            height: 28,
                            width: 28,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.play_circle_fill,
                              color: theme.colorScheme.primary,
                              size: 28,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppConfig.appName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'v$_appVersion',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // QR CODE with EMBEDDED LOGO
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade100, width: 1),
                      ),
                      child: QrImageView(
                        data: _downloadUrl,
                        version: QrVersions.auto,
                        size: 200.0,
                        backgroundColor: Colors.white,
                        errorCorrectionLevel: QrErrorCorrectLevel.H,
                        embeddedImage: const AssetImage('assets/logo.png'),
                        embeddedImageStyle: const QrEmbeddedImageStyle(
                          size: Size(44, 44),
                        ),
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Color(0xFF0F172A),
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Scan Instructions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_outlined, size: 14, color: Colors.grey.shade700),
                        const SizedBox(width: 5),
                        Text(
                          'Point phone camera to download APK',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Download URL Container with Copy Action
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: context.tokens.surfaceVariant,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: context.tokens.surfaceBorder,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.link_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _downloadUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: context.tokens.onSurfaceMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _copyLink,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isCopied ? Icons.check_rounded : Icons.copy_rounded,
                            size: 16,
                            color: _isCopied ? Colors.green : theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isCopied ? 'Copied' : 'Copy',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _isCopied ? Colors.green : theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Action Buttons
            Row(
              children: [
                // Primary: Share QR & Link
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    onPressed: _isSharing ? null : _shareQrImageAndLink,
                    icon: _isSharing
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary),
                          )
                        : const Icon(Icons.share_rounded, size: 18),
                    label: Text(
                      _isSharing ? 'Preparing...' : 'Share QR & Link',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Secondary: Share Link Only
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    onPressed: _shareTextLink,
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text(
                      'Link',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.primary,
                      side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Tertiary: Open in Browser
                IconButton(
                  onPressed: _openReleaseInBrowser,
                  icon: const Icon(Icons.open_in_browser_rounded),
                  tooltip: 'Open in Browser',
                  style: IconButton.styleFrom(
                    backgroundColor: context.tokens.surfaceVariant,
                    padding: const EdgeInsets.all(12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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
