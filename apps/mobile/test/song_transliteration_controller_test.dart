import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/features/songs/services/song_transliteration_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SongTransliterationController', () {
    test('defaults to off and persists the chosen value', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = SongTransliterationController();
      await controller.load();

      expect(controller.showTransliteration, isFalse);

      controller.showTransliteration = true;
      expect(controller.showTransliteration, isTrue);

      // A fresh controller restores the persisted value.
      final reloaded = SongTransliterationController();
      await reloaded.load();
      expect(reloaded.showTransliteration, isTrue);

      controller.dispose();
      reloaded.dispose();
    });

    test('notifies listeners on change', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = SongTransliterationController();
      await controller.load();

      var notified = 0;
      controller.addListener(() => notified++);
      controller.showTransliteration = true;
      expect(notified, 1);
      // Setting the same value again does not notify.
      controller.showTransliteration = true;
      expect(notified, 1);

      controller.dispose();
    });
  });
}
