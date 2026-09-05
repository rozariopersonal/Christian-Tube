/// Maps book content to a flat, zero-based "global row" across the whole book,
/// and back to a chapter + ordinal within that chapter.
///
/// A global row is the rendered position of one book line in a continuous
/// scroll reader. Because every `chapters/{n}.json` file holds all pages of its
/// chapter (line numbers reset per page), the row for a given line is the count
/// of lines in every earlier chapter plus the line's offset within its chapter.
///
/// Unlike [BibleVerseIndex] the chapter boundaries are **discovered
/// incrementally** as chapters stream in; [extend] is called with each
/// chapter's resolved line count. A row can only be resolved precisely when the
/// chapters before it are known, i.e. the book's prefix is contiguous.
/// [chapterForRow]/[splitRow] still answer for partially-indexed books using
/// the best-known chapter; [exactStartRow] returns null unless the target
/// chapter's prefix is fully known.
class BookLineIndex {
  BookLineIndex({required this.totalLines});

  /// Total lines of the book (from the catalog / toc); fixes the maximum
  /// `itemCount` of the scroll list, independent of discovery.
  final int totalLines;

  final Map<int, int> _lengths = {};
  List<int> _order = const [];
  List<int> _prefix = const [0];
  bool _built = false;

  void _ensureBuilt() {
    if (_built) return;
    _order = _lengths.keys.toList()..sort();
    _prefix = <int>[0];
    var sum = 0;
    for (final c in _order) {
      sum += _lengths[c]!;
      _prefix.add(sum);
    }
    _built = true;
  }

  /// Records a chapter's resolved line count. Overwrites previous values and is
  /// idempotent for equal counts.
  void extend(int chapterIndex, int lineCount) {
    if (lineCount < 0) lineCount = 0;
    if (_lengths[chapterIndex] == lineCount) return;
    _lengths[chapterIndex] = lineCount;
    _built = false;
  }

  /// How many chapters have been probed so far.
  int get chapterCount => _lengths.length;

  /// Sum of known chapter lengths, capped at [totalLines].
  int get knownRowCount {
    _ensureBuilt();
    final sum = _prefix.last;
    return sum > totalLines ? totalLines : sum;
  }

  /// True once probed chapter rows cover the whole book.
  bool get isComplete {
    _ensureBuilt();
    return _prefix.last >= totalLines;
  }

  /// Number of rows resolved by a chapter's prefix in canonical order, capped
  /// at [totalLines].
  int startRow(int chapterIndex) {
    _ensureBuilt();
    final pos = _lowerBound(_order, chapterIndex);
    if (pos == 0) return 0;
    return _prefix[pos].clamp(0, totalLines);
  }

  /// Like [startRow] but returns null unless every chapter *before*
  /// [chapterIndex] has been probed, i.e. the prefix is contiguous. Exact
  /// jumps (TOC chapter select) must use this.
  int? exactStartRow(int chapterIndex) {
    if (chapterIndex < 1) return 0;
    _ensureBuilt();
    if (!_isContiguousUpTo(chapterIndex)) return null;
    return startRow(chapterIndex);
  }

  /// Number of lines probed for a chapter, or null when unknown.
  int? lengthOf(int chapterIndex) => _lengths[chapterIndex];

  /// Best-known chapter containing [row] (0-based), or null when no chapter
  /// has been probed. Rows beyond the known extent clamp to the last known
  /// chapter; rows in an undiscovered gap between known chapters resolve to
  /// the chapter whose known prefix starts at or before [row].
  int? chapterForRow(int row) {
    _ensureBuilt();
    if (_order.isEmpty) return null;
    final r = row < 0
        ? 0
        : (knownRowCount > 0 && row >= knownRowCount ? knownRowCount - 1 : row);
    final pos = _upperBound(_prefix, r) - 1;
    if (pos < 0) return _order.first;
    if (pos >= _order.length) return _order.last;
    return _order[pos];
  }

  /// Resolves [row] to `(chapterIndex, ordinal)` strictly: returns null unless
  /// the row falls within the probed extent of its chapter **and** every
  /// chapter before it has been probed (contiguous prefix). Rows in an
  /// undiscovered gap or beyond the known extent resolve to null so consumers
  /// render placeholders instead of mis-mapping content.
  ({int chapterIndex, int ordinal})? splitRow(int row) {
    if (row < 0 || row >= knownRowCount) return null;
    final chapter = chapterForRow(row);
    if (chapter == null) return null;
    if (!_isContiguousUpTo(chapter)) return null;
    final start = startRow(chapter);
    final length = lengthOf(chapter);
    final ordinal = row - start;
    if (length == null || ordinal < 0 || ordinal >= length) return null;
    return (chapterIndex: chapter, ordinal: ordinal);
  }

  /// Chapter index to probe next after the last known one, assuming canonical
  /// 1-based chapter numbering. Returns null when nothing is known yet.
  int? get nextChapterAfterKnown {
    _ensureBuilt();
    if (_order.isEmpty) return 1;
    return _order.last + 1;
  }

  bool _isContiguousUpTo(int chapterIndex) {
    var next = 1;
    for (final c in _order) {
      if (c >= chapterIndex) break;
      if (c != next) return false;
      next++;
    }
    return next >= chapterIndex;
  }

  /// First index in sorted [list] whose value is >= [value].
  int _lowerBound(List<int> list, int value) {
    var lo = 0;
    var hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid] < value) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// First index in sorted [list] whose value is > [value].
  int _upperBound(List<int> list, int value) {
    var lo = 0;
    var hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid] <= value) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}