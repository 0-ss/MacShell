#!/usr/bin/env python3
"""Lightweight DBusMenu / com.canonical.AppMenu.Registrar bridge for MacShell.

Claims com.canonical.AppMenu.Registrar on the session bus when available, tracks
registered app menu trees (matched by window ID or Unix PID), and answers JSON-line
queries on stdin without any idle polling.
"""

from __future__ import annotations

import json
import sys
import time
from typing import Any

REGISTRAR_NAME = "com.canonical.AppMenu.Registrar"
REGISTRAR_PATH = "/com/canonical/AppMenu/Registrar"
REGISTRAR_XML = """
<node>
  <interface name="com.canonical.AppMenu.Registrar">
    <method name="RegisterWindow">
      <arg type="u" name="windowId" direction="in"/>
      <arg type="o" name="menuObjectPath" direction="in"/>
    </method>
    <method name="UnregisterWindow">
      <arg type="u" name="windowId" direction="in"/>
    </method>
    <method name="GetMenuForWindow">
      <arg type="u" name="windowId" direction="in"/>
      <arg type="s" name="service" direction="out"/>
      <arg type="o" name="menuObjectPath" direction="out"/>
    </method>
    <signal name="WindowRegistered">
      <arg type="u" name="windowId"/>
      <arg type="s" name="service"/>
      <arg type="o" name="menuObjectPath"/>
    </signal>
    <signal name="WindowUnregistered">
      <arg type="u" name="windowId"/>
    </signal>
  </interface>
</node>
"""

DBUSMENU_IFACE = "com.canonical.dbusmenu"
MENU_PROPS = [
    "label",
    "enabled",
    "visible",
    "type",
    "children-display",
    "toggle-type",
    "toggle-state",
    "shortcut",
]


def clean_mnemonic(label: str) -> str:
    return (
        str(label or "")
        .replace("__", "\x01")
        .replace("_", "")
        .replace("\x01", "_")
        .strip()
    )


def format_shortcut(raw: Any) -> str:
    if not raw:
        return ""
    if isinstance(raw, str):
        return raw
    seq = raw[0] if isinstance(raw, (list, tuple)) and raw and isinstance(raw[0], (list, tuple)) else raw
    if not isinstance(seq, (list, tuple)):
        return ""
    out: list[str] = []
    for tok in seq:
        s = str(tok or "").strip()
        if not s:
            continue
        low = s.lower()
        if low in ("control", "ctrl"):
            out.append("Ctrl")
        elif low == "shift":
            out.append("Shift")
        elif low in ("alt", "mod1"):
            out.append("Alt")
        elif low in ("super", "meta", "mod4"):
            out.append("Super")
        else:
            out.append(s.upper() if len(s) == 1 else s)
    return "+".join(out)


def parse_dbusmenu_node(node: Any, depth: int = 0) -> dict[str, Any] | None:
    """Convert a (id, props, children) DBusMenu tuple into a normalized dict."""
    if not isinstance(node, (list, tuple)) or len(node) < 3 or depth > 5:
        return None
    item_id, props, raw_children = node[0], node[1], node[2]
    if not isinstance(props, dict):
        props = {}
    if props.get("visible", True) is False:
        return None

    item_type = str(props.get("type", "standard") or "standard")
    if item_type == "separator":
        return {"id": int(item_id), "kind": "sep"}

    label = clean_mnemonic(props.get("label", ""))
    enabled = bool(props.get("enabled", True))
    toggle_type = str(props.get("toggle-type", "") or "")
    toggle_state = int(props.get("toggle-state", -1) or -1)
    shortcut = format_shortcut(props.get("shortcut"))

    children: list[dict[str, Any]] = []
    if isinstance(raw_children, (list, tuple)):
        for ch in raw_children:
            parsed = parse_dbusmenu_node(ch, depth + 1)
            if parsed is not None:
                children.append(parsed)

    # Collapse leading/trailing/duplicate separators
    cleaned: list[dict[str, Any]] = []
    for ch in children:
        if ch.get("kind") == "sep":
            if not cleaned or cleaned[-1].get("kind") == "sep":
                continue
        cleaned.append(ch)
    while cleaned and cleaned[-1].get("kind") == "sep":
        cleaned.pop()

    out: dict[str, Any] = {
        "id": int(item_id),
        "label": label,
        "disabled": not enabled,
    }
    if shortcut:
        out["shortcut"] = shortcut
    if toggle_type in ("checkmark", "radio") and toggle_state >= 0:
        out["checked"] = toggle_state == 1
    if cleaned:
        out["children"] = cleaned
    elif props.get("children-display") == "submenu":
        out["submenu"] = True
    return out


def extract_top_menus(layout_root: Any) -> list[dict[str, Any]]:
    """Extract top-level menu bar entries from a DBusMenu GetLayout root node."""
    parsed = parse_dbusmenu_node(layout_root, depth=0)
    if not parsed:
        return []
    menus: list[dict[str, Any]] = []
    for ch in parsed.get("children", []):
        if ch.get("kind") == "sep":
            continue
        label = ch.get("label", "").strip()
        if not label:
            continue
        menus.append({
            "id": ch["id"],
            "label": label,
            "items": ch.get("children", []),
            "submenu": bool(ch.get("submenu", False)),
        })
    return menus


def match_registration(
    by_win: dict[int, dict[str, Any]],
    pid: int = 0,
    xid: int = 0,
) -> dict[str, Any] | None:
    """Resolve the best matching registered app menu entry by XID or Unix PID."""
    if xid and xid in by_win:
        return by_win[xid]
    if pid > 0:
        best: dict[str, Any] | None = None
        for entry in by_win.values():
            if entry.get("pid") == pid:
                if best is None or entry.get("ts", 0) >= best.get("ts", 0):
                    best = entry
        return best
    return None


def emit(obj: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def run_watch() -> int:
    try:
        from gi.repository import Gio, GLib  # type: ignore[import-not-found]
    except Exception as exc:
        emit({"type": "ready", "registrar": False, "error": f"gi unavailable: {exc}"})
        return 0

    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    by_win: dict[int, dict[str, Any]] = {}
    name_owners: dict[str, set[int]] = {}

    def sender_pid(sender: str) -> int:
        try:
            res = bus.call_sync(
                "org.freedesktop.DBus",
                "/org/freedesktop/DBus",
                "org.freedesktop.DBus",
                "GetConnectionUnixProcessID",
                GLib.Variant("(s)", (sender,)),
                GLib.VariantType("(u)"),
                Gio.DBusCallFlags.NONE,
                1000,
                None,
            )
            return int(res.unpack()[0])
        except Exception:
            return 0

    def notify_changed() -> None:
        pids = sorted({int(e["pid"]) for e in by_win.values() if e.get("pid", 0) > 0})
        emit({"type": "changed", "pids": pids})

    def on_method_call(
        connection: Any,
        sender: str,
        object_path: str,
        interface_name: str,
        method_name: str,
        parameters: Any,
        invocation: Any,
    ) -> None:
        if method_name == "RegisterWindow":
            win_id, menu_path = parameters.unpack()
            pid = sender_pid(sender)
            by_win[int(win_id)] = {
                "xid": int(win_id),
                "service": sender,
                "path": str(menu_path),
                "pid": pid,
                "ts": time.monotonic(),
            }
            name_owners.setdefault(sender, set()).add(int(win_id))
            invocation.return_value(None)
            try:
                connection.emit_signal(
                    None,
                    REGISTRAR_PATH,
                    REGISTRAR_NAME,
                    "WindowRegistered",
                    GLib.Variant("(uso)", (int(win_id), sender, str(menu_path))),
                )
            except Exception:
                pass
            notify_changed()
        elif method_name == "UnregisterWindow":
            (win_id,) = parameters.unpack()
            entry = by_win.pop(int(win_id), None)
            if entry and entry["service"] in name_owners:
                name_owners[entry["service"]].discard(int(win_id))
            invocation.return_value(None)
            try:
                connection.emit_signal(
                    None,
                    REGISTRAR_PATH,
                    REGISTRAR_NAME,
                    "WindowUnregistered",
                    GLib.Variant("(u)", (int(win_id),)),
                )
            except Exception:
                pass
            notify_changed()
        elif method_name == "GetMenuForWindow":
            (win_id,) = parameters.unpack()
            entry = by_win.get(int(win_id))
            if entry:
                invocation.return_value(GLib.Variant("(so)", (entry["service"], entry["path"])))
            else:
                invocation.return_value(GLib.Variant("(so)", ("", "/")))

    def on_name_owner_changed(
        _conn: Any, _sender: str, _path: str, _iface: str, _sig: str, params: Any
    ) -> None:
        name, _old, new_owner = params.unpack()
        if not new_owner and name in name_owners:
            wids = name_owners.pop(name, set())
            for wid in wids:
                by_win.pop(wid, None)
            if wids:
                notify_changed()

    bus.signal_subscribe(
        "org.freedesktop.DBus",
        "org.freedesktop.DBus",
        "NameOwnerChanged",
        "/org/freedesktop/DBus",
        None,
        Gio.DBusSignalFlags.NONE,
        on_name_owner_changed,
    )

    node_info = Gio.DBusNodeInfo.new_for_xml(REGISTRAR_XML)
    reg_id = bus.register_object(
        REGISTRAR_PATH,
        node_info.interfaces[0],
        on_method_call,
        None,
        None,
    )

    def fetch_layout(service: str, path: str, parent_id: int = 0, depth: int = 3) -> Any:
        res = bus.call_sync(
            service,
            path,
            DBUSMENU_IFACE,
            "GetLayout",
            GLib.Variant("(iias)", (parent_id, depth, MENU_PROPS)),
            GLib.VariantType("(u(ia{sv}av))"),
            Gio.DBusCallFlags.NONE,
            1500,
            None,
        )
        return res.unpack()[1]

    def handle_cmd(line: str) -> None:
        try:
            msg = json.loads(line)
        except Exception:
            return
        cmd = msg.get("cmd")
        if cmd == "query":
            pid = int(msg.get("pid") or 0)
            xid = int(msg.get("xid") or 0)
            entry = match_registration(by_win, pid=pid, xid=xid)
            if not entry:
                emit({"type": "menu", "pid": pid, "menus": [], "service": "", "path": ""})
                return
            try:
                root = fetch_layout(entry["service"], entry["path"], 0, 3)
                menus = extract_top_menus(root)
                emit({
                    "type": "menu",
                    "pid": pid,
                    "service": entry["service"],
                    "path": entry["path"],
                    "menus": menus,
                })
            except Exception as exc:
                emit({"type": "menu", "pid": pid, "menus": [], "service": "", "path": "", "error": str(exc)})
        elif cmd == "activate":
            service = str(msg.get("service") or "")
            path = str(msg.get("path") or "")
            item_id = int(msg.get("id") or 0)
            if not service or not path:
                return
            try:
                bus.call_sync(
                    service,
                    path,
                    DBUSMENU_IFACE,
                    "Event",
                    GLib.Variant("(isvu)", (item_id, "clicked", GLib.Variant("s", ""), int(time.time()) & 0xFFFFFFFF)),
                    None,
                    Gio.DBusCallFlags.NONE,
                    1000,
                    None,
                )
            except Exception:
                pass
        elif cmd == "aboutToShow":
            service = str(msg.get("service") or "")
            path = str(msg.get("path") or "")
            item_id = int(msg.get("id") or 0)
            if not service or not path:
                return
            try:
                bus.call_sync(
                    service,
                    path,
                    DBUSMENU_IFACE,
                    "AboutToShow",
                    GLib.Variant("(i)", (item_id,)),
                    GLib.VariantType("(b)"),
                    Gio.DBusCallFlags.NONE,
                    1000,
                    None,
                )
            except Exception:
                pass

    loop = GLib.MainLoop()

    def on_stdin(_channel: Any, cond: Any) -> bool:
        if cond & (GLib.IOCondition.HUP | GLib.IOCondition.ERR):
            loop.quit()
            return False
        line = sys.stdin.readline()
        if not line:
            loop.quit()
            return False
        handle_cmd(line)
        return True

    stdin_ch = GLib.IOChannel.unix_new(sys.stdin.fileno())
    GLib.io_add_watch(
        stdin_ch,
        GLib.PRIORITY_DEFAULT,
        GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
        on_stdin,
    )

    own_id = Gio.bus_own_name_on_connection(
        bus,
        REGISTRAR_NAME,
        Gio.BusNameOwnerFlags.NONE,
        lambda _c, _n: emit({"type": "ready", "registrar": True}),
        lambda _c, _n: emit({"type": "ready", "registrar": False}),
    )

    try:
        loop.run()
    except KeyboardInterrupt:
        pass
    finally:
        Gio.bus_unown_name(own_id)
        bus.unregister_object(reg_id)
    return 0


def main(argv: list[str]) -> int:
    if len(argv) >= 2 and argv[1] == "watch":
        return run_watch()
    emit({"type": "error", "error": "usage: appmenu-bridge.py watch"})
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
