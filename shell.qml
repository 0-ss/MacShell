// macbar + macdock in ONE Quickshell process.
//
// Install (everything together in one config):
//   ~/.config/quickshell/macbar/shell.qml       (this file)
//   ~/.config/quickshell/macbar/MacBar.qml      (the menu bar)
//   ~/.config/quickshell/macbar/MacDock.qml     (the Dock)
//   ~/.config/quickshell/macbar/liquidglass.frag
// Run:  qs -c macbar        (remove your separate `qs -c macdock` autostart)
//
// Settings stay where they were: ~/.config/macbar/settings.json and ~/.config/macdock/settings.json (+ pinned.json).
// Layer namespaces are unchanged ("macbar" / "macdock"), so your existing layerrule / windowrule lines keep working.
// The Spotlight IPC bind is unchanged:  qs -c macbar ipc call spotlight toggle
//
// What is shared now (this is where the memory saving comes from):
//   * one Quickshell / Qt process instead of two,
//   * one `hyprctl` window-geometry poller for both Liquid Glass backdrops (it only runs while one of them needs it),
//   * one wallpaper lookup, and the wallpaper image is decoded once (Qt shares identical images inside a process).

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    Scope {
        id: sharedHub

        property var monData: []
        property var glassClients: []
        property var wallpaperMap: ({})

        // the single settings window lives in MacDock.qml; everything else reaches it through here
        property var bar: macBar
        property var dock: macDock
        function openSettings(pane) { macDock.openPrefs(pane); }

        // set by MacBar / MacDock (Binding elements) when their glass needs live data
        property bool barWantsGeo: false
        property bool dockWantsGeo: false
        property bool barWantsWallpaper: false
        property bool dockWantsWallpaper: false

        function refreshWallpaper() { if (!wpProc.running) wpProc.running = true; }

        // window + monitor geometry for the Liquid Glass backdrops
        Process {
            id: geoProc
            command: ["sh", "-c", "printf '{\"m\":'; hyprctl -j monitors; printf ',\"c\":'; hyprctl -j clients; printf '}'"]
            stdout: StdioCollector {
                onStreamFinished: {
                    if (text === sharedHub.geoLast) return;          // nothing moved: no JSON parse, no re-sync of every backdrop
                    sharedHub.geoLast = text;
                    sharedHub.geoHot = true; geoCool.restart();      // something changed: keep polling fast for a moment
                    try { var o = JSON.parse(text); sharedHub.monData = o.m; sharedHub.glassClients = o.c; } catch (err) { }
                }
            }
        }
        // Fast (90 ms, exactly as before) while windows are opening / moving / being dragged, relaxed (250 ms) once
        // nothing has changed for 1.5 s. Every poll spawns three processes, so an idle desktop now costs ~1/4 of before.
        property bool geoHot: true
        property string geoLast: ""
        Timer { id: geoCool; interval: 1500; onTriggered: sharedHub.geoHot = false }
        Connections {
            target: Hyprland
            function onRawEvent(event) { sharedHub.geoHot = true; geoCool.restart(); }
        }
        // Fallback path (hyprctl, three processes per poll). Only used while the fast path below is not available.
        Timer {
            interval: sharedHub.geoHot ? 90 : 250
            repeat: true
            running: (sharedHub.barWantsGeo || sharedHub.dockWantsGeo) && !sharedHub.ipcOk
            triggeredOnStart: true
            onTriggered: if (!geoProc.running) geoProc.running = true
        }

        // Fast path: ask Hyprland over Quickshell's own IPC socket (no process spawns), so the glass follows windows every
        // ~16 ms while they open / move / resize and the backdrop is real-time. Falls back to the hyprctl poller above
        // when this Quickshell build can't provide the data.
        property bool ipcOk: false
        property bool ipcBroken: false
        function ipcPoll() {
            var ts, ms, i, o, m, cl = [], mo = [];
            try {
                ts = Hyprland.toplevels.values;
                ms = Hyprland.monitors.values;
                for (i = 0; i < ts.length; i++) { o = ts[i].lastIpcObject; if (o && o.address !== undefined) cl.push(o); }
                for (i = 0; i < ms.length; i++) { m = ms[i].lastIpcObject; if (m && m.name !== undefined) mo.push(m); }
                Hyprland.refreshToplevels();      // the answer lands in lastIpcObject and is read on the next tick
                Hyprland.refreshMonitors();
            } catch (err) { ipcBroken = true; ipcOk = false; return; }
            if (mo.length === 0 || (ts.length > 0 && cl.length === 0)) { ipcOk = false; return; }
            ipcOk = true;
            var key = JSON.stringify([mo, cl]);
            if (key === geoLast) return;
            geoLast = key;
            geoHot = true; geoCool.restart();
            monData = mo;
            glassClients = cl;
        }
        Timer {
            interval: sharedHub.geoHot ? 16 : 100
            repeat: true
            running: (sharedHub.barWantsGeo || sharedHub.dockWantsGeo) && !sharedHub.ipcBroken
            triggeredOnStart: true
            onTriggered: sharedHub.ipcPoll()
        }

        // wallpaper the glass refracts (Noctalia settings.toml -> awww/swww/hyprpaper)
        Process {
            id: wpProc
            command: ["sh", "-c",
                ""
                + "out=\"\"\n"
                + "st=\"${XDG_STATE_HOME:-$HOME/.local/state}/noctalia\"; ns=\"${NOCTALIA_STATE_HOME:-/nonexistent}\"\n"
                + "for f in \"$ns/settings.toml\" \"$st/settings.toml\" \"$HOME/.config/noctalia/settings.toml\" \"$HOME/.config/noctalia/config.toml\"; do\n"
                + "  [ -f \"$f\" ] || continue\n"
                + "  out=\"$out$(awk '\n"
                + "    /^[ \\t]*\\[\\[/ { sec = \"\"; next }\n"
                + "    /^[ \\t]*\\[/ { sec = $0; gsub(/[\\[\\] \\t\"]/, \"\", sec); next }\n"
                + "    sec ~ /^wallpaper\\.(default|last|monitors\\..+)$/ && /^[ \\t]*path[ \\t]*=/ {\n"
                + "      v = $0; sub(/^[^=]*=[ \\t]*\"/, \"\", v); sub(/\".*$/, \"\", v); print sec \"\\t\" v\n"
                + "    }' \"$f\")\n"
                + "\"\n"
                + "done\n"
                + "if [ -z \"$(printf %s \"$out\" | tr -d ' \\t\\n')\" ]; then\n"
                + "  p=$(swww query 2>/dev/null | sed -n 's/.*image: //p' | head -n1)\n"
                + "  [ -z \"$p\" ] && p=$(awww query 2>/dev/null | sed -n 's/.*image: //p' | head -n1)\n"
                + "  [ -z \"$p\" ] && p=$(hyprctl hyprpaper listactive 2>/dev/null | head -n1 | sed 's/.*= //')\n"
                + "  if [ -z \"$p\" ]; then f=\"$HOME/.config/hypr/hyprpaper.conf\"\n"
                + "    [ -f \"$f\" ] && p=$(grep -E '^[[:space:]]*(path|wallpaper)[[:space:]]*=' \"$f\" | head -n1 | sed -E 's/^[^=]*=[[:space:]]*//; s/^[^,\\/]*,//')\n"
                + "  fi\n"
                + "  p=$(printf %s \"$p\" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')\n"
                + "  [ -n \"$p\" ] && out=\"wallpaper.default$(printf '\\t')$p\"\n"
                + "fi\n"
                + "printf '%s' \"$out\"\n"
            ]
            stdout: StdioCollector {
                onStreamFinished: {
                    var m = {}, lines = text.split("\n");
                    for (var i = 0; i < lines.length; i++) {
                        var k = lines[i].indexOf("\t");
                        if (k <= 0) continue;
                        var key = lines[i].substring(0, k).trim(), val = lines[i].substring(k + 1).trim();
                        if (val !== "" && m[key] === undefined) m[key] = val;
                    }
                    if (JSON.stringify(m) !== JSON.stringify(sharedHub.wallpaperMap)) sharedHub.wallpaperMap = m;
                }
            }
        }

        Timer {
            interval: 4000
            repeat: true
            running: sharedHub.barWantsWallpaper || sharedHub.dockWantsWallpaper
            onTriggered: sharedHub.refreshWallpaper()
        }
    }

    MacBar { id: macBar; hub: sharedHub }
    MacDock { id: macDock; hub: sharedHub }

    // reopen settings even when both the Dock and the Menu Bar are disabled:
    //   qs -c macbar ipc call settings open
    IpcHandler {
        target: "settings"
        function open(): void { macDock.openPrefs("general"); }
    }
}
