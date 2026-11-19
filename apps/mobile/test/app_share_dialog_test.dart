import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/profile/models/app_promo_content.dart';
import 'package:mobile/features/profile/services/app_share_exporter.dart';
import 'package:mobile/features/profile/widgets/app_promo_poster.dart';
import 'package:mobile/features/profile/widgets/app_share_dialog.dart';

Widget _wrapWithApp(
  Widget child, {
  ThemeData? theme,
  Locale? locale,
}) {
  return MaterialApp(
    locale: locale,
    theme: theme ??
        ThemeData.light().copyWith(
          extensions: const [AppTokens.light],
        ),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 720, maxWidth: 640),
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  group('AppPromoCatalog unit tests', () {
    test('provides localized content and 6 features for all 6 app languages',
        () {
      expect(
        AppPromoCatalog.supportedLanguageCodes,
        equals(['en', 'ta', 'hi', 'te', 'kn', 'ml']),
      );

      for (final code in AppPromoCatalog.supportedLanguageCodes) {
        final content =
            AppPromoCatalog.forLanguage(code, instanceId: 'christian_tube');
        expect(content.languageCode, equals(code));
        expect(content.subtitle, isNotEmpty);
        expect(content.scanPrompt, isNotEmpty);
        expect(content.features, hasLength(6));
        for (final feature in content.features) {
          expect(feature.title, isNotEmpty);
          expect(feature.description, isNotEmpty);
        }

        final shareText = content.buildShareText(
          appName: 'ChristianApp',
          version: '2.0.0',
          webAppUrl: 'https://christianapp.vercel.app',
          downloadUrl: 'https://example.com/christian-app.apk',
        );
        expect(shareText, contains('v2.0.0'));
        expect(shareText, contains('https://christianapp.vercel.app'));
        expect(shareText, contains('https://example.com/christian-app.apk'));
      }
    });

    test('normalizes locale strings and falls back safely to English', () {
      expect(AppPromoCatalog.normalizeLanguageCode('ta_IN'), equals('ta'));
      expect(AppPromoCatalog.normalizeLanguageCode('hi-IN'), equals('hi'));
      expect(AppPromoCatalog.normalizeLanguageCode('fr'), equals('en'));
      expect(AppPromoCatalog.normalizeLanguageCode(null), equals('en'));
    });

    test('uses generic copy for non-christian_tube white-label instances', () {
      final content = AppPromoCatalog.forLanguage(
        'en',
        instanceId: 'centum_academy',
      );
      expect(content.attribution, equals(AppConfig.appName));
    });
  });

  group('AppShareDialog responsive & language toggle tests', () {
    const viewports = [320.0, 600.0, 840.0, 1400.0];

    for (final width in viewports) {
      testWidgets('renders without overflow at width $width', (tester) async {
        tester.view.physicalSize = Size(width * 2, 900 * 2);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          _wrapWithApp(
            const AppShareDialog(customVersion: '2.0.0'),
            theme: ThemeData.dark().copyWith(
              extensions: const [AppTokens.dark],
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(AppPromoPoster), findsOneWidget);
        expect(find.text('Share Promo Poster'), findsOneWidget);
      });
    }

    testWidgets('toggles all 6 languages and updates poster content',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _wrapWithApp(
          const AppShareDialog(
            customVersion: '2.0.0',
            initialLanguageCode: 'en',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Starts in English
      expect(find.text('All CFC Content in one App'), findsOneWidget);
      expect(find.text('Features'), findsOneWidget);

      // Switch to Tamil
      await tester.ensureVisible(find.text('தமிழ்'));
      await tester.tap(find.text('தமிழ்'));
      await tester.pumpAndSettle();
      expect(find.text('அனைத்து CFC உள்ளடக்கமும் ஒரே ஆப்பில்'), findsOneWidget);
      expect(find.text('அம்சங்கள்'), findsOneWidget);

      // Switch to Hindi
      await tester.ensureVisible(find.text('हिन्दी'));
      await tester.tap(find.text('हिन्दी'));
      await tester.pumpAndSettle();
      expect(find.text('सारा CFC कंटेंट एक ही ऐप में'), findsOneWidget);
      expect(find.text('विशेषताएँ'), findsOneWidget);

      // Switch to Telugu
      await tester.ensureVisible(find.text('తెలుగు'));
      await tester.tap(find.text('తెలుగు'));
      await tester.pumpAndSettle();
      expect(find.text('CFC కంటెంట్ అంతా ఒకే యాప్‌లో'), findsOneWidget);

      // Switch to Kannada
      await tester.ensureVisible(find.text('ಕನ್ನಡ'));
      await tester.tap(find.text('ಕನ್ನಡ'));
      await tester.pumpAndSettle();
      expect(find.text('ಎಲ್ಲಾ CFC ವಿಷಯ ಒಂದೇ ಆ್ಯಪ್‌ನಲ್ಲಿ'), findsOneWidget);

      // Switch to Malayalam
      await tester.ensureVisible(find.text('മലയാളം'));
      await tester.tap(find.text('മലയാളം'));
      await tester.pumpAndSettle();
      expect(find.text('എല്ലാ CFC ഉള്ളടക്കവും ഒറ്റ ആപ്പിൽ'), findsOneWidget);
    });

    testWidgets('toggles QR target between Web App and Android APK',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _wrapWithApp(
          const AppShareDialog(
            customVersion: '2.0.0',
            initialLanguageCode: 'en',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('v2.0.0 • For Web & All Devices'), findsOneWidget);

      await tester.tap(find.text('Android APK').first);
      await tester.pumpAndSettle();

      expect(find.text('v2.0.0 • For Android'), findsOneWidget);
    });

    testWidgets('captures promotional poster PNG from RepaintBoundary',
        (tester) async {
      final boundaryKey = GlobalKey();
      final content = AppPromoCatalog.forLanguage(
        'ta',
        instanceId: 'christian_tube',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RepaintBoundary(
                key: boundaryKey,
                child: AppPromoPoster(
                  appName: 'ChristianApp',
                  version: '2.0.0',
                  qrData: 'https://christianapp.vercel.app',
                  targetLabel: content.targetWebLabel,
                  content: content,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bytes = await tester.runAsync(
        () => AppShareExporter.capturePosterPng(boundaryKey, pixelRatio: 1.0),
      );
      expect(bytes, isNotNull);
      expect(bytes!.length, greaterThan(1000));
    });
  });
}
