import 'dart:typed_data';
import 'package:mobile/features/engines/scripture/services/book_name_service.dart';

class WftwCard {
  final String articleId;
  final int dateMs;
  final int? year;
  final int? bookNumber;
  final String? bookName;
  final int? chapter;
  final int? startVerse;
  final int? endVerse;
  final String articleTitle;
  final String? fallbackExcerpt;
  final String referenceLabel;

  // Live state per card
  String? resolvedText;
  String? resolvedVersion;
  String? comparisonText;
  String? comparisonVersion;
  bool isSaved;
  String? customBackgroundPreset;
  String? customFontFamily;
  Uint8List? precomputedImageBytes;
  String? precomputedImageKey;

  WftwCard({
    required this.articleId,
    required this.dateMs,
    this.year,
    this.bookNumber,
    this.bookName,
    this.chapter,
    this.startVerse,
    this.endVerse,
    required this.articleTitle,
    this.fallbackExcerpt,
    required this.referenceLabel,
    this.resolvedText,
    this.resolvedVersion,
    this.comparisonText,
    this.comparisonVersion,
    this.isSaved = false,
    this.customBackgroundPreset,
    this.customFontFamily,
  });

  bool get hasPrimaryVerse =>
      bookNumber != null && chapter != null && startVerse != null;

  String get activeBackground =>
      customBackgroundPreset ?? 'mountain_dawn';

  String get formattedDate {
    final dt = DateTime.fromMillisecondsSinceEpoch(dateMs, isUtc: true);
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  factory WftwCard.fromMap(Map<String, dynamic> map) {
    final bNum = map['book_number'] as int?;
    final bName = bNum != null ? BookNameService.englishNameFor(bNum) : null;
    final ch = map['chapter'] as int?;
    final sVerse = map['start_verse'] as int?;
    final eVerse = map['end_verse'] as int?;

    String refLabel = '';
    if (bName != null && ch != null && sVerse != null) {
      refLabel = eVerse != null && eVerse != sVerse
          ? '$bName $ch:$sVerse-$eVerse'
          : '$bName $ch:$sVerse';
    }

    return WftwCard(
      articleId: map['article_id'] as String,
      dateMs: map['date_ms'] as int? ?? 0,
      year: map['year'] as int?,
      bookNumber: bNum,
      bookName: bName,
      chapter: ch,
      startVerse: sVerse,
      endVerse: eVerse,
      articleTitle: map['article_title'] as String? ?? 'Word for the Week',
      fallbackExcerpt: map['fallback_excerpt'] as String?,
      referenceLabel: refLabel,
      resolvedText: map['fallback_excerpt'] as String?,
    );
  }
}
