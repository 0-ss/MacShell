// Desktop — the files, folders and apps sitting on your desktop, exactly as macOS shows them.
//
// Everything in ~/Desktop appears here. Drag an icon to move it (positions live in ~/.config/macshell/desktop.json),
// double-click to open, drop one icon onto another to make a folder, right-click for the menu.
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
    readonly property string home: Quickshell.env("HOME")
    readonly property string dir: home + "/Desktop"

    readonly property bool enabled: dock ? dock.desktopIcons : true
    property var items: []                  // { name, path, isDir, isApp, exec, icon, kind }
    property var places: ({})               // name → { x, y }
    property string selected: ""

    readonly property int cellW: 96
    readonly property int cellH: 92

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
                    var name = c[1], isDir = c[0] === "d", isApp = /\.desktop$/.test(name);
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
    function placeOf(name, index) {
        var p = places[name];
        if (p) return p;
        // nothing saved yet: fill the right-hand column the way macOS does
        var perCol = 7;
        return { x: -(1 + Math.floor(index / perCol)) * cellW, y: 36 + (index % perCol) * cellH };
    }
    function setPlace(name, x, y) {
        var m = {}; for (var k in places) m[k] = places[k];
        m[name] = { x: x, y: y };
        places = m; savePlaces();
    }
    function openItem(it) {
        if (it.isApp) { Quickshell.execDetached(["sh", "-c", "gio launch \"$1\" 2>/dev/null || dex \"$1\" 2>/dev/null || xdg-open \"$1\"", "sh", it.path]); return; }
        if (it.isDir) { if (hub && hub.openFolder) hub.openFolder(it.path); else Quickshell.execDetached(["xdg-open", it.path]); return; }
        if (hub && hub.openPath) { hub.openPath(it.path); return; }
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
    function moveInto(srcPath, folderPath) {
        Quickshell.execDetached(["sh", "-c", "mv \"$1\" \"$2\"/", "sh", srcPath, folderPath]);
        rescan.restart();
    }
    function trash(path) {
        Quickshell.execDetached(["sh", "-c", "gio trash \"$1\" 2>/dev/null || { mkdir -p \"$HOME/.local/share/Trash/files\" && mv \"$1\" \"$HOME/.local/share/Trash/files/\"; }", "sh", path]);
        rescan.restart();
    }
    Timer { id: rescan; interval: 400; onTriggered: root.scan() }
    Timer { interval: 6000; repeat: true; running: root.enabled; triggeredOnStart: true; onTriggered: root.scan() }

    Variants {
        model: root.enabled ? Quickshell.screens : []
        PanelWindow {
            id: w
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "macdesktop"
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region { item: iconLayer }

            Item {
                id: iconLayer
                anchors.fill: parent

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        root.selected = "";
                        if (mouse.button === Qt.RightButton) dctx.show(null, mouse.x, mouse.y);
                        else dctx.item = undefined;
                    }
                }

                Repeater {
                    model: root.items
                    delegate: Item {
                        id: icon
                        required property var modelData
                        required property int index
                        readonly property var place: root.placeOf(modelData.name, index)
                        // a negative x means "measured from the right edge", which keeps the default column pinned there
                        x: dragging ? dragX : (place.x < 0 ? w.width + place.x : place.x)
                        y: dragging ? dragY : place.y
                        width: root.cellW; height: root.cellH
                        property bool dragging: false
                        property real dragX: 0
                        property real dragY: 0
                        z: dragging ? 10 : 1

                        Rectangle {
                            anchors.fill: parent; anchors.margins: 4
                            radius: 8
                            color: root.selected === icon.modelData.path ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)
                                 : (dropMa.containsDrag ? Qt.rgba(1, 1, 1, 0.18) : "transparent")
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        // the icon itself: app icon, folder, image thumbnail or a plain document
                        Image {
                            id: img
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 8
                            width: 48; height: 48
                            asynchronous: true; cache: true; smooth: true; mipmap: true
                            fillMode: icon.modelData.kind === "Image" ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                            sourceSize: Qt.size(96, 96)
                            source: icon.modelData.kind === "Image" ? "file://" + icon.modelData.path
                                  : (icon.modelData.isDir ? (root.dock ? root.dock.folderIcon : Quickshell.iconPath("folder"))
                                  : (icon.modelData.isApp ? root.appIcon(icon.modelData.path) : Quickshell.iconPath("text-x-generic", "application-x-executable")))
                            onStatusChanged: if (status === Image.Error) source = Quickshell.iconPath("application-x-executable", true)
                            // Settings → Icons → Tinted, for app icons (pictures and folders keep their colours)
                            layer.enabled: icon.modelData.isApp === true && root.dock !== null && root.dock.iconsTinted
                            layer.effect: MultiEffect {
                                colorization: root.dock ? root.dock.iconColorize : 0
                                colorizationColor: root.dock ? root.dock.iconColorizeColor : "white"
                                brightness: root.dock ? root.dock.iconBright : 0
                                saturation: root.dock ? root.dock.iconSat : 0
                                opacity: root.dock ? root.dock.iconAlpha : 1
                            }
                            // switching the icon style: a simple fade
                            opacity: icon.modelData.isApp === true && root.dock ? 1 - root.dock.iconSwap : 1
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 60
                            width: parent.width - 8
                            horizontalAlignment: Text.AlignHCenter
                            maximumLineCount: 2; wrapMode: Text.Wrap; elide: Text.ElideMiddle
                            text: icon.modelData.isApp ? icon.modelData.name.replace(/\.desktop$/, "") : icon.modelData.name
                            color: "white"; font.family: root.fam; font.pixelSize: 11
                            style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.55)
                        }
                        scale: dragMa.pressed ? 1.06 : 1
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }

                        DropArea {
                            id: dropMa
                            anchors.fill: parent
                            onDropped: drop => {
                                var src = drop.getDataAsString("text/plain");
                                if (!src || src === icon.modelData.path) return;
                                if (icon.modelData.isDir) root.moveInto(src, icon.modelData.path);
                                else root.combine(src, icon.modelData.path);
                            }
                        }
                        MouseArea {
                            id: dragMa
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            drag.target: null
                            property real px: 0
                            property real py: 0
                            onPressed: mouse => {
                                root.selected = icon.modelData.path;
                                px = mouse.x; py = mouse.y;
                                icon.dragX = icon.x; icon.dragY = icon.y;
                                if (mouse.button === Qt.RightButton) dctx.show(icon.modelData, icon.x + mouse.x, icon.y + mouse.y);
                            }
                            onPositionChanged: mouse => {
                                if (!pressed || mouse.buttons !== Qt.LeftButton) return;
                                if (!icon.dragging && Math.abs(mouse.x - px) + Math.abs(mouse.y - py) < 6) return;
                                icon.dragging = true;
                                icon.dragX += mouse.x - px;
                                icon.dragY += mouse.y - py;
                            }
                            onReleased: {
                                if (!icon.dragging) return;
                                icon.dragging = false;
                                // snap to the grid, like macOS with "Snap to Grid" on
                                var gx = Math.max(0, Math.min(w.width - root.cellW, Math.round(icon.dragX / root.cellW) * root.cellW));
                                var gy = Math.max(28, Math.min(w.height - root.cellH, Math.round((icon.dragY - 36) / root.cellH) * root.cellH + 36));
                                root.setPlace(icon.modelData.name, gx, gy);
                            }
                            onDoubleClicked: root.openItem(icon.modelData)
                        }
                    }
                }

                // right-click menu — the macOS one: a soft card, inset highlight, separators, and it springs open
                Item {
                    id: dctx
                    property var item: undefined
                    readonly property bool open: item !== undefined
                    visible: opacity > 0.01
                    opacity: open ? 1 : 0
                    z: 50
                    width: 212; height: col.height + 12
                    scale: open ? 1 : 0.94
                    transformOrigin: Item.TopLeft
                    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                    // Holding the Scope here keeps the menu's actions working: looking "root" up from inside the
                    // delegate's handler fails at runtime, which is what used to make Move to Trash do nothing.
                    readonly property var app: root
                    function show(it, mx, my) {
                        item = it;
                        x = Math.min(mx, iconLayer.width - width - 8);
                        y = Math.min(my, iconLayer.height - height - 8);
                    }
                    function run(k) {
                        var a = dctx.app, it = dctx.item;
                        dctx.item = undefined;
                        if (k === "open" && it) a.openItem(it);
                        else if (k === "ql" && it) {
                            if (it.kind === "Image" && a.hub && a.hub.openPath) a.hub.openPath(it.path);
                            else a.openItem(it);
                        }
                        else if (k === "rename" && it) renamer.begin(it);
                        else if (k === "copy" && it) Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", it.path]);
                        else if (k === "trash" && it) a.trash(it.path);
                        else if (k === "newfolder") a.newFolder();
                        else if (k === "cleanup") { a.places = ({}); a.savePlaces(); }
                        else if (k === "wallpaper" && a.dock) a.dock.openPrefs("wallpaper");
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: root.darkMode ? Qt.rgba(0.16, 0.16, 0.17, 0.97) : Qt.rgba(0.99, 0.99, 1.0, 0.98)
                        border.width: 1
                        border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.09)
                        layer.enabled: true
                        layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.9; shadowOpacity: 0.35; shadowVerticalOffset: 8 }
                    }
                    Column {
                        id: col
                        y: 6; width: parent.width
                        Repeater {
                            model: dctx.item
                                   ? [{ t: "Open", k: "open" }, { t: "Quick Look", k: "ql" }, { t: "Rename\u2026", k: "rename" },
                                      { t: "sep" }, { t: "Copy Path", k: "copy" }, { t: "Move to Trash", k: "trash", danger: true },
                                      { t: "sep" }, { t: "New Folder", k: "newfolder" }]
                                   : [{ t: "New Folder", k: "newfolder" }, { t: "Clean Up", k: "cleanup" },
                                      { t: "sep" }, { t: "Change Wallpaper\u2026", k: "wallpaper" }]
                            delegate: Item {
                                id: mrow
                                required property var modelData
                                readonly property bool sep: modelData.t === "sep"
                                width: parent.width
                                height: sep ? 9 : 25
                                Rectangle {
                                    visible: mrow.sep
                                    x: 12; y: 4; width: parent.width - 24; height: 1
                                    color: dctx.app.darkMode ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.08)
                                }
                                Rectangle {
                                    visible: !mrow.sep && mMa.containsMouse
                                    x: 6; width: parent.width - 12; height: parent.height - 2; y: 1
                                    radius: 6
                                    color: dctx.app.accent
                                }
                                Text {
                                    visible: !mrow.sep
                                    x: 16; anchors.verticalCenter: parent.verticalCenter
                                    text: mrow.modelData.t
                                    color: mMa.containsMouse ? "white"
                                           : (mrow.modelData.danger ? "#FF453A" : (dctx.app.darkMode ? "#F5F5F7" : "#1D1D1F"))
                                    font.family: dctx.app.fam; font.pixelSize: 13
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
                        Quickshell.execDetached(["sh", "-c", "mv \"$1\" \"$2/$3\"", "sh", it.path, root.dir, t]);
                        rescan.restart();
                    }
                    Text { x: 16; y: 14; text: I18n.tr("Rename"); color: "white"; font.family: Fonts.forWeight(font.weight, root.fam); font.pixelSize: 13; font.weight: Font.DemiBold }
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
        // through the Dock, so Settings → Icons → Dark gives the desktop the same real dark icons
        if (appIconNames[path] !== undefined && dock && dock.iconSrc) { var dk = dock.iconLook; return dock.iconSrc(appIconNames[path]); }
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
