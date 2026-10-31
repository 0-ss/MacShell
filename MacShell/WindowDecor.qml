// WindowDecor — a macOS window frame on every window: titlebar with the three traffic lights, centred title,
// hairline outline and rounded corners.
//
// Hyprland draws no titlebars, so MacShell draws them. One transparent layer surface per monitor holds a titlebar for each
// window on it. Only the titlebars take clicks (the surface's input mask is the union of their rectangles); everything else
// goes straight to the window underneath.
//
//   * The bar sits in the gap ABOVE the window, like hyprbars does. That needs a top gap of at least 28 px (see macshell.lua).
//     Where there is no room (a window right under the menu bar) the bar is laid over the first 28 px of the window instead.
//   * Lights: red closes, amber minimises, green goes full screen (Alt-click maximises). Hovering the group shows the glyphs;
//     lights of a window that is not focused are grey until you hover them.
//   * Drag the titlebar to move the window (a tiled window becomes floating first), double-click it to maximise / restore.
//   * Border and corners: Hyprland's own border is switched off per window and its corners are rounded to `radius`, then the
//     outline is drawn here so titlebar and window read as one rounded shape. The little wedges that rounding leaves at the
//     window's top corners are filled with the titlebar colour.
//   * MacShell's own windows (Settings, About ...) draw their own lights and are skipped, as are fullscreen windows,
//     windows hidden behind another floating window, and anything smaller than 220 x 120.
//
// Switch it on / off:   qs -c MacShell ipc call windecor toggle | on | off     (also Settings → Behavior)
// Settings are kept in ~/.config/macbar/windecor.json:  enabled, showTitle, radius, excludeClasses
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "Fonts.js" as Fonts

Scope {
    id: root
    property var hub: null
    readonly property var dock: hub ? hub.dock : null
    readonly property bool darkMode: dock ? dock.darkMode : true
    readonly property string fam: dock ? dock.fontFamily : "Open Runde"

    // ── settings ──
    property bool enabled: true
    property bool showTitle: true
    property int radius: 10                       // window corner radius (macOS: 10)
    property var excludeClasses: ["org.quickshell", "quickshell"]
    readonly property int barH: 28                // macOS titlebar height
    property bool ready: false

    FileView {
        id: store
        path: Quickshell.env("HOME") + "/.config/macbar/windecor.json"
        printErrors: false
        onLoaded: {
            try {
                var o = JSON.parse(text());
                if (o.enabled !== undefined) root.enabled = !!o.enabled;
                if (o.showTitle !== undefined) root.showTitle = !!o.showTitle;
                if (typeof o.radius === "number") root.radius = Math.max(0, Math.min(24, Math.round(o.radius)));
                if (Array.isArray(o.excludeClasses)) root.excludeClasses = o.excludeClasses.map(String);
            } catch (err) { }
            root.ready = true;
        }
        onLoadFailed: root.ready = true
    }
    Timer {
        id: saveT; interval: 400
        onTriggered: store.setText(JSON.stringify({ enabled: root.enabled, showTitle: root.showTitle, radius: root.radius,
                                                    excludeClasses: root.excludeClasses }, null, 2))
    }
    onEnabledChanged: { if (ready) saveT.restart(); if (!enabled) restoreProps(); recompute(); }
    onShowTitleChanged: if (ready) saveT.restart()

    // the window positions come from the shell's geometry feed, which only runs when something asks for it
    Binding { target: root.hub; property: "decorWantsGeo"; value: root.enabled; when: root.hub !== null }

    // ── palette (macOS window chrome) ──
    readonly property color barActive: darkMode ? "#383838" : "#ECECEC"
    readonly property color barInactive: darkMode ? "#2D2D2D" : "#F5F5F5"
    readonly property color barLine: darkMode ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(0, 0, 0, 0.13)
    readonly property color outlineOuter: darkMode ? Qt.rgba(0, 0, 0, 0.62) : Qt.rgba(0, 0, 0, 0.30)
    readonly property color outlineInner: darkMode ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(1, 1, 1, 0.55)
    readonly property var lights: [
        { c: "#FF5F57", b: "#E2463F", g: "×" },
        { c: "#FEBC2E", b: "#DEA123", g: "−" },
        { c: "#28C840", b: "#1AAB29", g: "↗" }
    ]

    // ── which windows get a bar ──
    readonly property var clients: hub ? (hub.glassClients || []) : []
    readonly property var mons: hub ? (hub.monData || []) : []
    property var barMap: ({})        // address -> descriptor, rebuilt on every geometry update
    property var barOrder: ({})      // monitor name -> [address]; only replaced when the SET changes (keeps the Repeaters stable)
    property string orderKey: ""
    property var applied: ({})       // addresses whose border / rounding we have set
    // while a titlebar is being dragged its position comes from the pointer, not from the (late) geometry feed
    property string dragAddr: ""
    property real dragX: 0
    property real dragY: 0

    onClientsChanged: recompute()
    onMonsChanged: recompute()
    onRadiusChanged: { restoreProps(); recompute(); }
    Component.onCompleted: recompute()

    function fullscreenOf(c) { return c.fullscreen === true || c.fullscreen === 2; }
    function addrOf(c) { return "0x" + String(c.address).replace(/^0x/, ""); }
    function sel(addr) { return 'window = "address:' + addr + '"'; }

    function recompute() {
        var map = {}, order = {}, key = [];
        if (enabled) {
            var cs = clients, ms = mons, i, j, c, m, monById = {}, fsWs = {}, cand = [];
            for (i = 0; i < ms.length; i++) monById[ms[i].id] = ms[i];
            for (i = 0; i < cs.length; i++) {
                c = cs[i];
                if (c.mapped && !c.hidden && c.workspace && fullscreenOf(c)) fsWs[c.workspace.id] = true;
            }
            for (i = 0; i < cs.length; i++) {
                c = cs[i];
                if (!c.mapped || c.hidden || !c.at || !c.size || !c.workspace) continue;
                if (c.size[0] < 220 || c.size[1] < 120) continue;
                if (excludeClasses.indexOf(String(c["class"] || "")) >= 0 || excludeClasses.indexOf(String(c.initialClass || "")) >= 0) continue;
                m = monById[c.monitor];
                if (!m) continue;
                var ws = c.workspace.id;
                var special = String(c.workspace.name || "").indexOf("special:") === 0;
                var shown = (m.activeWorkspace && m.activeWorkspace.id === ws) || (m.specialWorkspace && m.specialWorkspace.id !== 0 && m.specialWorkspace.id === ws);
                if (!shown || fsWs[ws]) continue;
                var fh = typeof c.focusHistoryID === "number" ? c.focusHistoryID : 99;
                var top = m.y + (m.reserved ? m.reserved[1] : 0);
                var ax = c.at[0], ay = c.at[1];
                if (dragAddr !== "" && addrOf(c) === dragAddr) { ax = dragX; ay = dragY; }
                var inset = (ay - barH) < top;          // no room above the window: lay the bar over its first 28 px
                cand.push({ c: c, m: m, inset: inset, z: (special ? 5000 : 0) + (c.floating ? 1000 + (500 - Math.min(fh, 499)) : 0),
                            x: ax, y: inset ? ay : ay - barH, w: c.size[0], h: c.size[1] + (inset ? 0 : barH) });
            }
            for (i = 0; i < cand.length; i++) {
                var a = cand[i], hidden = false;
                for (j = 0; j < cand.length && !hidden; j++) {
                    var b = cand[j];
                    if (b === a || b.m !== a.m || b.z <= a.z || !b.c.floating) continue;
                    // does b (with its own bar) cover the part of a that shows the titlebar?
                    var ox = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x);
                    var oy = Math.min(a.y + barH, b.y + b.h) - Math.max(a.y, b.y);
                    if (ox > 2 && oy > 2) hidden = true;
                }
                var addr = addrOf(a.c);
                var title = String(a.c.title || "");
                if (title === "") title = String(a.c["class"] || "");
                map[addr] = { addr: addr, mon: a.m.name, x: a.x - a.m.x, y: a.y - a.m.y, w: a.w, h: a.h, inset: a.inset,
                              shown: !hidden, active: a.c.focusHistoryID === 0, floating: !!a.c.floating, title: title,
                              bh: barH, atX: a.x, atY: a.inset ? a.y : a.y + barH, monX: a.m.x, monY: a.m.y, winW: a.c.size[0] };
                if (!order[a.m.name]) order[a.m.name] = [];
                order[a.m.name].push(addr);
                if (!applied[addr]) {
                    applied[addr] = true;
                    Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "border_size", value = "0", ' + sel(addr) + ' })');
                    Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "rounding", value = "' + radius + '", ' + sel(addr) + ' })');
                    // Hyprland reports where a window is GOING, then slides it there; a separate bar cannot follow a slide. No animation = no lag.
                    Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "no_anim", value = "1", ' + sel(addr) + ' })');
                }
            }
            for (var k in order) { order[k].sort(); key.push(k + ":" + order[k].join(",")); }
        }
        barMap = map;
        var ks = key.join("|");
        if (ks !== orderKey) { orderKey = ks; barOrder = order; }
    }

    // give the windows back their own border / corners (decoration switched off, or the radius changed)
    function restoreProps() {
        for (var addr in applied) {
            Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "border_size", value = "unset", ' + sel(addr) + ' })');
            Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "rounding", value = "unset", ' + sel(addr) + ' })');
            Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "no_anim", value = "0", ' + sel(addr) + ' })');
        }
        applied = ({});
    }

    // ── window actions ──
    function focusWin(addr) { Hyprland.dispatch('hl.dsp.focus({ ' + sel(addr) + ' })'); }
    function closeWin(addr) { Hyprland.dispatch('hl.dsp.window.close({ ' + sel(addr) + ' })'); }
    function minimizeWin(addr) { Hyprland.dispatch('hl.dsp.window.move({ workspace = "special:minimized", follow = false, ' + sel(addr) + ' })'); }
    function zoomWin(addr, alt) {
        if (alt) Hyprland.dispatch('hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle", ' + sel(addr) + ' })');
        else Hyprland.dispatch('hl.dsp.window.fullscreen_state({ internal = 2, client = 0, ' + sel(addr) + ' })');
    }
    function maximizeToggle(addr) { Hyprland.dispatch('hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle", ' + sel(addr) + ' })'); }
    function floatWin(addr) { Hyprland.dispatch('hl.dsp.window.float({ action = "enable", ' + sel(addr) + ' })'); }
    function moveWin(addr, x, y) { Hyprland.dispatch('hl.dsp.window.move({ x = ' + Math.round(x) + ', y = ' + Math.round(y) + ', "exact", ' + sel(addr) + ' })'); }

    // one layer surface per monitor
    Variants {
        model: root.enabled ? Quickshell.screens : []
        PanelWindow {
            id: w
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "macwindecor"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            readonly property var addrs: root.barOrder[modelData.name] || []

            // input mask: the union of the titlebars. 24 slots; windows past that still get a bar but cannot be clicked.
            readonly property var rects: {
                var r = [], bm = root.barMap;
                for (var i = 0; i < addrs.length; i++) {
                    var d = bm[addrs[i]];
                    if (d && d.shown) r.push(d);
                }
                return r;
            }
            component Slot: Region {
                required property int idx
                required property var rects
                readonly property var d: rects[idx]
                x: d ? Math.round(d.x) : 0
                y: d ? Math.round(d.y) : 0
                width: d ? Math.round(d.w) : 0
                height: d ? d.bh : 0
            }
            mask: Region {
                Slot { idx: 0; rects: w.rects }
                Slot { idx: 1; rects: w.rects }
                Slot { idx: 2; rects: w.rects }
                Slot { idx: 3; rects: w.rects }
                Slot { idx: 4; rects: w.rects }
                Slot { idx: 5; rects: w.rects }
                Slot { idx: 6; rects: w.rects }
                Slot { idx: 7; rects: w.rects }
                Slot { idx: 8; rects: w.rects }
                Slot { idx: 9; rects: w.rects }
                Slot { idx: 10; rects: w.rects }
                Slot { idx: 11; rects: w.rects }
                Slot { idx: 12; rects: w.rects }
                Slot { idx: 13; rects: w.rects }
                Slot { idx: 14; rects: w.rects }
                Slot { idx: 15; rects: w.rects }
                Slot { idx: 16; rects: w.rects }
                Slot { idx: 17; rects: w.rects }
                Slot { idx: 18; rects: w.rects }
                Slot { idx: 19; rects: w.rects }
                Slot { idx: 20; rects: w.rects }
                Slot { idx: 21; rects: w.rects }
                Slot { idx: 22; rects: w.rects }
                Slot { idx: 23; rects: w.rects }
            }

            Repeater {
                model: w.addrs
                delegate: Item {
                    id: deco
                    required property string modelData
                    readonly property var m: root.barMap[modelData]
                    readonly property bool active: m ? m.active : false
                    readonly property color barColor: active ? root.barActive : root.barInactive
                    readonly property int r: root.radius

                    visible: m !== undefined && m !== null && opacity > 0.01
                    opacity: m && m.shown ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    x: m ? m.x : 0
                    y: m ? m.y : 0
                    width: m ? m.w : 0
                    height: m ? m.h : 0

                    // wedges the window's own rounded top corners leave next to the bar
                    Canvas {
                        id: wedges
                        visible: !!m && !m.inset && deco.r > 0
                        x: 0; y: root.barH; width: parent.width; height: deco.r
                        renderTarget: Canvas.Image
                        property color fillColor: deco.barColor
                        onFillColorChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onVisibleChanged: requestPaint()
                        Connections { target: deco; function onRChanged() { wedges.requestPaint(); } }
                        onPaint: {
                            var c = getContext("2d"), rr = deco.r, W = width;
                            c.reset();
                            if (rr <= 0 || W <= 2 * rr) return;
                            c.fillStyle = fillColor;
                            c.beginPath();                      // left: the square minus the quarter disc the window keeps
                            c.moveTo(0, 0); c.lineTo(rr, 0); c.arc(rr, rr, rr, -Math.PI / 2, Math.PI, true); c.closePath(); c.fill();
                            c.beginPath();                      // right
                            c.moveTo(W, 0); c.lineTo(W - rr, 0); c.arc(W - rr, rr, rr, -Math.PI / 2, 0, false); c.closePath(); c.fill();
                        }
                    }

                    // titlebar body: rounded top corners only (a taller rounded rectangle, clipped)
                    Item {
                        id: bar
                        x: 0; y: 0; width: parent.width; height: root.barH
                        clip: true
                        Rectangle {
                            width: parent.width; height: root.barH + deco.r + 2
                            radius: deco.r
                            color: deco.barColor
                            Behavior on color { ColorAnimation { duration: 160 } }
                        }
                        Rectangle {                                  // the line under the titlebar
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: 1
                            color: root.barLine
                        }
                    }

                    // title, centred between the lights and the right edge
                    Text {
                        visible: root.showTitle
                        x: 80; y: 0
                        width: Math.max(0, parent.width - 160); height: root.barH
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: m ? m.title : ""
                        color: deco.active ? (root.darkMode ? Qt.rgba(1, 1, 1, 0.85) : Qt.rgba(0, 0, 0, 0.85))
                                           : (root.darkMode ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.42))
                        font.family: Fonts.forWeight(Font.DemiBold, root.fam)
                        font.weight: Font.DemiBold
                        font.pixelSize: 13
                    }

                    // drag to move, double-click to maximise
                    MouseArea {
                        id: dragMa
                        x: 0; y: 0; width: parent.width; height: root.barH
                        acceptedButtons: Qt.LeftButton
                        property real px: 0
                        property real py: 0
                        property real offX: 0
                        property real offY: 0
                        property bool moving: false
                        function surf(mouse) { return mapToItem(w.contentItem, mouse.x, mouse.y); }
                        onPressed: mouse => {
                            if (!deco.m) return;
                            var p = surf(mouse);
                            px = p.x; py = p.y;
                            offX = Math.min(p.x - (deco.m.atX - deco.m.monX), Math.max(40, deco.m.winW - 40));
                            offY = p.y - (deco.m.atY - deco.m.monY);
                            moving = false;
                            root.focusWin(deco.m.addr);
                        }
                        onPositionChanged: mouse => {
                            if (!pressed || !deco.m) return;
                            var p = surf(mouse);
                            if (!moving) {
                                if (Math.abs(p.x - px) + Math.abs(p.y - py) < 5) return;
                                moving = true;
                                if (!deco.m.floating) root.floatWin(deco.m.addr);
                            }
                            var nx = deco.m.monX + p.x - offX, ny = deco.m.monY + p.y - offY;
                            root.dragX = nx; root.dragY = ny; root.dragAddr = deco.m.addr;
                            root.recompute();
                            root.moveWin(deco.m.addr, nx, ny);
                        }
                        onReleased: { moving = false; root.dragAddr = ""; root.recompute(); }
                        onCanceled: { moving = false; root.dragAddr = ""; root.recompute(); }
                        onDoubleClicked: if (deco.m) root.maximizeToggle(deco.m.addr)
                    }

                    // the traffic lights: 12 px, 8 px apart, 13 px from the left edge, centred in the bar
                    Item {
                        id: lightsBox
                        x: 13 - 6; y: 0
                        width: 3 * 12 + 2 * 8 + 12; height: root.barH
                        HoverHandler { id: lightsHover }
                        Row {
                            x: 6; anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Repeater {
                                model: root.lights
                                delegate: Rectangle {
                                    id: light
                                    required property var modelData
                                    required property int index
                                    width: 12; height: 12; radius: 6
                                    readonly property bool coloured: deco.active || lightsHover.hovered
                                    color: coloured ? (lMa.pressed ? Qt.darker(modelData.c, 1.18) : modelData.c)
                                                    : (root.darkMode ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.15))
                                    border.width: 1
                                    border.color: coloured ? modelData.b : (root.darkMode ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.10))
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    TLGlyph {
                                        anchors.fill: parent
                                        kind: light.modelData.g
                                        opacity: lightsHover.hovered ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 100 } }
                                    }
                                    MouseArea {
                                        id: lMa
                                        anchors.fill: parent; anchors.margins: -3
                                        acceptedButtons: Qt.LeftButton
                                        onClicked: mouse => {
                                            if (!deco.m) return;
                                            var a = deco.m.addr;
                                            if (light.index === 0) root.closeWin(a);
                                            else if (light.index === 1) root.minimizeWin(a);
                                            else root.zoomWin(a, (mouse.modifiers & Qt.AltModifier) !== 0);
                                            if (root.hub && root.hub.bar && root.hub.bar.playSound) root.hub.bar.playSound("tink", 0.4);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // outline around titlebar + window (click-through: it is outside the input mask)
                    Rectangle {
                        anchors.fill: parent
                        radius: deco.r
                        color: "transparent"
                        border.width: 1
                        border.color: deco.active ? root.outlineOuter : Qt.rgba(root.outlineOuter.r, root.outlineOuter.g, root.outlineOuter.b, root.outlineOuter.a * 0.6)
                    }
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 1
                        radius: Math.max(0, deco.r - 1)
                        color: "transparent"
                        border.width: 1
                        border.color: root.outlineInner
                        opacity: deco.active ? 1 : 0.5
                    }
                }
            }
        }
    }
}
