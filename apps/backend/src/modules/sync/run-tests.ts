import { extractVideoMetadata, romanToDecimal } from './metadata-extractor';

function assert(condition: boolean, message: string) {
  if (!condition) {
    throw new Error(`Assertion failed: ${message}`);
  }
}

function runTests() {
  console.log('--- Running Metadata Extractor Tests ---');

  // Test 1: Roman numerals
  assert(romanToDecimal('I') === 1, 'Roman I should be 1');
  assert(romanToDecimal('IV') === 4, 'Roman IV should be 4');
  assert(romanToDecimal('XIV') === 14, 'Roman XIV should be 14');
  assert(romanToDecimal('XXXVII') === 37, 'Roman XXXVII should be 37');
  console.log('✓ romanToDecimal passed');

  // Test 2: Classic CFC Sermon
  const m1 = extractVideoMetadata({
    title: 'All That Jesus Taught | Part 37 | Bro. Zac Poonen',
    description: 'Sunday morning sermon on Matthew 5:3 in Chennai CFC.\n00:00 - Introduction\n05:12 - The Beatitudes\n25:00 - Closing Prayer',
    channelTitle: 'CFC Chennai',
  });
  assert(m1.speaker === 'Zac Poonen', `Expected speaker Zac Poonen, got ${m1.speaker}`);
  assert(m1.subSeries === 'All That Jesus Taught', `Expected subSeries All That Jesus Taught, got ${m1.subSeries}`);
  assert(m1.partNumber === 37, `Expected partNumber 37, got ${m1.partNumber}`);
  assert(m1.location === 'Chennai', `Expected location Chennai, got ${m1.location}`);
  assert(m1.meetingType === 'Sunday Service', `Expected meetingType Sunday Service, got ${m1.meetingType}`);
  assert(m1.language === 'Tamil', `Expected language Tamil, got ${m1.language}`);
  assert(m1.secondaryLanguage === 'English', `Expected secondaryLanguage English, got ${m1.secondaryLanguage}`);
  assert(m1.scripture?.book === 'MAT' && m1.scripture?.chapter === 5 && m1.scripture?.verse === 3, `Expected Scripture MAT 5:3`);
  assert(m1.cleanTitle === 'All That Jesus Taught | Part 37', `Expected cleanTitle 'All That Jesus Taught | Part 37', got '${m1.cleanTitle}'`);
  assert(m1.chapters?.length === 3, `Expected 3 chapters, got ${m1.chapters?.length}`);
  console.log('✓ Classic CFC Sermon passed');

  // Test 3: Youth Camp
  const m2 = extractVideoMetadata({
    title: 'Youth Camp 2024 - Overcoming Temptation & Victory Over Sin - Bro. Sandeep Poonen',
    description: 'Meeting for young people and teens at Bangalore',
    channelTitle: 'CFC Bangalore',
  });
  assert(m2.speaker === 'Sandeep Poonen', `Expected speaker Sandeep Poonen, got ${m2.speaker}`);
  assert(m2.meetingType === 'Youth Camp', `Expected meetingType Youth Camp, got ${m2.meetingType}`);
  assert(m2.targetAudience === 'Youth', `Expected targetAudience Youth, got ${m2.targetAudience}`);
  assert(m2.location === 'Bangalore', `Expected location Bangalore, got ${m2.location}`);
  assert(m2.topics?.includes('Holiness') === true, `Expected topics to include Holiness`);
  console.log('✓ Youth Camp passed');

  // Test 4: Bilingual tag
  const m3 = extractVideoMetadata({
    title: 'Living Free From Guilt [Tamil-English] - Bro. Bobby Babu',
    description: 'Romans 8:28 sermon at Coimbatore',
    channelTitle: 'CFC Coimbatore',
  });
  assert(m3.speaker === 'Bobby Babu', `Expected speaker Bobby Babu, got ${m3.speaker}`);
  assert(m3.language === 'Tamil', `Expected language Tamil, got ${m3.language}`);
  assert(m3.secondaryLanguage === 'English', `Expected secondaryLanguage English, got ${m3.secondaryLanguage}`);
  assert(m3.location === 'Coimbatore', `Expected location Coimbatore, got ${m3.location}`);
  assert(m3.scripture?.book === 'ROM' && m3.scripture?.chapter === 8 && m3.scripture?.verse === 28, `Expected Scripture ROM 8:28`);
  console.log('✓ Bilingual tag passed');

  // Test 5: Unicode scripts
  const m4 = extractVideoMetadata({
    title: 'परमेश्वर का अनुग्रह - Bro. Zac Poonen',
    description: 'Hindi meeting on Grace and Faith',
    channelTitle: 'CFC Hindi',
  });
  assert(m4.language === 'Hindi', `Expected language Hindi, got ${m4.language}`);
  assert(m4.speaker === 'Zac Poonen', `Expected speaker Zac Poonen, got ${m4.speaker}`);
  console.log('✓ Unicode scripts passed');

  // Test 6: Marriage & Family
  const m5 = extractVideoMetadata({
    title: 'Building a Christ-Centered Marriage & Home - Bro. Ian Poonen',
    description: 'Meeting for couples and parents at Loveland',
    channelTitle: 'RLCF',
  });
  assert(m5.speaker === 'Ian Poonen', `Expected speaker Ian Poonen, got ${m5.speaker}`);
  assert(m5.targetAudience === 'Married Couples / Families', `Expected targetAudience Married Couples / Families, got ${m5.targetAudience}`);
  assert(m5.location === 'Loveland', `Expected location Loveland, got ${m5.location}`);
  assert(m5.topics?.includes('Family & Marriage') === true, `Expected topics to include Family & Marriage`);
  console.log('✓ Marriage & Family passed');

  console.log('\n🎉 ALL METADATA EXTRACTOR TESTS PASSED SUCCESSFULLY!\n');
}

runTests();
