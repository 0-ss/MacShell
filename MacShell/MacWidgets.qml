// Desktop widgets (macOS Tahoe style) for macshell.
//
//   * one full-screen layer window on the first monitor, BELOW normal windows (WlrLayer.Bottom, namespace "macwidgets")
//   * click-through while you are not editing; edit mode shows free grid slots and snaps widget moves / sizes without overlap
//   * Weather data from Open-Meteo, a local-date Calendar, a live local-time Clock, and a Music player (MPRIS) widget
//   * settings + placed widgets are saved to ~/.config/macwidgets/settings.json
//
//   qs -c MacShell ipc call widgets refresh        re-fetch the weather now
//   qs -c MacShell ipc call widgets edit true      start / stop editing
//
// Hyprland: nothing is required. (No blur layerrule is needed, the Liquid Glass style blurs the wallpaper itself.)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import "I18n.js" as I18n

Scope {
    id: root

    property var hub: null
    readonly property var dock: hub ? hub.dock : null

    // ───────────── state ─────────────
    property bool editing: false
    property bool ready: false

    // saved settings
    property string tempUnit: "C"          // "C" | "F"
    property string locMode: "auto"        // "auto" (IP) | "city"
    property string cityName: ""
    property real widgetScale: 1.0         // the "Widget size" slider: scales every widget and the grid (0.6 - 1.5)

    readonly property string fontFamily: dock ? dock.fontFamily : "Open Runde"
    readonly property string boldFontFamily: hub && hub.boldFontFamily ? hub.boldFontFamily : "Open Runde Semibold"
    readonly property string configDir: Quickshell.env("HOME") + "/.config/macwidgets"

    // Liquid Glass look = the Appearance sliders (Translucency / Blur / Liquid strength) of the Dock + Menu Bar
    readonly property real glassOpacity: dock ? dock.glassOpacity : 0.42
    readonly property real glassBlur: (dock ? dock.glassBlur : 5) + 11     // the Appearance blur slider, plus 11 more for widgets
    readonly property real glassLiquid: dock ? dock.glassLiquid : 1.0
    readonly property real glassRim: dock ? dock.glassRim : 0.45
    readonly property real glassGrain: dock ? dock.glassGrain : 0.03
    readonly property bool darkGlass: dock ? dock.darkMode : true
    // Control Center border colour (follows the wallpaper's dominant colour)
    readonly property color borderTint: (hub && hub.bar) ? hub.bar.menuBorderColor : "#8A9AB5"

    // placed widgets: roles wid, wtype (weather | calendar | clock | player), wstyle, wsize, wmode (calendar: auto | light | dark), wx, wy
    property alias model: wmodel
    ListModel { id: wmodel }
    readonly property int widgetCount: wmodel.count
    property bool anyLiquid: false
    property int rev: 0                    // bumped on every change to the list, so Settings bindings can re-evaluate count()

    readonly property var styleNames: ({ liquid: "Liquid Glass", normal: "Normal", light: "Light", dark: "Dark" })
    readonly property var typeNames: ({ weather: "Weather", calendar: "Calendar", clock: "Clock", player: "Player", image: "Image" })
    readonly property var sizeNames: ({ small: "Small", medium: "Medium", large: "Large" })
    function dims(size) {
        var b = size === "large" ? [375, 385] : (size === "medium" ? [395, 185] : [185, 185]);
        return [Math.round(b[0] * widgetScale), Math.round(b[1] * widgetScale)];
    }
    // Size of the Player's contents (art, text, buttons) relative to the original design. The card itself fills the
    // normal widget footprint, like every other widget. 1.0 = original size.
    property real playerScale: 0.8
    readonly property int gridCell: Math.round(179 * widgetScale)
    readonly property int gridGapX: Math.round(28 * widgetScale)
    readonly property int gridGapY: Math.round(23 * widgetScale)
    readonly property int gridLeft: 21
    readonly property int gridTop: 56
    readonly property int gridRight: 21
    readonly property int gridBottom: 24
    function screenSize() {
        var scr = Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
        return [scr ? scr.width : 1920, scr ? scr.height : 1080];
    }
    function gridInfo(screenW, screenH) {
        var availW = screenW - gridLeft - gridRight;
        var availH = screenH - gridTop - gridBottom;
        var cols = Math.max(1, Math.floor((availW + gridGapX) / (gridCell + gridGapX)));
        var rows = Math.max(1, Math.floor((availH + gridGapY) / (gridCell + gridGapY)));
        var usedW = cols * gridCell + (cols - 1) * gridGapX;
        var spareW = Math.max(0, availW - usedW);
        return { cols: cols, rows: rows, left: gridLeft + Math.floor(spareW / 2), top: gridTop,
                 pitchX: gridCell + gridGapX, pitchY: gridCell + gridGapY };
    }
    function spans(size) { return size === "large" ? [2, 2] : (size === "medium" ? [2, 1] : [1, 1]); }

    function recount() {
        var l = false;
        for (var i = 0; i < wmodel.count; i++) if (wmodel.get(i).wstyle === "liquid") l = true;
        anyLiquid = l;
        rev++;
    }
    function count(type, style, size) {
        var n = 0;
        for (var i = 0; i < wmodel.count; i++) {
            var m = wmodel.get(i);
            if (m.wtype === type && (style === undefined || m.wstyle === style) && (size === undefined || m.wsize === size)) n++;
        }
        return n;
    }
    function overlaps(x, y, d, skipId) {
        for (var i = 0; i < wmodel.count; i++) {
            var m = wmodel.get(i);
            if (m.wid === skipId) continue;
            var md = dims(m.wsize);
            if (x < m.wx + md[0] && x + d[0] > m.wx && y < m.wy + md[1] && y + d[1] > m.wy) return true;
        }
        return false;
    }
    function validSlot(size, col, row, skipId, g, screenW, screenH) {
        var d = dims(size), p = [g.left + col * g.pitchX, g.top + row * g.pitchY];
        return p[0] >= gridLeft && p[1] >= gridTop
            && p[0] + d[0] <= screenW - gridRight && p[1] + d[1] <= screenH - gridBottom
            && !overlaps(p[0], p[1], d, skipId) ? p : null;
    }
    function firstFreeSlot(size, skipId) {
        var ss = screenSize(), g = gridInfo(ss[0], ss[1]), span = spans(size);
        for (var row = 0; row <= g.rows - span[1]; row++)
            for (var col = g.cols - span[0]; col >= 0; col--) {
                var p = validSlot(size, col, row, skipId, g, ss[0], ss[1]);
                if (p) return p;
            }
        return null;
    }
    function nearestFreeSlot(id, x, y, size) {
        var ss = screenSize(), g = gridInfo(ss[0], ss[1]), span = spans(size);
        var best = null, bestDistance = Infinity;
        for (var row = 0; row <= g.rows - span[1]; row++)
            for (var col = 0; col <= g.cols - span[0]; col++) {
                var p = validSlot(size, col, row, id, g, ss[0], ss[1]);
                if (!p) continue;
                var dx = p[0] - x, dy = p[1] - y, distance = dx * dx + dy * dy;
                if (distance < bestDistance) { best = p; bestDistance = distance; }
            }
        return best;
    }
    function gridSlots(screenW, screenH) {
        var g = gridInfo(screenW, screenH), slots = [];
        for (var row = 0; row < g.rows; row++)
            for (var col = 0; col < g.cols; col++) {
                var p = validSlot("small", col, row, "", g, screenW, screenH);
                if (p) slots.push({ x: p[0], y: p[1] });
            }
        return slots;
    }
    function normalizePositions() {
        var old = [];
        for (var i = 0; i < wmodel.count; i++) {
            var m = wmodel.get(i);
            old.push({ id: m.wid, x: m.wx, y: m.wy, size: m.wsize });
            wmodel.setProperty(i, "wx", -100000);
            wmodel.setProperty(i, "wy", -100000);
        }
        var ss = screenSize();
        for (var j = 0; j < old.length; j++) {
            var item = old[j], p = nearestFreeSlot(item.id, item.x, item.y, item.size);
            if (!p) p = firstFreeSlot(item.size, item.id);
            if (!p) p = [Math.max(gridLeft, Math.min(ss[0] - gridRight - dims(item.size)[0], item.x)),
                         Math.max(gridTop, Math.min(ss[1] - gridBottom - dims(item.size)[1], item.y))];
            for (var k = 0; k < wmodel.count; k++)
                if (wmodel.get(k).wid === item.id) { wmodel.setProperty(k, "wx", p[0]); wmodel.setProperty(k, "wy", p[1]); break; }
        }
    }
    function addWidget(type, style, size, src) {
        var sz = size || "small";
        var p = firstFreeSlot(sz, "");
        if (!p) return false;
        wmodel.append({ wid: "w" + Date.now().toString(36) + Math.floor(Math.random() * 1e4).toString(36),
                        wtype: type, wstyle: style, wsize: sz, wmode: "auto", wsrc: src || "", wx: p[0], wy: p[1] });
        recount(); scheduleSave();
        if (type === "weather") refreshSoon();
        return true;
    }
    function removeWidget(id) {
        for (var i = 0; i < wmodel.count; i++)
            if (wmodel.get(i).wid === id) { wmodel.remove(i); break; }
        recount(); scheduleSave();
    }
    // minus button in the Settings gallery: removes the most recently added widget of that kind
    function removeLast(type, style, size) {
        for (var i = wmodel.count - 1; i >= 0; i--) {
            var m = wmodel.get(i);
            if (m.wtype === type && m.wstyle === style && m.wsize === size) { wmodel.remove(i); break; }
        }
        recount(); scheduleSave();
    }
    function setStyle(id, style) {
        for (var i = 0; i < wmodel.count; i++)
            if (wmodel.get(i).wid === id) { wmodel.setProperty(i, "wstyle", style); break; }
        recount(); scheduleSave();
    }
    function setSource(id, src) {
        for (var i = 0; i < wmodel.count; i++)
            if (wmodel.get(i).wid === id) { wmodel.setProperty(i, "wsrc", src); break; }
        scheduleSave();
    }
    function setMode(id, mode) {
        var m = (mode === "light" || mode === "dark") ? mode : "auto";
        for (var i = 0; i < wmodel.count; i++)
            if (wmodel.get(i).wid === id) { wmodel.setProperty(i, "wmode", m); break; }
        scheduleSave();
    }
    // resize only onto a valid grid footprint; never let widgets overlap or sit between slots
    function setSize(id, size) {
        for (var i = 0; i < wmodel.count; i++) {
            if (wmodel.get(i).wid !== id) continue;
            var p = nearestFreeSlot(id, wmodel.get(i).wx, wmodel.get(i).wy, size);
            if (!p) return;
            wmodel.setProperty(i, "wsize", size);
            wmodel.setProperty(i, "wx", p[0]);
            wmodel.setProperty(i, "wy", p[1]);
            break;
        }
        recount(); scheduleSave();
    }
    function moveWidget(id, x, y) {
        for (var i = 0; i < wmodel.count; i++)
            if (wmodel.get(i).wid === id) {
                var p = nearestFreeSlot(id, x, y, wmodel.get(i).wsize);
                if (!p) return;
                wmodel.setProperty(i, "wx", p[0]);
                wmodel.setProperty(i, "wy", p[1]);
                break;
            }
        recount(); scheduleSave();
    }

    // ───────────── image widgets ─────────────
    // pickImage("", size) adds a new Image widget with the chosen picture; pickImage(id) changes the picture of widget id.
    // The chosen file is copied into ~/.config/macwidgets/images so the widget keeps working if the original moves.
    property string pickTargetId: ""
    property string pickTargetSize: "small"
    property string pickError: ""
    function pickImage(id, size) {
        if (imgPick.running) return;
        pickTargetId = id || "";
        pickTargetSize = size || "small";
        pickError = "";
        imgPick.running = true;
    }
    Process {
        id: imgPick
        command: ["sh", "-c",
            "f=''; "
            + "if command -v zenity >/dev/null 2>&1; then f=$(zenity --file-selection --title='Choose a picture' --file-filter='Images | *.png *.jpg *.jpeg *.webp *.gif *.bmp *.svg' 2>/dev/null); "
            + "elif command -v kdialog >/dev/null 2>&1; then f=$(kdialog --getopenfilename \"$HOME/Pictures\" 'image/png image/jpeg image/webp image/gif image/bmp image/svg+xml' 2>/dev/null); "
            + "elif command -v yad >/dev/null 2>&1; then f=$(yad --file --title='Choose a picture' 2>/dev/null); "
            + "else echo 'ERR:no file chooser (install zenity, kdialog or yad)'; exit 0; fi; "
            + "[ -n \"$f\" ] && [ -f \"$f\" ] || exit 0; "
            + "d=\"$1/images\"; mkdir -p \"$d\" || { echo 'ERR:cannot create the images folder'; exit 0; }; "
            + "n=\"$(date +%s)-$(printf '%s' \"$(basename \"$f\")\" | tr -c 'A-Za-z0-9._-' '_')\"; "
            + "cp -f \"$f\" \"$d/$n\" && echo \"OK:$d/$n\" || echo 'ERR:could not copy the picture'",
            "sh", root.configDir]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = text.trim();
                if (t.indexOf("OK:") === 0) {
                    var p = t.substring(3);
                    if (root.pickTargetId === "") { if (!root.addWidget("image", "normal", root.pickTargetSize, p)) root.pickError = "No free space on the desktop for another widget."; }
                    else root.setSource(root.pickTargetId, p);
                } else if (t.indexOf("ERR:") === 0) {
                    root.pickError = t.substring(4);
                    console.log("[macwidgets] image:", root.pickError);
                }
            }
        }
    }

    // ───────────── persistence ─────────────
    function scheduleSave() { if (ready) saveTimer.restart(); }
    onTempUnitChanged: { scheduleSave(); refreshSoon(); }
    onLocModeChanged: { scheduleSave(); refreshSoon(); }
    onCityNameChanged: { scheduleSave(); refreshSoon(); }
    onWidgetScaleChanged: { scheduleSave(); if (ready) rescaleTimer.restart(); }
    // after the slider settles, snap every widget onto the new grid
    Timer { id: rescaleTimer; interval: 300; onTriggered: { root.normalizePositions(); root.recount(); root.scheduleSave(); } }

    function saveSettings() {
        var list = [];
        for (var i = 0; i < wmodel.count; i++) {
            var m = wmodel.get(i);
            list.push({ id: m.wid, type: m.wtype, style: m.wstyle, size: m.wsize, mode: m.wmode || "auto", src: m.wsrc || "", x: m.wx, y: m.wy });
        }
        store.setText(JSON.stringify({ tempUnit: tempUnit, locMode: locMode, cityName: cityName, widgetScale: widgetScale, widgets: list }, null, 2));
    }
    function applySettings(o) {
        if (!o || typeof o !== "object") return;
        if (o.tempUnit === "C" || o.tempUnit === "F") tempUnit = o.tempUnit;
        if (o.locMode === "auto" || o.locMode === "city") locMode = o.locMode;
        if (typeof o.cityName === "string") cityName = o.cityName;
        if (typeof o.widgetScale === "number" && isFinite(o.widgetScale)) widgetScale = Math.max(0.6, Math.min(1.5, o.widgetScale));
        if (Array.isArray(o.widgets)) {
            wmodel.clear();
            for (var i = 0; i < o.widgets.length; i++) {
                var w = o.widgets[i];
                if (!w || (w.type !== "weather" && w.type !== "calendar" && w.type !== "clock" && w.type !== "player" && w.type !== "image")) continue;
                wmodel.append({ wid: String(w.id || ("w" + i)), wtype: w.type,
                                wstyle: w.type === "image" ? "normal" : (w.type === "clock" || w.type === "player")
                                    ? ((w.style === "light" || w.style === "dark") ? w.style : "liquid")
                                    : (w.style === "normal" ? "normal" : "liquid"),
                                wsize: (w.size === "medium" || w.size === "large") ? w.size : "small",
                                wmode: (w.mode === "light" || w.mode === "dark") ? w.mode : "auto",
                                wsrc: typeof w.src === "string" ? w.src : "",
                                wx: Number(w.x) || 0, wy: Number(w.y) || 0 });
            }
        }
        normalizePositions();
        recount();
    }
    Process { command: ["mkdir", "-p", root.configDir]; running: true }
    FileView {
        id: store
        path: root.configDir + "/settings.json"
        printErrors: false
        onLoaded: {
            try { root.applySettings(JSON.parse(text())); } catch (err) { }
            root.ready = true;
            root.scheduleSave();
            root.refresh();
        }
        onLoadFailed: { root.ready = true; }
    }
    Timer { id: saveTimer; interval: 400; onTriggered: root.saveSettings() }

    // ───────────── music player (MPRIS) ─────────────
    // the player that is playing, otherwise the first one (same rule as the Menu Bar's media widget)
    readonly property var player: {
        var ps = Mpris.players.values, best = null;
        for (var i = 0; i < ps.length; i++) {
            if (ps[i].isPlaying) return ps[i];
            if (!best) best = ps[i];
        }
        return best;
    }
    // MPRIS does not announce the playback position; ask for it once a second while something plays and a Player widget exists
    Timer {
        interval: root.lyricsWanted ? 250 : 1000        // quicker while lyrics are open, so lines change on time
        repeat: true
        running: root.player !== null && root.player.isPlaying && root.count("player") > 0
        onTriggered: { try { root.player.positionChanged(); } catch (err) { } }
    }
    // screen rectangles of the Player widgets: they stay clickable while the rest of the layer is click-through
    readonly property var playerRects: {
        var r = rev, out = [];
        for (var i = 0; i < wmodel.count; i++) {
            var m = wmodel.get(i);
            if (m.wtype !== "player") continue;
            var d = dims(m.wsize);
            out.push([m.wx, m.wy, d[0], d[1]]);
        }
        return out;
    }
    function pr(i, k) { var r = playerRects[i]; return r ? r[k] : 0; }

    // ───────────── lyrics (LRCLIB synced first; Genius plain-text fallback) ─────────────
    property bool lyricsWanted: false
    property var lyricsLines: []               // [{ t: seconds (-1 = not synced), text }]
    property bool lyricsSynced: false
    property string lyricsState: "idle"        // idle | loading | ok | none
    property string lyricsReqKey: ""
    property string lrcTitle: ""
    property string lrcArtist: ""
    property string lrcAlbum: ""
    property string lrcDur: ""
    readonly property string trackKey: player ? (player.trackTitle + "|" + player.trackArtist + "|" + player.trackAlbum + "|"
                                                  + Math.round(player.lengthSupported ? player.length : 0)) : ""
    onTrackKeyChanged: {
        lyricsLines = []; lyricsSynced = false; lyricsState = "idle";
        if (lyricsWanted) lyricsSoon.restart();
    }
    onLyricsWantedChanged: if (lyricsWanted && lyricsState === "idle") lyricsSoon.restart()
    Timer { id: lyricsSoon; interval: 500; onTriggered: root.fetchLyrics() }

    function fetchLyrics() {
        if (!lyricsWanted || !player || player.trackTitle === "") return;
        if (lrcProc.running) return;                      // finished handler re-checks the key
        lyricsReqKey = trackKey;
        lrcTitle = player.trackTitle; lrcArtist = player.trackArtist; lrcAlbum = player.trackAlbum;
        lrcDur = String(Math.round(player.lengthSupported ? player.length : 0));
        lyricsState = "loading";
        lrcProc.running = true;
    }
    function parseLrc(txt) {
        var out = [], lines = String(txt).split(/\r?\n/);
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i], re = /\[(\d+):(\d+(?:\.\d+)?)\]/g, times = [], m;
            while ((m = re.exec(line)) !== null) times.push(parseInt(m[1]) * 60 + parseFloat(m[2]));
            if (times.length === 0) continue;
            var text = line.replace(/\[[^\]]*\]/g, "").trim();
            for (var j = 0; j < times.length; j++) out.push({ t: times[j], text: text });
        }
        out.sort(function (a, b) { return a.t - b.t; });
        return out;
    }
    function applyLyrics(raw) {
        var o = null;
        try { o = JSON.parse(raw); } catch (err) { }
        if (Array.isArray(o)) {                           // search fallback: prefer a result with synced lyrics
            var pick = null;
            for (var i = 0; i < o.length; i++) {
                if (o[i].syncedLyrics) { pick = o[i]; break; }
                if (!pick && o[i].plainLyrics) pick = o[i];
            }
            o = pick;
        }
        if (!o || o.instrumental) { lyricsLines = []; lyricsSynced = false; lyricsState = "none"; return; }
        if (o.syncedLyrics) {
            var l = parseLrc(o.syncedLyrics);
            if (l.length > 0) { lyricsLines = l; lyricsSynced = true; lyricsState = "ok"; return; }
        }
        if (o.plainLyrics) {
            var ps = String(o.plainLyrics).split(/\r?\n/), pl = [];
            for (var k = 0; k < ps.length; k++) if (ps[k].trim() !== "") pl.push({ t: -1, text: ps[k].trim() });
            if (pl.length > 0) { lyricsLines = pl; lyricsSynced = false; lyricsState = "ok"; return; }
        }
        lyricsLines = []; lyricsSynced = false; lyricsState = "none";
    }
    Process {
        id: lrcProc
        command: ["sh", "-c",
            "UA='macshell-widgets (quickshell)'; "
            + "r=$(curl -fsS --max-time 8 -A \"$UA\" -G https://lrclib.net/api/get --data-urlencode \"track_name=$1\" --data-urlencode \"artist_name=$2\" "
            + "--data-urlencode \"album_name=$3\" -d \"duration=$4\" 2>/dev/null "
            + "|| curl -fsS --max-time 8 -A \"$UA\" -G https://lrclib.net/api/search --data-urlencode \"q=$2 $1\" 2>/dev/null || true); "
            + "if printf '%s' \"$r\" | jq -e 'if type == \"array\" then any(.[]; (.syncedLyrics // \"\") != \"\") else (.syncedLyrics // \"\") != \"\" end' >/dev/null 2>&1; then printf '%s' \"$r\"; exit 0; fi; "
            + "g=$(python3 \"$HOME/.config/quickshell/MacShell/genius-lyrics.py\" \"$2\" \"$1\" \"$HOME/.cache/macshell/lyrics\" 2>/dev/null || true); "
            + "gp=$(printf '%s' \"$g\" | jq -r '.plain // empty' 2>/dev/null); "
            + "if [ -n \"$gp\" ]; then jq -nc --arg p \"$gp\" '{plainLyrics:$p}'; "
            + "elif [ -n \"$r\" ]; then printf '%s' \"$r\"; else printf '{}'; fi",
            "sh", root.lrcTitle, root.lrcArtist, root.lrcAlbum, root.lrcDur]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.lyricsReqKey !== root.trackKey) {            // the song changed while we were asking
                    root.lyricsState = "idle";
                    Qt.callLater(root.fetchLyrics);
                    return;
                }
                root.applyLyrics(text);
            }
        }
    }

    // ───────────── weather data (Open-Meteo) ─────────────
    property bool wxReady: false
    property string wxCity: "—"
    property bool wxLocated: true
    property int wxTemp: 0
    property int wxHi: 0
    property int wxLo: 0
    property int wxCode: 0
    property bool wxDay: true
    property string wxError: ""
    property real wxLat: 0
    property real wxLon: 0
    property string wxPlace: ""
    property var wxHourly: []
    property var wxDaily: []

    function wmo(code, day) {
        switch (code) {
        case 0:  return day ? { t: "Sunny", k: "sun" } : { t: "Clear", k: "moon" };
        case 1:  return day ? { t: "Mostly Sunny", k: "sun" } : { t: "Mostly Clear", k: "moon" };
        case 2:  return { t: "Partly Cloudy", k: day ? "partly" : "partlyNight" };
        case 3:  return { t: "Cloudy", k: "cloud" };
        case 45: case 48: return { t: "Foggy", k: "fog" };
        case 51: case 53: case 55: return { t: "Drizzle", k: "rain" };
        case 56: case 57: return { t: "Freezing Drizzle", k: "rain" };
        case 61: return { t: "Light Rain", k: "rain" };
        case 63: return { t: "Rain", k: "rain" };
        case 65: return { t: "Heavy Rain", k: "rain" };
        case 66: case 67: return { t: "Freezing Rain", k: "rain" };
        case 71: return { t: "Light Snow", k: "snow" };
        case 73: return { t: "Snow", k: "snow" };
        case 75: case 77: return { t: "Heavy Snow", k: "snow" };
        case 80: case 81: return { t: "Showers", k: "rain" };
        case 82: return { t: "Heavy Showers", k: "rain" };
        case 85: case 86: return { t: "Snow Showers", k: "snow" };
        case 95: case 96: case 99: return { t: "Thunderstorms", k: "storm" };
        }
        return { t: "Cloudy", k: "cloud" };
    }
    readonly property var wxInfo: wmo(wxCode, wxDay)
    function hourLabel(iso, first) {
        if (first) return "Now";
        var h = parseInt(iso.substr(11, 2));
        return (h % 12 === 0 ? 12 : h % 12) + (h < 12 ? "AM" : "PM");
    }
    function dayLabel(iso, i) {
        if (i === 0) return "Today";
        var d = new Date(parseInt(iso.substr(0, 4)), parseInt(iso.substr(5, 2)) - 1, parseInt(iso.substr(8, 2)));
        return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d.getDay()];
    }

    function refresh() {
        if (!ready || count("weather") === 0) return;
        if (locProc.running || geoProc.running || wxProc.running) return;
        if (locMode === "city" && cityName.trim() !== "") { geoProc.running = true; }
        else { locProc.running = true; }
    }
    function refreshSoon() { if (ready) refreshDebounce.restart(); }
    Timer { id: refreshDebounce; interval: 700; onTriggered: root.refresh() }
    Timer {
        interval: 15 * 60 * 1000
        repeat: true
        running: root.ready && root.count("weather") > 0
        onTriggered: root.refresh()
    }
    onWidgetCountChanged: if (count("weather") > 0 && !wxReady) refreshSoon()

    // automatic location (IP): ipwho.is, falling back to ipapi.co
    Process {
        id: locProc
        command: ["sh", "-c",
            "o=$(curl -fsS --max-time 8 https://ipwho.is/ 2>/dev/null); "
            + "case \"$o\" in *'\"latitude\"'*) printf '%s' \"$o\";; *) curl -fsS --max-time 8 https://ipapi.co/json/;; esac"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var o = JSON.parse(text);
                    if (o.latitude === undefined) throw "no position";
                    root.wxLat = Number(o.latitude); root.wxLon = Number(o.longitude);
                    root.wxPlace = o.city || o.region || o.country || "Current Location";
                    root.wxLocated = true;
                    wxProc.running = true;
                } catch (err) { root.wxError = "location lookup failed"; console.log("[macwidgets] location:", err, text.substring(0, 120)); }
            }
        }
    }
    // a city typed in Settings
    Process {
        id: geoProc
        command: ["curl", "-fsS", "--max-time", "8", "-G", "https://geocoding-api.open-meteo.com/v1/search",
                  "--data-urlencode", "name=" + root.cityName.trim(), "-d", "count=1", "-d", "language=en", "-d", "format=json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var r = JSON.parse(text).results[0];
                    root.wxLat = Number(r.latitude); root.wxLon = Number(r.longitude);
                    root.wxPlace = r.name;
                    root.wxLocated = false;
                    wxProc.running = true;
                } catch (err) { root.wxError = "city not found"; console.log("[macwidgets] geocoding:", err); }
            }
        }
    }
    Process {
        id: wxProc
        command: ["curl", "-fsS", "--max-time", "10", "-G", "https://api.open-meteo.com/v1/forecast",
                  "-d", "latitude=" + root.wxLat, "-d", "longitude=" + root.wxLon,
                  "-d", "current=temperature_2m,weather_code,is_day",
                  "-d", "hourly=temperature_2m,weather_code,is_day",
                  "-d", "daily=temperature_2m_max,temperature_2m_min,weather_code",
                  "-d", "temperature_unit=" + (root.tempUnit === "F" ? "fahrenheit" : "celsius"),
                  "-d", "timezone=auto", "-d", "forecast_days=6"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var o = JSON.parse(text);
                    root.wxTemp = Math.round(o.current.temperature_2m);
                    root.wxCode = o.current.weather_code;
                    root.wxDay = o.current.is_day === 1;
                    root.wxHi = Math.round(o.daily.temperature_2m_max[0]);
                    root.wxLo = Math.round(o.daily.temperature_2m_min[0]);
                    // next hours (starting with the current one) and the coming days
                    var hrs = [], ht = o.hourly.time, cur = String(o.current.time).substring(0, 13), start = 0, i;
                    for (i = 0; i < ht.length; i++) if (ht[i].substring(0, 13) === cur) { start = i; break; }
                    for (i = start; i < ht.length && hrs.length < 6; i++)
                        hrs.push({ h: root.hourLabel(ht[i], hrs.length === 0), t: Math.round(o.hourly.temperature_2m[i]),
                                   k: root.wmo(o.hourly.weather_code[i], o.hourly.is_day[i] === 1).k });
                    var dys = [], dt = o.daily.time;
                    for (i = 0; i < dt.length && i < 5; i++)
                        dys.push({ d: root.dayLabel(dt[i], i), lo: Math.round(o.daily.temperature_2m_min[i]),
                                   hi: Math.round(o.daily.temperature_2m_max[i]), k: root.wmo(o.daily.weather_code[i], true).k });
                    root.wxHourly = hrs; root.wxDaily = dys;
                    root.wxCity = root.wxPlace;
                    root.wxReady = true;
                    root.wxError = "";
                } catch (err) { root.wxError = "weather lookup failed"; console.log("[macwidgets] forecast:", err, text.substring(0, 120)); }
            }
        }
    }

    // ───────────── Liquid Glass backend ─────────────
    // Same shader as the Dock / Menu Bar (liquidglass.frag), compiled with qsb into ~/.config/macwidgets/.
    property string glassState: "idle"                     // idle → building → ready | failed
    readonly property string glassShaderSrc: decodeURIComponent(Qt.resolvedUrl("liquidglass.frag").toString().replace("file://", ""))
    readonly property string glassShaderOut: configDir + "/liquidglass.frag.qsb"
    onAnyLiquidChanged: if (anyLiquid) startGlass()
    onReadyChanged: if (ready && anyLiquid) startGlass()
    function startGlass() {
        if (!ready || glassState === "ready" || glassState === "building" || glassState === "failed") return;
        glassState = "building";
        qsbProc.running = true;
        if (hub) hub.refreshWallpaper();
    }
    Process {
        id: qsbProc
        command: ["sh", "-c",
            "mkdir -p \"$(dirname \"$2\")\"; "
            + "for q in qsb qsb6 qsb-qt6 /usr/lib/qt6/bin/qsb /usr/lib64/qt6/bin/qsb /usr/lib/qt/bin/qsb; do "
            + "  if command -v \"$q\" >/dev/null 2>&1; then \"$q\" --qt6 -o \"$2\" \"$1\" && exit 0; fi; "
            + "done; "
            + "[ -f \"$1.qsb\" ] && cp \"$1.qsb\" \"$2\" && exit 0; "
            + "exit 1",
            "sh", root.glassShaderSrc, root.glassShaderOut]
        stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.log("[macwidgets-glass] qsb:", text.trim()) }
        onExited: (code, status) => root.glassState = (code === 0 ? "ready" : "failed")
    }
    Binding { target: root.hub; property: "widgetsWantWallpaper"; value: root.anyLiquid }

    // animated wallpaper the widget glass plays behind itself: only while the Dock's "Real-time glass" AND "Animated wallpaper in glass" are on
    readonly property string liveWallVideo: (dock && dock.glassLive && hub && hub.bar) ? hub.bar.glassVideo : ""
    // the widgets sit on the first screen's desktop: their video pauses while windows cover it (or in Game Mode)
    readonly property bool liveWallPaused: {
        if (!hub || !hub.bar) return false;
        if (hub.bar.gaming) return true;
        return Quickshell.screens.length > 0 && hub.bar.screenCovered[Quickshell.screens[0].name] === true;
    }
    // wallpaper behind the widgets (same lookup as the Dock's Liquid Glass)
    readonly property var wallpaperMap: hub ? hub.wallpaperMap : ({})
    function wallpaperFor(screenName) {
        var p = (dock && dock.wallpaperPath !== "") ? dock.wallpaperPath
              : (wallpaperMap["wallpaper.monitors." + screenName] || wallpaperMap["wallpaper.last"]
                 || wallpaperMap["wallpaper.default"] || "");
        if (p.indexOf("~/") === 0) p = Quickshell.env("HOME") + p.substring(1);
        return p;
    }
    function fileUrl(p) {
        if (p === "") return "";
        if (p.indexOf("file://") === 0) return p;
        return "file://" + encodeURI(p).replace(/#/g, "%23").replace(/\?/g, "%3F");
    }

    // ───────────── the desktop layer ─────────────
    Variants {
        model: (root.ready && Quickshell.screens.length > 0 && (root.widgetCount > 0 || root.editing)) ? [Quickshell.screens[0]] : []

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            anchors { left: true; right: true; top: true; bottom: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.namespace: "macwidgets"
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // click-through unless editing; only the Player widgets (up to 4) take clicks, for their buttons
            mask: Region {
                item: root.editing ? ui : null
                regions: [ Region { item: hit0 }, Region { item: hit1 }, Region { item: hit2 }, Region { item: hit3 } ]
            }

            Item {
                id: ui
                anchors.fill: parent

                Item { id: hit0; x: root.pr(0, 0); y: root.pr(0, 1); width: root.pr(0, 2); height: root.pr(0, 3) }
                Item { id: hit1; x: root.pr(1, 0); y: root.pr(1, 1); width: root.pr(1, 2); height: root.pr(1, 3) }
                Item { id: hit2; x: root.pr(2, 0); y: root.pr(2, 1); width: root.pr(2, 2); height: root.pr(2, 3) }
                Item { id: hit3; x: root.pr(3, 0); y: root.pr(3, 1); width: root.pr(3, 2); height: root.pr(3, 3) }

                Rectangle {   // slight dim while editing
                    anchors.fill: parent
                    color: "black"
                    opacity: root.editing ? 0.16 : 0
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }

                Repeater {   // free Small-sized grid cells; Medium and Large snap across 2-cell footprints
                    model: {
                        var revision = root.rev;
                        return root.editing ? root.gridSlots(win.modelData.width, win.modelData.height) : [];
                    }
                    delegate: Rectangle {
                        required property var modelData
                        x: modelData.x
                        y: modelData.y
                        width: root.gridCell
                        height: root.gridCell
                        radius: 28
                        color: Qt.rgba(1, 1, 1, 0.018)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.10)
                    }
                }

                Repeater {
                    model: root.model
                    delegate: Item {
                        id: ww
                        required property string wid
                        required property string wtype
                        required property string wstyle
                        required property string wsize
                        required property string wmode
                        required property string wsrc
                        required property real wx
                        required property real wy

                        property real dragDX: 0
                        property real dragDY: 0
                        x: wx + dragDX
                        y: wy + dragDY
                        readonly property var baseDims: root.dims(wsize)
                        readonly property real radiusPx: 28 * root.widgetScale * (wsize === "small" ? 168 / 158 : (wsize === "medium" ? 358 / 338 : 1))
                        width: baseDims[0]
                        height: baseDims[1]

                        WidgetVisual {
                            id: visual
                            anchors.fill: parent
                            host: root
                            wtype: ww.wtype; wstyle: ww.wstyle; wsize: ww.wsize; wmode: ww.wmode; wsrc: ww.wsrc
                            sx: ww.x; sy: ww.y
                            sname: win.modelData.name; sw: win.modelData.width; sh: win.modelData.height
                        }

                        scale: dragArea.pressed ? 1.03 : 1.0
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        z: dragArea.pressed ? 10 : 1

                        // edit mode: outline + drag + remove
                        Rectangle {
                            anchors.fill: parent
                            visible: root.editing
                            radius: ww.radiusPx
                            color: "transparent"
                            border.width: 2
                            border.color: Qt.rgba(1, 1, 1, 0.55)
                        }
                        MouseArea {
                            id: dragArea
                            anchors.fill: parent
                            enabled: root.editing
                            cursorShape: root.editing ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor
                            property real px: 0
                            property real py: 0
                            onPressed: mouse => { var p = mapToItem(ui, mouse.x, mouse.y); px = p.x; py = p.y; }
                            onPositionChanged: mouse => {
                                if (!pressed) return;
                                var p = mapToItem(ui, mouse.x, mouse.y);
                                var nx = Math.max(0, Math.min(ui.width - ww.width, ww.wx + (p.x - px)));
                                var ny = Math.max(0, Math.min(ui.height - ww.height, ww.wy + (p.y - py)));
                                ww.dragDX = nx - ww.wx;
                                ww.dragDY = ny - ww.wy;
                            }
                            onReleased: {
                                root.moveWidget(ww.wid, ww.wx + ww.dragDX, ww.wy + ww.dragDY);
                                ww.dragDX = 0; ww.dragDY = 0;
                            }
                        }
                        Rectangle {   // image widget: choose another picture
                            visible: root.editing && ww.wtype === "image"
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                            width: chooseText.width + 22; height: 26; radius: 13
                            color: chooseMa.pressed ? "#D8D8DC" : "#F2F2F5"
                            border.width: 1
                            border.color: Qt.rgba(0, 0, 0, 0.18)
                            Text { id: chooseText; anchors.centerIn: parent; text: I18n.tr("Choose Image\u2026"); color: "#3A3A3C"; font.family: root.fontFamily; font.pixelSize: 12 }
                            MouseArea { id: chooseMa; anchors.fill: parent; onClicked: root.pickImage(ww.wid, "small") }
                        }
                        Rectangle {   // "−" remove badge
                            visible: root.editing
                            x: -8; y: -8
                            width: 24; height: 24; radius: 12
                            color: minusMa.pressed ? "#D8D8DC" : "#F2F2F5"
                            border.width: 1
                            border.color: Qt.rgba(0, 0, 0, 0.18)
                            Rectangle { anchors.centerIn: parent; width: 10; height: 2; radius: 1; color: "#3A3A3C" }
                            MouseArea { id: minusMa; anchors.fill: parent; onClicked: root.removeWidget(ww.wid) }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "widgets"
        function refresh(): void { root.refresh(); }
        function edit(on: bool): void { root.editing = on; }
    }
}
