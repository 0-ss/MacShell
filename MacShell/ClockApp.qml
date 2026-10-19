// Clock — the macOS Clock app for MacShell: World Clock, Alarms, Stopwatch, Timers.
//
//   qs -c MacShell ipc call clock open            (also: clock tab alarms|world|stopwatch|timers, clock stop, clock snooze)
//
// Lives inside MacShell (not its own process) so alarms and timers ring even when the window is closed. Everything is
// saved to ~/.config/macshell/clock.json the moment it changes (survives crashes and restarts); the Clock widget and
// the lock screen read the same file, so a running timer / stopwatch shows there too.
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property var hub: null
    readonly property var dock: hub ? hub.dock : null
    readonly property var bar: hub ? hub.bar : null
    readonly property bool darkMode: dock ? dock.darkMode : true
    readonly property string fam: dock ? dock.fontFamily : "Inter Variable"
    property color accent: dock ? dock.accent : "#0A84FF"
    Behavior on accent { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
    readonly property bool use24h: bar ? bar.use24h : true
    readonly property bool appEnabled: bar ? bar.clockAppEnabled : true
    readonly property string home: Quickshell.env("HOME")
    readonly property string soundDir: home + "/.local/share/sounds/macshell"
    property color orange: "#FF9F0A"
    Behavior on orange { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }

    // ═════════════ STATE (saved) ═════════════
    property var alarms: []        // { id, h, m, label, on, days: [0..6] (0 = Sunday; empty = once) }
    property var cities: [ { name: "Cupertino", tz: "America/Los_Angeles" }, { name: "New York", tz: "America/New_York" },
                           { name: "London", tz: "Europe/London" }, { name: "Tokyo", tz: "Asia/Tokyo" } ]
    property var timer: ({ state: "idle", total: 300000, endAt: 0, left: 300000, label: "" })   // idle | running | paused
    property var sw: ({ running: false, startAt: 0, acc: 0, laps: [] })
    property var recents: []       // recent timer durations (ms), newest first
    property var snoozes: []       // { at, label }
    property var ringing: null     // { kind: "alarm" | "timer", label, time } while it rings
    property bool loaded: false

    property real nowMs: Date.now()
    readonly property bool timerActive: timer.state !== "idle"
    readonly property bool swActive: sw.running || sw.acc > 0

    function uid() { return Date.now().toString(36) + Math.floor(Math.random() * 1e6).toString(36); }
    function pad(n) { return (n < 10 ? "0" : "") + n; }
    function fmtHM(h, m) {
        if (use24h) return pad(h) + ":" + pad(m);
        var hh = h % 12; if (hh === 0) hh = 12;
        return hh + ":" + pad(m);
    }
    function ampm(h) { return use24h ? "" : (h < 12 ? "AM" : "PM"); }
    function timerLeft() {
        if (timer.state === "running") return Math.max(0, timer.endAt - nowMs);
        return timer.left;
    }
    function fmtDur(ms, tenths) {
        var s = Math.ceil(ms / 1000);
        if (tenths) s = Math.floor(ms / 1000);
        var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), x = s % 60;
        return (h > 0 ? h + ":" + pad(m) : pad(m)) + ":" + pad(x);
    }
    function swElapsed() { return sw.acc + (sw.running ? nowMs - sw.startAt : 0); }
    function fmtSw(ms) {
        var cs = Math.floor(ms / 10) % 100, s = Math.floor(ms / 1000), m = Math.floor(s / 60) % 60, h = Math.floor(s / 3600);
        return (h > 0 ? h + ":" : "") + pad(m) + ":" + pad(s % 60) + "," + pad(cs);
    }
    function repeatText(days) {
        if (!days || days.length === 0) return "";
        var d = days.slice().sort();
        if (d.length === 7) return "every day";
        if (d.join() === "1,2,3,4,5") return "weekdays";
        if (d.join() === "0,6") return "weekends";
        var n = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
        return d.map(function (i) { return n[i]; }).join(", ");
    }

    // ── persistence ──
    FileView {
        id: store
        path: root.home + "/.config/macshell/clock.json"
        printErrors: false
        onLoaded: {
            try {
                var o = JSON.parse(text());
                if (o.alarms) root.alarms = o.alarms;
                if (o.cities) root.cities = o.cities;
                if (o.timer) root.timer = o.timer;
                if (o.sw) root.sw = o.sw;
                if (o.recents) root.recents = o.recents;
                if (o.snoozes) root.snoozes = o.snoozes;
            } catch (e) { }
            root.loaded = true;
            root.refreshTz();
        }
        onLoadFailed: { root.loaded = true; root.refreshTz(); }
    }
    Timer { id: saveLater; interval: 150; onTriggered: root.saveNow() }
    function save() { if (loaded) saveLater.restart(); }
    function saveNow() {
        Quickshell.execDetached(["sh", "-c", "mkdir -p \"$HOME/.config/macshell\" && printf '%s\\n' \"$1\" > \"$HOME/.config/macshell/clock.json.tmp\" && mv -f \"$HOME/.config/macshell/clock.json.tmp\" \"$HOME/.config/macshell/clock.json\"",
            "sh", JSON.stringify({ alarms: alarms, cities: cities, timer: timer, sw: sw, recents: recents, snoozes: snoozes, ringing: ringing }, null, 1)]);
    }

    // ── alarms ──
    function addAlarm(h, m, label, days) {
        var a = alarms.slice(); a.push({ id: uid(), h: h, m: m, label: label || "", on: true, days: days || [] });
        a.sort(function (x, y) { return x.h * 60 + x.m - (y.h * 60 + y.m); });
        alarms = a; save();
    }
    function updateAlarm(id, h, m, label, days) {
        var a = alarms.map(function (x) { return x.id === id ? { id: id, h: h, m: m, label: label || "", on: true, days: days || [] } : x; });
        a.sort(function (x, y) { return x.h * 60 + x.m - (y.h * 60 + y.m); });
        alarms = a; save();
    }
    function setAlarmOn(id, on) { alarms = alarms.map(function (x) { if (x.id !== id) return x; var c = Object.assign({}, x); c.on = on; return c; }); save(); }
    function deleteAlarm(id) { alarms = alarms.filter(function (x) { return x.id !== id; }); save(); }
    function nextAlarmText(a) {
        // "in 7 hr 12 min" style hint for the widget
        var d = new Date(nowMs), best = -1;
        for (var k = 0; k < 8; k++) {
            var t = new Date(d.getFullYear(), d.getMonth(), d.getDate() + k, a.h, a.m, 0);
            if (t.getTime() <= nowMs) continue;
            if (a.days.length === 0 || a.days.indexOf(t.getDay()) >= 0) { best = t.getTime(); break; }
        }
        return best;
    }

    // ── timer ──
    function startTimer(ms, label) {
        if (ms <= 0) return;
        timer = { state: "running", total: ms, endAt: Date.now() + ms, left: ms, label: label || "" };
        var r = recents.filter(function (x) { return x !== ms; }); r.unshift(ms); recents = r.slice(0, 6);
        save();
    }
    function pauseTimer() { if (timer.state !== "running") return; var t = Object.assign({}, timer); t.left = Math.max(0, t.endAt - Date.now()); t.state = "paused"; timer = t; save(); }
    function resumeTimer() { if (timer.state !== "paused") return; var t = Object.assign({}, timer); t.endAt = Date.now() + t.left; t.state = "running"; timer = t; save(); }
    function cancelTimer() { var t = Object.assign({}, timer); t.state = "idle"; t.left = t.total; timer = t; save(); }

    // ── stopwatch ──
    function swStart() { sw = { running: true, startAt: Date.now(), acc: sw.acc, laps: sw.laps }; save(); }
    function swStop() { sw = { running: false, startAt: 0, acc: sw.acc + Date.now() - sw.startAt, laps: sw.laps }; save(); }
    function swLap() { var l = sw.laps.slice(); l.unshift(swElapsed()); sw = { running: sw.running, startAt: sw.startAt, acc: sw.acc, laps: l }; save(); }
    function swReset() { sw = { running: false, startAt: 0, acc: 0, laps: [] }; save(); }

    // ── world clock: UTC offsets come from the system tz database (DST-correct), refreshed hourly ──
    property var tzOff: ({})
    readonly property int localOff: -new Date(nowMs).getTimezoneOffset()
    function refreshTz() {
        var z = cities.map(function (c) { return c.tz; });
        if (z.length === 0 || tzProc.running) return;
        tzProc.command = ["sh", "-c", "for z in \"$@\"; do printf '%s %s\\n' \"$z\" \"$(TZ=$z date +%z)\"; done", "sh"].concat(z);
        tzProc.running = true;
    }
    Process {
        id: tzProc
        stdout: StdioCollector {
            onStreamFinished: {
                var o = {}, ls = text.trim().split("\n");
                for (var i = 0; i < ls.length; i++) {
                    var p = ls[i].split(" "); if (p.length < 2) continue;
                    var s = p[1], sg = s[0] === "-" ? -1 : 1;
                    o[p[0]] = sg * (parseInt(s.substr(1, 2), 10) * 60 + parseInt(s.substr(3, 2), 10));
                }
                root.tzOff = o;
            }
        }
    }
    Timer { interval: 3600000; repeat: true; running: true; onTriggered: root.refreshTz() }
    function cityDate(tz) {
        var off = tzOff[tz]; if (off === undefined) off = localOff;
        return new Date(nowMs + (off - localOff) * 60000);
    }
    function cityDayText(tz) {
        var off = tzOff[tz]; if (off === undefined) off = localOff;
        var c = cityDate(tz), l = new Date(nowMs);
        var dd = Math.round((new Date(c.getFullYear(), c.getMonth(), c.getDate()) - new Date(l.getFullYear(), l.getMonth(), l.getDate())) / 86400000);
        var day = dd === 0 ? "Today" : (dd > 0 ? "Tomorrow" : "Yesterday");
        var diff = (off - localOff) / 60, hrs = Math.abs(diff);
        var hs = (hrs % 1 === 0 ? hrs : hrs.toFixed(1)) + (hrs === 1 ? "HR" : "HRS");
        return day + ", " + (diff >= 0 ? "+" : "-") + hs;
    }
    readonly property var cityChoices: [
        ["Abu Dhabi", "Asia/Dubai"], ["Al Ain", "Asia/Dubai"], ["Amsterdam", "Europe/Amsterdam"], ["Athens", "Europe/Athens"],
        ["Auckland", "Pacific/Auckland"], ["Bangkok", "Asia/Bangkok"], ["Barcelona", "Europe/Madrid"], ["Beijing", "Asia/Shanghai"],
        ["Berlin", "Europe/Berlin"], ["Buenos Aires", "America/Argentina/Buenos_Aires"], ["Cairo", "Africa/Cairo"],
        ["Cape Town", "Africa/Johannesburg"], ["Chicago", "America/Chicago"], ["Cupertino", "America/Los_Angeles"],
        ["Delhi", "Asia/Kolkata"], ["Denver", "America/Denver"], ["Doha", "Asia/Qatar"], ["Dubai", "Asia/Dubai"],
        ["Dublin", "Europe/Dublin"], ["Hong Kong", "Asia/Hong_Kong"], ["Honolulu", "Pacific/Honolulu"], ["Istanbul", "Europe/Istanbul"],
        ["Jakarta", "Asia/Jakarta"], ["Jeddah", "Asia/Riyadh"], ["Karachi", "Asia/Karachi"], ["Kuwait City", "Asia/Kuwait"],
        ["Lagos", "Africa/Lagos"], ["Lisbon", "Europe/Lisbon"], ["London", "Europe/London"], ["Los Angeles", "America/Los_Angeles"],
        ["Madrid", "Europe/Madrid"], ["Manila", "Asia/Manila"], ["Mexico City", "America/Mexico_City"], ["Moscow", "Europe/Moscow"],
        ["Mumbai", "Asia/Kolkata"], ["Nairobi", "Africa/Nairobi"], ["New York", "America/New_York"], ["Paris", "Europe/Paris"],
        ["Riyadh", "Asia/Riyadh"], ["Rome", "Europe/Rome"], ["San Francisco", "America/Los_Angeles"], ["São Paulo", "America/Sao_Paulo"],
        ["Seoul", "Asia/Seoul"], ["Singapore", "Asia/Singapore"], ["Stockholm", "Europe/Stockholm"], ["Sydney", "Australia/Sydney"],
        ["Tehran", "Asia/Tehran"], ["Tokyo", "Asia/Tokyo"], ["Toronto", "America/Toronto"], ["Vancouver", "America/Vancouver"],
        ["Vienna", "Europe/Vienna"], ["Zurich", "Europe/Zurich"]
    ]
    function addCity(name, tz) { var c = cities.slice(); c.push({ name: name, tz: tz }); cities = c; save(); refreshTz(); }
    function removeCity(i) { var c = cities.slice(); c.splice(i, 1); cities = c; save(); }

    // ═════════════ TICK + RINGING ═════════════
    // 1 s normally; 30 fps only while the stopwatch is on screen and running
    Timer {
        interval: (win.visible && win.tab === 2 && root.sw.running) ? 33 : 1000
        repeat: true; running: true
        onTriggered: { root.nowMs = Date.now(); root.check(); }
    }
    property string lastMinute: ""
    function check() {
        if (!loaded || !appEnabled) return;
        var d = new Date(nowMs);
        if (timer.state === "running" && nowMs >= timer.endAt) {
            var t = Object.assign({}, timer); t.state = "idle"; t.left = t.total; timer = t;
            ring({ kind: "timer", label: t.label || "Timer", time: fmtDur(t.total) });
            save();
        }
        if (snoozes.length > 0) {
            var keep = [];
            for (var s = 0; s < snoozes.length; s++) {
                if (snoozes[s].at <= nowMs) ring({ kind: "alarm", label: snoozes[s].label, time: fmtHM(d.getHours(), d.getMinutes()) });
                else keep.push(snoozes[s]);
            }
            if (keep.length !== snoozes.length) { snoozes = keep; save(); }
        }
        var key = d.getFullYear() + "-" + d.getMonth() + "-" + d.getDate() + " " + d.getHours() + ":" + d.getMinutes();
        if (key === lastMinute) return;
        lastMinute = key;
        var changed = false, a = alarms.slice();
        for (var i = 0; i < a.length; i++) {
            var al = a[i];
            if (!al.on || al.h !== d.getHours() || al.m !== d.getMinutes()) continue;
            if (al.days.length > 0 && al.days.indexOf(d.getDay()) < 0) continue;
            ring({ kind: "alarm", label: al.label || "Alarm", time: fmtHM(al.h, al.m) + (ampm(al.h) ? " " + ampm(al.h) : "") });
            if (al.days.length === 0) { var c = Object.assign({}, al); c.on = false; a[i] = c; changed = true; }
        }
        if (changed) { alarms = a; save(); }
    }
    function ring(r) {
        ringing = r;
        ringProc.command = ["sh", "-c", "trap 'kill 0' TERM INT; while :; do pw-play --volume=0.9 \"$1\" & wait $!; sleep 0.25; done",
                            "sh", soundDir + "/" + (r.kind === "timer" ? "timer" : "alarm") + ".wav"];
        ringProc.running = false; ringProc.running = true;
        ringLimit.restart();
        save();
    }
    function stopRing() {
        if (!ringing) return;
        ringing = null; ringProc.running = false; ringLimit.stop(); save();
    }
    function snooze() {
        if (!ringing) return;
        var s = snoozes.slice(); s.push({ at: Date.now() + 9 * 60000, label: ringing.label }); snoozes = s;
        stopRing();
    }
    function repeatTimer() { var ms = timer.total; stopRing(); startTimer(ms, timer.label); }
    Process { id: ringProc }
    Timer { id: ringLimit; interval: 5 * 60000; onTriggered: root.stopRing() }

    function open(tabName) {
        if (!appEnabled) return;
        if (tabName !== undefined) {
            var i = ["world", "alarms", "stopwatch", "timers"].indexOf(tabName);
            if (i >= 0) win.tab = i;
        }
        win.visible = true; win.raise(); win.requestActivate();
    }

    // ═════════════ RINGING BANNER (top-right, every screen's focused one) ═════════════
    PanelWindow {
        id: banner
        screen: {
            var n = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
            for (var i = 0; i < Quickshell.screens.length; i++) if (Quickshell.screens[i].name === n) return Quickshell.screens[i];
            return Quickshell.screens[0];
        }
        visible: root.ringing !== null || bannerCard.opacity > 0.01
        anchors { top: true; right: true }
        margins { top: 38; right: 12 }
        implicitWidth: 372; implicitHeight: 96
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "macshell-clock-alert"
        Rectangle {
            id: bannerCard
            width: 356; height: 80; x: 8; y: 4
            radius: 20
            readonly property bool on: root.ringing !== null
            opacity: on ? 1 : 0
            transform: Translate { x: bannerCard.on ? 0 : 60; Behavior on x { NumberAnimation { duration: 520; easing.type: Easing.OutQuint } } }
            Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            color: root.darkMode ? Qt.rgba(0.17, 0.17, 0.18, 0.92) : Qt.rgba(0.97, 0.97, 0.98, 0.94)
            border.width: 1; border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10)
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.8; shadowOpacity: 0.35; shadowVerticalOffset: 6 }
            property color fg: root.darkMode ? "white" : "#1D1D1F"
            Behavior on fg { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color fg2: root.darkMode ? Qt.rgba(1, 1, 1, 0.6) : Qt.rgba(0, 0, 0, 0.55)
            Behavior on fg2 { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            ClockFace { x: 14; anchors.verticalCenter: parent.verticalCenter; width: 40; height: 40; night: true; date: new Date(root.nowMs); seconds: false }
            Column {
                x: 66; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 66 - btns.width - 16
                spacing: 1
                Text { text: root.ringing ? (root.ringing.kind === "timer" ? "Timer" : "Alarm") : ""; color: bannerCard.fg; font.family: root.fam; font.pixelSize: 14; font.weight: Font.DemiBold }
                Text { width: parent.width; elide: Text.ElideRight; text: root.ringing ? (root.ringing.kind === "timer" ? (root.ringing.label === "Timer" ? "Done" : root.ringing.label) : root.ringing.time + (root.ringing.label && root.ringing.label !== "Alarm" ? " · " + root.ringing.label : "")) : ""; color: bannerCard.fg2; font.family: root.fam; font.pixelSize: 13 }
            }
            Column {
                id: btns
                anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Repeater {
                    model: root.ringing ? (root.ringing.kind === "timer" ? ["Repeat", "Stop"] : ["Snooze", "Stop"]) : []
                    delegate: Rectangle {
                        required property string modelData
                        width: 78; height: 28; radius: 14
                        color: modelData === "Stop" ? root.orange : (bma.pressed ? Qt.rgba(0.5, 0.5, 0.5, 0.45) : Qt.rgba(0.5, 0.5, 0.5, 0.28))
                        Text { anchors.centerIn: parent; text: parent.modelData; color: parent.modelData === "Stop" ? "black" : bannerCard.fg; font.family: root.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
                        MouseArea {
                            id: bma; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (parent.modelData === "Stop") root.stopRing();
                                else if (parent.modelData === "Snooze") root.snooze();
                                else root.repeatTimer();
                            }
                        }
                    }
                }
            }
        }
    }

    // ═════════════ THE WINDOW ═════════════
    Window {
        id: win
        title: "Clock"
        width: 780; height: 540
        minimumWidth: 640; minimumHeight: 460
        visible: false
        color: "transparent"
        flags: Qt.Window | Qt.FramelessWindowHint
        property int tab: 1
        property string sheet: ""          // "" | "alarm" | "city"
        property var editing: null         // alarm being edited

        QtObject {
            id: pal
            readonly property bool dark: root.darkMode
            property color bg: dark ? "#1C1C1E" : "#F2F2F7"
            Behavior on bg { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color bar: dark ? "#2A2A2C" : "#E8E8ED"
            Behavior on bar { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color card: dark ? "#2C2C2E" : "#FFFFFF"
            Behavior on card { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color text: dark ? "#F5F5F7" : "#1D1D1F"
            Behavior on text { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color text2: dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.5)
            Behavior on text2 { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color text3: dark ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(0, 0, 0, 0.28)
            Behavior on text3 { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color sep: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.09)
            Behavior on sep { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color ctrl: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06)
            Behavior on ctrl { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color ctrlSel: dark ? "#636366" : "#FFFFFF"
            Behavior on ctrlSel { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color border: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.2)
            Behavior on border { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color lightOff: dark ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.15)
            Behavior on lightOff { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        }

        Rectangle {
            id: frame
            anchors.fill: parent
            radius: 12
            color: pal.bg
            border.width: 1; border.color: pal.border
            clip: true

            // resize edges
            MouseArea { x: parent.width - 8; y: parent.height - 8; width: 8; height: 8; z: 100; cursorShape: Qt.SizeFDiagCursor; onPressed: win.startSystemResize(Qt.BottomEdge | Qt.RightEdge) }
            MouseArea { x: parent.width - 5; y: 10; width: 5; height: parent.height - 20; z: 100; cursorShape: Qt.SizeHorCursor; onPressed: win.startSystemResize(Qt.RightEdge) }
            MouseArea { x: 10; y: parent.height - 5; width: parent.width - 20; height: 5; z: 100; cursorShape: Qt.SizeVerCursor; onPressed: win.startSystemResize(Qt.BottomEdge) }

            // ── toolbar ──
            Rectangle {
                id: toolbar
                width: parent.width; height: 52
                color: pal.bar
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: pal.sep }
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                // traffic lights
                Item {
                    x: 17; anchors.verticalCenter: parent.verticalCenter
                    width: 58; height: 14
                    Row {
                        spacing: 8
                        Repeater {
                            model: [{ c: "#FF5F57", g: "×" }, { c: "#FEBC2E", g: "−" }, { c: "#28C840", g: "↗" }]
                            delegate: Rectangle {
                                required property var modelData
                                width: 14; height: 14; radius: 7
                                color: ((root.bar && root.bar.tlColorOnHover) ? tlMa.containsMouse : (win.active || tlMa.containsMouse)) ? modelData.c : pal.lightOff
                                Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.14)
                                Text {
                                    anchors.centerIn: parent
                                    text: parent.modelData.g
                                    font.pixelSize: 11; font.bold: true
                                    color: Qt.rgba(0, 0, 0, 0.55)
                                    opacity: (tlMa.containsMouse || (root.bar && root.bar.tlAlwaysSymbols)) ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                }
                            }
                        }
                    }
                    MouseArea {
                        id: tlMa; anchors.fill: parent; hoverEnabled: true
                        onClicked: mouse => {
                            if (mouse.x < 22) win.visible = false;
                            else if (mouse.x < 44) root.hub && root.hub.minimizeWindow ? root.hub.minimizeWindow(win.title) : win.showMinimized();
                            else win.visibility === Window.FullScreen ? win.showNormal() : win.showFullScreen();
                        }
                    }
                }
                // tabs (segmented control)
                Rectangle {
                    id: seg
                    anchors.centerIn: parent
                    width: segRow.width + 4; height: 26; radius: 7
                    color: pal.ctrl
                    Rectangle {
                        y: 2; height: parent.height - 4; radius: 6
                        readonly property Item cur: segRep.count > win.tab ? segRep.itemAt(win.tab) : null
                        x: 2 + (cur ? cur.x : 0)
                        width: cur ? cur.width : 0
                        color: pal.ctrlSel
                        layer.enabled: true
                        layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.3; shadowOpacity: 0.25; shadowVerticalOffset: 1 }
                        Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutQuint } }
                        Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutQuint } }
                    }
                    Row {
                        id: segRow
                        x: 2; anchors.verticalCenter: parent.verticalCenter
                        Repeater {
                            id: segRep
                            model: ["World Clock", "Alarms", "Stopwatch", "Timers"]
                            delegate: Item {
                                required property string modelData
                                required property int index
                                width: tl.implicitWidth + 28; height: 22
                                Text { id: tl; anchors.centerIn: parent; text: parent.modelData; color: pal.text; font.family: root.fam; font.pixelSize: 13; font.weight: win.tab === parent.index ? Font.DemiBold : Font.Normal }
                                MouseArea { anchors.fill: parent; onClicked: win.tab = parent.index }
                            }
                        }
                    }
                }
                // + (add)
                Rectangle {
                    anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                    width: 30; height: 26; radius: 7
                    visible: win.tab === 0 || win.tab === 1
                    color: addMa.pressed ? pal.ctrl : (addMa.containsMouse ? Qt.rgba(0.5, 0.5, 0.5, 0.15) : "transparent")
                    Text { anchors.centerIn: parent; anchors.verticalCenterOffset: -1; text: "+"; color: pal.text; font.pixelSize: 22; font.weight: Font.Light }
                    MouseArea {
                        id: addMa; anchors.fill: parent; hoverEnabled: true
                        onClicked: { if (win.tab === 0) win.sheet = "city"; else { win.editing = null; win.sheet = "alarm"; } }
                    }
                }
            }

            // ── pages ──
            Item {
                id: pages
                anchors.top: toolbar.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                Repeater {
                    model: [pWorld, pAlarms, pStopwatch, pTimers]
                    delegate: Loader {
                        required property var modelData
                        required property int index
                        anchors.fill: parent
                        sourceComponent: modelData
                        active: win.visible && (win.tab === index || opacity > 0)
                        opacity: win.tab === index ? 1 : 0
                        scale: win.tab === index ? 1 : 0.985
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 420; easing.type: Easing.OutQuint } }
                    }
                }
            }

            // ── sheets ──
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.35)
                opacity: win.sheet !== "" ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 220 } }
                MouseArea { anchors.fill: parent; onClicked: win.sheet = "" }
            }
            Loader {
                anchors.horizontalCenter: parent.horizontalCenter
                y: win.sheet !== "" ? 70 : 40
                Behavior on y { NumberAnimation { duration: 420; easing.type: Easing.OutQuint } }
                opacity: win.sheet !== "" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220 } }
                visible: opacity > 0
                active: win.sheet !== "" || opacity > 0
                sourceComponent: win.sheet === "city" ? sCity : sAlarm
            }
        }

        // ═════ World Clock ═════
        Component {
            id: pWorld
            Flickable {
                contentHeight: grid.height + 48
                clip: true
                Flow {
                    id: grid
                    x: 24; y: 24
                    width: parent.width - 48
                    spacing: 18
                    Repeater {
                        model: root.cities
                        delegate: Item {
                            id: cc
                            required property var modelData
                            required property int index
                            readonly property var d: root.cityDate(modelData.tz)
                            width: 160; height: 214
                            ClockFace {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 136; height: 136
                                date: cc.d
                                night: cc.d.getHours() < 6 || cc.d.getHours() >= 18
                            }
                            Column {
                                y: 148; width: parent.width
                                spacing: 2
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: cc.modelData.name; color: pal.text; font.family: root.fam; font.pixelSize: 15; font.weight: Font.DemiBold }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.cityDayText(cc.modelData.tz); color: pal.text2; font.family: root.fam; font.pixelSize: 11 }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.fmtHM(cc.d.getHours(), cc.d.getMinutes()) + (root.use24h ? "" : " " + root.ampm(cc.d.getHours())); color: pal.text2; font.family: root.fam; font.pixelSize: 13 }
                            }
                            // remove (hover)
                            Rectangle {
                                x: 6; y: 2; width: 22; height: 22; radius: 11
                                color: "#FF453A"
                                opacity: cma.containsMouse ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 160 } }
                                Text { anchors.centerIn: parent; anchors.verticalCenterOffset: -1; text: "−"; color: "white"; font.pixelSize: 16; font.bold: true }
                                MouseArea { anchors.fill: parent; enabled: parent.opacity > 0.5; onClicked: root.removeCity(cc.index) }
                            }
                            MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                        }
                    }
                }
                Text {
                    visible: root.cities.length === 0
                    anchors.centerIn: parent
                    text: "No World Clocks"; color: pal.text3; font.family: root.fam; font.pixelSize: 22
                }
            }
        }

        // ═════ Alarms ═════
        Component {
            id: pAlarms
            Item {
            id: alPage
            Flickable {
                anchors.fill: parent
                contentHeight: alCol.height + 24
                clip: true
                Column {
                    id: alCol
                    x: 24; y: 12
                    width: parent.width - 48
                    Repeater {
                        model: root.alarms
                        delegate: Item {
                            id: ar
                            required property var modelData
                            required property int index
                            width: alCol.width; height: 92
                            Rectangle { anchors.fill: parent; anchors.topMargin: 2; anchors.bottomMargin: 2; radius: 10; color: rowMa.containsMouse ? Qt.rgba(0.5, 0.5, 0.5, 0.08) : "transparent" }
                            Rectangle { anchors.bottom: parent.bottom; x: 12; width: parent.width - 24; height: 1; color: pal.sep; visible: ar.index < root.alarms.length - 1 }
                            MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true; onClicked: { win.editing = ar.modelData; win.sheet = "alarm"; } }
                            Row {
                                x: 12; y: 10
                                spacing: 4
                                Text {
                                    text: root.fmtHM(ar.modelData.h, ar.modelData.m)
                                    color: ar.modelData.on ? pal.text : pal.text3
                                    font.family: root.fam; font.pixelSize: 50; font.weight: Font.Light
                                    Behavior on color { ColorAnimation { duration: 220 } }
                                }
                                Text {
                                    anchors.baseline: parent.children[0].baseline
                                    text: root.ampm(ar.modelData.h)
                                    color: ar.modelData.on ? pal.text : pal.text3
                                    font.family: root.fam; font.pixelSize: 26; font.weight: Font.Light
                                }
                            }
                            Text {
                                x: 13; y: 66
                                text: (ar.modelData.label || "Alarm") + (ar.modelData.days.length ? ", " + root.repeatText(ar.modelData.days) : "")
                                color: ar.modelData.on ? pal.text2 : pal.text3
                                font.family: root.fam; font.pixelSize: 13
                            }
                            // delete (hover)
                            Rectangle {
                                anchors.right: sw1.left; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                                width: 26; height: 26; radius: 13
                                color: delMa.containsMouse ? "#FF453A" : Qt.rgba(0.5, 0.5, 0.5, 0.22)
                                opacity: rowMa.containsMouse || delMa.containsMouse ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 160 } }
                                Text { anchors.centerIn: parent; text: "✕"; color: "white"; font.pixelSize: 11; font.bold: true }
                                MouseArea { id: delMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.deleteAlarm(ar.modelData.id) }
                            }
                            CSwitch { id: sw1; anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; on: ar.modelData.on; onToggled: v => root.setAlarmOn(ar.modelData.id, v) }
                        }
                    }
                }
                Column {
                    visible: root.alarms.length === 0
                    parent: alPage
                    anchors.centerIn: parent
                    spacing: 8
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "No Alarms"; color: pal.text3; font.family: root.fam; font.pixelSize: 22 }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Click + to add an alarm."; color: pal.text3; font.family: root.fam; font.pixelSize: 13 }
                }
            }
            }
        }

        // ═════ Stopwatch ═════
        Component {
            id: pStopwatch
            Item {
                readonly property real el: root.swElapsed()
                Text {
                    id: swTxt
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height * 0.12
                    text: root.fmtSw(parent.el)
                    color: pal.text
                    font.family: root.fam; font.pixelSize: Math.min(96, parent.width / 6.2); font.weight: Font.Light
                    font.features: { "tnum": 1 }
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: swTxt.y + swTxt.height + 26
                    spacing: parent.width * 0.32
                    RoundBtn {
                        label: root.sw.running ? "Lap" : "Reset"
                        enabledBtn: root.sw.running || root.sw.acc > 0
                        fill: Qt.rgba(0.5, 0.5, 0.5, 0.25); ink: pal.text
                        onClicked: root.sw.running ? root.swLap() : root.swReset()
                    }
                    RoundBtn {
                        label: root.sw.running ? "Stop" : "Start"
                        fill: root.sw.running ? Qt.rgba(1, 0.27, 0.23, 0.28) : Qt.rgba(0.19, 0.82, 0.35, 0.28)
                        ink: root.sw.running ? "#FF453A" : "#30D158"
                        onClicked: root.sw.running ? root.swStop() : root.swStart()
                    }
                }
                ListView {
                    id: laps
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: swTxt.y + swTxt.height + 130
                    width: Math.min(460, parent.width - 48); height: parent.height - y - 12
                    clip: true
                    model: root.sw.laps.length + (root.swActive ? 1 : 0)
                    readonly property var lapTimes: {
                        // per-lap durations, newest first; index 0 = the lap in progress
                        var L = root.sw.laps, out = [];
                        var cur = parent.el - (L.length ? L[0] : 0);
                        if (root.swActive) out.push(cur);
                        for (var i = 0; i < L.length; i++) out.push(L[i] - (i + 1 < L.length ? L[i + 1] : 0));
                        return out;
                    }
                    readonly property real best: { var v = lapTimes.slice(root.swActive ? 1 : 0); return v.length > 1 ? Math.min.apply(null, v) : -1; }
                    readonly property real worst: { var v = lapTimes.slice(root.swActive ? 1 : 0); return v.length > 1 ? Math.max.apply(null, v) : -1; }
                    delegate: Item {
                        required property int index
                        width: laps.width; height: 40
                        readonly property real t: laps.lapTimes[index] || 0
                        property color c: (index > 0 || !root.swActive) && t === laps.best ? "#30D158" : ((index > 0 || !root.swActive) && t === laps.worst ? "#FF453A" : pal.text)
                        Behavior on c { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
                        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: pal.sep }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Lap " + (laps.count - parent.index); color: parent.c; font.family: root.fam; font.pixelSize: 15 }
                        Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: root.fmtSw(parent.t); color: parent.c; font.family: root.fam; font.pixelSize: 15; font.features: { "tnum": 1 } }
                    }
                }
            }
        }

        // ═════ Timers ═════
        Component {
            id: pTimers
            Item {
                id: tp
                // idle: wheels + Start; running / paused: the ring
                Item {
                    anchors.fill: parent
                    opacity: root.timerActive ? 0 : 1
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 260 } }
                    // the selection band behind the middle row, then the three wheels
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: wheels.y + wheels.height / 2 - 18
                        width: wheels.width + 24; height: 36; radius: 8; color: pal.ctrl
                    }
                    Row {
                        id: wheels
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 36
                        spacing: 6
                        Repeater {
                            model: [{ n: 24, u: "hours", v: Math.floor(root.timer.total / 3600000) },
                                    { n: 60, u: "min", v: Math.floor(root.timer.total / 60000) % 60 },
                                    { n: 60, u: "sec", v: Math.floor(root.timer.total / 1000) % 60 }]
                            delegate: Row {
                                required property var modelData
                                required property int index
                                spacing: 4
                                Wheel { ink: pal.text; fam: root.fam;
                                    width: 56
                                    labels: root.range(parent.modelData.n, false)
                                    start: parent.modelData.v
                                    align: Text.AlignRight
                                    onValueChanged: tp.parts[parent.index] = value
                                    Component.onCompleted: tp.parts[parent.index] = start
                                }
                                Text { anchors.verticalCenter: parent.verticalCenter; width: 46; text: parent.modelData.u; color: pal.text; font.family: root.fam; font.pixelSize: 15; font.weight: Font.DemiBold }
                            }
                        }
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: wheels.y + wheels.height + 14
                        width: 300; height: 34; radius: 8; color: pal.ctrl
                        Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: "Label"; color: pal.text; font.family: root.fam; font.pixelSize: 13 }
                        TextInput {
                            id: tLabel
                            anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                            width: 200; horizontalAlignment: TextInput.AlignRight
                            color: pal.text2; font.family: root.fam; font.pixelSize: 13
                            text: ""
                            Text { anchors.right: parent.right; visible: parent.text === ""; text: "Timer"; color: pal.text3; font: parent.font }
                        }
                    }
                    RoundBtn {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: wheels.y + wheels.height + 66
                        label: "Start"
                        fill: Qt.rgba(0.19, 0.82, 0.35, 0.28); ink: "#30D158"
                        onClicked: root.startTimer(((tp.parts[0] || 0) * 3600 + (tp.parts[1] || 0) * 60 + (tp.parts[2] || 0)) * 1000, tLabel.text)
                    }
                    // recents
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 18
                        spacing: 10
                        visible: root.recents.length > 0
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Recents"; color: pal.text2; font.family: root.fam; font.pixelSize: 12; font.weight: Font.DemiBold }
                        Repeater {
                            model: root.recents
                            delegate: Rectangle {
                                required property var modelData
                                width: rt.implicitWidth + 22; height: 26; radius: 13
                                color: rma.pressed ? pal.ctrlSel : pal.ctrl
                                Text { id: rt; anchors.centerIn: parent; text: root.fmtDur(parent.modelData); color: pal.text; font.family: root.fam; font.pixelSize: 12 }
                                MouseArea { id: rma; anchors.fill: parent; onClicked: root.startTimer(parent.modelData, "") }
                            }
                        }
                    }
                }
                property var parts: [0, 5, 0]

                Item {
                    anchors.fill: parent
                    opacity: root.timerActive ? 1 : 0
                    scale: root.timerActive ? 1 : 0.94
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 300 } }
                    Behavior on scale { NumberAnimation { duration: 520; easing.type: Easing.OutQuint } }
                    readonly property real remain: root.timerLeft()
                    readonly property real frac: root.timer.total > 0 ? remain / root.timer.total : 0
                    Item {
                        id: ring
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 22
                        width: Math.min(300, parent.height - 140); height: width
                        Ring { anchors.fill: parent; frac: 1; ink: Qt.rgba(0.5, 0.5, 0.5, 0.22); lineW: 9 }
                        Ring { anchors.fill: parent; frac: parent.parent.frac; ink: root.orange; lineW: 9; smoothFrac: root.timer.state === "running" }
                        Column {
                            anchors.centerIn: parent
                            spacing: 4
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.timer.label || ""; visible: text !== ""; color: pal.text2; font.family: root.fam; font.pixelSize: 15 }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.fmtDur(parent.parent.parent.remain); color: pal.text; font.family: root.fam; font.pixelSize: ring.width / 5; font.weight: Font.Light; font.features: { "tnum": 1 } }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                readonly property var end: new Date(root.nowMs + parent.parent.parent.remain)
                                text: "🔔 " + root.fmtHM(end.getHours(), end.getMinutes()) + (root.use24h ? "" : " " + root.ampm(end.getHours()))
                                color: root.timer.state === "paused" ? pal.text3 : pal.text2
                                font.family: root.fam; font.pixelSize: 14
                            }
                        }
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: ring.y + ring.height + 22
                        spacing: Math.max(80, ring.width - 160)
                        RoundBtn { label: "Cancel"; fill: Qt.rgba(0.5, 0.5, 0.5, 0.25); ink: pal.text; onClicked: root.cancelTimer() }
                        RoundBtn {
                            label: root.timer.state === "running" ? "Pause" : "Resume"
                            fill: root.timer.state === "running" ? Qt.rgba(1, 0.62, 0.04, 0.26) : Qt.rgba(0.19, 0.82, 0.35, 0.28)
                            ink: root.timer.state === "running" ? root.orange : "#30D158"
                            onClicked: root.timer.state === "running" ? root.pauseTimer() : root.resumeTimer()
                        }
                    }
                }
            }
        }

        // ═════ sheets ═════
        Component {
            id: sAlarm
            Rectangle {
                id: sa
                width: 360; height: 360; radius: 14
                color: pal.card
                border.width: 1; border.color: pal.sep
                layer.enabled: true
                layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 1.0; shadowOpacity: 0.4; shadowVerticalOffset: 10 }
                readonly property var ed: win.editing
                property var days: ed ? ed.days.slice() : []
                property bool pm: ed ? ed.h >= 12 : false
                Text { x: 20; y: 16; text: sa.ed ? "Edit Alarm" : "Add Alarm"; color: pal.text; font.family: root.fam; font.pixelSize: 15; font.weight: Font.DemiBold }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: tw.y + tw.height / 2 - 18
                    width: tw.width + 20; height: 36; radius: 8; color: pal.ctrl
                }
                Row {
                    id: tw
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 46
                    spacing: 2
                    Wheel { ink: pal.text; fam: root.fam;
                        id: hT
                        labels: root.use24h ? root.range(24, true) : ["12", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11"]
                        fontPx: 26
                        start: { var h = sa.ed ? sa.ed.h : new Date().getHours(); return root.use24h ? h : h % 12; }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: ":"; color: pal.text; font.family: root.fam; font.pixelSize: 26 }
                    Wheel { ink: pal.text; fam: root.fam; id: mT; labels: root.range(60, true); fontPx: 26; start: sa.ed ? sa.ed.m : new Date().getMinutes() }
                    Wheel { ink: pal.text; fam: root.fam; id: pT; visible: !root.use24h; width: 56; labels: ["AM", "PM"]; fontPx: 20; start: sa.pm ? 1 : 0 }
                }
                // repeat days
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: tw.y + tw.height + 14
                    spacing: 6
                    Repeater {
                        model: ["S", "M", "T", "W", "T", "F", "S"]
                        delegate: Rectangle {
                            required property string modelData
                            required property int index
                            readonly property bool sel: sa.days.indexOf(index) >= 0
                            width: 32; height: 32; radius: 16
                            color: sel ? root.orange : pal.ctrl
                            Behavior on color { ColorAnimation { duration: 160 } }
                            Text { anchors.centerIn: parent; text: parent.modelData; color: parent.sel ? "black" : pal.text; font.family: root.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    var d = sa.days.slice(), i = d.indexOf(parent.index);
                                    if (i >= 0) d.splice(i, 1); else d.push(parent.index);
                                    sa.days = d;
                                }
                            }
                        }
                    }
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: tw.y + tw.height + 58
                    width: 320; height: 32; radius: 8; color: pal.ctrl
                    Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: "Label"; color: pal.text; font.family: root.fam; font.pixelSize: 13 }
                    TextInput {
                        id: aLabel
                        anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                        width: 220; horizontalAlignment: TextInput.AlignRight
                        text: sa.ed ? sa.ed.label : ""
                        color: pal.text2; font.family: root.fam; font.pixelSize: 13
                        Text { anchors.right: parent.right; visible: parent.text === ""; text: "Alarm"; color: pal.text3; font: parent.font }
                    }
                }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 14
                    spacing: 8
                    Repeater {
                        model: ["Cancel", "Save"]
                        delegate: Rectangle {
                            required property string modelData
                            width: 84; height: 28; radius: 7
                            color: modelData === "Save" ? root.accent : pal.ctrl
                            Text { anchors.centerIn: parent; text: parent.modelData; color: parent.modelData === "Save" ? "white" : pal.text; font.family: root.fam; font.pixelSize: 13 }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (parent.modelData === "Save") {
                                        var h = root.use24h ? hT.value : (hT.value + (pT.value === 1 ? 12 : 0));
                                        if (sa.ed) root.updateAlarm(sa.ed.id, h, mT.value, aLabel.text, sa.days);
                                        else root.addAlarm(h, mT.value, aLabel.text, sa.days);
                                    }
                                    win.sheet = "";
                                }
                            }
                        }
                    }
                }
            }
        }
        Component {
            id: sCity
            Rectangle {
                id: sc
                width: 360; height: 400; radius: 14
                color: pal.card
                border.width: 1; border.color: pal.sep
                layer.enabled: true
                layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 1.0; shadowOpacity: 0.4; shadowVerticalOffset: 10 }
                Rectangle {
                    x: 14; y: 14; width: parent.width - 28; height: 30; radius: 8; color: pal.ctrl
                    TextInput {
                        id: q
                        x: 10; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 20
                        color: pal.text; font.family: root.fam; font.pixelSize: 13
                        focus: true
                        Component.onCompleted: forceActiveFocus()
                        Text { visible: parent.text === ""; text: "Search cities"; color: pal.text3; font: parent.font }
                    }
                }
                ListView {
                    x: 6; y: 54; width: parent.width - 12; height: parent.height - 64
                    clip: true
                    model: root.cityChoices.filter(function (c) { return q.text === "" || c[0].toLowerCase().indexOf(q.text.toLowerCase()) >= 0; })
                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width; height: 32; radius: 6
                        color: cma2.containsMouse ? root.accent : "transparent"
                        Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[0]; color: cma2.containsMouse ? "white" : pal.text; font.family: root.fam; font.pixelSize: 13 }
                        MouseArea { id: cma2; anchors.fill: parent; hoverEnabled: true; onClicked: { root.addCity(parent.modelData[0], parent.modelData[1]); win.sheet = ""; } }
                    }
                }
            }
        }
    }

    // ═════════════ small parts ═════════════
    function range(n, padded) { var a = []; for (var i = 0; i < n; i++) a.push(padded ? pad(i) : String(i)); return a; }

    component CSwitch: Rectangle {
        id: csw
        property bool on: false
        signal toggled(bool v)
        width: 38; height: 22; radius: 11
        color: on ? "#30D158" : (root.darkMode ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.14))
        Behavior on color { ColorAnimation { duration: 200 } }
        Rectangle {
            width: 18; height: 18; radius: 9; y: 2
            x: csw.on ? csw.width - width - 2 : 2
            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
            color: "white"
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.3; shadowOpacity: 0.3; shadowVerticalOffset: 1 }
        }
        MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: csw.toggled(!csw.on) }
    }
    component RoundBtn: Item {
        id: rb
        property string label: ""
        property color fill: "gray"
        property color ink: "white"
        property bool enabledBtn: true
        signal clicked()
        width: 78; height: 78
        opacity: enabledBtn ? 1 : 0.45
        Rectangle {
            anchors.fill: parent; radius: width / 2
            color: rb.fill
            border.width: 2; border.color: root.darkMode ? "#1C1C1E" : "#F2F2F7"
            scale: rbMa.pressed ? 0.94 : 1
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutQuint } }
            Behavior on color { ColorAnimation { duration: 220 } }
            Rectangle { anchors.fill: parent; anchors.margins: 3; radius: width / 2; color: "transparent"; border.width: 1.5; border.color: rb.fill }
            Text { anchors.centerIn: parent; text: rb.label; color: rb.ink; font.family: root.fam; font.pixelSize: 15; font.weight: Font.Medium }
        }
        MouseArea { id: rbMa; anchors.fill: parent; enabled: rb.enabledBtn; cursorShape: Qt.PointingHandCursor; onClicked: rb.clicked() }
    }
    component Ring: Canvas {
        id: rg
        property real frac: 1
        property color ink: "orange"
        property real lineW: 8
        property bool smoothFrac: false
        property real shown: frac
        Behavior on shown { enabled: rg.smoothFrac; NumberAnimation { duration: 1000; easing.type: Easing.Linear } }
        onShownChanged: requestPaint()
        onInkChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            var c = getContext("2d"); c.reset();
            var r = width / 2 - lineW / 2;
            c.lineWidth = lineW; c.lineCap = "round"; c.strokeStyle = ink;
            c.beginPath();
            c.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0.0001, shown), false);
            c.stroke();
        }
    }
    // analog face: white by day, black by night (macOS World Clock)
    component ClockFace: Item {
        id: cf
        property var date: new Date()
        property bool night: false
        property bool seconds: true
        property color face: night ? "#1C1C1E" : "#F5F5F7"
        Behavior on face { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color ink: night ? "white" : "black"
        Behavior on ink { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Rectangle { anchors.fill: parent; radius: width / 2; color: cf.face; border.width: cf.night ? 1 : 0; border.color: Qt.rgba(1, 1, 1, 0.12) }
        Repeater {
            model: cf.width >= 100 ? 0 : 12
            delegate: Item {
                required property int index
                anchors.fill: parent
                rotation: index * 30
                Rectangle { x: cf.width / 2 - width / 2; y: cf.width * 0.06; width: Math.max(1.5, cf.width * 0.016); height: cf.width * 0.07; radius: 1; color: cf.ink; opacity: 0.85 }
            }
        }
        Repeater {
            model: cf.width >= 100 ? 12 : 0
            delegate: Text {
                required property int index
                readonly property real a: (index + 1) * Math.PI / 6
                x: cf.width / 2 + Math.sin(a) * cf.width * 0.33 - width / 2
                y: cf.height / 2 - Math.cos(a) * cf.width * 0.33 - height / 2
                text: index + 1; color: cf.ink; font.family: root.fam; font.pixelSize: cf.width * 0.105; font.weight: Font.Medium
            }
        }
        // hour, minute, second hands
        Item {
            anchors.fill: parent
            rotation: (cf.date.getHours() % 12) * 30 + cf.date.getMinutes() * 0.5
            Rectangle { x: cf.width / 2 - width / 2; y: cf.height * 0.24; width: Math.max(3, cf.width * 0.035); height: cf.height * 0.28; radius: width / 2; color: cf.ink }
        }
        Item {
            anchors.fill: parent
            rotation: cf.date.getMinutes() * 6 + cf.date.getSeconds() * 0.1
            Rectangle { x: cf.width / 2 - width / 2; y: cf.height * 0.1; width: Math.max(2, cf.width * 0.025); height: cf.height * 0.42; radius: width / 2; color: cf.ink }
        }
        Item {
            anchors.fill: parent
            visible: cf.seconds
            rotation: cf.date.getSeconds() * 6
            Rectangle { x: cf.width / 2 - width / 2; y: cf.height * 0.08; width: Math.max(1, cf.width * 0.01); height: cf.height * 0.52; color: root.orange }
        }
        Rectangle { anchors.centerIn: parent; width: cf.width * 0.05; height: width; radius: width / 2; color: root.orange }
    }
}
