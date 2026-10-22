// WindowBar — the macOS window controls, on every window.
//
// Hyprland draws no titlebars, so MacShell draws them: the three lights (and, if you like, the app's icon and name)
// float at the top-left of whatever window is focused. Only the controls take clicks; the rest of the window is
// untouched. MacShell's own windows draw their own, so they are skipped.
//
// Settings → Windows: show it at all, always show the symbols, keep the colours until you hover, show the title.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "I18n.js" as I18n
import "Fonts.js" as Fonts

Scope {
    id: root
    property var hub: null
    readonly property var dock: hub ? hub.dock : null
    readonly property var bar: hub ? hub.bar : null
    readonly property string fam: dock ? dock.fontFamily : "Open Runde"
    readonly property bool darkMode: dock ? dock.darkMode : true

    readonly property bool enabled: bar ? bar.windowBar : true
    readonly property bool showTitle: bar ? bar.windowBarTitle : true
    readonly property bool alwaysSymbols: bar ? bar.tlAlwaysSymbols : false
    readonly property bool colorOnHover: bar ? bar.tlColorOnHover : false

    // the focused window, straight from the geometry feed the glass already uses
    readonly property var clients: hub ? (hub.glassClients || []) : []
    // which window has focus, from the same toplevel manager the menu bar uses
    readonly property var activeTl: ToplevelManager.activeToplevel
    readonly property string activeAddr: {
        if (!activeTl) return "";
        var ts = Hyprland.toplevels.values;
        for (var i = 0; i < ts.length; i++)
            if (ts[i].wayland === activeTl) return "0x" + String(ts[i].address).replace(/^0x/, "");
        return "";
    }
    readonly property var active: {
        for (var i = 0; i < clients.length; i++) {
            var c = clients[i];
            if (("0x" + String(c.address).replace(/^0x/, "")) !== activeAddr && String(c.address) !== activeAddr) continue;
            if (!c.mapped || c.hidden || c.fullscreen) return null;
            // our own windows have their lights already
            if (c.class === "org.quickshell" || c.class === "quickshell") return null;
            if (c.size && (c.size[0] < 220 || c.size[1] < 120)) return null;
            return c;
        }
        return null;
    }
    // Window positions come from the shell's geometry feed, which only runs when something asks for it (the glass
    // did; in Opaque nothing did, so the controls had nowhere to go)
    Binding { target: root.hub; property: "winBarWantsGeo"; value: root.enabled; when: root.hub !== null }
    function dispatch(d) { Hyprland.dispatch(d + "({ window = \"address:" + activeAddr + "\" })"); }
    function close() { Hyprland.dispatch('hl.dsp.window.close({ window = "address:' + activeAddr + '" })'); }
    function minimize() { Hyprland.dispatch('hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = "address:' + activeAddr + '" })'); }
    function zoom() { Hyprland.dispatch('hl.dsp.window.fullscreen_state({ internal = 2, client = 0, window = "address:' + activeAddr + '" })'); }

    Variants {
        model: root.enabled ? Quickshell.screens : []
        PanelWindow {
            id: w
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "macwinbar"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            // only the little control cluster takes clicks; everything else goes to the window underneath
            mask: Region { item: cluster }

            readonly property var c: root.active
            readonly property bool here: c && c.monitor !== undefined && modelData && Hyprland.monitorFor(modelData) && Hyprland.monitorFor(modelData).id === c.monitor
            readonly property real wx: c ? c.at[0] - modelData.x : 0
            readonly property real wy: c ? c.at[1] - modelData.y : 0

            Item {
                id: cluster
                visible: w.here && opacity > 0.01
                opacity: w.here ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                x: w.wx + 12
                y: w.wy + 10
                width: lights.width + (root.showTitle ? titleRow.width + 12 : 0)
                height: 20
                Behavior on x { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                // a soft plate so the lights stay readable on any window
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -5
                    radius: 11
                    color: root.darkMode ? Qt.rgba(0, 0, 0, 0.28) : Qt.rgba(1, 1, 1, 0.3)
                    opacity: hover.hovered ? 1 : 0.55
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                }
                HoverHandler { id: hover }

                Row {
                    id: lights
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Repeater {
                        model: [{ c: "#FF5F57", g: "×" }, { c: "#FEBC2E", g: "−" }, { c: "#28C840", g: "↗" }]
                        delegate: Rectangle {
                            id: light
                            required property var modelData
                            required property int index
                            width: 13; height: 13; radius: 6.5
                            color: (root.colorOnHover ? hover.hovered : true) ? modelData.c
                                 : (root.darkMode ? Qt.rgba(1, 1, 1, 0.26) : Qt.rgba(0, 0, 0, 0.22))
                            Behavior on color { ColorAnimation { duration: 160 } }
                            border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.14)
                            scale: lMa.pressed ? 0.86 : 1
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutQuint } }
                            TLGlyph {
                                anchors.fill: parent
                                kind: parent.modelData.g
                                Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            }
                            MouseArea {
                                id: lMa
                                anchors.fill: parent; anchors.margins: -3
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (light.index === 0) root.close();
                                    else if (light.index === 1) root.minimize();
                                    else root.zoom();
                                    if (root.bar) root.bar.playSound("tink", 0.4);
                                }
                            }
                        }
                    }
                }
                Row {
                    id: titleRow
                    visible: root.showTitle
                    anchors.left: lights.right; anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14; height: 14
                        sourceSize: Qt.size(32, 32)
                        asynchronous: true; smooth: true
                        source: {
                            var cl = w.c;
                            if (!cl) return "";
                            var e = cl.class ? DesktopEntries.heuristicLookup(cl.class) : null;
                            return e && e.icon ? Quickshell.iconPath(e.icon, true) : "";
                        }
                    }
                    MorphText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            var cl = w.c;
                            if (!cl) return "";
                            var e = cl.class ? DesktopEntries.heuristicLookup(cl.class) : null;
                            return e && e.name ? e.name : (cl.class || "");
                        }
                        duration: 260
                        color: root.darkMode ? "white" : "#1D1D1F"
                        font.family: Fonts.forWeight(font.weight, root.fam); font.pixelSize: 11; font.weight: Font.DemiBold
                    }
                }
            }
        }
    }
}
