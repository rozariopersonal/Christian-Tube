"""Offline regression tests: no inference server or release assets required."""

import csv
import io
import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import validated_vocab_processor as pipeline
from vocab_checkpoints import atomic_json, chapter_complete, verified_words
from vocab_responses import resolve_items, validate_response, response_schema


def definition(index=0, **changes):
    return {"i": index, "p": "n", "c": "மரம்", "d": "கிளைகளுடன் வளரும் தாவரம்.",
            "m": "மரம்", "e": "tree", **changes}


def candidate(word_id=1, pos="noun"):
    return {"word_id": word_id, "pos": pos, "canonical": "மரம்",
            "definition_ta": "கிளைகளுடன் வளரும் தாவரம்.",
            "modern_equivalent": "மரம்", "english_word": "tree"}


def word(raw="மரம்", verse=1, index=0):
    return {"verse": verse, "word_index": index, "word": raw,
            **{k: v for k, v in candidate().items() if k != "word_id"}}


def record(raw="மரம்", **changes):
    item = word(raw)
    return {"book": 1, "chapter": 1, "verse": item["verse"], "word_index": item["word_index"],
            "raw_token": raw, "clean_token": raw, "word_id": None,
            **{key: item[key] for key in ("pos", "canonical", "definition_ta", "modern_equivalent", "english_word")},
            **changes}


class ResponseTests(unittest.TestCase):
    def test_retries_only_missing_or_invalid_items(self):
        prompts = []
        responses = iter([
            {"definitions": [definition(0), definition(1, d=" ")], "selections": []},
            {"definitions": [definition(1)], "selections": []},
        ])
        def call(prompt, **kwargs):
            prompts.append(json.loads(prompt.split("Words to analyze:\n")[1]))
            self.assertIn("schema", kwargs)
            return next(responses)
        defs, selected = resolve_items("மரம் மரம்", [{"i": 0, "w": "மரம்"}, {"i": 1, "w": "மரம்"}], [], call)
        self.assertEqual([list(item["i"] for item in request) for request in prompts], [[0, 1], [1]])
        self.assertEqual(set(defs), {0, 1})
        self.assertFalse(selected)

    def test_ambiguity_requires_candidate_id_not_just_pos(self):
        request = [{"i": 0, "task": "select", "candidates": [{"id": 1}, {"id": 2}]}]
        for result in ({"i": 0, "id": None}, {"i": 0, "id": 999}, {"i": 0, "id": True}, {"i": 0, "p": "n"}):
            with self.subTest(result=result):
                self.assertEqual(validate_response({"selections": [result]}, request), ({}, {}))
        self.assertEqual(validate_response({"selections": [{"i": 0, "id": 2}]}, request), ({}, {0: 2}))

    def test_duplicate_unrequested_and_wrong_type_indices_are_not_trusted(self):
        request = [{"i": 0, "task": "define"}]
        for entries in ([definition(), definition()], [definition(99)], [definition(True)], [definition("0")]):
            with self.subTest(entries=entries):
                self.assertEqual(validate_response({"definitions": entries}, request), ({}, {}))

    def test_invalid_fields_are_rejected_without_coercion(self):
        for changes in ({"p": "bogus"}, {"p": []}, {"c": ""}, {"d": None}, {"m": 5}, {"e": " "}):
            with self.subTest(changes=changes):
                self.assertEqual(validate_response({"definitions": [definition(**changes)]}, [{"i": 0, "task": "define"}]), ({}, {}))

    def test_schema_bounds_definition_fields_and_requested_occurrences(self):
        schema = response_schema([{"i": 12, "task": "define"}])
        defs = schema["properties"]["definitions"]
        self.assertEqual(defs["maxItems"], 1)
        self.assertEqual(defs["items"]["properties"]["i"]["enum"], [12])
        self.assertEqual(defs["items"]["properties"]["d"]["maxLength"], 360)
        self.assertEqual(schema["properties"]["selections"]["maxItems"], 0)
        self.assertEqual(validate_response({"definitions": [definition(d="அ" * 361)]}, [{"i": 0, "task": "define"}]), ({}, {}))

    def test_selection_only_request_uses_small_output_budget(self):
        calls = []
        def call(prompt, **kwargs):
            calls.append((prompt, kwargs))
            return {"selections": [{"i": 0, "id": 2}], "definitions": []}
        defs, selected = resolve_items("மரம்", [], [{"i": 0, "w": "மரம்", "candidates": [candidate(1), candidate(2)]}], call)
        self.assertEqual(selected, {0: 2})
        self.assertFalse(defs)
        self.assertEqual(calls[0][1]["num_predict"], 128)
        self.assertIn('"d":', calls[0][0])  # Candidate meaning remains available for context.

    def test_failures_have_bounded_retries_and_no_fabricated_result(self):
        calls = []
        defs, selected = resolve_items("மரம்", [{"i": 0, "w": "மரம்"}], [], lambda *args, **kwargs: calls.append(1))
        self.assertEqual(len(calls), 3)
        self.assertEqual((defs, selected), ({}, {}))

    def test_batch_boundary_does_not_requery_completed_items(self):
        requests = []
        def call(prompt, **kwargs):
            items = json.loads(prompt.split("Words to analyze:\n")[1])
            requests.append([item["i"] for item in items])
            return {"definitions": [definition(item["i"]) for item in items], "selections": []}
        defs, _ = resolve_items("verse", [{"i": i, "w": "மரம்"} for i in range(8)], [], call)
        self.assertEqual(requests, [[0, 1, 2, 3, 4, 5], [6, 7]])
        self.assertEqual(len(defs), 8)

    def test_definition_retries_expand_budget_and_split_unresolved_groups(self):
        requests = []
        def call(prompt, **kwargs):
            items = json.loads(prompt.split("Words to analyze:\n")[1])
            requests.append(([item["i"] for item in items], kwargs["num_predict"]))
            if len(requests) == 1:
                return None  # A truncated JSON document cannot be accepted.
            return {"definitions": [definition(item["i"]) for item in items], "selections": []}
        defs, _ = resolve_items("verse", [{"i": i, "w": "மரம்"} for i in range(4)], [], call)
        self.assertEqual([request[0] for request in requests], [[0, 1, 2, 3], [0, 1], [2, 3]])
        self.assertEqual(len(defs), 4)
        self.assertTrue(all(budget >= 500 for _, budget in requests))
        self.assertGreater(requests[1][1] / len(requests[1][0]), requests[0][1] / len(requests[0][0]))

    def test_single_tamil_definition_has_room_beyond_160_tokens(self):
        budgets = []
        def call(prompt, **kwargs):
            budgets.append(kwargs["num_predict"])
            return None if len(budgets) == 1 else {"definitions": [definition()], "selections": []}
        defs, _ = resolve_items("verse", [{"i": 0, "w": "மரம்"}], [], call)
        self.assertEqual(budgets, [500, 1000])
        self.assertEqual(set(defs), {0})

    def test_repeated_surface_occurrences_remain_distinct(self):
        result = {"definitions": [definition(0, p="n"), definition(1, p="v")], "selections": []}
        defs, _ = resolve_items("படி படி", [{"i": 0, "w": "படி"}, {"i": 1, "w": "படி"}], [], lambda *args, **kwargs: result)
        self.assertEqual(defs[0]["pos"], "noun")
        self.assertEqual(defs[1]["pos"], "verb")


class DatabaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.db = pipeline.BibleVocabDB(str(Path(self.temp.name) / "glossary.sqlite"))

    def test_repair_blank_entry_preserves_id_and_existing_references(self):
        with self.db.get_conn() as conn:
            conn.execute("INSERT INTO unique_words (surface_form,pos,canonical,definition_ta) VALUES ('மரம்','noun','மரம்','')")
            identifier = conn.execute("SELECT id FROM unique_words").fetchone()[0]
            conn.execute("INSERT INTO verse_tokens VALUES (1,1,1,0,'மரம்',?)", (identifier,))
        self.assertIsNone(self.db.lookup_word("மரம்"))
        self.db.save_verse_records([record()])
        found = self.db.lookup_word("மரம்")
        self.assertEqual(found["word_id"], identifier)
        self.assertEqual(found["definition_ta"], candidate()["definition_ta"])
        with self.db.get_conn() as conn:
            self.assertEqual(conn.execute("SELECT count(*) FROM unique_words").fetchone()[0], 1)
            self.assertEqual(conn.execute("SELECT word_id FROM verse_tokens").fetchone()[0], identifier)

    def test_complete_cached_entry_is_not_overwritten(self):
        self.db.save_verse_records([record()])
        self.db.save_verse_records([record(definition_ta="வேறு விளக்கம்.")])
        self.assertEqual(self.db.lookup_word("மரம்")["definition_ta"], candidate()["definition_ta"])

    def test_incomplete_records_are_rejected_before_any_write(self):
        with self.assertRaises(ValueError):
            self.db.save_verse_records([record(), record("வேறு", definition_ta="")])
        with self.db.get_conn() as conn:
            self.assertEqual(conn.execute("SELECT count(*) FROM unique_words").fetchone()[0], 0)

    def test_connections_are_closed(self):
        with self.db.get_conn() as conn:
            conn.execute("SELECT 1")
        with self.assertRaises(sqlite3.ProgrammingError):
            conn.execute("SELECT 1")

    def test_repeated_saves_export_one_row_per_occurrence(self):
        self.db.save_verse_records([record()])
        self.db.save_verse_records([record()])
        target = str(Path(self.temp.name) / "audit.csv")
        self.db.export_full_consolidated_csv(target)
        with open(target, encoding="utf-8", newline="") as fp:
            rows = list(csv.DictReader(fp))
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["raw_token"], "மரம்")


class ChapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bible = self.root / "bibles"
        self.outputs = self.root / "words"
        self.verses = [{"verse": 1, "text": "மரம்"}, {"verse": 2, "text": "இலை"}]
        atomic_json(self.bible / "1" / "1.json", self.verses)
        self.db = pipeline.BibleVocabDB(str(self.root / "glossary.sqlite"))
        self.patches = patch.multiple(pipeline, BASE_BIBLE_DIR=str(self.bible), BASE_WORDS_DIR=str(self.outputs), db=self.db, VALIDATED_CHAPTERS=set())
        self.patches.start()
        self.addCleanup(self.patches.stop)
        pipeline.STOP_EVENT.clear()

    def data(self, words):
        return {"book": 1, "chapter": 1, "is_step1_completed": True, "words": words}

    def test_complete_marker_requires_every_valid_token_in_order(self):
        valid = self.data([word(), word("இலை", verse=2)])
        self.assertTrue(chapter_complete(valid, self.verses, 1, 1))
        for data in (self.data([word()]), self.data([word(), word("மரம்", verse=2)]),
                     self.data([word(), {**word("இலை", verse=2), "definition_ta": ""}]),
                     self.data([word(), word("இலை", verse=2), word("extra", verse=99)])):
            with self.subTest(data=data):
                self.assertFalse(chapter_complete(data, self.verses, 1, 1))

    def test_partial_checkpoint_reuses_only_complete_source_matched_verses(self):
        data = self.data([word(), {**word("இலை", verse=2), "english_word": ""}])
        self.assertEqual(verified_words(data, self.verses, 1, 1), [word()])
        data["book"] = 2
        self.assertFalse(verified_words(data, self.verses, 1, 1))

    def test_failed_model_never_persists_an_empty_definition(self):
        with patch.object(pipeline, "call_llm", return_value=None), patch.object(pipeline, "log"):
            self.assertFalse(pipeline.process_chapter(1, 1))
        self.assertFalse(pipeline.VALIDATED_CHAPTERS)
        self.assertFalse((self.outputs / "1" / "1.json").exists())
        partial = json.loads((self.outputs / "1" / "1.partial.json").read_text(encoding="utf-8"))
        self.assertFalse(partial["is_step1_completed"])
        with self.db.get_conn() as conn:
            self.assertEqual(conn.execute("SELECT count(*) FROM unique_words").fetchone()[0], 0)

    def test_failed_disambiguation_does_not_select_first_candidate(self):
        self.db.save_verse_records([record(), record(pos="verb")])
        with patch.object(pipeline, "call_llm", return_value=None), patch.object(pipeline, "log"):
            with self.assertRaises(pipeline.IncompleteVerseError):
                pipeline.process_verse(1, 1, self.verses[0])

    def test_explicit_selection_preserves_the_chosen_cached_definition(self):
        self.db.save_verse_records([record(), record(pos="verb", canonical="வளர்", english_word="grow")])
        with self.db.get_conn() as conn:
            identifier = conn.execute("SELECT id FROM unique_words WHERE pos='verb'").fetchone()[0]
        response = {"definitions": [], "selections": [{"i": 0, "id": identifier}]}
        with patch.object(pipeline, "call_llm", return_value=response) as call, patch.object(pipeline, "log"):
            words = pipeline.process_verse(1, 1, self.verses[0])
        self.assertEqual(call.call_count, 1)
        self.assertEqual(words[0]["pos"], "verb")
        self.assertEqual(words[0]["canonical"], "வளர்")
        self.assertEqual(words[0]["english_word"], "grow")
        self.assertEqual(words[0]["definition_ta"], candidate()["definition_ta"])
        with self.db.get_conn() as conn:
            self.assertEqual(conn.execute("SELECT word_id FROM verse_tokens").fetchone()[0], identifier)

    def test_successful_words_survive_a_failed_batch_and_are_reused(self):
        verse = {"verse": 1, "text": "மரம் இலை"}
        partial_response = {"definitions": [definition()], "selections": []}
        with patch.object(pipeline, "call_llm", return_value=partial_response), patch.object(pipeline, "log"):
            with self.assertRaises(pipeline.IncompleteVerseError):
                pipeline.process_verse(1, 1, verse)
        self.assertIsNotNone(self.db.lookup_word("மரம்"))
        self.assertIsNone(self.db.lookup_word("இலை"))
        with patch.object(pipeline, "call_llm", return_value={"definitions": [definition(1)], "selections": []}) as call, patch.object(pipeline, "log"):
            words = pipeline.process_verse(1, 1, verse)
        self.assertEqual(len(words), 2)
        requested = json.loads(call.call_args.args[1].split("Words to analyze:\n")[1])
        self.assertEqual([item["i"] for item in requested], [1])

    def test_repair_invalid_complete_file_and_resume_good_verses(self):
        target = self.outputs / "1" / "1.json"
        atomic_json(target, self.data([word(), {**word("இலை", verse=2), "definition_ta": ""}]))
        with patch.object(pipeline, "process_verse", side_effect=pipeline.IncompleteVerseError("pending")) as call, patch.object(pipeline, "log"):
            self.assertFalse(pipeline.process_chapter(1, 1))
        self.assertFalse(json.loads(target.read_text(encoding="utf-8"))["is_step1_completed"])
        self.assertEqual(call.call_args.args[2]["verse"], 2)
        with patch.object(pipeline, "process_verse", return_value=[word("இலை", verse=2)]) as call, patch.object(pipeline, "log"):
            self.assertTrue(pipeline.process_chapter(1, 1))
        self.assertEqual(call.call_count, 1)
        final = json.loads(target.read_text(encoding="utf-8"))
        self.assertTrue(chapter_complete(final, self.verses, 1, 1))
        self.assertEqual(pipeline.VALIDATED_CHAPTERS, {(1, 1)})
        self.assertFalse((self.outputs / "1" / "1.partial.json").exists())

    def test_reordered_chapter_is_reassembled_before_completion(self):
        data = self.data([word("இலை", verse=2), word()])
        self.assertFalse(chapter_complete(data, self.verses, 1, 1))
        atomic_json(self.outputs / "1" / "1.json", data)
        with patch.object(pipeline, "process_verse") as call, patch.object(pipeline, "log"):
            self.assertTrue(pipeline.process_chapter(1, 1))
        call.assert_not_called()
        final = json.loads((self.outputs / "1" / "1.json").read_text(encoding="utf-8"))
        self.assertTrue(chapter_complete(final, self.verses, 1, 1))

    def test_main_exits_nonzero_and_exports_audit_when_chapter_is_pending(self):
        with patch.object(sys, "argv", ["processor", "--end-book", "1", "--end-chapter", "1"]), \
             patch.multiple(pipeline, SQLITE_PATH=str(self.root / "main.sqlite"), CSV_PATH=str(self.root / "audit.csv")), \
             patch.object(pipeline, "check_server_health", return_value=(True, "test", 0, "ollama")), \
             patch.object(pipeline, "process_chapter", return_value=False), \
             patch.object(pipeline, "live_monitor_loop"), patch.object(pipeline, "log"):
            self.assertEqual(pipeline.main(), 1)
        self.assertTrue((self.root / "audit.csv").exists())

    def test_punctuation_occurrence_is_preserved_without_model_call(self):
        with patch.object(pipeline, "call_llm") as call, patch.object(pipeline, "log"):
            words = pipeline.process_verse(19, 10, {"verse": 11, "text": '"'})
        call.assert_not_called()
        self.assertEqual(words[0]["word"], '"')
        self.assertEqual(words[0]["word_index"], 0)
        self.assertEqual(words[0]["pos"], "punctuation")

    def test_atomic_replace_failure_keeps_previous_checkpoint(self):
        target = self.root / "checkpoint.json"
        atomic_json(target, {"old": True})
        with patch("vocab_checkpoints.os.replace", side_effect=OSError("interrupted")):
            with self.assertRaises(OSError):
                atomic_json(target, {"new": True})
        self.assertEqual(json.loads(target.read_text(encoding="utf-8")), {"old": True})
        self.assertFalse(list(self.root.glob("checkpoint.json.*.tmp")))


class TransportTests(unittest.TestCase):
    def test_both_backends_receive_the_schema_and_selection_budget(self):
        for backend in ("ollama", "llama_server"):
            with self.subTest(backend=backend):
                body = {"message": {"content": '{"definitions":[],"selections":[]}'},
                        "choices": [{"message": {"content": '{"definitions":[],"selections":[]}'}, "finish_reason": "stop"}]}
                response = io.BytesIO(json.dumps(body).encode())
                with patch.dict(pipeline.TELEMETRY, {"backend_type": backend}), patch.object(pipeline.urllib.request, "urlopen", return_value=response) as request:
                    result = pipeline.call_llm("system", "verse", num_predict=128, schema={"type": "object"})
                payload = json.loads(request.call_args.args[0].data)
                self.assertEqual(result, {"definitions": [], "selections": []})
                if backend == "ollama":
                    self.assertEqual(payload["format"], {"type": "object"})
                    self.assertFalse(payload["think"])
                else:
                    self.assertEqual(payload["response_format"]["schema"], {"type": "object"})
                    self.assertEqual(payload["max_tokens"], 128)


if __name__ == "__main__":
    unittest.main()
