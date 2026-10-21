#!/usr/bin/env python3
"""
ollama_filter.py

Local LLM linguistic classifier using an Inverted "Default-to-Keep" filter.
Only flags high-confidence grammatical function words, pronouns, conjunctions,
particles, discourse fillers, and numbers as common: true.

Everything else (theological words, nouns, archaic words, verbs, and unknown terms)
defaults to common: false (DEFINITION-WORTHY).
"""

import json
import urllib.request
import urllib.error
from typing import List, Dict, Any, Optional

DEFAULT_OLLAMA_URL = "http://localhost:11434/api/generate"
DEFAULT_MODEL = "gemma2:2b"

INVERTED_SYSTEM_PROMPT = (
    "You are a classical Tamil grammatical classifier. Your ONLY task is to identify pure "
    "grammatical function words, pronouns, conjunctions, particles, discourse fillers, and numbers.\n\n"
    'TAG AS "common": true ONLY IF the word is:\n'
    "1. A pronoun (e.g., அவன், அவள், அவர்கள், நான், நீங்கள், தன், அது, அவை, இவன், இவர்).\n"
    "2. A conjunction or connective (e.g., ஆனால், ஆகையால், ஆனாலும், அல்லது, ஏனெனில், ஆதலால்).\n"
    "3. A grammatical particle, clitic, or reporting speech marker (e.g., என்று, என, ஆயிற்று, என்றார், என்றான், போல, படி).\n"
    "4. A pure number or ordinal (e.g., ஒன்று, இரண்டு, முதலாம், இரண்டாம்).\n\n"
    "CRITICAL RULE (DEFAULT TO FALSE):\n"
    "If a word is a noun, a theological term, a biblical person/place, an archaic word, or an action verb "
    "(like சிருஷ்டி, தேவன், ஆகாயவிரிவு, வெளிச்சம், அன்பு, விசுவாசம், நித்தியஜீவன்) — or if you are in any doubt — "
    'tag it as "common": false.\n\n'
    'Output strictly a JSON array of objects: [{"word": "அவன்", "common": true}, {"word": "ஆகாயவிரிவு", "common": false}]'
)

def tag_common_words_with_ollama(
    words: List[str],
    model: str = DEFAULT_MODEL,
    ollama_url: str = DEFAULT_OLLAMA_URL,
    timeout: int = 20
) -> Optional[Dict[str, bool]]:
    """
    Sends words to local Ollama and returns a dictionary: {word: is_common_bool}.
    Returns None if Ollama is unreachable.
    """
    if not words:
        return {}

    user_content = f"Classify these Tamil words:\n{json.dumps(words, ensure_ascii=False)}"
    payload = {
        "model": model,
        "system": INVERTED_SYSTEM_PROMPT,
        "prompt": user_content,
        "stream": False,
        "format": "json"
    }

    try:
        req = urllib.request.Request(
            ollama_url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=timeout) as response:
            resp_body = response.read().decode("utf-8")
            result = json.loads(resp_body)
            raw_response = result.get("response", "[]")

            parsed = json.loads(raw_response)
            if isinstance(parsed, dict):
                for k in ["results", "words", "data", "classification"]:
                    if k in parsed and isinstance(parsed[k], list):
                        parsed = parsed[k]
                        break

            if isinstance(parsed, list):
                out = {}
                for item in parsed:
                    if isinstance(item, dict) and "word" in item:
                        w = item["word"]
                        is_common = item.get("common", False)
                        out[w] = bool(is_common)
                return out
            return None
    except urllib.error.URLError:
        # Ollama server is offline or unreachable
        return None
    except Exception as e:
        print(f"[Ollama Inverted Tagger Notice] Fallback to rule-based: {e}")
        return None
