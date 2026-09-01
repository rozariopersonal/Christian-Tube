import 'package:flutter/foundation.dart';

abstract class FeedDataAdapter {
  ValueNotifier<double> get downloadProgress;
  Future<void> initialize();
  Future<List<Map<String, dynamic>>> getRandomItems(
    int limit, {
    String? bookFilter,
    String? testamentFilter,
    List<String>? excludeIds,
  });
}
