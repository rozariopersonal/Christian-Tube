import 'package:flutter/foundation.dart';
import 'package:mobile/shared/services/reader_appearance.dart';
import '../models/article_data.dart';
import '../services/article_sync_service.dart';

class ArticleReaderState {
  final bool isLoading;
  final bool hasError;
  final ArticleData? article;

  const ArticleReaderState({
    this.isLoading = true,
    this.hasError = false,
    this.article,
  });

  ArticleReaderState copyWith({
    bool? isLoading,
    bool? hasError,
    ArticleData? article,
  }) {
    return ArticleReaderState(
      isLoading: isLoading ?? this.isLoading,
      hasError: hasError ?? this.hasError,
      article: article ?? this.article,
    );
  }
}

class ArticleReaderController extends ChangeNotifier {
  final String articleId;
  final String lang;
  final ArticleSyncService _syncService;
  final ReaderAppearance appearance = ReaderAppearance();

  ArticleReaderState _state = const ArticleReaderState();
  ArticleReaderState get state => _state;

  ArticleReaderController(
    this.articleId, {
    this.lang = 'en',
    ArticleSyncService? syncService,
  }) : _syncService = syncService ?? ArticleSyncService() {
    appearance.addListener(notifyListeners);
    _init();
  }

  Future<void> _init() async {
    appearance.languageCode = lang;
    await appearance.loadFromPrefs();
    await loadArticle();
  }

  Future<void> loadArticle() async {
    _state = _state.copyWith(isLoading: true, hasError: false);
    notifyListeners();

    try {
      final data = await _syncService.getArticle(articleId, lang: lang);
      _state = _state.copyWith(isLoading: false, article: data);
    } catch (e) {
      _state = _state.copyWith(isLoading: false, hasError: true);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    appearance.removeListener(notifyListeners);
    super.dispose();
  }
}
