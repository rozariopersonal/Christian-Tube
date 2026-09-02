import json
import sqlite3
import gzip
import os
import re

PT_DB = 'data/dictionaries_raw/PTTamil.db'
KAIKKI_GZ = 'data/dictionaries_raw/kaikki_tamil.jsonl.gz'
TAMIL_JSON = 'data/dictionaries_raw/tamil.json'
OUT_SQLITE = 'data/dictionaries_published/dict_ta.sqlite'
OUT_GZ = 'data/dictionaries_published/dict_ta.sqlite.gz'

if os.path.exists(OUT_SQLITE):
    os.remove(OUT_SQLITE)

conn = sqlite3.connect(OUT_SQLITE)
c = conn.cursor()

c.execute('''
CREATE TABLE dictionary_entries (
  headword TEXT NOT NULL COLLATE NOCASE,
  part_of_speech TEXT,
  phonetic TEXT,
  definition TEXT NOT NULL,
  examples TEXT,
  PRIMARY KEY (headword, part_of_speech)
)
''')
c.execute('CREATE INDEX idx_dict_headword ON dictionary_entries (headword);')

entries_map = {} # headword -> {pos, phonetic, definitions: [], examples: []}

def add_entry(hw, pos, pho, defn, ex=''):
    hw = hw.strip()
    if not hw or len(hw) < 1:
        return
    defn = defn.strip()
    if not defn:
        return
    key = (hw.lower(), pos.lower())
    if key not in entries_map:
        entries_map[key] = {
            'headword': hw,
            'pos': pos,
            'pho': pho,
            'definitions': [],
            'examples': []
        }
    if defn not in entries_map[key]['definitions']:
        entries_map[key]['definitions'].append(defn)
    if ex and ex not in entries_map[key]['examples']:
        entries_map[key]['examples'].append(ex)

# 1. Kaikki Modern Wiktionary Tamil Data
if os.path.exists(KAIKKI_GZ):
    print('Loading Kaikki Tamil dataset...')
    with gzip.open(KAIKKI_GZ, 'rt', encoding='utf-8') as f:
        for line in f:
            try:
                d = json.loads(line)
                word = d.get('word', '').strip()
                pos = d.get('pos', '')
                senses = d.get('senses', [])
                all_glosses = []
                all_examples = []
                for s in senses:
                    for g in s.get('glosses', []):
                        if g and g not in all_glosses:
                            all_glosses.append(g)
                    for e in s.get('examples', []):
                        ex_text = e.get('text', '') if isinstance(e, dict) else str(e)
                        if ex_text and ex_text not in all_examples:
                            all_examples.append(ex_text)
                if all_glosses:
                    def_str = ' • ' + '\n • '.join(all_glosses)
                    ex_str = '\n'.join(all_examples[:2])
                    add_entry(word, pos, '', def_str, ex_str)
            except Exception:
                continue
    print(f'Entries after Kaikki: {len(entries_map)}')

# 2. PTTamil.db (63k Tamil-to-Tamil literary definitions)
if os.path.exists(PT_DB):
    print('Loading PTTamil dataset...')
    pt_conn = sqlite3.connect(PT_DB)
    pt_cur = pt_conn.cursor()
    pt_cur.execute('SELECT word, meanings FROM dictionary')
    for row in pt_cur.fetchall():
        w = row[0].strip()
        m = row[1].strip()
        add_entry(w, 'பெயர்ச்சொல்', '', m)
    pt_conn.close()
    print(f'Entries after PTTamil: {len(entries_map)}')

# 2b. Tamil Wiktionary TSV (84k inflected wordforms and definitions)
TA_TSV = 'data/dictionaries_raw/tamil_english_wiktionary.tsv'
if os.path.exists(TA_TSV):
    print('Loading Tamil TSV Wiktionary dataset (inflected forms)...')
    with open(TA_TSV, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split('\t')
            if len(parts) >= 2:
                headwords_part = parts[0]
                html_def = parts[1]
                pos_match = re.search(r'<i>([a-zA-Z]+)</i>', html_def)
                pos = pos_match.group(1) if pos_match else 'சொல்'
                clean_def = re.sub(r'<br\s*/?>', '\n', html_def)
                clean_def = re.sub(r'</li>\s*<li>', '\n • ', clean_def)
                clean_def = re.sub(r'<li>', '• ', clean_def)
                clean_def = re.sub(r'</?[^>]+(>|$)', '', clean_def).strip()
                hws = headwords_part.split('|')
                for hw in hws:
                    hw_trim = hw.strip()
                    if hw_trim and not re.match(r'^[a-zA-Z]+$', hw_trim):
                        add_entry(hw_trim, pos, '', clean_def)
    print(f'Entries after Wiktionary TSV: {len(entries_map)}')

# 3. Core Bible Terms
BIBLE_TAMIL_TERMS = [
    ['கர்த்தர்', 'பெயர்ச்சொல்', '', 'ஆண்டவர்; யெகோவா (YHWH); இயேசு கிறிஸ்து; சர்வலோகத்தையும் படைத்துக் காக்கும் ஏக இறைவன்.', ''],
    ['பிதா', 'பெயர்ச்சொல்', '', 'தந்தை; பரமபிதா; திரித்துவத்தின் முதல் ஆள் தத்துவம்; பரலோகத்தில் இருக்கிற நம்முடைய பிதா.', ''],
    ['குமாரன்', 'பெயர்ச்சொல்', '', 'மகன்; தேவகுமாரன்; இயேசு கிறிஸ்து; உலக இரட்சகர்.', ''],
    ['பரிசுத்த ஆவி', 'பெயர்ச்சொல்', '', 'தேற்றரவாளர்; பரிசுத்த ஆவியானவர்; சத்திய ஆவி; விசுவாசிகளுக்குள் வாசம்பண்ணி வழிநடத்தும் தேவ ஆவி.', ''],
    ['இரட்சிப்பு', 'பெயர்ச்சொல்', '', 'மீட்பு; பாவத்திலிருந்தும் அதன் தண்டனையிலிருந்தும் இயேசு கிறிஸ்துவின் மூலமாகப் பெறும் விடுதலை மற்றும் நித்திய ஜீவன்.', ''],
    ['கிருபை', 'பெயர்ச்சொல்', '', 'தேவனுடைய ஈவு; தகுதியற்ற மனிதனுக்கு தேவன் இயேசு கிறிஸ்துவின் மூலம் இலவசமாக அருளும் இரக்கமும் பேரன்பும்.', ''],
    ['விசுவாசம்', 'பெயர்ச்சொல்', '', 'நம்பிக்கை; தேவனுடைய வார்த்தையை முழுமையாக நம்பி கீழ்ப்படிதல்; காணப்படாதவைகளை நிச்சயிக்கும் உறுதி.', ''],
    ['நீதி', 'பெயர்ச்சொல்', '', 'நியாயம்; தேவனுடைய பரிசுத்த கட்டளைகளுக்கு ஏற்ப வாழ்தல்; விசுவாசத்தினாலே விளங்கும் தேவநீதி.', ''],
    ['பரிசுத்தம்', 'பெயர்ச்சொல்', '', 'பாவமற்ற தன்மை; தேவனுக்கென்று அர்ப்பணிக்கப்பட்ட தூய்மையான நிலை; பிரித்தெடுக்கப்படுதல்.', ''],
    ['ஜெபம்', 'பெயர்ச்சொல்', '', 'பிரார்த்தனை; மனிதன் தேவனுடன் வைக்கும் ஆவிக்குரிய உரையாடல், விண்ணப்பம், துதி, நன்றி செலுத்துதல்.', ''],
    ['சுவிசேஷம்', 'பெயர்ச்சொல்', '', 'நற்செய்தி; இயேசு கிறிஸ்துவின் பிறப்பு, மரணம், உயிர்த்தெழுதல் மூலமாக மனுக்குலத்திற்கு கிடைத்த மீட்பின் நற்செய்தி.', ''],
    ['ஞானஸ்நானம்', 'பெயர்ச்சொல்', '', 'திருமுழுக்கு; இயேசு கிறிஸ்துவை ஏற்றுக்கொண்டதன் அடையாளமாக ஜலத்தினால் செய்யப்படும் ஆவிக்குரிய முழுக்கு/அபிஷேகம்.', ''],
    ['மனுஷன்', 'பெயர்ச்சொல்', '', 'மனிதன்; தேவனுடைய சாயலாகப் படைக்கப்பட்ட ஆண்/பெண்.', ''],
    ['சாத்தான்', 'பெயர்ச்சொல்', '', 'பிசாசு; தேவனுக்கும் அவருடைய மக்களுக்கும் எதிரான எதிராளி; விழுந்துபோன தூதன்.', ''],
    ['தூதன்', 'பெயர்ச்சொல்', '', 'தேவதூதன்; தேவனுடைய செய்தியை அறிவிக்கும் பரலோக ஊழியக்காரன்/ஆவி.', ''],
    ['ஆசீர்வாதம்', 'பெயர்ச்சொல்', '', 'தேவனுடைய நன்மை, சுகம், சமாதானம் மற்றும் செழுமையின் அருட்கொடை.', ''],
    ['பாவம்', 'பெயர்ச்சொல்', '', 'தேவனுடைய கட்டளையை மீறுதல்; அநீதி; தேவனுக்கு விரோதமாகச் செய்யப்படும் தவறு.', ''],
    ['மன்னிப்பு', 'பெயர்ச்சொல்', '', 'குற்றங்களை நினைவுகூராமல் கிருபையாக நீக்கிவிடுதல்; தேவ சமாதானம் அளித்தல்.', ''],
    ['நித்திய ஜீவன்', 'பெயர்ச்சொல்', '', 'தேவனோடு பரலோகத்தில் என்றென்றைக்கும் வாழும் முடிவில்லாத ஆவிக்குரிய நித்திய வாழ்வு.', ''],
    ['பரலோகம்', 'பெயர்ச்சொல்', '', 'தேவனுடைய சிங்காசனம் அமைந்துள்ள பரம வீடு; விசுவாசிகள் அடையும் நித்திய இளைப்பாறுதல் ஸ்தலம்.', ''],
    ['நரகம்', 'பெயர்ச்சொல்', '', 'அக்கினி கடல்; பாவிகளுக்கும் சாத்தானுக்கும் நியமிக்கப்பட்ட நித்திய ஆக்கினை ஸ்தலம்.', ''],
    ['ஆலயம்', 'பெயர்ச்சொல்', '', 'தேவனுடைய வாசஸ்தலம்; ஜெபவீடு; ஆராதனை ஸ்தலம்.', ''],
    ['ஆசாரியன்', 'பெயர்ச்சொல்', '', 'மக்களுக்காக தேவனிடத்தில் பரிந்துபேசி பலியிடும் இறை ஊழியன்; பிரதான ஆசாரியர்.', ''],
    ['தீர்க்கதரிசி', 'பெயர்ச்சொல்', '', 'தேவனுடைய வார்த்தையையும் எதிர்கால நிகழ்வுகளையும் வெளிப்படுத்தும் இறைவாக்கினர்.', ''],
    ['அப்போஸ்தலர்', 'பெயர்ச்சொல்', '', 'அனுப்பப்பட்டவர்; இயேசு கிறிஸ்துவினால் தெரிந்துகொள்ளப்பட்டு அனுப்பப்பட்ட பன்னிரு சீடர்கள்.', ''],
    ['சீடர்', 'பெயர்ச்சொல்', '', 'இயேசுவைப் பின்பற்றி அவருடைய உபதேசங்களைக் கற்றுக்கொண்டு கீழ்ப்படிகிற விசுவாசி.', ''],
    ['உபவாசம்', 'பெயர்ச்சொல்', '', 'ஆவிக்குரிய வைராக்கியத்தோடு தேவனைத் தேட ஆகாரத்தை விட்டுவிட்டு ஜெபிக்கும் ஆவிக்குரிய ஒழுக்கம்.', ''],
    ['சீயோன்', 'பெயர்ச்சொல்', '', 'எருசலேமின் பர்வதம்; தேவனுடைய நகரம்; பரலோக எருசலேமின் அடையாளம்.', ''],
    ['பஸ்கா', 'பெயர்ச்சொல்', '', 'எகிப்தின் அடிமைத்தனத்திலிருந்து இஸ்ரவேலர் விடுதலையானதை நினைவுகூரும் பண்டிகை; நம்முடைய பஸ்காவாகிய கிறிஸ்து.', ''],
    ['மேசியா', 'பெயர்ச்சொல்', '', 'அபிஷேகம் பண்ணப்பட்டவர்; கிறிஸ்து; உலகத்தை மீட்க வந்த இரட்சகர்.', ''],
    ['மனுபுத்திரன்', 'பெயர்ச்சொல்', '', 'இயேசு தம்மைத்தாமே அழைத்துக் கொண்ட நாமம்; மனுக்குலத்தின் பிரதிநிதியாகிய தேவன்.', ''],
    ['ஒரேபேறான', 'பெயர்ச்சொல்', '', 'ஒரே விசேஷித்த மைந்தன்; பிதாவினால் அருளப்பட்ட தனித்துவமான தேவகுமாரன் (Only begotten - Monogenēs).', ''],
    ['வார்த்தை', 'பெயர்ச்சொல்', '', 'லோகோஸ் (Logos); ஆதியிலே தேவனோடு இருந்து உலகைப் படைத்த தேவனுடைய நித்திய வார்த்தை; மாம்சமான கிறிஸ்து.', ''],
    ['மகிமை', 'பெயர்ச்சொல்', '', 'தேவனுடைய பிரசன்னம், வல்லமை, மேன்மை மற்றும் மாட்சிமையின் வெளிப்பாடு (Shekinah Glory).', ''],
    ['இருள்', 'பெயர்ச்சொல்', '', 'அந்தகாரம்; பாவம் மற்றும் சாத்தானின் ஆளுகைக்குட்பட்ட ஆவிக்குரிய குருட்டுத்தன்மை.', ''],
    ['ஜீவன்', 'பெயர்ச்சொல்', '', 'உயிர்; ஆவிக்குரிய மெய்வாழ்வு; கிறிஸ்துவை விசுவாசிப்பதால் கிடைக்கும் அழியாத நித்திய ஜீவன்.', ''],
    ['சாட்சி', 'பெயர்ச்சொல்', '', 'தேவனுடைய சத்தியத்தைக் கண்கூடாகக் கண்டு உறுதியாய் அறிக்கையிடும் சாட்சியம் அல்லது சாட்சி பகருபவர்.', ''],
    ['இவ்வளவாய்', 'இடைச்சொல்', '', 'இந்த அளவிற்கு; மிகுந்த விதமாய்; அதிகமாய் (So much / In such a great measure - John 3:16).', ''],
    ['இவ்வளவு', 'பெயர்ச்சொல்', '', 'இந்த அளவு; இந்த மாத்திரம்.', ''],
    ['அசைவாடுதல்', 'வினைச்சொல்', '', 'ஆவியானவர் உயிரூட்டும் வண்ணமாய் மென்மையாய் அசைந்து கொண்டிருத்தல் (Hovering, moving over waters - Gen 1:2).', ''],
    ['அசைவாடு', 'வினைச்சொல்', '', 'அசைதல்; இயங்குதல்.', ''],
    ['ஒழுங்கின்மை', 'பெயர்ச்சொல்', '', 'முறையற்ற நிலை; பாழான அல்லது வெறுமையான தன்மை (Without form, void - Gen 1:2).', ''],
    ['சிருஷ்டித்தார்', 'வினைச்சொல்', '', 'படைத்தார்; ஒன்றுமில்லாமையிலிருந்து எல்லாவற்றையும் உண்டாக்கினார் (Created - Gen 1:1).', ''],
    ['சிருஷ்டி', 'பெயர்ச்சொல்', '', 'படைப்பு; சிருஷ்டிக்கப்பட்ட பொருள்.', ''],
    ['வெவ்வேறாக', 'வினையெச்சம்', '', 'தனித்தனியாக; வேறாக; பிரித்து.', ''],
    ['வெவ்வேறு', 'பெயரடை', '', 'வேறுபட்ட; பல்வேறு; தனித்தனி.', ''],
    ['முதலாம்', 'எண்ணுப்பெயரடை', '', 'முதலாவது; ஆரம்பமான; முதல் வரிசையிலான (First).', ''],
    ['விடியற்காலம்', 'பெயர்ச்சொல்', '', 'அதிகாலை; விடியும் நேரம்; பிரடியற்காலம்.', ''],
    ['சாயங்காலம்', 'பெயர்ச்சொல்', '', 'மாலை நேரம்; அந்திப்பொழுது.', ''],
    ['அன்புகூர்ந்தார்', 'வினைச்சொல்', '', 'அன்பு செலுத்தினார்; பேரன்பு பாராட்டினார் (Loved - John 3:16).', ''],
    ['அன்புகூரு', 'வினைச்சொல்', '', 'அன்புசெய்; நேசி.', '']
]
for item in BIBLE_TAMIL_TERMS:
    add_entry(item[0], item[1], item[2], item[3], item[4])

# 4. tamil.json bidirectional indexing (both English headwords AND Tamil headwords)
if os.path.exists(TAMIL_JSON):
    print('Loading tamil.json and generating bidirectional headwords...')
    with open(TAMIL_JSON, 'r', encoding='utf-8') as f:
        ta_json = json.load(f)
    
    sw_to_eng = {}
    for entry in ta_json:
        eng = entry.get('eng', '').strip()
        tam = entry.get('tamil', '').strip()
        if not eng or not tam:
            continue
        # Forward: English headword -> Tamil definition
        add_entry(eng, '', '', tam)

        # Reverse: Collect English meanings for each Tamil word
        clean_tam = re.sub(r'^[a-z0-9\-]+\.\s*', '', tam)
        terms = re.split(r'[,;.]', clean_tam)
        for t in terms:
            t_clean = re.sub(r'^[^\u0B80-\u0BFF]+|[^\u0B80-\u0BFF]+$', '', t.strip())
            if len(t_clean) >= 2 and re.match(r'^[\u0B80-\u0BFF\s]+$', t_clean):
                subwords = [t_clean] if ' ' not in t_clean else [t_clean] + t_clean.split()
                for sw in subwords:
                    sw = sw.strip()
                    if len(sw) >= 2:
                        if sw not in sw_to_eng:
                            sw_to_eng[sw] = []
                        if eng not in sw_to_eng[sw] and len(sw_to_eng[sw]) < 6:
                            sw_to_eng[sw].append(eng)

    for sw, engs in sw_to_eng.items():
        add_entry(sw, 'பெயர்ச்சொல்', '', f'English: {", ".join(engs)}')

print(f'Total compiled entries to insert: {len(entries_map)}')

c.execute('BEGIN TRANSACTION;')
for key, data in entries_map.items():
    hw = data['headword']
    pos = data['pos']
    pho = data['pho']
    defn = '\n\n'.join(data['definitions'])
    ex = '\n'.join(data['examples'])
    c.execute('''
    INSERT OR REPLACE INTO dictionary_entries (headword, part_of_speech, phonetic, definition, examples)
    VALUES (?, ?, ?, ?, ?)
    ''', (hw, pos, pho, defn, ex))
conn.commit()
conn.close()

print('Database generated! Compressing to gzip...')
with open(OUT_SQLITE, 'rb') as f_in, gzip.open(OUT_GZ, 'wb', compresslevel=9) as f_out:
    f_out.write(f_in.read())

raw_mb = os.path.getsize(OUT_SQLITE) / (1024 * 1024)
gz_mb = os.path.getsize(OUT_GZ) / (1024 * 1024)
print(f'Successfully built {OUT_GZ}: {raw_mb:.1f} MB uncompressed, {gz_mb:.1f} MB gzipped!')
