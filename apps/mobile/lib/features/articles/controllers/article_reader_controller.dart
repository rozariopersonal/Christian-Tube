import 'package:flutter/foundation.dart';
import 'package:mobile/shared/services/reader_appearance.dart';
import '../models/article_data.dart';
import '../services/article_sync_service.dart';

class ArticleReaderState {
  final bool isLoading;
  final String? errorMessage;
  final ArticleData? article;

  const ArticleReaderState({
    this.isLoading = true,
    this.errorMessage,
    this.article,
  });

  ArticleReaderState copyWith({
    bool? isLoading,
    String? errorMessage,
    ArticleData? article,
    bool clearError = false,
  }) {
    return ArticleReaderState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      article: article ?? this.article,
    );
  }
}

class ArticleReaderController extends ChangeNotifier {
  final String articleId;
  final ArticleSyncService _syncService;
  final ReaderAppearance appearance = ReaderAppearance();

  ArticleReaderState _state = const ArticleReaderState();
  ArticleReaderState get state => _state;

  ArticleReaderController(this.articleId, {ArticleSyncService? syncService})
      : _syncService = syncService ?? ArticleSyncService() {
    appearance.addListener(notifyListeners);
    _init();
  }

  Future<void> _init() async {
    await appearance.loadFromPrefs();
    await loadArticle();
  }

  Future<void> loadArticle() async {
    _state = _state.copyWith(isLoading: true, clearError: true);
    notifyListeners();

    try {
      final data = await _syncService.getArticle(articleId);
      _state = _state.copyWith(isLoading: false, article: data);
    } catch (e) {
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: 'Connect to the internet to read this article.',
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    appearance.removeListener(notifyListeners);
    super.dispose();
  }
}
