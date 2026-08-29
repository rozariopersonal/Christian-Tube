import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class LocalBibleService {
  static final LocalBibleService _instance = LocalBibleService._internal();
  factory LocalBibleService() => _instance;
  LocalBibleService._internal();

  Database? _db;
  final Map<String, String> _webVerses = {};
  // Bibles and the scripture feed are downloaded on demand from the releases
  // repo and registered here; nothing ships pre-installed with the app.
  final Set<String> _webInstalledVersions = {};

  Future<void> initialize() async {
    _seedAllPolyglotVerses();

    if (kIsWeb) return;
    if (_db != null) return;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'christian_tube_bibles.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE verses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            version_id TEXT NOT NULL,
            book_number INTEGER NOT NULL,
            book_name TEXT NOT NULL,
            chapter INTEGER NOT NULL,
            verse INTEGER NOT NULL,
            text TEXT NOT NULL
          );
        ''');
        await db.execute('''
          CREATE INDEX idx_bible_lookup 
          ON verses (version_id, book_number, chapter, verse);
        ''');

        await db.execute('''
          CREATE TABLE installed_versions (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            language TEXT NOT NULL,
            language_code TEXT NOT NULL,
            size_display TEXT NOT NULL,
            installed_at TEXT NOT NULL
          );
        ''');

        await _seedDefaultBibles(db);
      },
    );
  }

  Future<bool> hasVerses(String versionId) async {
    if (kIsWeb) {
      return _webVerses.keys.any((k) => k.startsWith('${versionId}_'));
    }
    final db = _db;
    if (db == null) await initialize();
    final count = Sqflite.firstIntValue(
      await _db!.rawQuery(
        'SELECT COUNT(*) FROM verses WHERE version_id = ?',
        [versionId],
      ),
    );
    return (count ?? 0) > 0;
  }

  void _addVerse(
      String versionId, int book, int chapter, int verse, String text) {
    _webVerses['${versionId}_${book}_${chapter}_$verse'] = text;
  }

  void _seedAllPolyglotVerses() {
    // 1. John 14:27 (book 43, ch 14, v 27)
    _addVerse('WEB', 43, 14, 27,
        'Peace I leave with you. My peace I give to you; not as the world gives, give I to you. Don’t let your heart be troubled, neither let it be fearful.');
    _addVerse('KJV', 43, 14, 27,
        'Peace I leave with you, my peace I give unto you: not as the world giveth, give I unto you. Let not your heart be troubled, neither let it be afraid.');
    _addVerse('BSB', 43, 14, 27,
        'Peace I leave with you; My peace I give to you. I do not give to you as the world gives. Do not let your hearts be troubled; do not be afraid.');
    _addVerse('MSG', 43, 14, 27,
        'I’m leaving you well and whole. That’s my parting gift to you. Peace. I don’t leave you the way you’re used to being left—feeling abandoned, bereft. So don’t be upset. Don’t be fearful.');
    _addVerse('TLB', 43, 14, 27,
        'I am leaving you with a gift—peace of mind and heart! And the peace I give isn’t fragile like the peace the world gives. So don’t be troubled or afraid.');
    _addVerse('NASB', 43, 14, 27,
        'Peace I leave with you; My peace I give to you; not as the world gives do I give to you. Do not let your heart be troubled, nor let it be fearful.');
    _addVerse('ASV', 43, 14, 27,
        'Peace I leave with you; my peace I give unto you: not as the world giveth, give I unto you. Let not your heart be troubled, neither let it be fearful.');
    _addVerse('BBE', 43, 14, 27,
        'May peace be with you; my peace I give to you: I do not give it to you as the world gives it. Let not your heart be troubled or fearful.');
    _addVerse('TAOBVSI', 43, 14, 27,
        'சமாதானத்தை உங்களுக்கு வைத்துப்போகிறேன், என்னுடைய சமாதானத்தையே உங்களுக்குக் கொடுக்கிறேன்; உலகம் கொடுக்கிறபிரகாரம் நான் உங்களுக்குக் கொடுக்கிறதில்லை. உங்கள் இருதயம் கலங்காமலும் பயப்படாமலும் இருப்பதாக.');
    _addVerse('TAM_IRV', 43, 14, 27,
        'சமாதானத்தை உங்களுக்கு வைத்துப்போகிறேன், என்னுடைய சமாதானத்தையே உங்களுக்குக் கொடுக்கிறேன்; உலகம் தருகிறவிதமாக நான் உங்களுக்குத் தரவில்லை. உங்கள் இருதயம் கலங்காமலும் பயப்படாமலும் இருப்பதாக.');
    _addVerse('MAL_IRV', 43, 14, 27,
        'സമാധാനം ഞാൻ നിങ്ങൾക്ക് തന്നിട്ടുപോകുന്നു; എന്റെ സമാധാനം ഞാൻ നിങ്ങൾക്ക് തരുന്നു; ലോകം തരുന്നതുപോലെയല്ല ഞാൻ നിങ്ങൾക്ക് തരുന്നത്. നിങ്ങളുടെ ഹൃദയം കലങ്ങരുത്, ഭയപ്പെടുകയും അരുത്.');
    _addVerse('TEL_IRV', 43, 14, 27,
        'శాంతిని మీకు విడిచి వెళ్తున్నాను. నా శాంతినే మీకిస్తున్నాను. లోకం ఇచ్చే విధంగా నేను మీకు ఇవ్వడం లేదు. మీ హృదయం కలవరపడనీయకండి, భయపడనీయకండి.');
    _addVerse('HIN_IRV', 43, 14, 27,
        'मैं तुम्हें शान्ति दिए जाता हूँ; अपनी शान्ति मैं तुम्हें देता हूँ; जैसे संसार देता है, मैं तुम्हें वैसे नहीं देता। तुम्हारा मन व्याकुल न हो और न डरे।');
    _addVerse('KAN_IRV', 43, 14, 27,
        'ಶಾಂತಿಯನ್ನು ನಿಮಗೆ ಬಿಟ್ಟುಹೋಗುತ್ತೇನೆ, ನನ್ನ ಶಾಂತಿಯನ್ನೇ ನಿಮಗೆ ಕೊಡುತ್ತೇನೆ; ಲೋಕವು ಕೊಡುವ ಪ್ರಕಾರ ನಾನು ನಿಮಗೆ ಕೊಡುವುದಿಲ್ಲ. ನಿಮ್ಮ ಹೃದಯವು ಕಳವಳಗೊಳ್ಳದಿರಲಿ, ಹೆದರದಿರಲಿ.');

    // 2. John 3:16 (book 43, ch 3, v 16)
    _addVerse('WEB', 43, 3, 16,
        'For God so loved the world, that he gave his one and only Son, that whoever believes in him should not perish, but have eternal life.');
    _addVerse('KJV', 43, 3, 16,
        'For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.');
    _addVerse('BSB', 43, 3, 16,
        'For God so loved the world that He gave His one and only Son, that everyone who believes in Him shall not perish but have eternal life.');
    _addVerse('MSG', 43, 3, 16,
        'This is how much God loved the world: He gave his Son, his one and only Son. And this is why: so that no one need be destroyed; by believing in him, anyone can have a whole and lasting life.');
    _addVerse('TLB', 43, 3, 16,
        'For God loved the world so much that he gave his only Son so that anyone who believes in him shall not perish but have eternal life.');
    _addVerse('NASB', 43, 3, 16,
        'For God so loved the world, that He gave His only begotten Son, that whoever believes in Him shall not perish, but have eternal life.');
    _addVerse('ASV', 43, 3, 16,
        'For God so loved the world, that he gave his only begotten Son, that whosoever believeth on him should not perish, but have eternal life.');
    _addVerse('BBE', 43, 3, 16,
        'For God had such love for the world that he gave his only Son, so that has faith in him may not come to destruction but have eternal life.');
    _addVerse('TAOBVSI', 43, 3, 16,
        'தேவன், தம்முடைய ஒரேபேறான குமாரனை விசுவாசிக்கிற எவனும் கெட்டுப்போகாமல் நித்தியஜீவனை அடையும்படிக்கு, அவரைத் தந்தருளி, இவ்வளவாய் உலகத்தில் அன்புகூர்ந்தார்.');
    _addVerse('TAM_IRV', 43, 3, 16,
        'தேவன் தம்முடைய ஒரேபேறான மகனை விசுவாசிக்கிற எவனும் கெட்டுப்போகாமல் நித்தியஜீவனை அடையும்படிக்கு, அவரைத் தந்தருளி, இவ்வளவாய் உலகத்தில் அன்பு கூர்ந்தார்.');
    _addVerse('MAL_IRV', 43, 3, 16,
        'തന്റെ ഏകജാതനായ പുത്രനിൽ വിശ്വസിക്കുന്ന ഏവനും നശിച്ചുപോകാതെ നിത്യജീവൻ പ്രാപിക്കേണ്ടതിന് ദൈവം അവനെ നൽകുവാൻ തക്കവണ്ണം ലോകത്തെ സ്നേഹിച്ചു.');
    _addVerse('TEL_IRV', 43, 3, 16,
        'దేవుడు లోకాన్ని ఎంతో ప్రేమించాడు. కాబట్టి తన అద్వితీయ కుమారునిగా పుట్టిన ఆయన యందు విశ్వాసముంచు ప్రతివాడూ నశించక నిత్యజీవం పొందేలా ఆయనను ఇచ్చాడు.');
    _addVerse('HIN_IRV', 43, 3, 16,
        'क्योंकि परमेश्वर ने जगत से ऐसा प्रेम रखा कि उसने अपना एकलौता पुत्र दे दिया, ताकि जो कोई उस पर विश्वास करे, वह नाश न हो, परन्तु अनन्त जीवन पाए।');
    _addVerse('KAN_IRV', 43, 3, 16,
        'ದೇವರು ಲೋಕವನ್ನು ಎಷ್ಟೋ ಪ್ರೀತಿಸಿದನು, ಆತನು ತನ್ನ ಒಬ್ಬನೇ ಮಗನನ್ನು ಕೊಟ್ಟನು; ಆತನಲ್ಲಿ ನಂಬಿಕೆಯಿಡುವ ಯಾವನೂ ನಾಶವಾಗದೆ ನಿತ್ಯಜೀವವನ್ನು ಪಡೆಯುವಂತೆ ಆತನನ್ನು ಕೊಟ್ಟನು.');

    // 3. Jeremiah 29:11 (book 24, ch 29, v 11)
    _addVerse('WEB', 24, 29, 11,
        '“For I know the thoughts that I think toward you,” says Yahweh, “thoughts of peace, and not of evil, to give you hope and a future.”');
    _addVerse('KJV', 24, 29, 11,
        'For I know the thoughts that I think toward you, saith the LORD, thoughts of peace, and not of evil, to give you an expected end.');
    _addVerse('BSB', 24, 29, 11,
        '“For I know the plans I have for you,” declares the LORD, “plans to prosper you and not to harm you, to give you a future and a hope.”');
    _addVerse('MSG', 24, 29, 11,
        '“I know what I’m doing. I have it all planned out—plans to take care of you, not abandon you, plans to give you the future you hope for.”');
    _addVerse('TLB', 24, 29, 11,
        'For I know the plans I have for you, says the Lord. They are plans for good and not for evil, to give you a future and a hope.');
    _addVerse('NASB', 24, 29, 11,
        '“For I know the plans that I have for you,” declares the LORD, “plans for welfare and not for calamity to give you a future and a hope.”');
    _addVerse('ASV', 24, 29, 11,
        'For I know the thoughts that I think toward you, saith Jehovah, thoughts of peace, and not of evil, to give you hope in your latter end.');
    _addVerse('BBE', 24, 29, 11,
        'For I am conscious of my thoughts about you, says the Lord, thoughts of peace and not of evil, to give you hope in the end.');
    _addVerse('TAOBVSI', 24, 29, 11,
        'நீங்கள் எதிர்பார்த்திருக்கும் முடிவை உங்களுக்குக் கொடுக்கும்படிக்கு நான் உங்கள்பேரில் நினைத்திருக்கிற நினைவுகளை அறிவேன் என்று கர்த்தர் சொல்லுகிறார்; அவைகள் தீமைக்கல்ல, சமாதானத்துக்கேதுவான நினைவுகளே.');
    _addVerse('TAM_IRV', 24, 29, 11,
        'நீங்கள் எதிர்பார்த்திருக்கும் முடிவை உங்களுக்குக் கொடுக்கும்படிக்கு நான் உங்களைப்பற்றி நினைத்திருக்கிற நினைவுகளை அறிவேன் என்று யெகோவா சொல்லுகிறார்; அவைகள் தீமைக்கல்ல, சமாதானத்திற்குரிய நினைவுகளே.');
    _addVerse('MAL_IRV', 24, 29, 11,
        'നിങ്ങൾക്ക് ശുഭകരമായ ഭാവിയും പ്രത്യാശയും നൽകേണ്ടതിന് ഞാൻ നിങ്ങളെക്കുറിച്ചു വിചാരിക്കുന്ന വിചാരങ്ങൾ ഇന്നവ എന്ന് ഞാൻ അറിയുന്നു; അവ തിന്മയ്ക്കല്ല നന്മയ്ക്കത്രേ എന്ന് യഹോവയുടെ അരുളപ്പാട്.');
    _addVerse('TEL_IRV', 24, 29, 11,
        'నేను మీ విషయమై కలిగియున్న ఆలోచనలు నాకు తెలియును; అవి మీకు నిరీక్షణతో కూడిన భవిష్యత్తును ఇచ్చుటకు సమాధానకరమైన ఆలోచనలే గాని హానికరమైనవి కావు.');
    _addVerse('HIN_IRV', 24, 29, 11,
        'क्योंकि यहोवा की यह वाणी है, कि जो कल्पनाएं मैं तुम्हारे विषय करता हूँ उन्हें मैं जानता हूँ, वे भलाई की हैं, बुराई की नहीं, और अन्त में तुम्हारी आशा पूरी करूंगा।');
    _addVerse('KAN_IRV', 24, 29, 11,
        'ಯೆಹೋವನು ಇಂತೆನ್ನುತ್ತಾನೆ: ನಿಮಗೋಸ್ಕರ ನಾನು ಇಟ್ಟುಕೊಂಡಿರುವ ಆಲೋಚನೆಗಳನ್ನು ನಾನೇ ಬಲ್ಲೆನು; ಅವು ಕೇಡಿಗಲ್ಲ, ನಿಮಗೆ ನಿರೀಕ್ಷೆಯುಳ್ಳ ಭವಿಷ್ಯತ್ತನ್ನು ಕೊಡುವಂಥ ಸಮಾಧಾನಕರವಾದ ಆಲೋಚನೆಗಳೇ.');

    // 4. Philippians 4:6-7 (book 50, ch 4, v 6 & 7)
    _addVerse('WEB', 50, 4, 6,
        'In nothing be anxious, but in everything, by prayer and petition with thanksgiving, let your requests be made known to God.');
    _addVerse('WEB', 50, 4, 7,
        'And the peace of God, which surpasses all understanding, will guard your hearts and your thoughts in Christ Jesus.');
    _addVerse('KJV', 50, 4, 6,
        'Be careful for nothing; but in every thing by prayer and supplication with thanksgiving let your requests be made known unto God.');
    _addVerse('KJV', 50, 4, 7,
        'And the peace of God, which passeth all understanding, shall keep your hearts and minds through Christ Jesus.');
    _addVerse('MSG', 50, 4, 6,
        'Don’t fret or worry. Instead of worrying, pray. Let petitions and praises shape your worries into prayers, letting God know your concerns.');
    _addVerse('MSG', 50, 4, 7,
        'Before you know it, a sense of God’s wholeness will come and settle you down. It’s wonderful what happens when Christ displaces worry at the center of your life.');
    _addVerse('TLB', 50, 4, 6,
        'Don’t worry about anything; instead, pray about everything; tell God your needs, and don’t forget to thank him for his answers.');
    _addVerse('TLB', 50, 4, 7,
        'If you do this, you will experience God’s peace, which is far more wonderful than the human mind can understand. His peace will keep your thoughts and your hearts quiet and at rest as you trust in Christ Jesus.');
    _addVerse('NASB', 50, 4, 6,
        'Be anxious for nothing, but in everything by prayer and supplication with thanksgiving let your requests be made known to God.');
    _addVerse('NASB', 50, 4, 7,
        'And the peace of God, which surpasses all comprehension, will guard your hearts and your minds in Christ Jesus.');
    _addVerse('TAOBVSI', 50, 4, 6,
        'நீங்கள் ஒன்றுக்குங் கவலைப்படாமல், எல்லாவற்றையுங்குறித்து உங்கள் விண்ணப்பங்களை ஸ்தோத்திரத்தோடே கூடிய ஜெபத்தினாலும் வேண்டுதலினாலும் தேவனுக்குத் தெரியப்படுத்துங்கள்.');
    _addVerse('TAOBVSI', 50, 4, 7,
        'அப்பொழுது, எல்லாப் புத்திக்கும் மேலான தேவ சமாதானம் உங்கள் இருதயங்களையும் உங்கள் சிந்தைகளையும் கிறிஸ்து இயேசுவுக்குள்ளாகக் காத்துக்கொள்ளும்.');
    _addVerse('MAL_IRV', 50, 4, 6,
        'ഒന്നിനെക്കുറിച്ചും വിചാരപ്പെടരുത്; എല്ലാറ്റിലും പ്രാർത്ഥനയാലും അപേക്ഷയാലും നിങ്ങളുടെ യാചനകൾ സ്തോത്രത്തോടുകൂടെ ദൈവത്തോട് അറിയിക്കുകയത്രേ വേണ്ടത്.');
    _addVerse('MAL_IRV', 50, 4, 7,
        'അപ്പോൾ സകല ബുദ്ധിയേയും കവിയുന്ന ദൈവസമാധാനം നിങ്ങളുടെ ഹൃദയങ്ങളെയും മനസ്സിനെയും ക്രിസ്തുയേശുവിങ്കൽ കാത്തുസൂക്ഷിക്കും.');
    _addVerse('TEL_IRV', 50, 4, 6,
        'దేనిని గురించి చింతించకండి. ప్రార్థన విజ్ఞాపనల ద్వారా కృతజ్ఞతాపూర్వకంగా మీ విన్నపాలను దేవునికి తెలియజేయండి.');
    _addVerse('TEL_IRV', 50, 4, 7,
        'అప్పుడు సమస్త జ్ఞానానికి మించిన దేవుని సమాధానం క్రీస్తు యేసు నందు మీ హృదయాలను, తలంపులను కాపాడుతుంది.');
    _addVerse('HIN_IRV', 50, 4, 6,
        'किसी भी बात की चिन्ता मत करो; परन्तु हर एक बात में तुम्हारे निवेदन, प्रार्थना और याचना के द्वारा धन्यवाद के साथ परमेश्वर के सम्मुख उपस्थित किए जाएं।');
    _addVerse('HIN_IRV', 50, 4, 7,
        'तब परमेश्वर की शान्ति जो समझ से परे है, तुम्हारे हृदय और मन को मसीह यीशु में सुरक्षित रखेगी।');
    _addVerse('KAN_IRV', 50, 4, 6,
        'ಯಾವ ವಿಷಯದಲ್ಲಿಯೂ ಚಿಂತೆಮಾಡಬೇಡಿರಿ; ಆದರೆ ಎಲ್ಲದರಲ್ಲಿಯೂ ಪ್ರಾರ್ಥನೆ ವಿಜ್ಞಾಪನೆಗಳಿಂದ ಕೃತಜ್ಞತಾಪೂರ್ವಕವಾಗಿ ನಿಮ್ಮ ಬಿನ್ನಹಗಳನ್ನು ದೇವರಿಗೆ ತಿಳಿಯಪಡಿಸಿರಿ.');
    _addVerse('KAN_IRV', 50, 4, 7,
        'ಆಗ ಸಮಸ್ತ ಜ್ಞಾನವನ್ನು ಮೀರುವ ದೇವಶಾಂತಿಯು ನಿಮ್ಮ ಹೃದಯಗಳನ್ನೂ ಮನಸ್ಸುಗಳನ್ನೂ ಕ್ರಿಸ್ತ ಯೇಸುವಿನಲ್ಲಿ ಕಾಪಾಡುವುದು.');

    // 5. Psalm 23:1-3 (book 19, ch 23, v 1, 2, 3)
    _addVerse('WEB', 19, 23, 1, 'Yahweh is my shepherd: I shall lack nothing.');
    _addVerse('WEB', 19, 23, 2,
        'He makes me lie down in green pastures. He leads me beside still waters.');
    _addVerse('WEB', 19, 23, 3,
        'He restores my soul. He guides me in the paths of righteousness for his name’s sake.');
    _addVerse('KJV', 19, 23, 1,
        'The LORD is my shepherd; I shall not want.');
    _addVerse('KJV', 19, 23, 2,
        'He maketh me to lie down in green pastures: he leadeth me beside the still waters.');
    _addVerse('KJV', 19, 23, 3,
        'He restoreth my soul: he leadeth me in the paths of righteousness for his name\'s sake.');
    _addVerse('MSG', 19, 23, 1, 'God, my shepherd! I don’t need a thing.');
    _addVerse('MSG', 19, 23, 2,
        'You have bedded me down in lush meadows, you find me quiet pools to drink from.');
    _addVerse('MSG', 19, 23, 3,
        'True to your word, you let me catch my breath and send me in the right direction.');
    _addVerse('TLB', 19, 23, 1,
        'Because the Lord is my Shepherd, I have everything I need!');
    _addVerse('TLB', 19, 23, 2,
        'He lets me rest in the green meadows, and leads me beside the quiet streams.');
    _addVerse('TLB', 19, 23, 3,
        'He gives me new strength. He helps me do what honors him the most.');
    _addVerse('NASB', 19, 23, 1,
        'The LORD is my shepherd, I shall not want.');
    _addVerse('NASB', 19, 23, 2,
        'He makes me lie down in green pastures; He leads me beside quiet waters.');
    _addVerse('NASB', 19, 23, 3,
        'He restores my soul; He guides me in the paths of righteousness for His name’s sake.');
    _addVerse('TAOBVSI', 19, 23, 1,
        'கர்த்தர் என் மேய்ப்பராயிருக்கிறார்; நான் தாழ்ச்சியடையேன்.');
    _addVerse('TAOBVSI', 19, 23, 2,
        'அவர் என்னைப் புல்லுள்ள இடங்களில் படுக்கப்பண்ணி, அமர்ந்த தண்ணீர்கள் அண்டையில் என்னைக் கொண்டுபோய் விடுகிறார்.');
    _addVerse('TAOBVSI', 19, 23, 3,
        'அவர் என் ஆத்துமாவைத் தேற்றி, தம்முடைய நாமத்தினிமித்தம் என்னை நீதியின் பாதைகளில் நடத்துகிறார்.');
    _addVerse('MAL_IRV', 19, 23, 1,
        'യഹോവ എന്റെ ഇടയനാകുന്നു; എനിക്ക് ഒരു കുറവും ഉണ്ടാകുകയില്ല.');
    _addVerse('MAL_IRV', 19, 23, 2,
        'അവൻ എന്നെ പച്ചപ്പുൽപ്പുറങ്ങളിൽ കിടത്തുന്നു; ശാന്തമായ വെള്ളത്തിനരികത്തേക്ക് എന്നെ നയിക്കുന്നു.');
    _addVerse('MAL_IRV', 19, 23, 3,
        'അവൻ എന്റെ മനസ്സിന് ഉന്മേഷം നൽകുന്നു. അവിടുത്തെ നാമത്തിന്റെ മഹത്വത്തിനായി എന്നെ നീതിപാതകളിൽ നടത്തുന്നു.');
    _addVerse('TEL_IRV', 19, 23, 1,
        'యెహోవా నా కాపరి; నాకు ఏ కొరతా ఉండదు.');
    _addVerse('TEL_IRV', 19, 23, 2,
        'ఆయన పచ్చికగల చోట్ల నన్ను పరుండజేస్తాడు. ప్రశాంతమైన జలముల యొద్దకు నన్ను నడిపిస్తాడు.');
    _addVerse('TEL_IRV', 19, 23, 3,
        'ఆయన నా ప్రాణానికి సేదదీర్చును. తన నామమును బట్టి నీతి మార్గములలో నన్ను నడిపించును.');
    _addVerse('HIN_IRV', 19, 23, 1,
        'यहोवा मेरा चरवाहा है; मुझे कुछ घटी न होगी।');
    _addVerse('HIN_IRV', 19, 23, 2,
        'वह मुझे हरी हरी चराइयों में बैठाता है; वह मुझे सुखदाई जल के झरने के पास ले चलता है।');
    _addVerse('HIN_IRV', 19, 23, 3,
        'वह मेरे जी में जी ले आता है। धर्म के मार्गों में वह अपने नाम के निमित्त मेरी अगुवाई करता है।');
    _addVerse('KAN_IRV', 19, 23, 1,
        'ಯೆಹೋವನು ನನ್ನ ಕುರುಬನು; ನನಗೇನೂ ಕೊರತೆಯಾಗದು.');
    _addVerse('KAN_IRV', 19, 23, 2,
        'ಆತನು ನನ್ನನ್ನು ಹಸಿರು ಹುಲ್ಲುಗಾವಲುಗಳಲ್ಲಿ ಮಲಗಿಸುತ್ತಾನೆ; ಪ್ರಶಾಂತ ನೀರಿನ ಬಳಿಗೆ ನನ್ನನ್ನು ನಡೆಸುತ್ತಾನೆ.');
    _addVerse('KAN_IRV', 19, 23, 3,
        'ಆತನು ನನ್ನ ಪ್ರಾಣವನ್ನು ಚೈತನ್ಯಗೊಳಿಸುತ್ತಾನೆ; ತನ್ನ ಹೆಸರಿನ ನಿಮಿತ್ತ ನನ್ನನ್ನು ನೀತಿಯ ಮಾರ್ಗಗಳಲ್ಲಿ ನಡೆಸುತ್ತಾನೆ.');

    // 6. Joshua 1:9 (book 6, ch 1, v 9)
    _addVerse('WEB', 6, 1, 9,
        'Haven’t I commanded you? Be strong and courageous. Don’t be afraid. Don’t be dismayed, for Yahweh your God is with you wherever you go.');
    _addVerse('KJV', 6, 1, 9,
        'Have not I commanded thee? Be strong and of a good courage; be not afraid, neither be thou dismayed: for the LORD thy God is with thee whithersoever thou goest.');
    _addVerse('MSG', 6, 1, 9,
        'Haven’t I commanded you? Strength! Courage! Don’t be timid; don’t get discouraged. God, your God, is with you every step you take.');
    _addVerse('TLB', 6, 1, 9,
        'Yes, be bold and strong! Banish fear and doubt! For the Lord your God is with you wherever you go.');
    _addVerse('NASB', 6, 1, 9,
        'Have I not commanded you? Be strong and courageous! Do not tremble or be dismayed, for the LORD your God is with you wherever you go.');
    _addVerse('TAOBVSI', 6, 1, 9,
        'நான் உனக்குக் கட்டளையிடவில்லையா? பலங்கொண்டு திடமனதாயிரு; திகையாதே, கலங்காதே, நீ போகும் இடமெல்லாம் உன் தேவனாகிய கர்த்தர் உன்னோடே இருக்கிறார் என்றார்.');
    _addVerse('MAL_IRV', 6, 1, 9,
        'ധൈര്യവും ബലവുമുള്ളവനായിരിക്കുക എന്ന് ഞാൻ നിന്നോട് കൽപിച്ചില്ലയോ? ഭയപ്പെടരുത്, പരിഭ്രമിക്കുകയും അരുത്; നീ പോകുന്നിടത്തൊക്കെയും നിന്റെ ദൈവമായ യഹോവ നിന്നോടുകൂടെയുണ്ട്.');
    _addVerse('TEL_IRV', 6, 1, 9,
        'ధైర్యంగా ఉండు, దృఢచిత్తము కలిగియుండు అని నేను నీకు ఆజ్ఞాపించలేదా? భయపడకు, దిగులుపడకు; నీవు వెళ్ళు ప్రతి స్థలమందు నీ దేవుడైన యెహోవా నీకు తోడైయుండును.');
    _addVerse('HIN_IRV', 6, 1, 9,
        'क्या मैंने तुझे आज्ञा नहीं दी? हियाव बान्ध और दृढ़ हो जा; भय न खा, और तेरा मन कच्चा न हो; क्योंकि जहाँ जहाँ तू जाएगा वहाँ वहाँ तेरा परमेश्वर यहोवा तेरे संग रहेगा।');
    _addVerse('KAN_IRV', 6, 1, 9,
        'ಧೈರ್ಯವಾಗಿರು, ದೃಢವಾಗಿರು ಎಂದು ನಿನಗೆ ಆಜ್ಞಾಪಿಸಲಿಲ್ಲವೇ? ಹೆದರಬೇಡ, ಕಳವಳಗೊಳ್ಳಬೇಡ; ನೀನು ಹೋಗುವ ಕಡೆಯಲ್ಲೆಲ್ಲಾ ನಿನ್ನ ದೇವರಾದ ಯೆಹೋವನು ನಿನ್ನ ಸಂಗಡ ಇರುವನು.');

    // 7. Romans 8:28 (book 45, ch 8, v 28)
    _addVerse('WEB', 45, 8, 28,
        'We know that all things work together for good for those who love God, to those who are called according to his purpose.');
    _addVerse('KJV', 45, 8, 28,
        'And we know that all things work together for good to them that love God, to them who are the called according to his purpose.');
    _addVerse('MSG', 45, 8, 28,
        'That’s why we can be so sure that every detail in our lives of love for God is worked into something good.');
    _addVerse('TLB', 45, 8, 28,
        'And we know that all that happens to us is working for our good if we love God and are fitting into his plans.');
    _addVerse('NASB', 45, 8, 28,
        'And we know that God causes all things to work together for good to those who love God, to those who are called according to His purpose.');
    _addVerse('TAOBVSI', 45, 8, 28,
        'அன்றியும், அவருடைய தீர்மானத்தின்படி அழைக்கப்பட்டவர்களாய் தேவனிடத்தில் அன்புகூருகிறவர்களுக்குச் சகலமும் நன்மைக்கு ஏதுவாக நடக்கிறது என்று அறிந்திருக்கிறோம்.');
    _addVerse('MAL_IRV', 45, 8, 28,
        'ദൈവത്തെ സ്നേഹിക്കുന്നവർക്ക്, അവിടുത്തെ നിർണ്ണയപ്രകാരം വിളിക്കപ്പെട്ടവർക്ക് തന്നെ, സകലവും നന്മയ്ക്കായി കൂടിവ്യാപരിക്കുന്നു എന്ന് നാം അറിയുന്നു.');
    _addVerse('TEL_IRV', 45, 8, 28,
        'దేవుని ప్రేమించువారికి, అనగా ఆయన సంకల్పం ప్రకారం పిలువబడిన వారికి సమస్తమూ మేలు కొరకే సమకూడి జరుగుచున్నవని ఎరుగుదుము.');
    _addVerse('HIN_IRV', 45, 8, 28,
        'और हम जानते हैं कि जो लोग परमेश्वर से प्रेम रखते हैं, उनके लिये सब बातें मिलकर भलाई ही को उत्पन्न करती हैं, अर्थात् उन्हीं के लिये जो उसकी इच्छा के अनुसार बुलाए हुए हैं।');
    _addVerse('KAN_IRV', 45, 8, 28,
        'ದೇವರನ್ನು ಪ್ರೀತಿಸುವವರಿಗೆ, ಅಂದರೆ ಆತನ ಸಂಕಲ್ಪದಂತೆ ಕರೆಯಲ್ಪಟ್ಟವರಿಗೆ ಎಲ್ಲವೂ ಒಳಿತಿಗಾಗಿಯೇ ಒಟ್ಟಾಗಿ ನಡೆಯುತ್ತವೆ ಎಂದು ನಾವು ಬಲ್ಲೆವು.');

    // 8. Isaiah 40:31 (book 23, ch 40, v 31)
    _addVerse('WEB', 23, 40, 31,
        'But those who wait for Yahweh will renew their strength. They will mount up with wings like eagles. They will run, and not be weary. They will walk, and not faint.');
    _addVerse('KJV', 23, 40, 31,
        'But they that wait upon the LORD shall renew their strength; they shall mount up with wings as eagles; they shall run, and not be weary; and they shall walk, and not faint.');
    _addVerse('MSG', 23, 40, 31,
        'Those who wait upon God get fresh strength. They spread their wings and soar like eagles, they run and don’t get tired, they walk and don’t lag behind.');
    _addVerse('TLB', 23, 40, 31,
        'Those who wait upon the Lord will find new strength. They will soar high on wings like eagles. They will run and not grow weary. They will walk and not faint.');
    _addVerse('NASB', 23, 40, 31,
        'Yet those who wait for the LORD will gain new strength; they will mount up with wings like eagles, they will run and not get tired, they will walk and not become weary.');
    _addVerse('TAOBVSI', 23, 40, 31,
        'கர்த்தருக்குக் காத்திருக்கிறவர்களோ புதுப்பெலன் அடைந்து, கழுகுகளைப்போலச் செட்டைகளை அடித்து எழும்புவார்கள்; அவர்கள் ஓடினாலும் இளைப்படையார்கள், நடந்தாலும் சோர்ந்துபோகார்கள்.');
    _addVerse('MAL_IRV', 23, 40, 31,
        'യഹോവയെ കാത്തിരിക്കുന്നവരോ പുതുശക്തി പ്രാപിക്കും; അവർ കഴുകന്മാരെപ്പോലെ ചിറകടിച്ചുയരും; അവർ ഓടിയാലും ക്ഷീണിക്കുകയില്ല; നടന്നാലും തളർന്നുപോകയില്ല.');
    _addVerse('TEL_IRV', 23, 40, 31,
        'యెహోవా కొరకు ఎదురుచూచువారు నూతన బలము పొందుదురు; వారు గద్దలవలె రెక్కలు చాపి పైకి ఎగురుదురు; వారు అలయక పరుగెత్తుదురు, సొమ్మసిల్లక నడచుదురు.');
    _addVerse('HIN_IRV', 23, 40, 31,
        'परन्तु जो यहोवा की बाट जोहते हैं, वे नया बल प्राप्त करते जाएंगे, वे उकाबों की नाईं उड़ेंगे, वे दौड़ेंगे और श्रमित न होंगे, चलेंगे और थकित न होंगे।');
    _addVerse('KAN_IRV', 23, 40, 31,
        'ಆದರೆ ಯೆಹೋವನ ಮೇಲೆ ನಿರೀಕ್ಷೆಯಿಡುವವರು ಹೊಸ ಬಲವನ್ನು ಹೊಂದುವರು; ಅವರು ಹದ್ದುಗಳಂತೆ ರೆಕ್ಕೆಗಳನ್ನು ಚಾಚಿ ಮೇಲಕ್ಕೆ ಹಾರುವರು; ಅವರು ಓಡಿದರೂ ದಣಿಯರು, ನಡೆದರೂ ಆಯಾಸಗೊಳ್ಳರು.');

    // 9. Proverbs 3:5-6 (book 20, ch 3, v 5 & 6)
    _addVerse('WEB', 20, 3, 5,
        'Trust in Yahweh with all your heart, and don’t lean on your own understanding.');
    _addVerse('WEB', 20, 3, 6,
        'In all your ways acknowledge him, and he will make your paths straight.');
    _addVerse('KJV', 20, 3, 5,
        'Trust in the LORD with all thine heart; and lean not unto thine own understanding.');
    _addVerse('KJV', 20, 3, 6,
        'In all thy ways acknowledge him, and he shall direct thy paths.');
    _addVerse('MSG', 20, 3, 5,
        'Trust God from the bottom of your heart; don’t try to figure out everything on your own.');
    _addVerse('MSG', 20, 3, 6,
        'Listen for God’s voice in everything you do, everywhere you go; he’s the one who will keep you on track.');
    _addVerse('TLB', 20, 3, 5,
        'Trust the Lord completely; don’t ever trust yourself.');
    _addVerse('TLB', 20, 3, 6,
        'In everything you do, put God first, and he will direct you and crown your efforts with success.');
    _addVerse('NASB', 20, 3, 5,
        'Trust in the LORD with all your heart and do not lean on your own understanding.');
    _addVerse('NASB', 20, 3, 6,
        'In all your ways acknowledge Him, and He will make your paths straight.');
    _addVerse('TAOBVSI', 20, 3, 5,
        'உன் சுயபுத்தியின்மேல் சாயாமல், உன் முழு இருதயத்தோடும் கர்த்தரில் நம்பிக்கையாயிருந்து;');
    _addVerse('TAOBVSI', 20, 3, 6,
        'உன் வழிகளிலெல்லாம் அவரை நினைத்துக்கொள்; அப்பொழுது அவர் உன் பாதைகளைச் செவ்வைப்படுத்துவார்.');
    _addVerse('MAL_IRV', 20, 3, 5,
        'പൂർണ്ണഹൃദയത്തോടെ യഹോവയിൽ ആശ്രയിക്കുക; സ്വന്ത വിവേകത്തിൽ ഊന്നരുത്.');
    _addVerse('MAL_IRV', 20, 3, 6,
        'നിന്റെ എല്ലാ വഴികളിലും അവിടുത്തെ വിചാരിച്ചുകൊള്ളുക; അവിടുന്ന് നിന്റെ പാതകളെ നേരെയാക്കും.');
    _addVerse('TEL_IRV', 20, 3, 5,
        'నీ పూర్ణహృదయంతో యెహోవాయందు నమ్మకముంచుము, నీ స్వబుద్ధిని ఆధారము చేసికొనవద్దు.');
    _addVerse('TEL_IRV', 20, 3, 6,
        'నీ మార్గములన్నిటిలో ఆయనను గుర్తింపుము, అప్పుడు ఆయన నీ త్రోవలను సరాళము చేయును.');
    _addVerse('HIN_IRV', 20, 3, 5,
        'तू अपनी समझ का सहारा न लेना, वरन् सम्पूर्ण मन से यहोवा पर भरोसा रखना।');
    _addVerse('HIN_IRV', 20, 3, 6,
        'उसी को स्मरण करके सब काम करना, तब वह तेरे लिये सीधा मार्ग निकालेगा।');
    _addVerse('KAN_IRV', 20, 3, 5,
        'ನಿನ್ನ ಸ್ವಂತ ವಿವೇಕವನ್ನು ಆಧಾರಮಾಡಿಕೊಳ್ಳದೆ ಪೂರ್ಣಹೃದಯದಿಂದ ಯೆಹೋವನಲ್ಲಿ ಭರವಸವಿಡು.');
    _addVerse('KAN_IRV', 20, 3, 6,
        'ನಿನ್ನ ಎಲ್ಲಾ ಮಾರ್ಗಗಳಲ್ಲಿ ಆತನನ್ನು ಸಮ್ಮತಿಸು, ಆಗ ಆತನೇ ನಿನ್ನ ಹಾದಿಗಳನ್ನು ಸರಾಗಮಾಡುವನು.');

    // 10. Matthew 11:28 (book 40, ch 11, v 28)
    _addVerse('WEB', 40, 11, 28,
        '“Come to me, all you who labor and are heavily burdened, and I will give you rest.”');
    _addVerse('KJV', 40, 11, 28,
        'Come unto me, all ye that labour and are heavy laden, and I will give you rest.');
    _addVerse('MSG', 40, 11, 28,
        '“Are you tired? Worn out? Burned out on religion? Come to me. Get away with me and you’ll recover your life. I’ll show you how to take a real rest.”');
    _addVerse('TLB', 40, 11, 28,
        '“Come to me, all of you who are weary and carry heavy burdens, and I will give you rest.”');
    _addVerse('NASB', 40, 11, 28,
        '“Come to Me, all who are weary and heavy-laden, and I will give you rest.”');
    _addVerse('TAOBVSI', 40, 11, 28,
        'வருத்தப்பட்டுப் பாரஞ்சுமக்கிறவர்களே! நீங்கள் எல்லாரும் என்னிடத்தில் வாருங்கள், நான் உங்களுக்கு இளைப்பாறுதல் தருவேன்.');
    _addVerse('MAL_IRV', 40, 11, 28,
        'അധ്വാനിക്കുന്നവരും ഭാരം ചുമക്കുന്നവരുമായുള്ളവരേ, എല്ലാവരും എന്റെ അടുക്കൽ വരുവിൻ; ഞാൻ നിങ്ങളെ ആശ്വസിപ്പിക്കാം.');
    _addVerse('TEL_IRV', 40, 11, 28,
        'ప్రయాసపడి భారం మోయుచున్న సమస్త జనులారా, నా యొద్దకు రండి; నేను మీకు విశ్రాంతిని కలుగజేతును.');
    _addVerse('HIN_IRV', 40, 11, 28,
        'हे सब परिश्रम करनेवालों और बोझ से दबे हुए लोगों, मेरे पास आओ; मैं तुम्हें विश्राम दूंगा।');
    _addVerse('KAN_IRV', 40, 11, 28,
        'ಪ್ರಯಾಸಪಡುವವರೇ, ಭಾರಹೊತ್ತವರೇ, ನೀವೆಲ್ಲರೂ ನನ್ನ ಬಳಿಗೆ ಬನ್ನಿರಿ; ನಾನು ನಿಮಗೆ ವಿಶ್ರಾಂತಿ ಕೊಡುವೆನು.');

    // 11. 1 Peter 5:7 (book 60, ch 5, v 7)
    _addVerse('WEB', 60, 5, 7,
        'Casting all your worries on him, because he cares for you.');
    _addVerse('KJV', 60, 5, 7,
        'Casting all your care upon him; for he careth for you.');
    _addVerse('MSG', 60, 5, 7,
        'Live carefree before God; he is most careful with you.');
    _addVerse('TLB', 60, 5, 7,
        'Let him have all your worries and cares, for he is always thinking about you and watching everything that concerns you.');
    _addVerse('NASB', 60, 5, 7,
        'Casting all your anxiety on Him, because He cares for you.');
    _addVerse('TAOBVSI', 60, 5, 7,
        'அவர் உங்களை விசாரிக்கிறவரானபடியால், உங்கள் கவலைகளையெல்லாம் அவர்மேல் வைத்துவிடுங்கள்.');
    _addVerse('MAL_IRV', 60, 5, 7,
        'അവൻ നിങ്ങൾക്കായി കരുതുന്നതുകൊണ്ട് നിങ്ങളുടെ സകല ചിന്താകുലങ്ങളും അവിടുത്തെ മേൽ ഇട്ടുകൊള്ളുവിൻ.');
    _addVerse('TEL_IRV', 60, 5, 7,
        'ఆయన మిమ్మును గూర్చి చింతించుచున్నాడు గనుక మీ చింత యావత్తు ఆయనపై వేయుడి.');
    _addVerse('HIN_IRV', 60, 5, 7,
        'अपनी सारी चिन्ता उसी पर डाल दो, क्योंकि उसको तुम्हारा ध्यान है।');
    _addVerse('KAN_IRV', 60, 5, 7,
        'ಆತನು ನಿಮ್ಮನ್ನು ಚಿಂತಿಸುವುದರಿಂದ ನಿಮ್ಮ ಎಲ್ಲಾ ಚಿಂತೆಗಳನ್ನು ಆತನ ಮೇಲೆ ಹಾಕಿರಿ.');

    // 12. Isaiah 41:10 (book 23, ch 41, v 10)
    _addVerse('WEB', 23, 41, 10,
        'Don’t you be afraid, for I am with you. Don’t be dismayed, for I am your God. I will strengthen you. Yes, I will help you.');
    _addVerse('KJV', 23, 41, 10,
        'Fear thou not; for I am with thee: be not dismayed; for I am thy God: I will strengthen thee; yea, I will help thee.');
    _addVerse('MSG', 23, 41, 10,
        'Don’t panic. I’m with you. There’s no need to fear for I’m your God. I’ll give you strength. I’ll help you. I’ll hold you steady, keep a firm grip on you.');
    _addVerse('TLB', 23, 41, 10,
        'Fear not, for I am with you. Do not be dismayed. I am your God. I will strengthen you; I will help you; I will uphold you with my victorious right hand.');
    _addVerse('NASB', 23, 41, 10,
        'Do not fear, for I am with you; do not anxiously look about you, for I am your God. I will strengthen you, surely I will help you, surely I will uphold you with My righteous right hand.');
    _addVerse('TAOBVSI', 23, 41, 10,
        'நீ பயப்படாதே, நான் உன்னுடனே இருக்கிறேன்; திகையாதே, நான் உன் தேவன்; நான் உன்னைப் பலப்படுத்தி உனக்குச் சகாயம்பண்ணுவேன்.');
    _addVerse('MAL_IRV', 23, 41, 10,
        'നീ ഭയപ്പെടേണ്ട, ഞാൻ നിന്നോടുകൂടെയുണ്ട്; ഭ്രമിച്ചുനോക്കേണ്ട, ഞാൻ നിന്റെ ദൈവമാകുന്നു; ഞാൻ നിന്നെ ശക്തീകരിക്കും; ഞാൻ നിന്നെ സഹായിക്കും.');
    _addVerse('TEL_IRV', 23, 41, 10,
        'భయపడకుము నేను నీకు తోడైయున్నాను; దిగులుపడకుము నేను నీ దేవుడనై యున్నాను; నేను నిన్ను బలపరుతును, నీకు సహాయము చేయుదును.');
    _addVerse('HIN_IRV', 23, 41, 10,
        'मत डर, क्योंकि मैं तेरे संग हूँ, इधर-उधर मत ताक, क्योंकि मैं तेरा परमेश्वर हूँ; मैं तुझे दृढ़ करूंगा और तेरी सहायता करूंगा।');
    _addVerse('KAN_IRV', 23, 41, 10,
        'ಹೆದರಬೇಡ, ನಾನು ನಿನ್ನ ಸಂಗಡ ಇದ್ದೇನೆ; ಕಳವಳಗೊಳ್ಳಬೇಡ, ನಾನೇ ನಿನ್ನ ದೇವರು; ನಾನು ನಿನ್ನನ್ನು ಬಲಪಡಿಸುವೆನು, ನಿನಗೆ ಸಹಾಯಮಾಡುವೆನು.');

    // 13. Philippians 4:13 (book 50, ch 4, v 13)
    _addVerse('WEB', 50, 4, 13,
        'I can do all things through Christ, who strengthens me.');
    _addVerse('KJV', 50, 4, 13,
        'I can do all things through Christ which strengtheneth me.');
    _addVerse('MSG', 50, 4, 13,
        'Whatever I have, wherever I am, I can make it through anything in the One who makes me who I am.');
    _addVerse('TLB', 50, 4, 13,
        'for I can do everything God asks me to with the help of Christ who gives me the strength and power.');
    _addVerse('NASB', 50, 4, 13,
        'I can do all things through Him who strengthens me.');
    _addVerse('TAOBVSI', 50, 4, 13,
        'என்னைப் பெலப்படுத்துகிற கிறிஸ்துவினாலே எல்லாவற்றையுஞ்செய்ய எனக்குப் பெலனுண்டு.');
    _addVerse('MAL_IRV', 50, 4, 13,
        'എന്നെ ശക്തനാക്കുന്ന ക്രിസ്തു മുഖാന്തരം ഞാൻ സകലത്തിനും പ്രാപ്തനാകുന്നു.');
    _addVerse('TEL_IRV', 50, 4, 13,
        'నన్ను బలపరచు క్రీస్తునందే నేను సమస్తమును చేయగలను.');
    _addVerse('HIN_IRV', 50, 4, 13,
        'जो मुझे सामर्थ्य देता है उसमें मैं सब कुछ कर सकता हूँ।');
    _addVerse('KAN_IRV', 50, 4, 13,
        'ನನ್ನನ್ನು ಬಲಪಡಿಸುವ ಕ್ರಿಸ್ತನಲ್ಲಿ ನಾನು ಎಲ್ಲವನ್ನೂ ಮಾಡಬಲ್ಲೆನು.');

    // 14. 2 Timothy 1:7 (book 55, ch 1, v 7)
    _addVerse('WEB', 55, 1, 7,
        'For God didn’t give us a spirit of fear, but of power, love, and self-control.');
    _addVerse('KJV', 55, 1, 7,
        'For God hath not given us the spirit of fear; but of power, and of love, and of a sound mind.');
    _addVerse('MSG', 55, 1, 7,
        'God doesn’t want us to be shy with his gifts, but bold and loving and sensible.');
    _addVerse('TLB', 55, 1, 7,
        'For the Holy Spirit, God’s gift, does not want you to be afraid of people, but to be wise and strong, and to love them and enjoy being with them.');
    _addVerse('NASB', 55, 1, 7,
        'For God has not given us a spirit of timidity, but of power and love and discipline.');
    _addVerse('TAOBVSI', 55, 1, 7,
        'தேவன் நமக்குப் பயமுள்ள ஆவியைக் கொடாமல், பலமும் அன்பும் தெளிந்த புத்தியுமுள்ள ஆவியையே கொடுத்திருக்கிறார்.');
    _addVerse('MAL_IRV', 55, 1, 7,
        'ഭയത്തിന്റെ ആത്മാവിനെയല്ല, ശക്തിയുടെയും സ്നേഹത്തിന്റെയും സമചിത്തതയുടെയും ആത്മാവിനെയത്രേ ദൈവം നമുക്ക് തന്നത്.');
    _addVerse('TEL_IRV', 55, 1, 7,
        'దేవుడు మనకు భయముగల ఆత్మను ఇవ్వలేదు గాని శక్తియు ప్రేమయు నిగ్రహముగల ఆత్మనే ఇచ్చెను.');
    _addVerse('HIN_IRV', 55, 1, 7,
        'क्योंकि परमेश्वर ने हमें भय की नहीं पर सामर्थ्य, और प्रेम, और संयम की आत्मा दी है।');
    _addVerse('KAN_IRV', 55, 1, 7,
        'ದೇವರು ನಮಗೆ ಭಯದ ಆತ್ಮವನ್ನು ಕೊಡದೆ ಶಕ್ತಿಯ, ಪ್ರೀತಿಯ ಮತ್ತು ಸ್ವಸ್ಥಬುದ್ಧಿಯ ಆತ್ಮವನ್ನೇ ಕೊಟ್ಟಿದ್ದಾನೆ.');

    // 15. Psalm 46:1 (book 19, ch 46, v 1)
    _addVerse('WEB', 19, 46, 1,
        'God is our refuge and strength, a very present help in trouble.');
    _addVerse('KJV', 19, 46, 1,
        'God is our refuge and strength, a very present help in trouble.');
    _addVerse('MSG', 19, 46, 1,
        'God is a safe place to hide, ready to help when we need him.');
    _addVerse('TLB', 19, 46, 1,
        'God is our refuge and strength, a tested help in times of trouble.');
    _addVerse('NASB', 19, 46, 1,
        'God is our refuge and strength, a very present help in trouble.');
    _addVerse('TAOBVSI', 19, 46, 1,
        'தேவன் நமக்கு அடைக்கலமும் பெலனும், ஆபத்துக்காலத்தில் அநுகூலமான துணையுமானவர்.');
    _addVerse('MAL_IRV', 19, 46, 1,
        'ദൈവം നമ്മുടെ സങ്കേതവും ബലവും ആകുന്നു; കഷ്ടങ്ങളിൽ അവൻ ഏറ്റവും അടുത്ത തുണയായി കാണപ്പെടുന്നു.');
    _addVerse('TEL_IRV', 19, 46, 1,
        'దేవుడు మనకు ఆశ్రయమును దుర్గమునై యున్నాడు, ఆపత్కాలములో ఆయన అత్యంత సన్నిహితమైన సహాయకుడు.');
    _addVerse('HIN_IRV', 19, 46, 1,
        'परमेश्वर हमारा शरणस्थान और बल है, संकट में अति सहज से मिलनेवाला सहायक।');
    _addVerse('KAN_IRV', 19, 46, 1,
        'ದೇವರು ನಮ್ಮ ಆಶ್ರಯವೂ ಬಲವೂ ಆಗಿದ್ದಾನೆ, ಇಕ್ಕಟ್ಟಿನಲ್ಲಿ ಅತಿ ಸನಿಹದ ಸಹಾಯಕನು.');
  }

  Future<void> _seedDefaultBibles(Database db) async {
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();

    for (final versionId in _webInstalledVersions) {
      batch.insert(
        'installed_versions',
        {
          'id': versionId,
          'name': versionId,
          'language': 'Multi',
          'language_code': 'multi',
          'size_display': '1.5 MB',
          'installed_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    _webVerses.forEach((key, text) {
      final parts = key.split('_');
      if (parts.length == 4) {
        batch.insert('verses', {
          'version_id': parts[0],
          'book_number': int.tryParse(parts[1]) ?? 0,
          'book_name': '',
          'chapter': int.tryParse(parts[2]) ?? 0,
          'verse': int.tryParse(parts[3]) ?? 0,
          'text': text,
        });
      }
    });

    await batch.commit(noResult: true);
  }

  String? resolvePassageSync({
    required String versionId,
    required int bookNumber,
    required int chapter,
    required int startVerse,
    int? endVerse,
  }) {
    final end = endVerse ?? startVerse;
    final List<String> parts = [];
    for (int v = startVerse; v <= end; v++) {
      final key = '${versionId}_${bookNumber}_${chapter}_$v';
      if (_webVerses.containsKey(key)) {
        parts.add(_webVerses[key]!);
      }
    }
    if (parts.isNotEmpty) return parts.join(' ');
    return null;
  }

  Future<String?> resolvePassage({
    required String versionId,
    required int bookNumber,
    required int chapter,
    required int startVerse,
    int? endVerse,
  }) async {
    final end = endVerse ?? startVerse;

    // 1. Check in-memory instant resolution map first (0ms latency, works on both Web & Mobile)
    final syncText = resolvePassageSync(
      versionId: versionId,
      bookNumber: bookNumber,
      chapter: chapter,
      startVerse: startVerse,
      endVerse: end,
    );
    if (syncText != null) return syncText;

    // 2. Check local SQLite DB on Mobile if not in memory
    final db = _db;
    if (db != null) {
      final results = await db.query(
        'verses',
        columns: ['text'],
        where:
            'version_id = ? AND book_number = ? AND chapter = ? AND verse >= ? AND verse <= ?',
        whereArgs: [versionId, bookNumber, chapter, startVerse, end],
        orderBy: 'verse ASC',
      );

      if (results.isNotEmpty) {
        return results.map((r) => r['text'] as String).join(' ');
      }
    }

    return null;
  }

  Future<List<String>> getInstalledVersionIds() async {
    if (kIsWeb) {
      return _webInstalledVersions.toList();
    }

    final db = _db;
    if (db == null) return _webInstalledVersions.toList();

    final results = await db.query('installed_versions', columns: ['id']);
    return results.map((r) => r['id'] as String).toList();
  }

  Future<void> registerInstalledVersion({
    required String id,
    required String name,
    required String language,
    required String languageCode,
    required String sizeDisplay,
  }) async {
    _webInstalledVersions.add(id);

    final db = _db;
    if (db == null) return;

    await db.insert(
      'installed_versions',
      {
        'id': id,
        'name': name,
        'language': language,
        'language_code': languageCode,
        'size_display': sizeDisplay,
        'installed_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertVerses(
      String versionId, List<Map<String, dynamic>> verses) async {
    for (final v in verses) {
      final book = v['bookNumber'] ?? v['book_number'];
      final chapter = v['chapter'];
      final verse = v['verse'];
      final text = v['text'];
      _webVerses['${versionId}_${book}_${chapter}_$verse'] = text;
    }

    final db = _db;
    if (db == null) return;

    final batch = db.batch();
    for (final v in verses) {
      batch.insert(
        'verses',
        {
          'version_id': versionId,
          'book_number': v['bookNumber'] ?? v['book_number'] ?? 0,
          'book_name': v['bookName'] ?? v['book_name'] ?? '',
          'chapter': v['chapter'] ?? 0,
          'verse': v['verse'] ?? 0,
          'text': v['text'] ?? '',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteVersion(String versionId) async {
    _webInstalledVersions.remove(versionId);
    _webVerses.removeWhere((key, _) => key.startsWith('${versionId}_'));

    if (kIsWeb) return;
    if (_db == null) await initialize();

    await _db!.delete(
      'verses',
      where: 'version_id = ?',
      whereArgs: [versionId],
    );

    await _db!.delete(
      'installed_versions',
      where: 'id = ?',
      whereArgs: [versionId],
    );
  }

  Future<List<Map<String, dynamic>>> getChapter(String versionId, String bookName, int chapter) async {
    if (kIsWeb) {
      // In web, we could return dummy data or filter _webVerses if we wanted full web support.
      // For now, return empty or a basic list if it matches a seeded verse.
      List<Map<String, dynamic>> results = [];
      _webVerses.forEach((key, value) {
        final parts = key.split('_');
        if (parts[0] == versionId && parts[2] == chapter.toString()) {
          // Simplistic web fallback - doesn't have full book names mapped to numbers here easily
          results.add({
            'verse': int.tryParse(parts[3]) ?? 1,
            'text': value,
          });
        }
      });
      results.sort((a, b) => (a['verse'] as int).compareTo(b['verse'] as int));
      return results;
    }

    if (_db == null) await initialize();

    final List<Map<String, dynamic>> maps = await _db!.query(
      'verses',
      where: 'version_id = ? AND book_name = ? AND chapter = ?',
      whereArgs: [versionId, bookName, chapter],
      orderBy: 'verse ASC',
    );

    return maps;
  }
}
