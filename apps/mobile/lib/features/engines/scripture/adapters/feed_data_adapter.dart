import 'package:flutter/foundation.dart';

abstract class FeedDataAdapter {
  ValueNotifier<double> get downloadProgress;
  Future<void> initialize();
  Future<List<Map<String, dynamic>>> getRandomItems(
    int limit, {
    int offset = 0,
    String? bookFilter,
    String? testamentFilter,
    List<String>? categoryFilter,
    List<String>? tagFilter,
    String order = 'random',
    List<String>? excludeIds,
  });
}
