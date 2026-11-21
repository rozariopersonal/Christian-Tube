import 'package:flutter/material.dart';
import '../../../core/config/app_config.dart';
import '../../../shared/ui/language_meta.dart';

/// A single highlighted capability row on the promotional share poster.
@immutable
class AppPromoFeature {
  final IconData icon;
  final String title;
  final String description;

  const AppPromoFeature({
    required this.icon,
    required this.title,
    required this.description,
  });
}

/// Localized promotional poster copy and outbound share text for one language.
@immutable
class AppPromoContent {
  final String languageCode;
  final String subtitle;
  final String scanPrompt;
  final String targetWebLabel;
  final String targetAndroidLabel;
  final String featuresHeading;
  final List<AppPromoFeature> features;
  final String shareBanner;
  final String attribution;
  final String shareHeadline;
  final String webLinkLabel;
  final String androidLinkLabel;

  const AppPromoContent({
    required this.languageCode,
    required this.subtitle,
    required this.scanPrompt,
    required this.targetWebLabel,
    required this.targetAndroidLabel,
    required this.featuresHeading,
    required this.features,
    required this.shareBanner,
    required this.attribution,
    required this.shareHeadline,
    required this.webLinkLabel,
    required this.androidLinkLabel,
  });

  /// Builds the localized text accompanying the shared poster or link.
  String buildShareText({
    required String appName,
    required String version,
    required String webAppUrl,
    required String downloadUrl,
  }) {
    return '$appName (v$version) — $shareHeadline\n\n'
        '🌐 $webLinkLabel:\n$webAppUrl\n\n'
        '📱 $androidLinkLabel:\n$downloadUrl';
  }
}

/// Registry of localized promotional poster content across all app languages.
class AppPromoCatalog {
  const AppPromoCatalog._();

  static const List<String> supportedLanguageCodes = [
    'en',
    'ta',
    'hi',
    'te',
    'kn',
    'ml',
  ];

  /// Normalizes a locale code to one of [supportedLanguageCodes], defaulting to `en`.
  static String normalizeLanguageCode(String? code) {
    if (code == null || code.isEmpty) return 'en';
    final normalized = code.split('_').first.split('-').first.toLowerCase();
    return supportedLanguageCodes.contains(normalized) ? normalized : 'en';
  }

  /// Native script label for the language toggle chips (e.g. `தமிழ்`, `हिन्दी`).
  static String languageDisplayLabel(String code) {
    final meta = LanguageMeta.supportedLanguages[code];
    if (meta == null) return code.toUpperCase();
    return meta.nativeName.isNotEmpty ? meta.nativeName : meta.englishName;
  }

  /// Resolves promotional poster copy for [languageCode] and the active instance.
  static AppPromoContent forLanguage(
    String languageCode, {
    String? instanceId,
  }) {
    final code = normalizeLanguageCode(languageCode);
    final effectiveInstance = instanceId ?? AppConfig.instanceId;
    if (effectiveInstance != 'christian_tube') {
      return _genericContent(code);
    }
    return _christianAppContent[code] ?? _christianAppContent['en']!;
  }

  static AppPromoContent _genericContent(String code) {
    final base = _christianAppContent[code] ?? _christianAppContent['en']!;
    return AppPromoContent(
      languageCode: base.languageCode,
      subtitle: AppConfig.appName,
      scanPrompt: base.scanPrompt,
      targetWebLabel: base.targetWebLabel,
      targetAndroidLabel: base.targetAndroidLabel,
      featuresHeading: base.featuresHeading,
      features: [
        base.features[0],
        base.features[1],
        base.features[4],
      ],
      shareBanner: base.shareBanner,
      attribution: AppConfig.appName,
      shareHeadline: base.shareHeadline,
      webLinkLabel: base.webLinkLabel,
      androidLinkLabel: base.androidLinkLabel,
    );
  }

  static const Map<String, AppPromoContent> _christianAppContent = {
    'en': AppPromoContent(
      languageCode: 'en',
      subtitle: 'All CFC Content in one App',
      scanPrompt: 'Scan to Download',
      targetWebLabel: 'For Web & All Devices',
      targetAndroidLabel: 'For Android',
      featuresHeading: 'Features',
      features: [
        AppPromoFeature(
          icon: Icons.block_rounded,
          title: 'No Ads',
          description:
              'Watch CFC YouTube channel videos inside the app without ads',
        ),
        AppPromoFeature(
          icon: Icons.groups_rounded,
          title: 'Easy to Use',
          description: 'Simple and accessible for all ages',
        ),
        AppPromoFeature(
          icon: Icons.play_arrow_rounded,
          title: 'Sermon Videos & Audio',
          description: 'From CFC churches and channels around the world',
        ),
        AppPromoFeature(
          icon: Icons.smartphone_rounded,
          title: 'Scripture Cards',
          description: 'Scroll endlessly like YouTube Shorts',
        ),
        AppPromoFeature(
          icon: Icons.menu_book_rounded,
          title: 'Books & Articles',
          description: 'Christian Fellowship Church (CFC)',
        ),
        AppPromoFeature(
          icon: Icons.auto_stories_rounded,
          title: 'Bible Reading',
          description:
              'NASB, MSG & Indian languages: Tamil, Telugu, Hindi, Kannada, Malayalam',
        ),
      ],
      shareBanner: 'Share with your family and friends!',
      attribution: 'Made with love by our CFC brothers',
      shareHeadline:
          'Ad-free Christian videos, shorts, Bible, books & audio for families.',
      webLinkLabel: 'Web App (All Devices)',
      androidLinkLabel: 'Android APK Download',
    ),
    'ta': AppPromoContent(
      languageCode: 'ta',
      subtitle: 'அனைத்து CFC உள்ளடக்கமும் ஒரே ஆப்பில்',
      scanPrompt: 'ஸ்கேன் செய்து பதிவிறக்கவும்',
      targetWebLabel: 'இணையம் & எல்லா சாதனங்களுக்கும்',
      targetAndroidLabel: 'ஆண்ட்ராய்டுக்காக',
      featuresHeading: 'அம்சங்கள்',
      features: [
        AppPromoFeature(
          icon: Icons.block_rounded,
          title: '100% விளம்பரம் இல்லை',
          description:
              'ஆப்பில் உள்ள CFC YouTube சேனல்களின் வீடியோக்களை விளம்பரம் இல்லாமல் பார்க்கலாம்',
        ),
        AppPromoFeature(
          icon: Icons.groups_rounded,
          title: 'பயன்படுத்த எளிதானது',
          description: 'எல்லா வயதினருக்கும்',
        ),
        AppPromoFeature(
          icon: Icons.play_arrow_rounded,
          title: 'பிரசங்க வீடியோக்கள் மற்றும் ஆடியோக்கள்',
          description: 'உலகெங்கிலும் உள்ள அனைத்து CFC சேனல்களிலிருந்தும்',
        ),
        AppPromoFeature(
          icon: Icons.smartphone_rounded,
          title: 'வேத வசன அட்டைகள்',
          description:
              'YouTube ஷார்ட்ஸ் போல முடிவில்லாமல் ஸ்க்ரோல் செய்து பார்க்கலாம்',
        ),
        AppPromoFeature(
          icon: Icons.menu_book_rounded,
          title: 'புத்தகங்கள் மற்றும் கட்டுரைகள்',
          description: 'கிறிஸ்தவ ஐக்கிய சபை (CFC)',
        ),
        AppPromoFeature(
          icon: Icons.auto_stories_rounded,
          title: 'வேதாகம வாசிப்பு',
          description:
              'NASB, MSG மற்றும் தமிழ், தெலுங்கு, இந்தி, கன்னடம், மலையாளம் போன்ற இந்திய மொழிகளில்',
        ),
      ],
      shareBanner: 'உங்கள் குடும்பத்தினருடனும் நண்பர்களுடனும் பகிருங்கள்!',
      attribution: 'நமது CFC சகோதரர்களால் அன்புடன் உருவாக்கப்பட்டது',
      shareHeadline:
          'விளம்பரமில்லாத கிறிஸ்தவ வீடியோக்கள், வேதாகமம், புத்தகங்கள் மற்றும் ஆடியோக்கள்.',
      webLinkLabel: 'இணைய ஆப் (எல்லா சாதனங்களுக்கும்)',
      androidLinkLabel: 'ஆண்ட்ராய்டு APK பதிவிறக்கம்',
    ),
    'hi': AppPromoContent(
      languageCode: 'hi',
      subtitle: 'सारा CFC कंटेंट एक ही ऐप में',
      scanPrompt: 'डाउनलोड करने के लिए स्कैन करें',
      targetWebLabel: 'वेब और सभी डिवाइस के लिए',
      targetAndroidLabel: 'एंड्रॉइड के लिए',
      featuresHeading: 'विशेषताएँ',
      features: [
        AppPromoFeature(
          icon: Icons.block_rounded,
          title: '100% विज्ञापन-मुक्त',
          description:
              'ऐप में CFC YouTube चैनलों के वीडियो बिना किसी विज्ञापन के देखें',
        ),
        AppPromoFeature(
          icon: Icons.groups_rounded,
          title: 'उपयोग में आसान',
          description: 'हर उम्र के लोगों के लिए सरल',
        ),
        AppPromoFeature(
          icon: Icons.play_arrow_rounded,
          title: 'प्रवचन वीडियो और ऑडियो',
          description: 'दुनिया भर के सभी CFC चैनलों से',
        ),
        AppPromoFeature(
          icon: Icons.smartphone_rounded,
          title: 'वचन कार्ड',
          description: 'YouTube शॉर्ट्स की तरह लगातार स्क्रॉल करके देखें',
        ),
        AppPromoFeature(
          icon: Icons.menu_book_rounded,
          title: 'पुस्तकें और लेख',
          description: 'क्रिश्चियन फ़ेलोशिप चर्च (CFC)',
        ),
        AppPromoFeature(
          icon: Icons.auto_stories_rounded,
          title: 'बाइबल पठन',
          description:
              'NASB, MSG और हिंदी, तमिल, तेलुगु, कन्नड़, मलयालम जैसी भारतीय भाषाओं में',
        ),
      ],
      shareBanner: 'अपने परिवार और दोस्तों के साथ साझा करें!',
      attribution: 'हमारे CFC भाइयों द्वारा प्रेम से निर्मित',
      shareHeadline:
          'परिवारों के लिए विज्ञापन-मुक्त मसीही वीडियो, बाइबल, पुस्तकें और ऑडियो।',
      webLinkLabel: 'वेब ऐप (सभी डिवाइस)',
      androidLinkLabel: 'एंड्रॉइड APK डाउनलोड',
    ),
    'te': AppPromoContent(
      languageCode: 'te',
      subtitle: 'CFC కంటెంట్ అంతా ఒకే యాప్‌లో',
      scanPrompt: 'డౌన్‌లోడ్ చేయడానికి స్కాన్ చేయండి',
      targetWebLabel: 'వెబ్ & అన్ని పరికరాల కోసం',
      targetAndroidLabel: 'ఆండ్రాయిడ్ కోసం',
      featuresHeading: 'ఫీచర్లు',
      features: [
        AppPromoFeature(
          icon: Icons.block_rounded,
          title: '100% ప్రకటన రహితం',
          description:
              'యాప్‌లో CFC YouTube ఛానెళ్ల వీడియోలను ప్రకటనలు లేకుండా చూడండి',
        ),
        AppPromoFeature(
          icon: Icons.groups_rounded,
          title: 'వాడటానికి సులభం',
          description: 'అన్ని వయసుల వారికి అనుకూలం',
        ),
        AppPromoFeature(
          icon: Icons.play_arrow_rounded,
          title: 'ప్రసంగ వీడియోలు మరియు ఆడియోలు',
          description: 'ప్రపంచవ్యాప్తంగా ఉన్న అన్ని CFC ఛానెళ్ల నుండి',
        ),
        AppPromoFeature(
          icon: Icons.smartphone_rounded,
          title: 'వాక్య కార్డులు',
          description:
              'YouTube షార్ట్స్ లాగా అంతులేకుండా స్క్రోల్ చేసి చూడండి',
        ),
        AppPromoFeature(
          icon: Icons.menu_book_rounded,
          title: 'పుస్తకాలు మరియు వ్యాసాలు',
          description: 'క్రిస్టియన్ ఫెలోషిప్ చర్చ్ (CFC)',
        ),
        AppPromoFeature(
          icon: Icons.auto_stories_rounded,
          title: 'బైబిల్ పఠనం',
          description:
              'NASB, MSG మరియు తెలుగు, తమిళం, హిందీ, కన్నడ, మలయాళం వంటి భారతీయ భాషలలో',
        ),
      ],
      shareBanner: 'మీ కుటుంబ సభ్యులు మరియు స్నేహితులతో పంచుకోండి!',
      attribution: 'మన CFC సహోదరుల ప్రేమతో రూపొందించబడింది',
      shareHeadline:
          'కుటుంబాల కోసం ప్రకటనలు లేని క్రైస్తవ వీడియోలు, బైబిల్, పుస్తకాలు మరియు ఆడియో.',
      webLinkLabel: 'వెబ్ యాప్ (అన్ని పరికరాలు)',
      androidLinkLabel: 'ఆండ్రాయిడ్ APK డౌన్‌లోడ్',
    ),
    'kn': AppPromoContent(
      languageCode: 'kn',
      subtitle: 'ಎಲ್ಲಾ CFC ವಿಷಯ ಒಂದೇ ಆ್ಯಪ್‌ನಲ್ಲಿ',
      scanPrompt: 'ಡೌನ್‌ಲೋಡ್ ಮಾಡಲು ಸ್ಕ್ಯಾನ್ ಮಾಡಿ',
      targetWebLabel: 'ವೆಬ್ ಮತ್ತು ಎಲ್ಲಾ ಸಾಧನಗಳಿಗೆ',
      targetAndroidLabel: 'ಆಂಡ್ರಾಯ್ಡ್‌ಗಾಗಿ',
      featuresHeading: 'ವೈಶಿಷ್ಟ್ಯಗಳು',
      features: [
        AppPromoFeature(
          icon: Icons.block_rounded,
          title: '100% ಜಾಹೀರಾತು-ರಹಿತ',
          description:
              'ಆ್ಯಪ್‌ನಲ್ಲಿ CFC YouTube ಚಾನೆಲ್‌ಗಳ ವೀಡಿಯೊಗಳನ್ನು ಜಾಹೀರಾತುಗಳಿಲ್ಲದೆ ನೋಡಿ',
        ),
        AppPromoFeature(
          icon: Icons.groups_rounded,
          title: 'ಬಳಸಲು ಸುಲಭ',
          description: 'ಎಲ್ಲಾ ವಯಸ್ಸಿನವರಿಗೆ',
        ),
        AppPromoFeature(
          icon: Icons.play_arrow_rounded,
          title: 'ಪ್ರಸಂಗ ವೀಡಿಯೊಗಳು ಮತ್ತು ಆಡಿಯೋಗಳು',
          description: 'ಪ್ರಪಂಚದಾದ್ಯಂತದ ಎಲ್ಲಾ CFC ಚಾನೆಲ್‌ಗಳಿಂದ',
        ),
        AppPromoFeature(
          icon: Icons.smartphone_rounded,
          title: 'ವೇದ ವಾಕ್ಯ ಕಾರ್ಡ್‌ಗಳು',
          description:
              'YouTube ಶಾರ್ಟ್ಸ್‌ನಂತೆ ನಿರಂತರವಾಗಿ ಸ್ಕ್ರಾಲ್ ಮಾಡಿ ನೋಡಿ',
        ),
        AppPromoFeature(
          icon: Icons.menu_book_rounded,
          title: 'ಪುಸ್ತಕಗಳು ಮತ್ತು ಲೇಖನಗಳು',
          description: 'ಕ್ರಿಶ್ಚಿಯನ್ ಫೆಲೋಶಿಪ್ ಚರ್ಚ್ (CFC)',
        ),
        AppPromoFeature(
          icon: Icons.auto_stories_rounded,
          title: 'ಬೈಬಲ್ ವಾಚನ',
          description:
              'NASB, MSG ಹಾಗೂ ಕನ್ನಡ, ತಮಿಳು, ತೆಲುಗು, ಹಿಂದಿ, ಮಲಯಾಳಂ ಮುಂತಾದ ಭಾರತೀಯ ಭಾಷೆಗಳಲ್ಲಿ',
        ),
      ],
      shareBanner: 'ನಿಮ್ಮ ಕುಟುಂಬ ಮತ್ತು ಸ್ನೇಹಿತರೊಂದಿಗೆ ಹಂಚಿಕೊಳ್ಳಿ!',
      attribution: 'ನಮ್ಮ CFC ಸಹೋದರರಿಂದ ಪ್ರೀತಿಯಿಂದ ನಿರ್ಮಿಸಲಾಗಿದೆ',
      shareHeadline:
          'ಕುಟುಂಬಗಳಿಗಾಗಿ ಜಾಹೀರಾತು-ರಹಿತ ಕ್ರೈಸ್ತ ವೀಡಿಯೊಗಳು, ಬೈಬಲ್, ಪುಸ್ತಕಗಳು ಮತ್ತು ಆಡಿಯೋ.',
      webLinkLabel: 'ವೆಬ್ ಆ್ಯಪ್ (ಎಲ್ಲಾ ಸಾಧನಗಳು)',
      androidLinkLabel: 'ಆಂಡ್ರಾಯ್ಡ್ APK ಡೌನ್‌ಲೋಡ್',
    ),
    'ml': AppPromoContent(
      languageCode: 'ml',
      subtitle: 'എല്ലാ CFC ഉള്ളടക്കവും ഒറ്റ ആപ്പിൽ',
      scanPrompt: 'ഡൗൺലോഡ് ചെയ്യാൻ സ്കാൻ ചെയ്യുക',
      targetWebLabel: 'വെബ് & എല്ലാ ഉപകരണങ്ങൾക്കും',
      targetAndroidLabel: 'ആൻഡ്രോയിഡിനായി',
      featuresHeading: 'സവിശേഷതകൾ',
      features: [
        AppPromoFeature(
          icon: Icons.block_rounded,
          title: '100% പരസ്യരഹിതം',
          description:
              'ആപ്പിലെ CFC YouTube ചാനലുകളുടെ വീഡിയോകൾ പരസ്യങ്ങളില്ലാതെ കാണാം',
        ),
        AppPromoFeature(
          icon: Icons.groups_rounded,
          title: 'ഉപയോഗിക്കാൻ എളുപ്പം',
          description: 'എല്ലാ പ്രായക്കാർക്കും',
        ),
        AppPromoFeature(
          icon: Icons.play_arrow_rounded,
          title: 'പ്രസംഗ വീഡിയോകളും ഓഡിയോകളും',
          description: 'ലോകമെമ്പാടുമുള്ള എല്ലാ CFC ചാനലുകളിൽ നിന്നും',
        ),
        AppPromoFeature(
          icon: Icons.smartphone_rounded,
          title: 'വേദവാക്യ കാർഡുകൾ',
          description:
              'YouTube ഷോർട്ട്സ് പോലെ അനന്തമായി സ്ക്രോൾ ചെയ്ത് കാണാം',
        ),
        AppPromoFeature(
          icon: Icons.menu_book_rounded,
          title: 'പുസ്തകങ്ങളും ലേഖനങ്ങളും',
          description: 'ക്രിസ്ത്യൻ ഫെലോഷിപ്പ് ചർച്ച് (CFC)',
        ),
        AppPromoFeature(
          icon: Icons.auto_stories_rounded,
          title: 'ബൈബിൾ വായന',
          description:
              'NASB, MSG കൂടാതെ മലയാളം, തമിഴ്, തെലുങ്ക്, ഹിന്ദಿ, കന്നഡ തുടങ്ങിയ ഇന്ത്യൻ ഭാಷകളിൽ',
        ),
      ],
      shareBanner: 'നിങ്ങളുടെ കുടുംബാംഗങ്ങളോടും സുഹൃത്തുക്കളോടും പങ്കിടൂ!',
      attribution: 'നമ്മുടെ CFC സഹോദരന്മാർ സ്നേഹത്തോടെ നിർമ്മിച്ചത്',
      shareHeadline:
          'കുടുംബങ്ങൾക്കായി പരസ്യരഹിത ക്രിസ്തീയ വീഡിയോകൾ, ബൈബിൾ, പുസ്തകങ്ങൾ, ഓഡിയോ.',
      webLinkLabel: 'വെബ് ആപ്പ് (എല്ലാ ഉപകരണങ്ങളും)',
      androidLinkLabel: 'ആൻഡ്രോയിഡ് APK ഡൗൺലോഡ്',
    ),
  };
}
