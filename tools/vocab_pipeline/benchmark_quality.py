"""
Benchmark Definition Quality for the Most Complex Biblical Words in TAOVBSI.
Model: gemma4:e4b running locally via Ollama on Intel Arc Pro GPU (Vulkan).
"""

import os
import sys
import json
import time
import urllib.request
from typing import Dict, List, Any

sys.stdout.reconfigure(encoding="utf-8")

OLLAMA_MODEL = "gemma4:e4b"
OLLAMA_URL = "http://localhost:11434/api/generate"

COMPLEX_TERMS_TEST_SET = [
    {
        "id": "kirubasanam",
        "word": "கிருபாசனம்",
        "domain": "Tabernacle & Atonement Typology",
        "reference": "லேவியராகமம் 16:2 / எபிரெயர் 9:5",
        "context": "பெட்டியின்மேலுள்ள கிருபாசன மூடிக்கு முன்பாகப் பிரவேசிக்கக்கூடாது; கிருபாசனத்தின்மேல் மேகத்திலே காணப்படுவேன்.",
        "expected_theology": "Mercy seat / Propitiatory lid of the Ark where the High Priest sprinkled sacrificial blood for atonement."
    },
    {
        "id": "kuttanivarana_bali",
        "word": "குற்றநிவாரணபலி",
        "domain": "Messianic Sacrificial Theology",
        "reference": "ஏசாயா 53:10",
        "context": "கர்த்தரோ அவரை நொறுக்கச்சித்தமாகி, அவரைப் பாடுகளுக்குட்படுத்தினார்; அவருடைய ஆத்துமா தன்னைக் குற்றநிவாரணபலியாக ஒப்புக்கொடுக்கும்போது...",
        "expected_theology": "Guilt offering / Asham / Trespass offering, prophetically fulfilled in Christ's vicarious atonement."
    },
    {
        "id": "pokkadu",
        "word": "போக்காடு",
        "domain": "Day of Atonement Sacrificial Typology",
        "reference": "லேவியராகமம் 16:8, 10",
        "context": "கர்த்தருக்கென்று ஒரு சீட்டும், போக்காடாக விடப்படும் வெள்ளாட்டுக்கடாவுக்கென்று ஒரு சீட்டும் போட்டு...",
        "expected_theology": "Scapegoat (Azazel) carrying the sins of Israel away into the uninhabited wilderness."
    },
    {
        "id": "aagayavirivu",
        "word": "ஆகாயவிரிவு",
        "domain": "Primeval Cosmology",
        "reference": "ஆதியாகமம் 1:6",
        "context": "பின்பு தேவன்: ஜலத்தின் மத்தியில் ஆகாயவிரிவு உண்டாகக்கடவது என்றும், அது ஜலத்தினின்று ஜலத்தைப் பிரிக்கக்கடவது என்றும் சொன்னார்.",
        "expected_theology": "Firmament / Expanse (Raqia) separating primeval waters above and below."
    },
    {
        "id": "asaivadu",
        "word": "அசைவாடு",
        "domain": "Pneumatology & Creation",
        "reference": "ஆதியாகமம் 1:2",
        "context": "பூமியானது ஒழுங்கின்மையும் வெறுமையுமாய் இருந்தது; தேவ ஆவியானவர் ஜலத்தின்மேல் அசைவாடிக்கொண்டிருந்தார்.",
        "expected_theology": "Hovering / brooding motion of the Holy Spirit imparting life and order to primeval chaos."
    },
    {
        "id": "potragadu",
        "word": "பொற்றகடு",
        "domain": "Tabernacle Regalia & Sacred Vessels",
        "reference": "எபிரெயர் 9:4",
        "context": "அதிலே பொன்னாற்செய்த தூபகலசமும், முழுவதும் பொற்றகடு பொதிந்திருக்கப்பட்ட உடன்படிக்கைப் பெட்டியும் இருந்தன...",
        "expected_theology": "Gold plate overlay signifying divine purity, holiness, and incorruptibility of the Ark."
    },
    {
        "id": "thupakalasam",
        "word": "தூபகலசம்",
        "domain": "Priesthood & Incense Worship",
        "reference": "எபிரெயர் 9:4",
        "context": "அதிலே பொன்னாற்செய்த தூபகலசமும், முழுவதும் பொற்றகடு பொதிந்திருக்கப்பட்ட உடன்படிக்கைப் பெட்டியும் இருந்தன...",
        "expected_theology": "Golden censer carrying burning coals and sweet incense before God's presence, typifying intercessory prayer."
    },
    {
        "id": "thalambu",
        "word": "தளம்பு",
        "domain": "Poetic Blessings & Archaic Idiom",
        "reference": "ஆதியாகமம் 49:4",
        "context": "தண்ணீரைப்போல தளம்பினவனே, நீ மேன்மை அடையமாட்டாய்; உன் தகப்பனுடைய மஞ்சத்தின்மேல் ஏறினாய்...",
        "expected_theology": "Turbulent, unstable, boiling over without restraint (used of Reuben's moral instability)."
    },
    {
        "id": "perungkaatru",
        "word": "பெருங்காற்று",
        "domain": "Theophany & Wisdom Literature",
        "reference": "யோபு 38:1",
        "context": "அப்பொழுது கர்த்தர்: பெருங்காற்றிலிருந்து யோபுக்கு உத்தரவாக: அறிவில்லாத வார்த்தைகளினால் ஆலோசனையை அந்தகாரப்படுத்துகிற இவன் யார்?",
        "expected_theology": "Whirlwind / tempest as God's awe-inspiring instrument of theophany confronting human pride."
    },
    {
        "id": "suthikaripu",
        "word": "சுத்திகரிப்பு",
        "domain": "Covenantal Redemption & Blood Cleansing",
        "reference": "எபிரெயர் 9:22-23",
        "context": "நியாயப்பிரமாணத்தின்படி கொஞ்சங்குறைய எல்லாம் இரத்தத்தினாலே சுத்திகரிக்கப்படும்; இரத்தஞ்சிந்துதலில்லாமல் மன்னிப்பு உண்டாகாது.",
        "expected_theology": "Spiritual and ceremonial cleansing from guilt and moral defilement, strictly through sacrificial blood."
    }
]

SYSTEM_PROMPT = """You are a lexicographer of classical ecclesiastical Tamil for the TAOVBSI Bible.
Generate glossary definitions for each supplied biblical word based on its context verse.
Omit Greek/Hebrew. Do NOT provide Strong's numbers.

For EACH word, respond with a JSON object in the "entries" array having these exact fields:
- "headword": Tamil lemma
- "transliteration": Latin transliteration
- "pos_ta": "பெயர்ச்சொல்" | "வினைச்சொல்" | "பெயரடை" | "வினையடை"
- "category": "theology" | "sacrifice" | "nature" | "attribute" | "action" | "covenant" | "other"
- "gloss_en": concise English gloss (1-3 words)
- "definition_ta": 1-2 sentences of classical Protestant Tamil definition (dignified TAOVBSI style, using வேதாகமம், தேவன், கர்த்தர்)
- "definition_en": 1-2 sentences of scholarly, theological English definition
- "modern_equivalents": array of 1-2 contemporary Tamil everyday synonyms
- "notes": 1-2 sentences explaining biblical/historical/theological typology and context

Return strictly a single JSON object: {"entries": [ ... ]}."""

def run_benchmark():
    print("=" * 80)
    print("COMPLEX BIBLICAL VOCABULARY QUALITY BENCHMARK")
    print(f"Model: {OLLAMA_MODEL} | Device: Intel Arc Pro GPU (Vulkan)")
    print(f"Test Set: 10 Ultra-Complex Biblical Concepts across 10 Domains")
    print("=" * 80)

    # Process in 2 batches of 5 words
    batch_size = 5
    all_results = []
    total_time = 0

    for b_idx in range(0, len(COMPLEX_TERMS_TEST_SET), batch_size):
        batch = COMPLEX_TERMS_TEST_SET[b_idx:b_idx + batch_size]
        words_input = [
            {"word": item["word"], "reference": item["reference"], "context": item["context"]}
            for item in batch
        ]

        prompt = f"{SYSTEM_PROMPT}\n\nWords to define:\n{json.dumps(words_input, ensure_ascii=False, indent=2)}"
        payload = {
            "model": OLLAMA_MODEL,
            "prompt": prompt,
            "stream": False,
            "format": "json",
            "options": {"temperature": 0.2}
        }

        t_start = time.time()
        req = urllib.request.Request(
            OLLAMA_URL,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )

        with urllib.request.urlopen(req, timeout=120) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            elapsed = time.time() - t_start
            total_time += elapsed

            raw = data.get("response", "{}")
            parsed = json.loads(raw)
            entries = parsed.get("entries", [])
            print(f"Batch {b_idx // batch_size + 1}/2 finished in {elapsed:.2f}s ({elapsed / len(batch):.2f}s/word)")

            for orig, gen in zip(batch, entries):
                all_results.append({
                    "concept": orig["word"],
                    "domain": orig["domain"],
                    "reference": orig["reference"],
                    "expected_theology": orig["expected_theology"],
                    "generated": gen
                })

    out_file = os.path.join(os.path.dirname(__file__), "quality_benchmark_results.json")
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump({
            "model": OLLAMA_MODEL,
            "total_words": len(all_results),
            "total_elapsed_seconds": round(total_time, 2),
            "avg_seconds_per_word": round(total_time / len(all_results), 2),
            "results": all_results
        }, f, ensure_ascii=False, indent=2)

    print(f"\nCompleted quality benchmark in {total_time:.2f}s! Saved to: {out_file}\n")

if __name__ == "__main__":
    run_benchmark()
