/// A single Word-for-the-Week article entry in the teaching browser index.
///
/// Mirrors one row of `releases/articles/wftw_index.json`, which is emitted
/// by `tool/sync_cfc_articles.js` and is platform-neutral (usable on web and
/// mobile, unlike the mobile-only feed SQLite).
class WftwIndexEntry {
  final String id;
  final String title;
  final String date;
  final String lang;
  final int? year;
  final int? bookNumber;
  final int? chapter;
  final int? startVerse;
  final int? endVerse;

  const WftwIndexEntry({
    required this.id,
    required this.title,
    required this.date,
    this.lang = 'en',
    this.year,
    this.bookNumber,
    this.chapter,
    this.startVerse,
    this.endVerse,
  });

  factory WftwIndexEntry.fromJson(Map<String, dynamic> json) {
    return WftwIndexEntry(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled',
      date: json['date'] as String? ?? '',
      lang: json['lang'] as String? ?? 'en',
      year: json['year'] as int?,
      bookNumber: json['bookNumber'] as int?,
      chapter: json['chapter'] as int?,
      startVerse: json['startVerse'] as int?,
      endVerse: json['endVerse'] as int?,
    );
  }

  /// Whether this article carries an anchored scripture reference.
  bool get hasPrimaryVerse =>
      bookNumber != null && chapter != null && startVerse != null;
}

/// Groups [entries] by year (descending) with each group's entries sorted
/// newest-first. Entries without a year are dropped.
Map<int, List<WftwIndexEntry>> groupByYear(List<WftwIndexEntry> entries) {
  final map = <int, List<WftwIndexEntry>>{};
  for (final entry in entries) {
    final year = entry.year;
    if (year == null) continue;
    (map[year] ??= []).add(entry);
  }
  for (final list in map.values) {
    list.sort((a, b) => b.date.compareTo(a.date));
  }
  final sorted = map.entries.toList()
    ..sort((a, b) => b.key.compareTo(a.key));
  return Map.fromEntries(sorted);
}

const List<String> _monthAbbr = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Formats `2026-09-06` into `Sep 6, 2026`. Returns the input untouched when
/// it is not in the expected shape.
String formatWftwDate(String isoDate) {
  final parts = isoDate.split('-');
  if (parts.length != 3) return isoDate;
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (month == null || month < 1 || month > 12 || day == null) return isoDate;
  return '${_monthAbbr[month - 1]} $day, ${parts[0]}';
}