import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "MacShell" / "macshell-update"

# Stub curl: the URL is the last argument; MacShell/VERSION answers $STUB_REMOTE_VERSION, everything else fails.
CURL_STUB = """#!/bin/sh
for url; do :; done
case "$url" in
    */MacShell/VERSION) printf '%s\\n' "$STUB_REMOTE_VERSION" ;;
    *) exit 22 ;;
esac
"""


class MacShellUpdateTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        tmp = Path(self._tmp.name)
        # Installed layout: the script sits in bin/ without a VERSION next to it.
        (tmp / "bin").mkdir()
        self.script = tmp / "bin" / "macshell-update"
        shutil.copy(SCRIPT, self.script)
        dest = tmp / "config" / "quickshell" / "MacShell"
        dest.mkdir(parents=True)
        (dest / "VERSION").write_text("0.5.3\n")
        (tmp / "stub").mkdir()
        curl = tmp / "stub" / "curl"
        curl.write_text(CURL_STUB)
        curl.chmod(0o755)
        self.env = {
            **os.environ,
            "PATH": f"{tmp / 'stub'}:{os.environ['PATH']}",
            "XDG_CONFIG_HOME": str(tmp / "config"),
            "XDG_DATA_HOME": str(tmp / "data"),
        }
        self.env.pop("MACSHELL_DEST", None)

    def run_script(self, *args, remote="0.5.3"):
        env = {**self.env, "STUB_REMOTE_VERSION": remote}
        return subprocess.run(["bash", str(self.script), *args], env=env, capture_output=True, text=True)

    def test_status_reads_installed_version_from_dest(self):
        r = self.run_script("status")
        self.assertIn("installed : 0.5.3", r.stdout)

    def test_check_uptodate_via_macshell_version(self):
        r = self.run_script("check", "--json")
        self.assertEqual(r.returncode, 0, r.stderr)
        for part in ('"status":"uptodate"', '"installed":"0.5.3"', '"latest":"0.5.3"'):
            self.assertIn(part, r.stdout)

    def test_check_update_available(self):
        r = self.run_script("check", remote="0.6.0")
        self.assertEqual(r.returncode, 10, r.stdout + r.stderr)
        self.assertIn("0.5.3 -> 0.6.0", r.stdout)


if __name__ == "__main__":
    unittest.main()
