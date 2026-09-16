"""Unit tests for the VideoChunk embedding helpers (service: embedder).

Run inside the embedder container:  python -m unittest test_chunks -v
"""

import unittest

import model_contract
import worker


class ChunkPassageTest(unittest.TestCase):
    def test_prefix_added(self):
        self.assertEqual(
            worker.chunk_passage("Walk in love"),
            model_contract.PASSAGE_PREFIX + "Walk in love",
        )

    def test_leading_whitespace_stripped(self):
        self.assertEqual(
            worker.chunk_passage("  Walk in love  "),
            model_contract.PASSAGE_PREFIX + "Walk in love",
        )

    def test_empty_content(self):
        self.assertEqual(worker.chunk_passage(None), model_contract.PASSAGE_PREFIX)
        self.assertEqual(worker.chunk_passage(""), model_contract.PASSAGE_PREFIX)


if __name__ == "__main__":
    unittest.main()