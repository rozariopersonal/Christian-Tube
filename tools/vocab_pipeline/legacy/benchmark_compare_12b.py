"""
Side-by-side comparative benchmark between gemma4:e4b (8B) and mistral-nemo (12B)
on 10 ultra-complex classical Tamil biblical words.
"""

import os
import sys
import json
import time
import urllib.request
from typing import Dict, List, Any

sys.stdout.reconfigure(encoding="utf-8")

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
if CURRENT_DIR not in sys.path:
    sys.path.insert(0, CURRENT_DIR)

from benchmark_quality import COMPLEX_TERMS_TEST_SET, SYSTEM_PROMPT

MODEL_12B = sys.argv[1] if len(sys.argv) > 1 else "gemma4:12b"
OLLAMA_URL = "http://localhost:11434/api/chat"

def run_12b_benchmark():
    print("=" * 80, flush=True)
    print(f"BENCHMARKING 12B MODEL: {MODEL_12B}", flush=True)
    print("Running 10 ultra-complex biblical concepts across 10 theological domains", flush=True)
    print("=" * 80, flush=True)

    # Load gemma4:e4b previous results for direct comparison
    gemma_file = os.path.join(CURRENT_DIR, "quality_benchmark_results.json")
    gemma_data = {}
    if os.path.exists(gemma_file):
        with open(gemma_file, "r", encoding="utf-8") as f:
            gemma_data = json.load(f)

    batch_size = 5
    all_results = []
    total_time = 0

    for b_idx in range(0, len(COMPLEX_TERMS_TEST_SET), batch_size):
        batch = COMPLEX_TERMS_TEST_SET[b_idx:b_idx + batch_size]
        words_input = [
            {"word": item["word"], "reference": item["reference"], "context": item["context"]}
            for item in batch
        ]

        payload = {
            "model": MODEL_12B,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": f"Words to define:\n{json.dumps(words_input, ensure_ascii=False, indent=2)}"}
            ],
            "stream": False,
            "format": "json",
            "options": {"temperature": 0.2}
        }

        print(f"Dispatching Batch {b_idx // batch_size + 1}/2 ({len(batch)} words)...", flush=True)
        t_start = time.time()
        req = urllib.request.Request(
            OLLAMA_URL,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )

        with urllib.request.urlopen(req, timeout=300) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            elapsed = time.time() - t_start
            total_time += elapsed

            raw = data.get("message", {}).get("content", "{}")
            thinking = data.get("message", {}).get("thinking", "")
            eval_count = data.get("eval_count", 0)
            eval_dur = data.get("eval_duration", 0) / 1e9

            tok_per_sec = (eval_count / eval_dur) if eval_dur > 0 else 0
            try:
                parsed = json.loads(raw)
            except Exception as e:
                print(f"JSON Parse warning: {e}", flush=True)
                parsed = {}

            entries = parsed.get("entries", [])
            print(f"Batch {b_idx // batch_size + 1}/2 finished in {elapsed:.2f}s ({elapsed / len(batch):.2f}s/word) | {tok_per_sec:.2f} tok/s ({eval_count} tokens)", flush=True)

            for orig, gen in zip(batch, entries):
                all_results.append({
                    "concept": orig["word"],
                    "domain": orig["domain"],
                    "reference": orig["reference"],
                    "expected_theology": orig["expected_theology"],
                    "generated_12b": gen
                })

    out_file = os.path.join(CURRENT_DIR, "benchmark_12b_comparison.json")
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump({
            "model_12b": MODEL_12B,
            "model_8b_ref": "gemma4:e4b",
            "total_words": len(all_results),
            "total_elapsed_seconds_12b": round(total_time, 2),
            "avg_seconds_per_word_12b": round(total_time / max(1, len(all_results)), 2),
            "gemma4_avg_seconds_per_word": gemma_data.get("avg_seconds_per_word", 13.53),
            "results": all_results
        }, f, ensure_ascii=False, indent=2)

    print(f"\nCompleted 12B benchmark in {total_time:.2f}s! Saved comparison to: {out_file}\n", flush=True)
    print("=" * 80, flush=True)
    for res in all_results:
        gen = res.get("generated_12b", {})
        print(f"Concept: {res['concept']} ({res['domain']}) | Ref: {res['reference']}", flush=True)
        print(f"  Tamil Def:   {gen.get('definition_ta')}", flush=True)
        print(f"  English Def: {gen.get('definition_en')}", flush=True)
        print(f"  Modern Syns: {gen.get('modern_equivalents')}", flush=True)
        print(f"  Theology:    {gen.get('notes')}", flush=True)
        print("-" * 80, flush=True)

if __name__ == "__main__":
    run_12b_benchmark()
