import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/admin/models/promotion_status.dart';
import 'package:mobile/features/admin/services/release_promotion_service.dart';
import 'package:mobile/features/admin/widgets/promotion_sheet.dart';

class StubReleasePromotionService extends ReleasePromotionService {
  final Future<PromotionStatus> Function()? onFetchStatus;
  final Future<String> Function()? onPromote;

  StubReleasePromotionService({
    this.onFetchStatus,
    this.onPromote,
  });

  @override
  Future<PromotionStatus> fetchStatus() async {
    if (onFetchStatus != null) {
      return onFetchStatus!();
    }
    return const PromotionStatus(
      canPromote: true,
      isBuilding: false,
      aheadCount: 2,
      latestProductionTag: 'v1.0.0',
      commits: [
        PendingCommit(
          sha: 'abc1234',
          message: 'feat: add audio playback',
          author: 'Arul',
        ),
        PendingCommit(
          sha: 'def5678',
          message: 'fix: audio buffer',
          author: 'Arul',
        ),
      ],
    );
  }

  @override
  Future<String> promoteToProduction() async {
    if (onPromote != null) {
      return onPromote!();
    }
    return 'Promotion started!';
  }
}

Widget buildTestWidget({
  required ReleasePromotionService service,
  required Size size,
  Brightness brightness = Brightness.dark,
}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      theme: ThemeData(
        brightness: brightness,
        extensions: const [AppTokens.dark],
      ),
      home: Scaffold(
        body: Center(
          child: PromotionSheet(service: service),
        ),
      ),
    ),
  );
}

void main() {
  group('PromotionSheet Widget Tests', () {
    for (final width in [320.0, 600.0, 840.0, 1400.0]) {
      testWidgets('renders without overflow at ${width.toInt()}dp viewport',
          (tester) async {
        final size = Size(width, 800.0);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final service = StubReleasePromotionService();
        await tester.pumpWidget(
          buildTestWidget(service: service, size: size),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Promote to Production'), findsOneWidget);
        expect(find.text('Commits to Promote (2)'), findsOneWidget);
        expect(find.text('feat: add audio playback'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('shows up to date status when aheadCount is 0', (tester) async {
      const size = Size(400.0, 800.0);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = StubReleasePromotionService(
        onFetchStatus: () async => const PromotionStatus(
          canPromote: false,
          isBuilding: false,
          aheadCount: 0,
          latestProductionTag: 'v1.0.0',
          commits: [],
        ),
      );

      await tester.pumpWidget(
        buildTestWidget(service: service, size: size),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Up to Date'), findsOneWidget);
      expect(find.text('No action needed. Production is already current.'),
          findsOneWidget);
    });

    testWidgets('shows release in progress when isBuilding is true',
        (tester) async {
      const size = Size(400.0, 800.0);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = StubReleasePromotionService(
        onFetchStatus: () async => const PromotionStatus(
          canPromote: false,
          isBuilding: true,
          aheadCount: 1,
          latestProductionTag: 'v1.0.0',
          commits: [],
        ),
      );

      await tester.pumpWidget(
        buildTestWidget(service: service, size: size),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Build in Progress'), findsOneWidget);
      expect(
        find.text(
            'A production build is currently in flight on GitHub Actions.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'two-step confirmation toggles release button and initiates promotion',
        (tester) async {
      const size = Size(400.0, 800.0);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool promoted = false;
      final service = StubReleasePromotionService(
        onPromote: () async {
          promoted = true;
          return 'Release initiated!';
        },
      );

      await tester.pumpWidget(
        buildTestWidget(service: service, size: size),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final checkbox = find.byType(Checkbox);
      expect(checkbox, findsOneWidget);

      // Tap checkbox to confirm
      await tester.tap(checkbox);
      await tester.pump();

      // Tap release button
      final releaseBtn = find.widgetWithText(FilledButton, 'Confirm & Release to Production');
      expect(releaseBtn, findsOneWidget);
      await tester.tap(releaseBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(promoted, isTrue);
      expect(find.text('Production Release Initiated!'), findsOneWidget);
    });
  });
}
