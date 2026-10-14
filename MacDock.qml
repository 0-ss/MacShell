// macdock v2 — a macOS-style dock for Hyprland, built on Quickshell.
//
// Part of the combined macbar + macdock shell (see shell.qml). Keep this file, MacBar.qml, shell.qml and
// liquidglass.frag together in ~/.config/quickshell/macbar/ and run:  qs -c macbar
// Pins are saved to ~/.config/macdock/pinned.json once you use "Keep in Dock".
//
// Settings are saved to ~/.config/macdock/settings.json (right-click the dock → Dock Preferences…).
// The preferences window is frameless; make it float in Hyprland, e.g. (hyprland.conf syntax):
//   windowrule = float, title:^(Dock Preferences)$
//   windowrule = center, title:^(Dock Preferences)$
//
// Dock style (Dock Preferences → Appearance):
//   Normal Blur         – the original translucent tint; blur comes from the Hyprland layer rule below.
//   Apple Liquid Glass  – real-time refraction shader (liquidglass.frag, next to this file). It is compiled
//                         with `qsb` (package qt6-shadertools) on first use and cached in ~/.config/macdock/.
//                         The backdrop it refracts is the wallpaper + the live windows behind the Dock;
//                         set "wallpaperPath" in settings.json if the wallpaper isn't auto-detected.
//
// Hyprland (Lua) layer rule for the glass:
//   hl.layer_rule({ name = "macdock", match = { namespace = "macdock" },
//                   blur = true, ignore_alpha = 0.2, no_anim = true })

import QtQuick
import QtQuick.Effects
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    // shared helpers from shell.qml (window geometry poller, wallpaper lookup)
    property var hub: null
    property bool dockEnabled: true      // false = no Dock at all (settings window stays available)
    readonly property var bar: hub ? hub.bar : null
    readonly property bool captureCut: hub ? hub.captureCut : false
    readonly property bool glassHold: hub ? hub.glassHold : false          // windows opening / closing: the glass's live captures pause, source stays attached
    readonly property bool captureHold: hub ? hub.captureHold : false     // windows opening / closing: the dock PREVIEW capture stops (source released 0.5 s later); the glass is not affected
    // appearance values shared by Dock and Menu Bar
    function setLook(k, v) { root[k] = v; if (bar) bar[k] = v; }

    // ───────────── CONFIG ───────────── Lachowski
    property string monitor: ""          // "" = every monitor, or e.g. "DP-1"
    property int iconSize: 52
    property real magnification: 1.7     // peak icon scale
    property int spacing: 6
    property int hPad: 10
    property int topPad: 8
    property int bottomPad: 9            // room under icons (running dots live here)
    property int cornerRadius: 18
    property int margin: 6
    property bool darkMode: true
    property string dockStyle: "blur"   // "blur" = Normal Blur, "liquid" = Apple Liquid Glass
    // Liquid Glass tuning (settings.json): rim = edge highlight, grain = noise, liquid = refraction depth
    property real glassRim: 0.45
    property real glassGrain: 0.03
    property real glassLiquid: 1.0
    readonly property bool glassRT: bar ? bar.glassRealtime : true     // real-time glass (Menu Bar settings)
    property real glassBlur: 5            // Liquid Glass backdrop blur radius, px (settings slider)
    property bool glassDebug: false       // settings.json only: draw the raw Liquid Glass backdrop texture
    property string wallpaperPath: ""    // optional override for the wallpaper the Liquid Glass refracts
    property real glassOpacity: 0.42     // 0 = fully clear; below the layerrule's ignore_alpha (0.2) the blur turns off
    // "smart"  = hide while a non-floating window is open on that monitor's workspace
    // "always" = always auto-hide, "never" = always visible and reserves space
    property string hideMode: "smart"
    property bool showTrash: true
    property string fontFamily: "Inter"  // falls back to the system font if missing
    property bool magnificationEnabled: true
    property bool showLabels: true       // hover tooltips
    property bool showIndicators: true   // dots under running apps
    property bool bounceOnLaunch: true
    property bool showThumbs: true       // open windows get a live preview cell next to the Trash
    property bool windowCapture: true    // live window capture for those previews (off: the cells show the app icon, nothing is captured). Liquid Glass is not affected
    property int hideDelay: 450          // ms before the dock hides after the pointer leaves
    readonly property var accentChoices: [
        { name: "Blue",     c: "#0a84ff" }, { name: "Purple", c: "#bf5af2" },
        { name: "Pink",     c: "#ff375f" }, { name: "Red",    c: "#ff453a" },
        { name: "Orange",   c: "#ff9f0a" }, { name: "Yellow", c: "#ffd60a" },
        { name: "Green",    c: "#30d158" }, { name: "Graphite", c: "#8e8e93" }
    ]
    property color accent: "#0A84FF"     // menu highlight (macOS blue)
    readonly property var defaultPinned: [
        "org.gnome.Nautilus", "org.kde.dolphin", "thunar",
        "firefox", "zen", "chromium", "google-chrome",
        "kitty", "com.mitchellh.ghostty", "Alacritty", "foot",
        "code", "discord", "spotify", "steam", "obsidian"
    ]   // used until you change pins from the dock; unknown ids are skipped
    property var pinned: defaultPinned
    // ──────────────────────────────────

    // ═════════════════════════════════════════════════════════════════
    //  SETTINGS UI  —  macOS "System Settings" look
    //  (inline components; they receive the palette through `t`)
    // ═════════════════════════════════════════════════════════════════

    // Rounded, inset group box (the white/grey "card" in System Settings)
    component SCard: Rectangle {
        id: card
        required property var t
        default property alias content: col.data
        width: parent ? parent.width : 0
        height: col.implicitHeight
        radius: 10
        color: t.card
        border.width: 1
        border.color: t.cardBorder
        Column { id: col; width: parent.width }
    }

    // One row inside a card: title (+ subtitle) on the left, control on the right
    component SRow: Item {
        id: r
        required property var t
        property string title: ""
        property string subtitle: ""
        property url iconSource: ""
        default property alias control: slot.data
        width: parent ? parent.width : 0
        height: Math.max(44, textCol.height + 22, slot.height + 20)

        Rectangle {
            visible: r.y > 0.5
            x: 14
            width: parent.width - 14
            height: 1
            color: r.t.sep
        }
        Image {
            id: ic
            visible: r.iconSource != ""
            source: r.iconSource
            x: 14
            width: 28; height: 28
            anchors.verticalCenter: parent.verticalCenter
            sourceSize: Qt.size(64, 64)
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }
        Column {
            id: textCol
            x: ic.visible ? 54 : 14
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, r.width - x - slot.width - 28)
            spacing: 2
            Text {
                width: parent.width
                text: r.title
                elide: Text.ElideRight
                color: r.t.text
                font.family: r.t.fam
                font.pixelSize: 13
            }
            Text {
                visible: r.subtitle !== ""
                width: parent.width
                text: r.subtitle
                wrapMode: Text.WordWrap
                color: r.t.text2
                font.family: r.t.fam
                font.pixelSize: 12
            }
        }
        Item {
            id: slot
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width
            height: childrenRect.height
        }
    }

    // Section header / footnote text
    component SLabel: Text {
        required property var t
        property bool header: false
        width: parent ? parent.width : 0
        leftPadding: 4
        topPadding: header ? 8 : 0
        wrapMode: Text.WordWrap
        color: t.text2
        font.family: t.fam
        font.pixelSize: header ? 12 : 12
        font.weight: header ? Font.DemiBold : Font.Normal
    }

    // macOS toggle switch
    component SSwitch: Item {
        id: sw
        required property var t
        property bool checked: false
        signal toggled(bool value)
        width: 38; height: 22
        Rectangle {
            anchors.fill: parent
            radius: 11
            color: sw.checked ? sw.t.accent : sw.t.switchOff
            Behavior on color { ColorAnimation { duration: 160 } }
        }
        Rectangle {
            x: sw.checked ? 18 : 2
            y: 2
            width: 18; height: 18; radius: 9
            color: "white"
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.10)
            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }
        MouseArea {
            anchors.fill: parent
            onClicked: sw.toggled(!sw.checked)
        }
    }

    // macOS slider (thin track, accent fill, white round knob)
    component SSlider: Item {
        id: s
        required property var t
        property real from: 0
        property real to: 1
        property real value: 0
        property real stepSize: 0
        property string leftLabel: ""
        property string rightLabel: ""
        signal moved(real v)
        readonly property real pos: to > from ? Math.max(0, Math.min(1, (value - from) / (to - from))) : 0
        width: 230
        height: leftLabel !== "" || rightLabel !== "" ? 40 : 22
        opacity: enabled ? 1 : 0.4

        Rectangle {
            id: track
            y: 11 - 2
            width: parent.width
            height: 4
            radius: 2
            color: s.t.track
        }
        Rectangle {
            y: track.y
            width: knob.x + knob.width / 2
            height: 4
            radius: 2
            color: s.t.accent
        }
        Rectangle {   // knob shadow
            x: knob.x - 1; y: knob.y + 1
            width: 22; height: 22; radius: 11
            color: Qt.rgba(0, 0, 0, 0.14)
        }
        Rectangle {
            id: knob
            x: s.pos * (s.width - 20)
            y: 1
            width: 20; height: 20; radius: 10
            color: "white"
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.16)
        }
        Text {
            visible: s.leftLabel !== ""
            y: 25
            text: s.leftLabel
            color: s.t.text2
            font.family: s.t.fam
            font.pixelSize: 11
        }
        Text {
            visible: s.rightLabel !== ""
            y: 25
            x: s.width - implicitWidth
            text: s.rightLabel
            color: s.t.text2
            font.family: s.t.fam
            font.pixelSize: 11
        }
        MouseArea {
            anchors.fill: parent
            preventStealing: true
            function setFrom(mx) {
                var p = Math.max(0, Math.min(1, (mx - 10) / (s.width - 20)));
                var v = s.from + p * (s.to - s.from);
                if (s.stepSize > 0) v = Math.round(v / s.stepSize) * s.stepSize;
                v = Math.round(v * 1000) / 1000;
                s.moved(v);
            }
            onPressed: mouse => setFrom(mouse.x)
            onPositionChanged: mouse => { if (pressed) setFrom(mouse.x); }
        }
    }

    // macOS segmented control
    component SSegmented: Item {
        id: g
        required property var t
        property var model: []
        property int current: 0
        property real segWidth: 72
        signal picked(int index)
        width: model.length * segWidth + 4
        height: 26
        Rectangle { anchors.fill: parent; radius: 7; color: g.t.ctrl }
        Rectangle {
            visible: g.current >= 0
            y: 2
            x: 2 + g.current * g.segWidth
            width: g.segWidth
            height: parent.height - 4
            radius: 5
            color: g.t.ctrlSel
            border.width: g.t.dark ? 0 : 1
            border.color: Qt.rgba(0, 0, 0, 0.10)
            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }
        Row {
            x: 2; y: 2
            Repeater {
                model: g.model
                delegate: Item {
                    required property var modelData
                    required property int index
                    width: g.segWidth
                    height: g.height - 4
                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData
                        color: g.t.text
                        font.family: g.t.fam
                        font.pixelSize: 12
                        font.weight: parent.index === g.current ? Font.Medium : Font.Normal
                    }
                    MouseArea { anchors.fill: parent; onClicked: g.picked(parent.index) }
                }
            }
        }
    }

    // macOS push button
    component SButton: Rectangle {
        id: b
        required property var t
        property string text: ""
        property bool destructive: false
        signal clicked()
        width: lbl.implicitWidth + 26
        height: 24
        radius: 6
        color: ma.pressed ? t.buttonPressed : t.button
        border.width: 1
        border.color: t.buttonBorder
        Text {
            id: lbl
            anchors.centerIn: parent
            text: b.text
            color: b.destructive ? b.t.danger : b.t.text
            font.family: b.t.fam
            font.pixelSize: 13
        }
        MouseArea { id: ma; anchors.fill: parent; onClicked: b.clicked() }
    }

    // Light / Dark appearance thumbnail
    component SThemeTile: Item {
        id: tile
        required property var t
        property bool dark: false
        property bool selected: false
        property string label: ""
        signal clicked()
        width: 84; height: 78
        Rectangle {
            width: 84; height: 56
            radius: 8
            color: tile.dark ? "#141416" : "#D9DDE6"
            border.width: tile.selected ? 3 : 1
            border.color: tile.selected ? tile.t.accent : tile.t.sep
            Rectangle {   // mini window
                x: 14; y: 9
                width: 56; height: 32
                radius: 4
                color: tile.dark ? "#2C2C2E" : "#FFFFFF"
                Rectangle { x: 0; y: 0; width: 15; height: parent.height; radius: 4; color: tile.dark ? "#3A3A3C" : "#E9E9EE" }
                Rectangle { x: 20; y: 7;  width: 28; height: 3; radius: 1.5; color: tile.dark ? "#5A5A5E" : "#C8C8CE" }
                Rectangle { x: 20; y: 14; width: 20; height: 3; radius: 1.5; color: tile.dark ? "#48484A" : "#DADADF" }
                Rectangle { x: 20; y: 21; width: 24; height: 3; radius: 1.5; color: tile.dark ? "#48484A" : "#DADADF" }
            }
            Rectangle {   // mini dock
                x: 26; y: 46
                width: 32; height: 6
                radius: 3
                color: tile.dark ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.75)
            }
        }
        Text {
            y: 60
            anchors.horizontalCenter: parent.horizontalCenter
            text: tile.label
            color: tile.t.text
            font.family: tile.t.fam
            font.pixelSize: 12
        }
        MouseArea { anchors.fill: parent; onClicked: tile.clicked() }
    }

    // Colored rounded-square sidebar icon with a tiny drawn glyph
    component SGlyph: Rectangle {
        id: gl
        property string kind: ""
        property color c1: "#4FA8FF"
        property color c2: "#0A6CFF"
        width: 24; height: 24; radius: 6
        gradient: Gradient {
            GradientStop { position: 0.0; color: gl.c1 }
            GradientStop { position: 1.0; color: gl.c2 }
        }
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.14)

        Item {
            anchors.centerIn: parent
            width: 16; height: 16

            // dock
            Item {
                visible: gl.kind === "dock"; anchors.fill: parent
                Rectangle { x: 1; y: 11; width: 14; height: 4; radius: 2; color: "white" }
                Rectangle { x: 2;    y: 4.5; width: 3.4; height: 3.4; radius: 1; color: "white" }
                Rectangle { x: 6.3;  y: 4.5; width: 3.4; height: 3.4; radius: 1; color: "white" }
                Rectangle { x: 10.6; y: 4.5; width: 3.4; height: 3.4; radius: 1; color: "white" }
            }
            // appearance (half-filled circle)
            Item {
                visible: gl.kind === "appearance"; anchors.fill: parent
                Rectangle {
                    x: 1.5; y: 1.5; width: 13; height: 13; radius: 6.5
                    color: "transparent"; border.width: 2; border.color: "white"
                }
                Item {
                    x: 8; y: 1.5; width: 6.5; height: 13; clip: true
                    Rectangle { x: -6.5; width: 13; height: 13; radius: 6.5; color: "white" }
                }
            }
            // behavior (two toggles)
            Item {
                visible: gl.kind === "behavior"; anchors.fill: parent
                Rectangle { x: 1; y: 2; width: 14; height: 5.5; radius: 2.75; color: "white" }
                Rectangle { x: 10.2; y: 3.2; width: 3.1; height: 3.1; radius: 1.55; color: gl.c2 }
                Rectangle {
                    x: 1; y: 9.5; width: 14; height: 5.5; radius: 2.75
                    color: "transparent"; border.width: 1; border.color: "white"
                }
                Rectangle { x: 2.7; y: 10.7; width: 3.1; height: 3.1; radius: 1.55; color: "white" }
            }
            // applications (2×2 grid)
            Item {
                visible: gl.kind === "apps"; anchors.fill: parent
                Rectangle { x: 1.5; y: 1.5; width: 5.6; height: 5.6; radius: 1.6; color: "white" }
                Rectangle { x: 8.9; y: 1.5; width: 5.6; height: 5.6; radius: 1.6; color: "white" }
                Rectangle { x: 1.5; y: 8.9; width: 5.6; height: 5.6; radius: 1.6; color: "white" }
                Rectangle { x: 8.9; y: 8.9; width: 5.6; height: 5.6; radius: 1.6; color: "white" }
            }
            // menu bar
            Item {
                visible: gl.kind === "menubar"; anchors.fill: parent
                Rectangle { x: 1; y: 2; width: 14; height: 4.5; radius: 1.5; color: "white" }
                Rectangle { x: 2.5; y: 3.4; width: 4; height: 1.6; radius: 0.8; color: gl.c2 }
                Rectangle {
                    x: 1; y: 8.5; width: 14; height: 6.5; radius: 2
                    color: "transparent"; border.width: 1; border.color: "white"
                }
            }
            // about
            Item {
                visible: gl.kind === "about"; anchors.fill: parent
                Rectangle {
                    x: 1; y: 1; width: 14; height: 14; radius: 7
                    color: "transparent"; border.width: 2; border.color: "white"
                }
                Text {
                    anchors.centerIn: parent
                    text: "i"
                    color: "white"
                    font.pixelSize: 10
                    font.bold: true
                }
            }
        }
    }

    // ─────────────────────────── THE WINDOW ───────────────────────────
    Window {
        id: prefsWindow
        title: "macshell Settings"
        width: 820
        height: 600
        minimumWidth: 700
        minimumHeight: 500
        visible: false
        color: "transparent"
        flags: Qt.Window | Qt.FramelessWindowHint

        // ── navigation state ──
        property int cur: 0
        property var backStack: []
        property var fwdStack: []
        property string query: ""

        readonly property var panes: [
            { id: "general",    name: "General",      glyph: "behavior",   c1: "#8E8E93", c2: "#636366",
              keys: "enable disable dock menu bar panel show hide off on" },
            { id: "dock",       name: "Dock",         glyph: "dock",       c1: "#4FA8FF", c2: "#0A6CFF",
              keys: "size icon magnification zoom spacing margin distance edge" },
            { id: "menubar",    name: "Menu Bar",     glyph: "menubar",    c1: "#7D7AFF", c2: "#4B48D6",
              keys: "panel bar height clock date seconds 24 hour battery tray search spotlight week monday style liquid bluetooth widget" },
            { id: "appearance", name: "Appearance",   glyph: "appearance", c1: "#636366", c2: "#1C1C1E",
              keys: "theme dark light mode accent color glass liquid apple style translucency blur corner radius font" },
            { id: "behavior",   name: "Dock Behavior", glyph: "behavior",  c1: "#4CD964", c2: "#26A844",
              keys: "hide auto labels tooltip indicators bounce animate trash display monitor delay window preview thumbnail" },
            { id: "apps",       name: "Applications", glyph: "apps",       c1: "#FFB340", c2: "#FF9500",
              keys: "pinned apps keep remove reset" },
            { id: "about",      name: "About",        glyph: "about",      c1: "#A7A7AD", c2: "#7C7C82",
              keys: "version reset config folder macdock macbar macshell" }
        ]

        readonly property var filtered: {
            var q = query.trim().toLowerCase();
            var out = [];
            for (var i = 0; i < panes.length; i++) {
                var hay = (panes[i].name + " " + panes[i].keys).toLowerCase();
                if (q === "" || hay.indexOf(q) >= 0) out.push(i);
            }
            return out;
        }

        function go(i) {
            if (i === cur) return;
            backStack = backStack.concat([cur]);
            fwdStack = [];
            cur = i;
        }
        function back() {
            if (backStack.length === 0) return;
            var b = backStack.slice();
            var p = b.pop();
            fwdStack = fwdStack.concat([cur]);
            backStack = b;
            cur = p;
        }
        function forward() {
            if (fwdStack.length === 0) return;
            var f = fwdStack.slice();
            var p = f.pop();
            backStack = backStack.concat([cur]);
            fwdStack = f;
            cur = p;
        }
        onCurChanged: flick.contentY = 0

        Shortcut { sequences: ["Escape", "Ctrl+W"]; onActivated: prefsWindow.visible = false }

        // ── palette ──
        QtObject {
            id: pal
            readonly property bool dark: root.darkMode
            readonly property string fam: root.fontFamily
            readonly property color accent: root.accent
            readonly property color content: dark ? "#1E1E1E" : "#F5F5F7"
            readonly property color sidebar: dark ? "#292929" : "#E9E9EC"
            readonly property color card: dark ? "#2B2B2D" : "#FFFFFF"
            readonly property color cardBorder: dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.07)
            readonly property color windowBorder: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.22)
            readonly property color sep: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.09)
            readonly property color text: dark ? "#F5F5F7" : "#1D1D1F"
            readonly property color text2: dark ? Qt.rgba(1, 1, 1, 0.56) : Qt.rgba(0, 0, 0, 0.52)
            readonly property color text3: dark ? Qt.rgba(1, 1, 1, 0.32) : Qt.rgba(0, 0, 0, 0.30)
            readonly property color track: dark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.13)
            readonly property color switchOff: dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.14)
            readonly property color ctrl: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06)
            readonly property color ctrlSel: dark ? "#636366" : "#FFFFFF"
            readonly property color button: dark ? Qt.rgba(1, 1, 1, 0.13) : "#FFFFFF"
            readonly property color buttonPressed: dark ? Qt.rgba(1, 1, 1, 0.24) : "#E4E4E7"
            readonly property color buttonBorder: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.14)
            readonly property color field: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.06)
            readonly property color hover: dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)
            readonly property color selInactive: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)
            readonly property color lightOff: dark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.15)
            readonly property color danger: "#FF453A"
        }

        NumberAnimation { id: fadeIn; target: paneLoader; property: "opacity"; from: 0; to: 1; duration: 160 }

        // ── frame ──
        Rectangle {
            id: frame
            anchors.fill: parent
            radius: 12
            color: pal.content
            border.width: 1
            border.color: pal.windowBorder

            // Native Wayland resize handles for this frameless window.
            MouseArea { x: 12; y: 0; width: parent.width - 24; height: 6; z: 1000; cursorShape: Qt.SizeVerCursor; onPressed: prefsWindow.startSystemResize(Qt.TopEdge) }
            MouseArea { x: 12; y: parent.height - 6; width: parent.width - 24; height: 6; z: 1000; cursorShape: Qt.SizeVerCursor; onPressed: prefsWindow.startSystemResize(Qt.BottomEdge) }
            MouseArea { x: 0; y: 12; width: 6; height: parent.height - 24; z: 1000; cursorShape: Qt.SizeHorCursor; onPressed: prefsWindow.startSystemResize(Qt.LeftEdge) }
            MouseArea { x: parent.width - 6; y: 12; width: 6; height: parent.height - 24; z: 1000; cursorShape: Qt.SizeHorCursor; onPressed: prefsWindow.startSystemResize(Qt.RightEdge) }
            MouseArea { x: 0; y: 0; width: 12; height: 12; z: 1001; cursorShape: Qt.SizeFDiagCursor; onPressed: prefsWindow.startSystemResize(Qt.TopEdge | Qt.LeftEdge) }
            MouseArea { x: parent.width - 12; y: 0; width: 12; height: 12; z: 1001; cursorShape: Qt.SizeBDiagCursor; onPressed: prefsWindow.startSystemResize(Qt.TopEdge | Qt.RightEdge) }
            MouseArea { x: 0; y: parent.height - 12; width: 12; height: 12; z: 1001; cursorShape: Qt.SizeBDiagCursor; onPressed: prefsWindow.startSystemResize(Qt.BottomEdge | Qt.LeftEdge) }
            MouseArea { x: parent.width - 12; y: parent.height - 12; width: 12; height: 12; z: 1001; cursorShape: Qt.SizeFDiagCursor; onPressed: prefsWindow.startSystemResize(Qt.BottomEdge | Qt.RightEdge) }

            // drag the window by its top strip
            Item {
                width: parent.width
                height: 52
                DragHandler {
                    target: null
                    onActiveChanged: if (active) prefsWindow.startSystemMove()
                }
            }

            // ───────── sidebar ─────────
            Rectangle {
                id: sidebar
                x: 1; y: 1
                width: 232
                height: parent.height - 2
                radius: 11
                color: pal.sidebar
                Rectangle { anchors.right: parent.right; width: 12; height: parent.height; color: parent.color }
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: pal.sep }

                // traffic lights
                Item {
                    id: lights
                    x: 17; y: 16
                    width: 58; height: 14
                    Row {
                        spacing: 8
                        Repeater {
                            model: [
                                { c: "#FF5F57", g: "\u00D7", on: true },
                                { c: "#FEBC2E", g: "\u2212", on: true },
                                { c: "#28C840", g: "↗", on: true }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                width: 14; height: 14; radius: 7
                                color: (modelData.on && (prefsWindow.active || lightsMa.containsMouse))
                                       ? modelData.c : pal.lightOff
                                border.width: 1
                                border.color: Qt.rgba(0, 0, 0, 0.14)
                                Text {
                                    anchors.centerIn: parent
                                    visible: lightsMa.containsMouse && parent.modelData.on
                                    text: parent.modelData.g
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: Qt.rgba(0, 0, 0, 0.55)
                                }
                            }
                        }
                    }
                    MouseArea {
                        id: lightsMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: mouse => {
                            if (mouse.x < 22) prefsWindow.visible = false;
                            else if (mouse.x < 44) prefsWindow.showMinimized();
                            else if (mouse.x < 58) {
                                if (prefsWindow.visibility === Window.FullScreen) prefsWindow.showNormal();
                                else prefsWindow.showFullScreen();
                            }
                        }
                    }
                }

                // search field
                Rectangle {
                    id: search
                    x: 12; y: 50
                    width: parent.width - 24
                    height: 28
                    radius: 7
                    color: pal.field

                    Rectangle {   // focus ring
                        anchors.fill: parent
                        anchors.margins: -2
                        radius: 9
                        color: "transparent"
                        border.width: 3
                        border.color: Qt.rgba(pal.accent.r, pal.accent.g, pal.accent.b, 0.5)
                        visible: searchInput.activeFocus
                    }
                    Item {   // magnifier
                        x: 9
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14; height: 14
                        Rectangle {
                            width: 9; height: 9; radius: 4.5
                            color: "transparent"
                            border.width: 2
                            border.color: pal.text3
                        }
                        Rectangle {
                            x: 8; y: 9
                            width: 5; height: 1.6; radius: 0.8
                            color: pal.text3
                            rotation: 45
                            transformOrigin: Item.Left
                        }
                    }
                    TextInput {
                        id: searchInput
                        x: 30
                        width: parent.width - 54
                        anchors.verticalCenter: parent.verticalCenter
                        clip: true
                        selectByMouse: true
                        color: pal.text
                        selectionColor: pal.accent
                        font.family: pal.fam
                        font.pixelSize: 13
                        onTextChanged: prefsWindow.query = text
                    }
                    Text {
                        x: 30
                        anchors.verticalCenter: parent.verticalCenter
                        visible: searchInput.text === ""
                        text: "Search"
                        color: pal.text3
                        font.family: pal.fam
                        font.pixelSize: 13
                    }
                    Rectangle {   // clear button
                        visible: searchInput.text !== ""
                        anchors.right: parent.right
                        anchors.rightMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14; height: 14; radius: 7
                        color: pal.text3
                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -0.5
                            text: "\u00D7"
                            color: pal.sidebar
                            font.pixelSize: 12
                            font.bold: true
                        }
                        MouseArea { anchors.fill: parent; onClicked: searchInput.text = "" }
                    }
                }

                // pane list
                Column {
                    x: 10; y: 92
                    width: parent.width - 20
                    spacing: 2

                    Repeater {
                        model: prefsWindow.filtered
                        delegate: Rectangle {
                            id: navRow
                            required property int modelData
                            readonly property var p: prefsWindow.panes[modelData]
                            readonly property bool sel: prefsWindow.cur === modelData
                            width: parent.width
                            height: 34
                            radius: 8
                            color: sel ? (prefsWindow.active ? pal.accent : pal.selInactive)
                                       : (navMa.containsMouse ? pal.hover : "transparent")

                            SGlyph {
                                x: 8
                                anchors.verticalCenter: parent.verticalCenter
                                kind: navRow.p.glyph
                                c1: navRow.p.c1
                                c2: navRow.p.c2
                            }
                            Text {
                                x: 42
                                anchors.verticalCenter: parent.verticalCenter
                                text: navRow.p.name
                                color: (navRow.sel && prefsWindow.active) ? "white" : pal.text
                                font.family: pal.fam
                                font.pixelSize: 14
                            }
                            MouseArea {
                                id: navMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: prefsWindow.go(navRow.modelData)
                            }
                        }
                    }

                    Text {
                        visible: prefsWindow.filtered.length === 0
                        width: parent.width
                        topPadding: 14
                        horizontalAlignment: Text.AlignHCenter
                        text: "No Results"
                        color: pal.text2
                        font.family: pal.fam
                        font.pixelSize: 12
                    }
                }
            }

            // ───────── toolbar ─────────
            Item {
                id: header
                x: sidebar.width + 1
                width: parent.width - sidebar.width - 2
                height: 52

                Row {
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Repeater {
                        model: [ { g: "\u2039", dir: -1 }, { g: "\u203A", dir: 1 } ]
                        delegate: Item {
                            id: navBtn
                            required property var modelData
                            readonly property bool ok: modelData.dir < 0 ? prefsWindow.backStack.length > 0
                                                                           : prefsWindow.fwdStack.length > 0
                            width: 26; height: 28
                            Text {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -2
                                text: navBtn.modelData.g
                                font.pixelSize: 28
                                color: navBtn.ok ? pal.text2 : pal.text3
                                opacity: navBtn.ok ? 1 : 0.5
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: navBtn.ok
                                onClicked: {
                                    if (navBtn.modelData.dir < 0) prefsWindow.back();
                                    else prefsWindow.forward();
                                }
                            }
                        }
                    }
                }
                Text {
                    x: 74
                    anchors.verticalCenter: parent.verticalCenter
                    text: prefsWindow.panes[prefsWindow.cur].name
                    color: pal.text
                    font.family: pal.fam
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: pal.sep
                    opacity: flick.contentY > 4 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
            }

            // ───────── scrolling content ─────────
            Flickable {
                id: flick
                x: sidebar.width + 1
                y: 52
                width: parent.width - sidebar.width - 2
                height: parent.height - 52 - 1
                contentWidth: width
                contentHeight: paneLoader.height + 36
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick

                Loader {
                    id: paneLoader
                    x: 22
                    y: 6
                    width: flick.width - 44
                    sourceComponent: [paneGeneral, paneDock, paneMenuBar, paneAppearance, paneBehavior, paneApps, paneAbout][prefsWindow.cur]
                    onLoaded: fadeIn.restart()
                }
            }
            Rectangle {   // thin overlay scrollbar
                visible: flick.contentHeight > flick.height + 1
                x: frame.width - 8
                y: 52 + flick.visibleArea.yPosition * flick.height
                width: 4
                height: Math.max(28, flick.visibleArea.heightRatio * flick.height)
                radius: 2
                color: pal.text3
                opacity: flick.moving ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 300 } }
            }
        }

        // ═════════════ PANES ═════════════

        // ── General ──
        Component {
            id: paneGeneral
            Column {
                spacing: 10

                SLabel { t: pal; header: true; text: "Shell" }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Dock"
                        subtitle: "Show the Dock at the bottom of the screen"
                        SSwitch { t: pal; checked: root.dockEnabled; onToggled: v => root.dockEnabled = v }
                    }
                    SRow {
                        t: pal
                        title: "Menu Bar"
                        subtitle: "Show the panel at the top of the screen. Spotlight, Control Center and the calendar belong to it."
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.barEnabled : true
                            onToggled: v => { if (root.bar) root.bar.barEnabled = v; }
                        }
                    }
                }
                SLabel {
                    t: pal
                    text: "If you turn both off, reopen this window with:  qs -c macbar ipc call settings open"
                }
            }
        }

        // ── Menu Bar ──
        Component {
            id: paneMenuBar
            Column {
                spacing: 10

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Menu Bar style"
                        subtitle: (root.bar && root.bar.barStyle === "liquid" && root.bar.glassState === "failed")
                                  ? "Liquid Glass couldn't start (install qt6-shadertools)"
                                  : "Style of the menus and popovers"
                        SSegmented {
                            t: pal
                            model: ["Normal Blur", "Apple Liquid Glass"]
                            segWidth: 128
                            current: (root.bar && root.bar.barStyle === "liquid") ? 1 : 0
                            onPicked: i => { if (root.bar) root.bar.barStyle = (i === 1 ? "liquid" : "blur"); }
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Menu Bar and widget size"
                        subtitle: "Scales the bar widgets; the left and right groups stay tucked into the screen corners"
                        SSlider {
                            t: pal; from: 22; to: 48; stepSize: 1
                            value: root.bar ? root.bar.barHeight : 28
                            leftLabel: "Compact"; rightLabel: "Large"
                            onMoved: v => { if (root.bar) root.bar.barHeight = Math.round(v); }
                        }
                    }
                }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Bar background"
                        subtitle: "A separate layer (macbarbg) so Hyprland can blur it. Needs: layerrule = blur, macbarbg"
                        SSlider {
                            t: pal
                            from: 0; to: 0.6; stepSize: 0.01
                            value: root.bar ? root.bar.barBgOpacity : 0.10
                            leftLabel: "Hidden"; rightLabel: "Tinted"
                            onMoved: v => { if (root.bar) root.bar.barBgOpacity = v; }
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "24-hour clock"
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.use24h : false
                            onToggled: v => { if (root.bar) root.bar.use24h = v; }
                        }
                    }
                    SRow {
                        t: pal
                        title: "Show date"
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.showDate : false
                            onToggled: v => { if (root.bar) root.bar.showDate = v; }
                        }
                    }
                    SRow {
                        t: pal
                        title: "Show seconds"
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.showSeconds : false
                            onToggled: v => { if (root.bar) root.bar.showSeconds = v; }
                        }
                    }
                    SRow {
                        t: pal
                        title: "Week starts on Monday"
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.weekStartsMonday : false
                            onToggled: v => { if (root.bar) root.bar.weekStartsMonday = v; }
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Battery percentage"
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.showBatteryPercent : false
                            onToggled: v => { if (root.bar) root.bar.showBatteryPercent = v; }
                        }
                    }
                    SRow {
                        t: pal
                        title: "Real-time glass"
                        subtitle: "Keep window captures live so popovers, Spotlight and the Dock open on current pixels. Turn off to save GPU."
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.glassRealtime : true
                            onToggled: v => { if (root.bar) root.bar.glassRealtime = v; }
                        }
                    }
                }

                SLabel { t: pal; header: true; text: "Top Bar Widgets" }
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: "Apple menu"
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("appleMenu") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("appleMenu", v); } }
                    }
                    SRow {
                        t: pal; title: "Application menus"
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("appMenus") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("appMenus", v); } }
                    }
                    SRow {
                        t: pal; title: "Workspace switcher"
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("workspaces") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("workspaces", v); } }
                    }
                    SRow {
                        t: pal; title: "System tray"
                        SSwitch { t: pal; checked: root.bar ? root.bar.showTray : true; onToggled: v => { if (root.bar) root.bar.showTray = v; } }
                    }
                    SRow {
                        t: pal; title: "Volume"
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("volume") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("volume", v); } }
                    }
                    SRow {
                        t: pal; title: "Bluetooth"
                        subtitle: "Show the Bluetooth status icon, even while Bluetooth is off"
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("bluetooth") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("bluetooth", v); } }
                    }
                    SRow {
                        t: pal; title: "Keyboard layout"
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("keyboard") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("keyboard", v); } }
                    }
                    SRow {
                        t: pal; title: "Notifications"
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("notifications") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("notifications", v); } }
                    }
                    SRow {
                        t: pal; title: "Wi-Fi and network"
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("wifi") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("wifi", v); } }
                    }
                    SRow {
                        t: pal; title: "Spotlight search"
                        SSwitch { t: pal; checked: root.bar ? root.bar.showSearch : true; onToggled: v => { if (root.bar) root.bar.showSearch = v; } }
                    }
                    SRow {
                        t: pal; title: "Privacy indicators"
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("privacy") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("privacy", v); } }
                    }
                    SRow {
                        t: pal; title: "Control Center"
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("controlCenter") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("controlCenter", v); } }
                    }
                    SRow {
                        t: pal; title: "Clock and calendar"
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("clock") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("clock", v); } }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Keep clipboard history"
                        subtitle: "Spotlight \u2192 Clipboard (needs wl-clipboard and cliphist). Turn off to stop recording what you copy"
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.clipHistory : false
                            onToggled: v => { if (root.bar) root.bar.clipHistory = v; }
                        }
                    }
                    SRow {
                        t: pal
                        title: "Paste after choosing"
                        subtitle: "Insert the chosen clipboard entry or emoji into the focused app (Shift+Return only copies)"
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.clipAutoPaste : false
                            onToggled: v => { if (root.bar) root.bar.clipAutoPaste = v; }
                        }
                    }
                }
                SLabel { t: pal; header: true; text: "Screenshots" }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Save to a folder"
                        subtitle: "Press Print to select an area. Turn off to only copy it to the clipboard"
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.screenshotSave : true
                            onToggled: v => { if (root.bar) root.bar.screenshotSave = v; }
                        }
                    }
                    SRow {
                        t: pal
                        title: "Save location"
                        subtitle: "Leave empty for ~/Pictures/Screenshots"
                        Row {
                            spacing: 8
                            Rectangle {
                                width: 200; height: 24; radius: 6
                                color: pal.ctrl
                                border.width: 1
                                border.color: pal.cardBorder
                                TextInput {
                                    id: shotDirInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 8; anchors.rightMargin: 8
                                    verticalAlignment: TextInput.AlignVCenter
                                    clip: true
                                    selectByMouse: true
                                    color: pal.text
                                    selectionColor: pal.accent
                                    font.family: pal.fam
                                    font.pixelSize: 12
                                    text: root.bar ? root.bar.screenshotDir : ""
                                    onTextEdited: { if (root.bar) root.bar.screenshotDir = text; }
                                }
                                Text {
                                    visible: shotDirInput.text === ""
                                    x: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "~/Pictures/Screenshots"
                                    color: pal.text3
                                    font.family: pal.fam
                                    font.pixelSize: 12
                                }
                            }
                            SButton { t: pal; text: "Choose\u2026"; onClicked: shotPick.running = true }
                        }
                    }
                    SRow {
                        t: pal
                        title: "Quick folders"
                        SSegmented {
                            t: pal
                            property var dirs: ["~/Pictures/Screenshots", "~/Pictures", "~/Desktop", "~/Downloads"]
                            model: ["Screenshots", "Pictures", "Desktop", "Downloads"]
                            segWidth: 84
                            current: {
                                var d = root.bar ? root.bar.screenshotDir.replace(/\/+$/, "") : "";
                                return dirs.indexOf(d === "" ? dirs[0] : d);
                            }
                            onPicked: i => { if (root.bar) root.bar.screenshotDir = dirs[i]; }
                        }
                    }
                    SRow {
                        t: pal
                        title: "Copy to clipboard"
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.screenshotClipboard : true
                            onToggled: v => { if (root.bar) root.bar.screenshotClipboard = v; }
                        }
                    }
                    SRow {
                        t: pal
                        title: "Show a notification"
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.screenshotNotify : true
                            onToggled: v => { if (root.bar) root.bar.screenshotNotify = v; }
                        }
                    }
                }
                SLabel {
                    t: pal
                    text: "Bind the Print key:  bind = , Print, exec, qs -c macbar ipc call screenshot region.  Choose\u2026 needs zenity, kdialog or yad; otherwise type the path. Screenshots need grim."
                }
                Process {
                    id: shotPick
                    command: ["sh", "-c",
                        "if command -v zenity >/dev/null 2>&1; then zenity --file-selection --directory --title='Screenshot folder' 2>/dev/null; "
                        + "elif command -v kdialog >/dev/null 2>&1; then kdialog --getexistingdirectory \"$HOME\" 2>/dev/null; "
                        + "elif command -v yad >/dev/null 2>&1; then yad --file --directory --title='Screenshot folder' 2>/dev/null; fi"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            var d = text.trim();
                            if (d !== "" && root.bar) root.bar.screenshotDir = d;
                        }
                    }
                }
                SLabel {
                    t: pal
                    text: "Translucency, accent color, appearance and font are in Appearance. Commands (terminal, launcher, files, clipboard) can be edited in ~/.config/macbar/settings.json."
                }
            }
        }

        // ── Dock ──
        Component {
            id: paneDock
            Column {
                spacing: 10

                // live preview
                Rectangle {
                    id: pv
                    width: parent.width
                    height: 150
                    radius: 10
                    clip: true
                    border.width: 1
                    border.color: pal.cardBorder
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#4158D0" }
                        GradientStop { position: 0.55; color: "#9B59D0" }
                        GradientStop { position: 1.0; color: "#F3805A" }
                    }
                    readonly property real base: root.iconSize * 0.5
                    readonly property var apps: root.items.filter(function (i) {
                        return i.kind === "app" && !i.special;
                    }).slice(0, 6)

                    Rectangle {
                        id: pbar
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 10 + root.margin * 0.5
                        width: prow.width + 16
                        height: pv.base + 14
                        radius: root.cornerRadius * 0.6
                        color: root.darkMode ? Qt.rgba(0.10, 0.10, 0.11, root.glassOpacity)
                                             : Qt.rgba(1, 1, 1, root.glassOpacity * 0.55)
                        border.width: 1
                        border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.45)
                    }
                    Row {
                        id: prow
                        anchors.horizontalCenter: pbar.horizontalCenter
                        anchors.bottom: pbar.bottom
                        anchors.bottomMargin: 7
                        spacing: root.spacing * 0.5
                        Repeater {
                            model: pv.apps
                            delegate: Item {
                                id: pi
                                required property var modelData
                                required property int index
                                width: pv.base
                                height: pv.base
                                readonly property int mid: Math.min(2, pv.apps.length - 1)
                                readonly property int d: Math.abs(index - mid)
                                readonly property real f: d === 0 ? 1 : (d === 1 ? 0.5 : (d === 2 ? 0.12 : 0))
                                Image {
                                    anchors.fill: parent
                                    source: root.iconSrc(pi.modelData.icon)
                                    sourceSize: Qt.size(96, 96)
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                    transformOrigin: Item.Bottom
                                    scale: root.magnificationEnabled ? 1 + (root.magnification - 1) * pi.f : 1
                                    Behavior on scale { NumberAnimation { duration: 120 } }
                                }
                            }
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Size"
                        SSlider {
                            t: pal
                            from: 32; to: 128; stepSize: 1
                            value: root.iconSize
                            leftLabel: "Small"; rightLabel: "Large"
                            onMoved: v => root.iconSize = Math.round(v)
                        }
                    }
                    SRow {
                        t: pal
                        title: "Magnification"
                        subtitle: "Enlarge icons as the pointer moves over them"
                        SSwitch {
                            t: pal
                            checked: root.magnificationEnabled
                            onToggled: v => root.magnificationEnabled = v
                        }
                    }
                    SRow {
                        t: pal
                        title: "Magnification amount"
                        opacity: root.magnificationEnabled ? 1 : 0.45
                        SSlider {
                            t: pal
                            enabled: root.magnificationEnabled
                            from: 1.1; to: 2.5; stepSize: 0.05
                            value: root.magnification
                            leftLabel: "Min"; rightLabel: "Max"
                            onMoved: v => root.magnification = v
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Icon spacing"
                        SSlider {
                            t: pal
                            from: 0; to: 20; stepSize: 1
                            value: root.spacing
                            leftLabel: "Tight"; rightLabel: "Loose"
                            onMoved: v => root.spacing = Math.round(v)
                        }
                    }
                    SRow {
                        t: pal
                        title: "Distance from screen edge"
                        SSlider {
                            t: pal
                            from: 0; to: 40; stepSize: 1
                            value: root.margin
                            leftLabel: "Flush"; rightLabel: "Floating"
                            onMoved: v => root.margin = Math.round(v)
                        }
                    }
                }
                SLabel { t: pal; text: "Changes apply to the Dock immediately." }
            }
        }

        // ── Appearance ──
        Component {
            id: paneAppearance
            Column {
                spacing: 10

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Appearance"
                        subtitle: "Applies to the Dock, the Menu Bar and this window"
                        Row {
                            spacing: 14
                            SThemeTile {
                                t: pal; label: "Light"; dark: false
                                selected: !root.darkMode
                                onClicked: root.setLook("darkMode", false)
                            }
                            SThemeTile {
                                t: pal; label: "Dark"; dark: true
                                selected: root.darkMode
                                onClicked: root.setLook("darkMode", true)
                            }
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Accent color"
                        subtitle: "Highlights in the Dock menu and this window"
                        Row {
                            spacing: 6
                            Repeater {
                                model: root.accentChoices
                                delegate: Item {
                                    id: sw
                                    required property var modelData
                                    readonly property bool sel: String(root.accent).toLowerCase() === modelData.c.toLowerCase()
                                    width: 26; height: 26
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 18; height: 18; radius: 9
                                        color: sw.modelData.c
                                        border.width: 1
                                        border.color: Qt.rgba(0, 0, 0, 0.18)
                                    }
                                    Rectangle {
                                        anchors.centerIn: parent
                                        visible: sw.sel
                                        width: 25; height: 25; radius: 12.5
                                        color: "transparent"
                                        border.width: 2
                                        border.color: pal.text3
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: root.setLook("accent", sw.modelData.c)
                                    }
                                }
                            }
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Dock style"
                        subtitle: root.dockStyle === "liquid" && root.glassState === "failed"
                                  ? "Liquid Glass couldn't start (install qt6-shadertools) – using Normal Blur"
                                  : (root.dockStyle === "liquid" && root.glassState === "building"
                                     ? "Preparing the Liquid Glass shader…"
                                     : "Blur of the desktop, or refracting Liquid Glass")
                        SSegmented {
                            t: pal
                            model: ["Normal Blur", "Apple Liquid Glass"]
                            segWidth: 128
                            current: root.dockStyle === "liquid" ? 1 : 0
                            onPicked: i => root.dockStyle = (i === 1 ? "liquid" : "blur")
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Translucency"
                        subtitle: root.dockStyle === "liquid" ? "How much tint the glass adds over the refraction"
                                                              : "How frosted the Dock's glass looks"
                        SSlider {
                            t: pal
                            from: 0.0; to: 0.85; stepSize: 0.01
                            value: root.glassOpacity
                            leftLabel: "Clear"; rightLabel: "Frosted"
                            onMoved: v => root.setLook("glassOpacity", v)
                        }
                    }
                    SRow {
                        t: pal
                        visible: root.dockStyle === "liquid"
                        title: "Blur"
                        subtitle: "How strongly the glass blurs what's behind it"
                        SSlider {
                            t: pal
                            from: 0; to: 80; stepSize: 1
                            value: root.glassBlur
                            leftLabel: "Sharp"; rightLabel: "Very blurry"
                            onMoved: v => root.setLook("glassBlur", Math.round(v))
                        }
                    }
                    SRow {
                        t: pal
                        visible: root.dockStyle === "liquid"
                        title: "Liquid strength"
                        subtitle: "Refraction, magnification and colour fringing of the glass"
                        SSlider {
                            t: pal
                            from: 0.5; to: 2.5; stepSize: 0.05
                            value: root.glassLiquid
                            leftLabel: "Subtle"; rightLabel: "Very liquid"
                            onMoved: v => root.setLook("glassLiquid", v)
                        }
                    }
                    SRow {
                        t: pal
                        title: "Corner radius"
                        SSlider {
                            t: pal
                            from: 0; to: 32; stepSize: 1
                            value: root.cornerRadius
                            leftLabel: "Square"; rightLabel: "Round"
                            onMoved: v => root.cornerRadius = Math.round(v)
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Font"
                        subtitle: "Used for labels and menus"
                        SSegmented {
                            t: pal
                            model: ["Inter", "Noto Sans", "System"]
                            segWidth: 76
                            current: root.fontFamily === "Inter" ? 0 : (root.fontFamily === "Noto Sans" ? 1 : 2)
                            onPicked: i => root.setLook("fontFamily", ["Inter", "Noto Sans", "sans-serif"][i])
                        }
                    }
                }
                SLabel { t: pal; text: root.dockStyle === "liquid"
                                       ? "Liquid Glass refracts the wallpaper and windows behind the Dock in real time. Corner radius also shapes the glass."
                                       : "The blur behind the Dock comes from your Hyprland layer rule; translucency only controls the tint." }
            }
        }

        // ── Behavior ──
        Component {
            id: paneBehavior
            Column {
                spacing: 10

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Automatically hide and show the Dock"
                        subtitle: root.hideMode === "smart" ? "Hides only while a tiled window needs the space"
                                : (root.hideMode === "always" ? "Always hidden until the pointer touches the screen edge"
                                                              : "Always visible and reserves screen space")
                        SSegmented {
                            t: pal
                            model: ["Smart", "Always", "Never"]
                            segWidth: 64
                            current: root.hideMode === "smart" ? 0 : (root.hideMode === "always" ? 1 : 2)
                            onPicked: i => root.hideMode = ["smart", "always", "never"][i]
                        }
                    }
                    SRow {
                        t: pal
                        visible: root.hideMode !== "never"
                        title: "Hide delay"
                        SSlider {
                            t: pal
                            from: 0; to: 1500; stepSize: 50
                            value: root.hideDelay
                            leftLabel: "Instant"; rightLabel: "1.5 s"
                            onMoved: v => root.hideDelay = Math.round(v)
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Show Dock on"
                        SSegmented {
                            t: pal
                            model: ["All Displays", "Primary Only"]
                            segWidth: 96
                            current: root.monitor === "" ? 0 : 1
                            onPicked: i => {
                                if (i === 0) root.monitor = "";
                                else if (Quickshell.screens.length > 0) root.monitor = Quickshell.screens[0].name;
                            }
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Show labels"
                        subtitle: "Display an app's name when you hover its icon"
                        SSwitch { t: pal; checked: root.showLabels; onToggled: v => root.showLabels = v }
                    }
                    SRow {
                        t: pal
                        title: "Show window previews"
                        subtitle: "Open windows appear as live previews next to the Trash, each with its app's icon"
                        SSwitch { t: pal; checked: root.showThumbs; onToggled: v => root.showThumbs = v }
                    }
                    SRow {
                        t: pal
                        title: "Live window capture"
                        subtitle: "Capture open windows for the previews. Turn off and the previews show the app icon instead (Liquid Glass is not affected)"
                        SSwitch { t: pal; checked: root.windowCapture; onToggled: v => root.windowCapture = v }
                    }
                    SRow {
                        t: pal
                        title: "Show indicators for open applications"
                        SSwitch { t: pal; checked: root.showIndicators; onToggled: v => root.showIndicators = v }
                    }
                    SRow {
                        t: pal
                        title: "Animate opening applications"
                        subtitle: "Icons bounce while an app is launching"
                        SSwitch { t: pal; checked: root.bounceOnLaunch; onToggled: v => root.bounceOnLaunch = v }
                    }
                    SRow {
                        t: pal
                        title: "Show Trash in the Dock"
                        SSwitch { t: pal; checked: root.showTrash; onToggled: v => root.showTrash = v }
                    }
                }
            }
        }

        // ── Applications ──
        Component {
            id: paneApps
            Column {
                id: appsCol
                spacing: 10
                readonly property int pinCount: root.items.filter(function (i) {
                    return i.kind === "app" && i.pinned && !i.special;
                }).length

                SLabel { t: pal; header: true; text: "Kept in Dock" }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        visible: appsCol.pinCount === 0
                        title: "No apps are kept in the Dock"
                        subtitle: "Right-click a running app and choose Keep in Dock."
                    }
                    Repeater {
                        model: root.items
                        delegate: SRow {
                            id: appRow
                            required property var modelData
                            t: pal
                            visible: modelData.kind === "app" && modelData.pinned === true && !modelData.special
                            title: modelData.name || ""
                            iconSource: modelData.icon ? root.iconSrc(modelData.icon) : ""
                            SButton {
                                t: pal
                                text: "Remove"
                                onClicked: root.togglePin(appRow.modelData)
                            }
                        }
                    }
                }
                SLabel { t: pal; text: "Drag icons in the Dock to reorder them. Pins are saved to ~/.config/macdock/pinned.json." }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Reset Dock Items"
                        subtitle: "Go back to the default set of apps"
                        SButton { t: pal; text: "Reset"; onClicked: root.resetPins() }
                    }
                }
            }
        }

        // ── About ──
        Component {
            id: paneAbout
            Column {
                id: aboutCol
                spacing: 10
                property bool armed: false
                Timer { id: disarm; interval: 3000; onTriggered: aboutCol.armed = false }

                SCard {
                    t: pal
                    Item {
                        width: parent.width
                        height: 176
                        SGlyph {
                            x: (parent.width - width) / 2
                            y: 44
                            kind: "dock"
                            scale: 3.4
                        }
                        Text {
                            y: 108
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: "macshell"
                            color: pal.text
                            font.family: pal.fam
                            font.pixelSize: 21
                            font.weight: Font.DemiBold
                        }
                        Text {
                            y: 138
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: "Version 2 \u2022 Hyprland \u2022 Quickshell"
                            color: pal.text2
                            font.family: pal.fam
                            font.pixelSize: 12
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Configuration"
                        Text {
                            text: "~/.config/macdock"
                            color: pal.text2
                            font.family: pal.fam
                            font.pixelSize: 13
                        }
                    }
                    SRow {
                        t: pal
                        title: "Open configuration folder"
                        SButton {
                            t: pal
                            text: "Open"
                            onClicked: Quickshell.execDetached(["xdg-open", root.configDir])
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: "Reset all settings"
                        subtitle: "Restore the default look and behavior. Pinned apps are kept."
                        SButton {
                            t: pal
                            destructive: true
                            text: aboutCol.armed ? "Click to Confirm" : "Reset\u2026"
                            onClicked: {
                                if (aboutCol.armed) { aboutCol.armed = false; root.resetSettings(); }
                                else { aboutCol.armed = true; disarm.restart(); }
                            }
                        }
                    }
                }

                SCard {
                    t: pal
                    Item {
                        width: parent.width
                        height: 64
                        Text {
                            x: 14
                            y: 12
                            text: "Made by Rickky"
                            color: pal.text
                            font.family: pal.fam
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }
                        Text {
                            id: ghLink
                            x: 14
                            y: 33
                            text: "https://github.com/0-ss"
                            color: pal.accent
                            font.family: pal.fam
                            font.pixelSize: 12
                            font.underline: ghMa.containsMouse
                            MouseArea {
                                id: ghMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Quickshell.execDetached(["xdg-open", "https://github.com/0-ss"])
                            }
                        }
                    }
                }
            }
        }
    }

    readonly property real effMag: magnificationEnabled ? magnification : 1
    readonly property int bgHeight: iconSize + topPad + bottomPad
    readonly property int sepWidth: 9
    readonly property real magRadius: (iconSize + spacing) * 2.6
    readonly property int menuRoom: 300
    readonly property int windowHeight: Math.ceil(margin + bgHeight + iconSize * (effMag - 1) + 72 + menuRoom)
    readonly property string configDir: Quickshell.env("HOME") + "/.config/macdock"

    property var items: []
    property int appCount: 0
    property int sepCount: 0
    readonly property real totalW0: Math.max(0, appCount * (iconSize + spacing) + sepCount * (sepWidth + spacing) - spacing)
    property var launching: ({})
    property var knownKeys: ({})
    property string lastSig: ""

    // ───────────── LOGIC ─────────────
    function openPrefs(pane) {
        if (pane !== undefined && pane !== "") {
            for (var i = 0; i < prefsWindow.panes.length; i++)
                if (prefsWindow.panes[i].id === pane) { prefsWindow.go(i); break; }
        }
        prefsWindow.visible = true;
        prefsWindow.requestActivate();
    }

    function resetPins() {
        pinned = defaultPinned;
        store.setText(JSON.stringify(defaultPinned.slice(), null, 2));
        rebuild();
    }

    function resetSettings() {
        dockEnabled = true;
        if (bar) bar.resetSettings();
        iconSize = 52; magnification = 1.7; magnificationEnabled = true;
        spacing = 6; margin = 6; cornerRadius = 18;
        darkMode = true; glassOpacity = 0.42; glassBlur = 5; glassLiquid = 1.0; dockStyle = "blur"; accent = "#0a84ff"; fontFamily = "Inter";
        hideMode = "smart"; hideDelay = 450; monitor = "";
        showTrash = true; showLabels = true; showIndicators = true; bounceOnLaunch = true; showThumbs = true; windowCapture = true;
    }

    // ── settings persistence (~/.config/macdock/settings.json) ──
    readonly property string settingsSig: [dockEnabled, iconSize, magnification, magnificationEnabled, spacing, margin,
        cornerRadius, darkMode, glassOpacity, glassBlur, glassLiquid, dockStyle, wallpaperPath, String(accent), fontFamily, hideMode, hideDelay, monitor,
        showTrash, showLabels, showIndicators, bounceOnLaunch, showThumbs, windowCapture].join("|")
    property bool settingsReady: false
    onSettingsSigChanged: if (settingsReady) saveTimer.restart()
    onShowTrashChanged: { rebuild(); if (showTrash) trashCheck(); }
    onShowThumbsChanged: rebuild()
    onWindowCaptureChanged: rebuild()

    function saveSettings() {
        var o = {
            dockEnabled: dockEnabled, iconSize: iconSize, magnification: magnification, magnificationEnabled: magnificationEnabled,
            spacing: spacing, margin: margin, cornerRadius: cornerRadius,
            darkMode: darkMode, glassOpacity: glassOpacity, dockStyle: dockStyle, wallpaperPath: wallpaperPath, glassDebug: glassDebug,
            glassRim: glassRim, glassGrain: glassGrain, glassLiquid: glassLiquid, glassBlur: glassBlur,
            accent: String(accent), fontFamily: fontFamily,
            hideMode: hideMode, hideDelay: hideDelay, monitor: monitor,
            showTrash: showTrash, showLabels: showLabels, showIndicators: showIndicators,
            bounceOnLaunch: bounceOnLaunch, showThumbs: showThumbs, windowCapture: windowCapture
        };
        settingsStore.setText(JSON.stringify(o, null, 2));
    }

    function applySettings(o) {
        if (!o || typeof o !== "object") return;
        var keys = ["dockEnabled", "iconSize", "magnification", "magnificationEnabled", "spacing", "margin", "cornerRadius",
                    "darkMode", "glassOpacity", "dockStyle", "wallpaperPath", "glassDebug", "glassRim", "glassGrain", "glassLiquid", "glassBlur", "accent", "fontFamily", "hideMode", "hideDelay", "monitor",
                    "showTrash", "showLabels", "showIndicators", "bounceOnLaunch", "showThumbs", "windowCapture"];
        for (var i = 0; i < keys.length; i++) {
            if (o[keys[i]] === undefined) continue;
            try { root[keys[i]] = o[keys[i]]; } catch (err) { }
        }
    }

    FileView {
        id: settingsStore
        path: root.configDir + "/settings.json"
        printErrors: false
        onLoaded: {
            try { root.applySettings(JSON.parse(text())); } catch (err) { }
            root.settingsReady = true;
            if (root.dockStyle === "liquid") root.startGlass();
        }
        onLoadFailed: root.settingsReady = true
    }
    Timer { id: saveTimer; interval: 400; onTriggered: root.saveSettings() }

    function lookup(appId) {
        if (!appId) return null;
        var e = DesktopEntries.byId(appId);
        if (!e && DesktopEntries.heuristicLookup) e = DesktopEntries.heuristicLookup(appId);
        return e;
    }

    function keyOf(appId) {
        var e = lookup(appId);
        return (e ? e.id : appId).toLowerCase();
    }

    // stable ids so a window's preview cell isn't rebuilt on every refresh
    property var winIdList: []
    property int winIdNext: 1
    function winIdFor(tl) {
        for (var i = 0; i < winIdList.length; i++) if (winIdList[i].tl === tl) return winIdList[i].id;
        var id = winIdNext++;
        winIdList.push({ tl: tl, id: id, born: Date.now() });
        return id;
    }
    function winAge(tl) {
        for (var i = 0; i < winIdList.length; i++) if (winIdList[i].tl === tl) return Date.now() - winIdList[i].born;
        return 0;
    }
    Timer { id: youngWin; interval: 250; onTriggered: root.rebuild() }

    function iconSrc(icon) {
        if (!icon) return Quickshell.iconPath("application-x-executable");
        if (icon.charAt(0) === "/") return "file://" + icon;
        return Quickshell.iconPath(icon, "application-x-executable");
    }
    // icon of a dock cell; the Trash switches to the "full" icon while there is something in it
    function cellIconSrc(it) {
        if (it && it.special === "trash" && trashFull) {
            var p = Quickshell.iconPath("user-trash-full", true);
            if (p !== "") return p;
        }
        return iconSrc(it ? it.icon : "");
    }

    // ── Trash state: the standard XDG trash (~/.local/share/Trash/files) is what Dolphin's trash:/ shows ──
    // inotifywait (inotify-tools) reports changes at once; without it the folder is checked every 3 s.
    property bool trashFull: false
    property bool trashReady: false           // first check done (it also creates the folder, which inotifywait needs)
    property bool trashPoll: false            // no inotifywait: poll instead
    readonly property string trashDir: {
        var x = Quickshell.env("XDG_DATA_HOME");
        return ((x && x !== "") ? x : Quickshell.env("HOME") + "/.local/share") + "/Trash/files";
    }
    function trashCheck() { if (!trashCheckProc.running) trashCheckProc.running = true; }
    Process {
        id: trashCheckProc
        command: ["sh", "-c", "mkdir -p \"$1\"; if [ -n \"$(ls -A \"$1\" 2>/dev/null | head -n 1)\" ]; then s=1; else s=0; fi; "
                              + "if command -v inotifywait >/dev/null 2>&1; then w=w; else w=p; fi; echo \"$s $w\"", "sh", root.trashDir]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = text.trim().split(" ");
                root.trashFull = t[0] === "1";
                root.trashPoll = t[1] === "p";
                root.trashReady = true;
            }
        }
    }
    Process {
        id: trashWatch
        running: root.showTrash && root.trashReady && !root.trashPoll
        command: ["inotifywait", "-m", "-q", "-e", "create", "-e", "delete", "-e", "moved_to", "-e", "moved_from", root.trashDir]
        stdout: SplitParser { onRead: data => trashDebounce.restart() }
    }
    // Empty Trash: KDE's ktrash when it exists (it also cleans trashes on other drives and keeps Dolphin's trash icon in sync),
    // otherwise the standard XDG trash folder is cleared directly. (gio is not used: without gvfs it "succeeds" without doing anything.)
    function emptyTrash() {
        Quickshell.execDetached(["sh", "-c",
            "command -v ktrash6 >/dev/null 2>&1 && ktrash6 --empty && exit 0; "
            + "command -v ktrash5 >/dev/null 2>&1 && ktrash5 --empty && exit 0; "
            + "d=\"${XDG_DATA_HOME:-$HOME/.local/share}/Trash\"; "
            + "chmod -R u+w \"$d/files\" 2>/dev/null; "
            + "find \"$d/files\" \"$d/info\" -mindepth 1 -delete 2>/dev/null; "
            + "rm -f \"$d/directorysizes\""]);
        trashAfterEmpty.restart();
    }
    Timer { id: trashAfterEmpty; interval: 900; onTriggered: root.trashCheck() }
    Timer { id: trashDebounce; interval: 150; onTriggered: root.trashCheck() }
    Timer { interval: 3000; repeat: true; running: root.showTrash && root.trashPoll; onTriggered: root.trashCheck() }

    // bumped (debounced) whenever windows open, close or change focus; thumbnails re-pick their window from it
    property int windowTick: 0
    Timer { id: tickDebounce; interval: 120; onTriggered: root.windowTick++ }

    // the window an unpinned app is represented by: the focused one, else the first
    function thumbWindow(key) {
        var w = windowsFor(key);
        for (var i = 0; i < w.length; i++) if (w[i].activated) return w[i];
        return w.length > 0 ? w[0] : null;
    }

    function windowsFor(key) {
        var out = [];
        var tls = ToplevelManager.toplevels.values;
        for (var i = 0; i < tls.length; i++) {
            if (tls[i].appId && keyOf(tls[i].appId) === key) out.push(tls[i]);
        }
        return out;
    }

    function activate(item, forceNew) {
        if (item.kind === "win") { if (item.tl) item.tl.activate(); return; }
        if (item.special === "trash") {
            // the file manager first (Dolphin understands trash:/ natively); xdg-open only as the last resort
            Quickshell.execDetached(["sh", "-c",
                "if command -v dolphin >/dev/null 2>&1; then exec dolphin trash:/; fi; "
                + "for fm in nautilus thunar nemo pcmanfm-qt; do if command -v $fm >/dev/null 2>&1; then exec $fm trash:///; fi; done; "
                + "exec xdg-open trash:///"]);
            return;
        }
        var wins = windowsFor(item.key);
        if (wins.length > 0 && !forceNew) {
            var idx = -1;
            for (var i = 0; i < wins.length; i++) if (wins[i].activated) idx = i;
            wins[(idx + 1) % wins.length].activate();
            return;
        }
        if (item.entry) {
            var L = {};
            for (var k in launching) L[k] = launching[k];
            L[item.key] = Date.now();
            launching = L;
            item.entry.execute();
            pruneTimer.restart();
        }
    }

    function togglePin(item) {
        var out = [], found = false;
        for (var i = 0; i < pinned.length; i++) {
            var id = String(pinned[i]).replace(/\.desktop$/, "");
            if (id.toLowerCase() === item.key) { found = true; continue; }
            out.push(pinned[i]);
        }
        if (!found && item.entry) out.push(item.entry.id);
        pinned = out;
        store.setText(JSON.stringify(out, null, 2));
        rebuild();
    }

    function reorderPinned(from, to) {
        var vis = [];
        for (var i = 0; i < items.length; i++) {
            var it = items[i];
            if (it.kind === "app" && it.pinned && !it.special) vis.push(it);
            else break;
        }
        if (from < 0 || from >= vis.length) return;
        var moved = vis.splice(from, 1)[0];
        vis.splice(Math.max(0, Math.min(to, vis.length)), 0, moved);

        var out = [], have = {};
        for (var v = 0; v < vis.length; v++) { out.push(vis[v].entry.id); have[vis[v].key] = true; }
        for (var p = 0; p < pinned.length; p++) {
            var id = String(pinned[p]).replace(/\.desktop$/, "");
            if (!have[id.toLowerCase()]) out.push(pinned[p]);
        }
        pinned = out;
        store.setText(JSON.stringify(out, null, 2));
        rebuild();
    }

    function menuFor(item) {
        var m = [];
        if (item.kind === "win") {
            m.push({ kind: "item", label: "Show", run: function () { activate(item, false); } });
            m.push({ kind: "item", label: "Close", run: function () { if (item.tl) item.tl.close(); } });
            m.push({ kind: "sep" });
            m.push({ kind: "item", label: "Settings\u2026", run: function() { root.openPrefs(); } });
            return m;
        }
        if (item.special === "trash") {
            m.push({ kind: "item", label: "Open", run: function () { activate(item, false); } });
            m.push({ kind: "item", label: "Empty Trash", confirm: true, disabled: !trashFull, run: function () { root.emptyTrash(); } });
            m.push({ kind: "sep" });
            m.push({ kind: "item", label: "Settings\u2026", run: function() { root.openPrefs(); } });
            return m;
        }
        var wins = windowsFor(item.key);
        if (wins.length > 0) {
            for (var i = 0; i < wins.length && i < 8; i++) {
                (function (w) {
                    var t = w.title && w.title.length > 0 ? w.title : item.name;
                    m.push({ kind: "item", label: (w.activated ? "\u2713  " : "") + t,
                             run: function () { w.activate(); } });
                })(wins[i]);
            }
            m.push({ kind: "sep" });
        }
        if (item.entry) {
            m.push({ kind: "item", label: item.pinned ? "Remove from Dock" : "Keep in Dock",
                     run: function () { togglePin(item); } });
            m.push({ kind: "item", label: wins.length > 0 ? "New Window" : "Open",
                     run: function () { activate(item, true); } });
        }
        if (wins.length > 0) {
            m.push({ kind: "sep" });
            m.push({ kind: "item", label: "Quit", run: function () {
                var ws = windowsFor(item.key);
                for (var j = 0; j < ws.length; j++) ws[j].close();
            } });
        }
        
        m.push({ kind: "sep" });
        m.push({ kind: "item", label: "Settings\u2026", run: function() { root.openPrefs(); } });

        return m;
    }

    function rebuild() {
        var tls = ToplevelManager.toplevels.values;
        var running = {};
        var runOrder = [];
        for (var i = 0; i < tls.length; i++) {
            var id = tls[i].appId;
            if (!id) continue;
            var k = keyOf(id);
            if (!running[k]) { running[k] = true; runOrder.push({ key: k, appId: id }); }
        }

        var L = {}, now = Date.now(), changed = false;
        for (var lk in launching) {
            if (!running[lk] && now - launching[lk] < 8000) L[lk] = launching[lk];
            else changed = true;
        }
        if (changed) launching = L;

        var list = [], seen = {};
        for (var p = 0; p < pinned.length; p++) {
            var e = DesktopEntries.byId(String(pinned[p]).replace(/\.desktop$/, ""));
            if (!e) continue;
            var ek = e.id.toLowerCase();
            if (seen[ek]) continue;
            seen[ek] = true;
            list.push({ kind: "app", key: ek, name: e.name, icon: e.icon, entry: e,
                        running: !!running[ek], pinned: true });
        }

        var extras = [];
        for (var r = 0; r < runOrder.length; r++) if (!seen[runOrder[r].key]) extras.push(runOrder[r]);
        if (extras.length > 0 && list.length > 0) list.push({ kind: "sep" });
        for (var x = 0; x < extras.length; x++) {
            var e2 = lookup(extras[x].appId);
            list.push({ kind: "app", key: extras[x].key,
                        name: e2 ? e2.name : extras[x].appId,
                        icon: e2 ? e2.icon : extras[x].appId.toLowerCase(),
                        entry: e2, running: true, pinned: false });
        }

        // window previews: one cell per open window, in their own section next to the Trash
        var winItems = [], liveWins = [];
        if (showThumbs) {
            for (var w = 0; w < tls.length; w++) {
                var tl = tls[w];
                if (!tl.appId || tl.title === "macshell Settings") continue;
                // live capture off: a preview cell is only an app icon, so a pinned app (its icon is already in the Dock) gets none; unpinned apps keep theirs
                if (!windowCapture && seen[keyOf(tl.appId)]) continue;
                var e3 = lookup(tl.appId);
                var wid = winIdFor(tl);
                liveWins.push(tl);
                if (winAge(tl) < 200) { if (!youngWin.running) youngWin.start(); continue; }     // no preview (= no capture) for brand-new windows
                winItems.push({ kind: "win", key: "win:" + wid, tl: tl,
                                name: e3 ? e3.name : tl.appId,
                                icon: e3 ? e3.icon : tl.appId.toLowerCase(),
                                entry: null, running: false, pinned: false });
            }
        }
        var keep = [];
        for (var wi = 0; wi < winIdList.length; wi++) if (liveWins.indexOf(winIdList[wi].tl) >= 0) keep.push(winIdList[wi]);
        winIdList = keep;

        if (showTrash || winItems.length > 0) {
            list.push({ kind: "sep" });
            for (var wj = 0; wj < winItems.length; wj++) list.push(winItems[wj]);
        }
        if (showTrash && winItems.length > 0) list.push({ kind: "sep" });
        if (showTrash) {
            list.push({ kind: "app", key: "__trash", name: "Trash", icon: "user-trash",
                        entry: null, running: false, pinned: true, special: "trash" });
        }

        var firstBuild = (lastSig === "");
        var nowKeys = {}, nA = 0, nS = 0, sig = [];
        for (var n = 0; n < list.length; n++) {
            var it = list[n];
            it.nA = nA; it.nS = nS;
            if (it.kind === "sep") nS++; else nA++;
            if (it.kind !== "sep") {
                it.fresh = !firstBuild && !knownKeys[it.key];
                nowKeys[it.key] = true;
            }
            sig.push(it.kind + ":" + (it.key || "") + ":" + it.running + ":" + (it.icon || ""));
        }
        appCount = nA;
        sepCount = nS;
        knownKeys = nowKeys;

        var s = sig.join("|");
        if (s !== lastSig) { lastSig = s; items = list; }
    }

    // ═════════════ LIQUID GLASS BACKEND ═════════════
    // glassState: "idle" → "building" (qsb running) → "ready" | "failed". "failed" falls back to Normal Blur.
    property string glassState: "idle"
    readonly property bool liquidActive: dockStyle === "liquid" && glassState === "ready"
    readonly property string glassShaderSrc: decodeURIComponent(Qt.resolvedUrl("liquidglass.frag").toString().replace("file://", ""))
    readonly property string glassShaderOut: configDir + "/liquidglass.frag.qsb"
    readonly property url glassShaderUrl: "file://" + glassShaderOut

    onDockStyleChanged: if (dockStyle === "liquid") startGlass()
    onGlassStateChanged: console.log("[macdock-glass] state:", glassState)
    function startGlass() {
        if (glassState === "ready" || glassState === "building") return;
        glassState = "building";
        qsbProc.running = true;
        hub.refreshWallpaper();
        refreshBusy();                 // monitor geometry for the window compositor
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
        stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.log("[macdock-glass] qsb:", text.trim()) }
        onExited: (code, status) => root.glassState = (code === 0 ? "ready" : "failed")
    }

    // wallpaper the glass refracts. Sources, in order: wallpaperPath override, Noctalia's settings.toml
    // ([wallpaper.monitors.<name>] → [wallpaper.last] → [wallpaper.default]), then awww/swww/hyprpaper.
    readonly property var wallpaperMap: hub ? hub.wallpaperMap : ({})
    Binding { target: root.hub; property: "dockWantsWallpaper"; value: root.liquidActive }
    onWallpaperMapChanged: console.log("[macdock-glass] wallpaper sources:", JSON.stringify(wallpaperMap))
    function wallpaperFor(screenName) {
        var p = wallpaperPath !== "" ? wallpaperPath
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

    // live window geometry for the backdrop compositor (polled only while Liquid Glass is on)
    readonly property var glassClients: hub ? hub.glassClients : []
    Binding { target: root.hub; property: "dockWantsGeo"; value: root.liquidActive && root.dockEnabled }
    // window captures are admitted by the shared gate in shell.qml (hub.tlFor): 0.2 s after a window appears, one every 110 ms

    // ── smart hide: which monitors have a non-floating window on their active workspace ──
    property var busyMonitors: ({})
    property var monData: []
    property bool refreshPending: false

    function refreshBusy() {
        if (monProc.running || clientProc.running) { refreshPending = true; return; }
        monProc.running = true;
    }

    function computeBusy(clients) {
        var busy = {};
        for (var m = 0; m < monData.length; m++) {
            var mon = monData[m];
            var ids = [mon.activeWorkspace ? mon.activeWorkspace.id : -999];
            if (mon.specialWorkspace && mon.specialWorkspace.id !== 0) ids.push(mon.specialWorkspace.id);
            for (var c = 0; c < clients.length; c++) {
                var cl = clients[c];
                if (cl.floating || !cl.mapped || cl.hidden) continue;
                if (cl.monitor !== mon.id) continue;
                if (ids.indexOf(cl.workspace.id) >= 0) { busy[mon.name] = true; break; }
            }
        }
        busyMonitors = busy;
    }

    Process {
        id: monProc
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.monData = JSON.parse(text); } catch (err) { }
                clientProc.running = true;
            }
        }
    }
    Process {
        id: clientProc
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.computeBusy(JSON.parse(text)); } catch (err) { }
                if (root.refreshPending) { root.refreshPending = false; monProc.running = true; }
            }
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) { busyDebounce.restart(); tickDebounce.restart(); }
    }
    Timer { id: busyDebounce; interval: 120; onTriggered: root.refreshBusy() }

    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", configDir]);
        rebuild();
        refreshBusy();
        trashCheck();
    }

    FileView {
        id: store
        path: root.configDir + "/pinned.json"
        printErrors: false
        onLoaded: {
            try {
                var a = JSON.parse(text());
                if (Array.isArray(a)) { root.pinned = a; root.rebuild(); }
            } catch (err) { }
        }
    }

    Connections {
        target: ToplevelManager.toplevels
        function onValuesChanged() { root.rebuild(); settle.restart(); tickDebounce.restart(); }
    }
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { root.rebuild(); }
    }
    Timer { id: settle; interval: 350; onTriggered: root.rebuild() }
    Timer { id: pruneTimer; interval: 8200; onTriggered: root.rebuild() }

    // ───────────── UI ─────────────
    Variants {
        model: (root.settingsReady && root.dockEnabled) ? Quickshell.screens : []

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: root.monitor === "" || modelData.name === root.monitor

            anchors { left: true; right: true; bottom: true }
            implicitHeight: root.windowHeight
            color: "transparent"

            exclusionMode: ExclusionMode.Normal
            exclusiveZone: root.hideMode === "never" ? root.bgHeight + root.margin : 0

            WlrLayershell.namespace: "macdock"
            WlrLayershell.layer: WlrLayer.Top

            mask: Region { item: maskItem }

            Item {
                id: ui
                anchors.fill: parent

                property real mx: 0
                Behavior on mx { NumberAnimation { duration: 55; easing.type: Easing.OutQuad } }
                property bool revealed: false
                property var menuItem: null
                property var menuModel: []
                property string armed: ""            // label of a confirm-type entry that was clicked once (e.g. Empty Trash)
                onMenuItemChanged: armed = ""
                property real menuCx: 0
                readonly property bool menuOpen: menuItem !== null
                readonly property bool wantsHide: root.hideMode === "always"
                    || (root.hideMode === "smart" && root.busyMonitors[win.modelData.name] === true)
                property bool dragging: false
                property int dragIndex: -1
                property int dragTarget: -1
                property string dragKey: ""
                property real dragPressX: 0
                property real dragDelta: 0
                property real dragShiftW: 0
                property bool justDragged: false

                function pinnedCount() {
                    var n = 0;
                    for (var i = 0; i < root.items.length; i++) {
                        var it = root.items[i];
                        if (it.kind === "app" && it.pinned && !it.special) n++;
                        else break;
                    }
                    return n;
                }
                function naturalCenter(i) {
                    var c = rep.itemAt(i);
                    return c ? row.mapToItem(ui, c.x + c.width / 2, 0).x : 0;
                }
                function beginDrag(index, key, pressX, shiftW) {
                    menuItem = null;
                    dragIndex = index;
                    dragTarget = index;
                    dragKey = key;
                    dragPressX = pressX;
                    dragDelta = 0;
                    dragShiftW = shiftW;
                    dragging = true;
                }
                function dragUpdate(absX) {
                    dragDelta = absX - dragPressX;
                    var center = naturalCenter(dragIndex) + dragDelta;
                    var P = pinnedCount(), t = 0;
                    for (var j = 0; j < P; j++) {
                        if (j === dragIndex) continue;
                        if (naturalCenter(j) < center) t++;
                    }
                    dragTarget = t;
                }
                function shiftFor(i) {
                    if (dragIndex < i && i <= dragTarget) return -dragShiftW;
                    if (dragTarget <= i && i < dragIndex) return dragShiftW;
                    return 0;
                }
                function endDrag() {
                    var from = dragIndex, to = dragTarget;
                    dragging = false;
                    dragKey = "";
                    dragIndex = -1;
                    dragTarget = -1;
                    dragDelta = 0;
                    justDragged = true;
                    Qt.callLater(function () { ui.justDragged = false; });
                    if (to !== from) root.reorderPinned(from, to);
                }

                readonly property bool tucked: wantsHide && !revealed && !menuOpen && !dragging
                readonly property real refLeft: (width - root.totalW0) / 2
                readonly property real activeTop: height - root.margin - root.bgHeight
                                                  - root.iconSize * (root.effMag - 1) - 12
                readonly property bool active: dragging || (hh.hovered && hh.point.position.y > activeTop && !tucked)
                property real strength: active ? 1 : 0
                Behavior on strength { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                HoverHandler {
                    id: hh
                    onPointChanged: if (hovered && !ui.dragging) ui.mx = point.position.x
                    onHoveredChanged: {
                        if (hovered) { hideTimer.stop(); ui.revealed = true; }
                        else hideTimer.restart();
                    }
                }
                Timer { id: hideTimer; interval: root.hideDelay; onTriggered: if (!ui.dragging) ui.revealed = false }

                // ── Liquid Glass backdrop: wallpaper + the live windows behind the Dock, in screen coordinates ──
                // Built from per-window captures (not a screen capture) so the Dock never ends up refracting itself.
                Loader {
                    id: glassBackdrop
                    active: root.liquidActive
                    sourceComponent: Item {
                        id: bd
                        x: 0
                        y: -(win.modelData.height - ui.height)
                        width: win.modelData.width
                        height: win.modelData.height

                        // placeholder until a wallpaper loads: deliberately colourful so a missing wallpaper is obvious
                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "#2f6bff" }
                                GradientStop { position: 0.5; color: "#b44cff" }
                                GradientStop { position: 1.0; color: "#ff8a3d" }
                            }
                        }
                        Image {
                            anchors.fill: parent
                            visible: status === Image.Ready
                            onStatusChanged: console.log("[macdock-glass] wallpaper image status:", status, "(1 = ready, 2 = loading, 3 = error)", source)
                            source: root.fileUrl(root.wallpaperFor(win.modelData.name))
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: bd.width
                            smooth: true
                        }

                        ListModel { id: wm }
                        Repeater {
                            model: wm
                            delegate: Item {
                                id: gw
                                required property string addr
                                required property real wx
                                required property real wy
                                required property real ww
                                required property real wh
                                required property real wz
                                required property bool gone      // window closed: capture is released first, the item is swept shortly after
                                x: wx; y: wy; width: ww; height: wh; z: wz
                                readonly property var tl: { if (!root.hub || gone) return null; var t = root.hub.tlTick; return root.hub.tlFor(addr); }
                                // only keep capturing windows that actually reach the Dock (+ refraction margin)
                                // real-time: EVERY visible window stays captured (also while the Dock is tucked and for windows far from the Dock), so a window
                                // dragged over the Dock or a revealed Dock never starts from the bare wallpaper
                                readonly property bool nearNow: root.glassRT || (!ui.tucked
                                    && x < dock.x + dock.width + 48 && x + width > dock.x - 48
                                    && y < dock.y + bd.height - ui.height + dock.height + 48
                                    && y + height > dock.y + bd.height - ui.height - 48)
                                // a capture is only torn down 2.5 s after the window left the dock area: creating / destroying
                                // live window captures every time a window brushes past the dock is what the compositor can choke on
                                property bool near: false
                                onNearNowChanged: { if (nearNow) { nearHold.stop(); near = true; } else nearHold.restart(); }
                                Component.onCompleted: near = nearNow
                                Timer { id: nearHold; interval: 2500; onTriggered: gw.near = gw.nearNow }
                                Loader {
                                    anchors.fill: parent
                                    active: gw.near && !gw.gone
                                    sourceComponent: ScreencopyView {
                                        id: sc
                                        captureSource: gw.tl
                                        live: !root.glassHold && (root.glassRT || !ui.tucked)
                                        onCaptureSourceChanged: { if (captureSource !== null && !live && !root.glassHold) firstShot.restart(); }
                                        Timer {
                                            id: firstShot
                                            interval: 90
                                            onTriggered: { if (sc.captureSource !== null && !sc.live && !root.glassHold && typeof sc.captureFrame === "function") sc.captureFrame(); }
                                        }
                                    }
                                }
                            }
                        }

                        function sync() {
                            var mon = null;
                            for (var i = 0; i < root.monData.length; i++)
                                if (root.monData[i].name === win.modelData.name) mon = root.monData[i];
                            if (!mon) return;
                            var ws = [mon.activeWorkspace ? mon.activeWorkspace.id : -999];
                            if (mon.specialWorkspace && mon.specialWorkspace.id !== 0) ws.push(mon.specialWorkspace.id);
                            var zoneTop = bd.height - win.height;
                            var want = {};
                            var cs = root.glassClients;
                            for (var c = 0; c < cs.length; c++) {
                                var cl = cs[c];
                                if (!cl.mapped || cl.hidden || cl.monitor !== mon.id || ws.indexOf(cl.workspace.id) < 0) continue;
                                var x = cl.at[0] - mon.x, y = cl.at[1] - mon.y, w = cl.size[0], h = cl.size[1];
                                if (x + w <= 0 || x >= bd.width || y + h <= zoneTop || y >= bd.height) continue;
                                var z = cl.floating ? 100 - Math.min(cl.focusHistoryID, 90) : 0;   // floating on top, most recently focused highest
                                want[cl.address] = { addr: cl.address, wx: x, wy: y, ww: w, wh: h, wz: z, gone: false };
                            }
                            for (var j = wm.count - 1; j >= 0; j--) {
                                var a = wm.get(j).addr;
                                if (want[a] === undefined) { if (!wm.get(j).gone) { wm.setProperty(j, "gone", true); sweep.restart(); } }
                                else { wm.set(j, want[a]); delete want[a]; }
                            }
                            for (var k in want) wm.append(want[k]);
                            bd.lastCount = wm.count;
                        }
                        Timer {
                            id: sweep
                            interval: 600
                            onTriggered: { for (var q = wm.count - 1; q >= 0; q--) if (wm.get(q).gone) wm.remove(q); bd.lastCount = wm.count; }
                        }
                        property int lastCount: -1
                        Connections {
                            target: root
                            function onGlassClientsChanged() { bd.sync(); }
                            function onMonDataChanged() { bd.sync(); }
                        }
                        Component.onCompleted: sync()
                    }
                }

                Item {
                    id: maskItem
                    x: ui.menuOpen ? 0 : dock.x
                    width: ui.menuOpen ? ui.width : dock.width
                    y: ui.menuOpen ? 0 : (ui.tucked ? ui.height - 3 : (hh.hovered ? ui.activeTop : dock.y))
                    height: ui.height - y
                }

                Item {
                    id: dock
                    width: row.width + root.hPad * 2
                    height: root.bgHeight
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: ui.height - root.margin - height + (ui.tucked ? height + root.margin + 6 : 0)
                    Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                    // ── Apple Liquid Glass: real-time refraction of the backdrop (see liquidglass.frag) ──
                    Loader {
                        id: glassLayer
                        anchors.fill: parent
                        active: root.liquidActive
                        sourceComponent: Item {
                            id: dg
                            // blurring at half resolution is visually identical for radii >= 8 px and costs a quarter of the GPU work
                            readonly property real ds: root.glassBlur >= 8 ? 0.5 : 1.0
                            readonly property real bn: root.glassBlur * 1.4 * ds / 64.0
                            readonly property real margin: 72      // extra backdrop captured around the Dock (refraction + blur reach)
                            readonly property real padPx: 10       // shader item padding (drop shadow)
                            ShaderEffectSource {
                                id: bsrc
                                sourceItem: glassBackdrop.item
                                hideSource: true
                                live: !ui.tucked
                                visible: false
                                sourceRect: Qt.rect(dock.x - parent.padPx - parent.margin,
                                                    dock.y + (win.modelData.height - ui.height) - parent.padPx - parent.margin,
                                                    dock.width + 2 * (parent.padPx + parent.margin),
                                                    dock.height + 2 * (parent.padPx + parent.margin))
                                textureSize: Qt.size(Math.max(1, Math.round(sourceRect.width * dg.ds)), Math.max(1, Math.round(sourceRect.height * dg.ds)))
                            }
                            MultiEffect {
                                id: bblurFx
                                source: bsrc
                                width: bsrc.sourceRect.width * dg.ds; height: bsrc.sourceRect.height * dg.ds
                                blurEnabled: true
                                blurMax: 64
                                blur: Math.min(1.0, dg.bn)
                                autoPaddingEnabled: false
                                visible: false
                            }
                            // real Gaussian pre-blur of the backdrop (Qt MultiEffect): the glass shader refracts THIS texture,
                            // so there are no sampled copies of the background any more
                            ShaderEffectSource {
                                id: bblur
                                sourceItem: bblurFx
                                live: !ui.tucked
                                visible: false
                            }
                            MultiEffect {
                                id: bblur2Fx
                                source: bblur
                                width: bsrc.sourceRect.width * dg.ds; height: bsrc.sourceRect.height * dg.ds
                                blurEnabled: dg.bn > 1.0
                                blurMax: 64
                                blur: Math.max(0.0, Math.min(1.0, dg.bn - 1.0))
                                autoPaddingEnabled: false
                                visible: false
                            }
                            // second Gaussian pass: only active when the slider goes past a single pass's 64 px limit
                            ShaderEffectSource {
                                id: bblur2
                                // the 2nd pass is a pure copy unless the blur radius exceeds one pass: skip it then (same pixels, one GPU pass less)
                                sourceItem: dg.bn > 1.0 ? bblur2Fx : null
                                live: !ui.tucked
                                visible: false
                            }
                            ShaderEffect {
                                id: glassFx
                                x: -padPx; y: -padPx
                                width: dock.width + 2 * padPx
                                height: dock.height + 2 * padPx
                                fragmentShader: root.glassShaderUrl
                                onStatusChanged: {
                                    console.log("[macdock-glass] shader status:", status, "(0 = compiled, 1 = uncompiled, 2 = error)", log);
                                    if (status === ShaderEffect.Error) root.glassState = "failed";
                                }

                                property variant src: dg.bn > 1.0 ? bblur2 : bblur
                                property real padPx: parent.padPx
                                property vector2d itemSize: Qt.vector2d(width, height)
                                property vector2d glassSize: Qt.vector2d(dock.width, dock.height)
                                property vector2d srcSize: Qt.vector2d(bsrc.sourceRect.width, bsrc.sourceRect.height)
                                property vector2d srcOffset: Qt.vector2d(parent.margin, parent.margin)
                                property real pad: padPx
                                property real radius: root.cornerRadius
                                property real bezel: Math.min(dock.height * 0.36, 26)
                                property real thickness: 30 * root.glassLiquid
                                property real dispersion: 0.06 * root.glassLiquid
                                property real magnify: 0.08 * root.glassLiquid
                                property real rim: root.glassRim
                                property real grain: root.glassGrain
                                property real blurPx: 1.5            // tiny residual smoothing; the real blur is the MultiEffect pre-pass
                                property real tintMix: root.glassOpacity * 0.55
                                property real saturation: 1.25
                                property real dark: root.darkMode ? 1 : 0
                                property real debug: root.glassDebug ? 1 : 0
                                property real shadowAmt: 1
                            }
                        }
                    }

                    Rectangle {
                        visible: !root.liquidActive
                        anchors.fill: parent
                        radius: root.cornerRadius
                        color: root.darkMode ? Qt.rgba(0.10, 0.10, 0.11, root.glassOpacity)
                                             : Qt.rgba(1, 1, 1, root.glassOpacity * 0.55)
                        border.width: 1
                        border.color: root.darkMode ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(0, 0, 0, 0.12)

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: parent.radius - 1
                            color: "transparent"
                            border.width: 1
                            border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.45)
                        }
                    }

                    Row {
                        id: row
                        spacing: root.spacing
                        height: root.iconSize
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: root.bottomPad

                        Repeater {
                            id: rep
                            model: root.items

                            delegate: Item {
                                id: cell
                                required property var modelData
                                required property int index
                                readonly property bool isSep: modelData.kind === "sep"
                                readonly property bool canDrag: !isSep && modelData.pinned === true && !modelData.special
                                readonly property bool isDragged: ui.dragging && modelData.key === ui.dragKey

                                // app cells always show their plain icon; only window cells show a live preview
                                // (with the app's icon as a badge), grouped next to the Trash
                                readonly property var thumbWin: (!isSep && modelData.kind === "win") ? modelData.tl : null
                                readonly property bool useThumb: thumbWin !== null
                                readonly property bool thumbReady: useThumb && (sv.hasContent === undefined || sv.hasContent === true)

                                property real dx: {
                                    if (!ui.dragging || isSep) return 0;
                                    if (isDragged) return ui.dragDelta;
                                    return ui.shiftFor(index);
                                }
                                Behavior on dx {
                                    enabled: !cell.isDragged
                                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                                }
                                transform: Translate { x: cell.dx }
                                z: isDragged ? 100 : 0
                                opacity: isDragged ? 0.92 : 1

                                property real appear: modelData.fresh ? 0 : 1
                                Behavior on appear { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                                Component.onCompleted: Qt.callLater(function () { cell.appear = 1; })

                                readonly property real c0: modelData.nA * (root.iconSize + root.spacing)
                                                           + modelData.nS * (root.sepWidth + root.spacing)
                                                           + (isSep ? root.sepWidth : root.iconSize) / 2
                                readonly property real s: {
                                    if (isSep) return 1;
                                    var dist = Math.abs(ui.mx - ui.refLeft - cell.c0);
                                    var R = root.magRadius;
                                    var f = dist < R ? 0.5 * (1 + Math.cos(Math.PI * dist / R)) : 0;
                                    return 1 + (root.effMag - 1) * f * ui.strength;
                                }

                                width: isSep ? root.sepWidth : root.iconSize * s * appear
                                height: root.iconSize

                                Rectangle {
                                    visible: cell.isSep
                                    width: 1
                                    height: root.iconSize * 0.85
                                    anchors.centerIn: parent
                                    color: root.darkMode ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(0, 0, 0, 0.22)
                                }

                                Image {
                                    id: img
                                    visible: false
                                    property real lift: 0
                                    width: root.iconSize * cell.s * cell.appear
                                    height: width
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: lift
                                    source: cell.isSep ? "" : root.cellIconSrc(cell.modelData)
                                    sourceSize: Qt.size(Math.ceil(root.iconSize * root.magnification * 1.25),
                                                        Math.ceil(root.iconSize * root.magnification * 1.25))
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                    asynchronous: true
                                }
                                MultiEffect {
                                    visible: !cell.isSep && !cell.thumbReady
                                    source: img
                                    anchors.fill: img
                                    shadowEnabled: true
                                    shadowColor: "black"
                                    shadowOpacity: 0.32
                                    shadowBlur: 0.55
                                    shadowVerticalOffset: 3
                                    brightness: ma.pressed ? -0.3 : 0.0
                                }

                                // ── window thumbnail (same box as the icon, so magnification just works) ──
                                Item {
                                    id: th
                                    anchors.fill: img
                                    // kept (almost) opaque while loading so the capture isn't paused by the renderer
                                    visible: cell.useThumb
                                    opacity: cell.thumbReady ? 1 : 0.01

                                    Rectangle {      // soft drop shadow
                                        x: sv.x
                                        y: sv.y + 3
                                        width: sv.width
                                        height: sv.height
                                        radius: 5
                                        color: Qt.rgba(0, 0, 0, 0.32)
                                    }
                                    ScreencopyView {
                                        id: sv
                                        anchors.centerIn: parent
                                        captureSource: root.captureCut ? null : cell.thumbWin
                                        live: !ui.tucked && !root.captureHold          // only keep capturing while the dock is on screen
                                        readonly property real ar: (implicitWidth > 0 && implicitHeight > 0)
                                                                   ? implicitWidth / implicitHeight : 4 / 3
                                        width: Math.min(th.width, th.height * ar)
                                        height: width / ar
                                    }
                                    Rectangle {      // thin frame + pressed dimming
                                        anchors.fill: sv
                                        radius: 3
                                        color: ma.pressed ? Qt.rgba(0, 0, 0, 0.3) : "transparent"
                                        border.width: 1
                                        border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(0, 0, 0, 0.28)
                                    }
                                }
                                // small app icon in the corner, so you can tell which app the window belongs to
                                Image {
                                    id: badge
                                    visible: cell.thumbReady
                                    width: img.width * 0.46
                                    height: width
                                    x: img.x + img.width - width + 3
                                    y: img.y + img.height - height + 3
                                    source: img.source
                                    sourceSize: Qt.size(Math.ceil(root.iconSize * root.magnification * 0.6),
                                                        Math.ceil(root.iconSize * root.magnification * 0.6))
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                }

                                Rectangle {
                                    visible: !cell.isSep && cell.modelData.running && root.showIndicators
                                    width: 4; height: 4; radius: 2
                                    color: root.darkMode ? Qt.rgba(1, 1, 1, 0.85) : Qt.rgba(0, 0, 0, 0.6)
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: cell.height + 3
                                }

                                SequentialAnimation {
                                    running: !cell.isSep && root.bounceOnLaunch && root.launching[cell.modelData.key] !== undefined
                                    loops: Animation.Infinite
                                    NumberAnimation { target: img; property: "lift"; to: root.iconSize * 0.4
                                                      duration: 260; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: img; property: "lift"; to: 0
                                                      duration: 260; easing.type: Easing.InQuad }
                                    onRunningChanged: if (!running) img.lift = 0
                                }

                                Rectangle {
                                    id: tip
                                    visible: opacity > 0
                                    opacity: (root.showLabels && !cell.isSep && ma.containsMouse && !ma.pressed && !ui.menuOpen && !ui.dragging) ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                    z: 10
                                    width: label.implicitWidth + 22
                                    height: label.implicitHeight + 10
                                    radius: 8
                                    color: Qt.rgba(0.12, 0.12, 0.13, 0.72)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.12)
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: cell.height - img.height - img.lift - height - 10

                                    Text {
                                        id: label
                                        anchors.centerIn: parent
                                        text: cell.isSep ? "" : ((cell.modelData.kind === "win" && cell.modelData.tl && cell.modelData.tl.title) ? cell.modelData.tl.title : cell.modelData.name)
                                        color: "white"
                                        font.pixelSize: 13
                                        font.family: root.fontFamily
                                    }
                                }

                                MouseArea {
                                    id: ma
                                    visible: !cell.isSep
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: -root.bottomPad
                                    width: cell.width
                                    height: img.height + root.bottomPad
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                                    property real pressX: 0

                                    onPressed: mouse => {
                                        if (mouse.button === Qt.LeftButton)
                                            pressX = ma.mapToItem(ui, mouse.x, 0).x;
                                    }
                                    onPositionChanged: mouse => {
                                        if (!cell.canDrag || !(pressedButtons & Qt.LeftButton)) return;
                                        var ax = ma.mapToItem(ui, mouse.x, 0).x;
                                        if (!ui.dragging) {
                                            if (Math.abs(ax - pressX) < 8) return;
                                            ui.beginDrag(cell.index, cell.modelData.key, pressX, cell.width + root.spacing);
                                        }
                                        if (cell.isDragged) ui.dragUpdate(ax);
                                    }
                                    onReleased: mouse => {
                                        if (ui.dragging && cell.isDragged) ui.endDrag();
                                    }
                                    onClicked: mouse => {
                                        if (ui.justDragged) return;
                                        if (mouse.button === Qt.RightButton) {
                                            ui.menuCx = cell.mapToItem(ui, cell.width / 2, 0).x;
                                            ui.menuModel = root.menuFor(cell.modelData);
                                            ui.menuItem = cell.modelData;
                                        } else {
                                            root.activate(cell.modelData, mouse.button === Qt.MiddleButton);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    z: 50
                    visible: ui.menuOpen
                    enabled: ui.menuOpen
                    acceptedButtons: Qt.AllButtons
                    onPressed: ui.menuItem = null
                }

                Rectangle {
                    id: menu
                    z: 60
                    visible: opacity > 0
                    opacity: ui.menuOpen ? 1 : 0
                    scale: ui.menuOpen ? 1 : 0.96
                    transformOrigin: Item.Bottom
                    Behavior on opacity { NumberAnimation { duration: 110 } }
                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                    width: 230
                    height: menuCol.height + 10
                    x: Math.max(8, Math.min(ui.width - width - 8, ui.menuCx - width / 2))
                    y: ui.height - root.margin - root.bgHeight - root.iconSize * (root.effMag - 1) - 14 - height
                    radius: 10
                    color: Qt.rgba(0.14, 0.14, 0.15, 0.62)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.16)

                    Column {
                        id: menuCol
                        x: 5
                        y: 5
                        width: parent.width - 10

                        Repeater {
                            model: ui.menuModel

                            delegate: Item {
                                id: mi
                                required property var modelData
                                readonly property bool isSep: modelData.kind === "sep"
                                readonly property bool off: !isSep && modelData.disabled === true
                                readonly property bool armedNow: !isSep && modelData.confirm === true && ui.armed === modelData.label
                                width: menuCol.width
                                height: isSep ? 9 : 26

                                Rectangle {
                                    visible: mi.isSep
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 6
                                    width: parent.width - 12
                                    height: 1
                                    color: Qt.rgba(1, 1, 1, 0.14)
                                }
                                Rectangle {
                                    visible: !mi.isSep && !mi.off && mia.containsMouse
                                    anchors.fill: parent
                                    radius: 5
                                    color: mi.armedNow ? "#FF453A" : root.accent
                                }
                                Text {
                                    visible: !mi.isSep
                                    x: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 20
                                    elide: Text.ElideRight
                                    text: mi.isSep ? "" : (mi.armedNow ? "Click again to confirm" : mi.modelData.label)
                                    color: mi.off ? Qt.rgba(1, 1, 1, 0.4) : "white"
                                    font.pixelSize: 13
                                    font.family: root.fontFamily
                                }
                                MouseArea {
                                    id: mia
                                    anchors.fill: parent
                                    enabled: !mi.isSep && !mi.off
                                    hoverEnabled: true
                                    onContainsMouseChanged: if (!containsMouse && ui.armed === mi.modelData.label) ui.armed = ""
                                    onClicked: {
                                        if (mi.modelData.confirm === true && ui.armed !== mi.modelData.label) { ui.armed = mi.modelData.label; return; }
                                        var run = mi.modelData.run;
                                        ui.menuItem = null;
                                        if (run) run();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
