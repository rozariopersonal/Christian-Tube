import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/engines/scripture/models/scripture_card.dart';

void main() {
  test('ScriptureCard model correctly handles JSON parsing including SQLite integer IDs', () {
    final Map<String, dynamic> mockJson = {
      'id': 12345, // Simulate SQLite auto-increment ID
      'engine': 'scripture',
      'bookNumber': 43,
      'bookName': 'John',
      'chapter': 3,
      'startVerse': 16,
      'endVerse': 16,
      'referenceLabel': 'John 3:16',
      'category': 'Love',
      'backgroundPreset': '',
      'tags': ['faith'],
      'isFeatured': 0,
    };

    final card = ScriptureCard.fromJson(mockJson);

    expect(card.id, '12345'); // Must be safely converted to String
    expect(card.bookName, 'John');
    expect(card.chapter, 3);
    expect(card.tags.length, 1);
    expect(card.tags.first, 'faith');
  });

  test('ScriptureCard assigns fallback ID if missing', () {
    final Map<String, dynamic> mockJson = {
      'engine': 'scripture',
      'bookNumber': 43,
      'bookName': 'John',
      'chapter': 3,
      'startVerse': 16,
      'endVerse': 16,
      'referenceLabel': 'John 3:16',
    };

    final card = ScriptureCard.fromJson(mockJson);

    expect(card.id, '43_3_16');
  });

  test('ScriptureCard serializes and restores customFontFamily', () {
    final card = ScriptureCard(
      id: 'custom_1',
      bookNumber: 1,
      bookName: 'Genesis',
      chapter: 1,
      startVerse: 1,
      endVerse: 1,
      referenceLabel: 'Genesis 1:1',
      customFontFamily: 'Cinzel',
    );

    final json = card.toJson();
    expect(json['customFontFamily'], 'Cinzel');

    final restored = ScriptureCard.fromJson(json);
    expect(restored.customFontFamily, 'Cinzel');
  });
}
