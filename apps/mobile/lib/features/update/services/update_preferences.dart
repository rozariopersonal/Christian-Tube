import 'package:shared_preferences/shared_preferences.dart';

class UpdatePreferences {
  static const _key = 'skipped_update_version';

  static String _normalize(String version) =>
      version.trim().replaceFirst(RegExp(r'^[vV]'), '').toLowerCase();

  static Future<bool> isSkipped(String version) async {
    final saved = (await SharedPreferences.getInstance()).getString(_key);
    return saved != null && _normalize(saved) == _normalize(version);
  }

  static Future<void> skip(String version) async {
    await (await SharedPreferences.getInstance()).setString(_key, version);
  }
}
