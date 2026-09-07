import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/features/articles/controllers/article_reader_controller.dart';
import 'package:mobile/features/articles/models/article_data.dart';
import 'package:mobile/features/articles/services/article_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockArticleSyncService extends Mock implements ArticleSyncService {}

const _article = ArticleData(
  id: '2024_10_26',
  title: 'Faith in Trials',
  date: '2024-10-26',
  author: 'Zac Poonen',
  lines: [
    ArticleLine(line: 1, text: 'Faith in Trials', isHeading: true, headingLevel: 1),
    ArticleLine(line: 2, text: 'Sometimes storms arrive unexpectedly.'),
  ],
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('starts in the loading state and resolves to the article on success',
      () async {
    final service = MockArticleSyncService();
    when(() => service.getArticle('2024_10_26'))
        .thenAnswer((_) async => _article);

    final controller = ArticleReaderController('2024_10_26', syncService: service);
    await pumpEventQueue();

    expect(controller.state.isLoading, isFalse);
    expect(controller.state.errorMessage, isNull);
    expect(controller.state.article?.title, 'Faith in Trials');
    expect(controller.state.article?.lines.length, 2);

    controller.dispose();
  });

  test('keeps the loading state while the fetch is in flight', () async {
    final service = MockArticleSyncService();
    final completer = Completer<ArticleData?>();
    when(() => service.getArticle('x')).thenAnswer((_) => completer.future);

    final controller = ArticleReaderController('x', syncService: service);
    await pumpEventQueue();
    expect(controller.state.isLoading, isTrue);

    completer.complete(_article);
    await pumpEventQueue();
    expect(controller.state.isLoading, isFalse);
    expect(controller.state.article, isNotNull);

    controller.dispose();
  });

  test('surfaces a user-friendly error message when the fetch fails', () async {
    final service = MockArticleSyncService();
    when(() => service.getArticle('x')).thenThrow(Exception('network down'));

    final controller = ArticleReaderController('x', syncService: service);
    await pumpEventQueue();

    expect(controller.state.isLoading, isFalse);
    expect(controller.state.errorMessage,
        'Connect to the internet to read this article.');
    expect(controller.state.article, isNull);

    controller.dispose();
  });

  test('loadArticle retry clears the error and reloads', () async {
    final service = MockArticleSyncService();
    var callCount = 0;
    when(() => service.getArticle('x')).thenAnswer((_) async {
      callCount++;
      if (callCount == 1) throw Exception('first attempt fails');
      return _article;
    });

    final controller = ArticleReaderController('x', syncService: service);
    await pumpEventQueue();
    expect(controller.state.errorMessage, isNotNull);

    await controller.loadArticle();
    expect(controller.state.errorMessage, isNull);
    expect(controller.state.article, isNotNull);

    controller.dispose();
  });
}