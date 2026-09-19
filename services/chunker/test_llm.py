"""Unit tests for services/chunker/llm.py (stdlib unittest, no deps).

Run:  python -m unittest test_llm -v  (from the services/chunker directory).
"""

import unittest
import llm


class FakeLLM:
    def __init__(self, payload):
        self.payload = payload

    def chat_json(self, system, user):
        return self.payload


class CosineSimilarityTest(unittest.TestCase):
    def test_identical_vectors(self):
        v = [0.6, 0.8]
        sim = llm.cosine_similarity(v, v)
        self.assertAlmostEqual(sim, 1.0, places=4)

    def test_orthogonal_vectors(self):
        v1 = [1.0, 0.0]
        v2 = [0.0, 1.0]
        sim = llm.cosine_similarity(v1, v2)
        self.assertAlmostEqual(sim, 0.0, places=4)

    def test_empty_vectors(self):
        self.assertEqual(llm.cosine_similarity([], []), 0.0)


class SegmentationTest(unittest.TestCase):
    def test_short_transcript_not_split(self):
        sentences = [
            {"id": "s1", "text": "A", "startSec": 0.0, "endSec": 5.0},
            {"id": "s2", "text": "B", "startSec": 5.0, "endSec": 10.0},
        ]
        embeddings = [[1.0, 0.0], [1.0, 0.0]]
        groups = llm.segment_sentences_by_similarity(sentences, embeddings, min_sentences=3)
        self.assertEqual(len(groups), 1)
        self.assertEqual(len(groups[0]), 2)

    def test_valley_causes_split(self):
        # 12 sentences: first 6 are topic 1, last 6 are topic 2
        sentences = [
            {"id": f"s{i}", "text": f"Text {i}", "startSec": float(i * 5), "endSec": float((i + 1) * 5)}
            for i in range(12)
        ]
        # Topic 1: [1, 0], Topic 2: [0, 1]
        embeddings = [[1.0, 0.0]] * 6 + [[0.0, 1.0]] * 6
        groups = llm.segment_sentences_by_similarity(sentences, embeddings, min_sentences=4, max_sentences=15)
        self.assertEqual(len(groups), 2)
        self.assertEqual(len(groups[0]), 6)
        self.assertEqual(len(groups[1]), 6)
        # Verify continuity of timestamps
        self.assertEqual(groups[0][0]["startSec"], 0.0)
        self.assertEqual(groups[0][-1]["endSec"], 30.0)
        self.assertEqual(groups[1][0]["startSec"], 30.0)
        self.assertEqual(groups[1][-1]["endSec"], 60.0)

    def test_max_sentences_cap(self):
        # 20 identical sentences with max_sentences=8
        sentences = [
            {"id": f"s{i}", "text": f"Text {i}", "startSec": float(i * 2), "endSec": float((i + 1) * 2)}
            for i in range(20)
        ]
        embeddings = [[0.7, 0.7]] * 20
        groups = llm.segment_sentences_by_similarity(sentences, embeddings, min_sentences=4, max_sentences=8)
        self.assertGreater(len(groups), 1)
        for g in groups:
            self.assertLessEqual(len(g), 12)


class SummarizeIdeaTest(unittest.TestCase):
    def test_fake_llm_summarize(self):
        fake = FakeLLM({"title": "Power of Faith", "summary": "We must believe God unconditionally."})
        sentences = [
            {"text": "Faith is trusting in God."},
            {"text": "Without faith it is impossible to please Him."},
        ]
        res = llm.summarize_idea(fake, sentences)
        self.assertEqual(res["title"], "Power of Faith")
        self.assertEqual(res["summary"], "We must believe God unconditionally.")

    def test_fallback_when_none(self):
        sentences = [
            {"text": "Jesus is the way, the truth, and the life."},
            {"text": "No one comes to the Father except through Him."},
        ]
        res = llm.summarize_idea(None, sentences)
        self.assertEqual(res["title"], "Jesus is the way, the truth, and the life.")
        self.assertIn("Jesus is the way", res["summary"])


class RobustJsonLoadsTest(unittest.TestCase):
    def test_plain_json(self):
        self.assertEqual(llm._robust_json_loads('{"title":"a","summary":"b"}'),
                         {"title": "a", "summary": "b"})

    def test_markdown_fence_stripped(self):
        out = llm._robust_json_loads('```json\n{"title":"a","summary":"b"}\n```')
        self.assertEqual(out["title"], "a")

    def test_trailing_comma_handled(self):
        out = llm._robust_json_loads('{"title":"a","summary":"b",}')
        self.assertEqual(out["title"], "a")


if __name__ == "__main__":
    unittest.main()