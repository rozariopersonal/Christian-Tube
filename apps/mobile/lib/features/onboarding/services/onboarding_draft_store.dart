import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/user_preference.dart';

class OnboardingDraft {
  const OnboardingDraft({
    required this.step,
    required this.preferences,
    required this.isAmoled,
    required this.channelsLoaded,
  });

  final int step;
  final UserPreference preferences;
  final bool isAmoled;
  final bool channelsLoaded;
}

class OnboardingDraftStore {
  static const _key = 'ct_onboarding_draft_v1';

  Future<OnboardingDraft?> load() async {
    final storage = await SharedPreferences.getInstance();
    final raw = storage.getString(_key);
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return OnboardingDraft(
        step: data['step'] as int,
        preferences: UserPreference.fromJson(
          data['preferences'] as Map<String, dynamic>,
        ),
        isAmoled: data['isAmoled'] == true,
        channelsLoaded: data['channelsLoaded'] == true,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> save(OnboardingDraft draft) async {
    final storage = await SharedPreferences.getInstance();
    if (!await storage.setString(_key, jsonEncode({
      'step': draft.step,
      'preferences': draft.preferences.toJson(),
      'isAmoled': draft.isAmoled,
      'channelsLoaded': draft.channelsLoaded,
    }))) {
      throw StateError('Could not save onboarding progress');
    }
  }

  Future<void> clear() async {
    final storage = await SharedPreferences.getInstance();
    await storage.remove(_key);
  }
}
