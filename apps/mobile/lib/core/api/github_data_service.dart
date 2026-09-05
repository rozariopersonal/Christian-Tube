import 'package:mobile/features/bible/models/book_abbreviation.dart';
import 'release_assets.dart';

/// Single source of truth for every GitHub-hosted data asset URL.
///
/// **Rules (enforced in review):**
/// - All consumers call methods on this class to get candidate URL lists.
/// - No file other than this one may call [ReleaseAssets.urlsFor] directly.
/// - No file may hardcode jsDelivr / raw.githubusercontent.com URLs.
///
/// ## Canonical Repo Structure
/// ```
/// Christian-Tube-Releases/
/// ├── bibles/
/// │   ├── bible_{version}.json              # monolith (offline download)
/// │   ├── {version}/books.json              # book list & chapter counts
/// │   ├── {version}/counts.json             # per-chapter verse-row counts
/// │   └── {version_id}/{bookNum}/{ch}.json  # per-chapter (live)
/// ├── books/
/// │   ├── catalog.json                      # common catalog (all languages)
/// │   └── {lang_code}/                      # e.g. en/, ta/
/// │       ├── books.sqlite.gz               # offline bulk download
/// │       └── {book_id}/toc.json + chapters/{n}.json
/// ├── cross_references/
/// │   └── {bookAbbrev}/{chapter}.json       # live per-chapter JSON (e.g. GEN/1.json)
/// ├── study/
/// │   └── {version_id}/                     # e.g. taobvsi/
/// │       ├── {version_id}.sqlite           # offline download
/// │       └── chapters/b{bb}_c{ccc}.json    # live per-chapter
/// ├── dictionaries/
/// │   └── dict_{id}.sqlite.gz
/// ├── words_feed/
/// │   ├── manifest.json
/// │   ├── daily.json
/// │   └── topics/{slug}.json
/// ├── commentaries/
/// │   └── {bookNum}/{chapter}.json          # Zac Poonen book scripture links
/// └── scriptures.json
/// ```
class GitHubDataService {
  GitHubDataService._();

  // ── Bible versions ────────────────────────────────────────────────────────

  /// Monolithic JSON archive for offline download.
  static List<String> bibleMonolithUrls(String versionId) =>
      ReleaseAssets.urlsFor('bibles/bible_${versionId.toLowerCase()}.json');

  /// Per-chapter verse list — use for live streaming (no download required).
  static List<String> bibleChapterUrls(
          String versionId, int bookNumber, int chapter) =>
      ReleaseAssets.urlsFor(
          'bibles/${versionId.toLowerCase()}/$bookNumber/$chapter.json');

/// Book list (name + chapter count) for a given version.
  static List<String> bibleBooksListUrls(String versionId) =>
      ReleaseAssets.urlsFor(
          'bibles/${versionId.toLowerCase()}/books.json');

  /// Per-chapter verse-row counts for a given version (the global-row index
  /// backing whole-Bible infinite scroll).
  static List<String> bibleCountsUrls(String versionId) =>
      ReleaseAssets.urlsFor(
          'bibles/${versionId.toLowerCase()}/counts.json');

  // ── Books library ─────────────────────────────────────────────────────────

  /// Common catalog — language-independent metadata for all books.
  /// This single file covers every language; content is fetched per-language.
  static List<String> booksCatalogUrls() =>
      ReleaseAssets.urlsFor('books/catalog.json');

  /// Book cover artwork URLs (CDN first, raw GitHub fallback).
  static List<String> bookCoverUrls(String coverFile) =>
      ReleaseAssets.urlsFor('books/covers/$coverFile');

  /// Primary book cover artwork URL for cached network loading.
  static String bookCoverUrl(String coverFile) =>
      bookCoverUrls(coverFile).first;

  static String _inferBookLanguage(String bookId, [String? langCode]) {
    if (langCode != null && langCode.trim().isNotEmpty && langCode != 'all') {
      return langCode.trim().toLowerCase();
    }
    for (final prefix in ['ta', 'hi', 'te', 'kn', 'ml', 'de']) {
      if (bookId.startsWith('${prefix}_')) {
        return prefix;
      }
    }
    return 'en';
  }

  /// Table of contents for one book (checks language folder first, then flat).
  static List<String> booksTocUrls(String bookId, {String? langCode}) {
    final lang = _inferBookLanguage(bookId, langCode);
    final urls = <String>[];
    if (lang != 'en') {
      urls.addAll(ReleaseAssets.urlsFor('books/$lang/$bookId/toc.json'));
    }
    urls.addAll(ReleaseAssets.urlsFor('books/$bookId/toc.json'));
    urls.addAll(ReleaseAssets.urlsFor('books/en/$bookId/toc.json'));
    return urls;
  }

  /// Chapter content lines for one book (checks language folder first, then flat).
  static List<String> bookChapterUrls(String bookId, int chapterIndex,
          {String? langCode}) {
    final lang = _inferBookLanguage(bookId, langCode);
    final urls = <String>[];
    if (lang != 'en') {
      urls.addAll(ReleaseAssets.urlsFor(
          'books/$lang/$bookId/chapters/$chapterIndex.json'));
    }
    urls.addAll(ReleaseAssets.urlsFor(
        'books/$bookId/chapters/$chapterIndex.json'));
    urls.addAll(ReleaseAssets.urlsFor(
        'books/en/$bookId/chapters/$chapterIndex.json'));
    return urls;
  }

  /// Per-book SQLite package (individual offline download).
  static List<String> bookSqliteUrls(String bookId, {String? langCode}) {
    final lang = _inferBookLanguage(bookId, langCode);
    final urls = <String>[];
    if (lang != 'en') {
      urls.addAll(ReleaseAssets.urlsFor('books/$lang/published/$bookId.sqlite.gz'));
    }
    urls.addAll(ReleaseAssets.urlsFor('books/published/$bookId.sqlite.gz'));
    urls.addAll(ReleaseAssets.urlsFor('books/en/published/$bookId.sqlite.gz'));
    for (final l in ['ta', 'hi', 'te', 'kn', 'ml', 'de']) {
      if (l != lang) {
        urls.addAll(ReleaseAssets.urlsFor('books/$l/published/$bookId.sqlite.gz'));
      }
    }
    return urls;
  }

  /// All-books SQLite for a language (bulk offline download).
  static List<String> allBooksSqliteUrls({String? langCode}) {
    final urls = <String>[];
    if (langCode != null &&
        langCode.trim().isNotEmpty &&
        langCode != 'all' &&
        langCode != 'en') {
      urls.addAll(ReleaseAssets.urlsFor('books/$langCode/books.sqlite.gz'));
    }
    urls.addAll(ReleaseAssets.urlsFor('books/books.sqlite.gz'));
    urls.addAll(ReleaseAssets.urlsFor('books/en/books.sqlite.gz'));
    return urls;
  }

  // ── Cross references ──────────────────────────────────────────────────────

  /// Per-chapter cross-reference JSON — always fetched live, never stored as
  /// SQLite. Cached in-memory for the session by [CrossReferenceService].
  /// Uses canonical 3-letter abbreviation (e.g. `GEN/1.json`), with numeric fallback.
  static List<String> crossReferenceChapterUrls(int bookNumber, int chapter) {
    final abbrev = BookAbbreviation.abbreviationFor(bookNumber);
    final urls = <String>[];
    if (abbrev != null && abbrev.isNotEmpty) {
      urls.addAll(ReleaseAssets.urlsFor('cross_references/$abbrev/$chapter.json'));
    }
    urls.addAll(ReleaseAssets.urlsFor('cross_references/$bookNumber/$chapter.json'));
    return urls;
  }

  // ── Study concepts ────────────────────────────────────────────────────────

  /// Live per-chapter study data for a Bible version (no download required).
  static List<String> studyChapterUrls(
      String versionId, int bookNumber, int chapter) {
    final b = bookNumber.toString().padLeft(2, '0');
    final c = chapter.toString().padLeft(3, '0');
    final v = versionId.toLowerCase();
    return [
      ...ReleaseAssets.urlsFor('study/$v/chapters/b${b}_c${c}.json'),
      ...ReleaseAssets.urlsFor('data/study_$v/chapters/b${b}_c${c}.json'),
      ...ReleaseAssets.urlsFor('data/study_ta_ovbsi/chapters/b${b}_c${c}.json'),
    ];
  }

  /// Offline SQLite for a Bible version''s study data (optional download).
  static List<String> studySqliteUrls(String versionId) {
    final v = versionId.toLowerCase();
    return [
      ...ReleaseAssets.urlsFor('study/$v/$v.sqlite'),
      ...ReleaseAssets.urlsFor('study_$v.sqlite'),
      ...ReleaseAssets.urlsFor('study_ta_ovbsi.sqlite'),
    ];
  }

  // ── Commentaries & Backgrounds ────────────────────────────────────────────

  /// Per-chapter verse commentary links (Zac Poonen book links).
  static List<String> commentaryUrls(int bookNumber, int chapter) =>
      ReleaseAssets.urlsFor('commentaries/$bookNumber/$chapter.json');

  /// Complete historical and cultural context background notes dataset.
  static List<String> bibleBackgroundUrls() =>
      ReleaseAssets.urlsFor('data/bible_backgrounds.json');

  // ── Dictionaries ──────────────────────────────────────────────────────────

  static List<String> dictionarySqliteUrls(String dictId) =>
      ReleaseAssets.urlsFor('dictionaries/dict_$dictId.sqlite.gz');

  /// `book_names.json` — localized book names for all Bible versions.
  static List<String> bookNamesUrls() =>
      ReleaseAssets.urlsFor('book_names.json');

  // ── Words feed ────────────────────────────────────────────────────────────

  static List<String> wordsFeedManifestUrls() =>
      ReleaseAssets.urlsFor('words_feed/manifest.json');

  static List<String> wordsFeedDailyUrls() =>
      ReleaseAssets.urlsFor('words_feed/daily.json');

  static List<String> wordsFeedTopicUrls(String topicSlug) =>
      ReleaseAssets.urlsFor('words_feed/topics/$topicSlug.json');

  /// Scripture feed (micro-feed / words engine).
  static List<String> scripturesFeedUrls() =>
      ReleaseAssets.urlsFor('scriptures.json');

  // ── Binaries ──────────────────────────────────────────────────────────────

  /// Precompiled binary packages (e.g. ffmpeg arm64).
  static List<String> ffmpegBinaryUrls(String assetPath) =>
      ReleaseAssets.urlsFor(assetPath);

  // ── Repo manifest ─────────────────────────────────────────────────────────

  /// Top-level dataset manifest (versions, hashes, sizes).
  static List<String> manifestUrls() =>
      ReleaseAssets.urlsFor('manifest.json');
}
