"""Unit tests for services/content-worker/llm.py (stdlib unittest, no deps).

Run:  python -m unittest test_llm -v  (from the content-worker directory).
"""

import unittest

import llm


class FakeLLM:
    def __init__(self, payload):
        self.payload = payload

    def chat_json(self, system, user):
        return self.payload


class NormIdeaTest(unittest.TestCase):
    def test_end_le_start_is_swapped(self):
        idea = {"statement": "s", "quote": "q", "start_sec": 300, "end_sec": 240}
        out = llm._norm_idea(idea, 600)
        self.assertEqual(out["start_sec"], 240)
        self.assertGreater(out["end_sec"], out["start_sec"])

    def test_equal_seconds_get_minimum_duration(self):
        idea = {"statement": "s", "quote": "q", "start_sec": 100, "end_sec": 100}
        out = llm._norm_idea(idea, 300)
        self.assertEqual(out["start_sec"], 100)
        self.assertEqual(out["end_sec"], 102)

    def test_tiny_duration_is_bumped(self):
        idea = {"statement": "s", "quote": "q", "start_sec": 240, "end_sec": 240.5}
        out = llm._norm_idea(idea, 300)
        self.assertEqual(out["end_sec"], 242)

    def test_clamp_respects_max_sec(self):
        idea = {"statement": "s", "quote": "q", "start_sec": 298, "end_sec": 297}
        out = llm._norm_idea(idea, 300)
        self.assertGreater(out["end_sec"], out["start_sec"])
        self.assertLessEqual(out["end_sec"], 300)

    def test_tail_collapse_overshoots_slightly(self):
        idea = {"statement": "s", "quote": "q", "start_sec": 614.56, "end_sec": 614.56}
        out = llm._norm_idea(idea, 614.56)
        self.assertEqual(out["end_sec"], 616.56)
        self.assertGreater(out["end_sec"], out["start_sec"])


class ScriptureFilterTest(unittest.TestCase):
    TRANSCRIPT = (
        "[00:00 -> 00:10] We read the Living Bible and then first Corinthians "
        "chapter nine and verse twenty seven. He must ask in faith. "
        "[00:10 -> 00:20] As the Psalms say we know already."
    )

    def _extract(self, scriptures):
        payload = {
            "ideas": [
                {
                    "title": "t",
                    "statement": "We must ask in faith without doubting.",
                    "quote": "We must ask in faith without doubting.",
                    "start_sec": 2,
                    "end_sec": 8,
                    "scriptures": scriptures,
                    "keywords": [],
                }
            ]
        }
        return llm.extract_ideas(FakeLLM(payload), self.TRANSCRIPT, 20)[0]["scriptures"]

    def test_translation_name_dropped_even_when_grounded(self):
        out = self._extract(["Living Bible", "1 Corinthians 9:27", "Psalm 90"])
        self.assertEqual(out, ["1 Corinthians 9:27", "Psalm 90"])

    def test_ungrounded_book_dropped(self):
        out = self._extract(["Ezekiel 38:2"])
        self.assertEqual(out, [])

    def test_digitless_reference_dropped(self):
        out = self._extract(["Matthew"])
        self.assertEqual(out, [])


if __name__ == "__main__":
    unittest.main()