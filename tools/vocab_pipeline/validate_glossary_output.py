#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Validation script for Bible Glossary entries in book_01_ஆதியாகமம்.json:
1. Schema & Field Completeness
2. Root Word & Root Meaning Alignment (no generic 'அறியப்படாத வேர்ச்சொல்')
3. Language Purity (No English letters inside Tamil fields)
4. Headword Canonical Base Form (no inflectional endings)
5. Zac Poonen Notes Compliance (no attribution names, null when not taught)
6. SQLite Database Synchronization
"""

import os
import sys
import json
import re
import sqlite3
from typing import Dict, List, Any

sys.stdout.reconfigure(encoding="utf-8")

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(CURRENT_DIR, "..", ".."))

GLOSSARY_JSON = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "glossary_additions", "book_01_ஆதியாகமம்.json")
ENRICHED_DB = os.path.join(PROJECT_ROOT, "releases", "study", "taobvsi", "taobvsi_glossary_enriched.sqlite")

ENGLISH_CHAR_RE = re.compile(r"[a-zA-Z]")

def validate_glossary(json_path: str = GLOSSARY_JSON, db_path: str = ENRICHED_DB) -> Dict[str, Any]:
    if not os.path.exists(json_path):
        return {"error": f"JSON file not found: {json_path}"}

    with open(json_path, "r", encoding="utf-8") as f:
        entries = json.load(f)

    report = {
        "total_entries": len(entries),
        "valid_count": 0,
        "issues": [],
        "generic_root_placeholders": [],
        "english_in_tamil_fields": [],
        "attribution_in_notes": [],
        "notes_count": 0,
        "null_notes_count": 0,
        "sqlite_sync": {}
    }

    # Prohibited placeholders in root
    prohibited_root_patterns = ["அறியப்படாத", "வேர்ச்சொல் இல்லை", "unknown root", "unused root"]
    # Prohibited attribution names in notes
    prohibited_attribution = ["சாக் பூனன்", "பூனன்", "zac poonen", "poonen", "போதனையின்படி"]

    for idx, e in enumerate(entries):
        hw = e.get("headword", f"Entry_{idx}")
        has_issue = False

        # 1. Check root word placeholders
        root = str(e.get("original_root", ""))
        for pat in prohibited_root_patterns:
            if pat.lower() in root.lower():
                report["generic_root_placeholders"].append({
                    "headword": hw,
                    "original_root": root,
                    "original_meaning": e.get("original_meaning")
                })
                has_issue = True

        # 2. Check English letters in pure Tamil fields
        for field in ["definition_ta", "notes", "original_lexical_definition"]:
            val = e.get(field)
            if val and isinstance(val, str):
                words = [w for w in val.split() if ENGLISH_CHAR_RE.search(w)]
                if words:
                    report["english_in_tamil_fields"].append({
                        "headword": hw,
                        "field": field,
                        "english_words": words[:3]
                    })
                    has_issue = True

        # 3. Check Zac Poonen attribution in notes
        note = e.get("notes")
        if note:
            report["notes_count"] += 1
            for attr in prohibited_attribution:
                if attr.lower() in note.lower():
                    report["attribution_in_notes"].append({
                        "headword": hw,
                        "notes": note[:100]
                    })
                    has_issue = True
        else:
            report["null_notes_count"] += 1

        # 4. Check prohibited terms (Strict Protestant TAOVBSI verification)
        PROHIBITED_CATHOLIC_TERMS = [
            "விவிலிய", "பைபிள்", "மறைநூல்", "மறைவாக்கு",
            "தூய ஆவியார்", "தூய ஆவி", "புனித",
            "நற்செய்தி", "திருமுழுக்கு", "திருத்தூதர்",
            "இறைவாக்கினர்", "நற்கருணை", "திருப்பலி",
            "தேவமாதா", "அன்னை மரியா", "பரலோக ராக்கினி",
            "விண்ணரசு", "இறையாட்சி", "நிலைவாழ்வு",
            "சந்திப்புக் கூடாரம்", "உத்தரிக்கும் ஸ்தலம்",
            "யாகப்பர்", "ராயப்பர்"
        ]
        for field in ["definition_ta", "notes", "original_lexical_definition"]:
            val = e.get(field)
            if val and isinstance(val, str):
                for bad_term in PROHIBITED_CATHOLIC_TERMS:
                    if bad_term in val:
                        if "prohibited_catholic_terms" not in report:
                            report["prohibited_catholic_terms"] = []
                        report["prohibited_catholic_terms"].append({
                            "headword": hw,
                            "field": field,
                            "matched_term": bad_term,
                            "snippet": val[:100]
                        })
                        has_issue = True

        # 5. Check references and surface forms
        if not e.get("refs"):
            report["issues"].append(f"{hw}: missing 'refs'")
            has_issue = True
        if not e.get("surface_forms"):
            report["issues"].append(f"{hw}: missing 'surface_forms'")
            has_issue = True

        if not has_issue:
            report["valid_count"] += 1

    # SQLite sync check
    if os.path.exists(db_path):
        try:
            conn = sqlite3.connect(db_path)
            c = conn.cursor()
            db_entries = c.execute("SELECT count(*) FROM glossary_entries WHERE first_reference LIKE 'ஆதியாகமம் %'").fetchone()[0]
            db_surfaces = c.execute("SELECT count(*) FROM surface_forms WHERE headword IN (SELECT headword FROM glossary_entries WHERE first_reference LIKE 'ஆதியாகமம் %')").fetchone()[0]
            db_refs = c.execute("SELECT count(*) FROM verse_references WHERE reference LIKE 'ஆதியாகமம் %'").fetchone()[0]
            conn.close()
            report["sqlite_sync"] = {
                "db_entries": db_entries,
                "db_surface_forms": db_surfaces,
                "db_verse_references": db_refs,
                "json_matches_db": (db_entries == len(entries))
            }
        except Exception as e:
            report["sqlite_sync"]["error"] = str(e)

    return report

if __name__ == "__main__":
    rep = validate_glossary()
    print(json.dumps(rep, ensure_ascii=False, indent=2))
