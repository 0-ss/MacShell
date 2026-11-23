import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
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
    readonly property bool darkMode: dock ? dock.darkMode : true
    readonly property color accent: dock ? dock.accent : "#0A84FF"
    readonly property string fam: dock ? dock.fontFamily : "Open Runde"
    readonly property string home: Quickshell.env("HOME")

    // ── persisted settings (~/.config/macbar/windowmgmt.json) ──
    property bool snapToEdges: true
    property int tileGap: 8
    property bool stageManager: false
    property bool stageAutoHide: false
    property string clickWallpaperReveal: "always"   // "always" | "stage" | "off"
    property string hotCornerTL: "none"
    property string hotCornerTR: "none"
    property string hotCornerBL: "none"
    property string hotCornerBR: "none"
    property int hotCornerDelay: 180
    property bool ready: false

    readonly property var hotCornerActions: [
        { id: "none",            label: I18n.tr("Off") },
        { id: "mission-control", label: I18n.tr("Mission Control") },
        { id: "expose",          label: I18n.tr("App Expos\u00e9") },
        { id: "show-desktop",    label: I18n.tr("Show Desktop") },
        { id: "notifications",   label: I18n.tr("Notification Center") },
        { id: "quick-note",      label: I18n.tr("Quick Note") },
        { id: "lock-screen",     label: I18n.tr("Lock Screen") },
        { id: "screensaver",     label: I18n.tr("Start Screen Saver") },
        { id: "spotlight",       label: I18n.tr("Spotlight") }
    ]

    readonly property bool anyHotCorner: hotCornerTL !== "none" || hotCornerTR !== "none"
                                      || hotCornerBL !== "none" || hotCornerBR !== "none"

    FileView {
        id: store
        path: root.home + "/.config/macbar/windowmgmt.json"
        printErrors: false
        onLoaded: {
            try {
                var o = JSON.parse(text());
                if (o.snapToEdges !== undefined) root.snapToEdges = !!o.snapToEdges;
                if (typeof o.tileGap === "number") root.tileGap = Math.max(0, Math.min(32, Math.round(o.tileGap)));
                if (o.stageManager !== undefined) root.stageManager = !!o.stageManager;
                if (o.stageAutoHide !== undefined) root.stageAutoHide = !!o.stageAutoHide;
                if (typeof o.clickWallpaperReveal === "string" && ["always", "stage", "off"].indexOf(o.clickWallpaperReveal) >= 0)
                    root.clickWallpaperReveal = o.clickWallpaperReveal;
                if (typeof o.hotCornerTL === "string") root.hotCornerTL = o.hotCornerTL;
                if (typeof o.hotCornerTR === "string") root.hotCornerTR = o.hotCornerTR;
                if (typeof o.hotCornerBL === "string") root.hotCornerBL = o.hotCornerBL;
                if (typeof o.hotCornerBR === "string") root.hotCornerBR = o.hotCornerBR;
                if (typeof o.hotCornerDelay === "number") root.hotCornerDelay = Math.max(60, Math.min(800, Math.round(o.hotCornerDelay)));
            } catch (err) { }
            root.ready = true;
            if (root.stageManager) stageSyncSoon.restart();
        }
        onLoadFailed: root.ready = true
    }

    Timer {
        id: saveT
        interval: 400
        onTriggered: {
            var payload = JSON.stringify({
                snapToEdges: root.snapToEdges,
                tileGap: root.tileGap,
                stageManager: root.stageManager,
                stageAutoHide: root.stageAutoHide,
                clickWallpaperReveal: root.clickWallpaperReveal,
                hotCornerTL: root.hotCornerTL,
                hotCornerTR: root.hotCornerTR,
                hotCornerBL: root.hotCornerBL,
                hotCornerBR: root.hotCornerBR,
                hotCornerDelay: root.hotCornerDelay
            }, null, 2);
            Quickshell.execDetached(["sh", "-c", "d=\"$HOME/.config/macbar\"; mkdir -p \"$d\" && t=$(mktemp \"$d/windowmgmt.json.XXXXXX\") && printf '%s' \"$1\" > \"$t\" && mv -f \"$t\" \"$d/windowmgmt.json\"", "sh", payload]);
        }
    }
    function scheduleSave() { if (ready) saveT.restart(); }

    onSnapToEdgesChanged: scheduleSave()
    onTileGapChanged: scheduleSave()
    onStageAutoHideChanged: scheduleSave()
    onClickWallpaperRevealChanged: scheduleSave()
    onHotCornerTLChanged: scheduleSave()
    onHotCornerTRChanged: scheduleSave()
    onHotCornerBLChanged: scheduleSave()
    onHotCornerBRChanged: scheduleSave()
    onHotCornerDelayChanged: scheduleSave()
    onStageManagerChanged: {
        scheduleSave();
        if (stageManager) {
            stageSyncSoon.restart();
        } else {
            restoreAllStaged();
            stageByScreen = ({});
        }
    }

    // Only request geometry polling from sharedHub when Stage Manager or live edge-snap drag needs it
    Binding {
        target: root.hub
        property: "wmWantsGeo"
        value: root.stageManager || root.snapPreviewActive
        when: root.hub !== null
    }

    Component.onDestruction: {
        if (desktopRevealed) restoreDesktop();
        if (stageManager || Object.keys(stageParkedOrigin).length > 0) restoreAllStaged();
    }

    // ── Hyprland data helpers (work even when geometry polling is idle) ──
    function liveMonitors() {
        var ms = (hub && hub.monData && hub.monData.length > 0) ? hub.monData : [];
        if (ms.length > 0) return ms;
        var out = [], hms = Hyprland.monitors.values;
        for (var i = 0; i < hms.length; i++) {
            var m = hms[i].lastIpcObject;
            if (m && m.name !== undefined) out.push(m);
        }
        return out;
    }

    function liveClients() {
        var cs = (hub && hub.glassClients && hub.glassClients.length > 0) ? hub.glassClients : [];
        if (cs.length > 0) return cs;
        var out = [], ts = Hyprland.toplevels.values;
        for (var i = 0; i < ts.length; i++) {
            var o = ts[i].lastIpcObject;
            if (o && o.address !== undefined) out.push(o);
        }
        return out;
    }

    function monitorFor(idOrName) {
        var ms = liveMonitors();
        for (var i = 0; i < ms.length; i++) {
            if (ms[i].id === idOrName || ms[i].name === idOrName) return ms[i];
        }
        for (var j = 0; j < ms.length; j++) if (ms[j].focused) return ms[j];
        return ms.length > 0 ? ms[0] : null;
    }

    function focusedClient(explicitAddr) {
        var want = WM.normAddr(explicitAddr);
        var cs = liveClients();
        for (var i = 0; i < cs.length; i++) {
            var c = cs[i];
            var a = WM.normAddr(c.address);
            if (want !== "") {
                if (a === want) return c;
            } else if (c.mapped && !c.hidden && c.focusHistoryID === 0) {
                return c;
            }
        }
        if (want === "") {
            var best = null;
            for (var j = 0; j < cs.length; j++) {
                var c2 = cs[j];
                if (!c2.mapped || c2.hidden || WM.isSpecialWorkspace(c2.workspace) || WM.isShellClass(c2["class"])) continue;
                if (!best || (c2.focusHistoryID || 999) < (best.focusHistoryID || 999)) best = c2;
            }
            return best;
        }
        return null;
    }

    function iconForClass(cls) {
        if (!cls) return "";
        if (dock && dock.lookup && dock.iconSrc) {
            var e = dock.lookup(cls);
            if (e && e.icon) return dock.iconSrc(e.icon);
        }
        var p = Quickshell.iconPath(String(cls), true);
        if (p === "") p = Quickshell.iconPath(String(cls).toLowerCase(), true);
        return p;
    }

    function appNameForClass(cls) {
        if (!cls) return "";
        if (dock && dock.lookup) {
            var e = dock.lookup(cls);
            if (e && e.name) return e.name;
        }
        return String(cls);
    }

    function usableOptsFor(mon) {
        var topInset = (bar && bar.barEnabled) ? Math.round(bar.barH || 28) : 0;
        var bottomInset = 0;
        if (dock && dock.dockEnabled && !dock.autoHide) {
            var dockOnMon = !dock.monitor || dock.monitor === "" || (mon && dock.monitor === mon.name);
            if (dockOnMon) bottomInset = Math.round((dock.bgHeight || 72) + (dock.bottomMargin || 6) + 8);
        }
        var leftInset = (stageManager && !stageAutoHide) ? 168 : 0;
        var titleBarOffset = (hub && hub.decor && hub.decor.enabled) ? Math.round(hub.decor.barH || 28) : 0;
        return {
            topInset: topInset,
            bottomInset: bottomInset,
            leftInset: leftInset,
            rightInset: 0,
            gap: tileGap,
            titleBarOffset: titleBarOffset
        };
    }

    // ═════════════ 1. WINDOW TILING & SNAP-TO-EDGES ═════════════
    property var preTileRects: ({})   // addr -> { floating, x, y, w, h }
    property bool snapPreviewActive: false
    property string snapPreviewScreen: ""
    property string snapPreviewZone: ""
    property var snapPreviewRect: ({ x: 0, y: 0, width: 0, height: 0 })

    function tileWindow(preset, explicitAddr) {
        try { Hyprland.refreshMonitors(); Hyprland.refreshToplevels(); } catch (err) { }
        var p = String(preset || "").toLowerCase();
        if (p === "restore") return restoreTiledWindow(explicitAddr);
        if (p === "arrange-left-right") return arrangePair("left-right");
        if (p === "arrange-right-left") return arrangePair("right-left");

        var c = focusedClient(explicitAddr);
        if (!c) return false;
        var addr = WM.normAddr(c.address);
        if (!addr) return false;
        var mon = monitorFor(c.monitor);
        if (!mon) return false;

        var opts = usableOptsFor(mon);
        if (Array.isArray(c.size)) { opts.winW = c.size[0]; opts.winH = c.size[1]; }
        var rect = WM.computeTileRect(p, mon, opts);
        if (!rect) return false;

        if (!preTileRects[addr] && Array.isArray(c.at) && Array.isArray(c.size)) {
            var next = {};
            for (var k in preTileRects) next[k] = preTileRects[k];
            next[addr] = { floating: !!c.floating, x: c.at[0], y: c.at[1], w: c.size[0], h: c.size[1] };
            preTileRects = next;
        }

        var sel = 'window = "address:' + addr + '"';
        if (c.fullscreen) Hyprland.dispatch('hl.dsp.window.fullscreen_state({ internal = 0, client = 0, ' + sel + ' })');
        if (!c.floating) Hyprland.dispatch('hl.dsp.window.float({ action = "enable", ' + sel + ' })');
        Hyprland.dispatch('hl.dsp.window.resize({ x = ' + rect.width + ', y = ' + rect.height + ', "exact", ' + sel + ' })');
        Hyprland.dispatch('hl.dsp.window.move({ x = ' + rect.x + ', y = ' + rect.y + ', "exact", ' + sel + ' })');
        Hyprland.dispatch('hl.dsp.focus({ ' + sel + ' })');
        if (bar && bar.playSound) bar.playSound("tink", 0.3);
        return true;
    }

    function restoreTiledWindow(explicitAddr) {
        var c = focusedClient(explicitAddr);
        if (!c) return false;
        var addr = WM.normAddr(c.address);
        var saved = preTileRects[addr];
        if (!saved) return false;

        var next = {};
        for (var k in preTileRects) if (k !== addr) next[k] = preTileRects[k];
        preTileRects = next;

        var sel = 'window = "address:' + addr + '"';
        if (!saved.floating) {
            Hyprland.dispatch('hl.dsp.window.float({ action = "disable", ' + sel + ' })');
        } else {
            Hyprland.dispatch('hl.dsp.window.resize({ x = ' + Math.round(saved.w) + ', y = ' + Math.round(saved.h) + ', "exact", ' + sel + ' })');
            Hyprland.dispatch('hl.dsp.window.move({ x = ' + Math.round(saved.x) + ', y = ' + Math.round(saved.y) + ', "exact", ' + sel + ' })');
        }
        return true;
    }

    function arrangePair(order) {
        try { Hyprland.refreshMonitors(); Hyprland.refreshToplevels(); } catch (err) { }
        var primary = focusedClient("");
        if (!primary) return false;
        var mon = monitorFor(primary.monitor);
        if (!mon) return false;
        var wsId = primary.workspace ? primary.workspace.id : (mon.activeWorkspace ? mon.activeWorkspace.id : 1);
        var cs = liveClients(), candidates = [];
        for (var i = 0; i < cs.length; i++) {
            var c = cs[i];
            if (!c.mapped || c.hidden || WM.isSpecialWorkspace(c.workspace) || WM.isShellClass(c["class"])) continue;
            if (c.monitor !== mon.id || !c.workspace || c.workspace.id !== wsId) continue;
            candidates.push(c);
        }
        candidates.sort(function (a, b) { return (a.focusHistoryID || 999) - (b.focusHistoryID || 999); });
        if (candidates.length === 0) return false;
        var firstZone = order === "right-left" ? "right" : "left";
        var secondZone = order === "right-left" ? "left" : "right";
        tileWindow(firstZone, candidates[0].address);
        if (candidates.length >= 2) tileWindow(secondZone, candidates[1].address);
        Hyprland.dispatch('hl.dsp.focus({ window = "address:' + WM.normAddr(candidates[0].address) + '" })');
        return true;
    }

    function updateDragSnap(screenName, addr, globalX, globalY) {
        if (!snapToEdges) { cancelDragSnap(); return; }
        var mon = monitorFor(screenName);
        if (!mon) { cancelDragSnap(); return; }
        var opts = usableOptsFor(mon);
        var zone = WM.detectSnapZone(globalX, globalY, mon, opts);
        if (zone === "") { cancelDragSnap(); return; }
        var rect = WM.computeTileRect(zone, mon, opts);
        if (!rect) { cancelDragSnap(); return; }
        snapPreviewScreen = mon.name;
        snapPreviewZone = zone;
        snapPreviewRect = { x: rect.x - mon.x, y: rect.y - mon.y, width: rect.width, height: rect.height };
        snapPreviewActive = true;
    }

    function commitDragSnap(addr) {
        var z = snapPreviewZone;
        var active = snapPreviewActive;
        cancelDragSnap();
        if (!active || z === "") return false;
        return tileWindow(z, addr);
    }

    function cancelDragSnap() {
        snapPreviewActive = false;
        snapPreviewZone = "";
    }

    function zoneLabel(z) {
        var labels = {
            "left": I18n.tr("Left Half"),
            "right": I18n.tr("Right Half"),
            "top": I18n.tr("Top Half"),
            "bottom": I18n.tr("Bottom Half"),
            "top-left": I18n.tr("Top Left Quarter"),
            "top-right": I18n.tr("Top Right Quarter"),
            "bottom-left": I18n.tr("Bottom Left Quarter"),
            "bottom-right": I18n.tr("Bottom Right Quarter"),
            "fill": I18n.tr("Fill Screen")
        };
        return labels[z] || z;
    }

    // Snap-to-Edge visual preview (Loader: 0 windows / 0 GPU memory unless actively snapping during drag)
    Loader {
        active: root.snapPreviewActive
        sourceComponent: Variants {
            model: Quickshell.screens
            PanelWindow {
                required property var modelData
                screen: modelData
                visible: modelData.name === root.snapPreviewScreen
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                WlrLayershell.namespace: "macsnap"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                mask: Region {}

                Rectangle {
                    x: root.snapPreviewRect.x
                    y: root.snapPreviewRect.y
                    width: root.snapPreviewRect.width
                    height: root.snapPreviewRect.height
                    radius: 14
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, root.darkMode ? 0.22 : 0.18)
                    border.width: 2
                    border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.85)
                    Behavior on x { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                    Behavior on width { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                    Rectangle {
                        anchors.centerIn: parent
                        width: snapTxt.implicitWidth + 24
                        height: 30
                        radius: 15
                        color: root.darkMode ? Qt.rgba(0.11, 0.11, 0.13, 0.82) : Qt.rgba(1, 1, 1, 0.86)
                        border.width: 1
                        border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.12)
                        Text {
                            id: snapTxt
                            anchors.centerIn: parent
                            text: root.zoneLabel(root.snapPreviewZone)
                            color: root.darkMode ? "#FFFFFF" : "#1D1D1F"
                            font.family: Fonts.forWeight(Font.DemiBold, root.fam)
                            font.weight: Font.DemiBold
                            font.pixelSize: 12
                        }
                    }
                }
            }
        }
    }

    // ═════════════ 2. REVEAL DESKTOP (SHOW DESKTOP + CLICK WALLPAPER) ═════════════
    property bool desktopRevealed: false
    property var revealedRecords: []
    property real revealedAt: 0

    function revealDesktop(screenName) {
        try { Hyprland.refreshMonitors(); Hyprland.refreshToplevels(); } catch (err) { }
        var mon = monitorFor(screenName);
        var cs = liveClients();
        var targets = [];
        if (mon && mon.activeWorkspace) {
            targets = WM.collectRevealTargets(cs, mon.id, mon.activeWorkspace.id);
        } else {
            var ms = liveMonitors();
            for (var i = 0; i < ms.length; i++) {
                if (ms[i].activeWorkspace)
                    targets = targets.concat(WM.collectRevealTargets(cs, ms[i].id, ms[i].activeWorkspace.id));
            }
        }
        if (targets.length === 0) return false;
        revealedAt = Date.now();
        revealedRecords = targets;
        desktopRevealed = true;
        for (var j = 0; j < targets.length; j++) {
            Hyprland.dispatch('hl.dsp.window.move({ workspace = "special:desktop-peek", follow = false, window = "address:' + targets[j].addr + '" })');
        }
        if (bar && bar.playSound) bar.playSound("tink", 0.25);
        return true;
    }

    function restoreDesktop() {
        var recs = revealedRecords.slice();
        revealedRecords = [];
        desktopRevealed = false;
        if (recs.length === 0) return false;
        for (var i = recs.length - 1; i >= 0; i--) {
            Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + recs[i].ws + '", follow = false, window = "address:' + recs[i].addr + '" })');
        }
        if (recs.length > 0) {
            Hyprland.dispatch('hl.dsp.focus({ window = "address:' + recs[0].addr + '" })');
        }
        return true;
    }

    function toggleRevealDesktop(screenName) {
        if (desktopRevealed) return restoreDesktop();
        return revealDesktop(screenName);
    }

    function handleWallpaperClick(screenName) {
        if (desktopRevealed) { restoreDesktop(); return true; }
        if (clickWallpaperReveal === "off") return false;
        if (clickWallpaperReveal === "stage" && !stageManager) return false;
        return revealDesktop(screenName);
    }

    // Subtle macOS edge vignette border while desktop is revealed (Loader: 0 resources otherwise)
    Loader {
        active: root.desktopRevealed
        sourceComponent: Variants {
            model: Quickshell.screens
            PanelWindow {
                id: revWin
                required property var modelData
                screen: modelData
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                WlrLayershell.namespace: "macreveal"
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                readonly property int edgeW: 16
                mask: Region {
                    Region { x: 0; y: 0; width: revWin.width; height: revWin.edgeW }
                    Region { x: 0; y: revWin.height - revWin.edgeW; width: revWin.width; height: revWin.edgeW }
                    Region { x: 0; y: 0; width: revWin.edgeW; height: revWin.height }
                    Region { x: revWin.width - revWin.edgeW; y: 0; width: revWin.edgeW; height: revWin.height }
                }

                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border.width: 14
                    border.color: Qt.rgba(0, 0, 0, 0.36)
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 14
                        radius: 10
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.22)
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.restoreDesktop()
                    }
                }
            }
        }
    }

    // ═════════════ 3. STAGE MANAGER ═════════════
    property var stageGroupOverrides: ({})   // addr -> groupId
    property var stageParkedOrigin: ({})     // addr -> { ws, mon }
    property var stageByScreen: ({})         // screenName -> { active, inactive }
    property bool stageSwitching: false

    Timer {
        id: stageSyncSoon
        interval: 80
        onTriggered: root.syncStages(true)
    }

    function syncStages(autoPark) {
        if (!stageManager) return;
        var ms = liveMonitors();
        var cs = liveClients();
        var byScr = {};
        var alive = {};
        for (var ci = 0; ci < cs.length; ci++) alive[WM.normAddr(cs[ci].address)] = true;

        // Prune closed windows from override/origin maps
        var nextOrig = {}, origChanged = false;
        for (var ok in stageParkedOrigin) {
            if (alive[ok]) nextOrig[ok] = stageParkedOrigin[ok];
            else origChanged = true;
        }
        if (origChanged) stageParkedOrigin = nextOrig;

        for (var i = 0; i < ms.length; i++) {
            var m = ms[i];
            var wsId = m.activeWorkspace ? m.activeWorkspace.id : 1;
            var res = WM.buildStages(cs, m.id, wsId, stageGroupOverrides);
            byScr[m.name] = res;

            if (autoPark && !stageSwitching && res.active && res.inactive.length > 0) {
                var toPark = [];
                for (var j = 0; j < res.inactive.length; j++) {
                    var wins = res.inactive[j].windows;
                    for (var k = 0; k < wins.length; k++) {
                        if (!wins[k].parked) toPark.push(wins[k].addr);
                    }
                }
                if (toPark.length > 0) {
                    var orig = {};
                    for (var pk in stageParkedOrigin) orig[pk] = stageParkedOrigin[pk];
                    for (var p = 0; p < toPark.length; p++) {
                        orig[toPark[p]] = { ws: wsId, mon: m.id };
                        Hyprland.dispatch('hl.dsp.window.move({ workspace = "special:stage", follow = false, window = "address:' + toPark[p] + '" })');
                    }
                    stageParkedOrigin = orig;
                }
            }
        }
        stageByScreen = byScr;
    }

    function activateStage(screenName, stage) {
        if (!stage || !stage.windows || stage.windows.length === 0) return;
        var mon = monitorFor(screenName);
        if (!mon) return;
        var wsId = mon.activeWorkspace ? mon.activeWorkspace.id : 1;
        var cur = stageByScreen[screenName];
        stageSwitching = true;

        var orig = {};
        for (var pk in stageParkedOrigin) orig[pk] = stageParkedOrigin[pk];

        // Park current active stage windows
        if (cur && cur.active && cur.active.id !== stage.id) {
            for (var i = 0; i < cur.active.windows.length; i++) {
                var wa = cur.active.windows[i].addr;
                orig[wa] = { ws: wsId, mon: mon.id };
                Hyprland.dispatch('hl.dsp.window.move({ workspace = "special:stage", follow = false, window = "address:' + wa + '" })');
            }
        }

        // Bring selected stage windows onto active workspace
        for (var j = stage.windows.length - 1; j >= 0; j--) {
            var sa = stage.windows[j].addr;
            delete orig[sa];
            Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + wsId + '", follow = false, window = "address:' + sa + '" })');
        }
        stageParkedOrigin = orig;
        Hyprland.dispatch('hl.dsp.focus({ window = "address:' + stage.windows[0].addr + '" })');
        stageSwitchEnd.restart();
        if (bar && bar.playSound) bar.playSound("tink", 0.3);
    }

    function addStageToActive(screenName, stage) {
        if (!stage || !stage.windows || stage.windows.length === 0) return;
        var mon = monitorFor(screenName);
        if (!mon) return;
        var wsId = mon.activeWorkspace ? mon.activeWorkspace.id : 1;
        var cur = stageByScreen[screenName];
        var targetGroup = (cur && cur.active) ? cur.active.id : stage.id;

        var ov = {};
        for (var k in stageGroupOverrides) ov[k] = stageGroupOverrides[k];
        if (cur && cur.active) {
            for (var a = 0; a < cur.active.windows.length; a++) ov[cur.active.windows[a].addr] = targetGroup;
        }
        var orig = {};
        for (var pk in stageParkedOrigin) orig[pk] = stageParkedOrigin[pk];

        stageSwitching = true;
        for (var i = 0; i < stage.windows.length; i++) {
            var sa = stage.windows[i].addr;
            ov[sa] = targetGroup;
            delete orig[sa];
            Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + wsId + '", follow = false, window = "address:' + sa + '" })');
        }
        stageGroupOverrides = ov;
        stageParkedOrigin = orig;
        Hyprland.dispatch('hl.dsp.focus({ window = "address:' + stage.windows[0].addr + '" })');
        stageSwitchEnd.restart();
    }

    function restoreAllStaged() {
        var cs = liveClients();
        var fallbackMon = monitorFor("");
        var fallbackWs = (fallbackMon && fallbackMon.activeWorkspace && fallbackMon.activeWorkspace.id > 0) ? fallbackMon.activeWorkspace.id : 1;
        for (var i = 0; i < cs.length; i++) {
            var c = cs[i];
            if (!c || !c.workspace || String(c.workspace.name || "") !== "special:stage") continue;
            var a = WM.normAddr(c.address);
            if (!a) continue;
            var saved = stageParkedOrigin[a];
            var ws = (saved && saved.ws > 0) ? saved.ws : fallbackWs;
            Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + ws + '", follow = false, window = "address:' + a + '" })');
        }
        stageParkedOrigin = ({});
        stageGroupOverrides = ({});
    }

    Timer {
        id: stageSwitchEnd
        interval: 220
        onTriggered: {
            root.stageSwitching = false;
            try { Hyprland.refreshToplevels(); } catch (err) { }
            root.syncStages(false);
        }
    }

    // React to Hyprland events for Stage Manager + Desktop Reveal auto-restore + preTile cleanup
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            var en = event.name;
            if (en === "closewindow") {
                var a = WM.normAddr(event.data);
                if (a && root.preTileRects[a]) {
                    var next = {};
                    for (var k in root.preTileRects) if (k !== a) next[k] = root.preTileRects[k];
                    root.preTileRects = next;
                }
            }
            if (root.desktopRevealed && Date.now() - root.revealedAt > 350) {
                if (en === "openwindow") root.restoreDesktop();
            }
            if (root.stageManager && (en === "openwindow" || en === "closewindow" || en === "workspace" || en === "workspacev2" || en === "movewindow" || en === "movewindowv2")) {
                stageSyncSoon.restart();
            }
        }
    }

    Connections {
        target: root.hub
        function onGlassClientsChanged() {
            if (root.stageManager && !root.stageSwitching) root.syncStages(false);
        }
    }

    // Stage Manager left-edge strip (0 PanelWindows when stageManager === false)
    Variants {
        model: root.stageManager ? Quickshell.screens : []
        PanelWindow {
            id: stageWin
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true }
            width: 168
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "macstage"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            readonly property var stageData: root.stageByScreen[modelData.name] || ({ active: null, inactive: [] })
            readonly property var stages: (stageData.inactive || []).slice(0, 5)
            readonly property bool stripOpen: !root.stageAutoHide || edgeHover.hovered || stripHover.hovered
            readonly property bool hasItems: stages.length > 0

            mask: Region {
                Region {
                    x: 0
                    y: (root.bar && root.bar.barEnabled ? root.bar.barH : 28) + 12
                    width: stageWin.hasItems ? (stageWin.stripOpen ? 160 : 8) : 0
                    height: Math.max(0, stageWin.height - 120)
                }
            }

            Item {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 8
                HoverHandler { id: edgeHover }
            }

            Item {
                id: stripBox
                x: stageWin.stripOpen ? 10 : -162
                anchors.verticalCenter: parent.verticalCenter
                width: 146
                height: stageCol.implicitHeight + 16
                visible: stageWin.hasItems
                Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                HoverHandler { id: stripHover }

                Column {
                    id: stageCol
                    anchors.centerIn: parent
                    spacing: 14
                    width: parent.width

                    Repeater {
                        model: stageWin.stages
                        delegate: Item {
                            id: card
                            required property var modelData
                            required property int index
                            width: 140
                            height: 98
                            anchors.horizontalCenter: parent.horizontalCenter

                            readonly property var primaryWin: modelData.windows.length > 0 ? modelData.windows[0] : null
                            readonly property var tl: {
                                if (!primaryWin || !root.hub) return null;
                                var _t = root.hub.tlTick;
                                return root.hub.tlFor(primaryWin.addr);
                            }
                            readonly property bool useCap: root.dock ? root.dock.windowCapture : true
                            readonly property string iconSrc: root.iconForClass(modelData.appClass)

                            HoverHandler { id: cardHover }

                            // Stacked deck hint behind card when a stage has multiple windows
                            Rectangle {
                                visible: card.modelData.windows.length > 1
                                x: 6; y: -5; width: parent.width - 12; height: parent.height - 4
                                radius: 10
                                color: root.darkMode ? Qt.rgba(0.18, 0.18, 0.21, 0.72) : Qt.rgba(0.92, 0.92, 0.95, 0.78)
                                border.width: 1
                                border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12)
                            }

                            Rectangle {
                                id: cardBody
                                anchors.fill: parent
                                radius: 11
                                clip: true
                                scale: cardHover.hovered ? 1.04 : 1.0
                                Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                                color: root.darkMode ? Qt.rgba(0.13, 0.13, 0.16, 0.88) : Qt.rgba(0.96, 0.96, 0.98, 0.90)
                                border.width: cardHover.hovered ? 1.5 : 1
                                border.color: cardHover.hovered ? root.accent : (root.darkMode ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.16))

                                SafeCapture {
                                    id: stageCap
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    visible: card.useCap && hasContent
                                    want: (card.useCap && stageWin.stripOpen) ? card.tl : null
                                    wantLive: cardHover.hovered && stageWin.stripOpen
                                    onHeldChanged: if (held !== null && !wantLive) snapOnce.restart()
                                    Timer { id: snapOnce; interval: 100; onTriggered: stageCap.snap() }
                                }

                                // Fallback icon when live capture is off or pending
                                Image {
                                    visible: !stageCap.visible && card.iconSrc !== ""
                                    anchors.centerIn: parent
                                    width: 40; height: 40
                                    source: card.iconSrc
                                    sourceSize: Qt.size(80, 80)
                                    smooth: true
                                }

                                // Bottom gradient + app badge + label
                                Rectangle {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                    height: 28
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: "transparent" }
                                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.68) }
                                    }
                                    Row {
                                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 6; rightMargin: 6 }
                                        spacing: 5
                                        Image {
                                            visible: card.iconSrc !== ""
                                            width: 16; height: 16
                                            anchors.verticalCenter: parent.verticalCenter
                                            source: card.iconSrc
                                            sourceSize: Qt.size(32, 32)
                                            smooth: true
                                        }
                                        Text {
                                            width: Math.max(0, parent.width - (card.iconSrc !== "" ? 22 : 0) - (card.modelData.windows.length > 1 ? 22 : 0))
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: root.appNameForClass(card.modelData.appClass)
                                            textFormat: Text.PlainText
                                            elide: Text.ElideRight
                                            color: "#FFFFFF"
                                            font.family: Fonts.forWeight(Font.Medium, root.fam)
                                            font.pixelSize: 11
                                        }
                                        Rectangle {
                                            visible: card.modelData.windows.length > 1
                                            width: 18; height: 16; radius: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: Qt.rgba(1, 1, 1, 0.24)
                                            Text {
                                                anchors.centerIn: parent
                                                text: String(card.modelData.windows.length)
                                                color: "#FFFFFF"
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => {
                                        if ((mouse.modifiers & Qt.ShiftModifier) !== 0)
                                            root.addStageToActive(stageWin.modelData.name, card.modelData);
                                        else
                                            root.activateStage(stageWin.modelData.name, card.modelData);
                                    }
                                }

                                // "+" button on hover: merge this stage into the active stage
                                Rectangle {
                                    visible: cardHover.hovered
                                    anchors { top: parent.top; right: parent.right; margins: 5 }
                                    width: 20; height: 20; radius: 10
                                    color: addMa.containsMouse ? root.accent : Qt.rgba(0, 0, 0, 0.62)
                                    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.35)
                                    Text {
                                        anchors.centerIn: parent
                                        text: "+"
                                        color: "#FFFFFF"
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                    }
                                    MouseArea {
                                        id: addMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.addStageToActive(stageWin.modelData.name, card.modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ═════════════ 4. HOT CORNERS ═════════════
    function screenHasFullscreen(screenName) {
        var mon = monitorFor(screenName);
        if (!mon || !mon.activeWorkspace) return false;
        var wsId = mon.activeWorkspace.id;
        var cs = liveClients();
        for (var i = 0; i < cs.length; i++) {
            var c = cs[i];
            if (c.mapped && !c.hidden && c.monitor === mon.id && c.workspace && c.workspace.id === wsId && (c.fullscreen === true || c.fullscreen === 2))
                return true;
        }
        return false;
    }

    function runHotCornerAction(action, screenName) {
        if (!action || action === "none") return;
        if (screenHasFullscreen(screenName)) return;
        if (action === "mission-control") {
            if (hub && hub.mc) hub.mc.toggleMission(screenName);
        } else if (action === "expose") {
            if (hub && hub.mc) hub.mc.toggleExpose("", screenName);
        } else if (action === "show-desktop") {
            toggleRevealDesktop(screenName);
        } else if (action === "notifications") {
            if (bar && bar.notifPopRequest) bar.notifPopRequest(true);
        } else if (action === "quick-note") {
            toggleQuickNote();
        } else if (action === "lock-screen" || action === "screensaver") {
            Quickshell.execDetached(["sh", "-c",
                "if [ -x \"$HOME/.config/quickshell/MacLock/lock-via-ipc.sh\" ]; then exec sh \"$HOME/.config/quickshell/MacLock/lock-via-ipc.sh\"; "
                + "else pgrep -f -- \"-c [M]acLock\" >/dev/null 2>&1 || qs -c MacLock; fi"]);
        } else if (action === "spotlight") {
            if (bar && bar.search) bar.search();
        }
    }

    // Hot Corners layer (0 PanelWindows when all corners are "none" or in gaming mode)
    Variants {
        model: (root.anyHotCorner && !(root.bar && root.bar.gaming)) ? Quickshell.screens : []
        PanelWindow {
            id: hcWin
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "machotcorners"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            readonly property int sz: 5
            mask: Region {
                Region { x: 0; y: 0; width: root.hotCornerTL !== "none" ? hcWin.sz : 0; height: root.hotCornerTL !== "none" ? hcWin.sz : 0 }
                Region { x: hcWin.width - hcWin.sz; y: 0; width: root.hotCornerTR !== "none" ? hcWin.sz : 0; height: root.hotCornerTR !== "none" ? hcWin.sz : 0 }
                Region { x: 0; y: hcWin.height - hcWin.sz; width: root.hotCornerBL !== "none" ? hcWin.sz : 0; height: root.hotCornerBL !== "none" ? hcWin.sz : 0 }
                Region { x: hcWin.width - hcWin.sz; y: hcWin.height - hcWin.sz; width: root.hotCornerBR !== "none" ? hcWin.sz : 0; height: root.hotCornerBR !== "none" ? hcWin.sz : 0 }
            }

            component CornerSensor: MouseArea {
                id: sensor
                required property string action
                property bool armed: true
                width: hcWin.sz; height: hcWin.sz
                visible: action !== "none"
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onEntered: if (armed && action !== "none") dwellT.restart()
                onExited: { dwellT.stop(); rearmT.restart(); }
                Timer {
                    id: dwellT
                    interval: root.hotCornerDelay
                    onTriggered: {
                        sensor.armed = false;
                        root.runHotCornerAction(sensor.action, hcWin.modelData.name);
                    }
                }
                Timer {
                    id: rearmT
                    interval: 350
                    onTriggered: sensor.armed = true
                }
            }

            CornerSensor { x: 0; y: 0; action: root.hotCornerTL }
            CornerSensor { x: hcWin.width - hcWin.sz; y: 0; action: root.hotCornerTR }
            CornerSensor { x: 0; y: hcWin.height - hcWin.sz; action: root.hotCornerBL }
            CornerSensor { x: hcWin.width - hcWin.sz; y: hcWin.height - hcWin.sz; action: root.hotCornerBR }
        }
    }

    // ═════════════ 5. QUICK NOTE (Hot Corner & IPC) ═════════════
    property bool quickNoteOpen: false
    property string quickNoteText: ""
    property bool quickNoteLoaded: false

    function openQuickNote() { quickNoteOpen = true; }
    function closeQuickNote() { quickNoteOpen = false; }
    function toggleQuickNote() { quickNoteOpen = !quickNoteOpen; }

    FileView {
        id: quickNoteFile
        path: root.home + "/.config/macshell/quick-note.md"
        printErrors: false
        onLoaded: { root.quickNoteText = text(); root.quickNoteLoaded = true; }
        onLoadFailed: root.quickNoteLoaded = true
    }

    Timer {
        id: quickNoteSaveT
        interval: 450
        onTriggered: {
            Quickshell.execDetached(["sh", "-c", "mkdir -p \"$HOME/.config/macshell\" && printf '%s' \"$1\" > \"$HOME/.config/macshell/quick-note.md\"", "sh", root.quickNoteText]);
        }
    }

    Loader {
        active: root.quickNoteOpen
        sourceComponent: PanelWindow {
            id: qnWin
            anchors { bottom: true; right: true }
            margins { bottom: 96; right: 24 }
            implicitWidth: 340
            implicitHeight: 280
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "macquicknote"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            Rectangle {
                anchors.fill: parent
                radius: 16
                color: root.darkMode ? Qt.rgba(0.14, 0.14, 0.16, 0.94) : Qt.rgba(0.99, 0.98, 0.94, 0.96)
                border.width: 1
                border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12)
                clip: true

                Rectangle {
                    id: qnHead
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    height: 36
                    color: root.darkMode ? Qt.rgba(1, 0.80, 0.20, 0.16) : Qt.rgba(1, 0.80, 0.20, 0.26)

                    Text {
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                        text: I18n.tr("Quick Note")
                        color: root.darkMode ? "#FFD60A" : "#9A6700"
                        font.family: Fonts.forWeight(Font.DemiBold, root.fam)
                        font.weight: Font.DemiBold
                        font.pixelSize: 13
                    }

                    Row {
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 6
                        Rectangle {
                            width: 48; height: 22; radius: 6
                            color: clrMa.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: I18n.tr("Clear")
                                color: root.darkMode ? Qt.rgba(1, 1, 1, 0.7) : Qt.rgba(0, 0, 0, 0.65)
                                font.pixelSize: 11
                            }
                            MouseArea {
                                id: clrMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { qnEdit.text = ""; root.quickNoteText = ""; quickNoteSaveT.restart(); }
                            }
                        }
                        Rectangle {
                            width: 22; height: 22; radius: 11
                            color: xMa.containsMouse ? Qt.rgba(1, 0.37, 0.34, 0.9) : (root.darkMode ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10))
                            Text {
                                anchors.centerIn: parent
                                text: "\u00d7"
                                color: xMa.containsMouse ? "#FFFFFF" : (root.darkMode ? "#FFFFFF" : "#1D1D1F")
                                font.pixelSize: 13
                            }
                            MouseArea {
                                id: xMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.closeQuickNote()
                            }
                        }
                    }
                }

                ScrollView {
                    anchors { top: qnHead.bottom; bottom: parent.bottom; left: parent.left; right: parent.right; margins: 10 }
                    TextArea {
                        id: qnEdit
                        text: root.quickNoteText
                        wrapMode: TextEdit.Wrap
                        color: root.darkMode ? "#F5F5F7" : "#1D1D1F"
                        selectionColor: root.accent
                        font.family: root.fam
                        font.pixelSize: 13
                        placeholderText: I18n.tr("Write a quick note\u2026")
                        placeholderTextColor: root.darkMode ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(0, 0, 0, 0.35)
                        background: null
                        onTextChanged: {
                            if (text !== root.quickNoteText) {
                                root.quickNoteText = text;
                                quickNoteSaveT.restart();
                            }
                        }
                        Keys.onEscapePressed: root.closeQuickNote()
                        Component.onCompleted: forceActiveFocus()
                    }
                }
            }
        }
    }
}
