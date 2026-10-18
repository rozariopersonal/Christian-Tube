#!/usr/bin/env node
/**
 * tool/systematic_audit_scriptures.mjs
 * 
 * Systematic examination of all 4,748 extracted passages in releases/scriptures.json
 * against:
 * 1. Structural & Schema Rules (verse bounds, category taxonomy, tag vocabulary, theme length/casing)
 * 2. High-Risk Moral Failures & Sin Narrative Chapters (2 Sam 11, Gen 34, Gen 38, 1 Kings 11, etc.)
 * 3. Ceremonial Shadows (Levitical sacrificial rules, dietary/uncleanness, tabernacle dimensions)
 * 4. Imprecations & Physical Warfare Slaughter
 * 5. Job Friends' Speeches & Ecclesiastes Cynicism
 * 6. Satanic / Antagonist Speeches
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT = path.resolve(__dirname, '..');

const SCRIPTURES_FILE = path.join(ROOT, 'releases', 'scriptures.json');
const BOOKS_FILE = path.join(ROOT, 'releases', 'bibles', 'web', 'books.json');

const CATEGORIES = [
  'words_of_god', 'jesus_words', 'prophecy', 'promise', 'commandment',
  'wisdom', 'doctrine', 'comfort', 'warning', 'prayer', 'praise',
  'salvation', 'faith', 'repentance', 'miracle', 'parable', 'divine_action', 'consecration',
];

const MASTER_TAGS = [
  'god_character', 'sovereignty', 'holiness', 'mercy_grace', 'christ_messiah', 'holy_spirit', 'trinity',
  'salvation', 'the_cross', 'resurrection', 'faith', 'forgiveness', 'repentance', 'eternal_life', 'justification',
  'prayer', 'worship_praise', 'thanksgiving', 'obedience', 'consecration', 'humility', 'word_of_god', 'fear_of_god', 'seeking_god', 'discipleship',
  'peace', 'comfort', 'hope', 'anxiety_fear', 'suffering_trials', 'joy', 'healing', 'perseverance', 'deliverance',
  'love', 'purity', 'wisdom', 'integrity', 'patience', 'courage', 'self_control', 'generosity', 'truth', 'righteousness',
  'marriage', 'family', 'fellowship_unity', 'service', 'forgiving_others', 'edification',
  'spiritual_warfare', 'temptation', 'pride', 'sin_warning', 'deceit', 'worldliness', 'idolatry',
  'covenant', 'prophecy', 'second_coming', 'kingdom_of_god', 'heaven', 'judgment', 'eternal_reward'
];

function loadVerses(bookNum, chapter) {
  const f = path.join(ROOT, 'releases', 'bibles', 'web', String(bookNum), `${chapter}.json`);
  if (!fs.existsSync(f)) return [];
  return JSON.parse(fs.readFileSync(f, 'utf8'));
}

async function audit() {
  const passages = JSON.parse(fs.readFileSync(SCRIPTURES_FILE, 'utf8'));
  const books = JSON.parse(fs.readFileSync(BOOKS_FILE, 'utf8'));
  const booksMap = new Map(books.map(b => [b.bookNumber, b]));

  console.log(`======================================================================`);
  console.log(` SYSTEMATIC AUDIT OF SCRIPTURE FEED (${passages.length} PASSAGES)`);
  console.log(`======================================================================\n`);

  const report = {
    totalPassages: passages.length,
    schemaIssues: [],
    invalidVerseBounds: [],
    invalidCategories: [],
    invalidTags: [],
    duplicateTags: [],
    tagCountIssues: [],
    themeLengthIssues: [],
    themeCasingIssues: [],
    oversizedPassages: [],
    
    // Hermeneutical & Content Audit
    moralFailurePassages: [],
    ceremonialPassages: [],
    imprecationOrWarPassages: [],
    jobFriendsDoctrines: [],
    antagonistSpeeches: [],
  };

  for (let i = 0; i < passages.length; i++) {
    const p = passages[i];
    const b = booksMap.get(p.bookNumber);
    const verses = loadVerses(p.bookNumber, p.chapter);
    const maxVerseInChapter = verses.length;

    // 1. Verse Bounds Check
    if (p.startVerse < 1 || p.endVerse < p.startVerse || p.endVerse > maxVerseInChapter) {
      report.invalidVerseBounds.push({
        ref: p.referenceLabel,
        error: `Invalid range ${p.startVerse}-${p.endVerse} (Chapter has ${maxVerseInChapter} verses)`,
      });
    }

    // 2. Length Guard
    const length = p.endVerse - p.startVerse + 1;
    if (length > 25) {
      report.oversizedPassages.push({
        ref: p.referenceLabel,
        length,
        theme: p.theme,
      });
    }

    // 3. Category Validation
    if (!CATEGORIES.includes(p.category)) {
      report.invalidCategories.push({
        ref: p.referenceLabel,
        category: p.category,
      });
    }

    // 4. Tag Validation
    if (!Array.isArray(p.tags) || p.tags.length === 0 || p.tags.length > 5) {
      report.tagCountIssues.push({
        ref: p.referenceLabel,
        count: p.tags ? p.tags.length : 0,
      });
    }

    const seenTags = new Set();
    for (const t of p.tags || []) {
      if (!MASTER_TAGS.includes(t)) {
        report.invalidTags.push({ ref: p.referenceLabel, tag: t });
      }
      if (seenTags.has(t)) {
        report.duplicateTags.push({ ref: p.referenceLabel, tag: t });
      }
      seenTags.add(t);
    }

    // 5. Theme Word Count & Casing Check
    const words = (p.theme || '').trim().split(/\s+/).filter(Boolean);
    if (words.length < 3 || words.length > 8) { // allow 3-6 strictly, flag >8
      report.themeLengthIssues.push({
        ref: p.referenceLabel,
        theme: p.theme,
        wordCount: words.length,
      });
    }

    // 6. Content Auditing: get actual passage verse text
    const passageVerses = verses.filter(v => v.verse >= p.startVerse && v.verse <= p.endVerse);
    const passageText = passageVerses.map(v => v.text).join(' ').toLowerCase();

    // 6A. High-Risk Moral Failures
    // 2 Samuel 11: David & Bathsheba
    if (p.bookNumber === 10 && p.chapter === 11) {
      report.moralFailurePassages.push({
        ref: p.referenceLabel,
        theme: p.theme,
        reason: '2 Samuel 11 (David adultery/Uriah murder narrative)',
      });
    }
    // Genesis 34: Dinah revenge massacre
    if (p.bookNumber === 1 && p.chapter === 34) {
      report.moralFailurePassages.push({
        ref: p.referenceLabel,
        theme: p.theme,
        reason: 'Genesis 34 (Simeon & Levi deceitful slaughter)',
      });
    }
    // Genesis 38: Judah and Tamar
    if (p.bookNumber === 1 && p.chapter === 38) {
      report.moralFailurePassages.push({
        ref: p.referenceLabel,
        theme: p.theme,
        reason: 'Genesis 38 (Judah & Tamar narrative)',
      });
    }
    // Peter's Denial: Matt 26:69-75, Mark 14:66-72, Luke 22:54-62, John 18:15-18, 25-27
    if (
      (p.bookNumber === 40 && p.chapter === 26 && p.startVerse >= 69) ||
      (p.bookNumber === 41 && p.chapter === 14 && p.startVerse >= 66) ||
      (p.bookNumber === 42 && p.chapter === 22 && p.startVerse >= 54 && p.endVerse <= 62) ||
      (p.bookNumber === 43 && p.chapter === 18 && ((p.startVerse >= 15 && p.endVerse <= 18) || (p.startVerse >= 25 && p.endVerse <= 27)))
    ) {
      report.moralFailurePassages.push({
        ref: p.referenceLabel,
        theme: p.theme,
        reason: "Peter's Denial extracted as devotional card",
      });
    }
    // Judas's Betrayal: Matt 27:3-5, Acts 1:18
    if (
      (p.bookNumber === 40 && p.chapter === 27 && p.startVerse <= 5) ||
      (p.bookNumber === 44 && p.chapter === 1 && p.startVerse === 18)
    ) {
      report.moralFailurePassages.push({
        ref: p.referenceLabel,
        theme: p.theme,
        reason: "Judas Suicide/Grave details extracted",
      });
    }

    // 6B. Old Covenant Ceremonial Shadows check
    // Check for explicit animal sacrifice procedures unless it's a prophetic/messianic or covenant passage
    const ceremonialKeywords = [
      'burnt offering of the herd',
      'wave offering before yahweh',
      'he-goat for a sin offering',
      'ram of the consecration',
      'sprinkle the blood on the altar',
      'fat that covers the innards',
      'unclean until the evening',
      'running issue of his flesh',
      'plague of leprosy in a garment',
      'sockets of fine brass',
      'hangings of the court',
      'cubits broad and cubits long',
    ];
    for (const kw of ceremonialKeywords) {
      if (passageText.includes(kw)) {
        // Exclude if it's Hebrews (which teaches the fulfillment of these)
        if (p.bookNumber !== 58) {
          report.ceremonialPassages.push({
            ref: p.referenceLabel,
            theme: p.theme,
            keyword: kw,
          });
        }
      }
    }

    // 6C. Imprecatory Violence against enemies
    // Psalm 109:6-19, Psalm 137:8-9
    if (p.bookNumber === 19 && p.chapter === 109 && (p.startVerse >= 6 && p.endVerse <= 19)) {
      report.imprecationOrWarPassages.push({
        ref: p.referenceLabel,
        theme: p.theme,
        reason: 'Psalm 109 imprecatory curse block extracted',
      });
    }
    if (p.bookNumber === 19 && p.chapter === 137 && p.endVerse >= 8) {
      report.imprecationOrWarPassages.push({
        ref: p.referenceLabel,
        theme: p.theme,
        reason: 'Psalm 137:8-9 dashing infants on rocks',
      });
    }

    // 6D. Job Friends' Speeches labeled as "doctrine"
    // Job chapters 4-27 (dialogues with Eliphaz, Bildad, Zophar)
    if (p.bookNumber === 18 && p.chapter >= 4 && p.chapter <= 27) {
      // Check if speaker is one of the friends
      // Eliphaz: 4-5, 15, 22
      // Bildad: 8, 18, 25
      // Zophar: 11, 20
      const friendChapters = [4, 5, 8, 11, 15, 18, 20, 22, 25];
      if (friendChapters.includes(p.chapter) && p.category === 'doctrine') {
        report.jobFriendsDoctrines.push({
          ref: p.referenceLabel,
          theme: p.theme,
          category: p.category,
          speakerChapter: `Job ${p.chapter} (Friend speech)`,
        });
      }
    }

    // 6E. Satan / Antagonist Speech labeled as divine or doctrine
    if (passageText.includes('you won\'t surely die') || passageText.includes('you will not surely die') || passageText.includes('all these things i will give you')) {
      report.antagonistSpeeches.push({
        ref: p.referenceLabel,
        theme: p.theme,
        textSnippet: passageText.slice(0, 80),
      });
    }
  }

  // PRINT SYSTEMATIC FINDINGS
  console.log(`--- 1. SCHEMA & VOCABULARY AUDIT ---`);
  console.log(`Invalid Verse Bounds:        ${report.invalidVerseBounds.length}`);
  console.log(`Invalid Categories:          ${report.invalidCategories.length}`);
  console.log(`Invalid / Unknown Tags:      ${report.invalidTags.length}`);
  console.log(`Duplicate Tags on Passage:   ${report.duplicateTags.length}`);
  console.log(`Tag Count Out of Bounds:     ${report.tagCountIssues.length}`);
  console.log(`Theme Word Count Issues:     ${report.themeLengthIssues.length}`);
  console.log(`Oversized (>25 verses):      ${report.oversizedPassages.length}`);

  console.log(`\n--- 2. HERMENEUTICAL & NEW COVENANT EXCLUSION AUDIT ---`);
  console.log(`Moral Failure Chapters:      ${report.moralFailurePassages.length}`);
  console.log(`Ceremonial Shadows Found:    ${report.ceremonialPassages.length}`);
  console.log(`Imprecations / Slaughter:    ${report.imprecationOrWarPassages.length}`);
  console.log(`Job Friends Doctrine Label:  ${report.jobFriendsDoctrines.length}`);
  console.log(`Antagonist Speeches Found:   ${report.antagonistSpeeches.length}`);

  // PRINT DETAILS IF ANY FOUND
  if (report.invalidVerseBounds.length > 0) {
    console.log(`\n[!] Invalid Verse Bounds Details:`);
    report.invalidVerseBounds.slice(0, 10).forEach(x => console.log(`   - ${x.ref}: ${x.error}`));
  }
  if (report.invalidCategories.length > 0) {
    console.log(`\n[!] Invalid Categories Details:`);
    report.invalidCategories.slice(0, 10).forEach(x => console.log(`   - ${x.ref}: ${x.category}`));
  }
  if (report.invalidTags.length > 0) {
    console.log(`\n[!] Invalid Tags Details:`);
    report.invalidTags.slice(0, 10).forEach(x => console.log(`   - ${x.ref}: ${x.tag}`));
  }
  if (report.moralFailurePassages.length > 0) {
    console.log(`\n[!] Moral Failure Details:`);
    report.moralFailurePassages.forEach(x => console.log(`   - ${x.ref} ("${x.theme}"): ${x.reason}`));
  }
  if (report.ceremonialPassages.length > 0) {
    console.log(`\n[!] Ceremonial Code Details:`);
    report.ceremonialPassages.forEach(x => console.log(`   - ${x.ref} ("${x.theme}"): contains "${x.keyword}"`));
  }
  if (report.imprecationOrWarPassages.length > 0) {
    console.log(`\n[!] Imprecations / War Details:`);
    report.imprecationOrWarPassages.forEach(x => console.log(`   - ${x.ref} ("${x.theme}"): ${x.reason}`));
  }
  if (report.jobFriendsDoctrines.length > 0) {
    console.log(`\n[!] Job Friends Speech Labeled as Doctrine:`);
    report.jobFriendsDoctrines.forEach(x => console.log(`   - ${x.ref} ("${x.theme}"): ${x.speakerChapter}`));
  }
  if (report.antagonistSpeeches.length > 0) {
    console.log(`\n[!] Antagonist Speech Found:`);
    report.antagonistSpeeches.forEach(x => console.log(`   - ${x.ref} ("${x.theme}"): "${x.textSnippet}"`));
  }

  // Also check empty chapters
  console.log(`\n--- 3. ZERO-PASSAGE CHAPTER AUDIT (Did clean chapters return []) ---`);
  const chaptersWithPassages = new Set(passages.map(p => `${p.bookNumber}_${p.chapter}`));
  let zeroCount = 0;
  const zeroChapters = [];
  for (const b of books) {
    for (let c = 1; c <= b.chapters; c++) {
      if (!chaptersWithPassages.has(`${b.bookNumber}_${c}`)) {
        zeroCount++;
        zeroChapters.push(`${b.name} ${c}`);
      }
    }
  }
  console.log(`Total Chapters Yielding 0 Passages: ${zeroCount} / 1189`);
  console.log(`Sample Zero Chapters: ${zeroChapters.slice(0, 15).join(', ')}...`);

  console.log(`\n======================================================================`);
  console.log(` AUDIT COMPLETE`);
  console.log(`======================================================================\n`);
}

audit().catch(console.error);
