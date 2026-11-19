import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/app_config.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../models/app_promo_content.dart';
import '../services/app_share_exporter.dart';
import 'app_promo_poster.dart';

class AppShareDialog extends StatefulWidget {
  final String? customVersion;
  final String? initialLanguageCode;

  const AppShareDialog({
    super.key,
    this.customVersion,
    this.initialLanguageCode,
  });

  static Future<void> show(
    BuildContext context, {
    String? version,
    String? initialLanguageCode,
  }) {
    final transparent = context.tokens.surface.withValues(alpha: 0);
    return showAdaptiveBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: transparent,
      builder: (ctx) => AppShareDialog(
        customVersion: version,
        initialLanguageCode: initialLanguageCode,
      ),
    );
  }

  @override
  State<AppShareDialog> createState() => _AppShareDialogState();
}

class _AppShareDialogState extends State<AppShareDialog> {
  final GlobalKey _posterBoundaryKey = GlobalKey();
  bool _isSharing = false;
  bool _isCopied = false;
  bool _isWebCopied = false;
  bool _initializedLocale = false;
  int _selectedTargetIndex = 0; // 0 = Web App, 1 = Android APK
  late String _selectedLanguageCode;

  @override
  void initState() {
    super.initState();
    _selectedLanguageCode = AppPromoCatalog.normalizeLanguageCode(
      widget.initialLanguageCode,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedLocale) {
      _initializedLocale = true;
      if (widget.initialLanguageCode == null) {
        final activeCode = Localizations.maybeLocaleOf(context)?.languageCode;
        _selectedLanguageCode =
            AppPromoCatalog.normalizeLanguageCode(activeCode);
      }
      precacheImage(const AssetImage('assets/logo.png'), context)
          .catchError((_) {});
    }
  }

  String get _appVersion => widget.customVersion ?? AppConfig.version;

  String get _webAppUrl => AppConfig.shareBaseUrl;

  String get _downloadUrl {
    if (AppConfig.releasesRepo.isNotEmpty && AppConfig.apkFileName.isNotEmpty) {
      return 'https://github.com/${AppConfig.releasesRepo}/releases/latest/download/${AppConfig.apkFileName}';
    }
    return '${AppConfig.apiBaseUrl}/download';
  }

  String get _activeQrData =>
      _selectedTargetIndex == 0 ? _webAppUrl : _downloadUrl;

  String get _releasePageUrl {
    if (AppConfig.releasesRepo.isNotEmpty) {
      return 'https://github.com/${AppConfig.releasesRepo}/releases/latest';
    }
    return _downloadUrl;
  }

  AppPromoContent get _promoContent =>
      AppPromoCatalog.forLanguage(_selectedLanguageCode);

  String get _activeTargetLabel => _selectedTargetIndex == 0
      ? _promoContent.targetWebLabel
      : _promoContent.targetAndroidLabel;

  String get _shareText => _promoContent.buildShareText(
        appName: AppConfig.appName,
        version: _appVersion,
        webAppUrl: _webAppUrl,
        downloadUrl: _downloadUrl,
      );

  String get _shareSubject =>
      '${AppConfig.appName} - Web App & Android Download';

  Future<void> _copyUrl(String url, bool isWeb) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    setState(() {
      if (isWeb) {
        _isWebCopied = true;
      } else {
        _isCopied = true;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              color: Theme.of(context).colorScheme.onPrimary,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isWeb
                    ? 'Web app link copied to clipboard!'
                    : 'Android download link copied to clipboard!',
                style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
              ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          if (isWeb) {
            _isWebCopied = false;
          } else {
            _isCopied = false;
          }
        });
      }
    });
  }

  Future<void> _sharePosterAndLinks() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      await AppShareExporter.sharePosterAndLinks(
        boundaryKey: _posterBoundaryKey,
        languageCode: _selectedLanguageCode,
        shareText: _shareText,
        subject: _shareSubject,
        context: context,
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _shareTextLink() async {
    await Share.share(_shareText, subject: _shareSubject);
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
    final tokens = context.tokens;

    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: tokens.scrim.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.paddingOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: tokens.surfaceBorder,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 12),

          // Header Title
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Share ${AppConfig.appName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Promo poster, QR code & links (v$_appVersion)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
                tooltip: 'Close',
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Scrollable body: target + language toggles, poster preview, copyable links
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // QR Target Selector (Web App vs Android APK)
                  Container(
                    decoration: BoxDecoration(
                      color: tokens.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 4,
                      children: [
                        _buildTargetPill(
                          context: context,
                          title: 'Web App',
                          icon: Icons.language_rounded,
                          isSelected: _selectedTargetIndex == 0,
                          onTap: () => setState(() => _selectedTargetIndex = 0),
                        ),
                        _buildTargetPill(
                          context: context,
                          title: 'Android APK',
                          icon: Icons.android_rounded,
                          isSelected: _selectedTargetIndex == 1,
                          onTap: () => setState(() => _selectedTargetIndex = 1),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Poster Language Toggle Strip (all 6 supported app languages)
                  _buildLanguageSelector(context),
                  const SizedBox(height: 12),

                  // Scaled Full Promotional Poster Preview (high-res RepaintBoundary inside)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: tokens.surfaceBorder,
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SizedBox(
                            width: constraints.maxWidth,
                            child: FittedBox(
                              fit: BoxFit.fitWidth,
                              alignment: Alignment.topCenter,
                              child: RepaintBoundary(
                                key: _posterBoundaryKey,
                                child: AppPromoPoster(
                                  appName: AppConfig.appName,
                                  version: _appVersion,
                                  qrData: _activeQrData,
                                  targetLabel: _activeTargetLabel,
                                  content: _promoContent,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Links Card (Web App & Android APK)
                  Container(
                    decoration: BoxDecoration(
                      color: tokens.surfaceVariant,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: tokens.surfaceBorder,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildLinkRow(
                          context: context,
                          icon: Icons.language_rounded,
                          label: 'Web App',
                          url: _webAppUrl,
                          isCopied: _isWebCopied,
                          onCopy: () => _copyUrl(_webAppUrl, true),
                        ),
                        Divider(height: 1, color: tokens.surfaceBorder),
                        _buildLinkRow(
                          context: context,
                          icon: Icons.android_rounded,
                          label: 'Android APK',
                          url: _downloadUrl,
                          isCopied: _isCopied,
                          onCopy: () => _copyUrl(_downloadUrl, false),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Pinned Action Buttons
          Row(
            children: [
              // Primary: Share Promo Poster & Links
              Expanded(
                flex: 3,
                child: ElevatedButton(
                  onPressed: _isSharing ? null : _sharePosterAndLinks,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 2,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isSharing)
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.onPrimary,
                          ),
                        )
                      else
                        const Icon(Icons.share_rounded, size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _isSharing ? 'Preparing...' : 'Share Promo Poster',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Secondary: Share Link Only
              OutlinedButton.icon(
                onPressed: _shareTextLink,
                icon: const Icon(Icons.send_rounded, size: 16),
                label: const Text(
                  'Link',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                  side: BorderSide(
                    color: theme.colorScheme.primary.withValues(alpha: 0.5),
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Tertiary: Open in Browser
              IconButton(
                onPressed: _openReleaseInBrowser,
                icon: const Icon(Icons.open_in_browser_rounded),
                tooltip: 'Open in Browser',
                style: IconButton.styleFrom(
                  backgroundColor: tokens.surfaceVariant,
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
    );
  }

  Widget _buildLanguageSelector(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0;
              i < AppPromoCatalog.supportedLanguageCodes.length;
              i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Builder(
              builder: (context) {
                final code = AppPromoCatalog.supportedLanguageCodes[i];
                final isSelected = _selectedLanguageCode == code;
                final label = AppPromoCatalog.languageDisplayLabel(code);
                return GestureDetector(
                  onTap: () => setState(() => _selectedLanguageCode = code),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.colorScheme.primary
                          : tokens.surfaceVariant,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isSelected
                            ? theme.colorScheme.primary
                            : tokens.surfaceBorder,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : tokens.onSurface,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTargetPill({
    required BuildContext context,
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary
              : tokens.surfaceVariant.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? theme.colorScheme.onPrimary
                  : tokens.onSurfaceMuted,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : tokens.onSurfaceMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkRow({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String url,
    required bool isCopied,
    required VoidCallback onCopy,
  }) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: tokens.onSurfaceMuted,
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: onCopy,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isCopied ? Icons.check_rounded : Icons.copy_rounded,
                    size: 13,
                    color: isCopied
                        ? theme.colorScheme.tertiary
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    isCopied ? 'Copied' : 'Copy',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isCopied
                          ? theme.colorScheme.tertiary
                          : theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
