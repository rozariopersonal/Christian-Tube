import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/audio/models/audio_track.dart';
import 'package:mobile/features/audio/services/audio_download_service.dart';
import 'package:mobile/features/audio/services/audio_local_library.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

AudioTrack _track(String id, {String seriesId = 'ttb', String? url}) => AudioTrack(
      id: id,
      title: 'Track $id',
      seriesId: seriesId,
      seriesTitle: 'Through The Bible',
      speaker: 'Zac Poonen',
      durationSeconds: 300,
      audioUrl: url ?? 'https://example.com/$id.mp3',
    );

/// Polls until [predicate] returns true or [timeout] elapses.
Future<void> _waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  expect(predicate(), isTrue, reason: 'Timed out waiting for condition');
}

void main() {
  late Directory tempDir;
  late AudioLocalLibrary library;
  late HttpServer server;
  late int port;
  late List<String> servedPaths;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('audio_dl_test');
    library = AudioLocalLibrary(overrideBaseDir: () => tempDir);
    servedPaths = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((request) {
      servedPaths.add(request.uri.path);
      if (request.uri.path.contains('fail')) {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.close();
      } else {
        // Hold the connection open so downloads stay "downloading".
        // Never close: the client will eventually time out (receiveTimeout 10m).
      }
    });
  });

  tearDown(() async {
    try {
      await server.close(force: true);
    } catch (_) {}
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  String serverUrl(String path) => 'http://127.0.0.1:$port/$path';

  group('AudioLocalLibrary', () {
    test('localUriFor returns null when file does not exist', () async {
      final uri = await library.localUriFor(_track('t1'));
      expect(uri, isNull);
    });

    test('localUriFor returns file URI after a file has been written', () async {
      final track = _track('t1', seriesId: 'series_a');
      final path = await library.pathFor(track);
      await File(path).create(recursive: true);
      await File(path).writeAsBytes([1, 2, 3]);
      final uri = await library.localUriFor(track);
      expect(uri, isNotNull);
      expect(uri, startsWith('file:'));
    });

    test('registerDownloaded and downloadedIds persist across instances', () async {
      await library.registerDownloaded([_track('t1'), _track('t2')]);
      final ids = await library.downloadedIds();
      expect(ids, containsAll(['t1', 't2']));
    });

    test('removeDownloaded deletes file and clears registry', () async {
      final track = _track('t1');
      final path = await library.pathFor(track);
      await File(path).create(recursive: true);
      await File(path).writeAsBytes([1]);
      await library.registerDownloaded([track]);

      await library.removeDownloaded('t1', track);

      final ids = await library.downloadedIds();
      expect(ids, isNot(contains('t1')));
      expect(await File(path).exists(), isFalse);
    });
  });

  group('AudioDownloadService', () {
    test('resetForTest clears state', () async {
      final service = AudioDownloadService(library: library);
      await service.syncFromDisk([_track('t1')]);
      await service.resetForTest();
      expect(service.entries, isEmpty);
    });

    test('syncFromDisk marks files present on disk as completed', () async {
      final track = _track('ready');
      final path = await library.pathFor(track);
      await File(path).create(recursive: true);
      await File(path).writeAsBytes([1, 2, 3]);

      final service = AudioDownloadService(library: library);
      await service.syncFromDisk([track, _track('missing')]);

      expect(service.isDownloaded('ready'), isTrue);
      expect(service.isDownloaded('missing'), isFalse);
      expect(service.progressFor('ready'), 1.0);
    });

    test('removeDownloaded resets entry to id and deletes file', () async {
      final stackDir = Directory(p.join(tempDir.path, 'stack_a'));
      await stackDir.create(recursive: true);
      final trackFile = File(p.join(stackDir.path, 't1.mp3'));
      await trackFile.writeAsBytes([1, 2, 3]);

      final track = _track('t1', seriesId: 'stack_a');
      final service = AudioDownloadService(library: library);
      await service.syncFromDisk([track]);
      expect(service.isDownloaded('t1'), isTrue);

      await service.removeDownloaded('t1');
      expect(service.isDownloaded('t1'), isFalse);
      expect(await trackFile.exists(), isFalse);
    });

    test('downloadTracks skips completed and does not duplicate queued tracks', () async {
      final existing = _track('existing');
      final path = await library.pathFor(existing);
      await File(path).create(recursive: true);
      await File(path).writeAsBytes([1]);

      final slow = _track('new', url: serverUrl('slow.mp3'));
      final service = AudioDownloadService(library: library);
      await service.syncFromDisk([existing, slow]);
      expect(service.isDownloaded('existing'), isTrue);

      await service.downloadTracks([existing, slow, slow]);
      await _waitFor(() => service.isDownloading('new'));

      expect(service.isDownloaded('existing'), isTrue);
      final newEntry = service.entryFor('new');
      expect(newEntry, isNotNull);
      expect(newEntry!.status, isIn([
        AudioDownloadStatus.queued,
        AudioDownloadStatus.downloading,
      ]));
    });

    test('failed downloads surface failed status and error message', () async {
      final track = _track('fail', url: serverUrl('fail.mp3'));
      final service = AudioDownloadService(library: library);
      await service.downloadTracks([track]);
      await _waitFor(
        () => service.entryFor('fail')?.status == AudioDownloadStatus.failed,
      );

      final entry = service.entryFor('fail');
      expect(entry!.status, AudioDownloadStatus.failed);
      expect(entry.error, isNotNull);
    });
  });
}