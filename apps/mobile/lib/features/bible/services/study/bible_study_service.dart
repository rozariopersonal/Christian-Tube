import 'package:flutter/foundation.dart';
import 'bible_study_repository.dart';
import 'bible_study_mobile_service.dart';
import 'bible_study_web_service.dart';

class BibleStudyService {
  static BibleStudyRepository? _instance;

  static BibleStudyRepository get instance {
    if (_instance == null) {
      if (kIsWeb) {
        _instance = BibleStudyWebService();
      } else {
        _instance = BibleStudyMobileService();
      }
    }
    return _instance!;
  }
}
