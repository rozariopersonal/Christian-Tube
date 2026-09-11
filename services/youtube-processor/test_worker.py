import json
import sys
from pathlib import Path
import unittest
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).parent))

from worker import (
    slugify,
    map_language,
    AudioComClient,
    GitHubRepo,
    update_channel_audio_catalog,
)


class TestWorkerCollections(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
