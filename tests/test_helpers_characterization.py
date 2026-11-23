"""Characterization tests for small helpers: pure logic only, no network, no live Hyprland."""
import importlib.util
import os
import pathlib
import tempfile
import time
import unittest
from importlib.machinery import SourceFileLoader
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parent.parent


def load(name, path, loader=None):
    spec = importlib.util.spec_from_file_location(name, ROOT / path, loader=loader(name, str(ROOT / path)) if loader else None)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


canvas = load("canvas_fetcher", "MacLock/canvas_fetcher.py")
genie = load("macshell_genie", "contrib/genie/macshell-genie", SourceFileLoader)
sysmon = load("sysmon_reader", "MacShell/sysmon_reader.py")


class CanvasFetcherTests(unittest.TestCase):
    def test_prune_keeps_newest_within_count_and_bytes_and_ignores_dotfiles(self):
        with tempfile.TemporaryDirectory() as d:
            folder = pathlib.Path(d)
            now = time.time()
            for i, name in enumerate(["old", "mid", "new"]):
                p = folder / name
                p.write_bytes(b"x" * 10)
                os.utime(p, (now + i, now + i))
            (folder / ".hidden").write_bytes(b"x" * 1000)
            canvas.prune(folder, 2, 1000)
            self.assertEqual(sorted(p.name for p in folder.iterdir()), [".hidden", "mid", "new"])
            canvas.prune(folder, 5, 15)  # byte limit: only the newest 10-byte file fits
            self.assertEqual(sorted(p.name for p in folder.iterdir()), [".hidden", "new"])

    def test_select_variant_picks_highest_bandwidth_under_cap_on_apple_only(self):
        base = "https://mvod.itunes.apple.com/p/master.m3u8"
        playlist = (
            "#EXTM3U\n"
            "#EXT-X-STREAM-INF:BANDWIDTH=1000000\nlow.m3u8\n"
            "#EXT-X-STREAM-INF:BANDWIDTH=4000000\nmid.m3u8\n"
            "#EXT-X-STREAM-INF:BANDWIDTH=9000000\nhigh.m3u8\n"
            "#EXT-X-STREAM-INF:BANDWIDTH=4400000\nhttps://evil.example/x.m3u8\n"
        )
        with mock.patch.object(canvas, "read_url", return_value=playlist.encode()):
            self.assertEqual(canvas.select_variant(base), "https://mvod.itunes.apple.com/p/mid.m3u8")
        with mock.patch.object(canvas, "read_url", return_value=b"#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nhttps://evil.example/x.m3u8\n"):
            self.assertEqual(canvas.select_variant(base), base)

    def test_read_url_rejects_non_http(self):
        with self.assertRaises(ValueError):
            canvas.read_url("file:///etc/passwd", 1024)


class GenieTests(unittest.TestCase):
    def test_valid_address(self):
        self.assertTrue(genie.valid_address("0x55a1b2c3"))
        for bad in ("0x1; rm", "", None):
            self.assertFalse(genie.valid_address(bad))

    def test_state_round_trip_drops_malformed_entries(self):
        with tempfile.TemporaryDirectory() as d, mock.patch.object(genie, "STATE", pathlib.Path(d) / "genie.json"):
            genie.save({"0xab": [1, 2], "0xcd": [3, "x"], "0xef": [1, 2, 3], "bad": [1, 2]})
            self.assertEqual(genie.load(), {"0xab": [1, 2]})
            genie.save({"0x1": [-5, 7]})
            self.assertEqual(genie.load(), {"0x1": [-5, 7]})


class SysmonTests(unittest.TestCase):
    def test_get_sysmon_shape_ranges_and_state_file(self):
        with tempfile.TemporaryDirectory() as d:
            state_dir = pathlib.Path(d) / "macshell"
            with mock.patch.object(sysmon, "STATE_DIR", state_dir), mock.patch.object(sysmon, "STATE_FILE", state_dir / "sysmon.json"):
                data = sysmon.get_sysmon()
                for key in ("cpu", "gpu", "ram", "ram_used", "ram_total", "disk", "disk_used", "disk_free", "disk_total", "temp", "net"):
                    self.assertIn(key, data)
                for key in ("cpu", "ram", "disk"):
                    self.assertTrue(0 <= data[key] <= 100, key)
                self.assertEqual(os.listdir(state_dir), ["sysmon.json"])


if __name__ == "__main__":
    unittest.main()
