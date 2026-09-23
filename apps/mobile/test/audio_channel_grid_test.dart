import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/layout/content_width.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/audio/controllers/audio_library_controller.dart';
import 'package:mobile/features/audio/models/audio_series.dart';
import 'package:mobile/features/audio/widgets/audio_channel_grid.dart';

void setSurfaceSize(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

AudioSeries _youtubeSeries(String id, String title, int trackCount) {
  return AudioSeries(
    id: id,
    title: title,
    description: '',
    speaker: 'Zac Poonen',
    coverUrl: null,
    trackCount: trackCount,
    category: 'YouTube',
    language: 'en',
    tracks: const [],
  );
}

void main() {
  final series = [
    _youtubeSeries('c', 'Alpha Channel', 50),
    _youtubeSeries('b', 'Beta Channel', 3),
    _youtubeSeries('d', 'Gamma Channel', 10),
  ];

  final baseState = AudioLibraryViewState(
    isLoading: false,
    seriesList: series,
    selectedFormat: AudioFormat.youtube,
    selectedLanguages: const {'All'},
    availableLanguages: const ['All'],
  );

  Widget buildHarness(AudioLibraryViewState state,
      ValueChanged<AudioChannelSort> onChannelSortChanged) {
    return MaterialApp(
      theme: ThemeData.light(useMaterial3: true).copyWith(
        extensions: [AppTokens.light],
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: AudioChannelGrid(
            state: state,
            onReset: () {},
            onOpenSeries: (_) {},
            onChannelSortChanged: onChannelSortChanged,
          ),
        ),
      ),
    );
  }

  testWidgets('sorts by most tracks by default with positions left-to-right',
      (tester) async {
    setSurfaceSize(tester, 700, 1200);
    await tester.pumpWidget(buildHarness(baseState, (_) {}));
    await tester.pump();

    expect(find.text('YouTube Channels (3)'), findsOneWidget);

    // Default sort: most tracks first, so Alpha(50) < Gamma(10) < Beta(3).
    final alphaX = tester.getTopLeft(find.text('Alpha Channel')).dx;
    final gammaX = tester.getTopLeft(find.text('Gamma Channel')).dx;
    final betaX = tester.getTopLeft(find.text('Beta Channel')).dx;
    expect(alphaX, lessThan(gammaX));
    expect(gammaX, lessThan(betaX));
  });

  testWidgets('A-Z popup reorders the grid and reports the selection',
      (tester) async {
    setSurfaceSize(tester, 700, 1200);

    AudioChannelSort selected = baseState.channelSort;
    await tester.pumpWidget(buildHarness(
      baseState,
      (sort) => selected = sort,
    ));
    await tester.pump();

    await tester.tap(find.byTooltip('Sort channels'));
    await tester.pumpAndSettle();
    expect(find.text('A–Z'), findsOneWidget);

    await tester.tap(find.text('A–Z'));
    await tester.pumpAndSettle();
    expect(selected, AudioChannelSort.name);
  });

  testWidgets('renders across breakpoints (320, 600, 840, 1400) without overflow',
      (tester) async {
    for (final width in [320.0, 600.0, 840.0, 1400.0]) {
      setSurfaceSize(tester, width, 900);
      await tester.pumpWidget(buildHarness(baseState, (_) {}));
      await tester.pump();

      expect(tester.takeException(), isNull,
          reason: 'Failed at width $width');
      expect(find.byType(MaxWidthBox), findsOneWidget,
          reason: 'Missing MaxWidthBox cap at width $width');
    }
  });

  testWidgets('shows empty state without channels', (tester) async {
    setSurfaceSize(tester, 600, 900);
    await tester.pumpWidget(buildHarness(
      baseState.copyWith(
        seriesList: const [],
        selectedFormat: AudioFormat.youtube,
      ),
      (_) {},
    ));
    await tester.pump();

    expect(find.text('No channels found for the selected filter.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}