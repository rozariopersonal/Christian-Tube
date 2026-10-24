"""
Legacy alias pointing to bible_vocab_processor.py.
"""
import sys
import os

target = os.path.join(os.path.dirname(__file__), "bible_vocab_processor.py")
if __name__ == "__main__":
    with open(target, "r", encoding="utf-8") as f:
        code = f.read()
    exec(compile(code, target, 'exec'))
