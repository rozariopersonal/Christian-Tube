/// Bidirectional mapping between canonical Bible book numbers (1-66) and the
/// 3-letter abbreviations used by public Bible datasets (e.g. HelloAO's
/// `open-cross-ref`, OpenBible.info).
///
/// This is a pure data table — no logic, no dependencies — so it can be used
/// anywhere without importing IO or Flutter-specific services.
class BookAbbreviation {
  BookAbbreviation._();

  /// Subset of HelloAO / OpenBible.info abbreviations.
  static const Map<int, String> _abbrevByNumber = {
    1: 'GEN',
    2: 'EXO',
    3: 'LEV',
    4: 'NUM',
    5: 'DEU',
    6: 'JOS',
    7: 'JDG',
    8: 'RUT',
    9: '1SA',
    10: '2SA',
    11: '1KI',
    12: '2KI',
    13: '1CH',
    14: '2CH',
    15: 'EZR',
    16: 'NEH',
    17: 'EST',
    18: 'JOB',
    19: 'PSA',
    20: 'PRO',
    21: 'ECC',
    22: 'SNG',
    23: 'ISA',
    24: 'JER',
    25: 'LAM',
    26: 'EZK',
    27: 'DAN',
    28: 'HOS',
    29: 'JOL',
    30: 'AMO',
    31: 'OBA',
    32: 'JON',
    33: 'MIC',
    34: 'NAM',
    35: 'HAB',
    36: 'ZEP',
    37: 'HAG',
    38: 'ZEC',
    39: 'MAL',
    40: 'MAT',
    41: 'MRK',
    42: 'LUK',
    43: 'JHN',
    44: 'ACT',
    45: 'ROM',
    46: '1CO',
    47: '2CO',
    48: 'GAL',
    49: 'EPH',
    50: 'PHP',
    51: 'COL',
    52: '1TH',
    53: '2TH',
    54: '1TI',
    55: '2TI',
    56: 'TIT',
    57: 'PHM',
    58: 'HEB',
    59: 'JAS',
    60: '1PE',
    61: '2PE',
    62: '1JN',
    63: '2JN',
    64: '3JN',
    65: 'JUD',
    66: 'REV',
  };

  static const Map<String, int> _numberByAbbrev = {
    'GEN': 1, 'EXO': 2, 'LEV': 3, 'NUM': 4, 'DEU': 5, 'JOS': 6, 'JDG': 7,
    'RUT': 8, '1SA': 9, '2SA': 10, '1KI': 11, '2KI': 12, '1CH': 13,
    '2CH': 14, 'EZR': 15, 'NEH': 16, 'EST': 17, 'JOB': 18, 'PSA': 19,
    'PRO': 20, 'ECC': 21, 'SNG': 22, 'ISA': 23, 'JER': 24, 'LAM': 25,
    'EZK': 26, 'DAN': 27, 'HOS': 28, 'JOL': 29, 'AMO': 30, 'OBA': 31,
    'JON': 32, 'MIC': 33, 'NAM': 34, 'HAB': 35, 'ZEP': 36, 'HAG': 37,
    'ZEC': 38, 'MAL': 39, 'MAT': 40, 'MRK': 41, 'LUK': 42, 'JHN': 43,
    'ACT': 44, 'ROM': 45, '1CO': 46, '2CO': 47, 'GAL': 48, 'EPH': 49,
    'PHP': 50, 'COL': 51, '1TH': 52, '2TH': 53, '1TI': 54, '2TI': 55,
    'TIT': 56, 'PHM': 57, 'HEB': 58, 'JAS': 59, '1PE': 60, '2PE': 61,
    '1JN': 62, '2JN': 63, '3JN': 64, 'JUD': 65, 'REV': 66,
  };

  /// Returns the 3-letter abbreviation for [bookNumber] (1-66), or null if the
  /// number is out of range.
  static String? abbreviationFor(int bookNumber) =>
      _abbrevByNumber[bookNumber];

  /// Returns the canonical book number (1-66) for [abbreviation], or null if
  /// the abbreviation is unknown. Case-insensitive.
  static int? bookNumberFor(String abbreviation) =>
      _numberByAbbrev[abbreviation.toUpperCase()];

  /// Returns true if [bookNumber] is a valid canonical book number.
  static bool isValidBookNumber(int bookNumber) =>
      _abbrevByNumber.containsKey(bookNumber);
}
