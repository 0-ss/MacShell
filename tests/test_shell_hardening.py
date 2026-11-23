import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
GAMING = ROOT / "hypr-macshell" / "scripts" / "macshell-gaming.sh"
GREETER = ROOT / "MacGreeter" / "macshell-greeter"


class GamingScriptTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.bin = self.dir / "bin"
        self.bin.mkdir()
        self.calls = self.dir / "calls"
        for name in ("hyprctl", "pkill"):
            self.stub(name, "exit 0")
        self.stub("powerprofilesctl", f'echo "powerprofilesctl $*" >> "{self.calls}"\n[ "$1" = get ] && echo balanced; exit 0')

    def stub(self, name, body):
        p = self.bin / name
        p.write_text("#!/bin/sh\n" + body + "\n")
        p.chmod(0o755)

    def run_script(self, arg, **env_extra):
        env = {"PATH": f"{self.bin}:{os.environ['PATH']}", "HOME": str(self.dir / "home")}
        env.update(env_extra)
        return subprocess.run(["sh", str(GAMING), arg], env=env, capture_output=True, text=True, timeout=20)

    def test_off_does_not_execute_state_file(self):
        rt = self.dir / "rt"
        rt.mkdir()
        state = rt / "macshell-gaming.state"
        state.write_text(
            f"blur=$(touch {self.dir}/pwned)\n"
            f"profile=balanced; touch {self.dir}/pwned2\n"
        )
        r = self.run_script("off", XDG_RUNTIME_DIR=str(rt))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse((self.dir / "pwned").exists())
        self.assertFalse((self.dir / "pwned2").exists())
        self.assertFalse(self.calls.exists() and "set balanced;" in self.calls.read_text())
        self.assertFalse(self.calls.exists() and "pwned2" in self.calls.read_text())
        self.assertFalse(state.exists())

    def test_off_restores_valid_profile(self):
        rt = self.dir / "rt"
        rt.mkdir()
        (rt / "macshell-gaming.state").write_text("blur=1\nshadow=1\nanim=1\nprofile=power-saver\n")
        self.run_script("off", XDG_RUNTIME_DIR=str(rt))
        self.assertIn("powerprofilesctl set power-saver", self.calls.read_text())

    def test_on_without_runtime_dir_uses_state_home_not_tmp(self):
        state_home = self.dir / "state"
        env = {"XDG_STATE_HOME": str(state_home)}
        r = self.run_script("on", **env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((state_home / "macshell" / "macshell-gaming.state").is_file())
        self.assertEqual(oct((state_home / "macshell").stat().st_mode & 0o777), "0o700")
        self.assertEqual(self.run_script("status", **env).stdout.strip(), "on")


class NoTmpFallbackTest(unittest.TestCase):
    def test_no_tmp_default(self):
        for script in (GREETER, GAMING):
            self.assertNotIn(":-/tmp", script.read_text(), script.name)


if __name__ == "__main__":
    unittest.main()
