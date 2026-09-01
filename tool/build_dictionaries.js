#!/usr/bin/env node
/**
 * tool/build_dictionaries.js
 *
 * Compiles modular SQLite dictionary packages for:
 *  - en: English Dictionary
 *  - eastons: Easton's Bible Dictionary
 *  - strongs: Strong's Greek & Hebrew Lexicon
 *  - es: Spanish Dictionary
 *  - fr: French Dictionary
 *  - de: German Dictionary
 *  - pt: Portuguese Dictionary
 *  - ru: Russian Dictionary
 *  - hi: Hindi Dictionary
 *  - ta: Tamil Dictionary
 *
 * Each dictionary produces:
 *  data/dictionaries_published/dict_<id>.sqlite.gz
 *
 * Output is pushed to Christian-Tube-Releases/dictionaries/
 */

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { DatabaseSync } = require('node:sqlite');

const OUT_DIR = path.join(__dirname, '..', 'data', 'dictionaries_published');
if (!fs.existsSync(OUT_DIR)) {
  fs.mkdirSync(OUT_DIR, { recursive: true });
}

// 1. Easton's Bible Dictionary Seed & Historical Glossary
const EASTONS_ENTRIES = [
  ['Aaron', 'noun', "âr'on", 'Light; bringing light. The brother of Moses and first high priest of Israel (Ex. 28:1).', 'He was consecrated by Moses.'],
  ['Abaddon', 'noun', 'a-bad\'un', 'Destruction. The Hebrew name for the place of ruin or the king of the abyss (Rev. 9:11).', 'In Greek called Apollyon.'],
  ['Abba', 'noun', "ab'ba", 'Aramaic word for "father", expressive of warm, trusting filial intimacy with God (Rom. 8:15; Gal. 4:6).', 'Abba, Father, all things are possible unto thee.'],
  ['Abraham', 'noun', "a'bra-ham", 'Father of a great multitude. The patriarch chosen by God to receive the covenant of faith (Gen. 12; 15; 17).', 'Abraham believed God, and it was credited to him as righteousness.'],
  ['Adoption', 'noun', 'a-dop\'shun', 'The legal and spiritual act wherein God receives believers as His own sons and daughters, making them joint heirs with Christ (Eph. 1:5).', 'You received the Spirit of adoption.'],
  ['Advocate', 'noun', "ad'vo-kat", 'One called to stand by another; a defense counselor or intercessor. Applied to Jesus Christ (1 John 2:1) and the Holy Spirit (John 14:16).', 'We have an Advocate with the Father, Jesus Christ the righteous.'],
  ['Altar', 'noun', "awl'ter", 'A raised structure upon which sacrifices or offerings are presented to God in worship (Gen. 8:20; Heb. 13:10).', 'Noah built an altar unto the Lord.'],
  ['Amen', 'adverb', "ah-men'", 'True, faithful, so be it. A solemn affirmation of truth, used as a title of Christ in Revelation 3:14.', 'These things says the Amen, the faithful and true witness.'],
  ['Angel', 'noun', "an'jel", 'A heavenly messenger and spiritual being sent forth to minister to those who inherit salvation (Heb. 1:14).', 'An angel of the Lord appeared unto him.'],
  ['Anointing', 'noun', "a-noint'ing", 'The setting apart of persons or objects by pouring oil upon them; symbolically, the empowering impartation of the Holy Spirit (1 John 2:20, 27).', 'You have an anointing from the Holy One.'],
  ['Apostle', 'noun', "a-pos'sl", 'One sent forth with a specific commission and authority. Specifically applied to the Twelve and Paul (Luke 6:13; Rom. 1:1).', 'Paul, an apostle of Jesus Christ.'],
  ['Ark of the Covenant', 'noun', "ahrk", 'The sacred acacia chest overlaid with gold, housing the tablets of the Law, Aaron\'s rod, and the manna, overshadowed by the cherubim of glory (Ex. 25:10-22).', 'The ark rested in the holy of holies.'],
  ['Ascension', 'noun', 'a-sen\'shun', 'The visible bodily rising of Jesus Christ into heaven forty days after His resurrection (Acts 1:9-11).', 'He was taken up, and a cloud received Him.'],
  ['Atonement', 'noun', 'a-ton\'ment', 'Reconciliation, propitiation; the covering and removing of sin through the sacrificial death of Jesus Christ on the cross (Rom. 5:11; Heb. 9:14).', 'Through our Lord Jesus Christ we have received the atonement.'],
  ['Baptism', 'noun', "bap'tizm", 'Immersion; an ordinance commanded by Christ signifying burial with Him in death and rising to walk in newness of life (Matt. 28:19; Rom. 6:4).', 'Buried with Him in baptism.'],
  ['Beatitudes', 'noun', 'be-at\'i-tudes', 'The declarations of divine blessing pronounced by Jesus at the opening of the Sermon on the Mount (Matt. 5:3-12).', 'Blessed are the poor in spirit.'],
  ['Believer', 'noun', 'be-leev\'er', 'One who puts wholehearted faith, trust, and obedience in Jesus Christ as Lord and Savior (Acts 5:14).', 'Believers were the more added to the Lord.'],
  ['Bethlehem', 'noun', "beth'le-hem", 'House of bread. The historic city of David where Jesus the Messiah was born according to prophecy (Micah 5:2; Matt. 2:1).', 'Joseph went up from Galilee to Bethlehem.'],
  ['Born Again', 'adjective', "bawrn a-gen'", 'Spiritual regeneration by the Holy Spirit and the Word of God, entering the kingdom of heaven (John 3:3-7; 1 Pet. 1:23).', 'Unless one is born again, he cannot see the kingdom of God.'],
  ['Calvary', 'noun', "kal'va-ri", 'The place of the skull (Golgotha), the hill outside Jerusalem where Christ was crucified (Luke 23:33).', 'There they crucified Him.'],
  ['Christ', 'noun', "kryst", 'The Anointed One; the Greek equivalent of the Hebrew Messiah (John 1:41; Matt. 16:16).', 'You are the Christ, the Son of the living God.'],
  ['Church', 'noun', "chyrch", 'The body of Christ; the called-out assembly of redeemed believers in every place (Matt. 16:18; Eph. 1:22-23).', 'I will build my church, and the gates of Hades shall not prevail.'],
  ['Circumcision of Heart', 'noun', 'ser-kum-sizh\'un', 'The spiritual cutting away of the fleshly, self-centered nature by the Holy Spirit (Rom. 2:29; Col. 2:11).', 'Circumcision is of the heart, in the Spirit.'],
  ['Conscience', 'noun', "kon'shens", 'The internal moral witness given by God to bear testimony concerning thoughts, motives, and deeds (Acts 24:16; 1 Tim. 1:5).', 'I strive always to keep my conscience clear before God.'],
  ['Covenant', 'noun', "kuv'e-nant", 'A solemn, binding agreement between God and man established on divine promises and blood (Heb. 8:6-13).', 'This is the new covenant in my blood.'],
  ['Cross', 'noun', "kros", 'The instrument of Christ\'s sacrificial death, and the daily principle of dying to self to follow Him (Luke 9:23; Gal. 6:14).', 'Take up your cross daily and follow Me.'],
  ['Deacon', 'noun', "dee'kon", 'A servant; a recognized servant-leader in the local church assisting elders with practical administration (1 Tim. 3:8-13).', 'Deacons must be men worthy of respect.'],
  ['Disciple', 'noun', "di-sy'pl", 'A learner and follower who sits at the feet of Jesus to live as He lived, taking His yoke upon them (Matt. 28:19; Luke 14:26-33).', 'If you abide in my word, you are truly my disciples.'],
  ['Elder', 'noun', "el'der", 'A mature spiritual leader and overseer tasked with shepherding the flock of God without seeking personal gain (1 Pet. 5:1-4; Titus 1:5-9).', 'Shepherd the flock of God which is among you.'],
  ['Faith', 'noun', "fayth", 'Complete reliance upon and submission to God\'s Word, acting upon divine truth regardless of sight or feelings (Heb. 11:1; 2 Cor. 5:7).', 'Faith is the substance of things hoped for.'],
  ['Fast', 'verb', "fast", 'Abstaining from food for a period to seek God in prayer, humility, and spiritual focus (Matt. 6:16-18; Acts 13:2-3).', 'When you fast, anoint your head.'],
  ['Forgiveness', 'noun', 'for-giv\'nes', 'The gracious pardon and cancellation of debt of sin granted by God through Christ, and to be extended by believers to one another (Matt. 6:14-15; Eph. 4:32).', 'Forgiving one another, even as God for Christ\'s sake forgave you.'],
  ['Grace', 'noun', "grays", 'God\'s unmerited favor, power, and mercy that pardons sin and supplies supernatural divine strength to live a holy, victorious life (Titus 2:11-12; 2 Cor. 12:9).', 'My grace is sufficient for you, for my power is made perfect in weakness.'],
  ['Holiness', 'noun', "hoh'lee-nes", 'Separation from sin and dedication unto God; conformity to the divine nature in character and walk (1 Pet. 1:15-16; Heb. 12:14).', 'Without holiness no man shall see the Lord.'],
  ['Holy Spirit', 'noun', "hoh'lee spir'it", 'The third Person of the Godhead; the Comforter, Teacher, and Power sent by Christ to dwell in and empower believers (John 14:26; Acts 1:8).', 'You shall receive power when the Holy Spirit has come upon you.'],
  ['Humility', 'noun', 'hew-mil\'i-tee', 'Freedom from pride and self-exaltation; taking the low place in reverence before God and serving others (Phil. 2:3-8; 1 Pet. 5:5).', 'God opposes the proud but gives grace to the humble.'],
  ['Justification', 'noun', 'jus-ti-fi-kay\'shun', 'The legal declaration of God counting a believing sinner as righteous on the basis of Christ\'s atoning blood (Rom. 3:24-26; 5:1).', 'Being justified by faith, we have peace with God.'],
  ['Kingdom of God', 'noun', "king'dum", 'The sovereign rule and reign of God in human hearts and in all creation, characterized by righteousness, peace, and joy in the Holy Spirit (Rom. 14:17).', 'Seek first the kingdom of God.'],
  ['New Covenant', 'noun', "noo kuv'e-nant", 'The covenant prophesied in Jeremiah 31:31-34 and established by Christ\'s blood, wherein God writes His laws directly upon the mind and heart (Heb. 8:10).', 'I will put my laws into their mind, and write them in their hearts.'],
  ['Overcomer', 'noun', 'oh-ver-kum\'er', 'A believer who, through faith in Christ and the power of the Spirit, triumphs over the world, the flesh, and the devil (1 John 5:4; Rev. 2:7).', 'To him that overcometh will I give to eat of the tree of life.'],
  ['Pharisee', 'noun', "far'i-see", 'A religious sect in first-century Judaism known for external legalism, hypocrisy, love of praise, and neglect of the heart (Matt. 23:1-33).', 'Beware of the leaven of the Pharisees, which is hypocrisy.'],
  ['Prayer', 'noun', "prair", 'Personal communion, petition, worship, and alignment of the human will with the Father\'s heart in the name of Jesus (Matt. 6:6-13; John 16:24).', 'Pray without ceasing.'],
  ['Propitiation', 'noun', 'pro-pish-ee-ay\'shun', 'The appeasing and satisfying of God\'s holy justice against sin through the sacrificial blood of Christ (Rom. 3:25; 1 John 2:2).', 'He is the propitiation for our sins.'],
  ['Repentance', 'noun', 'ri-pen\'tance', 'A radical change of mind and heart leading to turning away from sin and yielding unreservedly unto God (Acts 20:21; 2 Cor. 7:10).', 'Repent, for the kingdom of heaven is at hand.'],
  ['Resurrection', 'noun', 'rez-uh-rek\'shun', 'The bodily rising from the dead, initiated in Christ\'s triumph over the grave and promised to all believers at His return (1 Cor. 15:12-23).', 'I am the resurrection and the life.'],
  ['Righteousness', 'noun', "ry'chus-nes", 'Conformity of heart, thought, and deed to God\'s moral perfection and truth (Matt. 5:6; Rom. 6:18).', 'Blessed are those who hunger and thirst after righteousness.'],
  ['Sanctification', 'noun', 'sank-ti-fi-kay\'shun', 'The progressive work of the Holy Spirit transforming the believer into the likeness of Jesus Christ (1 Thess. 4:3; 5:23; 2 Cor. 3:18).', 'This is the will of God, even your sanctification.'],
  ['Self-life', 'noun', "self-lyf", 'The fallen, independent, self-centered principle of Adam that seeks its own honor, comfort, and will rather than God (Gal. 2:20; Luke 9:23).', 'I have been crucified with Christ.'],
  ['Victory', 'noun', "vik'ter-ee", 'Triumph over sin, temptation, discouragement, and Satan through faith in Jesus Christ (1 Cor. 15:57; 1 John 5:4).', 'Thanks be to God who gives us the victory through our Lord Jesus Christ.']
];

// 2. Strong's Greek & Hebrew Lexicon Highlights
const STRONGS_ENTRIES = [
  ['H1254 (Bara)', 'verb', 'baw-raw\'', 'To create, form, shape out of nothing. Used exclusively of divine activity (Gen. 1:1).', 'In the beginning God created the heaven and the earth.'],
  ['H2617 (Hesed)', 'noun', 'kheh\'-sed', 'Steadfast covenant love, unfailing kindness, mercy, fidelity (Ex. 34:6; Ps. 136).', 'His steadfast love endures forever.'],
  ['H7965 (Shalom)', 'noun', 'shaw-lome\'', 'Completeness, soundness, wholeness, peace, welfare, health, tranquility (Num. 6:26; Isa. 9:6).', 'The Lord lift up His countenance upon you and give you peace.'],
  ['H6944 (Qodesh)', 'noun', 'ko\'-desh', 'Apartness, holiness, sacredness; that which is separated unto God from common use (Lev. 19:2).', 'You shall be holy, for I the Lord your God am holy.'],
  ['H3068 (YHWH / Yahweh)', 'proper noun', 'yeh-ho-vaw\'', 'The self-existent and covenant-keeping God; "I AM WHO I AM" (Ex. 3:14-15; 6:3).', 'The Lord is my shepherd, I shall not want.'],
  ['G26 (Agape)', 'noun', 'ag-ah\'-pay', 'Self-giving, unconditional divine love that seeks the highest good of another regardless of merit (John 3:16; 1 Cor. 13:4-8).', 'God is love.'],
  ['G5485 (Charis)', 'noun', 'khar\'-ece', 'Grace, unmerited divine favor and operational spiritual power working in the heart (Eph. 2:8; 2 Cor. 12:9).', 'For by grace you have been saved through faith.'],
  ['G4102 (Pistis)', 'noun', 'pis\'-tis', 'Faith, firm persuasion, moral conviction of truth, active reliance upon God (Heb. 11:1).', 'The just shall live by faith.'],
  ['G3341 (Metanoia)', 'noun', 'met-an\'-oy-ah', 'Repentance, a complete transformation and reversal of mind, purpose, and direction toward God (Mark 1:15; Acts 26:20).', 'Bear fruits worthy of repentance.'],
  ['G4151 (Pneuma)', 'noun', 'pnyoo\'-mah', 'Spirit, wind, breath; the Holy Spirit, the divine vitality and essence of God (John 3:8; 4:24).', 'God is spirit, and those who worship Him must worship in spirit and truth.'],
  ['G3101 (Mathetes)', 'noun', 'math-ay-tes\'', 'A disciple, follower, pupil who learns by following and obeying a master (Matt. 28:19).', 'Make disciples of all nations.'],
  ['G4716 (Stauros)', 'noun', 'stow-ros\'', 'A stake or cross; instrument of crucifixion; emblem of death to the self-life and the world (Gal. 6:14; Phil. 2:8).', 'God forbid that I should boast except in the cross of our Lord Jesus Christ.'],
  ['G2222 (Zoe)', 'noun', 'dzo-ay\'', 'Divine, uncreated eternal life; the very life of God imparted to the believer in Christ (John 1:4; 10:10; 1 John 5:12).', 'He who has the Son has life.'],
  ['G1343 (Dikaiosyne)', 'noun', 'dik-ah-yos-oo\'-nay', 'Righteousness, equity of character, justice, uprightness of thought and conduct before God (Matt. 5:6; Rom. 1:17).', 'In it the righteousness of God is revealed from faith to faith.']
];

// Helper to write a dictionary SQLite file and compress to .gz
function buildDict(dictId, entries) {
  const sqliteFile = path.join(OUT_DIR, `dict_${dictId}.sqlite`);
  const gzFile = path.join(OUT_DIR, `dict_${dictId}.sqlite.gz`);

  if (fs.existsSync(sqliteFile)) fs.unlinkSync(sqliteFile);
  if (fs.existsSync(gzFile)) fs.unlinkSync(gzFile);

  const db = new DatabaseSync(sqliteFile);
  db.exec(`
    CREATE TABLE dictionary_entries (
      headword TEXT NOT NULL COLLATE NOCASE,
      part_of_speech TEXT,
      phonetic TEXT,
      definition TEXT NOT NULL,
      examples TEXT,
      PRIMARY KEY (headword, part_of_speech)
    );
    CREATE INDEX idx_dict_headword ON dictionary_entries (headword);
  `);

  const insert = db.prepare(`
    INSERT OR REPLACE INTO dictionary_entries (headword, part_of_speech, phonetic, definition, examples)
    VALUES (?, ?, ?, ?, ?)
  `);

  db.exec('BEGIN TRANSACTION;');
  for (const [w, pos, pho, def, ex] of entries) {
    insert.run(w, pos, pho, def, ex || '');
  }
  db.exec('COMMIT;');
  db.close();

  // Compress
  const buffer = fs.readFileSync(sqliteFile);
  const gz = zlib.gzipSync(buffer, { level: 9 });
  fs.writeFileSync(gzFile, gz);

  const kb = (gz.length / 1024).toFixed(1);
  console.log(`✓ Built dict_${dictId}.sqlite.gz (${entries.length} entries, ${kb} KB)`);
  return gzFile;
}

// 3. Global Languages (Spanish, French, German, Portuguese, Russian, Hindi, Tamil)
const SPANISH_ENTRIES = [
  ['gracia', 'sustantivo', '/ˈɡɾa.sja/', 'Favor inmerecido y poder divino de Dios dado por medio de Jesucristo para vivir en santidad.', 'Por gracia sois salvos por medio de la fe.'],
  ['fe', 'sustantivo', '/fe/', 'Certeza de lo que se espera, la convicción de lo que no se ve; confianza total en Dios.', 'El justo por la fe vivirá.'],
  ['discipulo', 'sustantivo', '/diˈsi.pu.lo/', 'Seguidor y aprendiz consagrado que camina como Jesús caminó.', 'Haced discípulos a todas las naciones.'],
  ['santidad', 'sustantivo', '/san.tiˈdad/', 'Separación del pecado y consagración total a Dios.', 'Sed santos, porque yo soy santo.'],
  ['oracion', 'sustantivo', '/o.ɾaˈsjon/', 'Comunión íntima, adoración y diálogo con Dios el Padre.', 'Orad sin cesar.'],
  ['cruz', 'sustantivo', '/kɾus/', 'Instrumento de redención y principio de negación del yo para seguir a Cristo.', 'Tome su cruz cada día y sígame.'],
  ['arrepentimiento', 'sustantivo', '/a.re.pen.tiˈmjen.to/', 'Cambio radical de mente y de corazón, volviéndose del pecado a Dios.', 'Arrepentíos y creed en el evangelio.']
];

const FRENCH_ENTRIES = [
  ['grace', 'nom', '/ɡʁas/', 'Faveur imméritée et puissance divine accordées par Dieu en Jésus-Christ.', 'C\'est par la grâce que vous êtes sauvés.'],
  ['foi', 'nom', '/fwa/', 'Ferme assurance des choses qu\'on espère, démonstration de celles qu\'on ne voit pas.', 'Sans la foi, il est impossible de lui être agréable.'],
  ['disciple', 'nom', '/di.sipl/', 'Personne qui suit fidèlement Jésus-Christ et met en pratique Sa Parole.', 'Faites de toutes les nations des disciples.'],
  ['saintete', 'nom', '/sɛ̃t.te/', 'Pureté morale et consécration absolue à Dieu.', 'Soyez saints, car je suis saint.'],
  ['priere', 'nom', '/pʁi.jɛʁ/', 'Dialogue et communion du cœur avec le Père céleste au nom de Jésus.', 'Priez sans cesse.']
];

const GERMAN_ENTRIES = [
  ['gnade', 'substantiv', '/ˈɡnaːdə/', 'Die unverdiente Gunst, Vergebung und göttliche Kraft Gottes in Christus.', 'Aus Gnade seid ihr selig geworden durch den Glauben.'],
  ['glaube', 'substantiv', '/ˈɡlaʊ̯bə/', 'Feste Zuversicht auf das, was man hofft, und Nichtzweifeln an dem, was man nicht sieht.', 'Der Gerechte wird seines Glaubens leben.'],
  ['junger', 'substantiv', '/ˈjʏŋɐ/', 'Ein Nachfolger Jesu Christi, der Sein Wort lernt und befolgt.', 'Gehet hin und machet zu Jüngern alle Völker.'],
  ['heiligkeit', 'substantiv', '/ˈhaɪ̯lɪçkaɪ̯t/', 'Absonderung von der Sünde und Hingabe an Gott.', 'Seid heilig, denn ich bin heilig.']
];

const PORTUGUESE_ENTRIES = [
  ['graca', 'substantivo', '/ˈɡɾa.sɐ/', 'O favor imerecido e o poder divino de Deus operando no crente em Cristo.', 'Pela graça sois salvos, por meio da fé.'],
  ['fe', 'substantivo', '/fɛ/', 'A certeza das coisas que se esperam e a prova das coisas que não se veem.', 'O justo viverá da fé.'],
  ['discipulo', 'substantivo', '/diˈsi.pu.lu/', 'Aquele que segue os passos de Cristo e vive como Ele viveu.', 'Fazei discípulos de todas as nações.'],
  ['santidade', 'substantivo', '/sɐ̃.tiˈda.dʒi/', 'Pureza de coração e dedicação integral a Deus.', 'Sede santos, porque eu sou santo.']
];

const RUSSIAN_ENTRIES = [
  ['благодать', 'существительное', '[bləɡɐˈdatʲ]', 'Незаслуженная милость и божественная сила Божья для святой жизни во Христе.', 'Ибо благодатью вы спасены через веру.'],
  ['вера', 'существительное', '[ˈvʲerə]', 'Осуществление ожидаемого и уверенность в невидимом; полное доверие Богу.', 'Праведный верою жив будет.'],
  ['ученик', 'существительное', '[ʊtɕɪˈnʲik]', 'Последователь Иисуса Христа, отрекающийся от себя ради Господа.', 'Идите и научите все народы.']
];

const HINDI_ENTRIES = [
  ['अनुग्रह', 'संज्ञा', '/anugraha/', 'परमेश्वर की असीम दया, अमोघ कृपा एवं सामर्थ्य जो यीशु मसीह के द्वारा विश्वासियों को मिलती है।', 'विश्वास के द्वारा अनुग्रह ही से तुम्हारा उद्धार हुआ है।'],
  ['विश्वास', 'संज्ञा', '/vishvaas/', 'आशा की हुई वस्तुओं का निश्चय, और अनदेखी वस्तुओं का प्रमाण।', 'धर्मी जन विश्वास से जीवित रहेगा।'],
  ['चेला', 'संज्ञा', '/chela/', 'प्रभु यीशु मसीह का समर्पित अनुयायी जो प्रतिदिन अपना क्रूस उठाकर उनके पीछे चलता है।', 'जाकर सब जातियों के लोगों को चेला बनाओ।']
];

const TAMIL_ENTRIES = [
  ['கிருபை', 'பெயர்ச்சொல்', '/kirubai/', 'இயேசு கிறிஸ்துவின் மூலமாக தேவனால் அருளப்படும் அளவற்ற தகுதிக்கு அப்பாற்பட்ட தயவு மற்றும் தெய்வீக வல்லமை.', 'கிருபையினாலே விசுவாசத்தைக்கொண்டு இரட்சிக்கப்பட்டீர்கள்.'],
  ['விசுவாசம்', 'பெயர்ச்சொல்', '/visuvaasam/', 'நம்பப்படுகிறவைகளின் உறுதியும், காணப்படாதவைகளின் நிச்சயமுமாய் இருக்கிறது.', 'விசுவாசத்தினாலே நீதிமான் பிழைப்பான்.'],
  ['சீஷன்', 'பெயர்ச்சொல்', '/seesan/', 'தன் சிலுவையைச் சுமந்து, தன்னைத் தான் வெறுத்து, இயேசு கிறிஸ்துவைப் பின்பற்றும் உண்மையான சீஷன்.', 'நீங்கள் போய், சகல ஜாதிகளையும் சீஷராக்குங்கள்.']
];

async function main() {
  console.log('\n--- Building Dictionaries ---');
  buildDict('en', EASTONS_ENTRIES);
  buildDict('eastons', EASTONS_ENTRIES);
  buildDict('strongs', STRONGS_ENTRIES);
  buildDict('es', SPANISH_ENTRIES);
  buildDict('fr', FRENCH_ENTRIES);
  buildDict('de', GERMAN_ENTRIES);
  buildDict('pt', PORTUGUESE_ENTRIES);
  buildDict('ru', RUSSIAN_ENTRIES);
  buildDict('hi', HINDI_ENTRIES);
  buildDict('ta', TAMIL_ENTRIES);
  console.log('\nAll 10 dictionary packages built successfully!\n');
}

main();
