import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/update/update_service.dart';

void main() {
  group('UpdateService.isNewerVersion', () {
    test('standard major/minor/patch increments', () {
      expect(UpdateService.isNewerVersion('v1.58.0', '1.28.0'), isTrue);
      expect(UpdateService.isNewerVersion('v2.0.0', '1.99.99'), isTrue);
      expect(UpdateService.isNewerVersion('v1.28.1', '1.28.0'), isTrue);
      expect(UpdateService.isNewerVersion('v1.29.0', 'v1.28.0'), isTrue);
    });

    test('same version returns false', () {
      expect(UpdateService.isNewerVersion('v1.28.0', '1.28.0'), isFalse);
      expect(UpdateService.isNewerVersion('1.28.0', 'v1.28.0'), isFalse);
      expect(UpdateService.isNewerVersion('v1.28.0', 'v1.28.0'), isFalse);
      expect(UpdateService.isNewerVersion('1.28.0', '1.28.0'), isFalse);
    });

    test('older latest release returns false', () {
      expect(UpdateService.isNewerVersion('v1.27.0', '1.28.0'), isFalse);
      expect(UpdateService.isNewerVersion('1.0.0', '2.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('v1.28.0', '1.28.1'), isFalse);
    });

    test('handles build numbers with + sign', () {
      expect(UpdateService.isNewerVersion('v1.28.0+46', '1.28.0+45'), isTrue);
      expect(UpdateService.isNewerVersion('1.28.0+45', '1.28.0+45'), isFalse);
      expect(UpdateService.isNewerVersion('1.28.0+44', '1.28.0+45'), isFalse);
    });

    test('handles pre-release tags and extra whitespace', () {
      expect(UpdateService.isNewerVersion(' v1.58.0-beta ', '1.28.0'), isTrue);
      expect(UpdateService.isNewerVersion('1.28.0-beta', '1.28.0'), isFalse);
    });
  });
}
