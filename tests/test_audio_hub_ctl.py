import importlib.machinery
import importlib.util
import os
import socket
import tempfile
import threading
import unittest
from unittest import mock

ASSETS = os.path.join(os.path.dirname(__file__), "..", "MacShell", "assets")


def load(name):
    path = os.path.join(ASSETS, name)
    loader = importlib.machinery.SourceFileLoader(name.replace("-", "_"), path)
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


discord = load("mac-discord-ctl")
earbuds = load("mac-earbuds-ctl")


class DiscordToggleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        patches = [
            mock.patch.object(discord, "STATE_FILE", os.path.join(self.tmp.name, "state.json")),
            mock.patch.object(discord, "run_cmd", return_value=""),
            mock.patch.object(discord, "get_pw_state", return_value=([], [])),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)
        self.shortcut = mock.patch.object(discord, "send_discord_shortcut").start()
        self.addCleanup(mock.patch.stopall)

    def test_mute_shortcut_only_on_transition(self):
        discord.toggle_mute("1")
        self.assertEqual(self.shortcut.call_count, 1)
        discord.toggle_mute("1")
        self.assertEqual(self.shortcut.call_count, 1)
        discord.toggle_mute("0")
        self.assertEqual(self.shortcut.call_count, 2)

    def test_deaf_shortcut_only_on_transition(self):
        discord.toggle_deaf("1")
        self.assertEqual(self.shortcut.call_count, 1)
        discord.toggle_deaf("1")
        self.assertEqual(self.shortcut.call_count, 1)
        discord.toggle_deaf("0")
        self.assertEqual(self.shortcut.call_count, 2)

    def test_save_state_leaves_no_temp_files(self):
        discord.save_state({"muted": True})
        self.assertEqual(os.listdir(self.tmp.name), ["state.json"])


class EarbudsTests(unittest.TestCase):
    def ask_daemon(self, reply):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        path = os.path.join(tmp.name, "s.sock")
        srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        srv.bind(path)
        srv.listen(1)
        self.addCleanup(srv.close)

        def serve():
            conn, _ = srv.accept()
            conn.recv(1024)
            if reply:
                conn.sendall(reply)
            conn.close()

        t = threading.Thread(target=serve, daemon=True)
        t.start()
        with mock.patch.object(earbuds, "UNIX_SOCK_PATH", path):
            result = earbuds.send_via_daemon("noise", "anc")
        t.join(2)
        return result

    def test_send_via_daemon_ack(self):
        self.assertTrue(self.ask_daemon(b"OK\n"))
        self.assertFalse(self.ask_daemon(b"ERR\n"))
        self.assertFalse(self.ask_daemon(b""))

    def test_spp_packet_crc_round_trip(self):
        pkt = earbuds.build_samsung_spp_packet(0x78, bytes([0x01]))
        self.assertEqual(pkt[0], 0xFD)
        self.assertEqual(pkt[-1], 0xDD)
        pkt_len = int.from_bytes(pkt[1:3], "little")
        body = pkt[3 : 3 + pkt_len - 2]
        crc = int.from_bytes(pkt[3 + pkt_len - 2 : 3 + pkt_len], "little")
        self.assertEqual(body, bytes([0x78, 0x01]))
        self.assertEqual(earbuds.crc16_ccitt(body), crc)


if __name__ == "__main__":
    unittest.main()
