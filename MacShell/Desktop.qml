// Desktop — the files, folders and apps sitting on your desktop, exactly as macOS shows them.
//
// Everything in the XDG Desktop directory appears here. Click to select (Ctrl / Shift-click adds, drag on empty desktop for a
// selection rectangle), drag to move one or many icons (positions live in ~/.config/macshell/desktop.json), double-click to open,
// drop one icon onto another to make a folder, drop onto a folder to move into it, right-click for the menu.
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

    // the picture for one item (also used by the menu bar's glass backdrop, so the glass shows the same icons)
    function iconSourceFor(m) {
        if (m.kind === "Image") return fileUrl(m.path);
        if (m.isDir) return dock && dock.iconSrc ? dock.iconSrc("folder") : Quickshell.iconPath("folder");
        if (m.isApp) return appIcon(m.path);
        return Quickshell.iconPath("text-x-generic", "application-x-executable");
    }
    function fileUrl(path) {
        return "file://" + encodeURI(path).replace(/#/g, "%23").replace(/\?/g, "%3F");
    }


    function scan() {
        lsProc.running = false;
        lsProc.command = ["sh", "-c",
            "mkdir -p \"$1\"; cd \"$1\" && find . -mindepth 1 -maxdepth 1 ! -name '.*' -printf '%y\\t%f\\n' 2>/dev/null | LC_ALL=C sort -t\"$(printf '\\t')\" -k1,1 -k2,2f | head -200", "sh", root.dir];
        lsProc.running = true;
    }
    Process {
        id: lsProc
        stdout: StdioCollector {
            onStreamFinished: {
                var out = [], ls = text.split("\n");
                for (var i = 0; i < ls.length; i++) {
                    var c = ls[i].split("\t");
                    if (c.length < 2) continue;
                    var name = c[1], isDir = c[0] === "d", isApp = /\.desktop$/i.test(name);
                    var e = name.toLowerCase().split(".").pop();
                    out.push({ name: name, path: root.dir + "/" + name, isDir: isDir, isApp: isApp,
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
            WlrLayershell.keyboardFocus: renamer.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

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
                    visible: dctx.open
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
                        paused: !dctx.open || (!!root.bar && (root.bar.gaming || root.bar.screenCovered[w.modelData.name] === true))
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

                    onPressed: mouse => {
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
                        if (!pressed || !(mouse.buttons & Qt.LeftButton)) return;
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
                        if (w.dragActive) w.finishDrag(mouse.x, mouse.y);
                        else if (!moved && collapseTo !== "") root.selectOnly(collapseTo);
                        w.marqueeActive = false;
                        pressedItem = null;
                    }
                    onCanceled: { w.dragActive = false; w.dragDX = 0; w.dragDY = 0; w.dropPath = ""; w.marqueeActive = false; pressedItem = null; }
                    onDoubleClicked: mouse => {
                        if (mouse.button !== Qt.LeftButton || addMode) return;
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
                    visible: opacity > 0.01
                    opacity: open ? 1 : 0
                    z: 50
                    property real menuScale: root.dock ? root.dock.labelK : 1
                    property real clickX: 0
                    property real clickY: 0
                    backdrop: desktopGlassBackdrop
                    live: open
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
                    scale: open ? 1 : 0.94
                    transformOrigin: Item.Bottom
                    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                    // Holding the Scope here keeps the menu's actions working: looking "root" up from inside the
                    // delegate's handler fails at runtime, which is what used to make Move to Trash do nothing.
                    readonly property var app: root
                    function positionAt() {
                        x = Math.max(8, Math.min(clickX - width / 2, iconLayer.width - width - 8));
                        y = Math.max(8, Math.min(clickY - height, iconLayer.height - height - 8));
                    }
                    function show(it, mx, my) {
                        item = it;
                        clickX = mx; clickY = my;
                        Qt.callLater(function () { dctx.positionAt(); });
                    }
                    function run(k) {
                        var a = dctx.app, it = dctx.item, sel = a.selectedItems();
                        dctx.item = undefined;
                        if (k === "open" && it) { for (var i = 0; i < sel.length; i++) a.openItem(sel[i]); }
                        else if (k === "ql" && it) {
                            if (it.kind === "Image" && a.hub && a.hub.bar && a.hub.bar.openPath) a.hub.bar.openPath(it.path);
                            else a.openItem(it);
                        }
                        else if (k === "rename" && it) renamer.begin(it);
                        else if (k === "copy" && it) Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", it.path]);
                        else if (k === "trash" && it) a.trashMany(sel.map(function (s) { return s.path; }));
                        else if (k === "newfolder") a.newFolder();
                        else if (k === "cleanup") { a.places = ({}); a.savePlaces(); }
                        else if (k === "wallpaper" && a.dock) a.dock.openPrefs("wallpaper");
                    }
                    Column {
                        id: col
                        x: dctx.pad; y: dctx.pad; width: dctx.width - 2 * dctx.pad
                        Repeater {
                            model: dctx.item
                                   ? (dctx.app.selectionCount > 1
                                      ? [{ t: "Open", k: "open" }, { t: "sep" }, { t: "Move to Trash", k: "trash", danger: true },
                                         { t: "sep" }, { t: "New Folder", k: "newfolder" }]
                                      : [{ t: "Open", k: "open" }, { t: "Quick Look", k: "ql" }, { t: "Rename\u2026", k: "rename" },
                                         { t: "sep" }, { t: "Copy Path", k: "copy" }, { t: "Move to Trash", k: "trash", danger: true },
                                         { t: "sep" }, { t: "New Folder", k: "newfolder" }])
                                   : [{ t: "New Folder", k: "newfolder" }, { t: "Clean Up", k: "cleanup" },
                                      { t: "sep" }, { t: "Change Wallpaper\u2026", k: "wallpaper" }]
                            delegate: Item {
                                id: mrow
                                required property var modelData
                                readonly property bool sep: modelData.t === "sep"
                                width: parent.width
                                height: sep ? Math.round(11 * dctx.k) : Math.round(22 * dctx.k)
                                Rectangle {
                                    visible: mrow.sep
                                    x: 10 * dctx.k; y: 4 * dctx.k; width: parent.width - 20 * dctx.k; height: 1
                                    color: dctx.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)
                                }
                                Rectangle {
                                    visible: !mrow.sep && mMa.containsMouse
                                    x: 4 * dctx.k; width: parent.width - 8 * dctx.k; height: parent.height - 2 * dctx.k; y: dctx.k
                                    radius: 8 * dctx.k
                                    color: dctx.app.accent
                                }
                                Text {
                                    visible: !mrow.sep
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
                                    enabled: !mrow.sep
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

                // rename sheet
                Rectangle {
                    id: renamer
                    property var item: undefined
                    visible: item !== undefined
                    z: 60
                    anchors.centerIn: parent
                    width: 320; height: 96; radius: 12
                    color: Qt.rgba(0.17, 0.17, 0.18, 0.98)
                    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
                    function begin(it) { item = it; nameIn.text = it.name; nameIn.forceActiveFocus(); nameIn.selectAll(); }
                    function commit() {
                        var it = item; item = undefined;
                        var t = nameIn.text.trim();
                        if (!it || t === "" || t === it.name) return;
                        Quickshell.execDetached(["sh", "-c", "if [ ! -e \"$2/$3\" ] && [ ! -L \"$2/$3\" ]; then mv -- \"$1\" \"$2/$3\"; fi", "sh", it.path, root.dir, t]);
                        rescan.restart();
                    }
                    Text { x: 16; y: 14; text: I18n.tr("Rename"); color: "white"; font.family: Fonts.forWeight(Font.DemiBold, root.fam); font.pixelSize: 13; font.weight: Font.DemiBold }
                    Rectangle {
                        x: 16; y: 40; width: parent.width - 32; height: 30; radius: 7
                        color: Qt.rgba(1, 1, 1, 0.1)
                        TextInput {
                            id: nameIn
                            anchors.fill: parent; anchors.margins: 9
                            verticalAlignment: TextInput.AlignVCenter
                            color: "white"; font.family: root.fam; font.pixelSize: 13
                            selectByMouse: true
                            onAccepted: renamer.commit()
                            Keys.onEscapePressed: renamer.item = undefined
                        }
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