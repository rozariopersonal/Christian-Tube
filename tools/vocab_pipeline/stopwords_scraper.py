#!/usr/bin/env python3
"""
stopwords_scraper.py

Scrapes and extracts common classical Tamil functional words, pronouns, particles,
and reporting auxiliaries from the TAOVBSI Bible text (or a frequency analysis)
that DO NOT need dictionary definitions.

Guarantees:
- Never blacklists core theological terms (e.g. கர்த்தர், தேவன், ஆவி, இரட்சிப்பு, விசுவாசம்).
- Exports both a comprehensive JSON dictionary and a ready-to-import Python file.
"""

import os
import re
import json
import sys
from collections import Counter
from typing import Dict, Set, List, Tuple

# Core theological terms that must NEVER be treated as stopwords,
# regardless of how frequently they appear in the Bible.
PROTECTED_THEOLOGICAL_WHITELIST: Set[str] = {
    "தேவன்", "தேவனாகிய", "தேவனுடைய", "தேவனுக்கு", "தேவனை", "தேவனாலே",
    "கர்த்தர்", "கர்த்தராகிய", "கர்த்தருடைய", "கர்த்தருக்கு", "கர்த்தரை", "கர்த்தராலே",
    "ஆவியானவர்", "ஆவி", "ஆவியினால்", "பரிசுத்த", "பரிசுத்தர்", "பரிசுத்தம்",
    "பிதா", "குமாரன்", "இயேசு", "கிறிஸ்து", "மேசியா", "மீட்பர்", "இரட்சகர்",
    "சிருஷ்டி", "சிருஷ்டித்தார்", "சிருஷ்டிக்கப்பட்ட", "ஜீவன்", "நித்தியஜீவன்",
    "விசுவாசம்", "விசுவாசிக்கிறவன்", "இரட்சிப்பு", "நீதி", "கிருபை", "இரக்கம்",
    "அன்பு", "உடன்படிக்கை", "ராஜ்யம்", "சுவிசேஷம்", "வேதம்", "வேதவாக்கியம்",
    "வார்த்தை", "ஜெபம்", "பலி", "ஆலயம", "ஆலயம்", "ஆசாரியன்", "தீர்க்கதரிசி",
    "அப்போஸ்தலன்", "சீஷன்", "பாவம்", "அக்கிரமம்", "சாபம்", "ஆசீர்வாதம்",
    "மனுஷன்", "மனுஷகுமாரன்", "வானம்", "பூமி", "பரலோகம்", "நரகம்", "பாதாளம்"
}

# Base classical Tamil grammatical function words
CURATED_GRAMMATICAL_STOPWORDS: Set[str] = {
    # 1. Pronouns - 1st person
    "நான்", "என்", "என்னை", "எனக்கு", "என்னால்", "என்னாலே", "என்னிடத்தில்",
    "நாம்", "நம்", "நம்முடைய", "நமக்கு", "நம்மை", "நம்மால்", "நாங்கள்", "எங்கள்", "எங்களை", "எங்களுக்கு",

    # 2. Pronouns - 2nd person
    "நீ", "உன்", "உன்னை", "உனக்கு", "உன்னால்", "உன்னாலே", "உன்னிடத்தில்",
    "நீர்", "உமது", "உம்முடைய", "உமக்கு", "உம்மை", "உம்மால்", "உம்மிடத்தில்",
    "நீங்கள்", "உங்கள்", "உங்களை", "உங்களுக்கு", "உங்களால்",

    # 3. Pronouns - 3rd person (Masculine / Feminine / Epicene)
    "அவன்", "அவனை", "அவனுக்கு", "அவனால்", "அவனாலே", "அவனிடத்தில்",
    "அவள்", "அவளை", "அவளுக்கு", "அவளால்", "அவளாலே", "அவளிடத்தில்",
    "அவர்", "அவரை", "அவருக்கு", "அவரால்", "அவராலே", "அவரிடத்தில்", "அவருடைய",
    "அவர்கள்", "அவர்களை", "அவர்களுக்கு", "அவர்களால்", "அவர்களுடைய", "அவர்களிடத்தில்",
    "இவன்", "இவனை", "இவனுக்கு", "இவள்", "இவர்", "இவர்கள்", "இவர்களை", "இவர்களுடைய",

    # 4. Reflexive & Possessive
    "தன்", "தன்னை", "தனக்கு", "தன்னால்", "தன்னாலே", "தன்னிடத்தில்", "தன்னுடைய",
    "தம்", "தம்மை", "தமக்கு", "தம்மால்", "தம்முடைய",
    "தங்கள்", "தங்களை", "தங்களுக்கு", "தங்களால்", "தங்களுடைய",

    # 5. Neuter / Demonstratives
    "அது", "அதை", "அதற்கு", "அதினால்", "அதினாலே", "அதின்", "அதினுடைய",
    "அவை", "அவைகளை", "அவைகளுக்கு", "அவைகளால்", "அவைகளின்", "அவைகள்",
    "இது", "இதை", "இதற்கு", "இதினால்", "இதினாலே", "இதின்", "இவைகள்",
    "அந்த", "இந்த", "எந்த",

    # 6. Conjunctions & Discourse Connectives
    "என்று", "என்றான்", "என்றார்", "என்றார்கள்", "என்றுஞ்", "என", "எனவே",
    "அப்பொழுது", "பின்பு", "ஆகையால்", "ஆனாலும்", "ஆனால்", "அல்லது", "அன்றி", "அன்றியும்",
    "ஏனெனில்", "ஏனென்றால்", "ஆதலால்", "இப்படியிருக்க", "ஆகிலும்", "ஆயினும்", "அன்றோ",
    "இதோ", "இதோ பார்", "மற்றும்", "கூட", "தானே", "தான்", "மட்டும்", "மட்டுமல்ல", "மாத்திரம்",

    # 7. Prepositions, Postpositions & Directional Adverbs
    "மேல்", "கீழ்", "முன்", "பின்", "உள்ளே", "வெளியே", "நடுவே", "மத்தியில்",
    "அருகே", "சமீபத்தில்", "பக்கத்தில்", "நேரே", "எதிரே", "சுற்றிலும்",
    "வரைக்கும்", "பரியந்தம்", "நிமித்தம்", "பொருட்டு", "படி", "படியே", "பிரகாரம்",

    # 8. Common Auxiliary & Reporting Verbs
    "சொன்னார்", "சொல்லி", "சொல்லுகிறார்", "சொல்லுகிறேன்", "சொன்னார்கள்",
    "பேசினார்", "கேட்டார்", "பார்த்தார்", "கண்டார்", "செய்தார்",
    "இருந்தது", "இருக்கிறார்", "இருக்கிறார்கள்", "இருப்பார்", "இருந்தான்", "இருந்தார்கள்",
    "ஆயிற்று", "ஆனது", "உண்டாயிற்று", "போனான்", "போனார்", "வந்தான்", "வந்தார்", "வந்து",
    "நின்று", "நோக்கி", "குறித்து",

    # 9. Numbers & Ordinals
    "ஒரு", "ஒன்று", "இரண்டு", "மூன்று", "நான்கு", "ஐந்து", "ஆறு", "ஏழு", "எட்டு", "ஒன்பது", "பத்து",
    "முதலாம்", "இரண்டாம்", "மூன்றாம்", "நாலாம்", "ஐந்தாம்", "ஆறாம்", "ஏழாம்", "எட்டாம்", "ஒன்பதாம்", "பத்தாம்"
}

def harvest_common_words_from_bible(
    bible_dir: str,
    frequency_cutoff: int = 50
) -> Tuple[Dict[str, int], Set[str]]:
    """
    Scans all JSON files in the TAOVBSI Bible directory, builds a word frequency
    distribution, and identifies words exceeding the frequency cutoff that are not
    theologically protected.
    """
    word_counts = Counter()
    
    if not os.path.exists(bible_dir):
        print(f"[Warning] Bible directory '{bible_dir}' not found. Using curated stopwords only.")
        return {}, CURATED_GRAMMATICAL_STOPWORDS

    print(f"Scraping Bible corpus at '{bible_dir}' across all books...")
    for b in range(1, 67):
        b_dir = os.path.join(bible_dir, str(b))
        if not os.path.exists(b_dir):
            continue
        for f in sorted(os.listdir(b_dir)):
            if not f.endswith(".json"):
                continue
            fpath = os.path.join(b_dir, f)
            with open(fpath, "r", encoding="utf-8") as fp:
                try:
                    verses = json.load(fp)
                    for v in verses:
                        tokens = re.findall(r"[\u0B80-\u0BFF]+", v.get("text", ""))
                        for t in tokens:
                            t = t.strip()
                            if t and len(t) >= 1:
                                word_counts[t] += 1
                except Exception as e:
                    print(f"Error reading {fpath}: {e}")

    # Build scraped stopword set
    scraped_stopwords = set(CURATED_GRAMMATICAL_STOPWORDS)
    for word, count in word_counts.items():
        if count >= frequency_cutoff:
            if word not in PROTECTED_THEOLOGICAL_WHITELIST:
                # Exclude if it looks like an obvious grammatical or auxiliary form
                scraped_stopwords.add(word)

    return word_counts, scraped_stopwords

def export_python_stopwords(
    stopwords: Set[str],
    output_py_path: str,
    output_json_path: str
):
    """Writes the scraped stopword set into a clean Python module and JSON file."""
    sorted_words = sorted(list(stopwords))
    
    # 1. Export JSON
    with open(output_json_path, "w", encoding="utf-8") as f:
        json.dump({
            "total_count": len(sorted_words),
            "words": sorted_words
        }, f, ensure_ascii=False, indent=2)
    print(f"Exported {len(sorted_words)} stopwords to JSON: '{output_json_path}'")

    # 2. Export Python module
    py_code = f'''# Auto-generated by stopwords_scraper.py
# Contains {len(sorted_words)} classical Tamil grammatical stopwords, pronouns, and auxiliaries.

COMMON_TAMIL_STOPWORDS = {{
'''
    # Group in lines of 5
    for i in range(0, len(sorted_words), 5):
        chunk = sorted_words[i:i+5]
        line_items = ", ".join(f'"{w}"' for w in chunk)
        py_code += f"    {line_items},\n"

    py_code += "}\n\n"
    py_code += "def is_stopword(word: str) -> bool:\n"
    py_code += "    return word in COMMON_TAMIL_STOPWORDS\n"

    with open(output_py_path, "w", encoding="utf-8") as f:
        f.write(py_code)
    print(f"Exported Python stopword set to: '{output_py_path}'")

if __name__ == "__main__":
    bible_path = os.path.join(os.path.dirname(__file__), "..", "..", "releases", "bibles", "taobvsi")
    bible_path = os.path.abspath(bible_path)

    out_py = os.path.join(os.path.dirname(__file__), "common_stopwords.py")
    out_json = os.path.join(os.path.dirname(__file__), "common_words_blacklist.json")

    counts, stop_set = harvest_common_words_from_bible(bible_path, frequency_cutoff=60)
    export_python_stopwords(stop_set, out_py, out_json)
