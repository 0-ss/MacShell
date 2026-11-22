import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "MacShell" / "assets" / "screenshot-search.py"


@unittest.skipUnless(shutil.which("magick"), "requires ImageMagick")
class ScreenshotSearchTest(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.home = Path(scratch.name)
        self.desktop = self.home / "Desktop"
        self.desktop.mkdir()
        self.folder = self.home / "Pictures" / "Screenshots"
        self.folder.mkdir(parents=True)
        self.env = {**os.environ, "HOME": str(self.home),
                    "XDG_CONFIG_HOME": str(self.home / ".config"),
                    "XDG_CACHE_HOME": str(self.home / ".cache"),
                    "MACSHELL_SCREENSHOT_VISION_PORT": "0"}

    def run_tool(self, *args, port="0"):
        result = subprocess.check_output([sys.executable, str(SCRIPT), *args],
                                         env={**self.env, "MACSHELL_SCREENSHOT_VISION_PORT": port},
                                         text=True, timeout=120)
        return json.loads(result)

    def paths(self, query):
        return [Path(hit["path"]) for hit in self.run_tool("search", "--", query)]

    def write_text_capture(self, path, text):
        subprocess.run(["magick", "-size", "1000x240", "xc:white", "-font", "DejaVu-Sans",
                        "-pointsize", "52", "-fill", "black", "-gravity", "center",
                        "-annotate", "+0+0", text, str(path)], check=True)

    @unittest.skipUnless(shutil.which("tesseract"), "requires Tesseract and English language data")
    def test_finds_text_in_original_and_reindexes_changed_file(self):
        shot = self.desktop / "Screenshot-2026-11-22_16-25-00.png"
        self.write_text_capture(shot, "Rare Quartz Token 7425")
        shutil.copyfile(shot, self.desktop / "personal-photo.png")
        (self.folder / "linked.png").symlink_to(shot)
        self.assertEqual(self.paths("quartz 7425"), [])
        self.run_tool("index")
        self.assertEqual(self.paths("quartz 7425"), [shot])
        self.assertEqual(self.paths(""), [shot])
        self.write_text_capture(shot, "Marine Compass 9331")
        self.run_tool("index")
        self.assertEqual(self.paths("quartz 7425"), [])
        self.assertEqual(self.paths("compass 9331"), [shot])
        shot.unlink()
        self.assertEqual(self.paths("compass 9331"), [])
        self.run_tool("index")
        self.assertEqual(self.paths(""), [])

    def test_finds_new_capture_in_a_configured_folder(self):
        custom = self.home / "My Captures"
        custom.mkdir()
        self.run_tool("index", "--folder", str(custom))
        shot = custom / "window-picker.png"
        self.write_text_capture(shot, "Window picker")
        self.run_tool("index", "--folder", str(custom))
        self.assertEqual(self.paths("window"), [shot])
        self.run_tool("index")
        self.assertEqual(self.paths("window"), [])

    @unittest.skipUnless(os.environ.get("MACSHELL_TEST_VISION_PORT"), "requires a local vision server")
    def test_finds_visual_content_in_an_image_without_text(self):
        shot = self.folder / "mystery.png"
        subprocess.run(["magick", "-size", "800x500", "xc:white", "-stroke", "#086aff",
                        "-strokewidth", "20", "-fill", "none", "-draw",
                        "polyline 72,410 175,270 280,348 455,180 610,230 730,75",
                        "-stroke", "black", "-strokewidth", "4", "-draw",
                        "polyline 55,65 55,430 750,430", str(shot)], check=True)
        self.run_tool("index")
        self.assertEqual(self.paths("blauer graph"), [])
        self.run_tool("index", port=os.environ["MACSHELL_TEST_VISION_PORT"])
        self.assertEqual(self.paths("blauer graph"), [shot])
        hit, = self.run_tool("search", "blauer graph")
        self.assertTrue(hit["title"] and hit["description"] and hit["tags"])
        self.assertEqual(self.paths("#" + hit["tags"][0].split()[0]), [shot])


if __name__ == "__main__":
    unittest.main()
