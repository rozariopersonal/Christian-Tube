import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/api/github_data_service.dart';
import '../models/audio_series.dart';
import '../models/audio_track.dart';

/// Fetches audio series and tracklists from GitHub/CDN with embedded fallback.
class AudioCatalogService {
  final http.Client _client;

  AudioCatalogService({http.Client? client}) : _client = client ?? http.Client();

  /// Loads the top-level audio catalog.
  Future<List<AudioSeries>> getCatalog() async {
    final urls = GitHubDataService.audioCatalogUrls();
    for (final url in urls) {
      try {
        final res = await _client.get(Uri.parse(url)).timeout(
              const Duration(seconds: 4),
            );
        if (res.statusCode == 200) {
          final list = jsonDecode(res.body) as List<dynamic>;
          return list
              .map((e) => AudioSeries.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      } catch (_) {
        // Try next fallback URL
      }
    }

    // Fallback seed catalog
    return _seedCatalog;
  }

  /// Loads the full series with tracks.
  Future<AudioSeries?> getSeries(String seriesId) async {
    final urls = GitHubDataService.audioSeriesUrls(seriesId);
    for (final url in urls) {
      try {
        final res = await _client.get(Uri.parse(url)).timeout(
              const Duration(seconds: 4),
            );
        if (res.statusCode == 200) {
          final map = jsonDecode(res.body) as Map<String, dynamic>;
          return AudioSeries.fromJson(map);
        }
      } catch (_) {
        // Try next fallback URL
      }
    }

    // Return seed series if available
    return _seedSeriesMap[seriesId];
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
          'https://www.cfcindia.org/resources/en/sermon-series/through-the-bible/01_Genesis_01.mp3',
      fallbackUrl:
          'https://github.com/rozariopersonal/Christian-Tube-Releases/releases/download/audio-ttb-v1/01_Genesis_01.mp3',
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
          'https://www.cfcindia.org/resources/en/sermon-series/through-the-bible/02_Genesis_02.mp3',
      fallbackUrl:
          'https://github.com/rozariopersonal/Christian-Tube-Releases/releases/download/audio-ttb-v1/02_Genesis_02.mp3',
      scriptureBook: 'GEN',
      scriptureChapter: 12,
    ),
    const AudioTrack(
      id: 'ttb_03_exodus',
      title: 'Exodus: Deliverance & The Tabernacle',
      seriesId: 'through_the_bible',
      seriesTitle: 'Through The Bible',
      speaker: 'Zac Poonen',
      durationSeconds: 3150,
      audioUrl:
          'https://www.cfcindia.org/resources/en/sermon-series/through-the-bible/03_Exodus.mp3',
      fallbackUrl:
          'https://github.com/rozariopersonal/Christian-Tube-Releases/releases/download/audio-ttb-v1/03_Exodus.mp3',
      scriptureBook: 'EXO',
      scriptureChapter: 1,
    ),
    const AudioTrack(
      id: 'ttb_40_matthew',
      title: 'Matthew: The King & His Kingdom',
      seriesId: 'through_the_bible',
      seriesTitle: 'Through The Bible',
      speaker: 'Zac Poonen',
      durationSeconds: 3340,
      audioUrl:
          'https://www.cfcindia.org/resources/en/sermon-series/through-the-bible/40_Matthew.mp3',
      fallbackUrl:
          'https://github.com/rozariopersonal/Christian-Tube-Releases/releases/download/audio-ttb-v1/40_Matthew.mp3',
      scriptureBook: 'MAT',
      scriptureChapter: 5,
    ),
    const AudioTrack(
      id: 'ttb_45_romans',
      title: 'Romans: The Righteousness of God',
      seriesId: 'through_the_bible',
      seriesTitle: 'Through The Bible',
      speaker: 'Zac Poonen',
      durationSeconds: 3290,
      audioUrl:
          'https://www.cfcindia.org/resources/en/sermon-series/through-the-bible/45_Romans.mp3',
      fallbackUrl:
          'https://github.com/rozariopersonal/Christian-Tube-Releases/releases/download/audio-ttb-v1/45_Romans.mp3',
      scriptureBook: 'ROM',
      scriptureChapter: 8,
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
