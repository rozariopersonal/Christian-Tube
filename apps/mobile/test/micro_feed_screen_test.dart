import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/core/engines/base_feed_engine.dart';
import 'package:mobile/features/micro_feed/micro_feed_screen.dart';

class MockFeedEngine<T, F extends BaseFeedFilterState> extends Mock implements BaseFeedEngine<T, F> {}
class MockFilterState extends Mock implements BaseFeedFilterState {}
class FakeBuildContext extends Fake implements BuildContext {}
class FakeGlobalKey extends Fake implements GlobalKey {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeBuildContext());
    registerFallbackValue(FakeGlobalKey());
    registerFallbackValue(MockFilterState());
  });

  late MockFeedEngine<String, MockFilterState> mockEngine;
  late MockFilterState mockFilterState;

  setUp(() {
    mockEngine = MockFeedEngine<String, MockFilterState>();
    mockFilterState = MockFilterState();

    when(() => mockEngine.engineType).thenReturn('mock');
    when(() => mockEngine.defaultTabTitle).thenReturn('Mock Feed');
    when(() => mockEngine.defaultTabIcon).thenReturn(Icons.circle);
    when(() => mockEngine.initialFilterState).thenReturn(mockFilterState);
    when(() => mockEngine.buildTopControls(any(), any(), any(), any())).thenReturn(const SizedBox.shrink());
    when(() => mockEngine.buildSideActions(any(), any(), any(), any(), any(), any())).thenReturn([]);
    when(() => mockEngine.buildCard(any(), any(), any(), any(), any())).thenAnswer(
      (invocation) => Text('Card ${invocation.positionalArguments[1]}', key: ValueKey(invocation.positionalArguments[1])),
    );
  });

  Widget buildSubject() {
    return MaterialApp(
      home: Scaffold(
        body: MicroFeedScreen<String, MockFilterState>(
          engine: mockEngine,
        ),
      ),
    );
  }

  testWidgets('MicroFeedScreen shows loading indicator initially', (tester) async {
    final completer = Completer<void>();
    when(() => mockEngine.initialize()).thenAnswer((_) => completer.future);

    await tester.pumpWidget(buildSubject());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    
    completer.complete();
    when(() => mockEngine.fetchItems(filterState: any(named: 'filterState'), page: any(named: 'page')))
        .thenAnswer((_) async => []);
    
    await tester.pumpAndSettle();
  });

  testWidgets('MicroFeedScreen renders feed items on successful load', (tester) async {
    when(() => mockEngine.initialize()).thenAnswer((_) async => {});
    when(() => mockEngine.fetchItems(filterState: any(named: 'filterState'), page: any(named: 'page')))
        .thenAnswer((_) async => ['Item 1', 'Item 2']);

    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    expect(find.text('Card Item 1'), findsOneWidget);
  });

  testWidgets('MicroFeedScreen shows error widget on initialization failure', (tester) async {
    when(() => mockEngine.initialize()).thenThrow(Exception('Failed to init'));

    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    expect(find.text('Failed to load feed. Please try again.'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
  });
}
