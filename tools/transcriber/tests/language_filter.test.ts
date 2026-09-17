import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { checkPureEnglish } from '../src/language_filter.js';

describe('LanguageFilter: Pure English Detection', () => {
  it('accepts pure English titles', () => {
    const titles = [
      'What Brokenness Means - Zac Poonen',
      'True Riches and Wise Fathers - Zac Poonen',
      'Right Attitudes When We Break Bread - Zac Poonen',
      'Sing Songs Meaningfully - Zac Poonen',
      'Commitment To The Local Church - Zac Poonen',
      'The Beginning of CFC in Tamilnadu (English)',
    ];

    for (const title of titles) {
      const res = checkPureEnglish(title);
      assert.equal(res.isPureEnglish, true, `Expected pure English for: ${title}`);
    }
  });

  it('rejects titles with non-Latin / Indic scripts', () => {
    const titles = [
      'Understanding Dead Works | ನಿರ್ಜೀವ ಕಾರ್ಯಗಳನ್ನು ಅರ್ಥಮಾಡಿಕೊಳ್ಳುವುದು | Zac Poonen | Kannada',
      'Cast All Your Burdens On Jesus | ನಿಮ್ಮ ಎಲ್ಲಾ ಭಾರವನ್ನು ಯೇಸುವಿನ ಮೇಲೆ ಹಾಕಿರಿ | Zac Poonen Illustrations',
      'God’s Wonderful Promises | தேவனின் அற்புதமான வாக்குத்தத்தங்கள் | Zac Poonen | Tamil',
    ];

    for (const title of titles) {
      const res = checkPureEnglish(title);
      assert.equal(res.isPureEnglish, false, `Expected rejection for: ${title}`);
      assert.ok(res.reason, 'Expected a rejection reason');
    }
  });

  it('rejects titles with translation / multilingual keywords', () => {
    const titles = [
      'Zac Poonen Illustrations - Life under the law and under the Holy Spirit (Tamil Translation)',
      'All That Jesus Taught (Bible Study – 14 of 80) - Zac Poonen (with Romanian Subtitles)',
      'Sermon with Hindi translation - Zac Poonen',
      'English to Telugu interpreted message',
    ];

    for (const title of titles) {
      const res = checkPureEnglish(title);
      assert.equal(res.isPureEnglish, false, `Expected rejection for: ${title}`);
    }
  });

  it('rejects videos when channelLanguage is non-English', () => {
    const res = checkPureEnglish('Normal English Title', undefined, 'Tamil');
    assert.equal(res.isPureEnglish, false);
    assert.ok(res.reason?.includes('Tamil'));

    const res2 = checkPureEnglish('Normal English Title', undefined, 'English');
    assert.equal(res2.isPureEnglish, true);
  });
});
