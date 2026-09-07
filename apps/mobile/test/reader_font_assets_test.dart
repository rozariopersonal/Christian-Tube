import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/engines/scripture/models/scripture_theme_state.dart';

void main() {
  final idToFamily = <String, MapEntry<String, String>>{
    'Playfair': const MapEntry('en', 'Playfair Display'),
    'Cinzel': const MapEntry('en', 'Cinzel'),
    'Cormorant': const MapEntry('en', 'Cormorant Garamond'),
    'Outfit': const MapEntry('en', 'Outfit'),
    'Lora': const MapEntry('en', 'Lora'),
    'Merriweather': const MapEntry('en', 'Merriweather'),
    'GreatVibes': const MapEntry('en', 'Great Vibes'),
    'Montserrat': const MapEntry('en', 'Montserrat'),
    'MuktaMalar': const MapEntry('tam', 'Mukta Malar'),
    'Catamaran': const MapEntry('tam', 'Catamaran'),
    'Kavivanar': const MapEntry('tam', 'Kavivanar'),
    'ArimaMadurai': const MapEntry('tam', 'Arima'),
    'Coiny': const MapEntry('tam', 'Coiny'),
    'NotoSerifTamil': const MapEntry('tam', 'Noto Serif Tamil'),
    'Gayathri': const MapEntry('mal', 'Gayathri'),
    'Manjari': const MapEntry('mal', 'Manjari'),
    'Chilanka': const MapEntry('mal', 'Chilanka'),
    'AnekMalayalam': const MapEntry('mal', 'Anek Malayalam'),
    'NotoSerifMalayalam': const MapEntry('mal', 'Noto Serif Malayalam'),
    'Mandali': const MapEntry('tel', 'Mandali'),
    'Ramabhadra': const MapEntry('tel', 'Ramabhadra'),
    'Gidugu': const MapEntry('tel', 'Gidugu'),
    'Suranna': const MapEntry('tel', 'Suranna'),
    'AnekTelugu': const MapEntry('tel', 'Anek Telugu'),
    'NotoSerifTelugu': const MapEntry('tel', 'Noto Serif Telugu'),
    'RozhaOne': const MapEntry('hin', 'Rozha One'),
    'YatraOne': const MapEntry('hin', 'Yatra One'),
    'Kalam': const MapEntry('hin', 'Kalam'),
    'Poppins': const MapEntry('hin', 'Poppins'),
    'AnekDevanagari': const MapEntry('hin', 'Anek Devanagari'),
    'NotoSerifDevanagari': const MapEntry('hin', 'Noto Serif Devanagari'),
    'BalooTamma2': const MapEntry('kan', 'Baloo Tamma 2'),
    'Hubballi': const MapEntry('kan', 'Hubballi'),
    'AnekKannada': const MapEntry('kan', 'Anek Kannada'),
    'NotoSerifKannada': const MapEntry('kan', 'Noto Serif Kannada'),
  };

  test('every selectable reader family resolves to a bundled font asset',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final entry in idToFamily.entries) {
      final id = entry.key;
      final lang = entry.value.key;
      final family = entry.value.value;
      final resolved = ScriptureThemeCatalog.resolveFontFamily(id, lang);
      expect(resolved, family,
          reason: 'resolveFontFamily($id, $lang) should resolve to $family');
      final file = 'assets/fonts/${family.replaceAll(' ', '_')}-Regular.ttf';
      final data = await rootBundle.load(file);
      expect(data.lengthInBytes, greaterThan(500),
          reason: '$file should be a real font asset');
    }
  });

  testWidgets('reader text renders with a bundled family without errors',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: Text(
            'For God so loved the world',
            style: TextStyle(fontFamily: 'Cinzel', fontSize: 40),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final t = tester.widget<Text>(find.text('For God so loved the world'));
    expect(t.style?.fontFamily, 'Cinzel');
  });
}