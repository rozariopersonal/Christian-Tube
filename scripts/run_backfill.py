"""Fast backfill runner — no sample output, just writes metadata."""
import json
import re
import time
import sys

import psycopg2
from psycopg2.extras import RealDictCursor, execute_values

DATABASE_URL = "postgresql://neondb_owner:npg_3OxmCSbQnf2U@ep-flat-frog-a5j1ayb0.us-east-2.aws.neon.tech/neondb?sslmode=require"

KNOWN_SPEAKERS = [
    'Zac Poonen', 'Ian Poonen', 'Santosh Poonen', 'Sandeep Poonen',
    'Bobby Babu', 'George Mathew', 'Suresh Babu', 'Thomas Abraham',
    'Biju Chacko', 'Sunny Varghese', 'K.O. John', 'Vinod Babu',
    'John Thomas', 'Zac Cherian', 'S. Johnson', 'Philip Eapen',
    'Anand Dawson', 'Sam Abraham', 'Prabhudas', 'Finny', 'Enoch',
    'Benny', 'Shibu', 'Elias', 'Jagan', 'Sasi', 'Clement', 'Stephen',
    'Daniel', 'Prathap', 'Rajesh', 'Saju', 'Sunil', 'Paul',
    'Naveen', 'Robin', 'Solomon', 'Wilson', 'Philip', 'Jacob',
    'Benjamin', 'Joseph', 'Vivek', 'Eric', 'David', 'Joshua', 'Mathew',
    'Prem', 'Vimal', 'G.V.',
]

BIBLE_BOOKS = {
    'genesis': 'GEN', 'gen': 'GEN', 'exodus': 'EXO', 'exo': 'EXO',
    'leviticus': 'LEV', 'lev': 'LEV', 'numbers': 'NUM', 'num': 'NUM',
    'deuteronomy': 'DEU', 'deut': 'DEU', 'joshua': 'JOS', 'josh': 'JOS',
    'judges': 'JDG', 'ruth': 'RUT', 'rut': 'RUT',
    '1 samuel': '1SA', '1samuel': '1SA', '1 sam': '1SA', '1sam': '1SA', '1sa': '1SA',
    '2 samuel': '2SA', '2samuel': '2SA', '2 sam': '2SA', '2sam': '2SA', '2sa': '2SA',
    '1 kings': '1KI', '1kings': '1KI', '1kgs': '1KI', '1ki': '1KI',
    '2 kings': '2KI', '2kings': '2KI', '2kgs': '2KI', '2ki': '2KI',
    '1 chronicles': '1CH', '1chronicles': '1CH', '1 chr': '1CH', '1chr': '1CH', '1ch': '1CH',
    '2 chronicles': '2CH', '2chronicles': '2CH', '2 chr': '2CH', '2chr': '2CH', '2ch': '2CH',
    'ezra': 'EZR', 'nehemiah': 'NEH', 'neh': 'NEH', 'esther': 'EST', 'est': 'EST',
    'job': 'JOB', 'psalms': 'PSA', 'psalm': 'PSA', 'psa': 'PSA', 'ps': 'PSA',
    'proverbs': 'PRO', 'prov': 'PRO', 'pro': 'PRO',
    'ecclesiastes': 'ECC', 'eccl': 'ECC', 'ecc': 'ECC',
    'song of solomon': 'SNG', 'song of songs': 'SNG', 'song': 'SNG', 'sng': 'SNG',
    'isaiah': 'ISA', 'isa': 'ISA', 'jeremiah': 'JER', 'jer': 'JER',
    'lamentations': 'LAM', 'lam': 'LAM', 'ezekiel': 'EZK', 'ezek': 'EZK', 'ezk': 'EZK',
    'daniel': 'DAN', 'dan': 'DAN', 'hosea': 'HOS', 'hos': 'HOS',
    'joel': 'JOL', 'jol': 'JOL', 'amos': 'AMO', 'amo': 'AMO', 'am': 'AMO',
    'obadiah': 'OBA', 'oba': 'OBA', 'jonah': 'JON', 'jon': 'JON',
    'micah': 'MIC', 'mic': 'MIC', 'nahum': 'NAM', 'nah': 'NAM', 'nam': 'NAM',
    'habakkuk': 'HAB', 'hab': 'HAB', 'zephaniah': 'ZEP', 'zeph': 'ZEP', 'zep': 'ZEP',
    'haggai': 'HAG', 'hag': 'HAG', 'zechariah': 'ZEC', 'zech': 'ZEC', 'zec': 'ZEC',
    'malachi': 'MAL', 'mal': 'MAL',
    'matthew': 'MAT', 'matt': 'MAT', 'mat': 'MAT', 'mt': 'MAT',
    'mark': 'MRK', 'mrk': 'MRK', 'mk': 'MRK',
    'luke': 'LUK', 'luk': 'LUK', 'lk': 'LUK',
    'john': 'JHN', 'jhn': 'JHN', 'jn': 'JHN',
    'acts': 'ACT', 'act': 'ACT', 'ac': 'ACT',
    'romans': 'ROM', 'rom': 'ROM', 'ro': 'ROM', 'rm': 'ROM',
    '1 corinthians': '1CO', '1corinthians': '1CO', '1 cor': '1CO', '1cor': '1CO', '1co': '1CO',
    '2 corinthians': '2CO', '2corinthians': '2CO', '2 cor': '2CO', '2cor': '2CO', '2co': '2CO',
    'galatians': 'GAL', 'gal': 'GAL', 'ephesians': 'EPH', 'eph': 'EPH',
    'philippians': 'PHP', 'phil': 'PHP', 'php': 'PHP',
    'colossians': 'COL', 'col': 'COL',
    '1 thessalonians': '1TH', '1thessalonians': '1TH', '1 thess': '1TH', '1th': '1TH',
    '2 thessalonians': '2TH', '2thessalonians': '2TH', '2 thess': '2TH', '2th': '2TH',
    '1 timothy': '1TI', '1timothy': '1TI', '1 tim': '1TI', '1ti': '1TI',
    '2 timothy': '2TI', '2timothy': '2TI', '2 tim': '2TI', '2ti': '2TI',
    'titus': 'TIT', 'tit': 'TIT', 'philemon': 'PHM', 'phm': 'PHM',
    'hebrews': 'HEB', 'heb': 'HEB',
    'james': 'JAS', 'jas': 'JAS', 'jam': 'JAS',
    '1 peter': '1PE', '1peter': '1PE', '1 pet': '1PE', '1pe': '1PE', '1pt': '1PE',
    '2 peter': '2PE', '2peter': '2PE', '2 pet': '2PE', '2pe': '2PE', '2pt': '2PE',
    '1 john': '1JN', '1john': '1JN', '1 jn': '1JN', '1jn': '1JN',
    '2 john': '2JN', '2john': '2JN', '2 jn': '2JN', '2jn': '2JN',
    '3 john': '3JN', '3john': '3JN', '3 jn': '3JN', '3jn': '3JN',
    'jude': 'JUD', 'jud': 'JUD',
    'revelation': 'REV', 'rev': 'REV', 'revelations': 'REV',
}

KNOWN_SERIES = [
    'Through The Bible', 'All That Jesus Taught', 'Sermon on the Mount',
    'The New Covenant', 'Basic Christian Truths', 'Secret of Godliness',
    'Living as Jesus Lived', 'A Heavenly Way of Life', 'Church Truths',
    'Spiritual Leadership', 'Full Gospel', 'Building the Body of Christ',
    'Discipleship', 'Romans Study', 'Hebrews Study', 'Revelation Study',
    'The Beatitudes', 'The Tabernacle',
]

MEETING_TYPES = [
    ('Sunday Service',     re.compile(r'\b(sunday\s*(service|morning|meeting)?|lord\'?s\s*day)\b', re.I)),
    ('Midweek Meeting',    re.compile(r'\b(mid[- ]?week|wednesday|bible\s*study)\b', re.I)),
    ('Youth Camp',         re.compile(r'\b(youth\s*(camp|conference|meeting|retreat)?|teens|young\s*people)\b', re.I)),
    ('Annual Conference',  re.compile(r'\b(annual\s*conference|conference\s*\d{4}|conference)\b', re.I)),
    ('Workers Conference', re.compile(r'\b(workers?\s*conference|elders?\s*meeting|leaders?\s*meeting)\b', re.I)),
    ('Brothers Meeting',   re.compile(r'\b(brothers?\s*meeting|men\'?s\s*meeting)\b', re.I)),
    ('Sisters Meeting',    re.compile(r'\b(sisters?\s*meeting|women\'?s\s*meeting)\b', re.I)),
    ('Prayer Meeting',     re.compile(r'\b(prayer\s*meeting|all\s*night\s*prayer|fasting\s*prayer)\b', re.I)),
    ('Communion',          re.compile(r'\b(communion|lord\'?s\s*table|breaking\s*of\s*bread)\b', re.I)),
]

LOCATIONS = [
    'Chennai', 'Bangalore', 'Coimbatore', 'Loveland', 'London', 'Dubai',
    'Singapore', 'Mumbai', 'Delhi', 'Hyderabad', 'Pune', 'Kottayam',
    'Trivandrum', 'Kochi', 'Salem', 'Madurai', 'Trichy', 'Vellore',
    'Tirunelveli', 'Sydney', 'Chicago', 'San Jose', 'Dallas', 'Houston', 'Toronto',
]

TARGET_AUDIENCES = [
    ('Youth',                      re.compile(r'\b(youth|young\s*people|teens|teenagers|campus)\b', re.I)),
    ('Married Couples / Families', re.compile(r'\b(couples|marriage|husband|wife|parents|parenting|family)\b', re.I)),
    ('Elders / Leaders',           re.compile(r'\b(elders?|leaders?|workers?|servants?|ministers?)\b', re.I)),
    ('Sisters',                    re.compile(r'\b(sisters?|women|mothers?)\b', re.I)),
    ('Children',                   re.compile(r'\b(children|sunday\s*school|kids)\b', re.I)),
]

TOPIC_KEYWORDS = [
    ('Holiness',             re.compile(r'\b(holiness|holy|pure|purity|victory over sin|overcoming sin|temptation|sinless)\b', re.I)),
    ('The Cross',            re.compile(r'\b(the cross|crucified|deny self|self denial|dying to self|take up cross)\b', re.I)),
    ('Holy Spirit',          re.compile(r'\b(holy spirit|baptism in the spirit|fullness of the spirit|spiritual gifts|tongues)\b', re.I)),
    ('Discipleship',         re.compile(r'\b(disciple|discipleship|follow jesus|obedience|obey|surrender)\b', re.I)),
    ('New Covenant',         re.compile(r'\b(new covenant|law and grace|old covenant|body of christ|covenant life)\b', re.I)),
    ('Humility',             re.compile(r'\b(humility|humble|pride|proud|brokenness|contrite)\b', re.I)),
    ('Prayer & Fasting',     re.compile(r'\b(prayer|praying|intercession|fasting|supplication)\b', re.I)),
    ('Faith',                re.compile(r'\b(faith|trusting god|belief|unbelief|doubt)\b', re.I)),
    ('Love & Forgiveness',   re.compile(r'\b(love|forgive|forgiveness|bitterness|grudge|reconciliation|unity)\b', re.I)),
    ('Family & Marriage',    re.compile(r'\b(marriage|husband|wife|parenting|children|family|home)\b', re.I)),
    ('Spiritual Warfare',    re.compile(r'\b(spiritual warfare|satan|devil|demons?|armor of god|resist the devil)\b', re.I)),
    ('Church & Fellowship',  re.compile(r'\b(church|fellowship|body of christ|assembly|eldership|local church)\b', re.I)),
    ('Finances & Money',     re.compile(r'\b(money|mammon|finances|financial|giving|tithe|greed|wealth)\b', re.I)),
    ('Suffering & Trials',   re.compile(r'\b(suffering|trials?|tribulation|persecution|affliction|hardship)\b', re.I)),
    ('End Times & Prophecy', re.compile(r'\b(end times|second coming|antichrist|prophecy|rapture|revelation)\b', re.I)),
    ('Grace',                re.compile(r'\b(grace|mercy|justification|righteousness of god|condemnation)\b', re.I)),
    ('Evangelism & Witness', re.compile(r'\b(evangelism|gospel|witnessing|soul winning|testimony)\b', re.I)),
    ('Praise & Worship',     re.compile(r'\b(praise|worship|thanksgiving|glorify god)\b', re.I)),
]

TAMIL_RE   = re.compile(r'[\u0B80-\u0BFF]')
TELUGU_RE  = re.compile(r'[\u0C00-\u0C7F]')
MALAY_RE   = re.compile(r'[\u0D00-\u0D7F]')
HINDI_RE   = re.compile(r'[\u0900-\u097F]')
KANNADA_RE = re.compile(r'[\u0C80-\u0CFF]')
LATIN_RE   = re.compile(r'[a-zA-Z]{4,}')
SCRIP_RE   = re.compile(r'\b((?:[1-3]\s*)?[A-Za-z]+)\s*(\d{1,3})(?::(\d{1,3}))?\b')
TIME_RE    = re.compile(r'(?:(\d{1,2}):)?(\d{2}):(\d{2})')


def roman_to_decimal(s):
    vals = {'I': 1, 'V': 5, 'X': 10, 'L': 50, 'C': 100, 'D': 500, 'M': 1000}
    s = s.upper()
    result = 0
    for i, c in enumerate(s):
        cur = vals.get(c, 0)
        nxt = vals.get(s[i + 1], 0) if i + 1 < len(s) else 0
        result += -cur if cur < nxt else cur
    return result if result > 0 else 0


def extract(title, description, channel_title, tags):
    combined = f"{title}\n{description}\n{channel_title}\n{' '.join(tags or [])}"
    desc_s = (description or '')[:500]

    speaker = None
    for name in KNOWN_SPEAKERS:
        pat = re.compile(r'\b(?:Bro(?:ther)?\.?\s*)?' + re.escape(name) + r'\b', re.I)
        if pat.search(title):
            speaker = name
            break
    if not speaker:
        for pat_str in [
            r'\b(?:Bro(?:ther)?\.?\s+)([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)\b',
            r'\b(?:Speaker|By):\s*([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)\b',
            r'[-|]\s*(?:Bro(?:ther)?\.?\s*)?([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)\s*$',
        ]:
            m = re.search(pat_str, title)
            if m:
                cand = m.group(1).strip()
                if cand not in ('Sunday', 'Midweek', 'Youth', 'CFC', 'Service', 'English', 'Tamil', 'Part'):
                    speaker = cand
                    break

    language = 'English'
    secondary_language = None
    bm = re.search(r'\[([A-Za-z]+)\s*[-&/]\s*([A-Za-z]+)\]', title, re.I)
    if bm:
        language = bm.group(1).strip()
        secondary_language = bm.group(2).strip()
    elif TAMIL_RE.search(combined) or re.search(r'\btamil\b', combined, re.I):
        language = 'Tamil'
        if LATIN_RE.search(title): secondary_language = 'English'
    elif TELUGU_RE.search(combined) or re.search(r'\btelugu\b', combined, re.I):
        language = 'Telugu'
        if LATIN_RE.search(title): secondary_language = 'English'
    elif MALAY_RE.search(combined) or re.search(r'\bmalayalam\b', combined, re.I):
        language = 'Malayalam'
        if LATIN_RE.search(title): secondary_language = 'English'
    elif HINDI_RE.search(combined) or re.search(r'\bhindi\b', combined, re.I):
        language = 'Hindi'
        if LATIN_RE.search(title): secondary_language = 'English'
    elif KANNADA_RE.search(combined) or re.search(r'\bkannada\b', combined, re.I):
        language = 'Kannada'
        if LATIN_RE.search(title): secondary_language = 'English'
    elif any(x in (channel_title or '').lower() for x in ['tamil', 'chennai', 'coimbatore']):
        language = 'Tamil'
        secondary_language = 'English'

    sub_series = None
    for s in KNOWN_SERIES:
        if re.search(r'\b' + re.escape(s) + r'\b', title, re.I) or \
           re.search(r'\b' + re.escape(s) + r'\b', desc_s, re.I):
            sub_series = s
            break

    part_number = None
    pm = re.search(r'\b(?:part|pt|episode|vol|lesson|#)\.?\s*([0-9]+|[ivxlcdm]+)\b', title, re.I)
    if pm:
        raw = pm.group(1)
        if raw.isdigit():
            part_number = int(raw)
        elif re.match(r'^[ivxlcdm]+$', raw, re.I):
            part_number = roman_to_decimal(raw)

    meeting_type = 'General Sermons'
    for mt_name, mt_pat in MEETING_TYPES:
        if mt_pat.search(title) or mt_pat.search(desc_s):
            meeting_type = mt_name
            break

    location = None
    for loc in LOCATIONS:
        if re.search(r'\b' + re.escape(loc) + r'\b', title, re.I) or \
           re.search(r'\b' + re.escape(loc) + r'\b', channel_title or '', re.I) or \
           re.search(r'\b' + re.escape(loc) + r'\b', desc_s, re.I):
            location = loc
            break

    target_audience = 'General'
    for ta_name, ta_pat in TARGET_AUDIENCES:
        if ta_pat.search(title) or ta_pat.search(desc_s):
            target_audience = ta_name
            break

    topics = []
    for t_name, t_pat in TOPIC_KEYWORDS:
        if t_pat.search(title) or t_pat.search(desc_s):
            topics.append(t_name)
            if len(topics) >= 4:
                break

    scripture = None
    for text in [title, desc_s]:
        for m in SCRIP_RE.finditer(text or ''):
            book_code = BIBLE_BOOKS.get(m.group(1).lower().strip())
            if book_code:
                scripture = {'book': book_code, 'chapter': int(m.group(2))}
                if m.group(3): scripture['verse'] = int(m.group(3))
                break
        if scripture: break

    chapters = []
    if description:
        for line in description.split('\n'):
            m = TIME_RE.search(line)
            if m:
                full_ts = m.group(0)
                h = int(m.group(1) or 0)
                total_s = h * 3600 + int(m.group(2)) * 60 + int(m.group(3))
                ch_title = line.replace(full_ts, '').strip().lstrip('-|: ').rstrip('-|: ').strip()
                if len(ch_title) > 2:
                    chapters.append({'title': ch_title, 'seconds': total_s, 'timestamp': full_ts})

    clean = title
    clean = re.sub(r'\[.*?\]', '', clean)
    def keep_parens(m):
        inner = m.group(0)
        return inner if re.search(r'\b(?:Part|Pt|\d+)\b', inner, re.I) else ''
    clean = re.sub(r'\(.*?\)', keep_parens, clean)
    clean = re.sub(r'#\S+', '', clean)
    clean = re.sub(r'\|\s*CFC\s*[^|]*', '', clean, flags=re.I)
    clean = re.sub(r'\|\s*Christian Fellowship Church[^|]*', '', clean, flags=re.I)
    clean = re.sub(r'\|\s*Bro\.?\s*[^|]*', '', clean, flags=re.I)
    clean = re.sub(r'[-|]\s*Bro\.?\s*.*$', '', clean, flags=re.I)
    clean = re.sub(r'\s+', ' ', clean).strip().lstrip('-|:/. ').rstrip('-|:/. ').strip()
    if not clean: clean = title

    result = {'speaker': speaker, 'language': language, 'cleanTitle': clean,
               'meetingType': meeting_type, 'targetAudience': target_audience}
    if secondary_language: result['secondaryLanguage'] = secondary_language
    if sub_series: result['subSeries'] = sub_series
    if part_number: result['partNumber'] = part_number
    if location: result['location'] = location
    if topics: result['topics'] = topics
    if scripture: result['scripture'] = scripture
    if chapters: result['chapters'] = chapters[:30]
    return result


def main():
    max_batches = None
    for a in sys.argv[1:]:
        if a.startswith('--max-batches='):
            max_batches = int(a.split('=')[1])

    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor(cursor_factory=RealDictCursor)

    cur.execute('SELECT COUNT(*) as c FROM "Video" WHERE metadata IS NULL;')
    total_null = cur.fetchone()['c']
    print(f"Videos to process: {total_null}")

    batch, updated = 0, 0
    batch_size = 300
    last_id = ''  # cursor-based pagination using id

    while True:
        if max_batches and batch >= max_batches:
            print(f"Max batches reached ({max_batches})")
            break

        # Fetch next page using keyset cursor (always id > last_id, no OFFSET)
        cur.execute(
            'SELECT id, title, description, "channelName", tags FROM "Video" '
            'WHERE metadata IS NULL AND id > %s ORDER BY id LIMIT %s',
            (last_id, batch_size)
        )
        rows = cur.fetchall()
        if not rows:
            print("All done!")
            break

        batch += 1
        update_tuples = []
        for row in rows:
            try:
                meta = extract(row['title'] or '', row['description'] or '',
                               row['channelName'] or '', row['tags'] or [])
                update_tuples.append((row['id'], json.dumps(meta, ensure_ascii=False)))
            except Exception as e:
                print(f"Extract error {row['id']}: {e}")

        if update_tuples:
            execute_values(
                cur,
                """
                UPDATE "Video" AS v
                SET metadata = val.meta::jsonb
                FROM (VALUES %s) AS val(id, meta)
                WHERE v.id = val.id
                """,
                update_tuples
            )
            updated += len(update_tuples)

        # Advance cursor to the last id in this batch
        last_id = rows[-1]['id']
        conn.commit()
        print(f"Batch {batch}: +{len(update_tuples)} rows | total_updated={updated} | cursor={last_id[:12]}...")
        sys.stdout.flush()

    print(f"\n=== DONE: {updated} records updated ===")
    cur.close()
    conn.close()

if __name__ == '__main__':
    main()
