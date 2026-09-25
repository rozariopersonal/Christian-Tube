import json
import os
import sys
import tempfile
from pathlib import Path
import unittest
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).parent))

from worker import (
    slugify,
    map_language,
    is_short_content,
    detect_category,
    extract_speaker,
    detect_languages,
    clean_audiocom_tags,
    norm_title,
    parse_duration_seconds,
    is_permanent_failure,
    process_video,
    AudioComClient,
    Config,
    Database,
    load_config,
)


def _make_db():
    with patch("psycopg2.connect") as mock_connect:
        conn = MagicMock()
        cur = MagicMock()
        mock_connect.return_value = conn
        conn.cursor.return_value = cur
        conn.autocommit = True
        cur.connection = conn
        conn.encoding = "UTF8"
        db = Database("postgresql://user:pass@host/db?sslmode=require")
        cur.reset_mock()
        return db, cur


class TestWorkerCollections(unittest.TestCase):
    def test_detect_languages(self):
        # Bilingual patterns
        self.assertEqual(detect_languages("10. Baptism in Fire by Bro Victor [Tamil-English]", ""), ("Tamil", "English"))
        self.assertEqual(detect_languages("Don't Ever Lose Heart (SPANISH & ENGLISH)", ""), ("Spanish", "English"))
        self.assertEqual(detect_languages("Sunday Service with Hindi Translation", ""), ("Hindi", "English"))

        # Indic script titles with English secondary
        self.assertEqual(detect_languages("பிலிப்பியர் மூன்றாம் பகுதி | Philippians Third Session", ""), ("Tamil", "English"))

        # Pure native script
        self.assertEqual(detect_languages("சகரியா பூணன் செய்தி", ""), ("Tamil", None))

        # Pure English
        self.assertEqual(detect_languages("Devotion to Christ - Zac Poonen", ""), ("English", None))

        # Romanized keyword
        self.assertEqual(detect_languages("Tamil Message by Bro. Vincent", ""), ("Tamil", None))

    def test_extract_speaker(self):
        # Known speakers from title (English)
        self.assertEqual(extract_speaker("Devotion to Christ - Zac Poonen", "", "CFC India"), "Zac Poonen")
        self.assertEqual(extract_speaker("Love and Grace - Charles Banna", "", "CFC India"), "Charles Banna")
        self.assertEqual(extract_speaker("Knowing God | Ian Robson", "", "CFC India"), "Ian Robson")
        self.assertEqual(extract_speaker("Bro. Parisutham - The Body of Christ", "", "CHENNAI CFC"), "Parisutham")

        # Known speakers from title (Tamil)
        self.assertEqual(extract_speaker("இயேசு போதித்த அனைத்தும் | சகோ. சகரியா பூணன்", "", "CHENNAI CFC"), "Zac Poonen")
        self.assertEqual(extract_speaker("மாம்சத்திற்கென்று விதையாதிருப்போம் | சகோ. செல்லையா", "", "CHENNAI CFC"), "Chellaiah")

        # Known speakers from description
        self.assertEqual(extract_speaker("Sunday Sermon", "Preached by Bro. Sam Varghese at Chennai", "CHENNAI CFC"), "Sam Varghese")

        # Heuristic unknown person names
        self.assertEqual(extract_speaker("Special Message | Bro. Arthur Pink", "", "CFC India"), "Arthur Pink")
        self.assertEqual(extract_speaker("General Meeting", "Sharing by Bro. John Wesley during Sunday Service", "CFC Thanjavur"), "John Wesley")

        # Fallback to default speaker when no person name detected
        self.assertEqual(extract_speaker("Sunday Service Live Stream", "Praise and worship", "CFC Thanjavur"), "CFC Thanjavur")

    def test_detect_category(self):
        self.assertEqual(detect_category("CFC Songs & Hymns"), "Songs")
        self.assertEqual(detect_category("Tamil Padalgal"), "Songs")
        self.assertEqual(detect_category("மாசில்லா வாலிபம் Maasilla Valibam"), "Songs")
        self.assertEqual(detect_category("CFC India - Zac Poonen"), "YouTube")
        self.assertEqual(detect_category("CHENNAI CFC"), "YouTube")

    def test_is_short_content(self):
        # By duration
        self.assertTrue(is_short_content("Regular Title", "desc", duration=45, width=1920, height=1080))
        self.assertTrue(is_short_content("Regular Title", "desc", duration=60, width=1920, height=1080))
        self.assertFalse(is_short_content("Full Sermon", "desc", duration=1800, width=1920, height=1080))

        # By aspect ratio (vertical)
        self.assertTrue(is_short_content("Vertical Video", "desc", duration=120, width=1080, height=1920))

        # By hashtag
        self.assertTrue(is_short_content("Great message #shorts", "desc", duration=120, width=1920, height=1080))
        self.assertTrue(is_short_content("Great message", "Check this out #short", duration=120, width=1920, height=1080))
        self.assertFalse(is_short_content("Shortest Path in Grace", "Full description", duration=3600, width=1920, height=1080))

        # Song channels: bypass short duration check if horizontal
        self.assertFalse(is_short_content("Altogether lovely", "Hymn", duration=84, width=1920, height=1080, is_song_channel=True))
        self.assertFalse(is_short_content("King of kings, Majesty", "Song", duration=45, width=1920, height=1080, is_song_channel=True))
        # Song channels: still catch vertical or explicit #shorts
        self.assertTrue(is_short_content("Song clip #shorts", "Hymn", duration=45, width=1920, height=1080, is_song_channel=True))
        self.assertTrue(is_short_content("Song clip", "Hymn", duration=45, width=1080, height=1920, is_song_channel=True))

    def test_slugify(self):
        self.assertEqual(slugify("Zac Poonen Sermons"), "zac_poonen_sermons")
        self.assertEqual(slugify("English Channel (Live!)"), "english_channel_live")
        self.assertEqual(slugify("  ***Special---Talks***  "), "special_talks")
        self.assertEqual(slugify(""), "misc")

    def test_map_language(self):
        self.assertEqual(map_language("en"), "English")
        self.assertEqual(map_language("fr"), "French")
        self.assertEqual(map_language("ta"), "Tamil")
        self.assertEqual(map_language(None), "English")
        self.assertEqual(map_language("italian"), "Italian")

    def test_norm_title(self):
        self.assertEqual(norm_title("  My Sermon (v12345)  "), "my sermon")
        self.assertEqual(norm_title("My Sermon [720p]"), "my sermon")
        self.assertEqual(norm_title(None), "")
        self.assertEqual(norm_title("Grace and Truth"), "grace and truth")

    def test_clean_audiocom_tags(self):
        # Long YouTube tags are truncated to the Audio.com 40-char limit.
        self.assertEqual(
            clean_audiocom_tags([
                "zac poonen cfc Christian Fellowship Church Church Fellowship Christian Zac Poonen",
                "  ",
                "sermon",
            ]),
            [
                "zac poonen cfc Christian Fellowship Chur",
                "sermon",
            ],
        )
        # Deduplicates and caps at the limit.
        self.assertEqual(
            clean_audiocom_tags(["a", "a", "b", "c", "d", "e", "f"]),
            ["a", "b", "c", "d", "e"],
        )
        self.assertEqual(clean_audiocom_tags([]), [])
        self.assertEqual(clean_audiocom_tags(None), [])

    def test_audiocom_collection_resolution(self):
        client = AudioComClient("test_token")

        # Test finding existing collection
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = [
            {"id": "12345", "title": "Zac Poonen Sermons"},
            {"id": "67890", "title": "Another Channel"},
        ]
        client._requests.get = MagicMock(return_value=mock_resp)

        cid = client.get_or_create_collection("Zac Poonen Sermons")
        self.assertEqual(cid, "12345")
        # Should be cached
        self.assertIn("zac poonen sermons", client._collection_cache)

        # Test creating new collection
        create_resp = MagicMock()
        create_resp.status_code = 201
        create_resp.json.return_value = {"id": "99999", "title": "Brand New Channel"}
        client._requests.post = MagicMock(return_value=create_resp)

        new_cid = client.get_or_create_collection("Brand New Channel")
        self.assertEqual(new_cid, "99999")
        client._requests.post.assert_called_once()

    def test_audiocom_add_to_collection(self):
        client = AudioComClient("test_token")
        mock_resp = MagicMock()
        mock_resp.status_code = 204
        client._requests.post = MagicMock(return_value=mock_resp)

        client.add_to_collection("12345", "audio_999")
        client._requests.post.assert_called_once_with(
            "https://api.audio.com/v1/collection/item/add?id=12345",
            headers=client.headers,
            json={"audio": "audio_999"},
            timeout=20,
        )

    def test_upload_audio_sends_metadata_at_create(self):
        client = AudioComClient("test_token")
        tmp = tempfile.NamedTemporaryFile(suffix=".mp3", delete=False)
        tmp.close()
        try:
            create_resp = MagicMock()
            create_resp.status_code = 201
            create_resp.json.return_value = {
                "url": "https://presigned/put",
                "success": "https://api.audio.com/v1/audio/upload/success?id=1&token=t",
                "audio": {"id": "1876", "title": "My Title"},
            }
            ok = MagicMock(status_code=204)
            client.find_existing_title_ids = MagicMock(return_value=[])
            client._resolve_stream_url = MagicMock(return_value="https://stream/1")
            client._requests.post = MagicMock(side_effect=[create_resp, ok])
            client._requests.put = MagicMock(return_value=ok)

            url, stream = client.upload_audio(
                Path(tmp.name),
                {"title": "My Title", "description": "Big desc", "tags": ["a", "b"]},
            )

            create_call = client._requests.post.call_args_list[0]
            create_payload = create_call.kwargs["json"]
            self.assertEqual(create_payload["title"], "My Title")
            self.assertEqual(create_payload["description"], "Big desc")
            self.assertEqual(create_payload["tags"], ["a", "b"])
            self.assertIs(create_payload["is_listed"], True)
            self.assertEqual(create_payload["category"], "podcast")
            # No metadata PUT attempt to /v1/audio/{id} (missing route)
            for call in client._requests.put.call_args_list:
                self.assertNotIn("api.audio.com/v1/audio/", call[0][0])
            self.assertIn("1876", url)
            self.assertEqual(stream, "https://stream/1")
        finally:
            os.unlink(tmp.name)

    def test_upload_audio_reuses_unreferenced_title_match(self):
        client = AudioComClient("test_token")
        tmp = tempfile.NamedTemporaryFile(suffix=".mp3", delete=False)
        tmp.close()
        try:
            client.find_existing_title_ids = MagicMock(return_value=["5555"])
            client.is_audio_live = MagicMock(return_value=True)
            client._resolve_stream_url = MagicMock(return_value="https://stream/5555")
            client._requests = MagicMock()

            url, stream = client.upload_audio(
                Path(tmp.name),
                {"title": "Grace and Truth"},
                referenced_ids={"1111"},
            )
            self.assertEqual(url, "https://audio.com/5555")
            self.assertEqual(stream, "https://stream/5555")
            client._requests.post.assert_not_called()
        finally:
            os.unlink(tmp.name)

    def test_upload_audio_skips_referenced_title_match(self):
        client = AudioComClient("test_token")
        tmp = tempfile.NamedTemporaryFile(suffix=".mp3", delete=False)
        tmp.close()
        try:
            # 5555 is in referenced_ids -> cannot be reused, so a fresh upload happens.
            client.find_existing_title_ids = MagicMock(return_value=["5555"])
            client.is_audio_live = MagicMock(return_value=True)
            client._resolve_stream_url = MagicMock(return_value="https://stream/6666")
            client._requests = MagicMock()

            create_resp = MagicMock()
            create_resp.status_code = 201
            create_resp.json.return_value = {
                "url": "https://presigned/put",
                "success": "https://api.audio.com/v1/audio/upload/success?id=1&token=t",
                "audio": {"id": "6666", "title": "Grace and Truth"},
            }
            ok = MagicMock(status_code=204)
            client._requests.post = MagicMock(side_effect=[create_resp, ok])
            client._requests.put = MagicMock(return_value=ok)

            url, stream = client.upload_audio(
                Path(tmp.name),
                {"title": "Grace and Truth"},
                referenced_ids={"5555"},
            )
            self.assertEqual(url, "https://audio.com/6666")
            self.assertEqual(stream, "https://stream/6666")
        finally:
            os.unlink(tmp.name)


class TestAudioCatalogDb(unittest.TestCase):
    """DB-authors the audio catalog directly in PostgreSQL (no releases repo)."""

    def test_find_audio_track_returns_audio_url(self):
        db, cur = _make_db()
        cur.fetchone.return_value = ("https://audio.com/123",)
        res = db.find_audio_track("series_id", "vid1")
        self.assertEqual(res, {"audioUrl": "https://audio.com/123"})

    def test_find_audio_track_missing(self):
        db, cur = _make_db()
        cur.fetchone.return_value = None
        self.assertIsNone(db.find_audio_track("series_id", "vid1"))

    def test_audio_id_referenced(self):
        db, cur = _make_db()
        cur.fetchone.return_value = (1,)
        self.assertTrue(db.audio_id_referenced("1876636242"))
        sql, params = cur.execute.call_args[0]
        self.assertIn("%audio.com/1876636242%", params[0])

    def test_audio_id_referenced_empty(self):
        db, _ = _make_db()
        self.assertFalse(db.audio_id_referenced(""))
        self.assertFalse(db.audio_id_referenced(None))

    def test_referenced_audio_ids_extracts_digits(self):
        db, cur = _make_db()
        cur.fetchall.return_value = [
            ("https://audio.com/123",),
            ("https://audio.com/abc456",),
        ]
        self.assertEqual(db.referenced_audio_ids(), {"123", "456"})

    def test_delete_audio_track_updates_series_counts(self):
        db, cur = _make_db()
        cur.rowcount = 1
        self.assertTrue(db.delete_audio_track("series_id", "vid1"))

    def test_upsert_audio_series_and_track_registers_rows(self):
        db, cur = _make_db()
        db.upsert_audio_series_and_track(
            series_id="cfc_india",
            series_title="CFC India",
            series_description="Audio sermons from CFC India",
            series_speaker="Zac Poonen",
            series_category="YouTube",
            series_language="English",
            cover_url="https://img/thumb",
            channel_id="UC_1",
            published_at="2026-09-11T00:00:00Z",
            track={
                "id": "vid123",
                "title": "Grace and Truth",
                "speaker": "Zac Poonen",
                "youtubeVideoId": "vid123",
                "thumbnailUrl": "https://img/thumb",
                "publishedAt": "2026-09-11T00:00:00Z",
                "durationSeconds": 1800,
                "audioUrl": "https://audio.com/123",
                "streamUrl": "https://stream/123",
            },
        )
        # series upsert + track upsert + series recount
        self.assertEqual(cur.execute.call_count, 3)
        inserts = [c[0][0] for c in cur.execute.call_args_list]
        self.assertTrue(any('INSERT INTO "AudioSeries"' in s for s in inserts))
        self.assertTrue(any('INSERT INTO "AudioTrack"' in s for s in inserts))


class TestDailyRetryPolicy(unittest.TestCase):
    """Per-day retry budget: failed videos retried daily until one passes,
    permanent failures marked 'dead' so they are never retried."""

    def test_mark_failed_transient_keeps_failed_status(self):
        db, cur = _make_db()
        db.mark_failed("vid1", "yt-dlp extraction failed: too many requests")
        sql, params = cur.execute.call_args[0]
        self.assertIn("'failed'", sql)
        self.assertNotIn("'dead'", sql)
        self.assertEqual(params[0], "yt-dlp extraction failed: too many requests")
        self.assertEqual(params[1], "vid1")

    def test_mark_failed_permanent_sets_dead_status(self):
        db, cur = _make_db()
        db.mark_failed("vid1", "ERROR: This video is not available", permanent=True)
        sql, params = cur.execute.call_args[0]
        self.assertIn("'dead'", sql)
        self.assertNotIn("'failed'", sql)

    def test_mark_failed_increments_retry_count(self):
        db, cur = _make_db()
        db.mark_failed("vid1", "desc")
        sql, params = cur.execute.call_args[0]
        self.assertIn("ELSE COALESCE(\"audioRetryCount\", 0) + 1", sql)

    def test_mark_completed_resets_retry_state(self):
        db, cur = _make_db()
        db.mark_completed("vid1", "https://audio.com/123")
        sql, params = cur.execute.call_args[0]
        self.assertIn('"audioUploadStatus"=\'completed\'', sql)
        self.assertIn('"audioRetryCount"=0', sql)
        self.assertIn('"audioLastRetryAt"=NULL', sql)

    def test_batch_mark_completed_resets_retry_state(self):
        db, cur = _make_db()
        captured = {}
        def fake_execute_values(cursor, sql, argslist, template=None, page_size=100, fetch=False):
            captured["sql"] = sql
            captured["args"] = argslist
        with patch("psycopg2.extras.execute_values", side_effect=fake_execute_values):
            db.batch_mark_completed([("vid1", "https://audio.com/1"), ("vid2", "https://audio.com/2")])
        sql = captured["sql"]
        self.assertIn('"audioRetryCount"=0', sql)
        self.assertIn('"audioLastRetryAt"=NULL', sql)
        self.assertIn("FROM (VALUES %s)", sql)
        self.assertEqual(captured["args"], [("vid1", "https://audio.com/1"), ("vid2", "https://audio.com/2")])

    def test_is_permanent_failure_classifies_terminal_errors(self):
        terminal = [
            "ERROR: This video is not available",
            "ERROR: This video has been removed by the uploader",
            "Video unavailable",
            "This video is private",
            "Sign in to confirm your age",
            "This video is not available in your country",
            "UNSUPPORTED URL: https://youtu.be/xyz",
            "This video does not exist",
            "Copyright claim: video taken down",
        ]
        for err in terminal:
            self.assertTrue(is_permanent_failure(err), f"expected terminal: {err}")

    def test_is_permanent_failure_keeps_transient_errors(self):
        transient = [
            "yt-dlp extraction failed: too many requests",
            "HTTP Error 403: Forbidden",
            "Audio.com create failed: 500 Internal Server Error",
            "Timed out after 30s",
            "No eligible videos found",
        ]
        for err in transient:
            self.assertFalse(is_permanent_failure(err), f"expected transient: {err}")

    def test_is_permanent_failure_handles_empty(self):
        self.assertFalse(is_permanent_failure(None))
        self.assertFalse(is_permanent_failure(""))
        self.assertFalse(is_permanent_failure("   "))


class TestProcessVideo(unittest.TestCase):
    """process_video: title-match first, no download when an orphan matches."""

    def test_title_match_registers_without_download(self):
        db = MagicMock(spec=Database)
        audiocom = MagicMock(spec=AudioComClient)
        cfg = Config(
            database_url="x",
            audio_com_token="x",
            work_dir=Path("."),
        )
        row = ("vid1", "Grace and Truth", "CFC India", "2026-09-11T00:00:00Z",
               "desc", "en", "UC_1", "30:00", "https://img/thumb")

        db.find_audio_track.return_value = None
        db.referenced_audio_ids.return_value = {"1111"}
        audiocom.find_existing_title_ids.return_value = ["5555"]
        audiocom.is_audio_live.return_value = True
        audiocom._resolve_stream_url.return_value = "https://stream/5555"

        with patch("worker.extract_audio") as mock_extract:
            res = process_video(db, audiocom, cfg, row)

        self.assertEqual(res, ("vid1", "https://audio.com/5555"))
        mock_extract.assert_not_called()
        db.upsert_audio_series_and_track.assert_called_once()

    def test_permanent_error_marks_dead(self):
        db = MagicMock(spec=Database)
        audiocom = MagicMock(spec=AudioComClient)
        cfg = Config(
            database_url="x",
            audio_com_token="x",
            work_dir=Path("."),
        )
        row = ("vid1", "Grace", "CFC India", "2026-09-11T00:00:00Z",
               "", "en", "UC_1", "30:00", None)

        db.find_audio_track.return_value = None
        db.referenced_audio_ids.return_value = set()
        audiocom.find_existing_title_ids.return_value = []

        with patch("worker.extract_audio", side_effect=RuntimeError("ERROR: This video is not available")):
            res = process_video(db, audiocom, cfg, row)

        self.assertIsNone(res)
        db.mark_failed.assert_called_once_with("vid1", "ERROR: This video is not available", permanent=True)


class TestFetchEligiblePriority(unittest.TestCase):
    """Channel-priority ordering in the eligible-videos query."""

    def test_priority_order_clause_included(self):
        db, cur = _make_db()
        cfg = Config(
            database_url="x",
            audio_com_token="x",
            work_dir=Path("."),
            priority_channel_ids=["UCpZG4Vl2tqg5cIfGMocI2Ag"],
        )
        db.fetch_eligible_videos(cfg)
        sql = cur.execute.call_args[0][0]
        self.assertIn(
            'CASE WHEN v."channelId" = ANY(%s::text[]) THEN 0 ELSE 1 END',
            sql,
        )
        self.assertIn(["UCpZG4Vl2tqg5cIfGMocI2Ag"], cur.execute.call_args[0][1])

    def test_language_tier_and_video_count_ordering(self):
        db, cur = _make_db()
        cfg = Config(
            database_url="x",
            audio_com_token="x",
            work_dir=Path("."),
        )
        db.fetch_eligible_videos(cfg)
        sql = cur.execute.call_args[0][0]
        self.assertIn('CASE c.language', sql)
        self.assertIn("WHEN 'Tamil' THEN 0", sql)
        self.assertIn("WHEN 'English' THEN 1", sql)
        self.assertIn('vc.video_count DESC', sql)
        self.assertIn('LEFT JOIN (', sql)
        # Shorts are eligible: no type restriction and no #short filters.
        self.assertNotIn("v.type = 'VIDEO'", sql)
        self.assertNotIn('#short', sql)

    def test_priority_order_clause_omitted_when_unset(self):
        db, cur = _make_db()
        cfg = Config(
            database_url="x",
            audio_com_token="x",
            work_dir=Path("."),
        )
        db.fetch_eligible_videos(cfg)
        sql = cur.execute.call_args[0][0]
        self.assertNotIn("ANY(%s::text[])", sql)

    def test_tokens_substituted_from_sql_file(self):
        db, cur = _make_db()
        cfg = Config(
            database_url="x",
            audio_com_token="x",
            work_dir=Path("."),
            priority_channel_ids=["UCpZG4Vl2tqg5cIfGMocI2Ag"],
        )
        db.fetch_eligible_videos(cfg)
        sql = cur.execute.call_args[0][0]
        for token in ["{status_ph}", "{retry_clause}", "{channel_clause}", "{priority_clause}"]:
            self.assertNotIn(token, sql)
        # LIMIT stays as a psycopg2 %s parameter.
        self.assertIn("LIMIT %s", sql)

    def test_retry_clause_gate_included(self):
        db, cur = _make_db()
        cfg = Config(
            database_url="x",
            audio_com_token="x",
            work_dir=Path("."),
        )
        db.fetch_eligible_videos(cfg)
        sql = cur.execute.call_args[0][0]
        # Failed videos retry when last attempt was a previous day or budget left.
        self.assertIn("audioLastRetryAt", sql)
        self.assertIn("audioUploadStatus", sql)
        self.assertIn("audioRetryCount", sql)

    def test_eligible_sql_env_override(self):
        custom = Path(__file__).parent / "custom_eligible.sql"
        custom.write_text(
            'SELECT 1 FROM "Video" WHERE y = %s AND z = %s LIMIT %s',
            encoding="utf-8",
        )
        try:
            with patch.dict(os.environ, {"ELIGIBLE_SQL_PATH": str(custom.resolve())}):
                db, cur = _make_db()
                cfg = Config(
                    database_url="x",
                    audio_com_token="x",
                    work_dir=Path("."),
                )
                db.fetch_eligible_videos(cfg)
                sql = cur.execute.call_args[0][0]
                self.assertIn("SELECT 1 FROM", sql)
                self.assertNotIn("CASE c.language", sql)
        finally:
            custom.unlink(missing_ok=True)

    def test_marker_guard_catches_bad_sql(self):
        custom = Path(__file__).parent / "custom_eligible.sql"
        custom.write_text(
            "SELECT 1 FROM \"Video\" WHERE x = %s AND y = %s AND z = %s LIMIT %s",
            encoding="utf-8",
        )
        try:
            with patch.dict(os.environ, {"ELIGIBLE_SQL_PATH": str(custom.resolve())}):
                db, cur = _make_db()
                cfg = Config(
                    database_url="x",
                    audio_com_token="x",
                    work_dir=Path("."),
                )
                with self.assertRaisesRegex(RuntimeError, "parameter marker"):
                    db.fetch_eligible_videos(cfg)
        finally:
            custom.unlink(missing_ok=True)

    def test_load_config_parses_priority_ids(self):
        args = MagicMock()
        args.channels = None
        args.limit = None
        args.redo = False
        args.retry_failed = False
        args.once = False
        args.video_id = None
        args.purge_audiocom = False
        with patch(
            "os.environ",
            {
                "DATABASE_URL": "postgresql://user:pass@host/db",
                "AUDIO_COM_TOKEN": "aud",
                "PRIORITY_CHANNEL_IDS": "UCpZG4Vl2tqg5cIfGMocI2Ag,UC_OTHER",
            },
        ):
            cfg = load_config(args)
        self.assertEqual(
            cfg.priority_channel_ids,
            ["UCpZG4Vl2tqg5cIfGMocI2Ag", "UC_OTHER"],
        )


if __name__ == "__main__":
    unittest.main()