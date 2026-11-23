import importlib.util
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("spotlight_search", ROOT / "MacShell" / "assets" / "spotlight-search.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class SpotlightSearchTests(unittest.TestCase):
    def test_search_matches_filename_and_fulltext_content(self):
        with tempfile.TemporaryDirectory() as d:
            docs = pathlib.Path(d) / "Documents"
            docs.mkdir()
            (docs / "roadmap-notes.md").write_text("# Plan\nUniqueTokenAlpha123 in body\n", encoding="utf-8")
            (docs / "other.txt").write_text("just plain text\n", encoding="utf-8")
            hits_name = mod.search_files("roadmap", d)
            self.assertTrue(any(h["path"].endswith("roadmap-notes.md") for h in hits_name))
            hits_body = mod.search_files("UniqueTokenAlpha123", d)
            if mod.shutil.which("rg"):
                self.assertTrue(any("UniqueTokenAlpha123" in h["snippet"] for h in hits_body))

    def test_read_preview_text_and_directory(self):
        with tempfile.TemporaryDirectory() as d:
            p = pathlib.Path(d) / "hello.py"
            p.write_text("print('hi')\n", encoding="utf-8")
            res = mod.read_preview(str(p))
            self.assertTrue(res["ok"])
            self.assertEqual(res["kind"], "text")
            self.assertIn("print('hi')", res["text"])
            dres = mod.read_preview(d)
            self.assertTrue(dres["ok"])
            self.assertEqual(dres["kind"], "dir")
            self.assertIn("hello.py", dres["text"])


if __name__ == "__main__":
    unittest.main()
