import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import '../../../core/api/github_data_service.dart';
import '../models/audio_series.dart';
import '../models/audio_track.dart';

/// Fetches CFC India audio series metadata from local source assets (with CDN fallback)
/// while streaming URLs point directly to live cfcindia.org servers.
class AudioCatalogService {
  final http.Client _client;
  static List<AudioSeries>? _cachedCatalog;
  static final Map<String, AudioSeries> _cachedSeries = {};

  AudioCatalogService({http.Client? client}) : _client = client ?? http.Client();

  /// Loads the top-level audio catalog.
  Future<List<AudioSeries>> getCatalog({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedCatalog != null && _cachedCatalog!.isNotEmpty) {
      return _cachedCatalog!;
    }

    // 1. Try reading directly from source assets bundled in the repo
    if (!forceRefresh) {
      try {
        final jsonStr = await rootBundle.loadString('assets/audio/catalog.json');
        final list = jsonDecode(jsonStr) as List<dynamic>;
        final parsed = list
            .map((e) => AudioSeries.fromJson(e as Map<String, dynamic>))
            .toList();
        if (parsed.isNotEmpty) {
          _cachedCatalog = parsed;
          return parsed;
        }
      } catch (_) {
        // Asset not available or web rootBundle fallback, continue to remote
      }
    }

    final urls = GitHubDataService.audioCatalogUrls();
    for (final url in urls) {
      try {
        final res = await _client.get(Uri.parse(url)).timeout(
              const Duration(seconds: 4),
            );
        if (res.statusCode == 200) {
          final list = jsonDecode(res.body) as List<dynamic>;
          final parsed = list
              .map((e) => AudioSeries.fromJson(e as Map<String, dynamic>))
              .toList();
          _cachedCatalog = parsed;
          return parsed;
        }
      } catch (_) {
        // Try next fallback URL
      }
    }

    // Fallback seed catalog
    _cachedCatalog = _seedCatalog;
    return _seedCatalog;
  }

  /// Loads the full series with tracks.
  Future<AudioSeries?> getSeries(String seriesId, {bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedSeries.containsKey(seriesId)) {
      return _cachedSeries[seriesId];
    }

    // 1. Try reading directly from source assets bundled in the repo
    if (!forceRefresh) {
      try {
        final jsonStr = await rootBundle.loadString('assets/audio/series/$seriesId.json');
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        final series = AudioSeries.fromJson(map);
        _cachedSeries[seriesId] = series;
        return series;
      } catch (_) {
        // Asset not available or web rootBundle fallback, continue to remote
      }
    }

    final urls = GitHubDataService.audioSeriesUrls(seriesId);
    for (final url in urls) {
      try {
        final res = await _client.get(Uri.parse(url)).timeout(
              const Duration(seconds: 4),
            );
        if (res.statusCode == 200) {
          final map = jsonDecode(res.body) as Map<String, dynamic>;
          final series = AudioSeries.fromJson(map);
          _cachedSeries[seriesId] = series;
          return series;
        }
      } catch (_) {
        // Try next fallback URL
      }
    }

    // Return seed series if available
    final fallback = _seedSeriesMap[seriesId];
    if (fallback != null) {
      _cachedSeries[seriesId] = fallback;
    }
    return fallback;
  }

  // ── Seed / Fallback Data ───────────────────────────────────────────────────

  static final List<AudioSeries> _seedCatalog = [
    AudioSeries(
      id: 'through_the_bible',
      title: 'Through The Bible',
      description:
          '70-Hour Bible Survey bringing out the distinctive message of each book from Genesis to Revelation.',
      speaker: 'Zac Poonen',
      trackCount: 70,
      category: 'Bible Survey',
      coverUrl: 'https://www.cfcindia.com/images/bank/cfc_ttb.jpg',
      tracks: _ttbTracks,
    ),
    AudioSeries(
      id: 'foundational_truths',
      title: 'Basic Christian Truths',
      description:
          'Crucial foundational teachings on discipleship, repentance, the cross, and victorious Christian living.',
      speaker: 'Zac Poonen',
      trackCount: 16,
      category: 'Foundations',
      coverUrl: 'https://www.cfcindia.org/images/bank/weekly_podcast.jpg',
      tracks: _foundationsTracks,
    ),
    AudioSeries(
      id: 'the_church',
      title: 'The Church & Discipleship',
      description:
          'Understanding New Testament church principles, fellowship, and servant leadership.',
      speaker: 'Zac Poonen',
      trackCount: 10,
      category: 'The Church',
      coverUrl: 'https://www.cfcindia.org/resources/en/icon/cfc-logo-maroon.png',
      tracks: _churchTracks,
    ),
  ];

  static final Map<String, AudioSeries> _seedSeriesMap = {
    for (final s in _seedCatalog) s.id: s,
  };

  static final List<AudioTrack> _ttbTracks = [
    const AudioTrack(
      id: 'ttb_01_genesis_01',
      title: 'Genesis - Part 1: Creation & The Fall',
      seriesId: 'through_the_bible',
      seriesTitle: 'Through The Bible',
      speaker: 'Zac Poonen',
      durationSeconds: 3130,
      audioUrl:
          'https://www.cfcindia.org/resources/en/study-series/through-the-bible/01-genesis-1.mp3',
      coverUrl: 'https://www.cfcindia.com/images/bank/cfc_ttb.jpg',
      scriptureBook: 'GEN',
      scriptureChapter: 1,
    ),
    const AudioTrack(
      id: 'ttb_02_genesis_02',
      title: 'Genesis - Part 2: Abraham & The Covenant',
      seriesId: 'through_the_bible',
      seriesTitle: 'Through The Bible',
      speaker: 'Zac Poonen',
      durationSeconds: 3205,
      audioUrl:
          'https://www.cfcindia.org/resources/en/study-series/through-the-bible/02-genesis-2.mp3',
      coverUrl: 'https://www.cfcindia.com/images/bank/cfc_ttb.jpg',
      scriptureBook: 'GEN',
      scriptureChapter: 12,
    ),
    const AudioTrack(
      id: 'ttb_03_genesis_03',
      title: 'Genesis - Part 3: Isaac, Jacob & Joseph',
      seriesId: 'through_the_bible',
      seriesTitle: 'Through The Bible',
      speaker: 'Zac Poonen',
      durationSeconds: 3180,
      audioUrl:
          'https://www.cfcindia.org/resources/en/study-series/through-the-bible/03-genesis-3.mp3',
      coverUrl: 'https://www.cfcindia.com/images/bank/cfc_ttb.jpg',
      scriptureBook: 'GEN',
      scriptureChapter: 37,
    ),
    const AudioTrack(
      id: 'ttb_04_exodus_01',
      title: 'Exodus - Part 1: Deliverance from Egypt',
      seriesId: 'through_the_bible',
      seriesTitle: 'Through The Bible',
      speaker: 'Zac Poonen',
      durationSeconds: 3150,
      audioUrl:
          'https://www.cfcindia.org/resources/en/study-series/through-the-bible/04-exodus-1.mp3',
      coverUrl: 'https://www.cfcindia.com/images/bank/cfc_ttb.jpg',
      scriptureBook: 'EXO',
      scriptureChapter: 1,
    ),
    const AudioTrack(
      id: 'ttb_05_exodus_02',
      title: 'Exodus - Part 2: The Law & The Tabernacle',
      seriesId: 'through_the_bible',
      seriesTitle: 'Through The Bible',
      speaker: 'Zac Poonen',
      durationSeconds: 3220,
      audioUrl:
          'https://www.cfcindia.org/resources/en/study-series/through-the-bible/05-exodus-2.mp3',
      coverUrl: 'https://www.cfcindia.com/images/bank/cfc_ttb.jpg',
      scriptureBook: 'EXO',
      scriptureChapter: 25,
    ),
  ];

  static final List<AudioTrack> _foundationsTracks = [
    const AudioTrack(
      id: 'ft_01_seven_truths',
      title: 'Seven Truths Every Christian Must Know',
      seriesId: 'foundational_truths',
      seriesTitle: 'Basic Christian Truths',
      speaker: 'Zac Poonen',
      durationSeconds: 2980,
      audioUrl:
          'https://www.cfcindia.org/resources/en/sermon-series/single-sermons/seven-truths-that-every-christian-must-know.mp3',
      scriptureBook: 'JHN',
      scriptureChapter: 8,
      scriptureVerse: 32,
    ),
    const AudioTrack(
      id: 'ft_02_christ_defeated_satan',
      title: 'Christ Defeated Satan On The Cross',
      seriesId: 'foundational_truths',
      seriesTitle: 'Basic Christian Truths',
      speaker: 'Zac Poonen',
      durationSeconds: 3120,
      audioUrl:
          'https://www.cfcindia.org/resources/en/sermon-series/the-power-of-christs-resurrection/christ-defeated-satan-on-the-cross.mp3',
      scriptureBook: 'COL',
      scriptureChapter: 2,
      scriptureVerse: 15,
    ),
    const AudioTrack(
      id: 'ft_03_god_rest',
      title: 'You Can Enter Into God’s Rest',
      seriesId: 'foundational_truths',
      seriesTitle: 'Basic Christian Truths',
      speaker: 'Zac Poonen',
      durationSeconds: 3040,
      audioUrl:
          'https://www.cfcindia.org/resources/en/sermon-series/single-sermons/you-can-enter-into-gods-rest.mp3',
      scriptureBook: 'HEB',
      scriptureChapter: 4,
      scriptureVerse: 9,
    ),
  ];

  static final List<AudioTrack> _churchTracks = [
    const AudioTrack(
      id: 'ch_01_god_centered',
      title: 'The God-Centered Can Build The Church',
      seriesId: 'the_church',
      seriesTitle: 'The Church & Discipleship',
      speaker: 'Zac Poonen',
      durationSeconds: 3180,
      audioUrl:
          'https://www.cfcindia.org/resources/en/sermon-series/single-sermons/the-god-centered-can-build-the-church.mp3',
      scriptureBook: 'EPH',
      scriptureChapter: 4,
    ),
    const AudioTrack(
      id: 'ch_02_light_in_darkness',
      title: 'The Church - A Light In The Darkness',
      seriesId: 'the_church',
      seriesTitle: 'The Church & Discipleship',
      speaker: 'Zac Poonen',
      durationSeconds: 3240,
      audioUrl:
          'https://www.cfcindia.org/resources/en/sermon-series/single-sermons/the-church-a-light-in-the-darkness.mp3',
      scriptureBook: 'MAT',
      scriptureChapter: 5,
      scriptureVerse: 14,
    ),
  ];
}
