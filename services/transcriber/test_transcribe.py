"""Unit tests for services/transcriber/transcribe.py (stdlib unittest).

Run:  python -m unittest test_transcribe -v  (from the transcriber directory).
Transcription/audio helpers are dependency-free; NeMo/yt-dlp are never loaded.
"""

import unittest

from transcribe import _parse_srt, _parse_vtt, _ts_to_sec, build_transcript, fmt_ts, parse_duration


class FmtTsTest(unittest.TestCase):
    def test_hours_format(self):
        self.assertEqual(fmt_ts(3661.4), "1:01:01")

    def test_minutes_zero_padded(self):
        self.assertEqual(fmt_ts(61), "01:01")

    def test_never_negative(self):
        self.assertEqual(fmt_ts(-5), "00:00")


class ParseDurationTest(unittest.TestCase):
    def test_iso_hms(self):
        self.assertEqual(parse_duration("PT1H2M3S"), 3723.0)

    def test_iso_ms(self):
        self.assertEqual(parse_duration("PT2M30S"), 150.0)

    def test_raw_seconds(self):
        self.assertEqual(parse_duration("1520"), 1520.0)

    def test_colon_clock(self):
        self.assertEqual(parse_duration("1:02:03"), 3723.0)

    def test_empty(self):
        self.assertIsNone(parse_duration(None))
        self.assertIsNone(parse_duration(""))


class TsToSecTest(unittest.TestCase):
    def test_minutes_seconds(self):
        self.assertEqual(_ts_to_sec("01:05"), 65.0)

    def test_hours(self):
        self.assertEqual(_ts_to_sec("1:01:01"), 3661.0)

    def test_decimal_comma(self):
        self.assertEqual(_ts_to_sec("00:00.5"), 0.5)


class CaptionParsersTest(unittest.TestCase):
    def test_vtt_cues(self):
        vtt = (
            "WEBVTT\n\n"
            "00:00:00.000 --> 00:00:03.000\n"
            "Walk in love\n\n"
            "00:00:03.500 --> 00:00:06.000\n"
            "as Christ loved us"
        )
        cues = _parse_vtt(vtt)
        self.assertEqual(len(cues), 2)
        self.assertEqual(cues[0]["text"], "Walk in love")
        self.assertEqual(cues[1]["start"], 3.5)

    def test_srt_cues(self):
        srt = (
            "1\n00:00:00,000 --> 00:00:02,000\n"
            "Faith is the substance\n\n"
            "2\n00:00:02,000 --> 00:00:04,000\n"
            "of things hoped for"
        )
        cues = _parse_srt(srt)
        self.assertEqual(len(cues), 2)
        self.assertEqual(cues[1]["text"], "of things hoped for")
        self.assertEqual(cues[1]["start"], 2.0)


class BuildTranscriptTest(unittest.TestCase):
    def test_timestamped_lines(self):
        segments = [{"start": 0, "end": 10, "text": "Grace to you"}, {"start": 10, "end": 20, "text": "and peace"}]
        out = build_transcript(segments)
        lines = out.splitlines()
        self.assertEqual(len(lines), 2)
        self.assertTrue(lines[0].startswith("[00:00 00:10] Grace to you"))

    def test_missing_end(self):
        segments = [{"start": 5, "text": "Only start matters"}]
        out = build_transcript(segments)
        self.assertTrue(out.startswith("[00:05] Only start matters"))


if __name__ == "__main__":
    unittest.main()