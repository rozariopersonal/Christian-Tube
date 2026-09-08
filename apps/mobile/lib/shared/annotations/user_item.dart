import 'package:mobile/features/bible/models/bible_bookmark.dart';
import 'package:mobile/features/bible/models/bible_highlight.dart';
import 'package:mobile/shared/models/note.dart';

/// A single authenticated user's persisted annotation: a Bible highlight,
/// a Bible bookmark, or a user note.
///
/// Pre-auth device-local data is NOT a [UserItem]; only rows that belong to an
/// authenticated account are stored as user items (local cache + backend
/// `user_items` database via `/user/items`). [userId] is therefore required
/// and non-empty. On sign-in, device-local data is migrated into user items,
/// pushed, then cleared from the device stores.
class UserItem {
  static const String typeHighlight = 'highlight';
  static const String typeBookmark = 'bookmark';
  static const String typeNote = 'note';

  static const String featureBible = 'bible';

  final String userId;
  final String id;
  final String itemType;
  final String feature;

  /// Bible version; empty for non-Bible anchors.
  final String versionId;
  final String book;
  final int chapter;
  final int verseStart;
  final int verseEnd;

  /// Canonical anchor string (`Book:Chapter:Verse` for bible items; the raw
  /// target id for book/article notes).
  final String targetId;

  /// Highlight color index; null for non-highlight items.
  final int? colorIndex;
  final String text;
  final String? contextText;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Soft-delete tombstone used by sync so deletions propagate across devices.
  final bool deleted;

  const UserItem({
    required this.userId,
    required this.id,
    required this.itemType,
    required this.feature,
    this.versionId = '',
    this.book = '',
    this.chapter = 0,
    this.verseStart = 0,
    this.verseEnd = 0,
    required this.targetId,
    this.colorIndex,
    this.text = '',
    this.contextText,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
  });

  String get reference {
    if (itemType == typeNote && feature == featureBible && book.isNotEmpty) {
      return verseEnd > verseStart
          ? '$book $chapter:$verseStart-$verseEnd'
          : '$book $chapter:$verseStart';
    }
    if (itemType == typeHighlight) {
      return verseEnd > verseStart
          ? '$book $chapter:$verseStart-$verseEnd'
          : '$book $chapter:$verseStart';
    }
    if (itemType == typeBookmark) return '$book $chapter:$verseStart';
    return targetId;
  }

  UserItem copyWith({
    String? userId,
    String? id,
    String? itemType,
    String? feature,
    String? versionId,
    String? book,
    int? chapter,
    int? verseStart,
    int? verseEnd,
    String? targetId,
    int? Function()? colorIndex,
    String? text,
    String? Function()? contextText,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? deleted,
  }) {
    return UserItem(
      userId: userId ?? this.userId,
      id: id ?? this.id,
      itemType: itemType ?? this.itemType,
      feature: feature ?? this.feature,
      versionId: versionId ?? this.versionId,
      book: book ?? this.book,
      chapter: chapter ?? this.chapter,
      verseStart: verseStart ?? this.verseStart,
      verseEnd: verseEnd ?? this.verseEnd,
      targetId: targetId ?? this.targetId,
      colorIndex: colorIndex != null ? colorIndex() : this.colorIndex,
      text: text ?? this.text,
      contextText: contextText != null ? contextText() : this.contextText,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }

  /// Wire + web-cache JSON shape.
  Map<String, dynamic> toJson() => {
        'userId': userId,
        'id': id,
        'itemType': itemType,
        'feature': feature,
        'versionId': versionId,
        'book': book,
        'chapter': chapter,
        'verseStart': verseStart,
        'verseEnd': verseEnd,
        'targetId': targetId,
        'colorIndex': colorIndex,
        'text': text,
        'contextText': contextText,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deleted': deleted,
      };

  factory UserItem.fromJson(Map<String, dynamic> json) => UserItem(
        userId: json['userId'] as String? ?? '',
        id: (json['id'] as String?) ?? '',
        itemType: json['itemType'] as String? ?? '',
        feature: json['feature'] as String? ?? featureBible,
        versionId: json['versionId'] as String? ?? '',
        book: json['book'] as String? ?? '',
        chapter: (json['chapter'] as num?)?.toInt() ?? 0,
        verseStart: (json['verseStart'] as num?)?.toInt() ?? 0,
        verseEnd: (json['verseEnd'] as num?)?.toInt() ?? 0,
        targetId: json['targetId'] as String? ?? '',
        colorIndex: (json['colorIndex'] as num?)?.toInt(),
        text: json['text'] as String? ?? '',
        contextText: json['contextText'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        deleted: json['deleted'] == true,
      );

  /// SQLite column shape.
  Map<String, dynamic> toMap() => {
        'user_id': userId,
        'id': id,
        'item_type': itemType,
        'feature': feature,
        'version_id': versionId,
        'book': book,
        'chapter': chapter,
        'verse_start': verseStart,
        'verse_end': verseEnd,
        'target_id': targetId,
        'color_index': colorIndex,
        'text': text,
        'context_text': contextText,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'deleted': deleted ? 1 : 0,
      };

  factory UserItem.fromMap(Map<String, dynamic> map) => UserItem(
        userId: map['user_id'] as String,
        id: map['id'] as String,
        itemType: map['item_type'] as String,
        feature: map['feature'] as String? ?? featureBible,
        versionId: map['version_id'] as String? ?? '',
        book: map['book'] as String? ?? '',
        chapter: (map['chapter'] as num?)?.toInt() ?? 0,
        verseStart: (map['verse_start'] as num?)?.toInt() ?? 0,
        verseEnd: (map['verse_end'] as num?)?.toInt() ?? 0,
        targetId: map['target_id'] as String? ?? '',
        colorIndex: (map['color_index'] as num?)?.toInt(),
        text: map['text'] as String? ?? '',
        contextText: map['context_text'] as String?,
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        deleted: (map['deleted'] as int? ?? 0) == 1,
      );

  /// Converts a (device-local) Bible highlight into a user item.
  factory UserItem.fromBibleHighlight(BibleHighlight h, String userId) {
    final verses = h.verses;
    final start = verses.isNotEmpty ? verses.first : 0;
    final end = verses.isNotEmpty ? verses.last : start;
    return UserItem(
      userId: userId,
      id: 'h_${h.versionId}_${h.book}_${h.chapter}_$start',
      itemType: typeHighlight,
      feature: featureBible,
      versionId: h.versionId,
      book: h.book,
      chapter: h.chapter,
      verseStart: start,
      verseEnd: end,
      targetId: '${h.book}:${h.chapter}:$start',
      colorIndex: h.colorIndex,
      text: h.text,
      createdAt: h.savedAt,
      updatedAt: h.savedAt,
    );
  }

  BibleHighlight toBibleHighlight() => BibleHighlight(
        versionId: versionId,
        book: book,
        chapter: chapter,
        verses: [
          for (var v = verseStart; v <= verseEnd; v++) v,
        ],
        colorIndex: colorIndex ?? 0,
        text: text,
        savedAt: createdAt,
      );

  /// Converts a (device-local) Bible bookmark into a user item.
  factory UserItem.fromBibleBookmark(BibleBookmark b, String userId) => UserItem(
        userId: userId,
        id: 'b_${b.versionId}_${b.book}_${b.chapter}_${b.verse}',
        itemType: typeBookmark,
        feature: featureBible,
        versionId: b.versionId,
        book: b.book,
        chapter: b.chapter,
        verseStart: b.verse,
        verseEnd: b.verse,
        targetId: '${b.book}:${b.chapter}:${b.verse}',
        text: b.text,
        createdAt: b.savedAt,
        updatedAt: b.savedAt,
      );

  BibleBookmark toBibleBookmark() => BibleBookmark(
        versionId: versionId,
        book: book,
        chapter: chapter,
        verse: verseStart,
        text: text,
        savedAt: createdAt,
      );

  /// Converts a (device-local) note into a user item. Bible notes keep their
  /// canonical `Book:Chapter:Verse` anchor; book/article notes preserve the raw
  /// target id.
  factory UserItem.fromNote(Note n, String userId) {
    var book = '';
    var chapter = 0;
    var verse = 0;
    if (n.feature == featureBible) {
      final parts = n.targetId.split(':');
      if (parts.length >= 3) {
        final maybeChapter = int.tryParse(parts[parts.length - 2]);
        final maybeVerse = int.tryParse(parts.last);
        if (maybeChapter != null && maybeVerse != null) {
          book = parts.sublist(0, parts.length - 2).join(':');
          chapter = maybeChapter;
          verse = maybeVerse;
        }
      }
    }
    return UserItem(
      userId: userId,
      id: n.id,
      itemType: typeNote,
      feature: n.feature,
      book: book,
      chapter: chapter,
      verseStart: verse,
      verseEnd: verse,
      targetId: n.targetId,
      text: n.text,
      contextText: n.contextText,
      createdAt: n.createdAt,
      updatedAt: n.updatedAt,
    );
  }

  Note toNote() => Note(
        id: id,
        feature: feature,
        targetId: targetId,
        text: text,
        contextText: contextText,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}