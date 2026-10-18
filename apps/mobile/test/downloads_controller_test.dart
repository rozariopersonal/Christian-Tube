import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/downloads/controllers/downloads_controller.dart';
import 'package:mobile/features/downloads/models/storage_breakdown.dart';
import 'package:mobile/features/engines/scripture/services/bible_download_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return Directory.systemTemp.path;
    });
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('StorageBreakdown formatting', () {
    test('formats zero bytes correctly', () {
      expect(StorageBreakdown.formatBytes(0), '0 B');
    });

    test('formats megabytes and gigabytes correctly', () {
      expect(StorageBreakdown.formatBytes(15 * 1024 * 1024), '15 MB');
      expect(StorageBreakdown.formatBytes(1500 * 1024 * 1024), '1.5 GB');
    });

    test('calculates percentage share correctly', () {
      const breakdown = StorageBreakdown(
        biblesBytes: 200,
        dictionariesBytes: 300,
        booksBytes: 500,
      );
      expect(breakdown.totalBytes, 1000);
      expect(breakdown.shareOf(200), 0.2);
      expect(breakdown.shareOf(500), 0.5);
    });
  });

  group('DownloadsController', () {
    late DownloadsController controller;

    setUp(() {
      controller = DownloadsController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('initializes with catalog bibles and dictionaries', () {
      final state = controller.state;
      expect(state.bibles, isNotEmpty);
      expect(state.dictionaries, isNotEmpty);
      expect(state.bibleLanguageFilter, 'All');
      expect(state.dictFilter, 'All');
      expect(state.bookLanguageFilter, 'All');
      expect(state.onlyInstalled, isFalse);
    });

    test('updates search and filter parameters properly', () {
      controller.setBibleSearch('tamil');
      expect(controller.state.bibleSearch, 'tamil');

      controller.setBibleLanguageFilter('Indian');
      expect(controller.state.bibleLanguageFilter, 'Indian');

      controller.setDictSearch('greek');
      expect(controller.state.dictSearch, 'greek');

      controller.setDictFilter('Biblical');
      expect(controller.state.dictFilter, 'Biblical');

      controller.setBookSearch('grace');
      expect(controller.state.bookSearch, 'grace');

      controller.setBookLanguageFilter('English');
      expect(controller.state.bookLanguageFilter, 'English');

      controller.toggleOnlyInstalled();
      expect(controller.state.onlyInstalled, isTrue);
    });

    test('protects default base Bible translation from deletion', () async {
      final result = await controller.deleteBible(BibleDownloadManager.defaultVersionId);
      expect(result, isFalse, reason: 'Default version must be protected');
    });

    test('isBookInstalled strictly checks installedBookIds', () {
      expect(controller.isBookInstalled('unknown_book'), isFalse);
    });

    test('error state and clearError work as expected', () {
      expect(controller.state.errorMessage, isNull);
      controller.clearError();
      expect(controller.state.errorMessage, isNull);
    });
  });
}
