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
  ['अनुग्रह', 'संज्ञा', '/anugraha/', 'परमेश्वर की असीम दया, अमोघ कृपा एवं सामर्थ्य जो यीशु मसीह के द्वारा विश्वासियों को मिलती है।', 'विश्वास के द्वारा अनुग्रह ही से तुम्हारा उद्धार हुआ है। (इफिसियों 2:8)'],
  ['विश्वास', 'संज्ञा', '/vishvaas/', 'आशा की हुई वस्तुओं का निश्चय, और अनदेखी वस्तुओं का प्रमाण; परमेश्वर के वचनों पर पूर्ण भरोसा।', 'धर्मी जन विश्वास से जीवित रहेगा। (रोमियों 1:17)'],
  ['चेला', 'संज्ञा', '/chela/', 'प्रभु यीशु मसीह का समर्पित अनुयायी जो प्रतिदिन अपना क्रूस उठाकर उनके पीछे चलता है।', 'जाकर सब जातियों के लोगों को चेला बनाओ। (मत्ती 28:19)'],
  ['पवित्रता', 'संज्ञा', '/pavitrata/', 'पाप से अलगाव एवं परमेश्वर के स्वभाव के सदृश जीवन बिताना।', 'पवित्र बनो, क्योंकि मैं पवित्र हूँ। (1 पतरस 1:16)'],
  ['धार्मिकता', 'संज्ञा', '/dhaarmikta/', 'परमेश्वर के नैतिक स्तर के अनुसार सत्य और न्यायपूर्ण चाल-चलन।', 'धन्य हैं वे जो धार्मिकता के भूखे और प्यासे हैं। (मत्ती 5:6)'],
  ['पश्चाताप', 'संज्ञा', '/pashchaataap/', 'मन और हृदय का सम्पूर्ण परिवर्तन, पाप को छोड़कर परमेश्वर की ओर मुड़ना।', 'मन फिराओ, क्योंकि स्वर्ग का राज्य निकट आया है। (मत्ती 4:17)'],
  ['उद्धार', 'संज्ञा', '/uddhaar/', 'पाप और मृत्यु के दंड से यीशु मसीह के लहू के द्वारा छुटकारा पाना।', 'प्रभु यीशु मसीह पर विश्वास कर, तो तू उद्धार पाएगा। (प्रेरितों 16:31)'],
  ['वाचा', 'संज्ञा', '/vaacha/', 'परमेश्वर और मनुष्य के बीच स्थापित एक पवित्र एवं अटल प्रतिज्ञा।', 'यह मेरे लहू की नई वाचा है। (लूका 22:20)'],
  ['क्रूस', 'संज्ञा', '/kroos/', 'मसीह के प्रायश्चित का साधन और अपने स्व-जीवन को समाप्त करने का प्रतीक।', 'जो कोई मेरे पीछे आना चाहे, वह अपने आप का इन्कार करे और अपना क्रूस उठाए। (मरकुस 8:34)'],
  ['पुनरुत्थान', 'संज्ञा', '/punarutthaan/', 'यीशु मसीह का मृतकों में से जी उठना और विश्वासियों के लिए अनंत जीवन की आशा।', 'पुनरुत्थान और जीवन मैं ही हूँ। (यूहन्ना 11:25)'],
  ['प्रार्थना', 'संज्ञा', '/praarthana/', 'परमेश्वर पिता के साथ आत्मिक सम्भाषण, स्तुति और याचना।', 'निरन्तर प्रार्थना में लगे रहो। (1 थिस्सलुनीकियों 5:17)'],
  ['शान्ति', 'संज्ञा', '/shaanti/', 'परमेश्वर के साथ मेल-मिलाप तथा हृदय का सम्पूर्ण विश्राम (शालोम)।', 'मैं तुम्हें अपनी शान्ति दिए जाता हूँ। (यूहन्ना 14:27)'],
  ['सत्य', 'संज्ञा', '/satya/', 'परमेश्वर का अपरिवर्तनीय वचन और वास्तविकता जो मनुष्य को स्वतंत्र करती है।', 'तुम सत्य को जानोगे, और सत्य तुम्हें स्वतंत्र करेगा। (यूहन्ना 8:32)'],
  ['क्षमा', 'संज्ञा', '/kshama/', 'पापों की माफी और दूसरों के प्रति द्वेष व कटुता का त्याग।', 'जैसे प्रभु ने तुम्हारे अपराध क्षमा किए, वैसे ही तुम भी करो। (कुलुस्सियों 3:13)'],
  ['सुसमाचार', 'संज्ञा', '/susamaachaar/', 'यीशु मसीह के द्वारा मनुष्य जाति के उद्धार का आनंददायक मंगल समाचार।', 'सारे जगत में जाकर सारी सृष्टि को सुसमाचार प्रचार करो। (मरकुस 16:15)'],
  ['प्रेम', 'संज्ञा', '/prem/', 'निःस्वार्थ, ईश्वरीय बलिदानमय प्रीति (अगापे प्रेम)।', 'परमेश्वर ने जगत से ऐसा प्रेम रखा कि उसने अपना एकलौता पुत्र दे दिया। (यूहन्ना 3:16)'],
  ['पवित्र आत्मा', 'संज्ञा', '/pavitra aatma/', 'त्रिएक परमेश्वर का तीसरा व्यक्तित्व; सहायक, शिक्षक और मार्गदर्शक।', 'जब पवित्र आत्मा तुम पर आएगा तब तुम सामर्थ्य पाओगे। (प्रेरितों 1:8)'],
  ['कलीसिया', 'संज्ञा', '/kaleesiya/', 'मसीह की देह; उद्धार पाए हुए विश्वासियों की संगति।', 'मैं अपनी कलीसिया बनाऊँगा, और अधोलोक के फाटक उस पर प्रबल न होंगे। (मत्ती 16:18)'],
  ['जय पाने वाला', 'संज्ञा', '/jay paane waala/', 'संसार, अभिलाषा और शैतान पर मसीह के द्वारा विजय प्राप्त करने वाला विश्वासी।', 'जो जय पाए, मैं उसे अपने साथ अपने सिंहासन पर बैठने दूँगा। (प्रकाशितवाक्य 3:21)'],
  ['नम्रता', 'संज्ञा', '/namrata/', 'अहंकार रहित हृदय, दूसरों को अपने से श्रेष्ठ समझना और परमेश्वर के अधीन रहना।', 'परमेश्वर अभिमानियों का विरोध करता है, परन्तु दीनों पर अनुग्रह करता है। (याकूब 4:6)']
];

const TAMIL_ENTRIES = [
  ['கிருபை', 'பெயர்ச்சொல்', '/kirubai/', 'இயேசு கிறிஸ்துவின் மூலமாக தேவனால் அருளப்படும் அளவற்ற தகுதிக்கு அப்பாற்பட்ட தயவு மற்றும் ஜீவிக்க உதவும் தெய்வீக வல்லமை.', 'கிருபையினாலே விசுவாசத்தைக்கொண்டு இரட்சிக்கப்பட்டீர்கள். (எபேசியர் 2:8)'],
  ['விசுவாசம்', 'பெயர்ச்சொல்', '/visuvaasam/', 'நம்பப்படுகிறவைகளின் உறுதியும், காணப்படாதவைகளின் நிச்சயமுமாய் இருக்கும் தேவபக்தி.', 'விசுவாசத்தினாலே நீதிமான் பிழைப்பான். (ரோமர் 1:17)'],
  ['சீஷன்', 'பெயர்ச்சொல்', '/seesan/', 'தன் சுயத்தை வெறுத்து, நாள்தோறும் தன் சிலுவையைச் சுமந்து இயேசுவைப் பின்பற்றும் அர்ப்பணிக்கப்பட்ட உண்மை விசுவாசி.', 'நீங்கள் என் உபதேசத்தில் நிலைத்திருந்தால் மெய்யாகவே என் சீஷராயிருப்பீர்கள். (யோவான் 8:31)'],
  ['பரிசுத்தம்', 'பெயர்ச்சொல்', '/parisuttham/', 'பாவத்திலிருந்தும் உலகத்திலிருந்தும் பிரித்தெடுக்கப்பட்டு, தேவ சாயலில் வாழும் தூய ஜீவியம்.', 'நான் பரிசுத்தர், ஆகையால் நீங்களும் பரிசுத்தராயிருங்கள். (1 பேதுரு 1:16)'],
  ['நீதி', 'பெயர்ச்சொல்', '/neethi/', 'தேவனுடைய நியாயப்பிரமாணத்திற்கும் பரிசுத்த சுபாவத்திற்கும் ஒப்பான நல்நடத்தை மற்றும் தேவநீதி.', 'நீதியைத் தேடுங்கள், சாந்தத்தைத் தேடுங்கள். (செப்பனியா 2:3)'],
  ['மனந்திரும்புதல்', 'பெயர்ச்சொல்', '/mananthirumbuthal/', 'பாவத்தை உணர்ந்து, மனதும் சிந்தையும் முற்றிலும் மாறி தேவனிடம் திரும்புதல்.', 'மனந்திரும்புங்கள், பரலோகராஜ்யம் சமீபித்திருக்கிறது. (மத்தேயு 4:17)'],
  ['இரட்சிப்பு', 'பெயர்ச்சொல்', '/iratchippu/', 'இயேசு கிறிஸ்துவின் இரத்தத்தினால் பாவத்தின் ஆக்கினையிலிருந்தும் வல்லமையிலிருந்தும் கிடைக்கும் விடுதலை.', 'கர்த்தராகிய இயேசுகிறிஸ்துவை விசுவாசி, அப்பொழுது நீயும் உன் வீட்டாரும் இரட்சிக்கப்படுவீர்கள். (அப். 16:31)'],
  ['உடன்படிக்கை', 'பெயர்ச்சொல்', '/udanpadikkai/', 'தேவனுக்கும் மனிதனுக்கும் இடையே இயேசுவின் இரத்தத்தினால் முத்திரையிடப்பட்ட நித்திய உடன்படிக்கை.', 'இந்த பாத்திரம் என் இரத்தத்தினாலாகிய புதிய உடன்படிக்கையாயிருக்கிறது. (லூக்கா 22:20)'],
  ['சிலுவை', 'பெயர்ச்சொல்', '/siluvai/', 'பாவப்பரிகார பலியின் சின்னம் மற்றும் சுயஜீவனைச் சிலுவையில் அறைந்து கிறிஸ்துவுக்காக வாழும் கொள்கை.', 'ஒருவன் என் பின்னே வர விரும்பினால், அவன் தன்னைத்தான் வெறுத்து, தன் சிலுவையை எடுத்துக்கொண்டு என்னைப் பின்பற்றக்கடவன். (மத்தேயு 16:24)'],
  ['உயிர்த்தெழுதல்', 'பெயர்ச்சொல்', '/uyirtthezhuthal/', 'இயேசு கிறிஸ்து மரணத்தை ஜெயித்து மூன்றாம் நாளில் உயிரோடு எழுந்த வெற்றியின் பிரகடனம்.', 'நானே உயிர்த்தெழுதலும் ஜீவனுமாயிருக்கிறேன். (யோவான் 11:25)'],
  ['ஜெபம்', 'பெயர்ச்சொல்', '/jebam/', 'பரலோக பிதாவோடு உள்ள இருதயப்பூர்வமான ஐக்கியம், விண்ணப்பம் மற்றும் ஆராதனை.', 'இடைவிடாமல் ஜெபம்பண்ணுங்கள். (1 தெசலோனிக்கேயர் 5:17)'],
  ['சமாதானம்', 'பெயர்ச்சொல்', '/samaadhaanam/', 'தேவனோடுள்ள சமாதானம் மற்றும் உலகத்தால் அறியப்படாத இருதயத்தின் தெய்வீக அமைதி (ஷாலோம்).', 'என்னுடைய சமாதானத்தையே உங்களுக்குக் கொடுக்கிறேன். (யோவான் 14:27)'],
  ['சத்தியம்', 'பெயர்ச்சொல்', '/sathiyam/', 'தேவனுடைய மாறாத மெய்வார்த்தை மற்றும் உண்மைத்தன்மை.', 'சத்தியத்தையும் அறிவீர்கள், சத்தியம் உங்களை விடுதலையாக்கும். (யோவான் 8:32)'],
  ['மன்னிப்பு', 'பெயர்ச்சொல்', '/mannippu/', 'தேவன் நம் பாவங்களை மன்னிப்பது போல, பிறர் செய்த குற்றங்களை மனப்பூர்வமாக மன்னிப்பது.', 'ஒருவருக்கொருவர் தயவாயும் மனஉருக்கமாயும் இருந்து, கிறிஸ்துவுக்குள் தேவன் உங்களுக்கு மன்னித்ததுபோல, நீங்களும் ஒருவருக்கொருவர் மன்னியுங்கள். (எபேசியர் 4:32)'],
  ['சுவிசேஷம்', 'பெயர்ச்சொல்', '/suvisesham/', 'இயேசு கிறிஸ்துவின் மூலமாக மனுக்குலத்திற்கு அருளப்படும் நற்செய்தி.', 'சுவிசேஷத்தைக்குறித்து நான் வெட்கப்படேன்; ஏனென்றால் இரட்சிப்புக்கு ஏதுவான தேவபெலனாயிருக்கிறது. (ரோமர் 1:16)'],
  ['அன்பு', 'பெயர்ச்சொல்', '/anbu/', 'சுயநலமற்ற, தியாகம் நிறைந்த தெய்வீக அன்பு (அகாபே).', 'தேவன், தம்முடைய ஒரேபேறான குமாரனை விசுவாசிக்கிறவன் எவனோ அவன் கெட்டுப்போகாமல் நித்தியஜீவனை அடையும்படிக்கு, அவரைத் தந்தருளி, இவ்வளவாய் உலகத்தில் அன்புகூர்ந்தார். (யோவான் 3:16)'],
  ['பரிசுத்த ஆவியானவர்', 'பெயர்ச்சொல்', '/parisuttha aaviyaanavar/', 'திரியேக தேவனுடைய மூன்றாம் ஆள்; தேற்றரவாளன், போதகர், வழிநடத்துபவர்.', 'பரிசுத்த ஆவி உங்களிடத்தில் வரும்போது நீங்கள் பெலனடைந்து... எனக்குச் சாட்சிகளாயிருப்பீர்கள். (அப். 1:8)'],
  ['சபை', 'பெயர்ச்சொல்', '/sabai/', 'கிறிஸ்துவை தலையாகக் கொண்ட விசுவாசிகளின் ஆவிக்குரிய சரீரம் (எக்லேசியா).', 'என் சபையைக் கட்டுவேன், பாதாளத்தின் வாசல்கள் அதை மேற்கொள்வதில்லை. (மத்தேயு 16:18)'],
  ['ஜெயங்கொள்ளுகிறவன்', 'பெயர்ச்சொல்', '/jeyangollugiravan/', 'கிறிஸ்துவுக்குள் விசுவாசத்தினால் உலகத்தையும் மாம்சத்தையும் சாத்தானையும் மேற்கொள்ளும் விசுவாசி.', 'ஜெயங்கொள்ளுகிறவனெவனோ அவனுக்கு நான் என்னோடேகூட என் சிங்காசனத்தில் உட்காரும்படி அருள்செய்வேன். (வெளி. 3:21)'],
  ['சுயஜீவன்', 'பெயர்ச்சொல்', '/suyajeevan/', 'சுயபெருமை, சுயநலம், மனித புகழ்ச்சியை நாடும் ஆதாமுக்குரிய பழைய சுபாவம்.', 'கிறிஸ்துவுடனேகூடச் சிலுவையிலறையப்பட்டேன்; ஆயினும் பிழைத்திருக்கிறேன்; இனி நான் அல்ல, கிறிஸ்துவே எனக்குள் பிழைத்திருக்கிறார். (கலாத்தியர் 2:20)'],
  ['தாழ்மை', 'பெயர்ச்சொல்', '/thaazhmai/', 'தன்னைத்தான் தாழ்த்தி, தேவனுக்கும் சகோதரர்களுக்கும் பணிவிடை செய்யும் உன்னத குணம்.', 'தேவன் பெருமையுள்ளவர்களுக்கு எதிர்த்து நிற்கிறார், தாழ்மையுள்ளவர்களுக்கோ கிருபை அளிக்கிறார். (1 பேதுரு 5:5)']
];

const MALAYALAM_ENTRIES = [
  ['കൃപ', 'നാമം', '/kripa/', 'യേശുക്രിസ്തുവിലൂടെ ദൈവത്തിൽ നിന്ന് ലഭിക്കുന്ന അർഹതയില്ലാത്ത കൃപയും വിശുദ്ധ ജീവിതം നയിക്കാനുള്ള ദൈവിക ശക്തിയും.', 'കൃപയാലല്ലോ നിങ്ങൾ വിശ്വാസംമൂലം രക്ഷിക്കപ്പെട്ടിരിക്കുന്നതു. (എഫെസ്യർ 2:8)'],
  ['വിശ്വാസം', 'നാമം', '/visvaasam/', 'പ്രത്യാശിക്കുന്നതിന്റെ ഉറപ്പും കാണാത്ത കാര്യങ്ങളുടെ നിശ്ചയവുമായ അചഞ്ചലമായ ദൈവഭക്തി.', 'നീതിമാൻ വിശ്വാസത്താൽ ജീവിക്കും. (റോമർ 1:17)'],
  ['ശിഷ്യൻ', 'നാമം', '/sishyan/', 'സ്വയത്തെ ത്യജിച്ചു പ്രതിദിനം ക്രൂശെടുത്തു യേശുവിനെ അനുഗമിക്കുന്ന യഥാർത്ഥ അനുയായി.', 'നിങ്ങൾ എന്റെ വചനത്തിൽ വസിക്കുന്നു എങ്കിൽ നിങ്ങൾ സാക്ഷാൽ എന്റെ ശിഷ്യന്മാരായി. (യോഹന്നാൻ 8:31)'],
  ['വിശുദ്ധി', 'നാമം', '/visuddhi/', 'പാപത്തിൽ നിന്നുള്ള വേർപാടും ദൈവസ്വഭാവത്തിലുള്ള പരിപൂർണ്ണ പങ്കാളിത്തവും.', 'ഞാൻ വിശുദ്ധനാകയാൽ നിങ്ങളും വിശുദ്ധരായിരിപ്പിൻ. (1 പത്രൊസ് 1:16)'],
  ['നീതി', 'നാമം', '/neethi/', 'ദൈവത്തിന്റെ വിശുദ്ധ സ്വഭാവത്തിനും ന്യായപ്രമാണത്തിനും അനുയോജ്യമായ ആത്മീയ ജീവിതം.', 'നീതിക്കായി വിശന്നു ദാഹിക്കുന്നവർ ഭാഗ്യവാന്മാർ. (മത്തായി 5:6)'],
  ['മാനസാന്തരം', 'നാമം', '/maanasaantharam/', 'പാപത്തെ വിട്ടു പൂർണ്ണഹൃദയത്തോടെ ദൈവത്തിലേക്ക് തിരിയുന്ന മനസ്സിന്റെ സമൂലമായ മാറ്റം.', 'മാനസാന്തരപ്പെടുവിൻ, സ്വർഗ്ഗരാജ്യം സമീപിച്ചിരിക്കുന്നു. (മത്തായി 4:17)'],
  ['രക്ഷ', 'നാമം', '/raksha/', 'യേശുവിന്റെ രക്തത്താൽ പാപത്തിൽ നിന്നും ന്യായവിധിയിൽ നിന്നുമുള്ള നിത്യമായ വിടുതൽ.', 'കർത്താവായ യേശുവിൽ വിശ്വസിക്ക; എന്നാൽ നീയും നിന്റെ കുടുംബവും രക്ഷപ്രാപിക്കും. (പ്രവൃത്തികൾ 16:31)'],
  ['നിയമം', 'നാമം', '/niyamam/', 'യേശുക്രിസ്തുവിന്റെ രക്തത്താൽ സ്ഥാപിതമായ പുതിയ നിയമം (ഉടമ്പടി).', 'ഈ പാനപാത്രം നിങ്ങൾക്കുവേണ്ടി ചൊരിയുന്ന എന്റെ രക്തത്തിലെ പുതിയ നിയമം ആകുന്നു. (ലൂക്കൊസ് 22:20)'],
  ['ക്രൂശ്', 'നാമം', '/kroos/', 'ക്രിസ്തുവിന്റെ പരമയാഗത്തിന്റെ അടയാളവും സ്വയജീവിതം അവസാനിപ്പിക്കാനുള്ള മാതൃകയും.', 'എന്നെ അനുഗമിപ്പാൻ ആരെങ്കിലും ഇച്ഛിച്ചാൽ അവൻ തന്നെത്താൻ ത്യജിച്ചു തന്റെ ക്രൂശു എടുത്തു എന്നെ അനുഗമിക്കട്ടെ. (മത്തായി 16:24)'],
  ['പുനരുത്ഥാനം', 'നാമം', '/punarutthaanam/', 'യേശുക്രിസ്തു മരണത്തെ തോൽപ്പിച്ചു ജീവനോടെ എഴുന്നേറ്റ ചരിത്രപരമായ വിജയം.', 'ഞാൻ തന്നേ പുനരുത്ഥാനവും ജീവനും ആകുന്നു. (യോഹന്നാൻ 11:25)'],
  ['പ്രാർത്ഥന', 'നാമം', '/praarthana/', 'സ്വർഗ്ഗസ്ഥനായ പിതാവിനോടുള്ള ഹൃദയംഗമമായ സംഭാഷണവും ആരാധനയും അപേക്ഷയും.', 'ഇടവിടാതെ പ്രാർത്ഥിപ്പിൻ. (1 തെസ്സലൊനീക്യർ 5:17)'],
  ['സമാധാനം', 'നാമം', '/samaadhaanam/', 'ദൈവത്തോടുള്ള അനുരഞ്ജനവും ലോകം നൽകാൻ കഴിയാത്ത ഹൃദയത്തിന്റെ ശാന്തിയും (ശാലോം).', 'സമാധാനം ഞാൻ നിങ്ങൾക്കു തന്നേച്ചുപോകുന്നു; എന്റെ സമാധാനം ഞാൻ നിങ്ങൾക്കു തരുന്നു. (യോഹന്നാൻ 14:27)'],
  ['സത്യം', 'നാമം', '/satyam/', 'മനുഷ്യനെ സകല ബന്ധനങ്ങളിൽ നിന്നും സ്വതന്ത്രനാക്കുന്ന ദൈവവചനം.', 'സത്യം അറിയുകയും സത്യം നിങ്ങളെ സ്വതന്ത്രന്മാരാക്കുകയും ചെയ്യും. (യോഹന്നാൻ 8:32)'],
  ['ക്ഷമ', 'നാമം', '/kshama/', 'ക്രിസ്തുവിലൂടെ നമുക്ക് ലഭിച്ച ദൈവകൃപ അനുസരിച്ച് മറ്റുള്ളവരോട് ക്ഷമിക്കുന്ന മനോഭാവം.', 'ക്രിസ്തു നിങ്ങളോടു ക്ഷമിച്ചതുപോലെ നിങ്ങളും ചെയ്‍വിൻ. (കൊലൊസ്സ്യർ 3:13)'],
  ['സുവിശേഷം', 'നാമം', '/suvisesham/', 'യേശുക്രിസ്തുവിലൂടെയുള്ള പാപമോചനത്തിന്റെയും നിത്യജീവന്റെയും സന്തോഷവാർത്ത.', 'സകല സൃഷ്ടിയോടും സുവിശേഷം പ്രസംഗിപ്പിൻ. (മർക്കൊസ് 16:15)'],
  ['സ്നേഹം', 'നാമം', '/sneham/', 'സ്വാർത്ഥതയില്ലാത്ത, ത്യാഗപൂർണ്ണമായ ദിവ്യസ്നേഹം (അഗാപെ).', 'തന്റെ ഏകജാതനായ പുത്രനിൽ വിശ്വസിക്കുന്ന ഏവനും നശിച്ചുപോകാതെ നിത്യജീവൻ പ്രാപിക്കേണ്ടതിന്നു ദൈവം അവനെ നല്കുവാൻ തക്കവണ്ണം ലോകത്തെ സ്നേഹിച്ചു. (യോഹന്നാൻ 3:16)'],
  ['പരിശുദ്ധാത്മാവ്', 'നാമം', '/parisuddhaathmaavu/', 'ത്രിത്വത്തിലെ മൂന്നാമത്തെ വ്യക്തി; ആശ്വാസപ്രദൻ, ഉപദേഷ്ടാവ്, ശക്തിപ്രദായകൻ.', 'പരിശുദ്ധാത്മാവു നിങ്ങളുടെ മേൽ വരുമ്പോൾ നിങ്ങൾ ശക്തി ലഭിച്ചിട്ടു എന്റെ സാക്ഷികൾ ആയിരിക്കും. (പ്രവൃത്തികൾ 1:8)'],
  ['സഭ', 'നാമം', '/sabha/', 'ക്രിസ്തു തലയായിരിക്കുന്ന വിശ്വാസികളുടെ ശരീരം (എക്ലേഷ്യ).', 'ഞാൻ എന്റെ സഭയെ പണിയും; പാതാളഗോപുരങ്ങൾ അതിനെ ജയിക്കയില്ല. (മത്തായി 16:18)'],
  ['ജയിക്കുന്നവൻ', 'നാമം', '/jayikkunnavan/', 'വിശ്വാസത്താൽ ലോകത്തെയും ജഡത്തെയും പിശാചിനെയും അതിജീവിക്കുന്ന ക്രിസ്തുശിഷ്യൻ.', 'ജയിക്കുന്നവന്നു ഞാൻ എന്റെ സിംഹാസനത്തിൽ എന്നോടുകൂടെ ഇരിപ്പാൻ വരം നല്കും. (വെളിപ്പാടു 3:21)'],
  ['താഴ്മ', 'നാമം', '/thaazhma/', 'അഹങ്കാരമില്ലായ്മയും ക്രിസ്തുവിന്റെ സൗമ്യതയും ഉൾക്കൊള്ളുന്ന ജീവിതം.', 'ദൈവം നിഗളികളോടു എതിർത്തുനിൽക്കയും താഴ്മയുള്ളവർക്കു കൃപ നല്കുകയും ചെയ്യുന്നു. (1 പത്രൊസ് 5:5)']
];

const TELUGU_ENTRIES = [
  ['కృప', 'నామవాచకం', '/krupa/', 'యేసుక్రీస్తు ద్వారా దేవుని ఉచిత దయ మరియు పవిత్ర జీవితం జీవించడానికి లభించే దైవిక శక్తి.', 'మీరు విశ్వాసముద్వారా కృపచేతనే రక్షింపబడియున్నారు. (ఎఫెసీయులకు 2:8)'],
  ['విశ్వాసము', 'నామవాచకం', '/visvaasamu/', 'నిరీక్షింపబడువాటి నిజస్వరూపమును, అదృశ్యమైనవి యున్నవనుటకు రుజువునైయున్న దైవభక్తి.', 'నీతిమంతుడు విశ్వాసమూలముగా జీవించును. (రోమీయులకు 1:17)'],
  ['శిష్యుడు', 'నామవాచకం', '/sishyudu/', 'తనను తాను ఉపేక్షించుకొని, ప్రతిదినము తన సిలువను ఎత్తికొని యేసును అనుసరించే భక్తుడు.', 'మీరు నా వాక్యమందు నిలిచినవారైతే నిజముగా నాకు శిష్యులై యుందురు. (యోహాను 8:31)'],
  ['పరిశుద్ధత', 'నామవాచకం', '/parisuddhata/', 'పాపము నుండి వేరుపరచబడి దేవుని కొరకు సమర్పించబడిన పవిత్ర జీవితం.', 'నేను పరిశుద్ధుడనై యున్నాను గనుక మీరును పరిశుద్ధులై యుండుడి. (1 పేతురు 1:16)'],
  ['నీతి', 'నామవాచకం', '/neethi/', 'దేవుని పరిశుద్ధ స్వభావానికి అనుగుణంగా జీవించే నిజాయితీ మరియు దైవనీతి.', 'నీతికొరకు ఆకలిదప్పులు గలవారు ధన్యులు. (మత్తయి 5:6)'],
  ['మారుమనస్సు', 'నామవాచకం', '/maarumansu/', 'పాపమును విడిచిపెట్టి, మనస్సును పూర్ణముగా మార్చుకొని దేవుని వైపు తిరుగుట.', 'పరలోకరాజ్యము సమీపించియున్నది, మారుమనస్సు పొందుడి. (మత్తయి 4:17)'],
  ['రక్షణ', 'నామవాచకం', '/rakshana/', 'యేసుక్రీస్తు రక్తము ద్వారా పాప శిక్ష నుండి మరియు పాప శక్తి నుండి పొందే విమోచన.', 'ప్రభువైన యేసునందు విశ్వాసముంచుము, అప్పుడు నీవును నీ యింటివారును రక్షణ పొందుదురు. (అపొ. కా. 16:31)'],
  ['నిబంధన', 'నామవాచకం', '/nibandhana/', 'యేసుక్రీస్తు రక్తముచేత స్థిరపరచబడిన నిత్య నూతన నిబంధన.', 'ఈ పాత్ర మీకొరకు చిందింపబడుచున్న నా రక్తమువలననైన క్రొత్త నిబంధన. (లూకా 22:20)'],
  ['సిలువ', 'నామవాచకం', '/siluva/', 'పాపపరిహార బలి చిహ్నం మరియు స్వార్థ జీవితమును చంపి క్రీస్తు కొరకు జీవించే విధానం.', 'ఎవడైనను నన్ను వెంబడింపగోరినయెడల, తన్నుతాను ఉపేక్షించుకొని, తన సిలువను ఎత్తికొని నన్ను వెంబడింపవలెను. (మత్తయి 16:24)'],
  ['పునరుత్థానము', 'నామవాచకం', '/punarutthaanamu/', 'యేసుక్రీస్తు మరణమును జయించి సజీవముగా లేచిన గొప్ప విజయం.', 'పునరుత్థానమును జీవమును నేనే. (యోహాను 11:25)'],
  ['ప్రార్థన', 'నామవాచకం', '/praarthana/', 'పరలోక తండ్రితో హృదయపూర్వక సహవాసము, విన్నపములు మరియు ఆరాధన.', 'ఎడతెగక ప్రార్థన చేయుడి. (1 థెస్సలొనీకయులకు 5:17)'],
  ['సమాధానము', 'నామవాచకం', '/samaadhaanamu/', 'దేవునితో సమాధానం మరియు లోకము ఇవ్వలేని అంతరంగ శాంతి (షాలోమ్).', 'శాంతి మీకొరకు విడిచి వెళ్లుచున్నాను, నా సమాధానమునే మీకనుగ్రహించుచున్నాను. (యోహాను 14:27)'],
  ['సత్యము', 'నామవాచకం', '/satyamu/', 'మనిషిని సమస్త బంధకాల నుండి విడిపించే దేవుని శాశ్వత వాక్యము.', 'మీరు సత్యమును గ్రహించెదరు, సత్యము మిమ్మును స్వతంత్రులనుగా చేయును. (యోహాను 8:32)'],
  ['క్షమాపణ', 'నామవాచకం', '/kshamaapana/', 'క్రీస్తు మనలను క్షమించినట్లుగా మనం కూడా ఇతరులను హృదయపూర్వకంగా క్షమించుట.', 'ప్రభువు మిమ్మును క్షమించినలాగున మీరును క్షమించుడి. (కొలొస్సయులకు 3:13)'],
  ['సువార్త', 'నామవాచకం', '/suvaarta/', 'యేసుక్రీస్తు ద్వారా మానవాళికి లభించే రక్షణ శుభవార్త.', 'సర్వలోకమునకు వెళ్లి సర్వసృష్టికి సువార్తను ప్రకటించుడి. (మార్కు 16:15)'],
  ['ప్రేమ', 'నామవాచకం', '/prema/', 'స్వార్థం లేని త్యాగపూరిత దైవిక ప్రేమ (అగాపే).', 'దేవుడు లోకమును ఎంతో ప్రేమించెను. కాగా ఆయన తన అద్వితీయకుమారునిగా పుట్టిన వానియందు విశ్వాసముంచు ప్రతివాడును నశింపక నిత్యజీవము పొందునట్లు ఆయనను అనుగ్రహించెను. (యోహాను 3:16)'],
  ['పరిశుద్ధాత్మ', 'నామవాచకం', '/parisuddhaatma/', 'త్రిత్వములోని మూడవ వ్యక్తి; ఆదరణకర్త, బోధకుడు, మార్గదర్శి.', 'పరిశుద్ధాత్మ మీమీదికి వచ్చునప్పుడు మీరు శక్తినొందెదరు. (అపొ. కా. 1:8)'],
  ['సంఘము', 'నామవాచకం', '/sanghamu/', 'క్రీస్తే శిరస్సైయున్న విశ్వాసుల ఆత్మీయ శరీరము.', 'నా సంఘమును కట్టుదును, పాతాళలోక ద్వారములు దానియెదుట నిలువనేరవు. (మత్తయి 16:18)'],
  ['జయించువాడు', 'నామవాచకం', '/jayinchuvaadu/', 'విశ్వాసము ద్వారా లోకమును, శరీరాశలను, సాతానును జయించే క్రీస్తు అనుచరుడు.', 'జయించువానిని నాతోకూడ నా సింహాసనమునందు కూర్చుండనిచ్చెదను. (ప్రకటన 3:21)'],
  ['దీనమనస్సు', 'నామవాచకం', '/deenamansu/', 'అహంకారం లేని వినయ స్వభావము, దేవుని ఎదుట తగ్గించుకొనుట.', 'దేవుడు అహంకారులను ఎదిరించి దీనులకు కృప అనుగ్రహించును. (1 పేతురు 5:5)']
];

const KANNADA_ENTRIES = [
  ['ಕೃಪೆ', 'ನಾಮಪದ', '/krupe/', 'ಯೇಸು ಕ್ರಿಸ್ತನ ಮೂಲಕ ದೇವರಿಂದ ಉಚಿತವಾಗಿ ದೊರೆಯುವ ದೈವಿಕ ಕೃಪೆ ಮತ್ತು ಪರಿಶುದ್ಧ ಜೀವನಕ್ಕೆ ಬೇಕಾದ ಶಕ್ತಿ.', 'ನೀವು ನಂಬಿಕೆಯ ಮೂಲಕ ಕೃಪೆಯಿಂದಲೇ ರಕ್ಷಿಸಲ್ಪಟ್ಟಿದ್ದೀರಿ. (ಎಫೆಸ 2:8)'],
  ['ನಂಬಿಕೆ', 'ನಾಮಪದ', '/nambike/', 'ನಿರೀಕ್ಷಿಸುವಂಥವುಗಳ ನಿಜರೂಪವೂ ಕಣ್ಣಿಗೆ ಕಾಣದವುಗಳ ನಿಶ್ಚಯವೂ ಆಗಿರುವ ದೈವಭಕ್ತಿ.', 'ನೀತಿವಂತನು ನಂಬಿಕೆಯಿಂದ ಜೀವಿಸುವನು. (ರೋಮಾಪುರದವರಿಗೆ 1:17)'],
  ['ಶಿಷ್ಯ', 'ನಾಮಪದ', '/shishya/', 'ತನ್ನನ್ನು ತಾನು ಅಲ್ಲಗಳೆದು ದಿನದಿನವೂ ತನ್ನ ಶಿలువವನ್ನು ಹೊತ್ತುಕೊಂಡು ಕ್ರಿಸ್ತನನ್ನು ಹಿಂಬಾಲಿಸುವವನು.', 'ನೀವು ನನ್ನ ವಾಕ್ಯದಲ್ಲಿ ನೆಲೆಗೊಂಡವರಾದರೆ ನಿಜವಾಗಿಯೂ ನನ್ನ ಶಿಷ್ಯರಾಗಿದ್ದೀರಿ. (ಯೋಹಾನ 8:31)'],
  ['ಪರಿಶುದ್ಧತೆ', 'ನಾಮಪದ', '/parishuddhate/', 'ಪಾಪದಿಂದ ಪ್ರತ್ಯೇಕಿಸಲ್ಪಟ್ಟು ದೇವರಿಗೆ ಸಮರ್ಪಿತವಾದ ಪವಿತ್ರ ಜೀವನ.', 'ನಾನು ಪರಿಶುದ್ಧನಾಗಿರುವ ಕಾರಣ ನೀವೂ ಪರಿಶುದ್ಧರಾಗಿರಬೇಕು. (1 ಪೇತ್ರ 1:16)'],
  ['ನೀತಿ', 'ನಾಮಪದ', '/neeti/', 'ದೇವರ ಪರಿಶುದ್ಧ ಸ್ವಭಾವಕ್ಕೆ ತಕ್ಕಂತೆ ಬದುಕುವ ಸತ್ಯವಾದ ಜೀವನ.', 'ನೀತಿಗಾಗಿ ಹಸಿದು ಬಾಯಾರಿದವರು ಧನ್ಯರು. (ಮತ್ತಾಯ 5:6)'],
  ['ಪಶ್ಚಾತ್ತಾಪ', 'ನಾಮಪದ', '/pashchaattaapa/', 'ಪಾಪವನ್ನು ಬಿಟ್ಟು ಮನಸ್ಸನ್ನು ಪೂರ್ಣವಾಗಿ ಬದಲಾಯಿಸಿ ದೇವರ ಕಡೆಗೆ ತಿರುಗುವುದು.', 'ಮನಸ್ಸು ತಿರುಗಿಸಿಕೊಳ್ಳಿರಿ, ಪರಲೋಕರಾಜ್ಯವು ಸಮೀಪಿಸಿದೆ. (ಮತ್ತಾಯ 4:17)'],
  ['ರಕ್ಷಣೆ', 'ನಾಮಪದ', '/rakshane/', 'ಯೇಸು ಕ್ರಿಸ್ತನ ರಕ್ತದ ಮೂಲಕ ಪಾಪದ ದಂಡನೆಯಿಂದ ಸಿಗುವ ನಿತ್ಯ ಬಿಡುಗಡೆ.', 'ಕರ್ತನಾದ ಯೇಸುವಿನಲ್ಲಿ ನಂಬಿಕೆಯಿಡು, ಆಗ ನೀನೂ ನಿನ್ನ ಮನೆಯವರೂ ರಕ್ಷಿಸಲ್ಪಡುವಿರಿ. (ಅ. ಕೃ. 16:31)'],
  ['ಒಡಂಬಡಿಕೆ', 'ನಾಮಪದ', '/odambadike/', 'ಯೇಸು ಕ್ರಿಸ್ತನ ರಕ್ತದಲ್ಲಿ ಸ್ಥಾಪಿಸಲ್ಪಟ್ಟ ನೂತನ ಒಡಂಬಡಿಕೆ.', 'ಈ ಪಾತ್ರೆಯು ನಿಮಗೋಸ್ಕರ ಸುರಿಸಲಾಗುವ ನನ್ನ ರಕ್ತದಲ್ಲಿನ ಹೊಸ ಒಡಂಬಡಿಕೆಯಾಗಿದೆ. (ಲೂಕ 22:20)'],
  ['ಶಿಲುವೆ', 'ನಾಮಪದ', '/shiluve/', 'ಕ್ರಿಸ್ತನ ಬಲಿಯ ಸಂಕೇತ ಮತ್ತು ಸ್ವಂತ ಜೀವವನ್ನು ಕೊನೆಗಾಣಿಸಿ ದೇವರಿಗಾಗಿ ಬದುಕುವ ಮಾದರಿ.', 'ಯಾವನಾದರೂ ನನ್ನನ್ನು ಹಿಂಬಾಲಿಸಬೇಕೆಂದಿದ್ದರೆ ಅವನು ತನ್ನನ್ನು ತಾನು ಅಲ್ಲಗಳೆದು ತನ್ನ ಶಿಲುವೆಯನ್ನು ಹೊತ್ತುಕೊಂಡು ನನ್ನನ್ನು ಹಿಂಬಾಲಿಸಲಿ. (ಮತ್ತಾಯ 16:24)'],
  ['ಪುನರುತ್ಥಾನ', 'ನಾಮಪದ', '/punarutthaana/', 'ಯೇಸು ಕ್ರಿಸ್ತನು ಮರಣವನ್ನು ಜಯಿಸಿ ಜೀವದಿಂದ ಎದ್ದುಬಂದ ಜಯ.', 'ಪುನರುತ್ಥಾನವೂ ಜೀವವೂ ನಾನೇ. (ಯೋಹಾನ 11:25)'],
  ['ಪ್ರಾರ್ಥನೆ', 'ನಾಮಪದ', '/praarthane/', 'ಪರಲೋಕದ ತಂದೆಯೊಡನೆ ಮಾಡುವ ಹೃದಯಪೂರ್ವಕ ಸಂಭಾಷಣೆ ಮತ್ತು ವಿಜ್ಞಾಪನೆ.', 'ಎಡೆಬಿಡದೆ ಪ್ರಾರ್ಥನೆಮಾಡಿರಿ. (1 ಥೆಸಲೋನಿಕ 5:17)'],
  ['ಸಮಾಧಾನ', 'ನಾಮಪದ', '/samaadhaana/', 'ದೇವರೊಡನೆ ಉಂಟಾಗುವ ಶಾಂತಿ ಮತ್ತು ಲೋಕವು ಕೊಡಲಾರದ ಆಂತರಿಕ ಶಾಂತಿ (ಶಾಲೋಮ್).', 'ನನ್ನ ಸಮಾಧಾನವನ್ನೇ ನಿಮಗೆ ಕೊಡುತ್ತೇನೆ. (ಯೋಹಾನ 14:27)'],
  ['ಸತ್ಯ', 'ನಾಮಪದ', '/satya/', 'ಮನುಷ್ಯನನ್ನು ಬಿಡುಗಡೆ ಮಾಡುವ ದೇವರ ಶಾಶ್ವತ ವಾಕ್ಯ.', 'ಸತ್ಯವನ್ನು ತಿಳಿದುಕೊಳ್ಳುವಿರಿ, ಸತ್ಯವು ನಿಮ್ಮನ್ನು ಸ್ವತಂತ್ರರನ್ನಾಗಿ ಮಾಡುವದು. (ಯೋಹಾನ 8:32)'],
  ['ಕ್ಷಮೆ', 'ನಾಮಪದ', '/kshame/', 'ಕ್ರಿಸ್ತನು ನಮ್ಮನ್ನು ಕ್ಷಮಿಸಿದಂತೆ ನಾವೂ ಇತರರನ್ನು ಕ್ಷಮಿಸುವ ದೈವಿಕ ಗುಣ.', 'ಕರ್ತನು ನಿಮ್ಮನ್ನು ಕ್ಷಮಿಸಿದಂತೆ ನೀವೂ ಒಬ್ಬರನ್ನೊಬ್ಬರು ಕ್ಷಮಿಸಿರಿ. (ಕೊಲೊಸ್ಸೆ 3:13)'],
  ['ಸುವಾರ್ತೆ', 'ನಾಮಪದ', '/suvaarte/', 'ಯೇಸು ಕ್ರಿಸ್ತನ ಮೂಲಕ ಸಮಸ್ತ ಮಾನವಕುಲಕ್ಕೆ ಸಿಗುವ ರಕ್ಷಣೆಯ ಶುಭಸುದ್ದಿ.', 'ಲೋಕದಲ್ಲೆಲ್ಲಾ ಹೋಗಿ ಸರ್ವಸೃಷ್ಟಿಗೆ ಸುವಾರ್ತೆಯನ್ನು ಸಾರಿರಿ. (ಮಾರ್ಕ 16:15)'],
  ['ಪ್ರೀತಿ', 'ನಾಮಪದ', '/preeti/', 'ಸ್ವಾರ್ಥವಿಲ್ಲದ, ತ್ಯಾಗಭರಿತ ದೈವಿಕ ಪ್ರೀತಿ (ಅಗಾಪೆ).', 'ದೇವರು ಲೋಕವನ್ನು ಎಷ್ಟೋ ಪ್ರೀತಿಸಿದನು. (ಯೋಹಾನ 3:16)'],
  ['ಪವಿತ್ರಾತ್ಮ', 'ನಾಮಪದ', '/pavitraatma/', 'ತ್ರಿತ್ವದಲ್ಲಿ ಮೂರನೆಯ ವ್ಯಕ್ತಿ; ಆದರಣಾದಾಯಕ, ಬೋಧಕ, ಮಾರ್ಗದರ್ಶಕ.', 'ಪವಿತ್ರಾತ್ಮನು ನಿಮ್ಮ ಮೇಲೆ ಬರುವಾಗ ನೀವು ಬಲವನ್ನು ಹೊಂದುವಿರಿ. (ಅ. ಕೃ. 1:8)'],
  ['ಸಭೆ', 'ನಾಮಪದ', '/sabhe/', 'ಕ್ರಿಸ್ತನೇ ಶಿರಸ್ಸಾಗಿರುವ ವಿಶ್ವಾಸಿಗಳ ಆತ್ಮಿಕ ಶರೀರ.', 'ನನ್ನ ಸಭೆಯನ್ನು ಕಟ್ಟುವೆನು, ಪಾತಾಳದ ಬಾಗಿಲುಗಳು ಅದರ ಮೇಲೆ ಜಯಗಳಿಸಲಾರವು. (ಮತ್ತಾಯ 16:18)'],
  ['ಜಯಿಸುವವನು', 'ನಾಮಪದ', '/jayisuvavanu/', 'ವಿಶ್ವಾಸದಿಂದ ಲೋಕವನ್ನೂ ಮಾಂಸವನ್ನೂ ಸೈತಾನನನ್ನೂ ಜಯಿಸುವ ಕ್ರಿಸ್ತ ಶಿಷ್ಯ.', 'ಜಯಿಸುವವನಿಗೆ ನನ್ನ ಸಿಂಹಾಸನದಲ್ಲಿ ನನ್ನೊಂದಿಗೆ ಕೂತುಕೊಳ್ಳುವಂತೆ ಅನುಗ್ರಹಿಸುವೆನು. (ಪ್ರಕಟನೆ 3:21)'],
  ['ದೀನತೆ', 'ನಾಮಪದ', '/deenate/', 'ಗರ್ವವಿಲ್ಲದ ನಮ್ರ ಸ್ವಭಾವ, ದೇವರ ಮುಂದೆ ತನ್ನನ್ನು ತಗ್ಗಿಸಿಕೊಳ್ಳುವುದು.', 'ದೇವರು ಗರ್ವಿಷ್ಠರನ್ನು ವಿರೋಧಿಸುತ್ತಾನೆ, ಆದರೆ ದೀನರಿಗೆ ಕೃಪೆಯನ್ನು ನೀಡುತ್ತಾನೆ. (1 ಪೇತ್ರ 5:5)']
];

async function main() {
  console.log('\\n--- Building Dictionaries ---');
  
  // 1. English Dictionary (from english.json)
  const engRawPath = path.join(__dirname, '..', 'data', 'dictionaries_raw', 'english.json');
  let engEntries = [];
  if (fs.existsSync(engRawPath)) {
    console.log('Loading English JSON dataset...');
    const engJson = JSON.parse(fs.readFileSync(engRawPath, 'utf8'));
    for (const [word, definition] of Object.entries(engJson)) {
      if (word && definition) {
        engEntries.push([word.trim(), '', '', definition.trim(), '']);
      }
    }
  } else {
    engEntries = EASTONS_ENTRIES; // fallback
  }

  // 2. Tamil Dictionary (from tamil.json)
  const taRawPath = path.join(__dirname, '..', 'data', 'dictionaries_raw', 'tamil.json');
  let taEntries = [];
  if (fs.existsSync(taRawPath)) {
    console.log('Loading Tamil JSON dataset...');
    const taJson = JSON.parse(fs.readFileSync(taRawPath, 'utf8'));
    for (const entry of taJson) {
      if (entry.eng && entry.tamil) {
        taEntries.push([entry.eng.trim(), '', '', entry.tamil.trim(), '']);
      }
    }
  } else {
    taEntries = TAMIL_ENTRIES; // fallback
  }

  buildDict('en', engEntries);
  buildDict('eastons', EASTONS_ENTRIES);
  buildDict('strongs', STRONGS_ENTRIES);
  buildDict('es', SPANISH_ENTRIES);
  buildDict('fr', FRENCH_ENTRIES);
  buildDict('de', GERMAN_ENTRIES);
  buildDict('pt', PORTUGUESE_ENTRIES);
  buildDict('ru', RUSSIAN_ENTRIES);

  // Indian Languages
  buildDict('ta', taEntries);
  buildDict('ml', MALAYALAM_ENTRIES);
  buildDict('te', TELUGU_ENTRIES);
  buildDict('kn', KANNADA_ENTRIES);
  buildDict('hi', HINDI_ENTRIES);

  console.log('\\nAll 13 dictionary packages (including 5 Indian languages) built successfully!\\n');
}

main();
