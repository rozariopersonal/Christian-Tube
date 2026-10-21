#!/usr/bin/env python3
"""
morphology.py

Pure, independent Classical Tamil morphological cleaner and tokenizer for TAOVBSI Bible text.
Contains 0 dependency on legacy databases or pre-existing files.
"""

import re
from typing import List

# Regex pattern for pure Tamil Unicode block [\u0B80-\u0BFF] + zero-width joiners
TAMIL_WORD_RE = re.compile(r"[\u0B80-\u0BFF]+")


def extract_tamil_words(text: str) -> List[str]:
    """Extracts all continuous Tamil character sequences from a verse string."""
    if not text:
        return []
    return TAMIL_WORD_RE.findall(text)


def clean_tamil_token(token: str) -> str:
    """Removes non-Tamil characters and trims whitespace."""
    cleaned = re.sub(r"[^\u0B80-\u0BFF]", "", token)
    return cleaned.strip()
