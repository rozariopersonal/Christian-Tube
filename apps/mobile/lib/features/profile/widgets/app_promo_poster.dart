import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/theme/app_tokens.dart';
import '../models/app_promo_content.dart';

/// Fixed-width promotional flyer widget matching the branded crimson-and-gold
/// layout with an embedded QR code (with white-bordered logo) and localized
/// feature highlights.
///
/// Designed to lay out at [posterWidth] logical pixels so `RepaintBoundary`
/// exports produce consistent, crisp high-resolution posters regardless of
/// device viewport width or active app theme.
class AppPromoPoster extends StatelessWidget {
  static const double posterWidth = 560;

  final String appName;
  final String version;
  final String qrData;
  final String targetLabel;
  final AppPromoContent content;

  const AppPromoPoster({
    super.key,
    required this.appName,
    required this.version,
    required this.qrData,
    required this.targetLabel,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: posterWidth,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              PromoPosterPalette.bannerTop,
              PromoPosterPalette.bannerBottom,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 32, 22, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildHeader(),
              const SizedBox(height: 26),
              _buildQrSection(),
              const SizedBox(height: 30),
              _buildFeaturesSection(),
              const SizedBox(height: 26),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          appName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 44,
            fontWeight: FontWeight.w800,
            height: 1.1,
            color: PromoPosterPalette.cream,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          content.subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w700,
            height: 1.3,
            color: PromoPosterPalette.qrSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildQrSection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          content.scanPrompt,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: PromoPosterPalette.cream,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: 280,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: PromoPosterPalette.qrSurface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 260,
                backgroundColor: PromoPosterPalette.qrSurface,
                errorCorrectionLevel: QrErrorCorrectLevel.H,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: PromoPosterPalette.qrForeground,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: PromoPosterPalette.qrForeground,
                ),
              ),
              Container(
                width: 60,
                height: 60,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: PromoPosterPalette.qrSurface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Image.asset(
                  'assets/logo.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.menu_book_rounded,
                    color: PromoPosterPalette.bannerBottom,
                    size: 36,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'v$version • $targetLabel',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: PromoPosterPalette.roseLight,
          ),
        ),
      ],
    );
  }

  Widget _buildFeaturesSection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          content.featuresHeading,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: PromoPosterPalette.gold,
          ),
        ),
        const SizedBox(height: 12),
        for (int i = 0; i < content.features.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _PromoFeatureCard(feature: content.features[i]),
        ],
      ],
    );
  }

  Widget _buildFooter() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: PromoPosterPalette.gold,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            content.shareBanner,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: PromoPosterPalette.goldInk,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          content.attribution,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            height: 1.5,
            color: PromoPosterPalette.roseMuted,
          ),
        ),
      ],
    );
  }
}

class _PromoFeatureCard extends StatelessWidget {
  final AppPromoFeature feature;

  const _PromoFeatureCard({required this.feature});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: PromoPosterPalette.cardOverlay,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: PromoPosterPalette.cardBorder,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: PromoPosterPalette.gold,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              feature.icon,
              size: 24,
              color: PromoPosterPalette.goldInk,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  feature.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                    color: PromoPosterPalette.cream,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  feature.description,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    height: 1.45,
                    color: PromoPosterPalette.roseLight,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
