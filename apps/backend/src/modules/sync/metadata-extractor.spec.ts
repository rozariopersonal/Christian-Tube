import { extractVideoMetadata, romanToDecimal } from './metadata-extractor';

describe('Video Metadata Extractor', () => {
  describe('romanToDecimal', () => {
    it('should correctly convert Roman numerals', () => {
      expect(romanToDecimal('I')).toBe(1);
      expect(romanToDecimal('IV')).toBe(4);
      expect(romanToDecimal('V')).toBe(5);
      expect(romanToDecimal('IX')).toBe(9);
      expect(romanToDecimal('X')).toBe(10);
      expect(romanToDecimal('XIV')).toBe(14);
      expect(romanToDecimal('XXXVII')).toBe(37);
    });
  });

  describe('extractVideoMetadata', () => {
    it('should extract full metadata for a classic CFC sermon', () => {
      const input = {
        title: 'All That Jesus Taught | Part 37 | Bro. Zac Poonen',
        description: 'Sunday morning sermon on Matthew 5:3 in Chennai CFC.\n00:00 - Introduction\n05:12 - The Beatitudes\n25:00 - Closing Prayer',
        channelTitle: 'CFC Chennai',
      };

      const meta = extractVideoMetadata(input);

      expect(meta.speaker).toBe('Zac Poonen');
      expect(meta.subSeries).toBe('All That Jesus Taught');
      expect(meta.partNumber).toBe(37);
      expect(meta.location).toBe('Chennai');
      expect(meta.meetingType).toBe('Sunday Service');
      expect(meta.language).toBe('Tamil');
      expect(meta.secondaryLanguage).toBe('English');
      expect(meta.scripture).toEqual({ book: 'MAT', chapter: 5, verse: 3 });
      expect(meta.topics).toContain('Discipleship');
      expect(meta.cleanTitle).toBe('All That Jesus Taught | Part 37');
      expect(meta.chapters).toHaveLength(3);
      expect(meta.chapters?.[0]).toEqual({
        title: 'Introduction',
        seconds: 0,
        timestamp: '00:00',
      });
      expect(meta.chapters?.[1]).toEqual({
        title: 'The Beatitudes',
        seconds: 312,
        timestamp: '05:12',
      });
    });

    it('should extract metadata for youth camp meetings', () => {
      const input = {
        title: 'Youth Camp 2024 - Overcoming Temptation & Victory Over Sin - Bro. Sandeep Poonen',
        description: 'Meeting for young people and teens at Bangalore',
        channelTitle: 'CFC Bangalore',
      };

      const meta = extractVideoMetadata(input);

      expect(meta.speaker).toBe('Sandeep Poonen');
      expect(meta.meetingType).toBe('Youth Camp');
      expect(meta.targetAudience).toBe('Youth');
      expect(meta.location).toBe('Bangalore');
      expect(meta.topics).toContain('Holiness');
    });

    it('should detect bilingual [Tamil-English] tags', () => {
      const input = {
        title: 'Living Free From Guilt [Tamil-English] - Bro. Bobby Babu',
        description: 'Romans 8:28 sermon at Coimbatore',
        channelTitle: 'CFC Coimbatore',
      };

      const meta = extractVideoMetadata(input);

      expect(meta.speaker).toBe('Bobby Babu');
      expect(meta.language).toBe('Tamil');
      expect(meta.secondaryLanguage).toBe('English');
      expect(meta.location).toBe('Coimbatore');
      expect(meta.scripture).toEqual({ book: 'ROM', chapter: 8, verse: 28 });
    });

    it('should detect Unicode Hindi / Telugu / Malayalam scripts', () => {
      const hindiInput = {
        title: 'परमेश्वर का अनुग्रह - Bro. Zac Poonen',
        description: 'Hindi meeting on Grace and Faith',
        channelTitle: 'CFC Hindi',
      };
      const hindiMeta = extractVideoMetadata(hindiInput);
      expect(hindiMeta.language).toBe('Hindi');
      expect(hindiMeta.speaker).toBe('Zac Poonen');

      const teluguInput = {
        title: 'దేవుని వాక్యం - Bro. George Mathew',
        description: 'Telugu sermon',
        channelTitle: 'CFC Telugu',
      };
      const teluguMeta = extractVideoMetadata(teluguInput);
      expect(teluguMeta.language).toBe('Telugu');
      expect(teluguMeta.speaker).toBe('George Mathew');
    });

    it('should parse Roman numeral part numbers', () => {
      const input = {
        title: 'Through The Bible - Part XIV - Bro. Zac Poonen',
        description: '1 Corinthians 13 study on Love and Unity',
        channelTitle: 'Christian Fellowship Church',
      };

      const meta = extractVideoMetadata(input);

      expect(meta.speaker).toBe('Zac Poonen');
      expect(meta.subSeries).toBe('Through The Bible');
      expect(meta.partNumber).toBe(14);
      expect(meta.scripture).toEqual({ book: '1CO', chapter: 13, verse: undefined });
      expect(meta.topics).toContain('Love & Forgiveness');
    });

    it('should extract family and marriage target audience and topics', () => {
      const input = {
        title: 'Building a Christ-Centered Marriage & Home - Bro. Ian Poonen',
        description: 'Meeting for couples and parents at Loveland',
        channelTitle: 'RLCF',
      };

      const meta = extractVideoMetadata(input);

      expect(meta.speaker).toBe('Ian Poonen');
      expect(meta.targetAudience).toBe('Married Couples / Families');
      expect(meta.location).toBe('Loveland');
      expect(meta.topics).toContain('Family & Marriage');
    });
  });
});
