import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("appmenu_bridge", ROOT / "MacShell" / "assets" / "appmenu-bridge.py")
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class AppMenuBridgeTests(unittest.TestCase):
    def test_clean_mnemonic(self):
        self.assertEqual(bridge.clean_mnemonic("_File"), "File")
        self.assertEqual(bridge.clean_mnemonic("A__B_C"), "A_BC")

    def test_format_shortcut(self):
        self.assertEqual(bridge.format_shortcut([["Control", "Shift", "t"]]), "Ctrl+Shift+T")
        self.assertEqual(bridge.format_shortcut(["Alt", "F4"]), "Alt+F4")
        self.assertEqual(bridge.format_shortcut(None), "")

    def test_extract_top_menus_and_collapse_separators(self):
        layout = (
            0,
            {},
            [
                (
                    1,
                    {"label": "_File", "enabled": True, "visible": True},
                    [
                        (10, {"type": "separator"}, []),
                        (11, {"label": "_New", "enabled": True, "shortcut": [["Control", "n"]]}, []),
                        (12, {"type": "separator"}, []),
                        (13, {"type": "separator"}, []),
                        (14, {"label": "Hidden", "visible": False}, []),
                        (15, {"label": "Auto _Save", "toggle-type": "checkmark", "toggle-state": 1}, []),
                        (16, {"type": "separator"}, []),
                    ],
                ),
                (2, {"type": "separator"}, []),
                (
                    3,
                    {"label": "_View", "enabled": True},
                    [
                        (
                            30,
                            {"label": "_Zoom"},
                            [
                                (31, {"label": "Zoom _In", "shortcut": [["Control", "plus"]]}, []),
                            ],
                        )
                    ],
                ),
            ],
        )
        menus = bridge.extract_top_menus(layout)
        self.assertEqual([m["label"] for m in menus], ["File", "View"])
        file_items = menus[0]["items"]
        self.assertEqual(len(file_items), 3)  # New, sep, Auto Save
        self.assertEqual(file_items[0]["label"], "New")
        self.assertEqual(file_items[0]["shortcut"], "Ctrl+N")
        self.assertEqual(file_items[1]["kind"], "sep")
        self.assertEqual(file_items[2]["checked"], True)
        zoom = menus[1]["items"][0]
        self.assertEqual(zoom["label"], "Zoom")
        self.assertEqual(zoom["children"][0]["label"], "Zoom In")

    def test_match_registration_by_xid_and_newest_pid(self):
        reg = {
            100: {"xid": 100, "pid": 42, "service": ":1.1", "path": "/menu/1", "ts": 10.0},
            101: {"xid": 101, "pid": 42, "service": ":1.1", "path": "/menu/2", "ts": 20.0},
            200: {"xid": 200, "pid": 99, "service": ":1.2", "path": "/menu/3", "ts": 15.0},
        }
        self.assertEqual(bridge.match_registration(reg, pid=42, xid=100)["path"], "/menu/1")
        self.assertEqual(bridge.match_registration(reg, pid=42)["path"], "/menu/2")
        self.assertIsNone(bridge.match_registration(reg, pid=777))


if __name__ == "__main__":
    unittest.main()
