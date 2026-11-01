// Desktop — the files, folders and apps sitting on your desktop, exactly as macOS shows them.
//
// Everything in the XDG Desktop directory appears here. Click to select (Ctrl / Shift-click adds, drag on empty desktop for a
// selection rectangle), drag to move one or many icons (positions live in ~/.config/macshell/desktop.json), double-click to open,
// drop one icon onto another to make a folder, drop onto a folder to move into it, right-click for the menu.
// Any folder can be linked onto the desktop (right-click → Add Folder to Desktop…), and folders can be given a colour.
//
// All pointer handling is in ONE MouseArea per screen that hit-tests the icon grid; DesktopIcon.qml only draws.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "I18n.js" as I18n
import "Fonts.js" as Fonts

Scope {
    id: root
    property var hub: null
    readonly property var dock: hub ? hub.dock : null
    readonly property var bar: hub ? hub.bar : null
    readonly property string fam: dock ? dock.fontFamily : "Open Runde"
    readonly property color accent: dock ? dock.accent : "#0A84FF"
    readonly property bool darkMode: dock ? dock.darkMode : true
    readonly property int iconSize: dock ? Math.max(32, Math.min(128, Math.round(dock.desktopIconSize || 48))) : 48
    readonly property string home: Quickshell.env("HOME")
    property string xdgDesktop: ""
    readonly property string dir: xdgDesktop !== "" ? xdgDesktop : home + "/Desktop"

    readonly property bool enabled: dock ? dock.desktopIcons : true

    onXdgDesktopChanged: if (enabled) scan()
    property var items: []                  // { name, path, isDir, isApp, kind }
    property var places: ({})               // "screen::name" → { x, y }

    // ── selection (path → true) ──
    property var selection: ({})
    readonly property int selectionCount: Object.keys(selection).length
    function isSelected(path) { return selection[path] === true; }
    function selectOnly(path) { var m = {}; m[path] = true; selection = m; }
    function clearSelection() { if (selectionCount > 0) selection = ({}); }
    function toggleSelect(path) {
        var m = {}; for (var k in selection) m[k] = true;
        if (m[path]) delete m[path]; else m[path] = true;
        selection = m;
    }
    function selectedItems() {
        var out = [];
        for (var i = 0; i < items.length; i++) if (selection[items[i].path] === true) out.push(items[i]);
        return out;
    }
    // forget selected things that are gone after a rescan
    onItemsChanged: {
        if (selectionCount === 0) return;
        var alive = {}, m = {}, changed = false;
        for (var i = 0; i < items.length; i++) alive[items[i].path] = true;
        for (var k in selection) { if (alive[k]) m[k] = true; else changed = true; }
        if (changed) selection = m;
    }

    readonly property int cellW: Math.max(96, iconSize + 32)
    readonly property int cellH: iconSize + 56      // highlight box (icon + padding) + two label lines
    readonly property int gridTop: 42
    readonly property int gridBottom: 24
    readonly property int gridSide: 16

    // is the widgets host in edit mode? Then it must receive the pointer, not us.
    readonly property bool widgetsEditing: hub && hub.widgets ? hub.widgets.editing : false
    // a Player widget's button area (the only part of the widgets layer that takes clicks); 0 when not on this screen
    function playerRect(screenName, i, k) {
        var wd = hub ? hub.widgets : null;
        if (!wd || Quickshell.screens.length === 0 || screenName !== Quickshell.screens[0].name) return 0;
        return wd.pr(i, k);
    }

    Process {
        running: true
        command: ["sh", "-c", "if command -v xdg-user-dir >/dev/null 2>&1; then xdg-user-dir DESKTOP; else printf '%s/Desktop' \"$HOME\"; fi"]
        stdout: StdioCollector { onStreamFinished: if (text.trim() !== "") root.xdgDesktop = text.trim() }
    }

    function positionKey(screenName, name) { return screenName + "::" + name; }
    function rectanglesOverlap(x, y, width, height, r, gap) {
        var g = gap || 0;
        return x < r.x + r.width + g && x + width + g > r.x
            && y < r.y + r.height + g && y + height + g > r.y;
    }
    function widgetRects(screenName) {
        var w = hub ? hub.widgets : null, screens = Quickshell.screens, out = [];
        // Widgets are currently hosted on the primary screen; other monitors have no widget footprint to reserve.
        if (!w || !w.model || screens.length === 0 || screenName !== screens[0].name) return out;
        for (var i = 0; i < w.model.count; i++) {
            var m = w.model.get(i), d = w.dims(m.wsize);
            out.push({ x: m.wx, y: m.wy, width: d[0], height: d[1] });
        }
        return out;
    }
    function collidesWithWidget(x, y, screenName) {
        var rects = widgetRects(screenName);
        for (var i = 0; i < rects.length; i++)
            if (rectanglesOverlap(x, y, cellW, cellH, rects[i], 8)) return true;
        return false;
    }
    // the Dock's footprint on a screen (null when it is off or on another monitor), and the strip the top bar takes
    function dockRect(screenName, screenW, screenH) {
        var d = dock;
        if (!d || !d.dockEnabled || (d.monitor && d.monitor !== "" && d.monitor !== screenName)) return null;
        var dw = Math.min(screenW, Math.max(440, d.bgWidth || 540));
        var dh = Math.max(76, d.bgHeight || 88);
        return { x: (screenW - dw) / 2, y: screenH - dh - 10, width: dw, height: dh + 10 };
    }
    function barBottom() { return (bar && bar.barEnabled) ? bar.barH : 0; }
    // the free band between the top bar and the Dock, where menus and sheets belong
    function freeBottom(screenName, screenW, screenH, x0, x1) {
        var r = dockRect(screenName, screenW, screenH);
        return (r && x0 < r.x + r.width && x1 > r.x) ? r.y : screenH;
    }
    // things a menu / sheet must not hide behind: the widgets (own window) and the Dock (own layer)
    function blockers(screenName, screenW, screenH) {
        var out = [], wr = widgetRects(screenName);
        for (var i = 0; i < wr.length; i++) out.push({ x: wr[i].x - 6, y: wr[i].y - 6, width: wr[i].width + 12, height: wr[i].height + 12 });
        var d = dockRect(screenName, screenW, screenH);
        if (d) out.push({ x: d.x - 6, y: d.y - 6, width: d.width + 12, height: d.height + 12 });
        return out;
    }
    // the free spot for a w x h box nearest to (px, py): inside the screen, under the top bar, off the widgets and the Dock
    function placeNear(w, h, px, py, screenName, screenW, screenH) {
        var bl = blockers(screenName, screenW, screenH);
        var x0 = 8, x1 = Math.max(8, screenW - w - 8), y0 = barBottom() + 8, y1 = Math.max(y0, screenH - 8 - h);
        function overlapArea(x, y) {
            var a = 0;
            for (var i = 0; i < bl.length; i++) {
                var ox = Math.min(x + w, bl[i].x + bl[i].width) - Math.max(x, bl[i].x);
                var oy = Math.min(y + h, bl[i].y + bl[i].height) - Math.max(y, bl[i].y);
                if (ox > 0 && oy > 0) a += ox * oy;
            }
            return a;
        }
        function score(x, y) { return overlapArea(x, y) * 1000 + (x - px) * (x - px) + (y - py) * (y - py); }
        var bx = Math.max(x0, Math.min(x1, px)), by = Math.max(y0, Math.min(y1, py)), best = score(bx, by);
        if (overlapArea(bx, by) > 0 || bx !== px || by !== py) {
            for (var x = x0; x <= x1; x += 24)
                for (var y = y0; y <= y1; y += 24) {
                    var sc = score(x, y);
                    if (sc < best) { best = sc; bx = x; by = y; }
                }
        }
        return { x: bx, y: by, score: best };
    }
    function collidesWithDock(x, y, screenName, screenW, screenH) {
        var d = dock;
        if (!d || !d.dockEnabled || (d.monitor && d.monitor !== "" && d.monitor !== screenName)) return false;
        var dw = Math.min(screenW, Math.max(440, d.bgWidth || 540));
        var dh = Math.max(76, d.bgHeight || 88);
        return rectanglesOverlap(x, y, cellW, cellH,
            { x: (screenW - dw) / 2, y: screenH - dh - 10, width: dw, height: dh + 10 }, 4);
    }
    function gridCells(screenW, screenH) {
        var cols = Math.max(0, Math.floor((screenW - 2 * gridSide) / cellW));
        var rows = Math.max(0, Math.floor((screenH - gridTop - gridBottom) / cellH));
        var left = screenW - gridSide - cols * cellW, cells = [];
        // Fill rightmost column first, top to bottom, like the familiar macOS desktop layout.
        for (var col = cols - 1; col >= 0; col--)
            for (var row = 0; row < rows; row++)
                cells.push({ x: left + col * cellW, y: gridTop + row * cellH });
        return cells;
    }
    function isCellFree(cell, screenName, screenW, screenH, occupied) {
        if (collidesWithWidget(cell.x, cell.y, screenName) || collidesWithDock(cell.x, cell.y, screenName, screenW, screenH)) return false;
        for (var i = 0; i < occupied.length; i++)
            if (rectanglesOverlap(cell.x, cell.y, cellW, cellH, occupied[i], 0)) return false;
        return true;
    }
    function computeLayout(screenName, screenW, screenH) {
        var cells = gridCells(screenW, screenH), result = ({}), occupied = [];
        var legacyAllowed = Quickshell.screens.length > 0 && screenName === Quickshell.screens[0].name;
        for (var i = 0; i < items.length; i++) {
            var name = items[i].name, wanted = places[positionKey(screenName, name)];
            if (!wanted && legacyAllowed) wanted = places[name];
            var best = null, bestDistance = Infinity;
            for (var j = 0; j < cells.length; j++) {
                var c = cells[j];
                if (!isCellFree(c, screenName, screenW, screenH, occupied)) continue;
                if (!wanted) { best = c; break; }
                var wantedX = Number(wanted.x) < 0 ? screenW + Number(wanted.x) : Number(wanted.x);
                var dx = c.x - wantedX, dy = c.y - Number(wanted.y), dist = dx * dx + dy * dy;
                if (dist < bestDistance) { bestDistance = dist; best = c; }
            }
            result[name] = best;
            if (best) occupied.push({ x: best.x, y: best.y, width: cellW, height: cellH });
        }
        return result;
    }
    function nearestFreePlace(name, screenName, x, y, screenW, screenH, layout) {
        var cells = gridCells(screenW, screenH), occupied = [], best = null, bestDistance = Infinity;
        for (var key in layout) {
            var p = layout[key];
            if (key !== name && p) occupied.push({ x: p.x, y: p.y, width: cellW, height: cellH });
        }
        for (var i = 0; i < cells.length; i++) {
            var c = cells[i];
            if (!isCellFree(c, screenName, screenW, screenH, occupied)) continue;
            var dx = c.x - x, dy = c.y - y, dist = dx * dx + dy * dy;
            if (dist < bestDistance) { bestDistance = dist; best = c; }
        }
        return best;
    }

    function pointOverWidget(x, y, screenName) {
        var rects = widgetRects(screenName);
        for (var i = 0; i < rects.length; i++)
            if (x >= rects[i].x && x <= rects[i].x + rects[i].width && y >= rects[i].y && y <= rects[i].y + rects[i].height) return true;
        return false;
    }

    // ── folder colours ──
    // path → colour name. The coloured folders come from the icon pack (folder_color_<name>); where the pack has none, SVGs written once
    // into ~/.cache/macshell/desktop-folders are the fallback.
    property var folderColors: ({})
    readonly property var folderPalette: ({
        blue:   ["#8FD0F7", "#5BB4EE", "#74C4F5", "#3C9FE4"],
        red:    ["#FF9F98", "#F2625A", "#FF8179", "#E5483F"],
        orange: ["#FFC980", "#FF9F43", "#FFB45F", "#F5821F"],
        yellow: ["#FFE88F", "#F7C948", "#FFDC66", "#EDB11A"],
        green:  ["#A8EAA3", "#5CCB6B", "#8EDF91", "#34B34A"],
        purple: ["#D5AEF7", "#A66BE0", "#C493F2", "#8E4CD1"],
        pink:   ["#FFB5D3", "#F76FA3", "#FF95C0", "#EA4B88"],
        gray:   ["#CDD1D7", "#9AA0A8", "#BABFC6", "#7E848C"]
    })
    // the dots of the menu's colour row: "none" = the normal theme folder
    readonly property var folderSwatches: [
        { name: "none", color: "#8E8E93" }, { name: "red", color: "#F2625A" }, { name: "orange", color: "#FF9F43" },
        { name: "yellow", color: "#F7C948" }, { name: "green", color: "#5CCB6B" }, { name: "blue", color: "#4DA8EC" },
        { name: "purple", color: "#A66BE0" }, { name: "pink", color: "#F76FA3" }, { name: "gray", color: "#9AA0A8" }
    ]
    readonly property string folderDir: home + "/.cache/macshell/desktop-folders"
    property bool folderIconsReady: false
    function folderSvg(c) {
        return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128"><defs>'
            + '<linearGradient id="back" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="' + c[0] + '"/><stop offset="1" stop-color="' + c[1] + '"/></linearGradient>'
            + '<linearGradient id="front" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="' + c[2] + '"/><stop offset="1" stop-color="' + c[3] + '"/></linearGradient></defs>'
            + '<path d="M10 36c0-5 4-9 9-9h30l11 11h58c5 0 9 4 9 9v12H10z" fill="url(#back)"/>'
            + '<path d="M10 46h108c5 0 9 4 9 9v45c0 5-4 9-9 9H19c-5 0-9-4-9-9z" fill="url(#front)"/>'
            + '<path d="M10 46h108c5 0 9 4 9 9v4H10z" fill="#ffffff" opacity="0.18"/></svg>';
    }
    function folderGenCommand() {
        var cmd = ["sh", "-c", "d=\"$1\"; shift; mkdir -p \"$d\"; while [ $# -ge 2 ]; do printf '%s' \"$2\" > \"$d/$1.svg\"; shift 2; done", "sh", folderDir];
        for (var n in folderPalette) { cmd.push(n); cmd.push(folderSvg(folderPalette[n])); }
        return cmd;
    }
    Process {
        running: true
        command: root.folderGenCommand()
        onExited: root.folderIconsReady = true
    }
    FileView {
        id: colorFile
        path: root.home + "/.config/macshell/desktop-colors.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.folderColors = JSON.parse(text()); } catch (e) { root.folderColors = ({}); } }
    }
    // ── folder glyphs (the symbol on a folder: code, music, games, ...) ──
    // The icon pack ships folder_color_<colour>_<glyph>.svg. path → glyph name, kept in ~/.config/macshell/desktop-glyphs.json.
    property var folderGlyphs: ({})
    property var glyphList: ["code", "desktop", "documents", "downloads", "games", "github", "music", "pictures", "projects", "public", "steam", "templates"]
    FileView {
        id: glyphFile
        path: root.home + "/.config/macshell/desktop-glyphs.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.folderGlyphs = JSON.parse(text()); } catch (e) { root.folderGlyphs = ({}); } }
    }
    function setFolderGlyph(paths, name) {
        var m = {}; for (var k in folderGlyphs) m[k] = folderGlyphs[k];
        for (var i = 0; i < paths.length; i++) { if (name === "") delete m[paths[i]]; else m[paths[i]] = name; }
        folderGlyphs = m;
        Quickshell.execDetached(["sh", "-c", "mkdir -p \"$HOME/.config/macshell\" && printf '%s' \"$1\" > \"$HOME/.config/macshell/desktop-glyphs.json\"", "sh", JSON.stringify(m)]);
    }
    // which glyphs the installed icon pack really has (looked up once: every folder_color_purple_<glyph> file in the icon folders)
    Process {
        running: true
        command: ["sh", "-c", "for d in \"$HOME/.local/share/icons\" \"$HOME/.icons\" /usr/share/icons /usr/local/share/icons; do [ -d \"$d\" ] && find -L \"$d\" -name 'folder_color_purple_*.svg' -printf '%f\\n' 2>/dev/null; done | sed 's/^folder_color_purple_//; s/\\.svg$//' | sort -u"]
        stdout: StdioCollector {
            onStreamFinished: {
                var l = text.split("\n").map(function (x) { return x.trim(); }).filter(function (x) { return x !== ""; });
                if (l.length > 0) root.glyphList = l;
            }
        }
    }
    // the icon for a folder colour + glyph, "" when the pack has no such file
    function glyphIcon(color, glyph) {
        if (!glyph) return "";
        return Quickshell.iconPath("folder_color_" + (color || "blue") + "_" + glyph, true);
    }
    function setFolderColor(paths, name) {
        var m = {}; for (var k in folderColors) m[k] = folderColors[k];
        for (var i = 0; i < paths.length; i++) { if (name === "none") delete m[paths[i]]; else m[paths[i]] = name; }
        folderColors = m;
        Quickshell.execDetached(["sh", "-c", "mkdir -p \"$HOME/.config/macshell\" && printf '%s' \"$1\" > \"$HOME/.config/macshell/desktop-colors.json\"", "sh", JSON.stringify(m)]);
    }

    // ── info for Quick Preview ──
    property var info: ({})
    function loadInfo(it) {
        info = ({});
        statProc.running = false;
        statProc.command = ["sh", "-c",
            "stat -L --printf '%s\\t%W\\t%Y\\t%A\\t%U\\n' -- \"$1\" 2>/dev/null || stat --printf '%s\\t%W\\t%Y\\t%A\\t%U\\n' -- \"$1\"; "
            + "if [ -d \"$1\" ]; then ls -A -- \"$1\" 2>/dev/null | wc -l; else { file -b --mime-type -- \"$1\" 2>/dev/null || echo; }; fi; "
            + "if [ -L \"$1\" ]; then readlink -f -- \"$1\"; fi; true", "sh", it.path];
        statProc.running = true;
    }
    Process {
        id: statProc
        stdout: StdioCollector {
            onStreamFinished: {
                var l = text.split("\n"), a = (l[0] || "").split("\t");
                root.info = { size: Number(a[0]), birth: Number(a[1]), mod: Number(a[2]), perms: a[3] || "", owner: a[4] || "",
                              extra: (l[1] || "").trim(), link: (l[2] || "").trim(), ready: true };
            }
        }
    }
    function humanSize(n) {
        if (isNaN(n)) return "\u2014";
        var u = ["bytes", "KB", "MB", "GB", "TB"], i = 0, v = n;
        while (v >= 1000 && i < u.length - 1) { v /= 1000; i++; }
        return (i === 0 ? String(n) : (v >= 100 ? v.toFixed(0) : v.toFixed(1))) + " " + u[i];
    }
    function fmtDate(sec) {
        if (!sec || sec <= 0 || isNaN(sec)) return "\u2014";
        return Qt.formatDateTime(new Date(sec * 1000), "ddd d MMM yyyy, HH:mm");
    }
    function kindOf(it, f) {
        if (it.isApp) return I18n.tr("Application");
        if (it.isDir) return it.isLink ? I18n.tr("Folder link") : I18n.tr("Folder");
        var m = f && f.extra ? f.extra : "";
        var e = it.name.indexOf(".") > 0 ? it.name.split(".").pop().toUpperCase() : "";
        if (it.kind === "Image") return I18n.tr("Image") + (e ? " (" + e + ")" : "");
        if (m.indexOf("text/") === 0) return I18n.tr("Text document") + (e ? " (" + e + ")" : "");
        if (m.indexOf("video/") === 0) return I18n.tr("Video") + (e ? " (" + e + ")" : "");
        if (m.indexOf("audio/") === 0) return I18n.tr("Audio") + (e ? " (" + e + ")" : "");
        if (m === "application/pdf") return "PDF " + I18n.tr("document");
        return e ? e + " " + I18n.tr("file") : I18n.tr("Document");
    }

    // ── linking a folder onto the desktop ──
    signal linkFinished(int code)
    signal pathPicked(string path)
    property bool picking: false
    function linkFolder(path) {
        linkProc.running = false;
        linkProc.command = ["sh", "-c",
            "p=\"$1\"; d=\"$2\"; case \"$p\" in '~') p=\"$HOME\";; '~/'*) p=\"$HOME/${p#'~/'}\";; esac; "
            + "[ \"$p\" != / ] && p=\"${p%/}\"; [ -e \"$p\" ] || exit 1; mkdir -p \"$d\"; "
            + "n=$(basename \"$p\"); [ \"$p\" = / ] && n=root; t=\"$d/$n\"; i=2; "
            + "while [ -e \"$t\" ] || [ -L \"$t\" ]; do t=\"$d/$n $i\"; i=$((i+1)); done; ln -s -- \"$p\" \"$t\"", "sh", path, root.dir];
        linkProc.running = true;
    }
    Process {
        id: linkProc
        onExited: code => { root.linkFinished(code); if (code === 0) rescan.restart(); }
    }
    function pickFolder() {
        if (pickProc.running) return;
        picking = true;
        pickProc.running = true;
    }
    Process {
        id: pickProc
        command: ["sh", "-c",
            "if command -v kdialog >/dev/null 2>&1; then kdialog --getexistingdirectory \"$HOME\"; "
            + "elif command -v zenity >/dev/null 2>&1; then zenity --file-selection --directory --filename=\"$HOME/\"; "
            + "elif command -v yad >/dev/null 2>&1; then yad --file --directory --filename=\"$HOME/\"; fi"]
        stdout: StdioCollector { onStreamFinished: { var t = text.trim(); if (t !== "") root.pathPicked(t); } }
        onExited: root.picking = false
    }

    // the picture for one item (also used by the menu bar's glass backdrop, so the glass shows the same icons)
    function iconSourceFor(m) {
        if (m.kind === "Image") return fileUrl(m.path);
        if (m.isDir) {
            var c = folderColors[m.path];
            var gi = glyphIcon(c, folderGlyphs[m.path]);
            if (gi !== "") return gi;
            if (c && folderPalette[c] !== undefined) {
                // the icon pack's own coloured folder first: folder_color_<name> (folder_color_green.svg, ...)
                var pk = Quickshell.iconPath("folder_color_" + c, true);
                if (pk !== "") return pk;
                // the pack has none of that colour: the built-in generated SVG
                if (folderIconsReady) return fileUrl(folderDir + "/" + c + ".svg");
            }
            return dock && dock.iconSrc ? dock.iconSrc("folder") : Quickshell.iconPath("folder");
        }
        if (m.isApp) return appIcon(m.path);
        return Quickshell.iconPath("text-x-generic", "application-x-executable");
    }
    function fileUrl(path) {
        return "file://" + encodeURI(path).replace(/#/g, "%23").replace(/\?/g, "%3F");
    }


    function scan() {
        lsProc.running = false;
        lsProc.command = ["sh", "-c",
            "mkdir -p \"$1\"; cd \"$1\" && find . -mindepth 1 -maxdepth 1 ! -name '.*' -printf '%Y\\t%y\\t%f\\n' 2>/dev/null | LC_ALL=C sort -t\"$(printf '\\t')\" -k1,1 -k3,3f | head -200", "sh", root.dir];
        lsProc.running = true;
    }
    Process {
        id: lsProc
        stdout: StdioCollector {
            onStreamFinished: {
                var out = [], ls = text.split("\n");
                for (var i = 0; i < ls.length; i++) {
                    var c = ls[i].split("\t");
                    if (c.length < 3) continue;
                    var name = c[2], isDir = c[0] === "d", isLink = c[1] === "l", isApp = /\.desktop$/i.test(name);
                    var e = name.toLowerCase().split(".").pop();
                    out.push({ name: name, path: root.dir + "/" + name, isDir: isDir, isApp: isApp, isLink: isLink,
                               kind: isDir ? "Folder" : (["png", "jpg", "jpeg", "webp", "gif", "bmp", "avif"].indexOf(e) >= 0 ? "Image" : "File") });
                }
                root.items = out;
            }
        }
    }
    FileView {
        id: placeFile
        path: root.home + "/.config/macshell/desktop.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.places = JSON.parse(text()); } catch (e) { root.places = ({}); } }
    }

    function savePlaces() {
        Quickshell.execDetached(["sh", "-c", "mkdir -p \"$HOME/.config/macshell\" && printf '%s' \"$1\" > \"$HOME/.config/macshell/desktop.json\"", "sh", JSON.stringify(places)]);
    }
    function setPlace(name, screenName, x, y) {
        var m = {}; for (var k in places) m[k] = places[k];
        m[positionKey(screenName, name)] = { x: x, y: y };
        places = m; savePlaces();
    }
    // several icons at once (a group drag): one write
    function setPlaces(screenName, byName) {
        var m = {}; for (var k in places) m[k] = places[k];
        for (var n in byName) m[positionKey(screenName, n)] = byName[n];
        places = m; savePlaces();
    }
    readonly property string folderScript: decodeURIComponent(String(Qt.resolvedUrl("assets/open-folder.sh")).replace(/^file:\/\//, ""))
    function openItem(it) {
        if (it.isApp) {
            var id = it.name.replace(/\.desktop$/i, "");
            var launchScript = "if command -v dex >/dev/null 2>&1; then dex \"$1\" && exit 0; fi; "
                + "if command -v gtk-launch >/dev/null 2>&1; then gtk-launch \"$2\" 2>/dev/null && exit 0; fi; "
                + "exec_line=$(awk -F= '$0 == \"[Desktop Entry]\" { active=1; next } active && /^\\[/ { exit } active && $1 == \"Exec\" { sub(/^[^=]*=/, \"\"); print; exit }' \"$1\"); "
                + "terminal=$(awk -F= '$0 == \"[Desktop Entry]\" { active=1; next } active && /^\\[/ { exit } active && $1 == \"Terminal\" { print tolower($2); exit }' \"$1\"); "
                + "exec_line=$(printf '%s\\n' \"$exec_line\" | sed -E 's/%[fFuUdDnNickvm]//g; s/%%/%/g'); "
                + "[ -n \"$exec_line\" ] || exec xdg-open \"$1\"; "
                + "if [ \"$terminal\" = true ]; then for t in x-terminal-emulator kitty foot alacritty wezterm konsole xfce4-terminal xterm; do c=$(command -v \"$t\" 2>/dev/null) || continue; \"$c\" -e sh -c \"$exec_line\" && exit 0; done; fi; "
                + "exec sh -c \"$exec_line\"";
            Quickshell.execDetached(["sh", "-c", launchScript, "sh", it.path, id]);
            return;
        }
        // folders open in a graphical file manager (the system default, unless that is a terminal program); files go through the Bar's viewer / xdg-open
        if (it.isDir) { Quickshell.execDetached(["bash", folderScript, it.path]); return; }
        if (hub && hub.bar && hub.bar.openPath) { hub.bar.openPath(it.path); return; }
        Quickshell.execDetached(["xdg-open", it.path]);
    }
    function newFolder() {
        Quickshell.execDetached(["sh", "-c", "cd \"$1\" && n='untitled folder'; i=2; while [ -e \"$n\" ]; do n=\"untitled folder $i\"; i=$((i+1)); done; mkdir \"$n\"", "sh", root.dir]);
        rescan.restart();
    }
    // dropping one icon onto another makes a folder holding both, the way macOS does
    function combine(aPath, bPath) {
        Quickshell.execDetached(["sh", "-c",
            "d=\"$1\"; a=\"$2\"; b=\"$3\"; n=\"$d/New Folder\"; i=2; while [ -e \"$n\" ]; do n=\"$d/New Folder $i\"; i=$((i+1)); done; "
            + "mkdir \"$n\" && mv \"$a\" \"$b\" \"$n\"/", "sh", root.dir, aPath, bPath]);
        rescan.restart();
    }
    function moveInto(srcPath, folderPath) { moveMany([srcPath], folderPath); }
    function moveMany(paths, folderPath) {
        Quickshell.execDetached(["sh", "-c", "d=\"$1\"; shift; for f in \"$@\"; do [ \"$f\" = \"$d\" ] || mv -- \"$f\" \"$d\"/; done", "sh", folderPath].concat(paths));
        rescan.restart();
    }
    function trash(path) { trashMany([path]); }
    function trashMany(paths) {
        Quickshell.execDetached(["sh", "-c", "for f in \"$@\"; do gio trash \"$f\" 2>/dev/null || { mkdir -p \"$HOME/.local/share/Trash/files\" && mv -- \"$f\" \"$HOME/.local/share/Trash/files/\"; }; done", "sh"].concat(paths));
        clearSelection();
        rescan.restart();
    }
    Timer { id: rescan; interval: 400; onTriggered: root.scan() }
    Timer { interval: 3000; repeat: true; running: root.enabled; triggeredOnStart: true; onTriggered: root.scan() }

    Variants {
        model: root.enabled ? Quickshell.screens : []
        PanelWindow {
            id: w
            required property var modelData
            screen: modelData
            property int widgetRevision: root.hub && root.hub.widgets ? root.hub.widgets.rev : 0
            property real widgetScale: root.hub && root.hub.widgets ? root.hub.widgets.widgetScale : 1
            property var layoutMap: {
                var _revision = widgetRevision, _scale = widgetScale, _items = root.items.length, _places = root.places;
                return root.computeLayout(modelData.name, width, height);
            }
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "macdesktop"
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.keyboardFocus: ((renameSheet.open || linkSheet.open) && !root.picking) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            // The whole screen takes the pointer (empty desktop: selection rectangle, right-click menu) EXCEPT
            //   * a Player widget's buttons, which live in the widgets window and still have to be clickable, and
            //   * everything, while the widgets are being edited (the widgets window needs the pointer then).
            mask: Region {
                item: root.widgetsEditing ? null : iconLayer
                regions: [
                    Region { item: pr0; intersection: Intersection.Subtract },
                    Region { item: pr1; intersection: Intersection.Subtract },
                    Region { item: pr2; intersection: Intersection.Subtract },
                    Region { item: pr3; intersection: Intersection.Subtract }
                ]
            }

            // any glass (right-click menu or a sheet) on screen?
            readonly property bool glassNeeded: dctx.open || renameSheet.visible || previewSheet.visible || picSheet.visible || linkSheet.visible || glyphSheet.visible
            // Shortly after start-up every sheet is shown once at opacity 0.01: the glass (shaders, blur and mask objects, canvases) gets
            // built and compiled then, instead of during the first real Quick Preview.
            property bool warm: false
            Timer { running: true; interval: 3000; onTriggered: { w.warm = true; warmOff.start(); } }
            Timer { id: warmOff; interval: 1500; onTriggered: w.warm = false }
            readonly property bool sheetOpen: renameSheet.open || previewSheet.open || picSheet.open || linkSheet.open || glyphSheet.open
            function closeSheets() { renameSheet.open = false; previewSheet.open = false; picSheet.open = false; linkSheet.open = false; glyphSheet.open = false; }
            // puts a sheet in the middle of the band between the top bar and the Dock, off the widgets
            function placeSheet(sh) {
                var top = root.barBottom() + 8;
                var bottom = root.freeBottom(modelData.name, width, height, (width - sh.width) / 2, (width + sh.width) / 2) - 8;
                var p = root.placeNear(sh.width, sh.height, (width - sh.width) / 2, top + Math.max(0, (bottom - top - sh.height) / 2) - 16, modelData.name, width, height);
                sh.x = p.x; sh.y = p.y;
            }
            // the centre of an icon, where a sheet grows out of
            function iconCenter(it) {
                var p = it ? layoutMap[it.name] : null;
                return p ? Qt.point(p.x + root.cellW / 2, p.y + (root.iconSize + 20) / 2) : Qt.point(width / 2, height / 2);
            }

            // ── interaction state of this screen ──
            property bool dragActive: false      // icons are being dragged
            property real dragDX: 0
            property real dragDY: 0
            property string dropPath: ""         // icon the dragged ones would land on
            property bool marqueeActive: false
            property real mqX0: 0
            property real mqY0: 0
            property real mqX1: 0
            property real mqY1: 0

            // the icon under a point (the whole cell counts), or null
            function iconAt(x, y) {
                for (var i = 0; i < root.items.length; i++) {
                    var p = layoutMap[root.items[i].name];
                    if (p && x >= p.x + 4 && x <= p.x + root.cellW - 4 && y >= p.y + 2 && y <= p.y + root.cellH - 2) return root.items[i];
                }
                return null;
            }
            // icons touched by the selection rectangle
            function itemsInRect(x0, y0, x1, y1) {
                var l = Math.min(x0, x1), r = Math.max(x0, x1), t = Math.min(y0, y1), b = Math.max(y0, y1), out = [];
                for (var i = 0; i < root.items.length; i++) {
                    var p = layoutMap[root.items[i].name];
                    if (!p) continue;
                    var bx = p.x + (root.cellW - (root.iconSize + 20)) / 2, bw = root.iconSize + 20;
                    if (bx < r && bx + bw > l && p.y < b && p.y + root.cellH - 8 > t) out.push(root.items[i]);
                }
                return out;
            }
            // drop the dragged icons: onto a folder / another icon, or snap each to the nearest free cell
            function finishDrag(px, py) {
                var moved = root.selectedItems().filter(function (it) { return !!layoutMap[it.name]; });
                var dx = dragDX, dy = dragDY;
                dragActive = false; dragDX = 0; dragDY = 0; dropPath = "";
                if (moved.length === 0) return;
                var target = iconAt(px, py);
                if (target && root.isSelected(target.path)) target = null;
                if (target && target.isDir) { root.moveMany(moved.map(function (it) { return it.path; }), target.path); return; }
                if (target && moved.length === 1) { root.combine(moved[0].path, target.path); return; }

                var layout = {}, k;
                for (k in layoutMap) layout[k] = layoutMap[k];
                var start = {};
                for (var i = 0; i < moved.length; i++) { start[moved[i].name] = layout[moved[i].name]; delete layout[moved[i].name]; }
                var result = {}, any = false;
                for (var j = 0; j < moved.length; j++) {
                    var n = moved[j].name, o = start[n];
                    var f = root.nearestFreePlace(n, modelData.name, o.x + dx, o.y + dy, width, height, layout);
                    if (f) { layout[n] = f; result[n] = { x: f.x, y: f.y }; any = true; }
                    else layout[n] = o;
                }
                if (any) root.setPlaces(modelData.name, result);
            }

            Item {
                id: iconLayer
                anchors.fill: parent

                // hit areas of the Player widgets' buttons, cut out of the mask above
                Item { id: pr0; x: root.playerRect(w.modelData.name, 0, 0); y: root.playerRect(w.modelData.name, 0, 1); width: root.playerRect(w.modelData.name, 0, 2); height: root.playerRect(w.modelData.name, 0, 3) }
                Item { id: pr1; x: root.playerRect(w.modelData.name, 1, 0); y: root.playerRect(w.modelData.name, 1, 1); width: root.playerRect(w.modelData.name, 1, 2); height: root.playerRect(w.modelData.name, 1, 3) }
                Item { id: pr2; x: root.playerRect(w.modelData.name, 2, 0); y: root.playerRect(w.modelData.name, 2, 1); width: root.playerRect(w.modelData.name, 2, 2); height: root.playerRect(w.modelData.name, 2, 3) }
                Item { id: pr3; x: root.playerRect(w.modelData.name, 3, 0); y: root.playerRect(w.modelData.name, 3, 1); width: root.playerRect(w.modelData.name, 3, 2); height: root.playerRect(w.modelData.name, 3, 3) }

                // A local monitor-sized wallpaper copy is the source for the right-click menu's glass.
                // It is never visible on screen: opacity 0 (a ShaderEffectSource ignores its source's own opacity, the same idiom the
                // Bar's backdrop uses). Drawn normally it was a full-screen opaque picture that covered the desktop widgets, which is
                // why they vanished on every right-click.
                Item {
                    id: desktopGlassBackdrop
                    anchors.fill: parent
                    z: -1
                    // Always "visible" (it is drawn at opacity 0, so it costs nothing on screen): the wallpaper copy stays decoded and
                    // uploaded, so opening a sheet no longer has to load a screen-sized texture in the middle of the animation.
                    visible: true
                    opacity: 0
                    Rectangle { anchors.fill: parent; color: root.darkMode ? "#242428" : "#e8e8ed" }
                    Image {
                        anchors.fill: parent
                        visible: status === Image.Ready
                        asynchronous: true
                        cache: true
                        smooth: true
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: width
                        source: root.dock && root.dock.wallpaperFor && root.dock.fileUrl
                            ? root.dock.fileUrl(root.dock.wallpaperFor(w.modelData.name)) : ""
                    }
                    LiveWall {
                        anchors.fill: parent
                        video: root.bar ? root.bar.glassVideo : ""
                        live: !!root.dock && root.dock.glassLive && dctx.open
                        paused: !w.glassNeeded || (!!root.bar && (root.bar.gaming || root.bar.screenCovered[w.modelData.name] === true))
                    }
                }

                // ── the one pointer handler: select, marquee, drag, open, menu ──
                MouseArea {
                    id: ptr
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    property real px: 0
                    property real py: 0
                    property bool addMode: false          // Ctrl / Shift held at press
                    property var pressedItem: null        // icon the press landed on
                    property string collapseTo: ""        // click on one of several selected icons (no drag) → select just it
                    property var baseSel: ({})            // selection a marquee starts from
                    property bool moved: false
                    property bool ignoring: false         // the press landed on a widget: the desktop does nothing (no menu, no selection)

                    onPressed: mouse => {
                        ignoring = root.pointOverWidget(mouse.x, mouse.y, w.modelData.name);
                        if (ignoring) {
                            // on a widget the desktop does nothing, except offering its settings
                            if (mouse.button === Qt.RightButton) dctx.show({ widget: true }, mouse.x, mouse.y);
                            return;
                        }
                        px = mouse.x; py = mouse.y; moved = false; collapseTo = "";
                        addMode = (mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) !== 0;
                        pressedItem = w.iconAt(mouse.x, mouse.y);
                        if (mouse.button === Qt.RightButton) {
                            if (pressedItem) { if (!root.isSelected(pressedItem.path)) root.selectOnly(pressedItem.path); }
                            else root.clearSelection();
                            dctx.show(pressedItem, mouse.x, mouse.y);
                            return;
                        }
                        dctx.item = undefined;
                        if (pressedItem) {
                            if (addMode) root.toggleSelect(pressedItem.path);
                            else if (!root.isSelected(pressedItem.path)) root.selectOnly(pressedItem.path);
                            else if (root.selectionCount > 1) collapseTo = pressedItem.path;
                        } else {
                            baseSel = addMode ? root.selection : ({});
                            if (!addMode) root.clearSelection();
                        }
                    }
                    onPositionChanged: mouse => {
                        if (ignoring || !pressed || !(mouse.buttons & Qt.LeftButton)) return;
                        if (!moved && Math.abs(mouse.x - px) + Math.abs(mouse.y - py) < 6) return;
                        moved = true;
                        if (pressedItem) {
                            if (!root.isSelected(pressedItem.path)) return;   // Ctrl-click that deselected it: nothing to drag
                            w.dragActive = true;
                            w.dragDX = mouse.x - px;
                            w.dragDY = mouse.y - py;
                            var t = w.iconAt(mouse.x, mouse.y);
                            w.dropPath = (t && !root.isSelected(t.path) && (t.isDir || root.selectionCount === 1)) ? t.path : "";
                        } else {
                            w.marqueeActive = true;
                            w.mqX0 = px; w.mqY0 = py; w.mqX1 = mouse.x; w.mqY1 = mouse.y;
                            var hit = w.itemsInRect(px, py, mouse.x, mouse.y), m = {};
                            for (var k in baseSel) m[k] = true;
                            for (var i = 0; i < hit.length; i++) m[hit[i].path] = true;
                            root.selection = m;
                        }
                    }
                    onReleased: mouse => {
                        if (ignoring) return;
                        if (w.dragActive) w.finishDrag(mouse.x, mouse.y);
                        else if (!moved && collapseTo !== "") root.selectOnly(collapseTo);
                        w.marqueeActive = false;
                        pressedItem = null;
                    }
                    onCanceled: { w.dragActive = false; w.dragDX = 0; w.dragDY = 0; w.dropPath = ""; w.marqueeActive = false; pressedItem = null; }
                    onDoubleClicked: mouse => {
                        if (ignoring || mouse.button !== Qt.LeftButton || addMode) return;
                        var it = w.iconAt(mouse.x, mouse.y);
                        if (it) root.openItem(it);
                    }
                }

                Repeater {
                    model: root.items
                    delegate: DesktopIcon {
                        id: icon
                        required property var modelData
                        readonly property var place: w.layoutMap[modelData.name] || null
                        readonly property bool moving: w.dragActive && selected
                        visible: place !== null
                        x: (place ? place.x : 0) + (moving ? w.dragDX : 0)
                        y: (place ? place.y : 0) + (moving ? w.dragDY : 0)
                        Behavior on x { enabled: !icon.moving; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        Behavior on y { enabled: !icon.moving; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        width: root.cellW; height: root.cellH
                        z: moving ? 10 : 1
                        item: modelData
                        fam: root.fam
                        iconSize: root.iconSize
                        selected: root.isSelected(modelData.path)
                        dropTarget: w.dropPath === modelData.path
                        dragging: moving
                        source: root.iconSourceFor(modelData)
                    }
                }

                // selection rectangle
                Rectangle {
                    visible: w.marqueeActive
                    x: Math.min(w.mqX0, w.mqX1); y: Math.min(w.mqY0, w.mqY1)
                    width: Math.abs(w.mqX1 - w.mqX0); height: Math.abs(w.mqY1 - w.mqY0)
                    radius: 4
                    color: Qt.rgba(1, 1, 1, 0.12)
                    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.45)
                    z: 5
                }

                // Right-click menu uses the same glass bubble component as the Dock's context menu.
                DockGlassPanel {
                    id: dctx
                    property var item: undefined
                    readonly property bool open: item !== undefined
                    // native-feeling pop: a quick fade and a small grow out of the pointer; leaves with a short plain fade
                    property real prog: open ? 1 : 0
                    Behavior on prog { NumberAnimation { duration: dctx.open ? 105 : 60; easing.type: Easing.OutQuad } }
                    property real ox: 0
                    property real oy: 0
                    visible: prog > 0.01
                    opacity: Math.min(1, prog * (open ? 1.8 : 1))
                    transform: Scale { origin.x: dctx.ox; origin.y: dctx.oy; xScale: 0.94 + 0.06 * dctx.prog; yScale: 0.94 + 0.06 * dctx.prog }
                    z: 50
                    property real menuScale: root.dock ? root.dock.labelK : 1
                    property real clickX: 0
                    property real clickY: 0
                    backdrop: desktopGlassBackdrop
                    live: visible
                    frozen: false
                    dark: root.darkMode
                    k: menuScale
                    radius: 16 * k
                    tailW: 0
                    tailH: 0
                    tailTipR: 0
                    readonly property real pad: Math.round(5 * k)
                    width: 224 * k
                    bodyH: col.height + 2 * pad
                    // Holding the Scope here keeps the menu's actions working: looking "root" up from inside the
                    // delegate's handler fails at runtime, which is what used to make Move to Trash do nothing.
                    readonly property var app: root
                    // Opens with its top-RIGHT corner under the pointer (the menu sits to the left of the click). It flips to the other side
                    // of the pointer when it would run off the screen, under the top bar, or behind a widget or the Dock.
                    function positionAt() {
                        var W = iconLayer.width, H = iconLayer.height, n = w.modelData.name;
                        var opts = [root.placeNear(width, height, clickX - width, clickY, n, W, H),
                                    root.placeNear(width, height, clickX, clickY, n, W, H),
                                    root.placeNear(width, height, clickX - width, clickY - height, n, W, H),
                                    root.placeNear(width, height, clickX, clickY - height, n, W, H)];
                        var r = opts[0];
                        for (var i = 1; i < opts.length; i++) if (opts[i].score < r.score) r = opts[i];
                        x = r.x; y = r.y;
                        ox = Math.max(0, Math.min(width, clickX - x));
                        oy = Math.max(0, Math.min(height, clickY - y));
                    }
                    // The rows are fixed when the menu opens and kept until it has finished fading out. They used to be bound to `item`,
                    // so on dismiss (item → undefined) the menu turned into the empty-desktop menu for the length of its fade-out.
                    property var menuModel: []
                    function buildModel(it) {
                        var a = dctx.app, hasDir = a.selectedItems().some(function (x) { return x.isDir; });
                        if (it && it.widget) return [{ t: "Widget Settings\u2026", k: "widgets" }];
                        if (!it) return [{ t: "New Folder", k: "newfolder" }, { t: "Add Folder to Desktop\u2026", k: "link" },
                                         { t: "sep" }, { t: "Desktop Settings\u2026", k: "settings" }, { t: "Change Wallpaper\u2026", k: "wallpaper" }];
                        var m = [{ t: "Open", k: "open" }];
                        if (a.selectionCount <= 1) { m.push({ t: "Quick Preview", k: "ql" }); m.push({ t: "Rename\u2026", k: "rename" }); }
                        if (hasDir) { m.push({ t: "sep" }); m.push({ t: "colors" }); m.push({ t: "Folder Icon\u2026", k: "glyph" }); }
                        m.push({ t: "sep" });
                        if (a.selectionCount <= 1) m.push({ t: "Copy Path", k: "copy" });
                        m.push({ t: "Move to Trash", k: "trash", danger: true });
                        m.push({ t: "sep" }); m.push({ t: "New Folder", k: "newfolder" });
                        return m;
                    }
                    function show(it, mx, my) {
                        menuModel = buildModel(it);
                        item = it;
                        clickX = mx; clickY = my;
                        Qt.callLater(function () { dctx.positionAt(); });
                    }
                    function run(k) {
                        var a = dctx.app, it = dctx.item, sel = a.selectedItems();
                        dctx.item = undefined;
                        if (k === "open" && it) { for (var i = 0; i < sel.length; i++) a.openItem(sel[i]); }
                        else if (k === "ql" && it) { if (it.kind === "Image") picSheet.begin(it); else previewSheet.begin(it); }
                        else if (k === "rename" && it) renameSheet.begin(it);
                        else if (k === "link") linkSheet.begin();
                        else if (k === "settings" && a.dock) a.dock.openPrefs("dock");
                        else if (k === "widgets" && a.dock) a.dock.openPrefs("widgets");
                        else if (k === "glyph") glyphSheet.begin(sel.filter(function (s2) { return s2.isDir; }).map(function (s2) { return s2.path; }));
                        else if (k.indexOf("color:") === 0) {
                            var dirs = sel.filter(function (s2) { return s2.isDir; }).map(function (s2) { return s2.path; });
                            a.setFolderColor(dirs, k.substring(6));
                        }
                        else if (k === "copy" && it) Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", it.path]);
                        else if (k === "trash" && it) a.trashMany(sel.map(function (s) { return s.path; }));
                        else if (k === "newfolder") a.newFolder();
                        else if (k === "wallpaper" && a.dock) a.dock.openPrefs("wallpaper");
                    }
                    Column {
                        id: col
                        x: dctx.pad; y: dctx.pad; width: dctx.width - 2 * dctx.pad
                        Repeater {
                            model: dctx.menuModel
                            delegate: Item {
                                id: mrow
                                required property var modelData
                                readonly property bool sep: modelData.t === "sep"
                                readonly property bool colors: modelData.t === "colors"
                                width: parent.width
                                height: sep ? Math.round(11 * dctx.k) : (colors ? Math.round(30 * dctx.k) : Math.round(22 * dctx.k))
                                Rectangle {
                                    visible: mrow.sep
                                    x: 10 * dctx.k; y: 4 * dctx.k; width: parent.width - 20 * dctx.k; height: 1
                                    color: dctx.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)
                                }
                                Rectangle {
                                    visible: !mrow.sep && !mrow.colors && mMa.containsMouse
                                    x: 4 * dctx.k; width: parent.width - 8 * dctx.k; height: parent.height - 2 * dctx.k; y: dctx.k
                                    radius: 8 * dctx.k
                                    color: dctx.app.accent
                                }
                                // folder colour dots
                                Row {
                                    visible: mrow.colors
                                    anchors.centerIn: parent
                                    spacing: Math.round(6 * dctx.k)
                                    Repeater {
                                        model: dctx.app.folderSwatches
                                        delegate: Item {
                                            id: sw
                                            required property var modelData
                                            width: Math.round(16 * dctx.k); height: width
                                            Rectangle {
                                                anchors.fill: parent; radius: width / 2
                                                color: sw.modelData.name === "none" ? "transparent" : sw.modelData.color
                                                border.width: sw.modelData.name === "none" ? 1.5 : 1
                                                border.color: sw.modelData.name === "none" ? (dctx.dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.4)) : Qt.rgba(0, 0, 0, 0.22)
                                                scale: swMa.containsMouse ? 1.18 : 1
                                                Behavior on scale { NumberAnimation { duration: 90 } }
                                                Rectangle {   // the "no colour" dot is a ring with a slash
                                                    visible: sw.modelData.name === "none"
                                                    anchors.centerIn: parent
                                                    width: parent.width * 0.9; height: 1.5; rotation: -45
                                                    color: dctx.dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.4)
                                                }
                                            }
                                            MouseArea { id: swMa; anchors.fill: parent; hoverEnabled: true; onClicked: dctx.run("color:" + sw.modelData.name) }
                                        }
                                    }
                                }
                                Text {
                                    visible: !mrow.sep && !mrow.colors
                                    x: 11 * dctx.k; anchors.verticalCenter: parent.verticalCenter
                                    text: I18n.tr(mrow.modelData.t)
                                    color: mMa.containsMouse ? "white"
                                           : (mrow.modelData.danger ? "#FF453A" : (dctx.dark ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(0, 0, 0, 0.86)))
                                    font.family: dctx.app.fam; font.pixelSize: Math.max(9, Math.round(13 * dctx.k))
                                }
                                MouseArea {
                                    id: mMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: !mrow.sep && !mrow.colors
                                    onClicked: dctx.run(mrow.modelData.k)
                                }
                            }
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    z: 40
                    visible: dctx.open
                    enabled: dctx.open
                    acceptedButtons: Qt.AllButtons
                    onPressed: dctx.item = undefined
                }
                // click outside a sheet closes it
                MouseArea {
                    anchors.fill: parent
                    z: 55
                    visible: w.sheetOpen
                    enabled: w.sheetOpen && !root.picking
                    acceptedButtons: Qt.AllButtons
                    onPressed: w.closeSheets()
                }

                // ───────── Rename ─────────
                DesktopSheet {
                    warm: w.warm
                    id: renameSheet
                    z: 60
                    property var item: null
                    title: I18n.tr("Rename")
                    backdrop: desktopGlassBackdrop
                    dark: root.darkMode
                    fam: root.fam
                    k: root.dock ? root.dock.labelK : 1
                    contentW: 340; contentH: 56
                    onCloseRequested: open = false
                    function begin(it) {
                        item = it;
                        w.placeSheet(renameSheet);
                        var c = w.iconCenter(it);
                        ox = c.x - x; oy = c.y - y;
                        nameIn.text = it.name;
                        open = true;
                        Qt.callLater(function () { nameIn.forceActiveFocus(); nameIn.selectAll(); });
                    }
                    function commit() {
                        var it = item, t = nameIn.text.trim();
                        open = false;
                        if (!it || t === "" || t === it.name) return;
                        Quickshell.execDetached(["sh", "-c", "if [ ! -e \"$2/$3\" ] && [ ! -L \"$2/$3\" ]; then mv -- \"$1\" \"$2/$3\"; fi", "sh", it.path, root.dir, t]);
                        rescan.restart();
                    }
                    Rectangle {
                        x: Math.round(16 * renameSheet.k); y: Math.round(2 * renameSheet.k)
                        width: renameSheet.width - 2 * x; height: Math.round(36 * renameSheet.k)
                        radius: Math.round(11 * renameSheet.k)
                        color: root.darkMode ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.07)
                        TextInput {
                            id: nameIn
                            anchors.fill: parent; anchors.leftMargin: Math.round(12 * renameSheet.k); anchors.rightMargin: Math.round(12 * renameSheet.k)
                            verticalAlignment: TextInput.AlignVCenter
                            color: root.darkMode ? "white" : "#1d1d1f"
                            selectionColor: root.accent
                            font.family: root.fam; font.pixelSize: Math.max(10, Math.round(14 * renameSheet.k))
                            selectByMouse: true
                            clip: true
                            onAccepted: renameSheet.commit()
                            Keys.onEscapePressed: renameSheet.open = false
                        }
                    }
                }

                // ───────── Quick Preview ─────────
                DesktopSheet {
                    warm: w.warm
                    id: previewSheet
                    z: 60
                    property var item: null
                    title: I18n.tr("Quick Preview")
                    backdrop: desktopGlassBackdrop
                    dark: root.darkMode
                    fam: root.fam
                    k: root.dock ? root.dock.labelK : 1
                    contentW: 400
                    // The size is fixed when the sheet opens. The rows used to arrive (and the sheet grow) AFTER it had opened, which
                    // rebuilt the whole glass (canvases, mask, blur) in the middle of the animation. Now the sheet waits for the
                    // file info (a few ms), sizes itself once, then opens.
                    property int lockedRows: 4
                    property bool pending: false
                    contentH: 96 + lockedRows * 20 + 18
                    onCloseRequested: open = false
                    function begin(it) {
                        item = it;
                        pending = true;
                        pvWait.restart();
                        root.loadInfo(it);           // root.info is reset here; openNow() runs from onInfoChanged once it is filled
                    }
                    function openNow() {
                        if (!pending) return;
                        pending = false; pvWait.stop();
                        lockedRows = pvRows.length;
                        w.placeSheet(previewSheet);
                        var c = w.iconCenter(item);
                        ox = c.x - x; oy = c.y - y;
                        open = true;
                    }
                    Timer { id: pvWait; interval: 400; onTriggered: previewSheet.openNow() }
                    Connections { target: root; function onInfoChanged() { if (previewSheet.pending && root.info && root.info.ready) previewSheet.openNow(); } }
                    // rows of "label / value"
                    readonly property var pvRows: {
                        var it = item, f = root.info, r = [];
                        if (!it) return r;
                        var n = Number(f.extra);
                        r.push([I18n.tr("Size"), it.isDir ? (f.ready ? n + " " + (n === 1 ? I18n.tr("item") : I18n.tr("items")) : "—") : root.humanSize(f.size)]);
                        r.push([I18n.tr("Created"), root.fmtDate(f.birth)]);
                        r.push([I18n.tr("Modified"), root.fmtDate(f.mod)]);
                        if (it.kind === "Image" && probe.status === Image.Ready) r.push([I18n.tr("Dimensions"), probe.implicitWidth + " × " + probe.implicitHeight]);
                        r.push([I18n.tr("Where"), root.dir]);
                        if (f.link) r.push([I18n.tr("Links to"), f.link]);
                        if (f.perms) r.push([I18n.tr("Permissions"), f.perms + (f.owner ? "  •  " + f.owner : "")]);
                        return r;
                    }
                    Image { id: probe; visible: false; asynchronous: true; source: previewSheet.item && previewSheet.item.kind === "Image" ? root.fileUrl(previewSheet.item.path) : "" }
                    Item {
                        anchors.fill: parent
                        Image {
                            id: pvIcon
                            x: Math.round(18 * previewSheet.k); y: Math.round(2 * previewSheet.k)
                            width: Math.round(76 * previewSheet.k); height: width
                            asynchronous: true; smooth: true; mipmap: true
                            fillMode: previewSheet.item && previewSheet.item.kind === "Image" ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                            sourceSize: Qt.size(256, 256)
                            source: previewSheet.item ? root.iconSourceFor(previewSheet.item) : ""
                        }
                        Column {
                            x: pvIcon.x + pvIcon.width + Math.round(16 * previewSheet.k)
                            y: Math.round(8 * previewSheet.k)
                            width: previewSheet.width - x - Math.round(18 * previewSheet.k)
                            spacing: Math.round(4 * previewSheet.k)
                            Text {
                                width: parent.width
                                text: previewSheet.item ? (previewSheet.item.isApp ? previewSheet.item.name.replace(/\.desktop$/i, "") : previewSheet.item.name) : ""
                                color: previewSheet.fg
                                font.family: root.fam; font.weight: Font.DemiBold; font.pixelSize: Math.max(11, Math.round(15 * previewSheet.k))
                                wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideMiddle
                            }
                            Text {
                                width: parent.width
                                text: previewSheet.item ? root.kindOf(previewSheet.item, root.info) : ""
                                color: previewSheet.fg2
                                font.family: root.fam; font.pixelSize: Math.max(9, Math.round(12 * previewSheet.k))
                                elide: Text.ElideRight
                            }
                        }
                        Column {
                            x: Math.round(18 * previewSheet.k)
                            y: Math.round(92 * previewSheet.k)
                            width: previewSheet.width - 2 * x
                            spacing: 0
                            Repeater {
                                model: previewSheet.pvRows
                                delegate: Item {
                                    id: pr
                                    required property var modelData
                                    width: parent.width; height: Math.round(20 * previewSheet.k)
                                    Text {
                                        width: Math.round(88 * previewSheet.k)
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: pr.modelData[0]
                                        color: previewSheet.fg2
                                        font.family: root.fam; font.pixelSize: Math.max(9, Math.round(12 * previewSheet.k))
                                    }
                                    Text {
                                        x: Math.round(92 * previewSheet.k)
                                        width: parent.width - x
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: pr.modelData[1]
                                        color: previewSheet.fg
                                        font.family: root.fam; font.pixelSize: Math.max(9, Math.round(12 * previewSheet.k))
                                        elide: Text.ElideMiddle
                                    }
                                }
                            }
                        }
                    }
                }

                // ───────── Quick Preview of a picture ─────────
                // Light weight on purpose (see PictureSheet.qml): the glass sheet repaints CPU canvases whenever it changes size, which
                // is what made big pictures lag.
                PictureSheet {
                    warm: w.warm
                    id: picSheet
                    z: 60
                    backdrop: desktopGlassBackdrop
                    dark: root.darkMode
                    fam: root.fam
                    k: root.dock ? root.dock.labelK : 1
                    maxW: w.width * 0.30 - 2 * pad
                    maxH: w.height * 0.30 - headH - pad - Math.round(2 * k)
                    property bool pending: false
                    onCloseRequested: open = false
                    function begin(it) {
                        item = it;
                        var url = root.fileUrl(it.path);
                        pending = true;
                        pendTimer.restart();
                        freeTimer.stop();
                        if (source === url && loaded) { openNow(); return; }
                        if (source === url && status === Image.Error) { fallback(); return; }
                        source = url;                       // opens from onPictureReady once it has been decoded
                    }
                    function openNow() {
                        pending = false; pendTimer.stop();
                        w.placeSheet(picSheet);
                        open = true;
                    }
                    // a picture that cannot be read (or takes far too long) falls back to the info card
                    function fallback() {
                        var it = item;
                        pending = false; pendTimer.stop();
                        if (it) previewSheet.begin(it);
                    }
                    onPictureReady: if (pending) openNow()
                    onPictureFailed: if (pending) fallback()
                    Timer { id: pendTimer; interval: 3000; onTriggered: picSheet.fallback() }
                    // once it has closed, let go of the picture so it does not stay in memory
                    Timer { id: freeTimer; interval: 600; onTriggered: if (!picSheet.open && !picSheet.pending) picSheet.source = "" }
                    onOpenChanged: { if (open) freeTimer.stop(); else freeTimer.restart(); }
                }

                // ───────── Folder Icon (pick the symbol on a folder) ─────────
                DesktopSheet {
                    warm: w.warm
                    id: glyphSheet
                    z: 60
                    property var paths: []
                    readonly property int cols: 6
                    readonly property var cells: [""].concat(root.glyphList)
                    readonly property int rows: Math.ceil(cells.length / cols)
                    // the folder colour the previews are drawn in (that of the first chosen folder)
                    readonly property string tint: paths.length > 0 ? (root.folderColors[paths[0]] || "") : ""
                    title: I18n.tr("Folder Icon")
                    backdrop: desktopGlassBackdrop
                    dark: root.darkMode
                    fam: root.fam
                    k: root.dock ? root.dock.labelK : 1
                    contentW: cols * 64 + 28
                    contentH: rows * 76 + 14
                    onCloseRequested: open = false
                    function begin(p) {
                        if (!p || p.length === 0) return;
                        paths = p;
                        w.placeSheet(glyphSheet);
                        ox = width / 2; oy = height / 2;
                        open = true;
                    }
                    function pick(g) { root.setFolderGlyph(paths, g); open = false; }
                    Grid {
                        x: Math.round(14 * glyphSheet.k); y: Math.round(4 * glyphSheet.k)
                        columns: glyphSheet.cols
                        Repeater {
                            model: glyphSheet.cells
                            delegate: Item {
                                id: gcell
                                required property string modelData
                                width: Math.round(64 * glyphSheet.k); height: Math.round(76 * glyphSheet.k)
                                readonly property string src: modelData === "" ? "" : root.glyphIcon(glyphSheet.tint, modelData)
                                readonly property bool current: glyphSheet.paths.length > 0 && (root.folderGlyphs[glyphSheet.paths[0]] || "") === modelData
                                Rectangle {
                                    anchors.fill: parent; anchors.margins: Math.round(2 * glyphSheet.k)
                                    radius: Math.round(10 * glyphSheet.k)
                                    color: gMa.containsMouse ? (glyphSheet.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.09)) : "transparent"
                                    border.width: gcell.current ? 2 : 0
                                    border.color: root.accent
                                }
                                Image {
                                    x: Math.round((parent.width - width) / 2); y: Math.round(8 * glyphSheet.k)
                                    width: Math.round(40 * glyphSheet.k); height: width
                                    sourceSize: Qt.size(width * 2, height * 2)
                                    asynchronous: true; cache: true; smooth: true
                                    fillMode: Image.PreserveAspectFit
                                    source: gcell.modelData !== "" ? gcell.src
                                        : ((glyphSheet.tint !== "" && Quickshell.iconPath("folder_color_" + glyphSheet.tint, true) !== "") ? Quickshell.iconPath("folder_color_" + glyphSheet.tint, true)
                                           : (root.dock && root.dock.iconSrc ? root.dock.iconSrc("folder") : Quickshell.iconPath("folder")))
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: Math.round(52 * glyphSheet.k)
                                    width: parent.width - 4; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                                    text: gcell.modelData === "" ? I18n.tr("Default") : gcell.modelData.charAt(0).toUpperCase() + gcell.modelData.slice(1)
                                    color: glyphSheet.fg2
                                    font.family: root.fam; font.pixelSize: Math.max(8, Math.round(11 * glyphSheet.k))
                                }
                                MouseArea { id: gMa; anchors.fill: parent; hoverEnabled: true; onClicked: glyphSheet.pick(gcell.modelData) }
                            }
                        }
                    }
                }

                // ───────── Add Folder to Desktop ─────────
                DesktopSheet {
                    warm: w.warm
                    id: linkSheet
                    z: 60
                    property string error: ""
                    title: I18n.tr("Add Folder to Desktop")
                    backdrop: desktopGlassBackdrop
                    dark: root.darkMode
                    fam: root.fam
                    k: root.dock ? root.dock.labelK : 1
                    contentW: 420; contentH: 128
                    onCloseRequested: open = false
                    function begin() {
                        error = "";
                        pathIn.text = "";
                        w.placeSheet(linkSheet);
                        ox = width / 2; oy = height / 2;
                        open = true;
                        Qt.callLater(function () { pathIn.forceActiveFocus(); });
                    }
                    function commit() {
                        var t = pathIn.text.trim();
                        if (t === "") { error = I18n.tr("Type or choose a folder."); return; }
                        error = "";
                        root.linkFolder(t);
                    }
                    Connections {
                        target: root
                        function onLinkFinished(code) {
                            if (!linkSheet.open) return;
                            if (code === 0) linkSheet.open = false;
                            else linkSheet.error = I18n.tr("That folder doesn't exist.");
                        }
                        function onPathPicked(p) { if (linkSheet.open) { pathIn.text = p; linkSheet.error = ""; } }
                    }
                    Text {
                        x: Math.round(18 * linkSheet.k); y: Math.round(0 * linkSheet.k)
                        text: I18n.tr("Shows the folder on your desktop as a link. The original stays where it is.")
                        width: linkSheet.width - 2 * x
                        wrapMode: Text.Wrap
                        color: linkSheet.fg2
                        font.family: root.fam; font.pixelSize: Math.max(9, Math.round(12 * linkSheet.k))
                    }
                    Rectangle {
                        id: pathBox
                        x: Math.round(18 * linkSheet.k); y: Math.round(40 * linkSheet.k)
                        width: linkSheet.width - 2 * x - chooseBtn.width - Math.round(8 * linkSheet.k)
                        height: Math.round(36 * linkSheet.k)
                        radius: Math.round(11 * linkSheet.k)
                        color: root.darkMode ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.07)
                        TextInput {
                            id: pathIn
                            anchors.fill: parent; anchors.leftMargin: Math.round(12 * linkSheet.k); anchors.rightMargin: Math.round(12 * linkSheet.k)
                            verticalAlignment: TextInput.AlignVCenter
                            color: root.darkMode ? "white" : "#1d1d1f"
                            selectionColor: root.accent
                            font.family: root.fam; font.pixelSize: Math.max(10, Math.round(14 * linkSheet.k))
                            selectByMouse: true
                            clip: true
                            onAccepted: linkSheet.commit()
                            onTextChanged: linkSheet.error = ""
                            Keys.onEscapePressed: linkSheet.open = false
                            Text {
                                visible: pathIn.text === ""
                                anchors.verticalCenter: parent.verticalCenter
                                text: "/home/" + (Quickshell.env("USER") || "user")
                                color: linkSheet.fg2
                                font: pathIn.font
                            }
                        }
                    }
                    Rectangle {
                        id: chooseBtn
                        x: pathBox.x + pathBox.width + Math.round(8 * linkSheet.k); y: pathBox.y
                        width: Math.round(84 * linkSheet.k); height: pathBox.height
                        radius: Math.round(11 * linkSheet.k)
                        color: chMa.pressed ? (root.darkMode ? Qt.rgba(1, 1, 1, 0.26) : Qt.rgba(0, 0, 0, 0.16))
                                            : (root.darkMode ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.09))
                        Text {
                            anchors.centerIn: parent
                            text: I18n.tr("Choose…")
                            color: linkSheet.fg
                            font.family: root.fam; font.pixelSize: Math.max(10, Math.round(13 * linkSheet.k))
                        }
                        MouseArea { id: chMa; anchors.fill: parent; onClicked: root.pickFolder() }
                    }
                    Text {
                        x: Math.round(18 * linkSheet.k); y: Math.round(88 * linkSheet.k)
                        width: linkSheet.width - 2 * x - addBtn.width - Math.round(10 * linkSheet.k)
                        text: linkSheet.error
                        color: "#FF6A5F"
                        font.family: root.fam; font.pixelSize: Math.max(9, Math.round(12 * linkSheet.k))
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        id: addBtn
                        x: linkSheet.width - width - Math.round(18 * linkSheet.k); y: Math.round(84 * linkSheet.k)
                        width: Math.round(84 * linkSheet.k); height: Math.round(34 * linkSheet.k)
                        radius: Math.round(11 * linkSheet.k)
                        color: addMa.pressed ? Qt.darker(root.accent, 1.2) : root.accent
                        Text {
                            anchors.centerIn: parent
                            text: I18n.tr("Add")
                            color: "white"
                            font.family: root.fam; font.weight: Font.DemiBold; font.pixelSize: Math.max(10, Math.round(13 * linkSheet.k))
                        }
                        MouseArea { id: addMa; anchors.fill: parent; onClicked: linkSheet.commit() }
                    }
                }
            }
        }
    }

    // a .desktop file's icon, read out of the file itself
    property var appIcons: ({})
    function appIcon(path) {
        // Use the Dock's icon resolver so themed and absolute Icon= values work the same way.
        if (appIconNames[path] !== undefined && dock && dock.iconSrc) return dock.iconSrc(appIconNames[path]);
        if (appIcons[path] !== undefined) return appIcons[path];
        iconQueue.push(path);
        iconTimer.restart();
        return Quickshell.iconPath("application-x-executable", true);
    }
    property var iconQueue: []
    property var appIconNames: ({})
    Timer {
        id: iconTimer
        interval: 60
        onTriggered: {
            if (root.iconQueue.length === 0) return;
            var p = root.iconQueue.shift();
            iconProc.pending = p;
            iconProc.command = ["sh", "-c", "grep -m1 '^Icon=' \"$1\" | cut -d= -f2-", "sh", p];
            iconProc.running = true;
        }
    }
    Process {
        id: iconProc
        property string pending: ""
        stdout: StdioCollector {
            onStreamFinished: {
                var name = text.trim(), m = {};
                for (var k in root.appIcons) m[k] = root.appIcons[k];
                m[iconProc.pending] = name === "" ? Quickshell.iconPath("application-x-executable", true)
                                    : (name.charAt(0) === "/" ? "file://" + name : Quickshell.iconPath(name, true));
                if (name !== "") { var nm = {}; for (var k2 in root.appIconNames) nm[k2] = root.appIconNames[k2]; nm[iconProc.pending] = name; root.appIconNames = nm; }
                root.appIcons = m;
                if (root.iconQueue.length > 0) iconTimer.restart();
            }
        }
    }
}