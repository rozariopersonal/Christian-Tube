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
    AudioComClient,
    GitHubRepo,
    update_channel_audio_catalog,
    Config,
    Database,
    load_config,
)


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
            client.find_existing_track_id = MagicMock(return_value=None)
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

    def test_update_channel_audio_catalog(self):
        storage = {}

        def mock_read(path):
            return storage.get(path)

        def mock_upsert(path, content, message):
            storage[path] = content

        repo = MagicMock(spec=GitHubRepo)
        repo.read_text_or_none.side_effect = mock_read
        repo.upsert.side_effect = mock_upsert

        # Seed existing catalog with old audiocom_uploads
        storage["audio/catalog.json"] = json.dumps([
            {"id": "audiocom_uploads", "title": "Audio.com Uploads", "trackCount": 1},
            {"id": "through_the_bible", "title": "Through the Bible", "trackCount": 50},
        ])

        track = {
            "id": "vid123",
            "title": "Grace and Truth",
            "speaker": "Zac Poonen",
            "youtubeVideoId": "vid123",
            "thumbnailUrl": "https://img.youtube.com/vi/vid123/hqdefault.jpg",
            "publishedAt": "2026-09-11T00:00:00Z",
            "durationSeconds": 1800,
            "audioUrl": "https://audio.com/123",
        }

        update_channel_audio_catalog(
            repo,
            channel_name="Zac Poonen Sermons",
            channel_lang="en",
            track=track,
        )

        # Verify channel series file
        series_file = "audio/series/zac_poonen_sermons.json"
        self.assertIn(series_file, storage)
        series_data = json.loads(storage[series_file])
        self.assertEqual(series_data["id"], "zac_poonen_sermons")
        self.assertEqual(series_data["title"], "Zac Poonen Sermons")
        self.assertEqual(series_data["trackCount"], 1)
        self.assertEqual(series_data["tracks"][0]["seriesId"], "zac_poonen_sermons")
        self.assertEqual(series_data["tracks"][0]["seriesTitle"], "Zac Poonen Sermons")

        # Verify catalog.json updated and audiocom_uploads removed
        cat_data = json.loads(storage["audio/catalog.json"])
        cat_ids = [s["id"] for s in cat_data]
        self.assertNotIn("audiocom_uploads", cat_ids)
        self.assertIn("zac_poonen_sermons", cat_ids)
        self.assertIn("through_the_bible", cat_ids)

        # Verify manifest.json bumped
        self.assertIn("manifest.json", storage)
        manifest_data = json.loads(storage["manifest.json"])
        self.assertTrue(bool(manifest_data.get("revision")))


class TestFetchEligiblePriority(unittest.TestCase):
    """Channel-priority ordering in the eligible-videos query (mirrors content-worker)."""

    def _make_db(self):
        with patch("psycopg2.connect") as mock_connect:
            conn = MagicMock()
            cur = MagicMock()
            mock_connect.return_value = conn
            conn.cursor.return_value = cur
            conn.autocommit = True
            return Database("postgresql://user:pass@host/db?sslmode=require"), cur

    def test_priority_order_clause_included(self):
        db, cur = self._make_db()
        cfg = Config(
            database_url="x",
            github_repo="x",
            github_token="x",
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
        db, cur = self._make_db()
        cfg = Config(
            database_url="x",
            github_repo="x",
            github_token="x",
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
        db, cur = self._make_db()
        cfg = Config(
            database_url="x",
            github_repo="x",
            github_token="x",
            audio_com_token="x",
            work_dir=Path("."),
        )
        db.fetch_eligible_videos(cfg)
        sql = cur.execute.call_args[0][0]
        self.assertNotIn("ANY(%s::text[])", sql)

    def test_tokens_substituted_from_sql_file(self):
        db, cur = self._make_db()
        cfg = Config(
            database_url="x",
            github_repo="x",
            github_token="x",
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

    def test_eligible_sql_env_override(self):
        custom = Path(__file__).parent / "custom_eligible.sql"
        custom.write_text(
            'SELECT 1 FROM "Video" WHERE y = %s LIMIT %s',
            encoding="utf-8",
        )
        try:
            with patch.dict(os.environ, {"ELIGIBLE_SQL_PATH": str(custom.resolve())}):
                db, cur = self._make_db()
                cfg = Config(
                    database_url="x",
                    github_repo="x",
                    github_token="x",
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
            "SELECT 1 FROM \"Video\" WHERE x = %s AND y = %s LIMIT %s",
            encoding="utf-8",
        )
        try:
            with patch.dict(os.environ, {"ELIGIBLE_SQL_PATH": str(custom.resolve())}):
                db, cur = self._make_db()
                cfg = Config(
                    database_url="x",
                    github_repo="x",
                    github_token="x",
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
                "GITHUB_TOKEN": "tok",
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
