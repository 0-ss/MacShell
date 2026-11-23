import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "WindowMgmt.js" as WM
import "I18n.js" as I18n
import "Fonts.js" as Fonts

Scope {
    id: root
    property var hub: null
    readonly property var dock: hub ? hub.dock : null
    readonly property var bar: hub ? hub.bar : null
    readonly property var wm: hub ? hub.wm : null
    readonly property bool darkMode: dock ? dock.darkMode : true
    readonly property color accent: dock ? dock.accent : "#0A84FF"
    readonly property string fam: dock ? dock.fontFamily : "Open Runde"
    readonly property bool allowCapture: dock ? dock.windowCapture : true

    property bool open: false
    property string mode: "mission"            // "mission" | "expose"
    property string exposeAppKey: ""           // normalized lowercase class/appId for App Exposé
    property string exposeAppLabel: ""
    property string targetScreen: ""           // focused screen name (empty = all screens show their own)
    property bool showAllSpaces: false         // Mission Control: current space vs all spaces
    property int selectedWs: 0                 // workspace currently inspected in Mission Control
    property var extraSpaces: []               // user-created empty workspace IDs while Mission Control is open
    property int selectedIdx: 0
    property int snapshotTick: 0               // forces refresh when windows move between spaces

    // Deferred Hyprland focus/workspace switch after closing the exclusive-focus overlay
    property var pendingAction: null
    Timer {
        id: pendingT
        interval: 55
        onTriggered: {
            var a = root.pendingAction;
            root.pendingAction = null;
            if (!a) return;
            if (a.restore) {
                if (root.hub && root.hub.restoreWindow) root.hub.restoreWindow(a.addr);
                return;
            }
            var lua = "";
            if (a.ws > 0) lua += 'hl.dispatch(hl.dsp.focus({ workspace = "' + a.ws + '" })); ';
            if (a.addr && a.addr !== "") {
                lua += 'hl.dispatch(hl.dsp.focus({ window = "address:' + a.addr + '" })); ';
                lua += 'hl.dispatch(hl.dsp.window.bring_to_top())';
            }
            if (lua !== "") Quickshell.execDetached(["hyprctl", "eval", lua]);
        }
    }

    function refreshNow() {
        try { Hyprland.refreshMonitors(); Hyprland.refreshToplevels(); } catch (err) { }
        snapshotTick++;
    }

    function openMission(screenName) {
        if (wm && wm.desktopRevealed) wm.restoreDesktop();
        refreshNow();
        mode = "mission";
        exposeAppKey = "";
        exposeAppLabel = "";
        showAllSpaces = false;
        extraSpaces = [];
        selectedIdx = 0;
        var mon = resolveMonitor(screenName);
        targetScreen = mon ? mon.name : String(screenName || "");
        selectedWs = (mon && mon.activeWorkspace && mon.activeWorkspace.id > 0) ? mon.activeWorkspace.id : 1;
        open = true;
    }

    function openExpose(appIdOrClass, screenName) {
        if (wm && wm.desktopRevealed) wm.restoreDesktop();
        refreshNow();
        var key = String(appIdOrClass || "").trim().toLowerCase();
        if (key === "") {
            var focused = wm ? wm.focusedClient("") : null;
            if (focused) key = String(focused["class"] || focused.initialClass || "").toLowerCase();
        }
        if (key === "") {
            openMission(screenName);
            return;
        }
        mode = "expose";
        exposeAppKey = key;
        exposeAppLabel = wm ? wm.appNameForClass(key) : key;
        selectedIdx = 0;
        var mon = resolveMonitor(screenName);
        targetScreen = mon ? mon.name : String(screenName || "");
        open = true;
    }

    function close() {
        open = false;
        extraSpaces = [];
    }

    function toggleMission(screenName) {
        if (open && mode === "mission") close();
        else openMission(screenName);
    }

    function toggleExpose(appIdOrClass, screenName) {
        var key = String(appIdOrClass || "").trim().toLowerCase();
        if (open && mode === "expose" && (key === "" || key === exposeAppKey)) close();
        else openExpose(appIdOrClass, screenName);
    }

    function resolveMonitor(screenName) {
        if (wm && wm.monitorFor) return wm.monitorFor(screenName || "");
        var hms = Hyprland.monitors.values;
        for (var i = 0; i < hms.length; i++) {
            var m = hms[i].lastIpcObject;
            if (m && screenName && m.name === screenName) return m;
        }
        return hms.length > 0 ? hms[0].lastIpcObject : null;
    }

    function allClients() {
        var _t = snapshotTick;
        if (wm && wm.liveClients) return wm.liveClients();
        var out = [], ts = Hyprland.toplevels.values;
        for (var i = 0; i < ts.length; i++) {
            var o = ts[i].lastIpcObject;
            if (o && o.address !== undefined) out.push(o);
        }
        return out;
    }

    function wallpaperUrlFor(screenName) {
        if (dock && dock.wallpaperFor && dock.fileUrl) {
            var p = dock.wallpaperFor(screenName);
            return p ? dock.fileUrl(p) : "";
        }
        return "";
    }

    function iconFor(cls) { return wm ? wm.iconForClass(cls) : ""; }
    function appNameFor(cls) { return wm ? wm.appNameForClass(cls) : String(cls || ""); }

    function focusWindowAndClose(addr, wsId, minimized) {
        pendingAction = { addr: WM.normAddr(addr), ws: wsId || 0, restore: !!minimized };
        close();
        pendingT.restart();
    }

    function switchWorkspaceAndClose(wsId) {
        if (!wsId || wsId <= 0) { close(); return; }
        pendingAction = { addr: "", ws: wsId, restore: false };
        close();
        pendingT.restart();
    }

    function moveWindowToWorkspace(addr, wsId) {
        var norm = WM.normAddr(addr);
        if (!norm || !wsId || wsId <= 0) return;
        Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + wsId + '", follow = false, window = "address:' + norm + '" })');
        refreshDelayed.restart();
    }

    function closeWindowFromOverview(addr) {
        var norm = WM.normAddr(addr);
        if (!norm) return;
        var go = function () {
            Hyprland.dispatch('hl.dsp.window.close({ window = "address:' + norm + '" })');
            refreshDelayed.restart();
        };
        if (hub && hub.closeQuietly) hub.closeQuietly(go);
        else go();
    }

    function createWorkspace(spaces) {
        var nextId = WM.nextFreeWorkspaceId(spaces);
        if (extraSpaces.indexOf(nextId) < 0) extraSpaces = extraSpaces.concat([nextId]);
        return nextId;
    }

    function removeWorkspace(wsId, spaces) {
        if (!spaces || spaces.length <= 1) return;
        var fallback = spaces[0].id === wsId ? spaces[1].id : spaces[0].id;
        var cs = allClients();
        for (var i = 0; i < cs.length; i++) {
            var c = cs[i];
            if (c && c.workspace && c.workspace.id === wsId) {
                var na = WM.normAddr(c.address);
                if (na) Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + fallback + '", follow = false, window = "address:' + na + '" })');
            }
        }
        extraSpaces = extraSpaces.filter(function (id) { return id !== wsId; });
        if (selectedWs === wsId) selectedWs = fallback;
        refreshDelayed.restart();
    }

    Timer {
        id: refreshDelayed
        interval: 120
        onTriggered: root.refreshNow()
    }

    Connections {
        target: Hyprland
        enabled: root.open
        function onRawEvent(event) {
            var en = event.name;
            if (en === "openwindow" || en === "closewindow" || en === "movewindow" || en === "movewindowv2" || en === "workspace" || en === "workspacev2")
                refreshDelayed.restart();
        }
    }

    // Entire UI is lazy-loaded ONLY while Mission Control / App Exposé is open -> 0 RAM / 0 CPU when closed
    Loader {
        id: overlayLoader
        active: root.open
        sourceComponent: Variants {
            model: Quickshell.screens
            PanelWindow {
                id: mcWin
                required property var modelData
                screen: modelData
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                WlrLayershell.namespace: "macmc"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: (root.targetScreen === "" || modelData.name === root.targetScreen)
                                              ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

                readonly property var mon: root.resolveMonitor(modelData.name)
                readonly property int activeWsId: (mon && mon.activeWorkspace && mon.activeWorkspace.id > 0) ? mon.activeWorkspace.id : 1
                readonly property int viewWsId: root.selectedWs > 0 ? root.selectedWs : activeWsId
                readonly property string wpUrl: root.wallpaperUrlFor(modelData.name)

                readonly property var spaces: {
                    var _t = root.snapshotTick, _e = root.extraSpaces, _c = root.hub ? root.hub.glassClients : null;
                    return WM.buildSpaces(root.allClients(), mcWin.mon, mcWin.activeWsId, root.extraSpaces);
                }

                // Windows to spread in the main overview area
                readonly property var spreadRaw: {
                    var _t = root.snapshotTick, _c = root.hub ? root.hub.glassClients : null;
                    var cs = root.allClients(), out = [];
                    for (var i = 0; i < cs.length; i++) {
                        var c = cs[i];
                        if (!c || !c.mapped || c.hidden || !c.workspace) continue;
                        if (WM.isShellClass(c["class"] || c.initialClass)) continue;
                        if (WM.isSpecialWorkspace(c.workspace)) continue;
                        var cls = String(c["class"] || c.initialClass || "");
                        if (root.mode === "expose") {
                            var matchCls = cls.toLowerCase();
                            var matchInit = String(c.initialClass || "").toLowerCase();
                            if (matchCls !== root.exposeAppKey && matchInit !== root.exposeAppKey) continue;
                        } else {
                            if (mcWin.mon && c.monitor !== mcWin.mon.id) continue;
                            if (!root.showAllSpaces && c.workspace.id !== mcWin.viewWsId) continue;
                        }
                        var sz = Array.isArray(c.size) ? c.size : [1200, 800];
                        out.push({
                            addr: WM.normAddr(c.address),
                            cls: cls,
                            title: String(c.title || cls),
                            wsId: c.workspace.id,
                            wsName: String(c.workspace.name || c.workspace.id),
                            w: sz[0],
                            h: sz[1],
                            focusHistoryID: typeof c.focusHistoryID === "number" ? c.focusHistoryID : 999
                        });
                    }
                    out.sort(function (a, b) { return a.focusHistoryID - b.focusHistoryID; });
                    return out;
                }

                // Minimized windows for App Exposé bottom strip
                readonly property var exposeMinimized: {
                    if (root.mode !== "expose") return [];
                    var _t = root.snapshotTick;
                    var cs = root.allClients(), out = [];
                    for (var i = 0; i < cs.length; i++) {
                        var c = cs[i];
                        if (!c || !c.workspace || String(c.workspace.name || "") !== "special:minimized") continue;
                        var cls = String(c["class"] || c.initialClass || "");
                        if (cls.toLowerCase() !== root.exposeAppKey && String(c.initialClass || "").toLowerCase() !== root.exposeAppKey) continue;
                        out.push({
                            addr: WM.normAddr(c.address),
                            cls: cls,
                            title: String(c.title || cls)
                        });
                    }
                    return out;
                }

                readonly property real topBandH: root.mode === "mission" ? 132 : 76
                readonly property real bottomBandH: (root.mode === "expose" && exposeMinimized.length > 0) ? 116 : 36
                readonly property var cards: WM.layoutWindowCards(
                    spreadRaw,
                    width,
                    Math.max(120, height - topBandH - bottomBandH),
                    { padX: 44, padY: 20, gapX: 24, gapY: 28, labelH: 30 }
                )

                // Drag-and-drop window -> workspace state
                property var draggingCard: null
                property real dragX: 0
                property real dragY: 0
                property int hoverDropWs: -1       // >0 workspace id, -2 = "+" create new workspace

                function findDropSpace(px, py) {
                    if (root.mode !== "mission" || py > topBandH + 16) return -1;
                    for (var i = 0; i < spaceRep.count; i++) {
                        var it = spaceRep.itemAt(i);
                        if (!it || !mcWin.spaces[i]) continue;
                        var p = it.mapToItem(mcRoot, 0, 0);
                        if (px >= p.x && px <= p.x + it.width && py >= p.y && py <= p.y + it.height)
                            return mcWin.spaces[i].id;
                    }
                    var ap = addSpaceBtn.mapToItem(mcRoot, 0, 0);
                    if (px >= ap.x && px <= ap.x + addSpaceBtn.width && py >= ap.y && py <= ap.y + addSpaceBtn.height)
                        return -2;
                    return -1;
                }

                Item {
                    id: mcRoot
                    anchors.fill: parent
                    focus: true

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true; return; }
                        var count = mcWin.cards.length;
                        if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab || event.key === Qt.Key_Down) {
                            if (count > 0) root.selectedIdx = (root.selectedIdx + 1) % count;
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab || event.key === Qt.Key_Up) {
                            if (count > 0) root.selectedIdx = (root.selectedIdx - 1 + count) % count;
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                            if (count > 0) {
                                var pick = mcWin.cards[Math.max(0, Math.min(root.selectedIdx, count - 1))];
                                root.focusWindowAndClose(pick.addr, pick.wsId, false);
                            } else {
                                root.close();
                            }
                            event.accepted = true;
                        } else if (root.mode === "mission" && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                            var num = event.key - Qt.Key_0;
                            root.selectedWs = num;
                            root.showAllSpaces = false;
                            root.selectedIdx = 0;
                            event.accepted = true;
                        } else if (root.mode === "mission" && event.key === Qt.Key_A) {
                            root.showAllSpaces = !root.showAllSpaces;
                            root.selectedIdx = 0;
                            event.accepted = true;
                        }
                    }

                    // Dimmed wallpaper backdrop
                    Rectangle {
                        anchors.fill: parent
                        color: root.darkMode ? "#0D0E12" : "#1D1F26"
                    }
                    Image {
                        anchors.fill: parent
                        visible: mcWin.wpUrl !== ""
                        source: mcWin.wpUrl
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: Math.min(1280, Math.max(640, Math.round(parent.width * 0.5)))
                        opacity: 0.42
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: root.darkMode ? Qt.rgba(0.04, 0.05, 0.08, 0.56) : Qt.rgba(0.08, 0.09, 0.12, 0.46)
                    }

                    // Click empty background to dismiss
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.close()
                    }

                    // ── TOP BAND: Mission Control Spaces Bar OR App Exposé Header ──
                    Rectangle {
                        id: topBand
                        anchors { top: parent.top; left: parent.left; right: parent.right }
                        height: mcWin.topBandH
                        color: Qt.rgba(0.06, 0.07, 0.10, 0.62)

                        Rectangle {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: 1
                            color: Qt.rgba(1, 1, 1, 0.14)
                        }

                        // Mode A: Mission Control Spaces Bar
                        Item {
                            visible: root.mode === "mission"
                            anchors.fill: parent

                            Row {
                                id: spacesRow
                                anchors.centerIn: parent
                                spacing: 14

                                Repeater {
                                    id: spaceRep
                                    model: mcWin.spaces
                                    delegate: Item {
                                        id: spCard
                                        required property var modelData
                                        required property int index
                                        readonly property bool isSelected: !root.showAllSpaces && modelData.id === mcWin.viewWsId
                                        readonly property bool isDropTarget: mcWin.hoverDropWs === modelData.id
                                        width: 152
                                        height: 108

                                        HoverHandler { id: spHover }

                                        Rectangle {
                                            id: thumbBox
                                            anchors { top: parent.top; left: parent.left; right: parent.right }
                                            height: 84
                                            radius: 10
                                            clip: true
                                            color: Qt.rgba(0.14, 0.15, 0.20, 0.90)
                                            border.width: (spCard.isSelected || spCard.isDropTarget) ? 2 : 1
                                            border.color: spCard.isDropTarget ? "#34C759"
                                                        : (spCard.isSelected ? root.accent : Qt.rgba(1, 1, 1, spHover.hovered ? 0.42 : 0.20))

                                            Image {
                                                anchors.fill: parent
                                                visible: mcWin.wpUrl !== ""
                                                source: mcWin.wpUrl
                                                fillMode: Image.PreserveAspectCrop
                                                sourceSize.width: 304
                                                opacity: 0.65
                                            }

                                            // Proportional mini-window layout inside each Space thumbnail
                                            Repeater {
                                                model: spCard.modelData.windows
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    x: Math.round(modelData.nx * thumbBox.width)
                                                    y: Math.round(modelData.ny * thumbBox.height)
                                                    width: Math.max(10, Math.round(modelData.nw * thumbBox.width))
                                                    height: Math.max(8, Math.round(modelData.nh * thumbBox.height))
                                                    radius: 3
                                                    color: Qt.rgba(0.16, 0.18, 0.24, 0.92)
                                                    border.width: 1
                                                    border.color: Qt.rgba(1, 1, 1, 0.42)
                                                }
                                            }

                                            // Empty workspace hint
                                            Text {
                                                visible: spCard.modelData.windows.length === 0
                                                anchors.centerIn: parent
                                                text: I18n.tr("Empty")
                                                color: Qt.rgba(1, 1, 1, 0.45)
                                                font.pixelSize: 10
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.showAllSpaces = false;
                                                    if (root.selectedWs === spCard.modelData.id) {
                                                        root.switchWorkspaceAndClose(spCard.modelData.id);
                                                    } else {
                                                        root.selectedWs = spCard.modelData.id;
                                                        root.selectedIdx = 0;
                                                    }
                                                }
                                                onDoubleClicked: root.switchWorkspaceAndClose(spCard.modelData.id)
                                            }

                                            // Close workspace button (hover, when >1 space exists)
                                            Rectangle {
                                                visible: spHover.hovered && mcWin.spaces.length > 1
                                                anchors { top: parent.top; left: parent.left; margins: 4 }
                                                width: 18; height: 18; radius: 9
                                                color: rmSpMa.containsMouse ? "#FF5F57" : Qt.rgba(0, 0, 0, 0.68)
                                                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.35)
                                                Text { anchors.centerIn: parent; text: "\u00d7"; color: "#FFFFFF"; font.pixelSize: 12 }
                                                MouseArea {
                                                    id: rmSpMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.removeWorkspace(spCard.modelData.id, mcWin.spaces)
                                                }
                                            }
                                        }

                                        Text {
                                            anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                                            text: I18n.tr("Desktop ") + spCard.modelData.name
                                                  + (spCard.modelData.windows.length > 0 ? (" (" + spCard.modelData.windows.length + ")") : "")
                                            color: spCard.isSelected ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.72)
                                            font.family: Fonts.forWeight(spCard.isSelected ? Font.DemiBold : Font.Normal, root.fam)
                                            font.weight: spCard.isSelected ? Font.DemiBold : Font.Normal
                                            font.pixelSize: 11
                                        }
                                    }
                                }

                                // "+" Create New Space button (also accepts window drops!)
                                Item {
                                    id: addSpaceBtn
                                    width: 56
                                    height: 108
                                    readonly property bool dropHot: mcWin.hoverDropWs === -2
                                    Rectangle {
                                        anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
                                        width: 48; height: 84; radius: 10
                                        color: addSpaceBtn.dropHot ? Qt.rgba(0.20, 0.78, 0.35, 0.35)
                                             : (addSpMa.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.11))
                                        border.width: addSpaceBtn.dropHot ? 2 : 1
                                        border.color: addSpaceBtn.dropHot ? "#34C759" : Qt.rgba(1, 1, 1, 0.24)
                                        Text {
                                            anchors.centerIn: parent
                                            text: "+"
                                            color: "#FFFFFF"
                                            font.pixelSize: 24
                                            font.weight: Font.Light
                                        }
                                        MouseArea {
                                            id: addSpMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                var nid = root.createWorkspace(mcWin.spaces);
                                                root.selectedWs = nid;
                                                root.showAllSpaces = false;
                                                root.selectedIdx = 0;
                                            }
                                        }
                                    }
                                    Text {
                                        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                                        text: I18n.tr("Add")
                                        color: Qt.rgba(1, 1, 1, 0.65)
                                        font.pixelSize: 11
                                    }
                                }
                            }

                            // Top-right toggle pill: "All Spaces" vs current space
                            Rectangle {
                                anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                                width: allTxt.implicitWidth + 22
                                height: 30
                                radius: 15
                                color: root.showAllSpaces ? root.accent : (allMa.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.12))
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.22)
                                Text {
                                    id: allTxt
                                    anchors.centerIn: parent
                                    text: root.showAllSpaces ? I18n.tr("Showing All Spaces") : I18n.tr("All Spaces")
                                    color: "#FFFFFF"
                                    font.family: Fonts.forWeight(Font.Medium, root.fam)
                                    font.pixelSize: 12
                                }
                                MouseArea {
                                    id: allMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.showAllSpaces = !root.showAllSpaces; root.selectedIdx = 0; }
                                }
                            }
                        }

                        // Mode B: App Exposé Header
                        Row {
                            visible: root.mode === "expose"
                            anchors.centerIn: parent
                            spacing: 12
                            Image {
                                readonly property string ico: root.iconFor(root.exposeAppKey)
                                visible: ico !== ""
                                width: 32; height: 32
                                anchors.verticalCenter: parent.verticalCenter
                                source: ico
                                sourceSize: Qt.size(64, 64)
                                smooth: true
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Text {
                                    text: root.exposeAppLabel !== "" ? root.exposeAppLabel : I18n.tr("App Expos\u00e9")
                                    textFormat: Text.PlainText
                                    color: "#FFFFFF"
                                    font.family: Fonts.forWeight(Font.DemiBold, root.fam)
                                    font.weight: Font.DemiBold
                                    font.pixelSize: 16
                                }
                                Text {
                                    text: mcWin.spreadRaw.length + " " + (mcWin.spreadRaw.length === 1 ? I18n.tr("window") : I18n.tr("windows"))
                                          + (mcWin.exposeMinimized.length > 0 ? (" \u00b7 " + mcWin.exposeMinimized.length + " " + I18n.tr("minimized")) : "")
                                    color: Qt.rgba(1, 1, 1, 0.65)
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }

                    // ── MAIN WINDOW SPREAD AREA ──
                    Item {
                        id: spreadArea
                        anchors { top: topBand.bottom; bottom: bottomTray.top; left: parent.left; right: parent.right }

                        Text {
                            visible: mcWin.cards.length === 0
                            anchors.centerIn: parent
                            text: root.mode === "expose" ? I18n.tr("No open windows for this application")
                                                         : I18n.tr("No open windows on this Desktop")
                            color: Qt.rgba(1, 1, 1, 0.55)
                            font.family: Fonts.forWeight(Font.Medium, root.fam)
                            font.pixelSize: 16
                        }

                        Repeater {
                            model: mcWin.cards
                            delegate: Item {
                                id: wCard
                                required property var modelData
                                required property int index
                                readonly property bool isSel: index === root.selectedIdx
                                readonly property bool isBeingDragged: mcWin.draggingCard && mcWin.draggingCard.addr === modelData.addr
                                readonly property string ico: root.iconFor(modelData.cls)
                                readonly property var tl: {
                                    if (!root.hub || !root.allowCapture) return null;
                                    var _t = root.hub.tlTick;
                                    return root.hub.tlFor(modelData.addr);
                                }

                                x: modelData.x
                                y: modelData.y
                                width: modelData.width
                                height: modelData.height + 30
                                opacity: isBeingDragged ? 0.35 : 1.0
                                Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                HoverHandler { id: cardHover }

                                Rectangle {
                                    id: previewFrame
                                    anchors { top: parent.top; left: parent.left; right: parent.right }
                                    height: wCard.modelData.height
                                    radius: 12
                                    clip: true
                                    scale: (cardHover.hovered || wCard.isSel) ? 1.025 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                                    color: Qt.rgba(0.12, 0.13, 0.17, 0.92)
                                    border.width: (cardHover.hovered || wCard.isSel) ? 2.5 : 1
                                    border.color: (cardHover.hovered || wCard.isSel) ? root.accent : Qt.rgba(1, 1, 1, 0.22)

                                    SafeCapture {
                                        id: cardCap
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        visible: root.allowCapture && hasContent
                                        want: root.allowCapture ? wCard.tl : null
                                        wantLive: cardHover.hovered && !wCard.isBeingDragged
                                        onHeldChanged: if (held !== null && !wantLive) capSnap.restart()
                                        Timer { id: capSnap; interval: Math.min(300, 35 * wCard.index + 60); onTriggered: cardCap.snap() }
                                    }

                                    // Fallback when live capture is off or waiting for frame
                                    Column {
                                        visible: !cardCap.visible
                                        anchors.centerIn: parent
                                        spacing: 8
                                        Image {
                                            visible: wCard.ico !== ""
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: 56; height: 56
                                            source: wCard.ico
                                            sourceSize: Qt.size(112, 112)
                                            smooth: true
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: Math.min(implicitWidth, previewFrame.width - 24)
                                            elide: Text.ElideRight
                                            text: root.appNameFor(wCard.modelData.cls)
                                            textFormat: Text.PlainText
                                            color: Qt.rgba(1, 1, 1, 0.78)
                                            font.pixelSize: 13
                                        }
                                    }

                                    // Space badge when viewing All Spaces or App Exposé
                                    Rectangle {
                                        visible: root.showAllSpaces || root.mode === "expose"
                                        anchors { top: parent.top; left: parent.left; margins: 8 }
                                        width: wsBadgeTxt.implicitWidth + 14; height: 20; radius: 10
                                        color: Qt.rgba(0, 0, 0, 0.65)
                                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.25)
                                        Text {
                                            id: wsBadgeTxt
                                            anchors.centerIn: parent
                                            text: I18n.tr("Desktop ") + wCard.modelData.wsName
                                            color: "#FFFFFF"
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                        }
                                    }

                                    // Click to focus, middle-click to close, drag to Space in Mission Control
                                    MouseArea {
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                        cursorShape: mcWin.draggingCard ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                        property real px: 0
                                        property real py: 0
                                        property bool dragged: false

                                        onPressed: mouse => {
                                            if (mouse.button === Qt.MiddleButton) {
                                                root.closeWindowFromOverview(wCard.modelData.addr);
                                                return;
                                            }
                                            var p = mapToItem(mcRoot, mouse.x, mouse.y);
                                            px = p.x; py = p.y; dragged = false;
                                            root.selectedIdx = wCard.index;
                                        }
                                        onPositionChanged: mouse => {
                                            if (!(mouse.buttons & Qt.LeftButton) || root.mode !== "mission") return;
                                            var p = mapToItem(mcRoot, mouse.x, mouse.y);
                                            if (!dragged && Math.abs(p.x - px) + Math.abs(p.y - py) > 10) {
                                                dragged = true;
                                                mcWin.draggingCard = wCard.modelData;
                                            }
                                            if (dragged) {
                                                mcWin.dragX = p.x;
                                                mcWin.dragY = p.y;
                                                mcWin.hoverDropWs = mcWin.findDropSpace(p.x, p.y);
                                            }
                                        }
                                        onReleased: mouse => {
                                            if (mouse.button !== Qt.LeftButton) return;
                                            if (dragged && mcWin.draggingCard) {
                                                var target = mcWin.hoverDropWs;
                                                var addr = mcWin.draggingCard.addr;
                                                mcWin.draggingCard = null;
                                                mcWin.hoverDropWs = -1;
                                                if (target === -2) {
                                                    var newId = root.createWorkspace(mcWin.spaces);
                                                    root.moveWindowToWorkspace(addr, newId);
                                                } else if (target > 0) {
                                                    root.moveWindowToWorkspace(addr, target);
                                                }
                                                dragged = false;
                                                return;
                                            }
                                            root.focusWindowAndClose(wCard.modelData.addr, wCard.modelData.wsId, false);
                                        }
                                        onCanceled: {
                                            dragged = false;
                                            mcWin.draggingCard = null;
                                            mcWin.hoverDropWs = -1;
                                        }
                                    }

                                    // Hover close button
                                    Rectangle {
                                        visible: cardHover.hovered && !mcWin.draggingCard
                                        anchors { top: parent.top; right: parent.right; margins: 8 }
                                        width: 24; height: 24; radius: 12
                                        color: clsMa.containsMouse ? "#FF5F57" : Qt.rgba(0, 0, 0, 0.65)
                                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.35)
                                        Text { anchors.centerIn: parent; text: "\u00d7"; color: "#FFFFFF"; font.pixelSize: 14 }
                                        MouseArea {
                                            id: clsMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: root.closeWindowFromOverview(wCard.modelData.addr)
                                        }
                                    }
                                }

                                // Title pill below window preview
                                Row {
                                    anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                                    height: 24
                                    spacing: 6
                                    Image {
                                        visible: wCard.ico !== ""
                                        width: 16; height: 16
                                        anchors.verticalCenter: parent.verticalCenter
                                        source: wCard.ico
                                        sourceSize: Qt.size(32, 32)
                                        smooth: true
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.min(implicitWidth, Math.max(60, wCard.width - 28))
                                        elide: Text.ElideRight
                                        text: wCard.modelData.title
                                        textFormat: Text.PlainText
                                        color: (cardHover.hovered || wCard.isSel) ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.84)
                                        font.family: Fonts.forWeight(Font.Medium, root.fam)
                                        font.pixelSize: 12
                                    }
                                }
                            }
                        }
                    }

                    // ── BOTTOM TRAY (Minimized windows in App Exposé, or shortcut hint in Mission Control) ──
                    Item {
                        id: bottomTray
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: mcWin.bottomBandH

                        Row {
                            visible: root.mode === "expose" && mcWin.exposeMinimized.length > 0
                            anchors.centerIn: parent
                            spacing: 12

                            Repeater {
                                model: mcWin.exposeMinimized
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 168; height: 74; radius: 10
                                    color: minMa.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0.12, 0.13, 0.18, 0.85)
                                    border.width: 1
                                    border.color: minMa.containsMouse ? root.accent : Qt.rgba(1, 1, 1, 0.22)

                                    Column {
                                        anchors { fill: parent; margins: 10 }
                                        spacing: 4
                                        Text {
                                            text: I18n.tr("Minimized")
                                            color: "#FEBC2E"
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                        }
                                        Text {
                                            width: parent.width
                                            elide: Text.ElideRight
                                            text: modelData.title
                                            textFormat: Text.PlainText
                                            color: "#FFFFFF"
                                            font.pixelSize: 12
                                        }
                                    }
                                    MouseArea {
                                        id: minMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: root.focusWindowAndClose(modelData.addr, 0, true)
                                    }
                                }
                            }
                        }

                        Text {
                            visible: root.mode === "mission"
                            anchors.centerIn: parent
                            text: I18n.tr("Drag a window onto a Desktop above to move it \u00b7 Press Esc to close")
                            color: Qt.rgba(1, 1, 1, 0.48)
                            font.pixelSize: 11
                        }
                    }

                    // Floating drag ghost when dragging a window card onto a Space
                    Rectangle {
                        visible: mcWin.draggingCard !== null
                        z: 100
                        x: mcWin.dragX - width / 2
                        y: mcWin.dragY - height / 2
                        width: 156; height: 96; radius: 10
                        color: Qt.rgba(0.14, 0.16, 0.22, 0.92)
                        border.width: 2
                        border.color: mcWin.hoverDropWs !== -1 ? "#34C759" : root.accent
                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Image {
                                readonly property string ico: mcWin.draggingCard ? root.iconFor(mcWin.draggingCard.cls) : ""
                                visible: ico !== ""
                                width: 22; height: 22
                                source: ico
                                sourceSize: Qt.size(44, 44)
                            }
                            Text {
                                width: 104
                                elide: Text.ElideRight
                                text: mcWin.draggingCard ? mcWin.draggingCard.title : ""
                                textFormat: Text.PlainText
                                color: "#FFFFFF"
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                        }
                    }
                }
            }
        }
    }
}
