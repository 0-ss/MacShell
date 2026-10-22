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
    // The UI font ("Open Runde") ships with MacShell: registered here, first, so every Text below can use it
    // without installing anything. (The installer also copies it to ~/.local/share/fonts.)
    FontLoader { id: uiFontLoader; source: Qt.resolvedUrl("assets/fonts/OpenRunde-Regular.otf") }
    FontLoader { id: uiBoldFontLoader; source: Qt.resolvedUrl("assets/fonts/OpenRunde-Semibold.otf") }

    Scope {
        id: sharedHub

        property var monData: []
        property var glassClients: []
        property var wallpaperMap: ({})
        readonly property string boldFontFamily: uiBoldFontLoader.status === FontLoader.Ready ? uiBoldFontLoader.name : "Open Runde Semibold"

        // the single settings window lives in MacDock.qml; everything else reaches it through here
        property var bar: macBar
        property var dock: macDock
        property var widgets: macWidgets
        property var clock: clockApp
        property var about: aboutApp
        function openSettings(pane) { macDock.openPrefs(pane); }

        // set by MacBar / MacDock (Binding elements) when their glass needs live data
        property bool barWantsGeo: false
        property bool dockWantsGeo: false
        property bool barWantsWallpaper: false
        property bool dockWantsWallpaper: false
        property bool widgetsWantWallpaper: false

        // ── screen recording / screen sharing: the window captures sit out ──
        // A recorder (wf-recorder, a screen share) and the glass's live ScreencopyViews all pull frames from Hyprland at the same
        // time. With dozens of captures running, the compositor cut the Wayland connection ("invalid object NN") and the shell
        // crashed. While something records, the glass keeps its last frames (and refreshes slowly, only while a popover is open);
        // live capture resumes 1.5 s after the recording ends, spread over 0.6 s.
        property bool captureQuiet: false
        readonly property bool wantQuiet: macBar.recording || macBar.recRun || macBar.privacy.share.length > 0
        onWantQuietChanged: { if (wantQuiet) { quietRelease.stop(); captureQuiet = true; } else quietRelease.restart(); }
        Timer { id: quietRelease; interval: 1500; onTriggered: sharedHub.captureQuiet = false }

        // ── capture hold: the Dock's window PREVIEWS (thumbnails) are not captured while windows are being opened / closed ──
        // (Liquid Glass backdrops are NOT affected: they capture exactly as in the older version, see tlFor below.)
        // Crash: opening / closing many windows quickly ended with
        //   wl_display#1: error 0: invalid object NNN
        // (WAYLAND_DEBUG showed a hyprland_toplevel_export_frame_v1 destroyed by the shell while it was still in flight, i.e. before
        // Hyprland answered ready / failed; the compositor then killed the whole Wayland connection.)
        // Two stages, so an in-flight frame is never aborted:
        //   stage 1 (captureHold): live capture stops, the current frame finishes;
        //   stage 2 (captureCut, 0.5 s later): the capture source is released. A short hold never reaches stage 2.
        // The hold starts on every openwindow / closewindow and ends 1.2 s after the last one; the previews then resume.
        // windowCapture = false (Dock Preferences, or  qs -c <config> ipc call glass captures false) switches the window previews off.
        readonly property bool windowCapture: macDock.windowCapture      // Dock Preferences -> "Live window capture" (saved in macdock/settings.json)
        property bool churn: false
        readonly property bool captureHold: churn || !windowCapture || macBar.gaming
        // Liquid Glass: only stage 1, and only while windows open / close. Live capture pauses (the glass keeps its last frame, the capture
        // source stays attached, so nothing goes blank), then resumes. Not tied to the previews switch, never cut.
        readonly property bool glassHold: churn || macBar.gaming
        property bool captureCut: false
        // Dock previews no longer pause as a whole while windows open / close (that froze every preview for ~1.5 s):
        // only the CLOSING window's own preview stops its live capture, the moment Hyprland announces the close
        // (before the toplevel is destroyed, so no frame is ever aborted in flight). Everything else keeps running.
        readonly property bool previewHold: !windowCapture || macBar.gaming
        property var closingWins: ({})
        onCaptureHoldChanged: { if (captureHold) cutDelay.restart(); else { cutDelay.stop(); captureCut = false; } }
        Timer { id: cutDelay; interval: 500; onTriggered: sharedHub.captureCut = true }
        Timer { id: closingForget; interval: 3000; onTriggered: sharedHub.closingWins = ({}) }
        Timer { id: churnRelease; interval: 1200; onTriggered: sharedHub.churn = false }
        // forget admission records of windows that no longer exist (the table grew by one entry per window ever opened)
        function tlPrune() {
            var ts = Hyprland.toplevels.values, live = {}, k;
            for (var i = 0; i < ts.length; i++) live[ts[i].address] = true;
            for (k in tlState.ready) if (!live[k]) delete tlState.ready[k];
        }

        Timer { id: wpKick; interval: 250; onTriggered: sharedHub.refreshWallpaper() }
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
        property string lastActive: ""
        property string geoLast: ""
        Timer { id: geoCool; interval: 1500; onTriggered: sharedHub.geoHot = false }
        Connections {
            target: Hyprland
            function onRawEvent(event) {
                if (event.name === "openwindow" || event.name === "closewindow") { sharedHub.churn = true; churnRelease.restart(); }
                if (event.name === "closewindow") {
                    var cw = {}, a = String(event.data).replace(/^0x/, "");
                    for (var k in sharedHub.closingWins) cw[k] = true;
                    cw[a] = true;
                    sharedHub.closingWins = cw;
                    closingForget.restart();
                }
                // titles changing (terminals, browsers, players do it all the time) move nothing on screen
                var en = event.name;
                if (en === "windowtitle" || en === "windowtitlev2" || en === "activewindow") return;
                // our own window previews / screen captures announce themselves as "screencast": not a change
                if (en === "screencast" || en === "screencastv2") return;
                // workspace switch, window moved to another workspace / monitor, fullscreen, float toggle, special workspace:
                // refresh monitors + windows NOW so the glass (and smart hide) follow within a frame, not on the next poll
                if (en === "workspace" || en === "workspacev2" || en === "focusedmon" || en === "focusedmonv2" || en === "activespecial" || en === "activespecialv2"
                    || en === "moveworkspace" || en === "moveworkspacev2" || en === "movewindow" || en === "movewindowv2" || en === "fullscreen"
                    || en === "changefloatingmode" || en === "openwindow" || en === "closewindow") {
                    try { Hyprland.refreshMonitors(); Hyprland.refreshToplevels(); } catch (err) { }
                    if (en.indexOf("workspace") >= 0 || en.indexOf("focusedmon") === 0) wpKick.restart();   // per-workspace wallpapers
                }
                // focus only matters when it moves to ANOTHER window (titles changing re-send the same one)
                if (en === "activewindowv2") { if (event.data === sharedHub.lastActive) return; sharedHub.lastActive = event.data; }
                sharedHub.geoHot = true; geoCool.restart(); tlDebounce.restart();
            }
        }

        // ── window capture gate (shared by the Menu Bar and the Dock glass) ──
        // A window is only handed to a ScreencopyView 0.2 s after it appeared (shorter than the open animation, so nobody sees it),
        // and windows that appear together (opening a batch of apps, a game launcher...) are admitted ONE EVERY 110 ms instead of
        // all at once. Hyprland answers every live capture with a frame request; starting a dozen of them in the same instant
        // while a screen recorder is also pulling frames is what made the compositor drop frames and the Wayland connection
        // die ("invalid object NN"). Short-lived dialogs that close while their first frame is in flight are covered by the 0.2 s.
        property int tlTick: 0
        property var tlState: ({ ready: {}, last: 0, next: 0 })     // plain bookkeeping: mutated inside bindings WITHOUT notifying (no binding loop)
        Timer { id: tlYoung; onTriggered: { sharedHub.tlState.next = 0; sharedHub.tlTick++; } }
        Timer { id: tlDebounce; interval: 120; onTriggered: { sharedHub.tlPrune(); sharedHub.tlSeed(); sharedHub.tlTick++; } }
        function tlArm() {
            var st = tlState, d = st.next - Date.now();
            tlYoung.interval = Math.max(10, d) + 15;
            tlYoung.restart();
        }
        // Windows are admitted the moment Hyprland first lists them (not the first time their workspace becomes visible), so switching to a
        // workspace whose windows are already open captures them AT ONCE instead of after the 0.2 s "young window" delay.
        function tlSeed() {
            var ts = Hyprland.toplevels.values, st = tlState, now = Date.now();
            for (var i = 0; i < ts.length; i++) {
                var a = ts[i].address;
                if (st.ready[a] === undefined) { st.ready[a] = Math.max(now + 200, st.last + 110); st.last = st.ready[a]; }
            }
        }
        function tlFor(addr) {
            var a = String(addr).replace(/^0x/, "");
            var ts = Hyprland.toplevels.values;
            for (var i = 0; i < ts.length; i++) {
                if (ts[i].address !== a) continue;
                var st = tlState, now = Date.now();
                if (st.ready[a] === undefined) {
                    st.ready[a] = Math.max(now + 200, st.last + 110);
                    st.last = st.ready[a];
                }
                if (st.ready[a] > now) {
                    if (st.next === 0 || st.ready[a] < st.next) { st.next = st.ready[a]; Qt.callLater(tlArm); }
                    return null;
                }
                return ts[i].wayland;
            }
            return null;
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
            tlSeed();
            // fingerprint the GEOMETRY only: a window retitling itself (a terminal, a browser tab, a player) is no
            // reason to wake the 60 Hz path — that kept it hot (and the main thread busy) the whole time
            var gk = [], j, c;
            for (j = 0; j < cl.length; j++) {
                c = cl[j];
                gk.push([c.address, c.at, c.size, c.workspace ? c.workspace.id : 0, c.monitor, c.floating, c.fullscreen, c.mapped, c.hidden]);
            }
            var mk = [];
            for (j = 0; j < mo.length; j++) mk.push([mo[j].name, mo[j].x, mo[j].y, mo[j].width, mo[j].height, mo[j].scale, mo[j].activeWorkspace ? mo[j].activeWorkspace.id : 0, mo[j].specialWorkspace ? mo[j].specialWorkspace.id : 0]);
            var key = JSON.stringify([mk, gk]);
            if (key === geoLast) return;
            geoLast = key;
            geoHot = true; geoCool.restart();
            monData = mo;
            glassClients = cl;
        }
        // Re-read monitors + windows right now (the bar changed size, so every tiled window just moved) and keep re-reading for a moment
        // while Hyprland settles, even when nothing is polling at the time. Forgets the last fingerprint so the result is always applied.
        function kickGeo() {
            geoLast = ""; geoHot = true; geoCool.restart(); tlDebounce.restart();
            kickPass = 0; kickT.restart();
        }
        property int kickPass: 0
        Timer {
            id: kickT; interval: 120; repeat: true
            onTriggered: {
                sharedHub.kickPass++;
                if (sharedHub.ipcOk && !sharedHub.ipcBroken) sharedHub.ipcPoll();
                else { try { Hyprland.refreshMonitors(); Hyprland.refreshToplevels(); } catch (err) { } if (!geoProc.running) geoProc.running = true; }
                if (sharedHub.kickPass >= 6) kickT.stop();
            }
        }
        Timer {
            // fast (60 Hz) for 1.5 s after any window event, otherwise a relaxed 2.5 Hz check (idle CPU)
            interval: sharedHub.geoHot ? 16 : 400
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
            interval: 4000        // was 15 s: a wallpaper change reaches the glass within a few seconds
            repeat: true
            running: sharedHub.barWantsWallpaper || sharedHub.dockWantsWallpaper || sharedHub.widgetsWantWallpaper
            onTriggered: sharedHub.refreshWallpaper()
        }
    }

    MacBar { id: macBar; hub: sharedHub }
    MacDock { id: macDock; hub: sharedHub; bar: macBar }
    MacWidgets { id: macWidgets; hub: sharedHub }
    ClockApp { id: clockApp; hub: sharedHub }
    AboutApp { id: aboutApp; hub: sharedHub }

    Component.onCompleted: {
        sharedHub.bar = macBar;
        sharedHub.dock = macDock;
        sharedHub.widgets = macWidgets;
    }

    // reopen settings even when both the Dock and the Menu Bar are disabled:
    //   qs -c macbar ipc call settings open
    IpcHandler {
        target: "settings"
        function open(): void { macDock.openPrefs("general"); }
        function toggle(): void { macDock.togglePrefs("general"); }
        // qs -c MacShell ipc call settings pane wallpaper   (general, dock, menubar, appearance, wallpaper, behavior, apps, about)
        function pane(id: string): void { macDock.openPrefs(id); }
    }
    // qs -c MacShell ipc call clock open | tab alarms | stop | snooze
    IpcHandler {
        target: "clock"
        function open(): void { clockApp.open(); }
        function tab(name: string): void { clockApp.open(name); }
        function stop(): void { clockApp.stopRing(); }
        function snooze(): void { clockApp.snooze(); }
    }
    // qs -c MacShell ipc call about open | close | toggle      (the Apple menu's "About This Linux")
    IpcHandler {
        target: "about"
        function open(): void { aboutApp.open(); }
        function close(): void { aboutApp.close(); }
        function toggle(): void { aboutApp.toggle(); }
    }
    IpcHandler {
        target: "notifications"
        function open(): void { macBar.notifPopRequest(true); }
        function close(): void { macBar.notifPopRequest(false); }
        function clear(): void { macBar.notifClearAnimated(); }
        // the lock screen: a notification swiped away
        function dismiss(id: int): void { macBar.notifDelete(id); macBar.notifUnread = Math.max(0, macBar.notifUnread - 1); }
    }
    // qs -c MacShell ipc call gaming toggle | on | off
    IpcHandler {
        target: "gaming"
        function toggle(): void { macBar.gamingMode = !macBar.gaming; }
        function on(): void { macBar.gamingMode = true; }
        function off(): void { macBar.gamingMode = false; macBar.gamingAutoActive = false; }
    }
    // qs -c <config> ipc call glass captures false   (true to switch window previews back on)
    IpcHandler {
        target: "glass"
        function captures(on: bool): void { macDock.windowCapture = on; }
    }
}
