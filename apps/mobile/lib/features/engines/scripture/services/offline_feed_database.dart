import 'dart:async';
import 'package:flutter/foundation.dart';
import '../adapters/feed_data_adapter.dart';
import '../adapters/sqlite_feed_data_adapter.dart';
import '../adapters/web_feed_data_adapter.dart';

class OfflineFeedDatabase {
  static final OfflineFeedDatabase _instance = OfflineFeedDatabase._internal();
  factory OfflineFeedDatabase() => _instance;

  late final FeedDataAdapter _adapter;
  
  bool _isInitializing = false;
  Future<void>? _initFuture;
  
  // Expose initialization state so UI can show a loading spinner
  bool get isInitializing => _isInitializing;
  ValueNotifier<double> get downloadProgress => _adapter.downloadProgress;

  OfflineFeedDatabase._internal() {
    if (kIsWeb) {
      _adapter = WebFeedDataAdapter();
    } else {
      _adapter = SqliteFeedDataAdapter();
    }
  }

  Future<void> initialize() async {
    final inFlight = _initFuture;
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {}
      return;
    }

    final completer = Completer<void>();
    _initFuture = completer.future;
    _isInitializing = true;
    try {
      await _adapter.initialize();
      completer.complete();
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _isInitializing = false;
      _initFuture = null;
    }
  }

  Future<List<Map<String, dynamic>>> getRandomItems(
    int limit, {
    String? bookFilter,
    String? testamentFilter,
    List<String>? excludeIds,
  }) async {
    return _adapter.getRandomItems(
      limit,
      bookFilter: bookFilter,
      testamentFilter: testamentFilter,
      excludeIds: excludeIds,
    );
  }
}
