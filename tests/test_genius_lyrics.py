import importlib.util
import json
import os
import tempfile
from unittest import mock
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("genius_lyrics", ROOT / "MacLock" / "genius-lyrics.py")
genius = importlib.util.module_from_spec(spec)
spec.loader.exec_module(genius)

HTML = """
<html><body><div class="Header">Nav junk</div>
<div data-lyrics-container="true" class="Lyrics__Container-sc-1">
  <div data-exclude-from-selection="true"><div>12 Contributors</div><span>Read More</span></div>
  [Verse 1]<br/>First <a href="#"><span>line</span></a><br/>Second line<br/>
</div>
<div class="Ad">Advertisement</div>
<div data-lyrics-container="true" class="Lyrics__Container-sc-1">
  [Chorus]<br/>Third line<br/><br/>Fourth line
</div>
<div class="Footer">You might also like</div>
<footer>Footer junk</footer>
</body></html>
"""


class WriteCacheAtomicTests(unittest.TestCase):
    def test_writes_valid_json_and_leaves_no_temp_file(self):
        with tempfile.TemporaryDirectory() as d:
            target = os.path.join(d, "genius_x.json")
            genius.write_cache_atomic(target, {"plain": "ä", "lines": []})
            self.assertEqual(json.load(open(target, encoding="utf-8")), {"plain": "ä", "lines": []})
            self.assertEqual(os.listdir(d), ["genius_x.json"])

    def test_failure_removes_temp_file(self):
        with tempfile.TemporaryDirectory() as d:
            target = os.path.join(d, "genius_x.json")
            with self.assertRaises(TypeError):
                genius.write_cache_atomic(target, {"bad": object()})
            self.assertEqual(os.listdir(d), [])
            with mock.patch.object(genius.os, "replace", side_effect=OSError), self.assertRaises(OSError):
                genius.write_cache_atomic(target, {"ok": 1})
            self.assertEqual(os.listdir(d), [])


class GeniusTests(unittest.TestCase):
    def test_only_lyrics_are_extracted(self):
        p = genius.GeniusLyricsParser()
        p.feed(HTML)
        self.assertEqual(
            p.get_lyrics(),
            "[Verse 1]\nFirst line\nSecond line\n\n[Chorus]\nThird line\n\nFourth line",
        )

    def test_cache_key_non_latin_distinct(self):
        k = genius.cache_key_for
        self.assertNotEqual(k("米津玄師", "Lemon"), k("米津玄師", "Kick Back"))
        self.assertNotEqual(k("Кино", "Группа крови"), k("Кино", "Звезда"))

    def test_cache_key_normalised(self):
        k = genius.cache_key_for
        self.assertEqual(k(" Queen ", "Bohemian Rhapsody"), k("queen", "bohemian rhapsody "))

    def test_scripts_identical(self):
        self.assertEqual((ROOT / "MacLock/genius-lyrics.py").read_bytes(),
                         (ROOT / "MacShell/genius-lyrics.py").read_bytes())


if __name__ == "__main__":
    unittest.main()
