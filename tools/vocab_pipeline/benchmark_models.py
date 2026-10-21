#!/usr/bin/env python3
"""
benchmark_models.py

Direct comparison benchmark between local Ollama models (gemma4:e4b, qwen3.5:9b, gemma3:4b)
for classical Tamil linguistic parsing, accuracy, and tokens/sec throughput.
"""

import json
import time
import urllib.request
import sys

# Test words: mix of theological concepts, archaic terms, pronouns, conjunctions, numbers, and Sandhi forms
TEST_WORDS = [
    "தேவன்",                 # Noun / Divine name -> common: false
    "அவன்",                  # Pronoun -> common: true
    "ஆகாயவிரிவு",            # Archaic theological term -> common: false
    "ஆனால்",                 # Conjunction -> common: true
    "வெளிச்சமுண்டாயிற்று",    # Sandhi compound verb -> common: false
    "அப்பொழுது",             # Discourse particle -> common: true
    "சிருஷ்டித்தார்",         # Theological verb -> common: false
    "என்று",                 # Quotative particle -> common: true
    "ஒழுங்கின்மை",           # Abstract noun -> common: false
    "முதலாம்",               # Ordinal number -> common: true
    "பிதோலாகும்",            # Rare archaic noun -> common: false
    "அசைவாடிக்கொண்டிருந்தார்" # Complex theological verb phrase -> common: false
]

SYSTEM_PROMPT = """You are a classical Tamil linguistic parser. Analyze these Tamil words from the TAOVBSI Bible text.
For each word, determine if it is a pure grammatical function word (pronoun, preposition, conjunction, particle, number, or reporting auxiliary) -> tag common: true.
If it has independent lexical meaning (noun, root verb, distinct adjective, theological term, biblical entity) -> tag common: false.
Respond strictly in a valid JSON array of objects.
Format: [{"word": "தேவன்", "common": false}, {"word": "அவன்", "common": true}]"""

def test_model(model_name: str):
    print(f"\n" + "=" * 60)
    print(f"BENCHMARKING MODEL: {model_name}")
    print("=" * 60)

    prompt = f"{SYSTEM_PROMPT}\n\nWords to classify:\n{json.dumps(TEST_WORDS, ensure_ascii=False)}"
    payload = {
        "model": model_name,
        "prompt": prompt,
        "stream": False,
        "format": "json",
        "options": {"temperature": 0.1}
    }

    t0 = time.time()
    req = urllib.request.Request(
        "http://localhost:11434/api/generate",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )

    try:
        with urllib.request.urlopen(req, timeout=90) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            elapsed = round(time.time() - t0, 2)
            eval_count = data.get("eval_count", 0)
            eval_duration = data.get("eval_duration", 1) / 1e9
            speed = round(eval_count / eval_duration, 1)

            print(f"Total Latency: {elapsed}s | Eval Speed: {speed} tokens/sec")
            print(f"Raw Output:\n{data.get('response', '')}")
            
            # Check accuracy
            try:
                raw_json = json.loads(data.get("response", "[]"))
                if isinstance(raw_json, dict):
                    for k in ["results", "words", "data", "classification"]:
                        if k in raw_json: raw_json = raw_json[k]; break
                if isinstance(raw_json, list):
                    parsed_dict = {item.get("word"): item.get("common") for item in raw_json if isinstance(item, dict)}
                    print("\nParsed Classification:")
                    for w in TEST_WORDS:
                        is_com = parsed_dict.get(w)
                        print(f"  {w:<25} -> common: {is_com}")
            except Exception as pe:
                print(f"JSON Parse warning: {pe}")

    except Exception as e:
        print(f"Error testing {model_name}: {e}")

if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    for m in ["qwen3.5:9b", "gemma4:e4b", "gemma3:4b"]:
        test_model(m)
