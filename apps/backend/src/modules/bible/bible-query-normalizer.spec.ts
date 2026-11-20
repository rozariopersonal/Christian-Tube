import {
  fuzzyWordMatch,
  normalizeBibleQuery,
  numberToWords,
  resolveBookCandidate,
} from './bible-query-normalizer';

describe('bible-query-normalizer', () => {
  it('resolves canonical and misspelled book names with length-scaled typo safety', () => {
    expect(resolveBookCandidate('Matthew')).toEqual({ bookNumber: 40, bookName: 'Matthew' });
    expect(resolveBookCandidate('mathew')).toEqual({ bookNumber: 40, bookName: 'Matthew' });
    expect(resolveBookCandidate('pslam')).toEqual({ bookNumber: 19, bookName: 'Psalms' });
    expect(resolveBookCandidate('revelations')).toEqual({ bookNumber: 66, bookName: 'Revelation' });
    expect(resolveBookCandidate('1 corintians')).toEqual({ bookNumber: 46, bookName: '1 Corinthians' });
    expect(resolveBookCandidate('philipians')).toEqual({ bookNumber: 50, bookName: 'Philippians' });

    // Short common words must NOT misfire into 3-4 letter Bible books like John or Job.
    expect(resolveBookCandidate('join')).toBeNull();
    expect(resolveBookCandidate('had')).toBeNull();
    expect(resolveBookCandidate('for')).toBeNull();
  });

  it('expands standalone numbers outside references while preserving Bible citations', () => {
    expect(normalizeBibleQuery('jesus healed the 10 lepors')).toEqual({
      normalizedQuery: 'jesus healed the ten lepors',
      directRef: null,
    });

    expect(normalizeBibleQuery('jesus feeds 5000 men')).toEqual({
      normalizedQuery: 'jesus feeds five thousand men',
      directRef: null,
    });

    expect(normalizeBibleQuery('1 John 4:8')).toEqual({
      normalizedQuery: '1 John 4:8',
      directRef: {
        bookNumber: 62,
        bookName: '1 John',
        chapter: 4,
        verse: 8,
        endVerse: null,
      },
    });

    expect(normalizeBibleQuery('1 corintians 13:4')).toEqual({
      normalizedQuery: '1 Corinthians 13:4',
      directRef: {
        bookNumber: 46,
        bookName: '1 Corinthians',
        chapter: 13,
        verse: 4,
        endVerse: null,
      },
    });

    expect(normalizeBibleQuery('mathew 6:33 10 virtues')).toEqual({
      normalizedQuery: 'Matthew 6:33 ten virtues',
      directRef: {
        bookNumber: 40,
        bookName: 'Matthew',
        chapter: 6,
        verse: 33,
        endVerse: null,
      },
    });

    expect(normalizeBibleQuery('forgive 70 times 7')).toEqual({
      normalizedQuery: 'forgive seventy times seven',
      directRef: null,
    });
  });

  it('converts cardinal numbers accurately and leaves ordinals untouched', () => {
    expect(numberToWords(10)).toBe('ten');
    expect(numberToWords(40)).toBe('forty');
    expect(numberToWords(144000)).toBe('one hundred forty-four thousand');
    expect(normalizeBibleQuery('2nd time 30 pieces')).toEqual({
      normalizedQuery: '2nd time thirty pieces',
      directRef: null,
    });
  });

  it('matches minor single-character typos on longer words cleanly', () => {
    expect(fuzzyWordMatch('lepors', 'ten men who were lepers met him')).toBe(true);
    expect(fuzzyWordMatch('lepers', 'healed the blind')).toBe(false);
    expect(fuzzyWordMatch('cry', 'jesus wept')).toBe(false);
  });
});
