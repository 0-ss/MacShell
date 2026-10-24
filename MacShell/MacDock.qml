// macdock v2 — a macOS-style dock for Hyprland, built on Quickshell. vSuol
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
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import "I18n.js" as I18n
import "Fonts.js" as Fonts

Scope {
    id: root

    // shared helpers from shell.qml (window geometry poller, wallpaper lookup)
    property var hub: null
    property bool dockEnabled: true      // false = no Dock at all (settings window stays available)
    property bool settingsEnabled: true  // false = keep the System Settings window closed
    property var bar: hub ? hub.bar : null
    Connections {
        target: root.bar
        function onDarkModeChanged() {
            if (root.darkMode !== root.bar.darkMode) root.darkMode = root.bar.darkMode;
        }
        function onAppearanceModeChanged() {
            if (root.appearanceMode !== root.bar.appearanceMode) root.appearanceMode = root.bar.appearanceMode;
        }
    }
    property string userName: Quickshell.env("USER") || ""

    // ═════ Displays: main display + resolution / refresh, with a macOS-style "keep or revert" safety net ═════
    property var displays: ({ primary: "", modes: {} })      // saved in ~/.config/macshell/displays.json
    property var monList: []                                  // hyprctl monitors (live)
    property string pendingOut: ""                            // a mode change waiting for "Keep"
    property string pendingPrev: ""
    property int revertLeft: 0
    FileView {
        id: dispFile
        path: Quickshell.env("HOME") + "/.config/macshell/displays.json"
        printErrors: false
        onLoaded: { try { root.displays = JSON.parse(text()); } catch (e) {} root.applySavedModes(); }
    }
    function saveDisplays() { dispFile.setText(JSON.stringify(root.displays, null, 2)); }
    function refreshMons() { if (!monListProc.running) monListProc.running = true; }
    Process {
        id: monListProc
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector { onStreamFinished: { try { root.monList = JSON.parse(text); } catch (e) {} } }
    }
    function modeOf(m) { return m.width + "x" + m.height + "@" + Number(m.refreshRate).toFixed(2); }
    function applyMode(out, mode) {
        var m = null;
        for (var i = 0; i < monList.length; i++) if (monList[i].name === out) m = monList[i];
        var pos = m ? (m.x + "x" + m.y) : "auto", sc = m ? m.scale : 1;
        Quickshell.execDetached(["hyprctl", "eval", "hl.monitor({ output = \"" + out + "\", mode = \"" + mode + "\", position = \"" + pos + "\", scale = " + sc + " })"]);
        monRefreshSoon.restart();
    }
    Timer { id: monRefreshSoon; interval: 700; onTriggered: root.refreshMons() }
    // change a monitor's mode; it reverts by itself after 15 s unless kept
    function tryMode(out, mode) {
        var m = null;
        for (var i = 0; i < monList.length; i++) if (monList[i].name === out) m = monList[i];
        if (!m) return;
        if (pendingOut === "") pendingPrev = modeOf(m);
        pendingOut = out;
        applyMode(out, mode);
        pendingMode = mode;
        revertLeft = 15;
        revertTimer.restart();
    }
    property string pendingMode: ""
    Timer {
        id: revertTimer; interval: 1000; repeat: true
        onTriggered: { root.revertLeft--; if (root.revertLeft <= 0) root.revertMode(); }
    }
    function keepMode() {
        revertTimer.stop();
        var d = displays, mm = {}; for (var k in d.modes) mm[k] = d.modes[k];
        mm[pendingOut] = pendingMode;
        displays = { primary: d.primary || "", modes: mm };
        saveDisplays();
        pendingOut = ""; pendingMode = "";
    }
    function revertMode() {
        revertTimer.stop();
        if (pendingOut !== "" && pendingPrev !== "") applyMode(pendingOut, pendingPrev);
        pendingOut = ""; pendingMode = "";
    }
    function applySavedModes() {
        var mm = displays.modes || {};
        for (var k in mm) Quickshell.execDetached(["hyprctl", "eval", "hl.monitor({ output = \"" + k + "\", mode = \"" + mm[k] + "\", position = \"auto\", scale = 1 })"]);
        if (displays.primary) root.monitorPrimary = displays.primary;
        refreshMons();
    }
    property string monitorPrimary: ""
    function setPrimary(name) {
        var d = displays;
        displays = { primary: name, modes: d.modes || {} };
        saveDisplays();
        monitorPrimary = name;
        root.monitor = name;                                         // the Dock lives on the main display
    }
    Process {
        running: true
        command: ["sh", "-c", "n=$(getent passwd \"$USER\" | cut -d: -f5 | cut -d, -f1); printf '%s' \"${n:-$USER}\""]
        stdout: StdioCollector { onStreamFinished: if (text.trim() !== "") root.userName = text.trim() }
    }
    readonly property bool captureCut: hub ? hub.captureCut : false
    readonly property bool glassHold: hub ? hub.glassHold : false          // windows opening / closing: the glass's live captures pause, source stays attached
    readonly property bool previewHold: hub ? hub.previewHold : false
    readonly property bool captureHold: hub ? hub.captureHold : false     // windows opening / closing: the dock PREVIEW capture stops (source released 0.5 s later); the glass is not affected
    // appearance values shared by Dock and Menu Bar
    function setLook(k, v) { root[k] = v; if (bar) bar[k] = v; }
    // Appearance: the Menu Bar resolves "auto" (light by day, dark by night) and keeps both windows in step
    function setAppearance(mode) {
        if (["light", "dark", "auto"].indexOf(mode) < 0) return;
        appearanceMode = mode;
        if (mode === "auto") {
            var h = new Date().getHours();
            darkMode = bar && bar.autoIsDark ? bar.autoIsDark() : (h < 7 || h >= 19);
        } else darkMode = mode === "dark";
        // Update this window first so its palette reacts immediately, then keep the Menu Bar in sync.
        if (bar && bar.setAppearance) {
            bar.setAppearance(mode);
            appearanceMode = mode;
            darkMode = bar.darkMode;
        }
    }

    // ───────────── CONFIG ───────────── Lachowski
    property string monitor: ""          // "" = every monitor, or e.g. "DP-1"
    property int iconSize: 52
    property real magnification: 1.7     // peak icon scale
    property int spacing: 6
    property int hPad: 10
    property int topPad: 8
    property int bottomPad: 9            // room under icons (running dots live here)
    property int cornerRadius: 18
    readonly property real uiS: bar ? bar.uiScale : 1      // UI scale (Settings → Menu Bar): Settings / About windows follow it
    property int margin: 6
    property bool darkMode: true
    // the dock keeps one fixed look (dark): switching the system between Light and Dark does not change its colours
    readonly property bool dockDark: true
    property string appearanceMode: "dark"      // light | dark | auto (kept in step with the Menu Bar, see setAppearance)
    property string dockStyle: "blur"   // "blur" = Normal Blur, "liquid" = Apple Liquid Glass
    // Liquid Glass tuning (settings.json): rim = edge highlight, grain = noise, liquid = refraction depth
    property real glassRim: 0.45
    property real glassGrain: 0.03
    property real glassLiquid: 1.0
    // The Dock's own real-time switch (Dock Preferences -> Appearance). It used to follow the Menu Bar's "Real-time glass" toggle, which is OFF by
    // default, so the Dock glass was a 15 fps, pause-while-windows-open snapshot unless that was found and switched on.
    property bool glassLive: true
    readonly property bool glassRT: glassLive
    property real glassBlur: 5            // Liquid Glass backdrop blur radius, px (settings slider)
    readonly property real dockBlurBoost: 8    // extra px of blur added on top of glassBlur for the Dock glass only
    property bool glassDebug: false       // settings.json only: draw the raw Liquid Glass backdrop texture
    property string wallpaperPath: ""    // optional override for the wallpaper the Liquid Glass refracts
    property real glassOpacity: 0.42     // 0 = fully clear; below the layerrule's ignore_alpha (0.2) the blur turns off
    // "smart"  = hide while a non-floating window is open on that monitor's workspace
    // "always" = always auto-hide, "never" = always visible and reserves space
    property string hideMode: "smart"
    property bool showTrash: true
    property string fontFamily: "Open Runde"  // bundled in assets/fonts (shell.qml loads it); falls back to the system font if missing
    readonly property string boldFontFamily: hub && hub.boldFontFamily ? hub.boldFontFamily : "Open Runde Semibold"
    // Open Runde: bold text uses its Semibold face; another selected font keeps its own family (and real bold weight)
    function fontForWeight(weight, regularFamily) { return (Number(weight) >= Font.DemiBold && regularFamily === "Open Runde") ? boldFontFamily : regularFamily; }
    onFontFamilyChanged: if (fontFamily.indexOf("Inter") === 0) fontFamily = "Open Runde"
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
    // Dock icon tint: every icon is re-coloured with one colour (works with any icon pack)
    property bool iconTint: false
    property string iconTintColor: "#0a84ff"
    property real iconTintStrength: 1.0
    readonly property var tintChoices: [
        { name: "Blue",     c: "#0a84ff" }, { name: "Purple", c: "#bf5af2" }, { name: "Pink",  c: "#ff375f" },
        { name: "Red",      c: "#ff453a" }, { name: "Orange", c: "#ff9f0a" }, { name: "Yellow", c: "#ffd60a" },
        { name: "Green",    c: "#30d158" }, { name: "Teal",   c: "#40c8e0" }, { name: "Graphite", c: "#8e8e93" },
        { name: "White",    c: "#ffffff" }, { name: "Black",  c: "#1c1c1e" }
    ]
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
                font.family: root.fontForWeight(font.weight, r.t.fam)
                font.pixelSize: 13
            }
            Text {
                visible: r.subtitle !== ""
                width: parent.width
                text: r.subtitle
                wrapMode: Text.WordWrap
                color: r.t.text2
                font.family: root.fontForWeight(font.weight, r.t.fam)
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
        font.family: root.fontForWeight(font.weight, t.fam)
        font.pixelSize: header ? 12 : 12
        font.weight: header ? Font.DemiBold : Font.Normal
    }

    // macOS toggle switch: capsule knob, draggable, fluid slide, the knob turns into Liquid Glass while held (see GlassSwitch.qml)
    component SSwitch: GlassSwitch {
        required property var t
        accentColor: "#30D158"
        offColor: t.switchOff
        knobColor: t.dark ? "#DCDDDA" : "white"
        dark: t.dark
        baseColor: t.dark ? "#2B2B2D" : "#FFFFFF"
        glass: root.settingsGlass
        shaderUrl: root.glassShaderUrl
        glassLiquid: root.glassLiquid
        glassRim: root.glassRim
        glassGrain: root.glassGrain
        glassTint: root.glassOpacity
        borderTint: root.bar ? root.bar.menuBorderColor : "#8A9AB5"
        onGlassFailed: root.glassState = "failed"
    }

    // slider: identical to the Control Center sliders (thin bar, knob on hover, Liquid Glass knob while held; see GlassSlider.qml)
    component SSlider: GlassSlider {
        required property var t
        fg: t.text
        fillColor: t.accent
        knobColor: "white"
        knobSize: 1.2
        pressGrow: 0.8
        trackColor: t.track
        labelColor: t.text2
        fontFamily: t.fam
        dark: t.dark
        baseColor: t.dark ? "#2B2B2D" : "#FFFFFF"
        glass: root.settingsGlass
        shaderUrl: root.glassShaderUrl
        glassLiquid: root.glassLiquid
        glassRim: root.glassRim
        glassGrain: root.glassGrain
        glassTint: root.glassOpacity
        borderTint: root.bar ? root.bar.menuBorderColor : "#8A9AB5"
        onGlassFailed: root.glassState = "failed"

        // "Reset to default": every settings slider can name its default (resetValue, in the slider's own from..to units).
        // The link shows under the track only while the value differs from it; clicking it sends the default through moved().
        property var resetValue: undefined
        readonly property bool canReset: resetValue !== undefined && Math.abs(value - Number(resetValue)) > Math.max(1e-6, Math.abs(to - from) * 0.004)
        height: (leftLabel !== "" || rightLabel !== "" || resetValue !== undefined) ? 40 : 22
        Text {
            id: resetLink
            visible: parent.resetValue !== undefined
            opacity: parent.canReset ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            x: (parent.width - width) / 2
            y: 25
            text: I18n.tr("Reset to default")
            color: parent.t.accent
            font.family: parent.t.fam
            font.pixelSize: 11
            MouseArea {
                anchors.fill: parent; anchors.margins: -5
                enabled: parent.parent.canReset
                cursorShape: Qt.PointingHandCursor
                onClicked: parent.parent.moved(Number(parent.parent.resetValue))
            }
        }
    }

    // macOS segmented control: capsule track, dividers between the options, and a marker that turns into Liquid Glass while it
    // slides to the chosen option (see GlassSegmented.qml)
    component SSegmented: GlassSegmented {
        required property var t
        segWidth: 72
        dark: t.dark
        textColor: t.text
        fontFamily: t.fam
        fontSize: 12
        trackColor: t.ctrl
        pillColor: t.ctrlSel
        baseColor: t.dark ? "#2B2B2D" : "#FFFFFF"
        glass: root.settingsGlass
        shaderUrl: root.glassShaderUrl
        glassLiquid: root.glassLiquid
        glassRim: root.glassRim
        glassGrain: root.glassGrain
        glassTint: root.glassOpacity
        borderTint: root.bar ? root.bar.menuBorderColor : "#8A9AB5"
        onGlassFailed: root.glassState = "failed"
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
            font.family: root.fontForWeight(font.weight, b.t.fam)
            font.pixelSize: 13
        }
        MouseArea { id: ma; anchors.fill: parent; onClicked: b.clicked() }
    }

    // Light / Dark appearance thumbnail
    component SThemeTile: Item {
        id: tile
        required property var t
        property bool dark: false
        property bool split: false            // Auto: left half light, right half dark
        property bool selected: false
        property string label: ""
        signal clicked()
        width: 84; height: 78
        readonly property bool leftDark: split ? false : dark
        // the little desktop picture (left half, or the whole tile)
        Item {
            width: 84; height: 56
            Rectangle { width: 84; height: 56; radius: 8; color: tile.leftDark ? "#141416" : "#D9DDE6" }
            Rectangle {   // mini window
                x: 14; y: 9
                width: 56; height: 32
                radius: 4
                color: tile.leftDark ? "#2C2C2E" : "#FFFFFF"
                Rectangle { x: 0; y: 0; width: 15; height: parent.height; radius: 4; color: tile.leftDark ? "#3A3A3C" : "#E9E9EE" }
                Rectangle { x: 20; y: 7;  width: 28; height: 3; radius: 1.5; color: tile.leftDark ? "#5A5A5E" : "#C8C8CE" }
                Rectangle { x: 20; y: 14; width: 20; height: 3; radius: 1.5; color: tile.leftDark ? "#48484A" : "#DADADF" }
                Rectangle { x: 20; y: 21; width: 24; height: 3; radius: 1.5; color: tile.leftDark ? "#48484A" : "#DADADF" }
            }
            Rectangle {   // mini dock
                x: 26; y: 46
                width: 32; height: 6
                radius: 3
                color: tile.leftDark ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.75)
            }
        }
        // Auto: the right half is the dark picture
        Item {
            visible: tile.split
            x: 42; width: 42; height: 56
            clip: true
            Item {
                x: -42; width: 84; height: 56
                Rectangle { width: 84; height: 56; radius: 8; color: true ? "#141416" : "#D9DDE6" }
                Rectangle {   // mini window
                    x: 14; y: 9
                    width: 56; height: 32
                    radius: 4
                    color: true ? "#2C2C2E" : "#FFFFFF"
                    Rectangle { x: 0; y: 0; width: 15; height: parent.height; radius: 4; color: true ? "#3A3A3C" : "#E9E9EE" }
                    Rectangle { x: 20; y: 7;  width: 28; height: 3; radius: 1.5; color: true ? "#5A5A5E" : "#C8C8CE" }
                    Rectangle { x: 20; y: 14; width: 20; height: 3; radius: 1.5; color: true ? "#48484A" : "#DADADF" }
                    Rectangle { x: 20; y: 21; width: 24; height: 3; radius: 1.5; color: true ? "#48484A" : "#DADADF" }
                }
                Rectangle {   // mini dock
                    x: 26; y: 46
                    width: 32; height: 6
                    radius: 3
                    color: true ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.75)
                }
            }
        }
        Rectangle {   // selection / outline ring
            width: 84; height: 56
            radius: 8
            color: "transparent"
            border.width: tile.selected ? 3 : 1
            border.color: tile.selected ? tile.t.accent : tile.t.sep
        }
        Text {
            y: 60
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr(tile.label)
            color: tile.t.text
            font.family: root.fontForWeight(font.weight, tile.t.fam)
            font.pixelSize: 12
        }
        MouseArea { anchors.fill: parent; onClicked: tile.clicked() }
    }

    // Colored rounded-square sidebar icon with a tiny drawn glyph
    component SGlyph: Rectangle {
        id: gl
        property string kind: ""
        property string fam: "Open Runde"   // the selected UI font (set by the sidebar)
        property string wg: ""          // a menu-bar glyph (WGlyph.qml) instead of the hand-drawn kinds below
        property color c1: "#4FA8FF"
        property color c2: "#0A6CFF"
        width: 24; height: 24; radius: 6
        gradient: Gradient {
            GradientStop { position: 0.0; color: gl.c1 }
            GradientStop { position: 1.0; color: gl.c2 }
        }
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.14)

        WGlyph { visible: gl.wg !== ""; anchors.centerIn: parent; width: 16; height: 16; kind: gl.wg; color: "white" }
        Item {
            anchors.centerIn: parent
            width: 16; height: 16
            visible: gl.wg === ""

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
            // widgets (three tiles and an empty slot)
            Item {
                visible: gl.kind === "widgets"; anchors.fill: parent
                Rectangle { x: 1.5; y: 1.5; width: 5.6; height: 5.6; radius: 1.6; color: "white" }
                Rectangle { x: 8.9; y: 1.5; width: 5.6; height: 5.6; radius: 1.6; color: "white" }
                Rectangle { x: 1.5; y: 8.9; width: 5.6; height: 5.6; radius: 1.6; color: "white" }
                Rectangle { x: 8.9; y: 8.9; width: 5.6; height: 5.6; radius: 1.6; color: "transparent"; border.width: 1.2; border.color: "white" }
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
            // wallpaper (picture with a sun and hills)
            Item {
                visible: gl.kind === "wallpaper"; anchors.fill: parent
                Rectangle {
                    x: 1; y: 2.5; width: 14; height: 11; radius: 2
                    color: "transparent"; border.width: 1.5; border.color: "white"
                }
                Rectangle { x: 9.5; y: 4.6; width: 2.8; height: 2.8; radius: 1.4; color: "white" }
                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var c = getContext("2d"); c.reset(); c.fillStyle = "white";
                        c.beginPath(); c.moveTo(2.5, 12.5); c.lineTo(6.2, 7.6); c.lineTo(9.2, 11); c.lineTo(10.8, 9.4); c.lineTo(13.5, 12.5); c.closePath(); c.fill();
                    }
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
                    font.family: Fonts.forWeight(font.weight, gl.fam); font.pixelSize: 10
                    font.bold: true
                }
            }
        }
    }

    // ─────────────────────────── THE WINDOW ───────────────────────────
    Window {
        id: prefsWindow
        title: "macshell Settings"
        // NOT bindings: a bound size gets re-applied by Qt and snaps the window back while it is being resized by hand.
        // The size is set once when the window opens and again only when the UI scale itself changes (see below).
        width: 800
        height: 880
        minimumWidth: 400
        minimumHeight: 300
        visible: false
        color: "transparent"
        flags: Qt.Window | Qt.FramelessWindowHint

        // where this window sits on its monitor, for the glass sidebar's backdrop
        QtObject {
            id: prefsGlassGeo
            readonly property var g: {
                var cs = root.glassClients || [], ms = root.hub ? (root.hub.monData || []) : [];
                for (var i = 0; i < cs.length; i++) {
                    var c = cs[i];
                    if (c.title !== prefsWindow.title || !c.mapped) continue;
                    for (var j = 0; j < ms.length; j++) {
                        var mm = ms[j];
                        if (mm.id !== c.monitor) continue;
                        var sc = mm.scale || 1;
                        return { x: c.at[0] - mm.x, y: c.at[1] - mm.y, mw: mm.width / sc, mh: mm.height / sc, mon: mm.name };
                    }
                }
                return null;
            }
            readonly property bool ok: g !== null
            // the window content is drawn scaled by the UI scale, so these are expressed in that scaled coordinate space
            readonly property real x: ok ? g.x / root.uiS : 0
            readonly property real y: ok ? g.y / root.uiS : 0
            readonly property real mw: ok ? g.mw / root.uiS : 1
            readonly property real mh: ok ? g.mh / root.uiS : 1
            readonly property string mon: ok ? g.mon : ""
        }

        // ── navigation state ──
        property int cur: 0
        property var backStack: []
        property var fwdStack: []
        property string query: ""

        // grouped like macOS System Settings (sec = sidebar section; a gap is drawn between sections)
        readonly property var panes: [
            // 1 · Connectivity
            { id: "wifi",       sec: 1, name: "Wi-Fi",           wg: "wifi",       c1: "#3D9BFF", c2: "#0A6CFF", keys: "wireless network internet ssid join" },
            { id: "bluetooth",  sec: 1, name: "Bluetooth",       wg: "bluetooth",  c1: "#3D9BFF", c2: "#0A6CFF", keys: "devices pair headphones mouse keyboard" },
            { id: "network",    sec: 1, name: "Network",         wg: "ethernet",   c1: "#3D9BFF", c2: "#0A6CFF", keys: "ethernet ip address vpn tailscale connection" },
            // 2 · System
            { id: "general",    sec: 2, name: "General",         glyph: "behavior", c1: "#8E8E93", c2: "#636366", keys: "language shell enable disable dock menu bar panel show hide off on" },
            { id: "appearance", sec: 2, name: "Appearance",      glyph: "appearance", c1: "#3A3A3C", c2: "#1C1C1E", keys: "theme dark light auto mode accent color glass liquid apple style blur font spotlight top bar menus" },
            { id: "wallpaper",  sec: 2, name: "Wallpaper",       glyph: "wallpaper", c1: "#5AC8FA", c2: "#007AFF", keys: "wallpaper background picture image video animated live motion desktop dynamic" },
            { id: "displays",   sec: 2, name: "Displays",        wg: "sun",        c1: "#3D9BFF", c2: "#0A6CFF", keys: "brightness night shift monitor resolution refresh scale" },
            { id: "battery",    sec: 2, name: "Battery",         wg: "bolt",       c1: "#4CD964", c2: "#28A745", keys: "power energy charge profile performance game mode gaming fullscreen" },
            // 3 · Desktop
            { id: "dock",       sec: 3, name: "Desktop & Dock",  glyph: "dock",     c1: "#2C2C2E", c2: "#1C1C1E", keys: "size icon magnification zoom spacing margin distance corner radius round square edge hide auto labels indicators bounce trash monitor preview app switcher alt tab" },
            { id: "menubar",    sec: 3, name: "Menu Bar",        glyph: "menubar",  c1: "#3D9BFF", c2: "#0A6CFF", keys: "panel bar height clock date seconds 24 hour battery tray search spotlight week monday style liquid bluetooth screenshots" },
            { id: "controlcenter", sec: 3, name: "Control Center", wg: "cc",       c1: "#8E8E93", c2: "#636366", keys: "modules tiles controls" },
            { id: "widgets",    sec: 3, name: "Widgets",         glyph: "widgets",  c1: "#FF9F0A", c2: "#FF7A00", keys: "desktop widgets weather clock calendar player image photo add remove arrange edit size temperature fahrenheit celsius city location" },
            // 4 · Notifications & Sound
            { id: "notifications", sec: 4, name: "Notifications", wg: "bell",      c1: "#FF5E57", c2: "#E8342A", keys: "alerts banners popups do not disturb screenshot" },
            { id: "sound",      sec: 4, name: "Sound",           wg: "speaker",    c1: "#FF5E7E", c2: "#E8344F", keys: "volume output input microphone speakers headphones effects ui sounds" },
            { id: "focus",      sec: 4, name: "Focus",           wg: "moon",       c1: "#7D7AFF", c2: "#5856D6", keys: "do not disturb keep awake sleep" },
            // 5 · Security & Accounts
            { id: "lockscreen", sec: 5, name: "Lock Screen",     wg: "lock",       c1: "#3A3A3C", c2: "#1C1C1E", keys: "lock password album lyrics media clock" },
            { id: "users",      sec: 5, name: "Users & Groups",  wg: "smile",      c1: "#3D9BFF", c2: "#0A6CFF", keys: "account user name picture avatar" },
            // 6 · Input
            { id: "keyboard",   sec: 6, name: "Keyboard",        wg: "keyboard",   c1: "#A7A7AD", c2: "#7C7C82", keys: "repeat rate delay layout typing" },
            { id: "mouse",      sec: 6, name: "Mouse",           wg: "mouse",      c1: "#A7A7AD", c2: "#7C7C82", keys: "tracking speed scroll natural" },
            { id: "trackpad",   sec: 6, name: "Trackpad",        wg: "trackpad",   c1: "#A7A7AD", c2: "#7C7C82", keys: "tap click natural scroll touchpad gestures" },
            // 7 · Apps & About
            { id: "apps",       sec: 7, name: "Applications",    glyph: "apps",     c1: "#FFB340", c2: "#FF9500", keys: "pinned apps keep remove reset dock" },
            { id: "about",      sec: 7, name: "About",           glyph: "about",    c1: "#A7A7AD", c2: "#7C7C82", keys: "version reset config folder macdock macbar macshell" }
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

        // Settings always opens as a floating, centred window (no windowrule needed in hyprland.conf)
        onVisibleChanged: if (visible) { if (root.bar) { root.bar.updateDialogOpen = root.bar.updateState === "available"; root.bar.checkForUpdates(true); } showNormal(); applyScaledSize(); floatTries = 0; floatTimer.restart(); if (root.glassState === "idle") root.startGlass(); }
        property int floatTries: 0
        readonly property int preferredWidth: Math.round(800 * root.uiS)
        readonly property int preferredHeight: Math.round(880 * root.uiS)
        // the UI scale changed while the window is open: Hyprland keeps the old floating size (and its blur / shadow region), so
        // tell it the new size again
        // ── resize that only applies when you let go ──
        // The edge handles no longer start the compositor's live resize: they remember where the drag began, and when the button is
        // released the window is resized once, to the size the drag ended at (left / top edges also move the window so the opposite
        // edge stays put).
        property var rs: null
        function rsBegin(edges, p) { rs = { e: edges, x: p.x, y: p.y, w: width, h: height }; }
        function rsEnd(p) {
            if (!rs) return;
            var e = rs.e, dx = p.x - rs.x, dy = p.y - rs.y;
            rs = null;
            var minW = Math.round(560 * root.uiS), minH = Math.round(380 * root.uiS);
            var nw = width, nh = height;
            if (e & Qt.RightEdge)  nw = width + dx;
            if (e & Qt.LeftEdge)   nw = width - dx;
            if (e & Qt.BottomEdge) nh = height + dy;
            if (e & Qt.TopEdge)    nh = height - dy;
            nw = Math.max(minW, Math.round(nw)); nh = Math.max(minH, Math.round(nh));
            console.log('[macshell-settings] resize on release:', width + 'x' + height, '->', nw + 'x' + nh);
            if (nw === width && nh === height) return;
            var sel = 'window = "title:^(' + title + ')$"';
            // current position (left / top edges keep the opposite edge fixed by moving the window as well)
            var ox = null, oy = null, cs = root.glassClients || [];
            for (var i = 0; i < cs.length; i++) if (cs[i].title === title && cs[i].mapped) { ox = cs[i].at[0]; oy = cs[i].at[1]; break; }
            Hyprland.dispatch('hl.dsp.window.resize({ x = ' + nw + ', y = ' + nh + ', "exact", ' + sel + ' })');
            if (ox !== null && ((e & Qt.LeftEdge) || (e & Qt.TopEdge))) {
                var nx = (e & Qt.LeftEdge) ? ox + (width - nw) : ox;
                var ny = (e & Qt.TopEdge) ? oy + (height - nh) : oy;
                Hyprland.dispatch('hl.dsp.window.move({ x = ' + nx + ', y = ' + ny + ', ' + sel + ' })');
            }
        }

        function applyScaledSize() {
            minimumWidth = Math.round(560 * root.uiS); minimumHeight = Math.round(380 * root.uiS);
            width = preferredWidth; height = preferredHeight;
        }
        Component.onCompleted: applyScaledSize()
        Connections {
            target: root
            function onUiSChanged() { prefsWindow.applyScaledSize(); if (prefsWindow.visible) { prefsWindow.floatTries = 0; floatTimer.restart(); } }
        }
        Timer {
            id: floatTimer
            interval: 60
            repeat: true
            onTriggered: {
                // the compositor maps the window a moment after it becomes visible: send the dispatches a few times
                var sel = 'window = "title:^(' + prefsWindow.title + ')$"';
                Hyprland.dispatch('hl.dsp.window.float({ action = "enable", ' + sel + ' })');
                Hyprland.dispatch('hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", ' + sel + ' })');
                // the window draws its own macOS-style edge: no Hyprland border, and Hyprland's rounding (used for its
                // shadow and the blur behind the sidebar) matches the window's own corner radius
                Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "border_size", value = "0", ' + sel + ' })');
                Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "rounding", value = "' + Math.round(frame.radius * root.uiS) + '", ' + sel + ' })');
                // Hyprland can remember an older floating size; reapply the compact size after mapping.
                if (prefsWindow.floatTries >= 2) {
                    Hyprland.dispatch('hl.dsp.window.resize({ x = ' + prefsWindow.preferredWidth + ', y = ' + prefsWindow.preferredHeight + ', "exact", ' + sel + ' })');
                    Hyprland.dispatch('hl.dsp.window.center({ ' + sel + ' })');
                }
                if (++prefsWindow.floatTries >= 12) stop();
            }
        }

        // ── palette ──
        QtObject {
            id: pal
            readonly property bool dark: root.darkMode
            readonly property string fam: root.fontFamily
            readonly property color accent: root.accent
            readonly property bool glass: root.liquidActive
            readonly property color content: glass ? (dark ? Qt.rgba(0.09, 0.09, 0.10, 0.58) : Qt.rgba(0.97, 0.97, 0.98, 0.62))
                                                   : (dark ? "#1E1E1E" : "#F5F5F7")
            readonly property color sidebar: dark ? "#292929" : "#E9E9EC"
            // the pages are opaque (only the sidebar is translucent), so the cards are solid too
            readonly property color contentSolid: dark ? "#1E1E1E" : "#F5F5F7"
            readonly property color sidebarGlass: dark ? Qt.rgba(0.17, 0.17, 0.18, 0.55) : Qt.rgba(0.94, 0.94, 0.96, 0.60)
            readonly property color card: dark ? "#2B2B2D" : "#FFFFFF"
            readonly property color cardBorder: dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.12)
            readonly property color windowBorder: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.22)
            // two-tone macOS window edge: a thin dark line outside, a soft highlight just inside it
            readonly property color edgeOuter: Qt.rgba(1, 1, 1, 0.50)
            readonly property color edgeInner: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.65)
            readonly property color sep: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.12)
            readonly property color text: dark ? "#F5F5F7" : "#1D1D1F"
            readonly property color text2: dark ? Qt.rgba(1, 1, 1, 0.56) : Qt.rgba(0, 0, 0, 0.52)
            readonly property color text3: dark ? Qt.rgba(1, 1, 1, 0.32) : Qt.rgba(0, 0, 0, 0.30)
            readonly property color track: dark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.13)
            readonly property color switchOff: dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.14)
            readonly property color ctrl: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06)
            readonly property color ctrlSel: dark ? "#636366" : "#FFFFFF"
            readonly property color button: dark ? Qt.rgba(1, 1, 1, 0.13) : "#FFFFFF"
            readonly property color buttonPressed: dark ? Qt.rgba(1, 1, 1, 0.24) : "#E4E4E7"
            readonly property color buttonBorder: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.20)
            readonly property color field: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.06)
            readonly property color hover: dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)
            readonly property color selInactive: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)
            function lightBorder(active, c) { return active ? Qt.darker(c, dark ? 1.12 : 1.22) : "transparent"; }
            readonly property color lightOff: dark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.15)
            readonly property color danger: "#FF453A"
        }

        NumberAnimation { id: fadeIn; target: paneLoader; property: "opacity"; from: 0; to: 1; duration: 160 }

        // ── frame ──
        Rectangle {
            id: frame
            // drawn at a scaled size: the whole window content shrinks with the UI scale, the window itself shrinks to match
            width: parent.width / root.uiS; height: parent.height / root.uiS
            scale: root.uiS; transformOrigin: Item.TopLeft
            radius: 12
            color: "transparent"        // the sidebar is translucent (blur of what is behind the window), the pages are opaque
            border.width: 1
            border.color: pal.edgeOuter

            // inner highlight (on top of everything, never takes the mouse)
            Rectangle {
                anchors.fill: parent; anchors.margins: 1
                radius: frame.radius - 1
                color: "transparent"
                border.width: 1; border.color: pal.edgeInner
                z: 900
            }

            // "New update x.x.x": shown by itself when Settings opens and a newer version exists. Nothing is downloaded.
            Item {
                id: updateOverlay
                anchors.fill: parent
                z: 1000
                visible: root.bar && root.bar.updateDialogOpen
                MouseArea { anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.AllButtons }     // modal: blocks the page underneath
                Rectangle { anchors.fill: parent; radius: frame.radius; color: Qt.rgba(0, 0, 0, pal.dark ? 0.45 : 0.25) }
                Rectangle {
                    anchors.centerIn: parent
                    width: 300; height: 176
                    radius: 14
                    color: pal.contentSolid
                    border.width: 1; border.color: pal.buttonBorder
                    Text {
                        x: 0; y: 28; width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: I18n.tr("New update ") + (root.bar ? root.bar.updateVersion : "")
                        color: pal.text
                        font.family: root.fontForWeight(Font.DemiBold, pal.fam); font.weight: Font.DemiBold
                        font.pixelSize: 17
                    }
                    Text {
                        x: 20; y: 62; width: parent.width - 40
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: I18n.tr("A new version of MacShell is available.")
                        color: pal.text2
                        font.family: root.fontForWeight(font.weight, pal.fam)
                        font.pixelSize: 13
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 20
                        spacing: 10
                        SButton {
                            t: pal
                            text: I18n.tr("Update")
                            onClicked: { if (root.bar) root.bar.openUpdateLink(); }
                        }
                        SButton {
                            t: pal
                            text: I18n.tr("Close")
                            onClicked: { if (root.bar) root.bar.updateDialogOpen = false; }
                        }
                    }
                }
            }

            // opaque page area: from the sidebar's right edge to the window edge (rounded on the right only)
            Rectangle {
                x: sidebar.x + sidebar.width; y: 1
                width: parent.width - x - 1; height: parent.height - 2
                radius: 11
                color: pal.contentSolid
                Rectangle { anchors.left: parent.left; width: 12; height: parent.height; color: parent.color }
            }

            // Native Wayland resize handles for this frameless window.
            MouseArea { x: 12; y: 0; width: parent.width - 24; height: 6; z: 1000; cursorShape: Qt.SizeVerCursor; onPressed: m => { prefsWindow.rsBegin(Qt.TopEdge, mapToItem(null, m.x, m.y)); }; preventStealing: true; onReleased: m => { prefsWindow.rsEnd(mapToItem(null, m.x, m.y)); }; }
            MouseArea { x: 12; y: parent.height - 6; width: parent.width - 24; height: 6; z: 1000; cursorShape: Qt.SizeVerCursor; onPressed: m => { prefsWindow.rsBegin(Qt.BottomEdge, mapToItem(null, m.x, m.y)); }; preventStealing: true; onReleased: m => { prefsWindow.rsEnd(mapToItem(null, m.x, m.y)); }; }
            MouseArea { x: 0; y: 12; width: 6; height: parent.height - 24; z: 1000; cursorShape: Qt.SizeHorCursor; onPressed: m => { prefsWindow.rsBegin(Qt.LeftEdge, mapToItem(null, m.x, m.y)); }; preventStealing: true; onReleased: m => { prefsWindow.rsEnd(mapToItem(null, m.x, m.y)); }; }
            MouseArea { x: parent.width - 6; y: 12; width: 6; height: parent.height - 24; z: 1000; cursorShape: Qt.SizeHorCursor; onPressed: m => { prefsWindow.rsBegin(Qt.RightEdge, mapToItem(null, m.x, m.y)); }; preventStealing: true; onReleased: m => { prefsWindow.rsEnd(mapToItem(null, m.x, m.y)); }; }
            MouseArea { x: 0; y: 0; width: 12; height: 12; z: 1001; cursorShape: Qt.SizeFDiagCursor; onPressed: m => { prefsWindow.rsBegin(Qt.TopEdge | Qt.LeftEdge, mapToItem(null, m.x, m.y)); }; preventStealing: true; onReleased: m => { prefsWindow.rsEnd(mapToItem(null, m.x, m.y)); }; }
            MouseArea { x: parent.width - 12; y: 0; width: 12; height: 12; z: 1001; cursorShape: Qt.SizeBDiagCursor; onPressed: m => { prefsWindow.rsBegin(Qt.TopEdge | Qt.RightEdge, mapToItem(null, m.x, m.y)); }; preventStealing: true; onReleased: m => { prefsWindow.rsEnd(mapToItem(null, m.x, m.y)); }; }
            MouseArea { x: 0; y: parent.height - 12; width: 12; height: 12; z: 1001; cursorShape: Qt.SizeBDiagCursor; onPressed: m => { prefsWindow.rsBegin(Qt.BottomEdge | Qt.LeftEdge, mapToItem(null, m.x, m.y)); }; preventStealing: true; onReleased: m => { prefsWindow.rsEnd(mapToItem(null, m.x, m.y)); }; }
            MouseArea { x: parent.width - 12; y: parent.height - 12; width: 12; height: 12; z: 1001; cursorShape: Qt.SizeFDiagCursor; onPressed: m => { prefsWindow.rsBegin(Qt.BottomEdge | Qt.RightEdge, mapToItem(null, m.x, m.y)); }; preventStealing: true; onReleased: m => { prefsWindow.rsEnd(mapToItem(null, m.x, m.y)); }; }

            // drag the window by its top strip
            Item {
                z: 3        // above the page scroller (which now reaches the top), below the sidebar with the traffic lights
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
                z: 4
                // the sidebar is the normal flat one, attached to the window edge (set floating to true for the inset glass card)
                readonly property bool floating: false
                x: sidebar.floating ? 8 : 1; y: sidebar.floating ? 8 : 1
                width: sidebar.floating ? 224 : 232
                height: parent.height - (sidebar.floating ? 16 : 2)
                radius: sidebar.floating ? 18 : 11
                // frosted: a translucent pane over Hyprland's blur of what's behind the window (no Liquid Glass shader)
                color: sidebar.floating ? (pal.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.35)) : "transparent"
                border.width: sidebar.floating ? 1 : 0
                border.color: pal.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)
                // translucent fill, drawn as ONE layer so the rounded body and the square right edge don't add up to a darker band:
                // both shapes are opaque inside the layer, and the layer carries the translucency
                Item {
                    visible: !sidebar.floating
                    anchors.fill: parent
                    z: -1
                    layer.enabled: true
                    opacity: pal.sidebarGlass.a
                    Rectangle { anchors.fill: parent; radius: sidebar.radius; color: Qt.rgba(pal.sidebarGlass.r, pal.sidebarGlass.g, pal.sidebarGlass.b, 1) }
                    Rectangle { anchors.right: parent.right; width: 14; height: parent.height; color: Qt.rgba(pal.sidebarGlass.r, pal.sidebarGlass.g, pal.sidebarGlass.b, 1) }
                }
                Rectangle { visible: !sidebar.floating; anchors.right: parent.right; width: 1; height: parent.height; color: pal.sep }

                // the glass slab: refracts the wallpaper exactly where the window sits (Hyprland's blur is xray, so
                // that is also what the rest of the window shows, blurred)
                Loader {
                    anchors.fill: parent
                    z: -1
                    active: false       // Liquid Glass sidebar removed: Settings is plain transparent + frosted blur
                    sourceComponent: Item {
                        id: sbg
                        readonly property real m: 64       // backdrop margin around the window (refraction reach)
                        readonly property real pad: 12     // shader padding (drop shadow)
                        Item {
                            id: prefsBackdrop
                            parent: frame
                            x: -sbg.m; y: -sbg.m
                            z: -100
                            width: frame.width + 2 * sbg.m
                            height: frame.height + 2 * sbg.m
                            Rectangle { anchors.fill: parent; color: "#141418" }
                            Image {
                                x: sbg.m - prefsGlassGeo.x
                                y: sbg.m - prefsGlassGeo.y
                                width: prefsGlassGeo.mw; height: prefsGlassGeo.mh
                                source: root.fileUrl(root.wallpaperFor(prefsGlassGeo.mon))
                                sourceSize.width: prefsGlassGeo.mw
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true; smooth: true
                            }
                            LiveWall {
                                x: sbg.m - prefsGlassGeo.x
                                y: sbg.m - prefsGlassGeo.y
                                width: prefsGlassGeo.mw; height: prefsGlassGeo.mh
                                video: root.bar ? root.bar.glassVideo : ""
                                live: root.glassLive && prefsWindow.visible
                                paused: !!root.bar && root.bar.gaming
                            }
                        }
                        ShaderEffectSource {
                            id: sbSrc
                            sourceItem: prefsBackdrop
                            hideSource: true
                            live: true
                            visible: false
                            textureSize: Qt.size(Math.round(prefsBackdrop.width / 2), Math.round(prefsBackdrop.height / 2))
                        }
                        MultiEffect {
                            id: sbBlurFx
                            source: sbSrc
                            width: sbSrc.textureSize.width; height: sbSrc.textureSize.height
                            blurEnabled: true; blurMax: 48
                            blur: Math.min(1, root.glassBlur * 1.4 * 0.5 / 48 + 0.25)
                            autoPaddingEnabled: false
                            visible: false
                        }
                        ShaderEffectSource { id: sbBlur; sourceItem: sbBlurFx; live: true; mipmap: true; visible: false }
                        ShaderEffect {
                            x: -sbg.pad; y: -sbg.pad
                            width: sidebar.width + 2 * sbg.pad
                            height: sidebar.height + 2 * sbg.pad
                            fragmentShader: root.glassShaderUrl
                            property variant src: sbBlur
                            property vector2d itemSize: Qt.vector2d(width, height)
                            property vector2d glassSize: Qt.vector2d(sidebar.width, sidebar.height)
                            property vector2d srcSize: Qt.vector2d(prefsBackdrop.width, prefsBackdrop.height)
                            property vector2d srcOffset: Qt.vector2d(sidebar.x - sbg.pad + sbg.m, sidebar.y - sbg.pad + sbg.m)
                            property real pad: sbg.pad
                            property real radius: sidebar.radius
                            property real bezel: 24
                            property real thickness: 30 * root.glassLiquid * 1.6
                            property real dispersion: 0.06 * root.glassLiquid * 1.3
                            property real magnify: 0.03 * root.glassLiquid
                            property real rim: Math.max(0.5, root.glassRim)
                            property real grain: root.glassGrain * 0.2
                            property real blurPx: 1.5
                            property real tintMix: root.glassOpacity * 0.5
                            property real saturation: 1.25
                            property real dark: root.dockDark ? 1 : 0
                            property real debug: 0
                            property real shadowAmt: 0.6
                            property real rimTint: 0
                            property real ringW: 0
                        }
                    }
                }

                // traffic lights
                Item {
                    id: lights
                    x: 17; y: 14
                    width: 58; height: 14
                    Row {
                        scale: 0.93; transformOrigin: Item.TopLeft      // a touch smaller
                        spacing: 8
                        Repeater {
                            model: [
                                { c: "#FF5F57", g: "\u00D7", on: true },
                                { c: "#FEBC2E", g: "\u2212", on: false },     // minimize: not available (greyed out)
                                { c: "#28C840", g: "↗", on: true }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                width: 14; height: 14; radius: 7
                                color: (modelData.on && (prefsWindow.active || lightsMa.containsMouse))
                                       ? modelData.c : pal.lightOff
                                border.width: 1
                                border.color: pal.lightBorder(modelData.on && (prefsWindow.active || lightsMa.containsMouse), modelData.c)
                                Canvas {
                                    anchors.fill: parent
                                    visible: lightsMa.containsMouse && parent.modelData.on
                                    onVisibleChanged: if (visible) requestPaint()
                                    onPaint: {
                                        var ctx = getContext("2d");
                                        ctx.clearRect(0, 0, width, height);
                                        if (parent.modelData.g === "\u00D7") {
                                            ctx.strokeStyle = "rgba(0,0,0,0.58)";
                                            ctx.lineWidth = 1.1;
                                            ctx.lineCap = "round";
                                            ctx.beginPath();
                                            ctx.moveTo(4.9, 4.9); ctx.lineTo(9.1, 9.1);
                                            ctx.moveTo(9.1, 4.9); ctx.lineTo(4.9, 9.1);
                                            ctx.stroke();
                                        } else if (parent.modelData.g === "\u2212") {
                                            ctx.strokeStyle = "rgba(0,0,0,0.58)";
                                            ctx.lineWidth = 1.2;
                                            ctx.lineCap = "round";
                                            ctx.beginPath();
                                            ctx.moveTo(3.5, 7.0); ctx.lineTo(10.5, 7.0);
                                            ctx.stroke();
                                        } else if (parent.modelData.g === "↗") {
                                            ctx.fillStyle = "rgba(0,0,0,0.58)";
                                            ctx.beginPath();
                                            ctx.moveTo(6, 4); ctx.lineTo(10, 4); ctx.lineTo(10, 8);
                                            ctx.closePath();
                                            ctx.fill();
                                            ctx.beginPath();
                                            ctx.moveTo(8, 10); ctx.lineTo(4, 10); ctx.lineTo(4, 6);
                                            ctx.closePath();
                                            ctx.fill();
                                        }
                                    }
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
                            else if (mouse.x < 44) { }      // minimize is greyed out and does nothing
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
                        font.family: root.fontForWeight(font.weight, pal.fam)
                        font.pixelSize: 13
                        onTextChanged: prefsWindow.query = text
                    }
                    Text {
                        x: 30
                        anchors.verticalCenter: parent.verticalCenter
                        visible: searchInput.text === ""
                        text: I18n.tr("Search")
                        color: pal.text3
                        font.family: root.fontForWeight(font.weight, pal.fam)
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
                            font.family: Fonts.forWeight(font.weight, pal.fam); font.pixelSize: 12
                            font.bold: true
                        }
                        MouseArea { anchors.fill: parent; onClicked: searchInput.text = "" }
                    }
                }

                // account card (macOS: your name + picture at the top of the sidebar) → Users & Groups
                Rectangle {
                    id: acct
                    x: 10; y: 90; width: parent.width - 20; height: 52; radius: 10
                    visible: prefsWindow.query === ""
                    readonly property int idx: { for (var i = 0; i < prefsWindow.panes.length; i++) if (prefsWindow.panes[i].id === "users") return i; return 0; }
                    color: prefsWindow.cur === idx ? (prefsWindow.active ? pal.accent : pal.selInactive) : (acctMa.containsMouse ? pal.hover : "transparent")
                    Item {
                        id: acctPic
                        x: 6; anchors.verticalCenter: parent.verticalCenter; width: 38; height: 38
                        Item { id: acctMask; anchors.fill: parent; visible: false; layer.enabled: true; Rectangle { anchors.fill: parent; radius: width / 2; color: "black" } }
                        Rectangle { anchors.fill: parent; radius: width / 2; color: pal.ctrl }
                        Image {
                            anchors.fill: parent; source: "file://" + Quickshell.env("HOME") + "/.face"; sourceSize: Qt.size(96, 96)
                            fillMode: Image.PreserveAspectCrop; cache: false
                            layer.enabled: true; layer.effect: MultiEffect { maskEnabled: true; maskSource: acctMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                        }
                    }
                    Column {
                        x: 52; anchors.verticalCenter: parent.verticalCenter
                        Text { text: root.userName; color: prefsWindow.cur === acct.idx && prefsWindow.active ? "white" : pal.text; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 13; font.weight: Font.DemiBold }
                        Text { text: I18n.tr("Local Account"); color: prefsWindow.cur === acct.idx && prefsWindow.active ? Qt.rgba(1, 1, 1, 0.8) : pal.text2; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 11 }
                    }
                    MouseArea { id: acctMa; anchors.fill: parent; hoverEnabled: true; onClicked: prefsWindow.go(acct.idx) }
                }

                // pane list (scrolls; sections separated by a gap, like System Settings)
                // feather: the list dissolves at the top / bottom edge wherever more rows are hidden beyond it
                Item {
                    id: navFeather
                    visible: false; layer.enabled: true
                    width: navFlick.width; height: navFlick.height
                    readonly property real size: 26
                    readonly property real topFade: Math.max(0, Math.min(1, navFlick.contentY / 18))
                    readonly property real bottomFade: Math.max(0, Math.min(1, (navFlick.contentHeight - navFlick.height - navFlick.contentY) / 18))
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 1 - navFeather.topFade) }
                            GradientStop { position: Math.min(0.49, navFeather.size / Math.max(1, navFeather.height)); color: "black" }
                            GradientStop { position: Math.max(0.51, 1 - navFeather.size / Math.max(1, navFeather.height)); color: "black" }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 1 - navFeather.bottomFade) }
                        }
                    }
                }
                Flickable {
                    id: navFlick
                    layer.enabled: true
                    layer.effect: MultiEffect { maskEnabled: true; maskSource: navFeather }
                    x: 10; y: acct.visible ? 150 : 92
                    width: parent.width - 20
                    height: parent.height - y - 8
                    contentHeight: navCol.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: navCol
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: prefsWindow.filtered
                        delegate: Item {
                            id: navItem
                            required property int modelData
                            required property int index
                            readonly property bool gap: index > 0 && prefsWindow.panes[prefsWindow.filtered[index - 1]].sec !== prefsWindow.panes[modelData].sec
                            width: parent.width
                            height: 34 + (gap ? 12 : 0)
                        Rectangle {
                            id: navRow
                            readonly property int modelData: navItem.modelData
                            readonly property var p: prefsWindow.panes[modelData]
                            readonly property bool sel: prefsWindow.cur === modelData
                            y: navItem.gap ? 12 : 0
                            width: parent.width
                            height: 34
                            radius: 8
                            color: sel ? (prefsWindow.active ? pal.accent : pal.selInactive)
                                       : (navMa.containsMouse ? pal.hover : "transparent")

                            SGlyph {

                                fam: pal.fam
                                x: 8
                                anchors.verticalCenter: parent.verticalCenter
                                kind: navRow.p.glyph || ""
                                wg: navRow.p.wg || ""
                                c1: navRow.p.c1
                                c2: navRow.p.c2
                            }
                            Text {
                                x: 42
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr(navRow.p.name)
                                color: (navRow.sel && prefsWindow.active) ? "white" : pal.text
                                font.family: root.fontForWeight(font.weight, pal.fam)
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
                    }

                    Text {
                        visible: prefsWindow.filtered.length === 0
                        width: parent.width
                        topPadding: 14
                        horizontalAlignment: Text.AlignHCenter
                        text: I18n.tr("No Results")
                        color: pal.text2
                        font.family: root.fontForWeight(font.weight, pal.fam)
                        font.pixelSize: 12
                    }
                }
                }
            }

            // ───────── toolbar ─────────
            Item {
                id: header
                z: 6
                x: sidebar.x + sidebar.width + 1
                width: parent.width - sidebar.x - sidebar.width - 2
                height: 52
                GlassSlab {                         // Liquid Glass pill behind the back / forward buttons
                    id: navPill
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 66; height: 36
                    cornerR: 18
                    glass: root.settingsGlass
                    shaderUrl: root.glassShaderUrl
                    dark: pal.dark
                    baseColor: pal.dark ? "#3C3C40" : "#FBFBFD"
                    thickness: 14; strengthMul: 0.6        // same glass as the Control Center buttons
                    liquid: root.glassLiquid
                    rim: root.glassRim * 0.25
                    grain: root.glassGrain
                    tint: root.glassOpacity
                    shadowAmt: 0; flatInner: 1
                    onFailed: root.glassState = "failed"
                    // Control Center border: thin, brighter shade of the wallpaper colour, fading at top-right / bottom-left
                    CornerBorder {
                        z: 2; anchors.fill: parent
                        cornerR: 18; dark: pal.dark
                        tint: root.bar ? root.bar.menuBorderColor : "#8A9AB5"
                        amount: 1; lineW: 0.8
                    }
                }

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
                            Rectangle {         // hover: the same faint light as the Control Center pills
                                anchors.fill: parent; radius: 13
                                color: (navBtn.ok && navMa.containsMouse) ? (pal.dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.5)) : "transparent"
                                Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            }
                            Text {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -2
                                text: navBtn.modelData.g
                                font.family: Fonts.forWeight(font.weight, pal.fam); font.pixelSize: 28
                                color: navBtn.ok ? pal.text : pal.text3
                                opacity: navBtn.ok ? 1 : 0.5
                                scale: (navBtn.ok && navMa.pressed) ? 0.86 : 1
                                Behavior on scale { NumberAnimation { duration: 230; easing.type: Easing.OutBack; easing.overshoot: 3.2 } }
                            }
                            MouseArea {
                                id: navMa
                                anchors.fill: parent
                                hoverEnabled: true
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
                    x: 90
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr(prefsWindow.panes[prefsWindow.cur].name)
                    color: pal.text
                    font.family: root.fontForWeight(font.weight, pal.fam)
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
            }

            // ───────── scrolling content ─────────
            // feather: the page scrolls all the way up under the toolbar; what slides under it melts away. Same feather as the
            // lyrics in the Player widget: one smooth alpha mask over the scroller (switched on as the page starts to scroll).
            Item {
                id: flickFeather
                visible: false; layer.enabled: true
                width: flick.width; height: flick.height
                readonly property real fp: Math.min(0.32, 46 / Math.max(1, height))     // feather depth: 46 px
                readonly property real amt: Math.max(0, Math.min(1, flick.contentY / 18))
                function a(base) { return 1 - amt * (1 - base); }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0;                    color: Qt.rgba(0, 0, 0, flickFeather.a(0.0)) }
                        GradientStop { position: flickFeather.fp * 0.25; color: Qt.rgba(0, 0, 0, flickFeather.a(0.04)) }
                        GradientStop { position: flickFeather.fp * 0.50; color: Qt.rgba(0, 0, 0, flickFeather.a(0.30)) }
                        GradientStop { position: flickFeather.fp * 0.75; color: Qt.rgba(0, 0, 0, flickFeather.a(0.72)) }
                        GradientStop { position: flickFeather.fp;        color: "black" }
                        GradientStop { position: 1.0;                    color: "black" }
                    }
                }
            }
            Flickable {
                id: flick
                layer.enabled: true
                layer.effect: MultiEffect { maskEnabled: true; maskSource: flickFeather }
                x: sidebar.x + sidebar.width + 1
                y: 1
                width: parent.width - sidebar.x - sidebar.width - 2
                height: parent.height - 2
                contentWidth: width
                contentHeight: paneLoader.height + 36 + 52
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick

                Loader {
                    id: paneLoader
                    // nothing of Settings stays built while the window is closed
                    active: prefsWindow.visible
                    x: 22
                    y: 58
                    width: flick.width - 44
                    sourceComponent: ({
                        wifi: paneWifi, bluetooth: paneBt, network: paneNetwork, battery: paneBattery,
                        general: paneGeneral, appearance: paneAppearance, controlcenter: paneCC, dock: paneDesktopDock,
                        displays: paneDisplays, menubar: paneMenuBar, wallpaper: paneWallpaper,
                        notifications: paneNotif, sound: paneSound, focus: paneFocus,
                        widgets: paneWidgets, lockscreen: paneLock, users: paneUsers, keyboard: paneKeyboard, mouse: paneMouse, trackpad: paneTrackpad,
                        apps: paneApps, about: paneAbout
                    })[prefsWindow.panes[prefsWindow.cur].id]
                    onLoaded: fadeIn.restart()
                }
            }
            Rectangle {   // thin overlay scrollbar
                visible: flick.contentHeight > flick.height + 1
                x: frame.width - 8
                y: 52 + flick.visibleArea.yPosition * (flick.height - 52)
                width: 4
                height: Math.max(28, flick.visibleArea.heightRatio * (flick.height - 52))
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

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Language")
                        subtitle: I18n.tr("Automatic follows the system language")
                        SSegmented {
                            t: pal
                            readonly property var codes: ["auto", "en", "ru"]
                            model: ["Automatic", "English", "Русский"]
                            segWidth: 96
                            current: codes.indexOf(root.bar ? root.bar.language : "auto")
                            onPicked: i => { if (root.bar) root.bar.language = codes[i]; }
                        }
                    }
                }

                SLabel { t: pal; header: true; text: I18n.tr("Shell") }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Dock")
                        subtitle: I18n.tr("Show the Dock at the bottom of the screen")
                        SSwitch { t: pal; checked: root.dockEnabled; onToggled: v => root.dockEnabled = v }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Menu Bar")
                        subtitle: I18n.tr("Show the panel at the top of the screen. Spotlight, Control Center and the calendar belong to it.")
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.barEnabled : true
                            onToggled: v => { if (root.bar) root.bar.barEnabled = v; }
                        }
                    }
                }
                SLabel {
                    t: pal
                    text: I18n.tr("If you turn both off, reopen this window with:  qs -c MacShell ipc call settings open")
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Software Update")
                        subtitle: !root.bar ? ""
                                  : root.bar.updateChecking ? I18n.tr("Checking for updates…")
                                  : root.bar.updateState === "available" ? I18n.tr("New update ") + root.bar.updateVersion
                                  : root.bar.updateState === "uptodate" ? I18n.tr("MacShell is up to date")
                                  : root.bar.updateState === "error" ? I18n.tr("Couldn't check for updates")
                                  : ""
                        Row {
                            spacing: 8
                            SButton {
                                t: pal
                                visible: root.bar && root.bar.updateState === "available"
                                text: I18n.tr("Update")
                                onClicked: { if (root.bar) root.bar.openUpdateLink(); }
                            }
                            SButton {
                                t: pal
                                opacity: root.bar && root.bar.updateChecking ? 0.5 : 1
                                text: I18n.tr("Check for updates")
                                onClicked: { if (root.bar && !root.bar.updateChecking) root.bar.checkForUpdates(false); }
                            }
                        }
                    }
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
                        title: I18n.tr("Menu Bar style")
                        subtitle: (root.bar && root.bar.barStyle === "liquid" && root.bar.glassState === "failed")
                                  ? I18n.tr("Liquid Glass couldn't start (install qt6-shadertools)")
                                  : I18n.tr("Style of the menus and popovers")
                        SSegmented {
                            t: pal
                            model: ["Normal Blur", "Apple Liquid Glass"]
                            segWidth: 128
                            current: (root.bar && root.bar.barStyle === "liquid") ? 1 : 0
                            onPicked: i => { if (root.bar) root.bar.barStyle = (i === 1 ? "liquid" : "blur"); }
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Liquid Glass bar")
                        subtitle: I18n.tr("The menu bar strip itself is Liquid Glass, refracting the wallpaper and windows under it (needs Apple Liquid Glass style)")
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.barGlass : true
                            onToggled: v => { if (root.bar) root.bar.barGlass = v; }
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Menu Bar size")
                        subtitle: I18n.tr("Scales the bar, its widgets, the menus and the Control Center; the left and right groups stay tucked into the screen corners")
                        SSlider {
                            t: pal; from: 18; to: 48; stepSize: 1
                            value: root.bar ? root.bar.barHeight : 28
                            leftLabel: I18n.tr("Compact"); rightLabel: I18n.tr("Large")
                            resetValue: 28
                            onMoved: v => { if (root.bar) root.bar.barHeight = Math.round(v); }
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Automatic scaling")
                        subtitle: I18n.tr("Shrinks the menu bar, its menus, Spotlight, Control Center and the Settings / About windows on screens smaller than 1920\u00d71080")
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.uiScaleAuto : true
                            onToggled: v => { if (root.bar) root.bar.uiScaleAuto = v; }
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("UI scale")
                        subtitle: I18n.tr("Your own multiplier, applied on top of automatic scaling (") + Math.round((root.bar ? root.bar.uiScale : 1) * 100) + "%)"
                        // The scale is applied only when the knob is released: applying it while dragging resizes this very window
                        // under the pointer. While held, the knob follows the pointer through `pend` only.
                        SSlider {
                            id: scaleSlider
                            property real pend: 1
                            t: pal; from: 0.5; to: 1.25; stepSize: 0.05
                            resetValue: 1.0
                            value: pressed ? pend : (root.bar ? root.bar.uiScaleManual : 1)
                            leftLabel: I18n.tr("Smaller"); rightLabel: I18n.tr("Larger")
                            onMoved: v => {
                                var r = Math.round(v * 100) / 100;
                                if (pressed) pend = r;
                                else if (root.bar) root.bar.uiScaleManual = r;     // e.g. "Reset to default"
                            }
                            onReleased: { if (root.bar) root.bar.uiScaleManual = Math.round(pend * 100) / 100; }
                        }
                    }
                }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Menu Bar logo")
                        subtitle: I18n.tr("Choose the Arch mark, Apple logo, or a custom image")
                        SSegmented {
                            t: pal
                            model: ["Arch", "Apple", "Custom"]
                            segWidth: 68
                            current: !root.bar || root.bar.barLogoMode === "arch" ? 0 : (root.bar.barLogoMode === "apple" ? 1 : 2)
                            onPicked: i => {
                                if (root.bar) root.bar.barLogoMode = ["arch", "apple", "custom"][i];
                            }
                        }
                    }
                    SRow {
                        t: pal
                        visible: root.bar && root.bar.barLogoMode === "custom"
                        title: I18n.tr("Custom image path")
                        subtitle: I18n.tr("Enter a local image path (PNG, SVG, or other supported format)")
                        Row {
                            spacing: 8
                            Rectangle {
                                width: 210; height: 26; radius: 6
                                color: pal.ctrl
                                border.width: 1
                                border.color: pal.cardBorder
                                TextInput {
                                    id: barLogoPathInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 8; anchors.rightMargin: 8
                                    verticalAlignment: TextInput.AlignVCenter
                                    clip: true
                                    selectByMouse: true
                                    color: pal.text
                                    selectionColor: pal.accent
                                    font.family: root.fontForWeight(font.weight, pal.fam)
                                    font.pixelSize: 12
                                    text: root.bar ? root.bar.barCustomLogoPath : ""
                                    onTextEdited: { if (root.bar) root.bar.barCustomLogoPath = text; }
                                    Connections {
                                        target: root.bar
                                        function onBarCustomLogoPathChanged() {
                                            if (root.bar && barLogoPathInput.text !== root.bar.barCustomLogoPath)
                                                barLogoPathInput.text = root.bar.barCustomLogoPath;
                                        }
                                    }
                                }
                                Text {
                                    visible: barLogoPathInput.text === ""
                                    x: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "~/Pictures/logo.png"
                                    color: pal.text3
                                    font.family: root.fontForWeight(font.weight, pal.fam)
                                    font.pixelSize: 12
                                }
                            }
                            SButton {
                                t: pal; text: I18n.tr("Clear")
                                onClicked: { if (root.bar) root.bar.barCustomLogoPath = ""; }
                            }
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Bar background")
                        subtitle: I18n.tr("A separate layer (macbarbg) so Hyprland can blur it. Needs: layerrule = blur, macbarbg")
                        SSlider {
                            t: pal
                            from: 0; to: 0.6; stepSize: 0.01
                            value: root.bar ? root.bar.barBgOpacity : 0.10
                            leftLabel: I18n.tr("Hidden"); rightLabel: I18n.tr("Tinted")
                            resetValue: 0.10
                            onMoved: v => { if (root.bar) root.bar.barBgOpacity = v; }
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("24-hour clock")
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.use24h : false
                            onToggled: v => { if (root.bar) root.bar.use24h = v; }
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Show date")
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.showDate : false
                            onToggled: v => { if (root.bar) root.bar.showDate = v; }
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Show seconds")
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.showSeconds : false
                            onToggled: v => { if (root.bar) root.bar.showSeconds = v; }
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Week starts on Monday")
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
                        title: I18n.tr("Battery percentage")
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.showBatteryPercent : false
                            onToggled: v => { if (root.bar) root.bar.showBatteryPercent = v; }
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Real-time glass")
                        subtitle: I18n.tr("Keep window captures live so popovers, Spotlight and the Dock open on current pixels. Turn off to save GPU.")
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.glassRealtime : true
                            onToggled: v => { if (root.bar) root.bar.glassRealtime = v; }
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Animated wallpaper in glass")
                        subtitle: I18n.tr("Play the animated wallpaper inside the Liquid Glass in real time. Off by default: the glass refracts a still frame and uses no video memory.")
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.liveWallGlass : false
                            onToggled: v => { if (root.bar) root.bar.liveWallGlass = v; }
                        }
                    }
                }

                SLabel { t: pal; header: true; text: I18n.tr("Top Bar Widgets") }
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: I18n.tr("Apple menu")
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("appleMenu") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("appleMenu", v); } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Application menus")
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("appMenus") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("appMenus", v); } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Workspace switcher")
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("workspaces") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("workspaces", v); } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("System tray")
                        SSwitch { t: pal; checked: root.bar ? root.bar.showTray : true; onToggled: v => { if (root.bar) root.bar.showTray = v; } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Volume")
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("volume") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("volume", v); } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Bluetooth")
                        subtitle: I18n.tr("Show the Bluetooth status icon, even while Bluetooth is off")
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("bluetooth") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("bluetooth", v); } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Keyboard layout")
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("keyboard") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("keyboard", v); } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Notifications")
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("notifications") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("notifications", v); } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Wi-Fi and network")
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("wifi") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("wifi", v); } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Spotlight search")
                        SSwitch { t: pal; checked: root.bar ? root.bar.showSearch : true; onToggled: v => { if (root.bar) root.bar.showSearch = v; } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Privacy indicators")
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("privacy") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("privacy", v); } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Control Center")
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("controlCenter") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("controlCenter", v); } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Clock and calendar")
                        SSwitch { t: pal; checked: root.bar ? root.bar.barWidgetEnabled("clock") : true; onToggled: v => { if (root.bar) root.bar.setBarWidget("clock", v); } }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Keep clipboard history")
                        subtitle: I18n.tr("Spotlight \u2192 Clipboard (needs wl-clipboard and cliphist). Turn off to stop recording what you copy")
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.clipHistory : false
                            onToggled: v => { if (root.bar) root.bar.clipHistory = v; }
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Paste after choosing")
                        subtitle: I18n.tr("Insert the chosen clipboard entry or emoji into the focused app (Shift+Return only copies)")
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.clipAutoPaste : false
                            onToggled: v => { if (root.bar) root.bar.clipAutoPaste = v; }
                        }
                    }
                }
                SLabel { t: pal; header: true; text: I18n.tr("Screenshots") }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Save to a folder")
                        subtitle: I18n.tr("Press Print to select an area. Turn off to only copy it to the clipboard")
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.screenshotSave : true
                            onToggled: v => { if (root.bar) root.bar.screenshotSave = v; }
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Save location")
                        subtitle: I18n.tr("Leave empty for ~/Pictures/Screenshots")
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
                                    font.family: root.fontForWeight(font.weight, pal.fam)
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
                                    font.family: root.fontForWeight(font.weight, pal.fam)
                                    font.pixelSize: 12
                                }
                            }
                            SButton { t: pal; text: I18n.tr("Choose\u2026"); onClicked: shotPick.running = true }
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Quick folders")
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
                        title: I18n.tr("Copy to clipboard")
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.screenshotClipboard : true
                            onToggled: v => { if (root.bar) root.bar.screenshotClipboard = v; }
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Show a notification")
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.screenshotNotify : true
                            onToggled: v => { if (root.bar) root.bar.screenshotNotify = v; }
                        }
                    }
                }
                SLabel {
                    t: pal
                    text: I18n.tr("Bind the Print key:  bind = , Print, exec, qs -c macbar ipc call screenshot region.  Choose\u2026 needs zenity, kdialog or yad; otherwise type the path. Screenshots need grim.")
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
                    text: I18n.tr("Accent color, appearance and font are in Appearance. Commands (terminal, launcher, files, clipboard) can be edited in ~/.config/macbar/settings.json.")
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
                        color: root.dockDark ? Qt.rgba(0.10, 0.10, 0.11, root.glassOpacity)
                                             : Qt.rgba(1, 1, 1, root.glassOpacity * 0.55)
                        border.width: 1
                        border.color: root.dockDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.45)
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
                                    id: pimg
                                    anchors.fill: parent
                                    visible: false
                                    source: root.iconSrc(pi.modelData.icon)
                                    sourceSize: Qt.size(96, 96)
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                }
                                MultiEffect {
                                    anchors.fill: pimg
                                    source: pimg
                                    saturation: root.iconTint ? -0.75 * root.iconTintStrength : 0.0
                                    colorization: root.iconTint ? 1.0 * root.iconTintStrength : 0.0
                                    brightness: root.iconTint ? 0.14 * root.iconTintStrength : 0.0
                                    contrast: root.iconTint ? 0.04 * root.iconTintStrength : 0.0
                                    colorizationColor: root.iconTintColor
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
                        title: I18n.tr("Size")
                        SSlider {
                            t: pal
                            from: 32; to: 128; stepSize: 1
                            value: root.iconSize
                            leftLabel: I18n.tr("Small"); rightLabel: I18n.tr("Large")
                            resetValue: 52
                            onMoved: v => root.iconSize = Math.round(v)
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Magnification")
                        subtitle: I18n.tr("Enlarge icons as the pointer moves over them")
                        SSwitch {
                            t: pal
                            checked: root.magnificationEnabled
                            onToggled: v => root.magnificationEnabled = v
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Magnification amount")
                        opacity: root.magnificationEnabled ? 1 : 0.45
                        SSlider {
                            t: pal
                            enabled: root.magnificationEnabled
                            from: 1.1; to: 2.5; stepSize: 0.05
                            value: root.magnification
                            leftLabel: I18n.tr("Min"); rightLabel: I18n.tr("Max")
                            resetValue: 1.7
                            onMoved: v => root.magnification = v
                        }
                    }
                }

                SLabel { t: pal; header: true; text: I18n.tr("Icon Tint") }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Tint Dock icons")
                        subtitle: I18n.tr("Re-colours every icon with one colour. Works with any icon pack.")
                        SSwitch { t: pal; checked: root.iconTint; onToggled: v => root.iconTint = v }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Colour")
                        opacity: root.iconTint ? 1 : 0.45
                        Row {
                            spacing: 6
                            Repeater {
                                model: root.tintChoices
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 18; height: 18; radius: 9
                                    color: modelData.c
                                    border.width: String(root.iconTintColor).toLowerCase() === modelData.c ? 2 : 1
                                    border.color: String(root.iconTintColor).toLowerCase() === modelData.c ? pal.text : pal.cardBorder
                                    MouseArea { anchors.fill: parent; enabled: root.iconTint; onClicked: root.iconTintColor = parent.modelData.c }
                                }
                            }
                            Rectangle {
                                width: 74; height: 22; radius: 6
                                color: pal.ctrl
                                border.width: 1
                                border.color: pal.cardBorder
                                TextInput {
                                    anchors.fill: parent
                                    anchors.leftMargin: 7; anchors.rightMargin: 7
                                    verticalAlignment: TextInput.AlignVCenter
                                    clip: true
                                    selectByMouse: true
                                    enabled: root.iconTint
                                    maximumLength: 7
                                    color: pal.text
                                    selectionColor: pal.accent
                                    font.family: root.fontForWeight(font.weight, pal.fam)
                                    font.pixelSize: 12
                                    text: root.iconTintColor
                                    onEditingFinished: { if (/^#[0-9a-fA-F]{6}$/.test(text)) root.iconTintColor = text.toLowerCase(); else text = root.iconTintColor; }
                                }
                            }
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Strength")
                        subtitle: I18n.tr("Lower values keep some of the original icon colours")
                        opacity: root.iconTint ? 1 : 0.45
                        SSlider {
                            t: pal
                            enabled: root.iconTint
                            from: 0.1; to: 1.0; stepSize: 0.05
                            value: root.iconTintStrength
                            leftLabel: I18n.tr("Subtle"); rightLabel: I18n.tr("Full")
                            resetValue: 1.0
                            onMoved: v => root.iconTintStrength = Math.round(v * 100) / 100
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Icon spacing")
                        SSlider {
                            t: pal
                            from: 0; to: 20; stepSize: 1
                            value: root.spacing
                            leftLabel: I18n.tr("Tight"); rightLabel: I18n.tr("Loose")
                            resetValue: 6
                            onMoved: v => root.spacing = Math.round(v)
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Distance from screen edge")
                        SSlider {
                            t: pal
                            from: 0; to: 40; stepSize: 1
                            value: root.margin
                            leftLabel: I18n.tr("Flush"); rightLabel: I18n.tr("Floating")
                            resetValue: 6
                            onMoved: v => root.margin = Math.round(v)
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Corner radius")
                        SSlider {
                            t: pal
                            from: 0; to: 32; stepSize: 1
                            value: root.cornerRadius
                            leftLabel: I18n.tr("Square"); rightLabel: I18n.tr("Round")
                            resetValue: 18
                            onMoved: v => root.cornerRadius = Math.round(v)
                        }
                    }
                }
                SLabel { t: pal; text: I18n.tr("Changes apply to the Dock immediately.") }
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
                        title: I18n.tr("Appearance")
                        subtitle: I18n.tr("Light, Dark, or Auto for everything: Dock, Menu Bar, menus, Spotlight, Settings and About. The Control Center tile and the Dark Mode menu item use this same setting.")
                        Row {
                            spacing: 14
                            SThemeTile {
                                t: pal; label: I18n.tr("Light"); dark: false
                                selected: root.appearanceMode === "light"
                                onClicked: root.setAppearance("light")
                            }
                            SThemeTile {
                                t: pal; label: I18n.tr("Dark"); dark: true
                                selected: root.appearanceMode === "dark"
                                onClicked: root.setAppearance("dark")
                            }
                            SThemeTile {
                                t: pal; label: I18n.tr("Auto"); split: true
                                selected: root.appearanceMode === "auto"
                                onClicked: root.setAppearance("auto")
                            }
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Accent color")
                        subtitle: I18n.tr("Highlights in the Dock menu and this window")
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
                                        x: 4; y: 4
                                        width: 18; height: 18; radius: 9
                                        color: sw.modelData.c
                                        border.width: 1
                                        border.color: Qt.rgba(0, 0, 0, 0.18)
                                    }
                                    Rectangle {         // selection ring: same centre as the dot, whole pixels only
                                        x: 0; y: 0
                                        visible: sw.sel
                                        width: 26; height: 26; radius: 13
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
                        title: I18n.tr("Dock style")
                        subtitle: root.dockStyle === "liquid" && root.glassState === "failed"
                                  ? I18n.tr("Liquid Glass couldn't start (install qt6-shadertools) – using Normal Blur")
                                  : (root.dockStyle === "liquid" && root.glassState === "building"
                                     ? I18n.tr("Preparing the Liquid Glass shader…")
                                     : I18n.tr("Blur of the desktop, or refracting Liquid Glass"))
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
                    visible: root.dockStyle === "liquid"     // both rows below are Liquid Glass only: no empty card in Normal Blur
                    SRow {
                        t: pal
                        visible: root.dockStyle === "liquid"
                        title: I18n.tr("Blur")
                        subtitle: I18n.tr("How strongly the glass blurs what's behind it")
                        SSlider {
                            t: pal
                            from: 0; to: 80; stepSize: 1
                            value: root.glassBlur
                            leftLabel: I18n.tr("Sharp"); rightLabel: I18n.tr("Very blurry")
                            resetValue: 5
                            onMoved: v => root.setLook("glassBlur", Math.round(v))
                        }
                    }
                    SRow {
                        t: pal
                        visible: root.dockStyle === "liquid"
                        title: I18n.tr("Liquid strength")
                        subtitle: I18n.tr("Refraction, magnification and colour fringing of the glass")
                        SSlider {
                            t: pal
                            from: 0.5; to: 2.5; stepSize: 0.05
                            value: root.glassLiquid
                            leftLabel: I18n.tr("Subtle"); rightLabel: I18n.tr("Very liquid")
                            resetValue: 1.0
                            onMoved: v => root.setLook("glassLiquid", v)
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Font")
                        subtitle: I18n.tr("Used for labels and menus")
                        SSegmented {
                            t: pal
                            model: ["Open Runde", "Noto Sans", "System"]
                            segWidth: 76
                            current: root.fontFamily === "Open Runde" ? 0 : (root.fontFamily === "Noto Sans" ? 1 : 2)
                            onPicked: i => root.setLook("fontFamily", ["Open Runde", "Noto Sans", "sans-serif"][i])
                        }
                    }
                }
                SCard {
                    t: pal
                    visible: root.dockStyle === "liquid"
                    SRow {
                        t: pal
                        title: I18n.tr("Real-time glass")
                        subtitle: I18n.tr("Windows behind the Dock stream live (every frame); workspace switches, new windows and wallpaper changes show through at once")
                        SSwitch { t: pal; checked: root.glassLive; onToggled: v => root.glassLive = v }
                    }
                }
                SLabel { t: pal; text: root.dockStyle === "liquid"
                                       ? I18n.tr("Liquid Glass refracts the wallpaper and windows behind the Dock in real time. Corner radius also shapes the glass.")
                                       : I18n.tr("The blur behind the Dock comes from your Hyprland layer rule.") }
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
                        title: I18n.tr("Automatically hide and show the Dock")
                        subtitle: root.hideMode === "smart" ? I18n.tr("Hides only while a tiled window needs the space")
                                : (root.hideMode === "always" ? "Always hidden until the pointer touches the screen edge"
                                                              : I18n.tr("Always visible and reserves screen space"))
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
                        title: I18n.tr("Hide delay")
                        SSlider {
                            t: pal
                            from: 0; to: 1500; stepSize: 50
                            value: root.hideDelay
                            leftLabel: I18n.tr("Instant"); rightLabel: "1.5 s"
                            resetValue: 450
                            onMoved: v => root.hideDelay = Math.round(v)
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Show Dock on")
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
                        title: I18n.tr("Show labels")
                        subtitle: I18n.tr("Display an app's name when you hover its icon")
                        SSwitch { t: pal; checked: root.showLabels; onToggled: v => root.showLabels = v }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Show window previews")
                        subtitle: I18n.tr("Open windows appear as live previews next to the Trash, each with its app's icon")
                        SSwitch { t: pal; checked: root.showThumbs; onToggled: v => root.showThumbs = v }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Live window capture")
                        subtitle: I18n.tr("Capture open windows for the previews. Turn off and the previews show the app icon instead (Liquid Glass is not affected)")
                        SSwitch { t: pal; checked: root.windowCapture; onToggled: v => root.windowCapture = v }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Show indicators for open applications")
                        SSwitch { t: pal; checked: root.showIndicators; onToggled: v => root.showIndicators = v }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Animate opening applications")
                        subtitle: I18n.tr("Icons bounce while an app is launching")
                        SSwitch { t: pal; checked: root.bounceOnLaunch; onToggled: v => root.bounceOnLaunch = v }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Show Trash in the Dock")
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

                SLabel { t: pal; header: true; text: I18n.tr("Kept in Dock") }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        visible: appsCol.pinCount === 0
                        title: I18n.tr("No apps are kept in the Dock")
                        subtitle: I18n.tr("Right-click a running app and choose Keep in Dock.")
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
                                text: I18n.tr("Remove")
                                onClicked: root.togglePin(appRow.modelData)
                            }
                        }
                    }
                }
                SLabel { t: pal; text: I18n.tr("Drag icons in the Dock to reorder them. Pins are saved to ~/.config/macdock/pinned.json.") }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Reset Dock Items")
                        subtitle: I18n.tr("Go back to the default set of apps")
                        SButton { t: pal; text: I18n.tr("Reset"); onClicked: root.resetPins() }
                    }
                }
            }
        }

        // ── About ──

        // ═════════ macOS-style panes linked to the shell ═════════

        // ── Wi-Fi ──
        Component {
            id: paneWifi
            Column {
                id: wifiPane
                spacing: 10
                property string ethInfo: ""
                Component.onCompleted: { if (root.bar) root.bar.scanWifi(); ethProc.running = true; }
                Timer { interval: 4000; repeat: true; running: prefsWindow.visible; onTriggered: if (!ethProc.running) ethProc.running = true }
                Process {
                    id: ethProc
                    command: ["sh", "-c", "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev 2>/dev/null | awk -F: '$2==\"ethernet\"' | head -1 | while IFS=: read -r d t st c; do ip=$(ip -4 -o addr show \"$d\" 2>/dev/null | awk '{print $4}' | head -1); sp=$(cat /sys/class/net/$d/speed 2>/dev/null); printf '%s\t%s\t%s\t%s\t%s' \"$d\" \"$st\" \"$c\" \"$ip\" \"$sp\"; done"]
                    stdout: StdioCollector { onStreamFinished: wifiPane.ethInfo = text.trim() }
                }
                readonly property var eth: { var f = ethInfo.split("\t"); return f.length >= 2 ? { dev: f[0], up: f[1].indexOf("connected") === 0, con: f[2] || "", ip: f[3] || "", speed: f[4] || "" } : null; }
                // Ethernet first: it's what you're actually online through when it's plugged in
                SCard {
                    t: pal
                    visible: wifiPane.eth !== null
                    SRow {
                        t: pal; title: I18n.tr("Ethernet")
                        subtitle: !wifiPane.eth ? "" : (wifiPane.eth.up
                                  ? I18n.tr("Connected") + (wifiPane.eth.ip !== "" ? " · " + wifiPane.eth.ip : "") + (parseInt(wifiPane.eth.speed) > 0 ? " · " + wifiPane.eth.speed + I18n.tr(" Mb/s") : "")
                                  : I18n.tr("Cable unplugged"))
                        Row {
                            spacing: 8
                            WGlyph { width: 18; height: 18; kind: "ethernet"; color: pal.text; anchors.verticalCenter: parent.verticalCenter }
                            Rectangle { width: 10; height: 10; radius: 5; anchors.verticalCenter: parent.verticalCenter; color: wifiPane.eth && wifiPane.eth.up ? "#30D158" : pal.text3 }
                        }
                    }
                }
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: I18n.tr("Wi-Fi")
                        subtitle: !root.bar ? "" : (!root.bar.wifiOn ? I18n.tr("Off") : (root.bar.wifiSsid !== "" ? I18n.tr("Connected to ") + root.bar.wifiSsid : I18n.tr("Not connected")))
                        SSwitch { t: pal; checked: root.bar ? root.bar.wifiOn : false; onToggled: v => { if (root.bar && root.bar.wifiOn !== v) root.bar.toggleWifi(); } }
                    }
                }
                SLabel { t: pal; header: true; text: I18n.tr("Known Networks & Other Networks"); visible: root.bar && root.bar.wifiOn }
                SCard {
                    t: pal
                    visible: root.bar && root.bar.wifiOn
                    Repeater {
                        model: root.bar ? root.bar.wifiNets : []
                        delegate: SRow {
                            required property var modelData
                            t: pal
                            title: modelData.ssid + (modelData.inUse ? "  ✓" : "")
                            subtitle: (modelData.secure ? I18n.tr("Secured") : I18n.tr("Open")) + (modelData.saved ? I18n.tr(" · Saved") : "") + " · " + modelData.signal + "%"
                            SButton {
                                t: pal
                                text: modelData.inUse ? I18n.tr("Connected") : (modelData.saved || !modelData.secure ? I18n.tr("Connect") : I18n.tr("Join…"))
                                onClicked: {
                                    if (modelData.inUse) return;
                                    if (modelData.saved || !modelData.secure) root.bar.connectWifi(modelData.ssid, "");
                                    else { prefsWindow.visible = false; root.bar.wifiJoin ? root.bar.wifiJoin(modelData.ssid) : null; }
                                }
                            }
                        }
                    }
                }
                Row {
                    spacing: 8
                    SButton { t: pal; text: I18n.tr("Scan Again"); onClicked: if (root.bar) root.bar.scanWifi() }
                }
            }
        }

        // ── Bluetooth ── (uses the Menu Bar's Bluetooth backend, so pairing, scanning and errors behave like the Control Center)
        Component {
            id: paneBt
            Column {
                id: btPane
                spacing: 10
                readonly property var bar: root.bar
                readonly property var allDevs: bar ? bar.btDevices : []
                readonly property var myDevs: allDevs.filter(function (d) { return d.paired || d.connected; })
                readonly property var nearby: allDevs.filter(function (d) { return !d.paired && !d.connected; })
                Component.onCompleted: { if (bar) { bar.refreshBt(); bar.scanBt(); } }
                Timer { interval: 4000; repeat: true; running: prefsWindow.visible; onTriggered: if (btPane.bar) btPane.bar.refreshBt() }
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: I18n.tr("Bluetooth")
                        subtitle: root.bar && root.bar.btOn ? I18n.tr("This computer is discoverable as \"") + root.userName + "\"" : I18n.tr("Off")
                        SSwitch { t: pal; checked: root.bar ? root.bar.btOn : false; onToggled: v => { if (root.bar && root.bar.btOn !== v) root.bar.toggleBt(); } }
                    }
                }
                SLabel { t: pal; header: true; text: I18n.tr("My Devices"); visible: btPane.myDevs.length > 0 }
                SCard {
                    t: pal
                    visible: btPane.myDevs.length > 0
                    Repeater {
                        model: btPane.myDevs
                        delegate: SRow {
                            required property var modelData
                            t: pal
                            title: modelData.name
                            subtitle: (root.bar && root.bar.btBusy === modelData.mac ? (modelData.connected ? I18n.tr("Disconnecting\u2026") : I18n.tr("Connecting\u2026"))
                                       : (modelData.connected ? "Connected" : "Not Connected")) + (modelData.bat !== "" ? " \u00B7 " + modelData.bat + "%" : "")
                            SButton {
                                t: pal; text: modelData.connected ? I18n.tr("Disconnect") : I18n.tr("Connect")
                                enabled: !(root.bar && root.bar.btBusy !== "")
                                onClicked: { if (root.bar) root.bar.connectBt(modelData.mac, modelData.connected); }
                            }
                        }
                    }
                }
                SLabel { t: pal; header: true; text: (root.bar && root.bar.btScanning) ? I18n.tr("Nearby Devices \u2014 searching\u2026") : I18n.tr("Nearby Devices"); visible: root.bar && root.bar.btOn }
                SCard {
                    t: pal
                    visible: root.bar && root.bar.btOn
                    Repeater {
                        model: btPane.nearby
                        delegate: SRow {
                            required property var modelData
                            t: pal
                            title: modelData.name
                            subtitle: root.bar && root.bar.btBusy === modelData.mac ? I18n.tr("Pairing\u2026") : I18n.tr("Not paired")
                            SButton {
                                t: pal; text: I18n.tr("Connect")
                                enabled: !(root.bar && root.bar.btBusy !== "")
                                onClicked: { if (root.bar) root.bar.connectBt(modelData.mac, false); }
                            }
                        }
                    }
                    SRow {
                        t: pal
                        visible: btPane.nearby.length === 0
                        title: root.bar && root.bar.btScanning ? I18n.tr("Searching for devices\u2026") : I18n.tr("No new devices found")
                        subtitle: I18n.tr("Put the device in pairing mode, then scan again")
                        SButton { t: pal; text: I18n.tr("Scan Again"); enabled: !(root.bar && root.bar.btScanning); onClicked: { if (root.bar) root.bar.scanBt(); } }
                    }
                }
                SLabel { t: pal; text: root.bar ? root.bar.btError : ""; visible: root.bar && root.bar.btError !== "" }
            }
        }

        // ── Network ──
        Component {
            id: paneNetwork
            Column {
                id: netPane
                spacing: 10
                property var devs: []
                Component.onCompleted: netProc.running = true
                Timer { interval: 4000; repeat: true; running: prefsWindow.visible; onTriggered: if (!netProc.running) netProc.running = true }
                Process {
                    id: netProc
                    command: ["sh", "-c", "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev 2>/dev/null | grep -vE ':(loopback|wifi-p2p|bridge):' | while IFS=: read -r d t s c; do ip=$(ip -4 -o addr show \"$d\" 2>/dev/null | awk '{print $4}' | head -1); printf '%s\\t%s\\t%s\\t%s\\t%s\\n' \"$d\" \"$t\" \"$s\" \"$c\" \"$ip\"; done"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            var out = [], l = text.split("\n");
                            for (var i = 0; i < l.length; i++) { var f = l[i].split("\t"); if (f.length >= 3 && f[0] !== "") out.push({ dev: f[0], type: f[1], state: f[2], con: f[3] || "", ip: f[4] || "" }); }
                            netPane.devs = out;
                        }
                    }
                }
                SCard {
                    t: pal
                    Repeater {
                        model: netPane.devs
                        delegate: SRow {
                            required property var modelData
                            t: pal
                            readonly property bool up: modelData.state.indexOf("connected") === 0
                            title: ({ ethernet: I18n.tr("Ethernet"), wifi: I18n.tr("Wi-Fi"), tun: modelData.dev === "tailscale0" ? I18n.tr("Tailscale") : I18n.tr("VPN") })[modelData.type] || modelData.dev
                            subtitle: (up ? I18n.tr("Connected") : I18n.tr("Not Connected")) + (modelData.con !== "" ? " · " + modelData.con : "") + (modelData.ip !== "" ? " · " + modelData.ip : "")
                            Rectangle { width: 10; height: 10; radius: 5; color: parent.up ? "#30D158" : pal.text3 }
                        }
                    }
                }
            }
        }

        // ── Battery ──
        Component {
            id: paneBattery
            Column {
                id: batPane
                spacing: 10
                readonly property var dev: UPower.displayDevice
                readonly property real pct: dev ? Math.round(dev.percentage <= 1 ? dev.percentage * 100 : dev.percentage) : 0
                readonly property bool charging: dev && (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.FullyCharged)
                property string profile: ""
                Component.onCompleted: ppGet.running = true
                Process { id: ppGet; command: ["powerprofilesctl", "get"]; stdout: StdioCollector { onStreamFinished: batPane.profile = text.trim() } }
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: I18n.tr("Battery Level")
                        subtitle: batPane.charging ? I18n.tr("Charging") : (batPane.dev && batPane.dev.timeToEmpty > 0 ? Math.floor(batPane.dev.timeToEmpty / 3600) + " h " + Math.round(batPane.dev.timeToEmpty % 3600 / 60) + I18n.tr(" min remaining") : I18n.tr("On battery"))
                        Row {
                            spacing: 8
                            Rectangle {
                                width: 120; height: 10; radius: 5; color: pal.track; anchors.verticalCenter: parent.verticalCenter
                                Rectangle { width: parent.width * batPane.pct / 100; height: parent.height; radius: 5; color: batPane.pct <= 20 && !batPane.charging ? "#FF453A" : "#30D158" }
                            }
                            Text { text: batPane.pct + "%"; color: pal.text; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Energy Mode")
                        subtitle: I18n.tr("Power profile used by the system")
                        SSegmented {
                            t: pal; model: ["Low Power", "Automatic", "High Power"]; segWidth: 84
                            current: ["power-saver", "balanced", "performance"].indexOf(batPane.profile)
                            onPicked: i => { var p = ["power-saver", "balanced", "performance"][i]; Quickshell.execDetached(["powerprofilesctl", "set", p]); batPane.profile = p; }
                        }
                    }
                }
                SLabel { t: pal; header: true; text: I18n.tr("Game Mode") }
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: I18n.tr("Game Mode")
                        subtitle: I18n.tr("Turns off blur, shadows, animations and Liquid Glass, pauses an animated wallpaper and uses the performance power profile. Everything comes back when it turns off.")
                        SSwitch { t: pal; checked: root.bar ? root.bar.gamingMode : false; onToggled: v => { if (root.bar) root.bar.gamingMode = v; } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Turn on automatically for fullscreen games")
                        subtitle: root.bar && root.bar.gamingAutoActive ? I18n.tr("On now: a game is fullscreen") : I18n.tr("Steam, Sober (Roblox), Minecraft, Lutris, Heroic and Windows games")
                        SSwitch { t: pal; checked: root.bar ? root.bar.gamingAuto : true; onToggled: v => { if (root.bar) root.bar.gamingAuto = v; } }
                    }
                }
            }
        }

        // ── Control Center ──
        Component {
            id: paneCC
            Column {
                spacing: 10
                SLabel { t: pal; text: I18n.tr("Choose which controls appear in Control Center. You can also drag them around in Control Center → Edit Controls.") }
                SCard {
                    t: pal
                    Repeater {
                        model: root.bar ? root.bar.ccCatalog : []
                        delegate: SRow {
                            required property var modelData
                            t: pal
                            title: I18n.tr(modelData.label)
                            SSwitch {
                                t: pal
                                checked: root.bar ? root.bar.ccControls.indexOf(modelData.id) >= 0 : false
                                onToggled: v => {
                                    if (!root.bar) return;
                                    var cl = root.bar.ccControls.filter(function (x) { return x !== modelData.id; });
                                    if (v) cl.push(modelData.id);
                                    root.bar.ccControls = cl;
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Desktop & Dock = Dock + Dock Behavior ──
        Component {
            id: paneDesktopDock
            Column {
                spacing: 18
                Loader { width: parent.width; sourceComponent: paneDock }
                SLabel { t: pal; header: true; text: I18n.tr("App Switcher (Alt + Tab)") }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Style")
                        subtitle: I18n.tr("Liquid Glass refracts what's behind it, Frosted blurs it, Opaque is a solid panel")
                        SSegmented {
                            t: pal
                            model: ["Liquid Glass", "Frosted", "Opaque"]
                            segWidth: 92
                            current: Math.max(0, ["glass", "frosted", "opaque"].indexOf(root.bar ? root.bar.switcherStyle : "glass"))
                            onPicked: i => { if (root.bar) root.bar.switcherStyle = ["glass", "frosted", "opaque"][i]; }
                        }
                    }
                }
                SLabel { t: pal; header: true; text: I18n.tr("Behavior") }
                Loader { width: parent.width; sourceComponent: paneBehavior }
            }
        }

        // ── Widgets ──
        Component {
            id: paneWidgets
            Column {
                id: wgPane
                spacing: 10
                readonly property var wdg: root.hub ? root.hub.widgets : null
                readonly property int total: (wdg && wdg.rev >= 0) ? wdg.widgetCount : 0
                readonly property bool editing: wdg ? wdg.editing : false
                function removeAll() {
                    if (!wdg) return;
                    var ids = [];
                    for (var i = 0; i < wdg.model.count; i++) ids.push(wdg.model.get(i).wid);
                    for (var k = 0; k < ids.length; k++) wdg.removeWidget(ids[k]);
                }
                function removeOne(type) {
                    if (!wdg) return;
                    for (var i = wdg.model.count - 1; i >= 0; i--)
                        if (wdg.model.get(i).wtype === type) { wdg.removeWidget(wdg.model.get(i).wid); return; }
                }

                // ── Layout ──
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Arrange widgets")
                        subtitle: wgPane.editing
                                  ? I18n.tr("Editing is on: drag a widget to move it, use the \u2212 badge to remove it, then click Stop Editing.")
                                  : I18n.tr("Drag a widget to move it (it snaps to the grid). Use the \u2212 badge on a widget to remove it.")
                        SButton {
                            t: pal
                            text: wgPane.editing ? I18n.tr("Stop Editing") : I18n.tr("Edit on Desktop")
                            onClicked: { if (wgPane.wdg) wgPane.wdg.editing = !wgPane.wdg.editing; }
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Widget size")
                        subtitle: I18n.tr("Makes every desktop widget smaller or larger (") + Math.round((wgPane.wdg ? wgPane.wdg.widgetScale : 1) * 100) + "%)"
                        SSlider {
                            t: pal
                            from: 0.6; to: 1.5; stepSize: 0.05
                            value: wgPane.wdg ? wgPane.wdg.widgetScale : 1
                            leftLabel: I18n.tr("Small"); rightLabel: I18n.tr("Large")
                            resetValue: 1.0
                            onMoved: v => { if (wgPane.wdg) wgPane.wdg.widgetScale = Math.round(v * 100) / 100; }
                        }
                    }
                }

                // ── Add ──
                // One tidy block per widget: name + hint on top, then   Style · Size · Add   on one line that wraps on a narrow window.
                SLabel { t: pal; header: true; text: I18n.tr("Add a Widget") }
                SCard {
                    t: pal
                    Repeater {
                        model: [
                            { type: "weather",  name: I18n.tr("Weather"),  hint: I18n.tr("Current conditions, hourly and daily forecast"), styles: [["liquid", I18n.tr("Liquid Glass")], ["normal", I18n.tr("Normal")]] },
                            { type: "calendar", name: I18n.tr("Calendar"), hint: I18n.tr("Today's date and the month"), styles: [["liquid", I18n.tr("Liquid Glass")], ["normal", I18n.tr("Normal")]] },
                            { type: "clock",    name: I18n.tr("Clock"),    hint: I18n.tr("Analog clock face"), styles: [["liquid", I18n.tr("Liquid Glass")], ["light", I18n.tr("Light")], ["dark", I18n.tr("Dark")]] },
                            { type: "player",   name: I18n.tr("Player"),   hint: I18n.tr("Now Playing with controls and lyrics"), styles: [["liquid", I18n.tr("Liquid Glass")], ["light", I18n.tr("Light")], ["dark", I18n.tr("Dark")]] },
                            { type: "image",    name: I18n.tr("Image"),    hint: I18n.tr("Your own picture (you choose the file)"), styles: [["normal", I18n.tr("Photo")]] }
                        ]
                        delegate: Item {
                            id: addRow
                            required property var modelData
                            required property int index
                            property int styleIdx: 0
                            property int sizeIdx: 1
                            readonly property var sizeKeys: ["small", "medium", "large"]
                            readonly property int onDesktop: (wgPane.wdg && wgPane.wdg.rev >= 0) ? wgPane.wdg.count(modelData.type) : 0
                            width: parent ? parent.width : 0
                            height: 12 + head.height + 10 + ctl.height + 14

                            Rectangle { visible: addRow.index > 0; x: 14; width: parent.width - 14; height: 1; color: pal.sep }

                            // name, hint and how many are already on the desktop
                            Item {
                                id: head
                                x: 14; y: 12
                                width: parent.width - 28
                                height: Math.max(nameCol.height, badge.height)
                                Column {
                                    id: nameCol
                                    width: parent.width - badge.width - 12
                                    spacing: 2
                                    Text { width: parent.width; text: addRow.modelData.name; elide: Text.ElideRight; color: pal.text; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 13; font.weight: Font.DemiBold }
                                    Text { width: parent.width; text: addRow.modelData.hint; wrapMode: Text.WordWrap; color: pal.text2; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 12 }
                                }
                                Row {
                                    id: badge
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    spacing: 8
                                    visible: addRow.onDesktop > 0
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: addRow.onDesktop + I18n.tr(" on desktop")
                                        color: pal.text2; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 12
                                    }
                                    SButton { t: pal; text: "\u2212"; onClicked: wgPane.removeOne(addRow.modelData.type) }
                                }
                            }

                            // style · size · add
                            Flow {
                                id: ctl
                                x: 14; y: 12 + head.height + 10
                                width: parent.width - 28
                                spacing: 10
                                SSegmented {
                                    t: pal
                                    visible: addRow.modelData.styles.length > 1
                                    model: addRow.modelData.styles.map(function (s) { return s[1]; })
                                    segWidth: 88
                                    current: addRow.styleIdx
                                    onPicked: i => addRow.styleIdx = i
                                }
                                SSegmented {
                                    t: pal
                                    model: [I18n.tr("Small"), I18n.tr("Medium"), I18n.tr("Large")]
                                    segWidth: 64
                                    current: addRow.sizeIdx
                                    onPicked: i => addRow.sizeIdx = i
                                }
                                SButton {
                                    t: pal
                                    text: "+ " + I18n.tr("Add")
                                    onClicked: {
                                        if (!wgPane.wdg) return;
                                        var sz = addRow.sizeKeys[addRow.sizeIdx];
                                        if (addRow.modelData.type === "image") wgPane.wdg.pickImage("", sz);
                                        else wgPane.wdg.addWidget(addRow.modelData.type, addRow.modelData.styles[addRow.styleIdx][0], sz);
                                    }
                                }
                            }
                        }
                    }
                }
                SLabel {
                    t: pal
                    visible: wgPane.wdg && wgPane.wdg.pickError !== ""
                    text: wgPane.wdg ? wgPane.wdg.pickError : ""
                    color: pal.danger
                }
                SLabel {
                    t: pal
                    text: I18n.tr("Image widgets open a file picker (needs zenity, kdialog or yad). To change a picture later, use Edit on Desktop and press Choose Image on the widget.")
                }

                // ── On the desktop now ──
                SLabel { t: pal; header: true; text: I18n.tr("On Your Desktop") }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        visible: wgPane.total === 0
                        title: I18n.tr("No widgets yet")
                        subtitle: I18n.tr("Add one above and it appears on the desktop.")
                    }
                    Repeater {
                        model: wgPane.wdg ? wgPane.wdg.model : null
                        delegate: SRow {
                            id: placedRow
                            required property string wid
                            required property string wtype
                            required property string wstyle
                            required property string wsize
                            t: pal
                            title: (wgPane.wdg ? (wgPane.wdg.typeNames[wtype] || wtype) : wtype)
                            subtitle: (wgPane.wdg ? (wgPane.wdg.sizeNames[wsize] || wsize) : wsize) + "  \u00B7  " + (wgPane.wdg ? (wgPane.wdg.styleNames[wstyle] || wstyle) : wstyle)
                            SButton { t: pal; text: I18n.tr("Remove"); onClicked: { if (wgPane.wdg) wgPane.wdg.removeWidget(placedRow.wid); } }
                        }
                    }
                    SRow {
                        t: pal
                        visible: wgPane.total > 1
                        title: I18n.tr("Remove all widgets")
                        SButton { t: pal; text: I18n.tr("Remove All"); onClicked: wgPane.removeAll() }
                    }
                }

                // ── Weather ──
                SLabel { t: pal; header: true; text: I18n.tr("Weather") }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Temperature unit")
                        subtitle: I18n.tr("Used by the Weather widget")
                        SSegmented {
                            t: pal
                            model: ["\u00B0C", "\u00B0F"]
                            segWidth: 56
                            current: wgPane.wdg && wgPane.wdg.tempUnit === "F" ? 1 : 0
                            onPicked: i => { if (wgPane.wdg) wgPane.wdg.tempUnit = (i === 1 ? "F" : "C"); }
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Location")
                        subtitle: I18n.tr("Automatic uses your IP address; or type a city name")
                        SSegmented {
                            t: pal
                            model: ["Automatic", "City"]
                            segWidth: 80
                            current: wgPane.wdg && wgPane.wdg.locMode === "city" ? 1 : 0
                            onPicked: i => { if (wgPane.wdg) wgPane.wdg.locMode = (i === 1 ? "city" : "auto"); }
                        }
                    }
                    SRow {
                        t: pal
                        visible: wgPane.wdg && wgPane.wdg.locMode === "city"
                        title: I18n.tr("City")
                        subtitle: I18n.tr("For example: Riyadh, Dubai, London")
                        Rectangle {
                            width: 210; height: 26; radius: 6
                            color: pal.ctrl
                            border.width: 1
                            border.color: pal.cardBorder
                            TextInput {
                                anchors.fill: parent
                                anchors.leftMargin: 8; anchors.rightMargin: 8
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                selectByMouse: true
                                color: pal.text
                                selectionColor: pal.accent
                                font.family: root.fontForWeight(font.weight, pal.fam)
                                font.pixelSize: 12
                                text: wgPane.wdg ? wgPane.wdg.cityName : ""
                                onEditingFinished: { if (wgPane.wdg) wgPane.wdg.cityName = text; }
                            }
                        }
                    }
                }
            }
        }

        // ── Displays ──
        Component {
            id: paneDisplays
            Column {
                id: dispPane
                spacing: 10
                property var mons: []
                Component.onCompleted: { monList.running = true; root.refreshMons(); }
                Process {
                    id: monList
                    command: ["hyprctl", "-j", "monitors"]
                    stdout: StdioCollector { onStreamFinished: { try { dispPane.mons = JSON.parse(text); } catch (e) {} } }
                }
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: I18n.tr("Brightness")
                        SSlider { t: pal; resetValue: 0.5; value: root.bar ? root.bar.brightness : 0.5; onMoved: v => { if (root.bar) root.bar.setBrightness(v); } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Night Shift")
                        subtitle: I18n.tr("Warmer colours to reduce blue light")
                        SSwitch { t: pal; checked: root.bar ? root.bar.nightOn : false; onToggled: v => { if (root.bar) root.bar.nightOn = v; } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Colour Temperature"); visible: root.bar && root.bar.nightOn
                        SSlider {
                            t: pal; resetValue: 0.571; leftLabel: I18n.tr("Less Warm"); rightLabel: I18n.tr("More Warm")
                            value: root.bar ? 1 - (root.bar.nightTemp - 2500) / 3500 : 0.5
                            onMoved: v => { if (root.bar) root.bar.nightTemp = Math.round(2500 + (1 - v) * 3500); }
                        }
                    }
                }
                SLabel { t: pal; header: true; text: I18n.tr("Displays") }
                // keep / revert sheet (macOS: "Keep these display settings?")
                Rectangle {
                    visible: root.pendingOut !== ""
                    width: parent.width; height: 64; radius: 10
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
                    border.width: 1; border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6)
                    Text {
                        x: 14; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 220; wrapMode: Text.WordWrap
                        text: I18n.tr("Keep these display settings? Reverting in ") + root.revertLeft + " s."
                        color: pal.text; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                    Row {
                        anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        SButton { t: pal; text: I18n.tr("Revert"); onClicked: root.revertMode() }
                        SButton { t: pal; text: I18n.tr("Keep Changes"); onClicked: root.keepMode() }
                    }
                }
                SCard {
                    t: pal
                    visible: root.monList.length > 1
                    SRow {
                        t: pal; title: I18n.tr("Main display")
                        subtitle: I18n.tr("The Dock, the lock screen controls and new widgets go here")
                        SSegmented {
                            t: pal
                            model: root.monList.map(function (m) { return m.name; })
                            segWidth: 96
                            current: { var p = root.monitorPrimary || root.monitor; for (var i = 0; i < root.monList.length; i++) if (root.monList[i].name === p) return i; return -1; }
                            onPicked: i => root.setPrimary(root.monList[i].name)
                        }
                    }
                }
                Repeater {
                    model: root.monList
                    delegate: SCard {
                        id: monCard
                        required property var modelData
                        t: pal
                        // available modes → resolutions (largest first) and the refresh rates of the chosen one
                        readonly property var modes: {
                            var seen = {}, out = [];
                            var am = modelData.availableModes || [];
                            for (var i = 0; i < am.length; i++) {
                                var m = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(am[i]); if (!m) continue;
                                var k = m[1] + "x" + m[2] + "@" + parseFloat(m[3]).toFixed(2);
                                if (seen[k]) continue; seen[k] = true;
                                out.push({ w: parseInt(m[1]), h: parseInt(m[2]), hz: parseFloat(m[3]) });
                            }
                            return out;
                        }
                        readonly property var resolutions: {
                            var seen = {}, out = [];
                            for (var i = 0; i < modes.length; i++) { var r = modes[i].w + "x" + modes[i].h; if (!seen[r]) { seen[r] = true; out.push(modes[i]); } }
                            out.sort(function (a, b) { return b.w * b.h - a.w * a.h; });
                            var cur = modelData.width + "x" + modelData.height;
                            if (!seen[cur]) out.unshift({ w: modelData.width, h: modelData.height, hz: modelData.refreshRate, custom: true });
                            return out;
                        }
                        property string selRes: modelData.width + "x" + modelData.height
                        readonly property var rates: {
                            var out = [];
                            for (var i = 0; i < modes.length; i++) if (modes[i].w + "x" + modes[i].h === selRes && out.indexOf(Math.round(modes[i].hz)) < 0) out.push(Math.round(modes[i].hz));
                            out.sort(function (a, b) { return b - a; });
                            if (out.length === 0) out.push(Math.round(modelData.refreshRate));
                            return out;
                        }
                        function bestHz(res, hz) {
                            var best = null;
                            for (var i = 0; i < modes.length; i++) if (modes[i].w + "x" + modes[i].h === res && (best === null || Math.abs(modes[i].hz - hz) < Math.abs(best - hz))) best = modes[i].hz;
                            return best === null ? hz : best;
                        }
                        SRow {
                            t: pal
                            title: (modelData.description || modelData.name).replace(/\s*\(.*\)$/, "")
                            subtitle: modelData.name + " · " + modelData.width + " × " + modelData.height + " @ " + Math.round(modelData.refreshRate) + I18n.tr(" Hz · Scale ") + modelData.scale
                        }
                        SRow {
                            t: pal; title: I18n.tr("Resolution")
                            SPopUp {
                                t: pal
                                model: monCard.resolutions.map(function (r) { return r.w + " × " + r.h + (r.custom ? "  (current)" : ""); })
                                current: { for (var i = 0; i < monCard.resolutions.length; i++) if (monCard.resolutions[i].w + "x" + monCard.resolutions[i].h === monCard.selRes) return i; return 0; }
                                onPicked: i => {
                                    var r = monCard.resolutions[i];
                                    if (r.custom) return;
                                    monCard.selRes = r.w + "x" + r.h;
                                    var hz = monCard.bestHz(monCard.selRes, monCard.modelData.refreshRate);
                                    root.tryMode(monCard.modelData.name, monCard.selRes + "@" + hz.toFixed(2));
                                }
                            }
                        }
                        SRow {
                            t: pal; title: I18n.tr("Refresh rate")
                            SPopUp {
                                t: pal
                                model: monCard.rates.map(function (h) { return h + " Hz"; })
                                current: { var c = Math.round(monCard.modelData.refreshRate), i = monCard.rates.indexOf(c); return i < 0 ? 0 : i; }
                                onPicked: i => {
                                    var hz = monCard.bestHz(monCard.selRes, monCard.rates[i]);
                                    root.tryMode(monCard.modelData.name, monCard.selRes + "@" + hz.toFixed(2));
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Notifications ──
        Component {
            id: paneNotif
            Column {
                spacing: 10
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: I18n.tr("Show notification banners")
                        subtitle: I18n.tr("Off = Do Not Disturb: notifications still go to Notification Center, without banners")
                        SSwitch { t: pal; checked: root.bar ? !root.bar.notifDnd : true; onToggled: v => { if (root.bar) root.bar.notifDnd = !v; } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Play sound for notifications")
                        SSwitch { t: pal; checked: root.bar ? root.bar.uiSounds : true; onToggled: v => { if (root.bar) root.bar.uiSounds = v; } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Screenshot notifications")
                        SSwitch { t: pal; checked: root.bar ? root.bar.screenshotNotify : true; onToggled: v => { if (root.bar) root.bar.screenshotNotify = v; } }
                    }
                }
                Row {
                    spacing: 8
                    SButton { t: pal; text: I18n.tr("Send Test Notification"); onClicked: Quickshell.execDetached(["notify-send", "-a", I18n.tr("Settings"), I18n.tr("Test notification"), I18n.tr("Notifications are working")]) }
                    SButton { t: pal; text: I18n.tr("Clear Notification Center"); onClicked: if (root.bar) root.bar.notifClearAnimated() }
                }
            }
        }

        // ── Sound ──
        Component {
            id: paneSound
            Column {
                id: sndPane
                spacing: 10
                readonly property var outs: Pipewire.nodes.values.filter(function (n) { return n.isSink && !n.isStream && n.audio; })
                readonly property var ins: Pipewire.nodes.values.filter(function (n) { return !n.isSink && !n.isStream && n.audio && (n.name || "").indexOf("monitor") < 0; })
                readonly property var src: Pipewire.defaultAudioSource
                PwObjectTracker { objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource] }
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: I18n.tr("Play user interface sound effects")
                        SSwitch { t: pal; checked: root.bar ? root.bar.uiSounds : true; onToggled: v => { if (root.bar) root.bar.uiSounds = v; } }
                    }
                }
                SLabel { t: pal; header: true; text: I18n.tr("Output") }
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: I18n.tr("Output volume")
                        SSlider { t: pal; resetValue: 0.5; value: root.bar ? (root.bar.muted ? 0 : root.bar.volume) : 0; onMoved: v => { if (root.bar) root.bar.setVolume(v); } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Mute")
                        SSwitch { t: pal; checked: root.bar ? root.bar.muted : false; onToggled: v => { if (root.bar && root.bar.muted !== v) root.bar.toggleMute(); } }
                    }
                    Repeater {
                        model: sndPane.outs
                        delegate: SRow {
                            required property var modelData
                            t: pal
                            title: modelData.description || modelData.nickname || modelData.name
                            id: devRowSink
                            readonly property bool cur: Pipewire.defaultAudioSink === modelData
                            subtitle: cur ? I18n.tr("Selected") : ""
                            SButton { t: pal; text: devRowSink.cur ? I18n.tr("In Use") : I18n.tr("Use"); onClicked: Pipewire.preferredDefaultAudioSink = devRowSink.modelData }
                        }
                    }
                }
                SLabel { t: pal; header: true; text: I18n.tr("Input") }
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: I18n.tr("Input volume")
                        SSlider { t: pal; resetValue: 1.0; value: sndPane.src && sndPane.src.audio ? sndPane.src.audio.volume : 0; onMoved: v => { if (sndPane.src && sndPane.src.audio) sndPane.src.audio.volume = v; } }
                    }
                    Repeater {
                        model: sndPane.ins
                        delegate: SRow {
                            required property var modelData
                            t: pal
                            title: modelData.description || modelData.nickname || modelData.name
                            id: devRowSource
                            readonly property bool cur: Pipewire.defaultAudioSource === modelData
                            subtitle: cur ? I18n.tr("Selected") : ""
                            SButton { t: pal; text: devRowSource.cur ? I18n.tr("In Use") : I18n.tr("Use"); onClicked: Pipewire.preferredDefaultAudioSource = devRowSource.modelData }
                        }
                    }
                }
            }
        }

        // ── Focus ──
        Component {
            id: paneFocus
            Column {
                spacing: 10
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: I18n.tr("Do Not Disturb")
                        subtitle: I18n.tr("Silences notification banners")
                        SSwitch { t: pal; checked: root.bar ? root.bar.notifDnd : false; onToggled: v => { if (root.bar) root.bar.notifDnd = v; } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Keep Awake")
                        subtitle: I18n.tr("Stop the computer from going to sleep or locking")
                        SSwitch { t: pal; checked: root.bar ? root.bar.keepAwake : false; onToggled: v => { if (root.bar) root.bar.keepAwake = v; } }
                    }
                }
            }
        }

        // ── Lock Screen ──
        Component {
            id: paneLock
            Column {
                id: lockPane
                spacing: 10
                property string slot: "top"
                Component.onCompleted: slotGet.running = true
                Process { id: slotGet; command: ["sh", "-c", "jq -r '.mediaSlot // \"top\"' \"$HOME/.config/maclock/settings.json\" 2>/dev/null || echo top"]
                          stdout: StdioCollector { onStreamFinished: lockPane.slot = text.trim() === "bottom" ? "bottom" : "top" } }
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: I18n.tr("Now Playing position")
                        subtitle: I18n.tr("You can also drag it on the lock screen")
                        SSegmented {
                            t: pal; model: ["Under Clock", "Above Password"]; segWidth: 110
                            current: lockPane.slot === "bottom" ? 1 : 0
                            onPicked: i => {
                                lockPane.slot = i === 1 ? "bottom" : "top";
                                Quickshell.execDetached(["sh", "-c", "mkdir -p \"$HOME/.config/maclock\" && printf '{\\n  \"mediaSlot\": \"%s\"\\n}\\n' \"$1\" > \"$HOME/.config/maclock/settings.json\"", "sh", lockPane.slot]);
                            }
                        }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Album background when the cover is enlarged")
                        SSwitch { t: pal; checked: root.bar ? root.bar.lockArtBackground : true; onToggled: v => { if (root.bar) root.bar.lockArtBackground = v; } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("24-hour clock")
                        subtitle: I18n.tr("Shared with the menu bar clock")
                        SSwitch { t: pal; checked: root.bar ? root.bar.use24h : true; onToggled: v => { if (root.bar) root.bar.use24h = v; } }
                    }
                }
                // ── Clock ──
                // the clock fonts, loaded straight from their files so the previews never fall back to another face
                FontLoader { id: fNunito; source: "file://" + Quickshell.env("HOME") + "/.local/share/fonts/Nunito/Nunito.ttf" }
                FontLoader { id: fSerif; source: "file://" + Quickshell.env("HOME") + "/.local/share/fonts/NotoSerifDisplay/NotoSerifDisplay.ttf" }
                SLabel { t: pal; text: I18n.tr("Clock"); font.weight: Font.DemiBold; topPadding: 6 }
                SCard {
                    t: pal
                    // preset tiles
                    Item {
                        width: parent.width; height: 132
                        Row {
                            anchors.centerIn: parent
                            spacing: 10
                            Repeater {
                                model: [
                                    { id: "glass",   name: "Glass",   fam: fNunito.status === FontLoader.Ready ? fNunito.name : "Nunito", w: 680, tall: false, liquid: false },
                                    { id: "classic", name: "Classic", fam: fNunito.status === FontLoader.Ready ? fNunito.name : "Nunito",             w: 640, tall: false, liquid: false },
                                    { id: "serif",   name: "Serif",   fam: fSerif.status === FontLoader.Ready ? fSerif.name : "Noto Serif Display", w: 560, tall: false, liquid: false },
                                    { id: "liquid",  name: "Liquid",  fam: fNunito.status === FontLoader.Ready ? fNunito.name : "Nunito", w: 560, tall: false, liquid: true },
                                    { id: "thin",    name: "Thin",    fam: fNunito.status === FontLoader.Ready ? fNunito.name : "Nunito",             w: 220, tall: false, liquid: true }
                                ]
                                delegate: Column {
                                    id: tile
                                    required property var modelData
                                    readonly property bool sel: root.bar && root.bar.lockClockStyle === modelData.id
                                    spacing: 6
                                    Rectangle {
                                        width: 92; height: 92; radius: 14
                                        gradient: Gradient {
                                            GradientStop { position: 0; color: "#8C7A6B" }
                                            GradientStop { position: 1; color: "#3E3530" }
                                        }
                                        border.width: tile.sel ? 3 : 0; border.color: pal.accent
                                        Behavior on border.width { NumberAnimation { duration: 160 } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: "9:41"
                                            font.family: Fonts.forWeight(font.weight, tile.modelData.fam); font.pixelSize: tile.modelData.tall ? 40 : 30
                                            font.weight: Math.max(100, Math.min(900, tile.modelData.w))
                                            font.variableAxes: ({ "wght": tile.modelData.w })
                                            color: tile.modelData.liquid ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.78)
                                            style: tile.modelData.liquid ? Text.Outline : Text.Normal
                                            styleColor: Qt.rgba(1, 1, 1, 0.85)
                                        }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.bar) root.bar.applyLockClockPreset(tile.modelData.id) }
                                    }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: I18n.tr(tile.modelData.name); color: tile.sel ? pal.accent : pal.text; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 12; font.weight: tile.sel ? Font.DemiBold : Font.Normal }
                                }
                            }
                        }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Font")
                        SPopUp {
                            t: pal
                            model: ["Rounded", "Serif", "Default"]
                            readonly property var ids: ["rounded", "serif", "inter"]
                            current: Math.max(0, ids.indexOf(root.bar ? root.bar.lockClockFont : "rounded"))
                            onPicked: i => { if (root.bar) { root.bar.lockClockFont = ids[i]; root.bar.lockClockStyle = "custom"; } }
                        }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Weight")
                        SSlider {
                            t: pal; resetValue: 680; width: 220; from: 100; to: 1000; stepSize: 10
                            leftLabel: I18n.tr("Thin"); rightLabel: I18n.tr("Heavy")
                            value: root.bar ? root.bar.lockClockWeight : 680
                            onMoved: v => { if (root.bar) { root.bar.lockClockWeight = Math.round(v); root.bar.lockClockStyle = "custom"; } }
                        }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Style")
                        subtitle: I18n.tr("Solid glows with a hint of the wallpaper; Glass is Liquid Glass that catches the light")
                        SSegmented {
                            t: pal; model: ["Solid", "Glass"]; segWidth: 80
                            current: root.bar && root.bar.lockClockMaterial === "solid" ? 0 : 1
                            onPicked: i => { if (root.bar) { root.bar.lockClockMaterial = i === 0 ? "solid" : "glass"; root.bar.lockClockStyle = "custom"; } }
                        }
                    }
                    SRow {
                        t: pal; title: root.bar && root.bar.lockClockMaterial === "solid" ? I18n.tr("Brightness") : I18n.tr("Glass")
                        SSlider {
                            t: pal; resetValue: 0.6; width: 220; from: 0; to: 1
                            leftLabel: root.bar && root.bar.lockClockMaterial === "solid" ? I18n.tr("Subtle") : I18n.tr("Clear")
                            rightLabel: root.bar && root.bar.lockClockMaterial === "solid" ? I18n.tr("Bright") : I18n.tr("Frosted")
                            value: root.bar ? root.bar.lockClockIntensity : 0.6
                            onMoved: v => { if (root.bar) { root.bar.lockClockIntensity = v; root.bar.lockClockStyle = "custom"; } }
                        }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Color")
                        Row {
                            spacing: 8
                            Repeater {
                                model: ["#FFFFFF", "#FFE7C2", "#FFC2D6", "#D9C8FF", "#BFE3FF", "#C6F2D6", "#FFF3A8"]
                                delegate: Rectangle {
                                    required property string modelData
                                    readonly property bool sel: root.bar && root.bar.lockClockTint.toUpperCase() === modelData
                                    width: 22; height: 22; radius: 11
                                    color: modelData
                                    border.width: sel ? 2.5 : 1
                                    border.color: sel ? pal.accent : Qt.rgba(0, 0, 0, 0.2)
                                    scale: swMa.pressed ? 0.88 : 1
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
                                    MouseArea { id: swMa; anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor; onClicked: if (root.bar) root.bar.lockClockTint = parent.modelData }
                                }
                            }
                        }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Date")
                        SSegmented {
                            t: pal; model: ["Friday, October 16", "Fri Oct 16"]; segWidth: 130
                            current: root.bar && root.bar.lockClockDate === "short" ? 1 : 0
                            onPicked: i => { if (root.bar) { root.bar.lockClockDate = i === 1 ? "short" : "long"; root.bar.lockClockStyle = "custom"; } }
                        }
                    }
                }
                Row {
                    spacing: 8
                    // a 6-second look at the lock screen (no real lock) with the settings above
                    SButton {
                        t: pal; text: I18n.tr("Preview")
                        onClicked: {
                            var b = root.bar;
                            var cfg = JSON.stringify({ f: b.lockClockFont, w: b.lockClockWeight, m: b.lockClockMaterial, i: b.lockClockIntensity, c: b.lockClockTint, d: b.lockClockDate });
                            Quickshell.execDetached(["sh", "-c", "MACLOCK_PREVIEW=1 MACLOCK_CLOCK=\"$1\" timeout 6 qs -c MacLock >/dev/null 2>&1", "sh", cfg]);
                        }
                    }
                    SButton { t: pal; text: I18n.tr("Lock Screen Now"); onClicked: { prefsWindow.visible = false; Quickshell.execDetached(["sh", "-c", "pgrep -f -- \"-c [M]acLock\" >/dev/null 2>&1 || qs -c MacLock"]); } }
                }
            }
        }

        // ── Users & Groups ──
        Component {
            id: paneUsers
            Column {
                spacing: 14
                Item {
                    width: parent.width; height: 120
                    Item {
                        id: upic
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 84; height: 84
                        property int ver: 0
                        Item { id: upMask; anchors.fill: parent; visible: false; layer.enabled: true; Rectangle { anchors.fill: parent; radius: width / 2; color: "black" } }
                        Rectangle { anchors.fill: parent; radius: width / 2; color: pal.ctrl }
                        Image {
                            anchors.fill: parent; cache: false; fillMode: Image.PreserveAspectCrop; sourceSize: Qt.size(200, 200)
                            source: "file://" + Quickshell.env("HOME") + "/.face?" + upic.ver
                            layer.enabled: true; layer.effect: MultiEffect { maskEnabled: true; maskSource: upMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                        }
                    }
                    Text { anchors.top: upic.bottom; anchors.topMargin: 8; anchors.horizontalCenter: parent.horizontalCenter; text: root.userName; color: pal.text; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 17; font.weight: Font.DemiBold }
                }
                SCard {
                    t: pal
                    SRow { t: pal; title: I18n.tr("Full name"); Text { text: root.userName; color: pal.text2; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 13 } }
                    SRow { t: pal; title: I18n.tr("Account name"); Text { text: Quickshell.env("USER"); color: pal.text2; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 13 } }
                    SRow { t: pal; title: I18n.tr("Home folder"); Text { text: Quickshell.env("HOME"); color: pal.text2; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 13 } }
                    SRow {
                        t: pal; title: I18n.tr("Picture")
                        subtitle: I18n.tr("Used on the lock screen and here")
                        SButton {
                            t: pal; text: I18n.tr("Change…")
                            onClicked: picProc.running = true
                        }
                    }
                }
                Process {
                    id: picProc
                    command: ["sh", "-c", "f=$(zenity --file-selection --title='Choose a picture' --file-filter='Images | *.png *.jpg *.jpeg *.webp' 2>/dev/null || kdialog --getopenfilename \"$HOME/Pictures\" 'image/png image/jpeg image/webp' 2>/dev/null); [ -n \"$f\" ] && magick \"$f\" -resize 512x512^ -gravity center -extent 512x512 \"$HOME/.face\" && echo ok"]
                    stdout: StdioCollector { onStreamFinished: if (text.indexOf("ok") >= 0) upic.ver++ }
                }
            }
        }

        // ── Keyboard ──
        Component {
            id: paneKeyboard
            Column {
                spacing: 10
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: I18n.tr("Key repeat rate")
                        SSlider { t: pal; resetValue: 35; leftLabel: I18n.tr("Slow"); rightLabel: I18n.tr("Fast"); from: 10; to: 80; value: root.bar ? root.bar.kbRepeatRate : 35; onMoved: v => { if (root.bar) root.bar.kbRepeatRate = Math.round(v); } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Delay until repeat")
                        SSlider { t: pal; resetValue: 0.846; leftLabel: I18n.tr("Long"); rightLabel: I18n.tr("Short"); from: 0; to: 1; value: root.bar ? 1 - (root.bar.kbRepeatDelay - 150) / 650 : 0.6; onMoved: v => { if (root.bar) root.bar.kbRepeatDelay = Math.round(150 + (1 - v) * 650); } }
                    }
                }
                SLabel { t: pal; text: I18n.tr("Layout: ") + "us" + ". Changes apply right away." }
            }
        }

        // ── Mouse ──
        Component {
            id: paneMouse
            Column {
                spacing: 10
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: I18n.tr("Tracking speed")
                        SSlider { t: pal; resetValue: 0; leftLabel: I18n.tr("Slow"); rightLabel: I18n.tr("Fast"); from: -1; to: 1; value: root.bar ? root.bar.mouseSens : 0; onMoved: v => { if (root.bar) root.bar.mouseSens = v; } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Natural scrolling")
                        subtitle: I18n.tr("Content tracks finger movement")
                        SSwitch { t: pal; checked: root.bar ? root.bar.mouseNatural : false; onToggled: v => { if (root.bar) root.bar.mouseNatural = v; } }
                    }
                }
            }
        }

        // ── Trackpad ──
        Component {
            id: paneTrackpad
            Column {
                spacing: 10
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: I18n.tr("Tap to click")
                        SSwitch { t: pal; checked: root.bar ? root.bar.tpTap : true; onToggled: v => { if (root.bar) root.bar.tpTap = v; } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Natural scrolling")
                        SSwitch { t: pal; checked: root.bar ? root.bar.tpNatural : true; onToggled: v => { if (root.bar) root.bar.tpNatural = v; } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Ignore trackpad while typing")
                        SSwitch { t: pal; checked: root.bar ? root.bar.tpDwt : true; onToggled: v => { if (root.bar) root.bar.tpDwt = v; } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Scrolling speed")
                        SSlider { t: pal; resetValue: 0.7; leftLabel: I18n.tr("Slow"); rightLabel: I18n.tr("Fast"); from: 0.2; to: 2; value: root.bar ? root.bar.tpScroll : 0.7; onMoved: v => { if (root.bar) root.bar.tpScroll = v; } }
                    }
                }
            }
        }

        // ── Wallpaper ──
        Component {
            id: paneWallpaper
            Column {
                id: wpPane
                spacing: 10
                property int filter: 0          // 0 all, 1 pictures, 2 animated, 3 favourites
                property string searchText: ""
                readonly property var files: root.bar ? root.bar.wpFiles : []
                readonly property var shown: {
                    var out = [], f = files, q = searchText.trim().toLowerCase();
                    for (var i = 0; i < f.length; i++) {
                        var typeMatch = filter === 0 || (filter === 1 && !f[i].video) || (filter === 2 && f[i].video) || (filter === 3 && f[i].fav);
                        var textMatch = q === "" || f[i].name.toLowerCase().indexOf(q) >= 0;
                        if (typeMatch && textMatch) out.push(f[i]);
                    }
                    return out;
                }
                readonly property string curVideo: root.bar ? root.bar.wallpaperVideo : ""
                readonly property string curStill: root.bar ? root.bar.wallpaperPath : root.wallpaperPath
                readonly property string curPath: curVideo !== "" ? curVideo : curStill
                readonly property string curPreview: (root.bar && curVideo !== "") ? (root.bar.wpPreviews[curVideo] || "") : ""
                function nameOf(p) { var n = p.substring(p.lastIndexOf("/") + 1); var k = n.lastIndexOf("."); return k > 0 ? n.substring(0, k) : n; }
                Component.onCompleted: if (root.bar) root.bar.wpRefresh()

                // current wallpaper, big, playing if it's animated
                SCard {
                    t: pal
                    Item {
                        width: parent.width
                        height: 190
                        Item {
                            id: curBox
                            x: 14; y: 14
                            width: 256; height: 160
                            Item {
                                id: curMask
                                anchors.fill: parent; visible: false
                                layer.enabled: true; layer.smooth: true
                                Rectangle { anchors.fill: parent; radius: 10; color: "black" }
                            }
                            Item {
                                anchors.fill: parent
                                layer.enabled: true; layer.smooth: true
                                layer.effect: MultiEffect { maskEnabled: true; maskSource: curMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                                Rectangle { anchors.fill: parent; color: pal.ctrl }
                                Image {
                                    anchors.fill: parent
                                    source: wpPane.curStill !== "" ? "file://" + wpPane.curStill : ""
                                    sourceSize.width: 520
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true; smooth: true
                                }
                                Loader {
                                    anchors.fill: parent
                                    active: wpPane.curVideo !== "" && prefsWindow.visible && wpPane.curPreview !== ""
                                    sourceComponent: AnimatedImage {
                                        source: "file://" + wpPane.curPreview
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true; cache: false; playing: true
                                    }
                                }
                            }
                            Rectangle { anchors.fill: parent; radius: 10; color: "transparent"; border.width: 1; border.color: pal.cardBorder }
                        }
                        Column {
                            x: curBox.x + curBox.width + 18
                            anchors.verticalCenter: curBox.verticalCenter
                            width: parent.width - x - 14
                            spacing: 6
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: wpPane.curPath !== "" ? wpPane.nameOf(wpPane.curPath) : I18n.tr("No wallpaper")
                                color: pal.text; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 15; font.weight: Font.DemiBold
                            }
                            Text {
                                width: parent.width
                                text: wpPane.curVideo !== "" ? I18n.tr("Animated wallpaper") : I18n.tr("Picture")
                                color: pal.text2; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 12
                            }
                            Text {
                                width: parent.width; wrapMode: Text.WordWrap
                                visible: wpPane.curVideo !== ""
                                text: I18n.tr("Plays on every display and pauses behind fullscreen windows. The Liquid Glass and the lock screen use it too.")
                                color: pal.text3; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 11
                            }
                            Row {
                                spacing: 8
                                topPadding: 4
                                SButton { t: pal; text: I18n.tr("Open Folder"); onClicked: Quickshell.execDetached(["xdg-open", root.bar ? root.bar.wpDirEff : ""]) }
                                SButton { t: pal; text: I18n.tr("Refresh"); onClicked: if (root.bar) root.bar.wpRefresh() }
                            }
                        }
                    }
                }

                SCard {
                    t: pal
                    visible: wpPane.curVideo !== "" || (root.bar && root.bar.liveWallGlass)
                    SRow {
                        t: pal
                        title: I18n.tr("Animated wallpaper in glass")
                        subtitle: I18n.tr("Play the animated wallpaper inside the Liquid Glass in real time. Off by default: the glass refracts a still frame and uses no video memory.")
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.liveWallGlass : false
                            onToggled: v => { if (root.bar) root.bar.liveWallGlass = v; }
                        }
                    }
                }

                // macOS: a wallpaper that comes in light and dark versions gets an appearance picker
                SCard {
                    t: pal
                    visible: root.bar && root.bar.wpHasPair
                    SRow {
                        t: pal
                        title: I18n.tr("Appearance")
                        subtitle: {
                            var a = root.bar ? root.bar.wallpaperAppearance : "auto";
                            return a === "auto" ? "Follows Light / Dark Mode"
                                 : a === "dynamic" ? "Changes through the day: light by day, dark at night, blending at sunrise and sunset"
                                 : a === "light" ? "Always the light version" : "Always the dark version";
                        }
                        SSegmented {
                            t: pal
                            model: ["Automatic", "Light", "Dark", "Dynamic"]
                            segWidth: 78
                            current: ["auto", "light", "dark", "dynamic"].indexOf(root.bar ? root.bar.wallpaperAppearance : "auto")
                            onPicked: i => { if (root.bar) root.bar.wallpaperAppearance = ["auto", "light", "dark", "dynamic"][i]; }
                        }
                    }
                }

                Item {
                    width: parent.width; height: 30
                    SLabel { t: pal; header: true; width: 200; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("Wallpapers"); topPadding: 0 }
                    SSegmented {
                        t: pal
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        model: ["All", "Pictures", "Animated", "★ Favourites"]
                        segWidth: 88
                        current: wpPane.filter
                        onPicked: i => wpPane.filter = i
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 36
                    radius: 10
                    color: pal.ctrl
                    border.width: 1
                    border.color: wpSearchInput.activeFocus ? pal.accent : pal.cardBorder
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        spacing: 8
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "⌕"
                            color: pal.text3
                            font.family: Fonts.forWeight(font.weight, pal.fam); font.pixelSize: 19
                        }
                        Item {
                            width: parent.width - 52
                            height: parent.height
                            TextInput {
                                id: wpSearchInput
                                anchors.fill: parent
                                verticalAlignment: TextInput.AlignVCenter
                                color: pal.text
                                selectionColor: pal.accent
                                font.family: root.fontForWeight(font.weight, pal.fam)
                                font.pixelSize: 12
                                clip: true
                                selectByMouse: true
                                onTextChanged: wpPane.searchText = text
                            }
                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                text: I18n.tr("Search wallpapers")
                                color: pal.text3
                                font.family: root.fontForWeight(font.weight, pal.fam)
                                font.pixelSize: 12
                                visible: wpSearchInput.text === "" && !wpSearchInput.activeFocus
                                MouseArea { anchors.fill: parent; onClicked: wpSearchInput.forceActiveFocus() }
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: wpSearchInput.text !== ""
                            text: "×"
                            color: pal.text2
                            font.family: Fonts.forWeight(font.weight, pal.fam); font.pixelSize: 18
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                onClicked: { wpSearchInput.clear(); wpSearchInput.forceActiveFocus(); }
                            }
                        }
                    }
                }

                GridView {
                    id: wpFlow
                    width: parent.width
                    cellWidth: Math.floor((width - 20) / 3)
                    cellHeight: Math.round(cellWidth * 0.625) + 32
                    height: Math.min(contentHeight, cellHeight * 3)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: wpPane.shown
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        width: 6
                        background: Rectangle {
                            color: pal.cardBorder
                            radius: 3
                            opacity: 0.45
                        }
                        contentItem: Rectangle {
                            color: pal.text3
                            radius: 3
                        }
                    }
                    delegate: Item {
                            id: wt
                            required property var modelData
                            width: wpFlow.cellWidth
                            height: wpFlow.cellHeight
                            readonly property bool cur: modelData.video ? wpPane.curVideo === modelData.path
                                                                        : (wpPane.curVideo === "" && wpPane.curStill === modelData.path)
                            Item {
                                id: wtBox
                                x: 5; y: 5
                                width: parent.width - 10; height: parent.height - 32
                                scale: wtMa.pressed ? 0.98 : 1
                                Item {
                                    id: wtMask
                                    anchors.fill: parent; visible: false
                                    layer.enabled: true; layer.smooth: true
                                    Rectangle { anchors.fill: parent; radius: 9; color: "black" }
                                }
                                Item {
                                    anchors.fill: parent
                                    layer.enabled: true; layer.smooth: true
                                    layer.effect: MultiEffect { maskEnabled: true; maskSource: wtMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                                    Rectangle { anchors.fill: parent; color: pal.ctrl }
                                    Image {
                                        anchors.fill: parent
                                        source: "file://" + (wt.modelData.video ? wt.modelData.thumb : wt.modelData.path)
                                        sourceSize.width: 260
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true; smooth: true
                                        opacity: status === Image.Ready ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 250 } }
                                    }
                                    Loader {
                                        anchors.fill: parent
                                        active: wt.modelData.video && wt.modelData.preview !== "" && wtMa.containsMouse
                                        sourceComponent: AnimatedImage {
                                            source: "file://" + wt.modelData.preview
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true; cache: false; playing: true
                                        }
                                    }
                                    Rectangle {
                                        visible: wt.modelData.video
                                        x: 6; y: 6
                                        width: wtBadge.implicitWidth + 12; height: 18; radius: 9
                                        color: Qt.rgba(0, 0, 0, 0.5)
                                        Text {
                                            id: wtBadge
                                            anchors.centerIn: parent
                                            text: I18n.tr("\u25B6  Animated")
                                            color: "white"; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 9; font.weight: Font.DemiBold
                                        }
                                    }
                                }
                                Rectangle {
                                    anchors.fill: parent; anchors.margins: wt.cur ? -3 : 0
                                    radius: wt.cur ? 12 : 9
                                    color: "transparent"
                                    border.width: wt.cur ? 2.5 : 1
                                    border.color: wt.cur ? pal.accent : pal.cardBorder
                                }
                                MouseArea {
                                    id: wtMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (root.bar) root.bar.wpApply(wt.modelData.path)
                                }
                                    Rectangle {
                                        anchors.right: parent.right; anchors.top: parent.top
                                        anchors.margins: 7
                                        width: 26; height: 26; radius: 13
                                        visible: wt.modelData.fav || wtMa.containsMouse || wtFavMa.containsMouse
                                        color: Qt.rgba(0, 0, 0, wtFavMa.containsMouse ? 0.72 : 0.52)
                                        Text {
                                            anchors.centerIn: parent
                                            text: wt.modelData.fav ? "★" : "☆"
                                            color: wt.modelData.fav ? "#ffd60a" : "white"
                                            font.family: Fonts.forWeight(font.weight, pal.fam); font.pixelSize: 16
                                        }
                                        MouseArea {
                                            id: wtFavMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: if (root.bar) root.bar.wpToggleFav(wt.modelData.path)
                                        }
                                    }
                            }
                            Text {
                                anchors.bottom: parent.bottom
                                x: 5
                                width: parent.width - 10
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideMiddle
                                text: wt.modelData.name
                                color: wt.cur ? pal.text : pal.text2
                                font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 11
                            }
                    }
                }
                SLabel {
                    t: pal
                    visible: wpPane.shown.length === 0
                    text: wpPane.searchText.trim() !== "" ? I18n.tr("No wallpapers match “") + wpPane.searchText + "”."
                        : wpPane.filter === 2 ? "No animated wallpapers yet. Drop .mp4 / .webm videos into " + (root.bar ? root.bar.wpDirEff : "~/Pictures/Wallpapers") + "."
                                              : I18n.tr("Nothing here yet.")
                }
                SLabel { t: pal; text: I18n.tr("Tip: Ctrl+Alt+W opens the quick wallpaper picker, which shows animated wallpapers too.") }
            }
        }

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
                        Image {
                            x: (parent.width - width) / 2
                            y: 16
                            width: 84; height: 84
                            source: Qt.resolvedUrl("assets/macshell-logo.png")
                            sourceSize.width: 256; sourceSize.height: 256
                            fillMode: Image.PreserveAspectFit
                            smooth: true; mipmap: true
                        }
                        Text {
                            y: 108
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: "macshell"
                            color: pal.text
                            font.family: root.fontForWeight(font.weight, pal.fam)
                            font.pixelSize: 21
                            font.weight: Font.DemiBold
                        }
                        Text {
                            y: 138
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: I18n.tr("Version 0.3.9 \u2022 Hyprland \u2022 Quickshell")
                            color: pal.text2
                            font.family: root.fontForWeight(font.weight, pal.fam)
                            font.pixelSize: 12
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Configuration")
                        Text {
                            text: "~/.config/macdock"
                            color: pal.text2
                            font.family: root.fontForWeight(font.weight, pal.fam)
                            font.pixelSize: 13
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Open configuration folder")
                        SButton {
                            t: pal
                            text: I18n.tr("Open")
                            onClicked: Quickshell.execDetached(["xdg-open", root.configDir])
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Install dependencies")
                        subtitle: I18n.tr("Installs everything MacShell uses (Quickshell, awww, mpvpaper, ffmpeg, wf-recorder, fonts, icons…) with your package manager, in a terminal")
                        SButton {
                            t: pal
                            text: I18n.tr("Install\u2026")
                            onClicked: {
                                var inst = Quickshell.env("HOME") + "/.local/share/macshell/install.sh";
                                var term = root.bar ? root.bar.terminal : "kitty";
                                Quickshell.execDetached(["sh", "-c", term + " -e sh -c '\"$0\" --deps-only; echo; echo Press Enter to close; read x'", inst]);
                            }
                        }
                    }
                }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Reset MacShell")
                        subtitle: I18n.tr("Restore every setting to its default (appearance, Dock, Menu Bar, widgets, lock screen, input). Pinned apps and your widgets' layout are kept.")
                        SButton {
                            t: pal
                            destructive: true
                            text: aboutCol.armed ? I18n.tr("Click to Confirm") : I18n.tr("Reset\u2026")
                            onClicked: {
                                if (aboutCol.armed) { aboutCol.armed = false; root.resetSettings(); }
                                else { aboutCol.armed = true; disarm.restart(); }
                            }
                        }
                    }
                }

                // ── Credits ──
                SLabel { t: pal; header: true; text: I18n.tr("Credits") }
                SCard {
                    t: pal
                    Repeater {
                        model: [
                            { img: "assets/credits/0-ss.jpg", name: "Rickky", gh: "0-ss",
                              role: "Owner — the menu bar, the Dock, the Liquid Glass the widgets and more... The one who actually knew what he was doing" },
                            { img: "assets/credits/vsoultann.png", name: "vSuol", gh: "vsoultann",
                              role: "Contributors — improved the Settings app, and most of the bugs you would find" }
                        ]
                        delegate: Item {
                            id: cr
                            required property var modelData
                            width: parent.width; height: 72
                            Rectangle { visible: cr.y > 0.5; x: 14; width: parent.width - 14; height: 1; color: pal.sep }
                            Item {
                                id: crPic
                                x: 14; anchors.verticalCenter: parent.verticalCenter
                                width: 44; height: 44
                                Item { id: crMask; anchors.fill: parent; visible: false; layer.enabled: true; Rectangle { anchors.fill: parent; radius: width / 2; color: "black" } }
                                Image {
                                    anchors.fill: parent
                                    source: Qt.resolvedUrl(cr.modelData.img)
                                    sourceSize: Qt.size(96, 96)
                                    fillMode: Image.PreserveAspectCrop; smooth: true; mipmap: true
                                    layer.enabled: true
                                    layer.effect: MultiEffect { maskEnabled: true; maskSource: crMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                                }
                                Rectangle { anchors.fill: parent; radius: width / 2; color: "transparent"; border.width: 1; border.color: pal.cardBorder }
                            }
                            Column {
                                x: 70; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 70 - 90
                                spacing: 2
                                Text { text: cr.modelData.name; color: pal.text; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 13; font.weight: Font.DemiBold }
                                Text { width: parent.width; text: I18n.tr(cr.modelData.role); wrapMode: Text.WordWrap; color: pal.text2; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 11 }
                            }
                            Text {
                                anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                                text: "@" + cr.modelData.gh
                                color: pal.accent; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 12
                                font.underline: crMa.containsMouse
                                MouseArea { id: crMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["xdg-open", "https://github.com/" + cr.modelData.gh]) }
                            }
                        }
                    }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: 4
                    text: I18n.tr("Designed by Apple in California.\nRebuilt on Linux by two people who could not afford the Mac.")
                    color: pal.text3; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 11
                }

                // (keep scrolling…)
                Item { width: 1; height: 900 }

                // ── AppleCare+ — nobody asked. The button does nothing. ──
                SCard {
                    t: pal
                    Item {
                        width: parent.width; height: 214
                        Image {
                            anchors.horizontalCenter: parent.horizontalCenter; y: 16
                            width: 36; height: 36
                            source: Qt.resolvedUrl(pal.dark ? "apple-logo-white.svg" : "apple-logo-black.svg")
                            sourceSize: Qt.size(72, 72); fillMode: Image.PreserveAspectFit; smooth: true
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter; y: 64
                            text: I18n.tr("Protect your MacShell with AppleCare+")
                            color: pal.text; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 17; font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter; y: 90
                            width: parent.width - 60; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                            text: I18n.tr("Unlimited repairs for accidental damage, 24/7 priority access to Apple experts, and battery service coverage. Same price as for a MacBook Pro.")
                            color: pal.text2; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 12
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter; y: 136
                            text: I18n.tr("$279.00 for 3 years or $99.99/yr.")
                            color: pal.text; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 13; font.weight: Font.Medium
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter; y: 166
                            width: 150; height: 32; radius: 16
                            color: careMa.pressed ? Qt.darker(pal.accent, 1.15) : pal.accent
                            scale: careMa.pressed ? 0.96 : 1
                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }
                            Text { anchors.centerIn: parent; text: I18n.tr("Add AppleCare+"); color: "white"; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 13; font.weight: Font.DemiBold }
                            MouseArea { id: careMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor }
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
    // the Dock's cells live in a keyed ListModel updated in place: a cell is only created when its item appears and
    // only destroyed after it has animated out — every other cell (and its live window preview) keeps running
    property var itemMap: ({})
    ListModel { id: dockModel }
    function syncModel(list) {
        var m = dockModel;
        for (var i = 0; i < list.length; i++) {
            var k = list[i].key;
            if (i < m.count && m.get(i).key === k) continue;
            var j = -1;
            for (var x = i + 1; x < m.count; x++) if (m.get(x).key === k) { j = x; break; }
            if (j >= 0) m.move(j, i, 1); else m.insert(i, { key: k });
        }
        while (m.count > list.length) m.remove(m.count - 1);
    }
    property var leaving: ({})          // key → time it started leaving
    readonly property int leaveMs: 340
    Timer { id: leaveTimer; interval: root.leaveMs + 30; onTriggered: root.rebuild() }
    property string lastSig: ""

    // ───────────── LOGIC ─────────────
    function openPrefs(pane) {
        if (!settingsEnabled) return;
        if (bar) {
            darkMode = bar.darkMode;
            appearanceMode = bar.appearanceMode;
        }
        if (pane !== undefined && pane !== "") {
            for (var i = 0; i < prefsWindow.panes.length; i++)
                if (prefsWindow.panes[i].id === pane) { prefsWindow.go(i); break; }
        }
        prefsWindow.visible = true;
        prefsWindow.requestActivate();
    }

    function togglePrefs(pane) {
        if (prefsWindow.visible) prefsWindow.visible = false;
        else openPrefs(pane);
    }

    function resetPins() {
        pinned = defaultPinned;
        store.setText(JSON.stringify(defaultPinned.slice(), null, 2));
        rebuild();
    }

    function resetSettings() {
        dockEnabled = true;
        settingsEnabled = true;
        if (bar) {
            bar.resetSettings();
            bar.uiSounds = true; bar.gamingMode = false; bar.gamingAuto = true; bar.lockArtBackground = true;
            bar.applyLockClockPreset("glass");
            bar.wallpaperAppearance = "auto"; bar.notifDnd = false; bar.nightOn = false; bar.keepAwake = false;
            bar.kbRepeatRate = 35; bar.kbRepeatDelay = 250; bar.mouseSens = 0; bar.mouseNatural = false;
            bar.tpNatural = true; bar.tpTap = true; bar.tpDwt = true; bar.tpScroll = 0.7;
        }
        if (hub && hub.widgets) { hub.widgets.tempUnit = "C"; hub.widgets.locMode = "auto"; hub.widgets.cityName = ""; hub.widgets.widgetScale = 1.0; }
        Quickshell.execDetached(["sh", "-c", "rm -f \"$HOME/.config/maclock/settings.json\""]);
        iconSize = 52; magnification = 1.7; magnificationEnabled = true;
        spacing = 6; margin = 6; cornerRadius = 18;
        darkMode = true; appearanceMode = "dark"; glassOpacity = 0.42; glassBlur = 5; glassLiquid = 1.0; dockStyle = "blur"; accent = "#0a84ff"; fontFamily = "Open Runde";
        iconTint = false; iconTintColor = "#0a84ff"; iconTintStrength = 1.0;
        hideMode = "smart"; hideDelay = 450; monitor = "";
        showTrash = true; showLabels = true; showIndicators = true; bounceOnLaunch = true; showThumbs = true; windowCapture = true; glassLive = true;
    }

    // ── settings persistence (~/.config/macdock/settings.json) ──
    readonly property string settingsSig: [dockEnabled, settingsEnabled, iconSize, magnification, magnificationEnabled, spacing, margin,
        cornerRadius, darkMode, appearanceMode, glassOpacity, glassBlur, glassLiquid, dockStyle, wallpaperPath, String(accent), fontFamily, hideMode, hideDelay, monitor,
        showTrash, showLabels, showIndicators, bounceOnLaunch, showThumbs, windowCapture, glassLive, iconTint, iconTintColor, iconTintStrength].join("|")
    property bool settingsReady: false
    onSettingsSigChanged: if (settingsReady) saveTimer.restart()
    onShowTrashChanged: { rebuild(); if (showTrash) trashCheck(); }
    onShowThumbsChanged: rebuild()
    onWindowCaptureChanged: rebuild()

    function saveSettings() {
        var o = {
            dockEnabled: dockEnabled, settingsEnabled: settingsEnabled, iconSize: iconSize, magnification: magnification, magnificationEnabled: magnificationEnabled,
            spacing: spacing, margin: margin, cornerRadius: cornerRadius,
            darkMode: darkMode, appearanceMode: appearanceMode, glassOpacity: glassOpacity, dockStyle: dockStyle, wallpaperPath: wallpaperPath, glassDebug: glassDebug,
            glassRim: glassRim, glassGrain: glassGrain, glassLiquid: glassLiquid, glassBlur: glassBlur,
            accent: String(accent), fontFamily: fontFamily,
            hideMode: hideMode, hideDelay: hideDelay, monitor: monitor,
            showTrash: showTrash, showLabels: showLabels, showIndicators: showIndicators,
            bounceOnLaunch: bounceOnLaunch, showThumbs: showThumbs, windowCapture: windowCapture, glassLive: glassLive,
            iconTint: iconTint, iconTintColor: iconTintColor, iconTintStrength: iconTintStrength
        };
        settingsStore.setText(JSON.stringify(o, null, 2));
    }

    function applySettings(o) {
        if (!o || typeof o !== "object") return;
        var keys = ["dockEnabled", "settingsEnabled", "iconSize", "magnification", "magnificationEnabled", "spacing", "margin", "cornerRadius",
                    "darkMode", "appearanceMode", "glassOpacity", "dockStyle", "wallpaperPath", "glassDebug", "glassRim", "glassGrain", "glassLiquid", "glassBlur", "accent", "fontFamily", "hideMode", "hideDelay", "monitor",
                    "showTrash", "showLabels", "showIndicators", "bounceOnLaunch", "showThumbs", "windowCapture", "glassLive", "iconTint", "iconTintColor", "iconTintStrength"];
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

    // MacShell's own windows (About This Linux, Settings, Finder, Photos ...) all have the app id "org.quickshell":
    // they show the MacShell logo and name instead of a generic icon
    readonly property string logoPath: decodeURIComponent(String(Qt.resolvedUrl("assets/macshell-logo.png")).replace(/^file:\/\//, ""))
    function isShellApp(appId) { return appId === "org.quickshell"; }

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
        if (bar) bar.playSound("trash", 0.8);
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

    // MacShell's own windows all have the app id "org.quickshell": the Clock window counts as the Clock app
    function appOf(tl) { return (tl.appId === "org.quickshell" && tl.title === "Clock") ? "macshell-clock" : tl.appId; }
    function windowsFor(key) {
        var out = [];
        var tls = ToplevelManager.toplevels.values;
        for (var i = 0; i < tls.length; i++) {
            if (tls[i].appId && keyOf(appOf(tls[i])) === key) out.push(tls[i]);
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
        if (item.entry || item.key) {
            var L = {};
            for (var k in launching) L[k] = launching[k];
            L[item.key] = Date.now();
            launching = L;
            // resolve the desktop entry again at click time: the one stored in the dock model can be a stale object
            // (after the app database reloads it turned into "TypeError ... execute is not a function", and Files never opened)
            var ent = null;
            var rid = item.appId || item.key;
            try { ent = DesktopEntries.byId(rid); } catch (err) { ent = null; }
            if (!ent) { try { ent = DesktopEntries.heuristicLookup ? DesktopEntries.heuristicLookup(item.key) : null; } catch (err2) { ent = null; } }
            var ok = false;
            if (ent && typeof ent.execute === "function") { try { ent.execute(); ok = true; } catch (err3) { ok = false; } }
            if (!ok) {
                var id = rid;
                console.log("[macdock] launching", id, "via gtk-launch (desktop entry unavailable)");
                Quickshell.execDetached(["sh", "-c", 'gtk-launch "$1" 2>/dev/null || gtk-launch "$1.desktop" 2>/dev/null || exec "$1"', "sh", id]);
            }
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
            m.push({ kind: "item", label: I18n.tr("Show"), run: function () { activate(item, false); } });
            m.push({ kind: "item", label: I18n.tr("Close"), run: function () { if (item.tl) item.tl.close(); } });
            m.push({ kind: "sep" });
            m.push({ kind: "item", label: I18n.tr("Settings\u2026"), run: function() { root.openPrefs(); } });
            return m;
        }
        if (item.special === "trash") {
            m.push({ kind: "item", label: I18n.tr("Open"), run: function () { activate(item, false); } });
            m.push({ kind: "item", label: I18n.tr("Empty Trash"), confirm: true, disabled: !trashFull, run: function () { root.emptyTrash(); } });
            m.push({ kind: "sep" });
            m.push({ kind: "item", label: I18n.tr("Settings\u2026"), run: function() { root.openPrefs(); } });
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
            m.push({ kind: "item", label: item.pinned ? I18n.tr("Remove from Dock") : I18n.tr("Keep in Dock"),
                     run: function () { togglePin(item); } });
            m.push({ kind: "item", label: wins.length > 0 ? I18n.tr("New Window") : I18n.tr("Open"),
                     run: function () { activate(item, true); } });
        }
        if (wins.length > 0) {
            m.push({ kind: "sep" });
            m.push({ kind: "item", label: I18n.tr("Quit"), run: function () {
                var ws = windowsFor(item.key);
                for (var j = 0; j < ws.length; j++) ws[j].close();
            } });
        }
        
        m.push({ kind: "sep" });
        m.push({ kind: "item", label: I18n.tr("Settings\u2026"), run: function() { root.openPrefs(); } });

        return m;
    }

    function rebuild() {
        var tls = ToplevelManager.toplevels.values;
        var running = {};
        var runOrder = [];
        for (var i = 0; i < tls.length; i++) {
            var id = appOf(tls[i]);
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
            list.push({ kind: "app", key: ek, appId: e.id, name: e.name, icon: e.icon, entry: e,
                        running: !!running[ek], pinned: true });
        }

        var extras = [];
        for (var r = 0; r < runOrder.length; r++) if (!seen[runOrder[r].key]) extras.push(runOrder[r]);
        if (extras.length > 0 && list.length > 0) list.push({ kind: "sep", key: "sep:run" });
        for (var x = 0; x < extras.length; x++) {
            var e2 = lookup(extras[x].appId);
            var own = isShellApp(extras[x].appId);
            list.push({ kind: "app", key: extras[x].key, appId: e2 ? e2.id : extras[x].appId,
                        name: own ? "MacShell" : (e2 ? e2.name : extras[x].appId),
                        icon: own ? logoPath : (e2 ? e2.icon : extras[x].appId.toLowerCase()),
                        entry: e2, running: true, pinned: false });
        }

        // window previews: one cell per open window, in their own section next to the Trash
        var winItems = [], liveWins = [];
        if (showThumbs) {
            for (var w = 0; w < tls.length; w++) {
                var tl = tls[w];
                if (!tl.appId || tl.title === "macshell Settings") continue;
                // live capture off: a preview cell is only an app icon, so a pinned app (its icon is already in the Dock) gets none; unpinned apps keep theirs
                if (!windowCapture && seen[keyOf(appOf(tl))]) continue;
                var e3 = lookup(appOf(tl));
                var wid = winIdFor(tl);
                liveWins.push(tl);
                if (winAge(tl) < 200) { if (!youngWin.running) youngWin.start(); continue; }     // no preview (= no capture) for brand-new windows
                var own3 = isShellApp(tl.appId);
                winItems.push({ kind: "win", key: "win:" + wid, tl: tl,
                                name: own3 ? (tl.title || "MacShell") : (e3 ? e3.name : tl.appId),
                                icon: own3 ? logoPath : (e3 ? e3.icon : tl.appId.toLowerCase()),
                                entry: null, running: false, pinned: false });
            }
        }
        var keep = [];
        for (var wi = 0; wi < winIdList.length; wi++) if (liveWins.indexOf(winIdList[wi].tl) >= 0) keep.push(winIdList[wi]);
        winIdList = keep;

        if (showTrash || winItems.length > 0) {
            list.push({ kind: "sep", key: "sep:win" });
            for (var wj = 0; wj < winItems.length; wj++) list.push(winItems[wj]);
        }
        if (showTrash && winItems.length > 0) list.push({ kind: "sep", key: "sep:trash" });
        if (showTrash) {
            list.push({ kind: "app", key: "__trash", name: "Trash", icon: "user-trash",
                        entry: null, running: false, pinned: true, special: "trash" });
        }

        var firstBuild = (lastSig === "");
        // closed apps / windows don't vanish: they stay for a moment as "leaving" cells that shrink and fade out —
        // the opening animation played backwards — then are dropped by leaveTimer's rebuild
        var liveKeys = {};
        for (var lq = 0; lq < list.length; lq++) if (list[lq].key) liveKeys[list[lq].key] = true;
        var LV = {};
        for (var lk2 in leaving) if (!liveKeys[lk2] && now - leaving[lk2] < leaveMs) LV[lk2] = leaving[lk2];
        if (!firstBuild) {
            var prev = items || [];
            for (var pv = 0; pv < prev.length; pv++) {
                var po = prev[pv];
                if (!po.key || liveKeys[po.key]) continue;
                if (LV[po.key] === undefined) { if (po.leaving) continue; LV[po.key] = now; }
                // put it back after the item that preceded it last time
                var at = 0;
                for (var pb = pv - 1; pb >= 0; pb--) {
                    var ix = -1;
                    for (var q = 0; q < list.length; q++) if (list[q].key === prev[pb].key) { ix = q; break; }
                    if (ix >= 0) { at = ix + 1; break; }
                }
                var cp = {};
                for (var f in po) cp[f] = po[f];
                cp.leaving = true; cp.leaveAt = LV[po.key]; cp.fresh = false;
                cp.tl = null;          // the window is gone: never capture a destroyed toplevel (that crashed the shell)
                list.splice(at, 0, cp);
            }
        }
        leaving = LV;
        var anyLeaving = false;
        for (var lk3 in LV) { anyLeaving = true; break; }
        if (anyLeaving) leaveTimer.restart();

        var nowKeys = {}, nA = 0, nS = 0, sig = [];
        for (var n = 0; n < list.length; n++) {
            var it = list[n];
            it.nA = nA; it.nS = nS;
            if (it.kind === "sep") nS++; else nA++;
            if (it.key && !it.leaving) {
                it.fresh = !firstBuild && !knownKeys[it.key];
                nowKeys[it.key] = true;
            }
            sig.push(it.kind + ":" + (it.key || "") + ":" + it.running + ":" + (it.icon || "") + (it.leaving ? ":L" : ""));
        }
        appCount = nA;
        sepCount = nS;
        knownKeys = nowKeys;

        var s = sig.join("|");
        if (s !== lastSig) {
            lastSig = s;
            var map = {};
            for (var mi = 0; mi < list.length; mi++) map[list[mi].key] = list[mi];
            itemMap = map;
            items = list;
            syncModel(list);
        }
    }

    // ═════════════ LIQUID GLASS BACKEND ═════════════
    // glassState: "idle" → "building" (qsb running) → "ready" | "failed". "failed" falls back to Normal Blur.
    property string glassState: "idle"
    readonly property bool liquidActive: dockStyle === "liquid" && glassState === "ready" && !(bar && bar.gaming)
    // Settings' own glass (back / forward pill, knobs of switches and sliders): available whenever the shader is built,
    // whatever the Dock style is
    readonly property bool settingsGlass: glassState === "ready" && !(bar && bar.gaming)
    readonly property string glassShaderSrc: decodeURIComponent(Qt.resolvedUrl("liquidglass.frag").toString().replace("file://", ""))
    readonly property string glassShaderOut: configDir + "/liquidglass.frag.qsb"
    readonly property url glassShaderUrl: "file://" + glassShaderOut

    onDockStyleChanged: if (dockStyle === "liquid") startGlass()
    onGlassStateChanged: console.log("[macdock-glass] state:", glassState)
    function startGlass() {
        if (dockGlassState === "idle" || dockGlassState === "failed") {
            dockGlassState = "building";
            dockQsbProc.running = true;
        }
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

    // The Dock has its own glass shader (dockglass.frag: Tahoe-style edge light, outer hairline, shadow, adaptive tint), built the
    // same way. It is independent of liquidglass.frag: if it fails to build or to load, the Dock keeps using the shared shader, so
    // the Control Center, menu bar and widgets are never affected.
    property string dockGlassState: "idle"        // idle → building → ready | failed
    readonly property bool dockGlassNew: dockGlassState === "ready"
    readonly property string dockGlassSrc: decodeURIComponent(Qt.resolvedUrl("dockglass.frag").toString().replace("file://", ""))
    readonly property string dockGlassOut: configDir + "/dockglass.frag.qsb"
    readonly property url dockGlassUrl: dockGlassNew ? "file://" + dockGlassOut : glassShaderUrl
    Process {
        id: dockQsbProc
        command: ["sh", "-c",
            "mkdir -p \"$(dirname \"$2\")\"; "
            + "for q in qsb qsb6 qsb-qt6 /usr/lib/qt6/bin/qsb /usr/lib64/qt6/bin/qsb /usr/lib/qt/bin/qsb; do "
            + "  if command -v \"$q\" >/dev/null 2>&1; then \"$q\" --qt6 -o \"$2\" \"$1\" && exit 0; fi; "
            + "done; "
            + "[ -f \"$1.qsb\" ] && cp \"$1.qsb\" \"$2\" && exit 0; "
            + "exit 1",
            "sh", root.dockGlassSrc, root.dockGlassOut]
        stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.log("[macdock-glass] dockglass qsb:", text.trim()) }
        onExited: (code, status) => root.dockGlassState = (code === 0 ? "ready" : "failed")
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
    Binding { target: root.hub; property: "dockWantsGeo"; value: root.liquidActive && (root.dockEnabled || prefsWindow.visible) }
    // window captures are admitted by the shared gate in shell.qml (hub.tlFor): 0.2 s after a window appears, one every 110 ms

    // ── smart hide: which monitors have a non-floating window on their active workspace ──
    property var busyMonitors: ({})
    property var monData: []
    property bool refreshPending: false

    function refreshBusy() {
        if (monProc.running || clientProc.running) { refreshPending = true; return; }
        monProc.running = true;
    }

    // Match the 0.3.0 method: recompute directly from hyprctl's monitor/client snapshot after each compositor event.
    function computeBusy(clients) {
        if (!Array.isArray(clients)) clients = [];
        var busy = {};
        for (var m = 0; m < monData.length; m++) {
            var mon = monData[m];
            if (!mon || mon.id === undefined || !mon.name) continue;
            var ids = [mon.activeWorkspace && mon.activeWorkspace.id !== undefined ? mon.activeWorkspace.id : -999];
            if (mon.specialWorkspace && mon.specialWorkspace.id !== undefined && mon.specialWorkspace.id !== 0) ids.push(mon.specialWorkspace.id);
            for (var c = 0; c < clients.length; c++) {
                var cl = clients[c];
                if (!cl || cl.floating || !cl.mapped || cl.hidden) continue;
                if (cl.monitor !== mon.id) continue;
                if (!cl.workspace || cl.workspace.id === undefined) continue;
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
                try { root.monData = JSON.parse(text); } catch (err) { root.monData = []; }
                clientProc.running = true;
            }
        }
    }
    Process {
        id: clientProc
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.computeBusy(JSON.parse(text)); } catch (err) { root.computeBusy([]); }
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

            // the lifted item lives in its own full-screen, click-through overlay so it can go anywhere on the screen
            // (the Dock's own surface only covers the bottom of the screen — it used to be cut off half way up)
            PanelWindow {
                id: tearWin
                screen: win.modelData
                visible: ui.tearing || tearLaunch.running || tearHome.running || ghostFade.running || oldOut.running
                anchors { left: true; right: true; top: true; bottom: true }
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                mask: Region {}
                WlrLayershell.namespace: "macdock-drag"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                // the window where it WAS: a still copy that takes its place the instant the real window jumps to the
                // pointer, then fades and sinks away — so the old spot never just blinks empty
                Item {
                    id: oldSnap
                    property bool shown: false
                    visible: shown && opacity > 0.01
                    opacity: 0
                    transformOrigin: Item.Center
                    RectangularShadow { anchors.fill: parent; radius: 10; blur: 30; offset.y: 8; color: Qt.rgba(0, 0, 0, 0.30) }
                    Rectangle { anchors.fill: parent; radius: 10; color: Qt.rgba(0.09, 0.08, 0.09, 0.88) }
                    ScreencopyView {
                        id: oldSv
                        anchors.fill: parent
                        live: false
                        layer.enabled: true
                        layer.effect: MultiEffect { maskEnabled: true; maskSource: oldMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                    }
                    Item { id: oldMask; anchors.fill: parent; visible: false; layer.enabled: true; Rectangle { anchors.fill: parent; radius: 10; color: "black" } }
                    ParallelAnimation {
                        id: oldOut
                        NumberAnimation { target: oldSnap; property: "opacity"; from: 1; to: 0; duration: 340; easing.type: Easing.OutCubic }
                        NumberAnimation { target: oldSnap; property: "scale"; from: 1; to: 0.94; duration: 420; easing.type: Easing.OutQuint }
                        onFinished: { oldSnap.shown = false; oldSv.captureSource = null; }
                    }
                }
                Item {
                    id: tearGhost
                    property real zoom: 1
                    property real wob: 0
                    readonly property bool isWin: ui.tearItem !== null && ui.tearItem.kind === "win"
                    // a window preview is picked up like the window itself: the higher it's pulled out of the Dock the
                    // closer it gets to the window's real size, held near its title bar (no wiggle — it's a window)
                    readonly property real liftRaw: isWin ? Math.max(0, Math.min(1, (ui.activeTop - ui.tearY) / 240)) : 0
                    property real lift: 1 - Math.pow(1 - liftRaw, 3)
                    Behavior on lift { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    readonly property real thumbW: 170
                    readonly property real liftW: thumbW + (ui.tearW - thumbW) * lift
                    readonly property real grabFy: 0.5 + (0.035 - 0.5) * lift
                    readonly property real offY: tearWin.height - win.height   // Dock surface → screen coordinates
                    visible: opacity > 0.01
                    width: isWin ? liftW : root.iconSize * 1.12
                    height: isWin ? liftW * ui.tearH / ui.tearW : width
                    x: ui.tearX - width / 2
                    y: offY + ui.tearY - height * (isWin ? grabFy : 0.5)
                    scale: zoom
                    rotation: isWin ? 0 : wob
                    Image {
                        visible: !tearGhost.isWin
                        anchors.fill: parent
                        source: ui.tearSrc
                        sourceSize: Qt.size(256, 256)
                        smooth: true; mipmap: true
                    }
                    RectangularShadow {
                        visible: tearGhost.isWin
                        anchors.fill: parent; radius: 10
                        offset.y: 6 + 14 * tearGhost.lift; blur: 18 + 32 * tearGhost.lift; spread: 0
                        color: Qt.rgba(0, 0, 0, 0.30 + 0.15 * tearGhost.lift)
                    }
                    // translucent windows (terminals) get Hyprland's blur behind them; the lifted copy can't, so it gets a
                    // dark backing instead — otherwise it reads as a faint see-through ghost, not the window
                    Rectangle {
                        visible: tearGhost.isWin
                        anchors.fill: parent; radius: 10
                        color: Qt.rgba(0.09, 0.08, 0.09, 0.88)
                    }
                    ScreencopyView {
                        id: gsv
                        visible: tearGhost.isWin
                        anchors.fill: parent
                        captureSource: tearGhost.isWin && tearWin.visible ? ui.tearItem.tl : null
                        live: tearGhost.isWin && tearWin.visible && tearGhost.visible
                        layer.enabled: true
                        layer.effect: MultiEffect { maskEnabled: true; maskSource: gsvMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                    }
                    Item { id: gsvMask; anchors.fill: parent; visible: false; layer.enabled: true; Rectangle { anchors.fill: parent; radius: 10; color: "black" } }
                    Rectangle {
                        visible: tearGhost.isWin
                        anchors.fill: parent; radius: 10; color: "transparent"
                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.25)
                    }
                    // light wiggle while held
                    SequentialAnimation on wob {
                        running: ui.tearing
                        loops: Animation.Infinite
                        NumberAnimation { to: 2.5; duration: 90; easing.type: Easing.InOutSine }
                        NumberAnimation { to: -2.5; duration: 180; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0; duration: 90; easing.type: Easing.InOutSine }
                    }
                }
            }

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
                // tear-off: an icon dragged up out of the Dock follows the pointer (wiggling); dropped over the desktop it
                // zooms up and fades while the app opens / comes to the front, dropped back on the Dock it flies home
                property bool tearing: false
                property var tearItem: null
                property string tearSrc: ""
                property real tearX: 0
                property real tearY: 0
                property real tearHomeX: 0
                property real tearHomeY: 0
                // window being dragged: its real size (capped) and Hyprland address
                property real tearW: 900
                property real tearH: 600
                property string tearAddr: ""
                // the real window: once its preview (pulled out of the Dock) has grown to the window's size, the real window
                // takes over under the pointer and follows it (like Super + drag) until the button is let go; a still copy
                // fades away where it used to be
                property bool following: false
                property bool oldVisible: false
                NumberAnimation { id: ghostFade; target: tearGhost; property: "opacity"; to: 0; duration: 180; easing.type: Easing.OutCubic }
                onTearXChanged: if (following) Qt.callLater(moveReal)
                onTearYChanged: {
                    if (following) Qt.callLater(moveReal);
                    else if (tearing && tearAddr && tearGhost.liftRaw >= 1) handoff();
                }
                function wsel() { return 'window = "address:' + tearAddr + '"'; }
                function realPos() {
                    return { x: Math.round(win.modelData.x + tearX - tearW / 2),
                             y: Math.round(win.modelData.y + tearGhost.offY + tearY - tearH * 0.035) };
                }
                function moveReal() {
                    if (!following || !tearAddr) return;
                    var p = realPos();
                    Hyprland.dispatch('hl.dsp.window.move({ x = ' + p.x + ', y = ' + p.y + ', "exact", ' + wsel() + ' })');
                }
                function handoff() {
                    if (following || !tearAddr) return;
                    following = true;
                    var mon = Hyprland.monitorFor(win.modelData);
                    var ws = (mon && mon.activeWorkspace) ? String(mon.activeWorkspace.name) : "";
                    var p = realPos(), sel = wsel();
                    if (ws) Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + ws + '", follow = false, ' + sel + ' })');
                    Hyprland.dispatch('hl.dsp.window.fullscreen_state({ internal = 0, client = 0, ' + sel + ' })');
                    Hyprland.dispatch('hl.dsp.window.float({ action = "enable", ' + sel + ' })');
                    Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "no_anim", value = "1", ' + sel + ' })');
                    Hyprland.dispatch('hl.dsp.window.resize({ x = ' + Math.round(tearW) + ', y = ' + Math.round(tearH) + ', "exact", ' + sel + ' })');
                    Hyprland.dispatch('hl.dsp.window.move({ x = ' + p.x + ', y = ' + p.y + ', "exact", ' + sel + ' })');
                    if (tearItem && tearItem.tl) tearItem.tl.activate();
                    if (oldVisible) { oldSnap.scale = 1; oldSnap.opacity = 1; oldSnap.shown = true; oldOut.restart(); }
                    // the real window appears exactly where its preview is, the preview fades off it
                    ghostFade.restart();
                }
                function finishFollow() {
                    following = false;
                    tearing = false;
                    if (tearAddr) Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "no_anim", value = "0", ' + wsel() + ' })');
                    tearAddr = "";
                    if (!ghostFade.running) tearItem = null;
                    else ghostFade.finished.connect(function () { if (!ui.tearing) ui.tearItem = null; });
                }
                function hyprOf(tl) {
                    var v = Hyprland.toplevels.values;
                    for (var i = 0; i < v.length; i++) if (v[i].wayland === tl) return v[i];
                    return null;
                }
                function beginTear(item, src, homeX, homeY) {
                    if (dragging) { dragTarget = dragIndex; endDrag(); }
                    menuItem = null;
                    tearItem = item; tearSrc = src; tearHomeX = homeX; tearHomeY = homeY;
                    tearGhost.opacity = 1; tearGhost.zoom = 1;
                    following = false; ghostFade.stop();
                    tearAddr = "";
                    if (item.kind === "win") {
                        var h = hyprOf(item.tl), o = h ? h.lastIpcObject : null;
                        tearAddr = h ? ("0x" + h.address.replace(/^0x/, "")) : "";
                        var sw = win.modelData.width, sh = win.modelData.height;
                        var w = (o && o.size) ? o.size[0] : (gsv.implicitWidth || 900);
                        var hh = (o && o.size) ? o.size[1] : (gsv.implicitHeight || 600);
                        // a fullscreen / huge window comes off as a comfortable floating size, like macOS restoring it
                        var k = Math.min(1, (sw * 0.78) / w, (sh * 0.78) / hh);
                        tearW = Math.round(w * k); tearH = Math.round(hh * k);
                        // where it is now: if that's on screen here, a still copy will stand in for it at the hand-off
                        var mon0 = Hyprland.monitorFor(win.modelData);
                        oldSnap.shown = false; oldOut.stop();
                        oldVisible = !!(o && o.at && o.workspace && mon0 && mon0.activeWorkspace && o.workspace.id === mon0.activeWorkspace.id);
                        if (oldVisible) {
                            oldSnap.x = o.at[0] - win.modelData.x; oldSnap.y = o.at[1] - win.modelData.y;
                            oldSnap.width = o.size[0]; oldSnap.height = o.size[1];
                            oldSv.captureSource = item.tl;          // one still frame (live: false)
                        }
                    }
                    tearing = true;
                }
                function endTear() {
                    if (!tearing) return;
                    // a window: let go wherever the pointer is — it simply stays there
                    if (tearAddr && (following || tearY < activeTop - 30)) {
                        if (!following) handoff();
                        finishFollow();
                        justDragged = true;
                        Qt.callLater(function () { ui.justDragged = false; });
                        return;
                    }
                    tearing = false;
                    justDragged = true;
                    Qt.callLater(function () { ui.justDragged = false; });
                    if (tearY < activeTop - 30) {
                        tearLaunch.item = tearItem;
                        tearLaunch.restart();               // enlarge + fade, then open / focus
                    } else {
                        // back on the Dock: the preview flies home and the window fades back in where it was
                        tearHome.restart();                 // back to its place
                    }
                }

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

                SequentialAnimation {
                    id: tearLaunch
                    property var item: null
                    ParallelAnimation {
                        NumberAnimation { target: tearGhost; property: "zoom"; to: tearGhost.isWin ? 2.0 : 2.6; duration: 460; easing.type: Easing.OutQuint }
                        NumberAnimation { target: tearGhost; property: "opacity"; to: 0; duration: 460; easing.type: Easing.OutCubic }
                        NumberAnimation { target: tearGhost; property: "wob"; to: 0; duration: 200 }
                    }
                    ScriptAction { script: { if (tearLaunch.item) root.activate(tearLaunch.item, false); ui.tearItem = null; } }
                }
                ParallelAnimation {
                    id: tearHome
                    NumberAnimation { target: ui; property: "tearX"; to: ui.tearHomeX; duration: 420; easing.type: Easing.OutQuint }
                    NumberAnimation { target: ui; property: "tearY"; to: ui.tearHomeY; duration: 420; easing.type: Easing.OutQuint }
                    NumberAnimation { target: tearGhost; property: "wob"; to: 0; duration: 200 }
                    onFinished: { ui.tearItem = null; ui.tearAddr = ""; }
                }

                readonly property bool tucked: wantsHide && !revealed && !menuOpen && !dragging && !tearing
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
                        // the wallpaper that is SHOWN only switches once the new one has finished loading, so a wallpaper change never
                        // flashes the placeholder gradient (or a black hole) through the glass
                        Image {
                            id: wpShown
                            anchors.fill: parent
                            visible: status === Image.Ready
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: bd.width
                            smooth: true
                        }
                        Image {
                            id: wpNext
                            visible: false
                            width: 1; height: 1
                            onStatusChanged: {
                                console.log("[macdock-glass] wallpaper image status:", status, "(1 = ready, 2 = loading, 3 = error)", source);
                                if (status === Image.Ready) wpShown.source = source;
                            }
                            source: root.fileUrl(root.wallpaperFor(win.modelData.name))
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: bd.width
                        }
                        // animated wallpaper: plays behind the Dock glass only while Real-time glass is on
                        LiveWall {
                            anchors.fill: parent
                            video: root.bar ? root.bar.glassVideo : ""
                            live: root.glassLive
                            paused: !!root.bar && (root.bar.gaming || root.bar.screenCovered[win.modelData.name] === true)
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
                                required property bool gone      // window closed / left this workspace: hidden at once, its capture is released shortly after
                                x: wx; y: wy; width: ww; height: wh; z: wz
                                visible: !gone                    // a window of the workspace we just left must not linger behind the Dock
                                // the capture itself is kept 300 ms after the window is gone, so a frame that is in flight can finish
                                // (destroying a capture mid-frame is what made the compositor drop the Wayland connection)
                                property bool released: false
                                onGoneChanged: { if (gone) relTimer.restart(); else { relTimer.stop(); released = false; } }
                                Timer { id: relTimer; interval: 300; onTriggered: gw.released = true }
                                // the closing window's own capture stops the moment Hyprland announces the close
                                readonly property bool closing: !!root.hub && root.hub.closingWins[String(addr).replace(/^0x/, "")] === true
                                readonly property var tl: { if (!root.hub || released || closing) return null; var t = root.hub.tlTick; return root.hub.tlFor(addr); }
                                // does this window reach the glass (Dock + the backdrop margin the refraction / blur read from)?
                                readonly property real dockTop: dock.y + bd.height - ui.height
                                readonly property bool overlap: x < dock.x + dock.width + 100 && x + width > dock.x - 100
                                    && y < dockTop + dock.height + 100 && y + height > dockTop - 100
                                // only keep capturing windows that actually reach the Dock (+ refraction margin)
                                // real-time: EVERY visible window stays captured (also while the Dock is tucked and for windows far from the Dock), so a window
                                // dragged over the Dock or a revealed Dock never starts from the bare wallpaper
                                readonly property bool nearNow: root.glassRT || (!ui.tucked
                                    && x < dock.x + dock.width + 48 && x + width > dock.x - 48
                                    && y < dockTop + dock.height + 48
                                    && y + height > dockTop - 48)
                                // a capture is only torn down 2.5 s after the window left the dock area: creating / destroying
                                // live window captures every time a window brushes past the dock is what the compositor can choke on
                                property bool near: false
                                onNearNowChanged: { if (nearNow) { nearHold.stop(); near = true; } else nearHold.restart(); }
                                Component.onCompleted: near = nearNow
                                Timer { id: nearHold; interval: 2500; onTriggered: gw.near = gw.nearNow }
                                Loader {
                                    anchors.fill: parent
                                    active: gw.near && !gw.released
                                    sourceComponent: ScreencopyView {
                                        id: sc
                                        captureSource: gw.tl
                                        // Real-time glass ON: a window that reaches the Dock STREAMS (live: every frame the compositor renders), windows
                                        // elsewhere refresh at 5 Hz so they are fresh the moment they slide under the Dock. Opening / closing windows no
                                        // longer freeze the glass: only the closing window's own capture stops.
                                        // Real-time glass OFF: the old behaviour (15 fps polling, paused while windows open / close).
                                        readonly property bool canRun: root.glassRT
                                            ? !(root.hub && root.hub.captureQuiet) && !(root.bar && root.bar.gaming) && !gw.gone && !gw.closing
                                            : (!root.glassHold && !ui.tucked)
                                        live: root.glassRT && canRun && gw.overlap && !ui.tucked
                                        Timer {
                                            interval: root.glassRT ? (gw.overlap ? 33 : 200) : 66
                                            repeat: true
                                            running: sc.canRun && !sc.live && sc.captureSource !== null
                                            onTriggered: if (typeof sc.captureFrame === "function") sc.captureFrame()
                                        }
                                        onCaptureSourceChanged: { if (captureSource !== null && sc.canRun) firstShot.restart(); }
                                        Timer {
                                            id: firstShot
                                            interval: 60
                                            onTriggered: { if (sc.captureSource !== null && !sc.live && sc.canRun && typeof sc.captureFrame === "function") sc.captureFrame(); }
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
                        active: root.liquidActive          // exactly as before: runs on the shared shader until dockglass.frag is built, then swaps
                        sourceComponent: Item {
                            id: dg
                            // wallpaper's dominant colour: the edge light leans toward it (slides to the new colour when the wallpaper changes)
                            property color edgeCol: root.bar ? root.bar.menuBorderColor : "#8A9AB5"
                            Behavior on edgeCol { ColorAnimation { duration: 450; easing.type: Easing.OutCubic } }
                            // blurring at half resolution is visually identical for radii >= 8 px and costs a quarter of the GPU work
                            // the Dock gets extra blur on top of the shared Blur slider (dockBlurBoost px), so it is frosted even at the default setting
                            readonly property real eb: root.glassBlur + root.dockBlurBoost
                            readonly property real ds: eb >= 8 ? 0.5 : 1.0
                            readonly property real bn: eb * 1.5 * ds / 64.0
                            readonly property real margin: 72      // extra backdrop captured around the Dock (refraction + blur reach)
                            readonly property real padPx: root.dockGlassNew ? 30 : 10   // shader item padding (shadow room); dockglass.frag needs >= 30, the shared shader keeps its original 10
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
                                fragmentShader: root.dockGlassUrl
                                onStatusChanged: {
                                    console.log("[macdock-glass] shader status:", status, "(0 = compiled, 1 = uncompiled, 2 = error)", log);
                                    if (status === ShaderEffect.Error) {
                                        // the Dock's own shader failed to load: drop back to the shared one; only if THAT fails too, give up on Liquid Glass
                                        if (root.dockGlassNew) root.dockGlassState = "failed";
                                        else root.glassState = "failed";
                                    }
                                }
                                // dockglass.frag only (ignored by liquidglass.frag): rgb = wallpaper colour, a = how strongly the edge light follows it
                                property vector4d edgeTint: Qt.vector4d(dg.edgeCol.r, dg.edgeCol.g, dg.edgeCol.b, root.dockGlassNew ? 0.5 : 0)

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
                                property real rim: root.glassRim * 0.20
                                property real grain: root.glassGrain * 0.3     // quieter noise on the Dock glass
                                property real blurPx: 1.5            // tiny residual smoothing; the real blur is the MultiEffect pre-pass
                                property real tintMix: root.glassOpacity * 0.55
                                property real saturation: 1.25
                                property real dark: root.dockDark ? 1 : 0
                                property real debug: root.glassDebug ? 1 : 0
                                // Keep the Dock glass clean: no drop shadow.
                                property real shadowAmt: 0
                                property real rimTint: 0
                                property real ringW: 0
                            }
                        }
                    }

                    Rectangle {
                        visible: !root.liquidActive
                        anchors.fill: parent
                        radius: root.cornerRadius
                        color: root.dockDark ? Qt.rgba(0.10, 0.10, 0.11, root.glassOpacity)
                                             : Qt.rgba(1, 1, 1, root.glassOpacity * 0.55)
                        border.width: 0      // dark outer border removed

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 0
                            radius: parent.radius - 0.35
                            color: "transparent"
                            border.width: 0.25
                            border.color: root.dockDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.12)
                        }
                    }

                    // same extra edge detail as the top-bar menus: faint dominant-colour edge (no dark hairline)
                    MenuBorder {
                        anchors.fill: parent      // no z: stays below the icon row, so magnified icons are drawn over the border
                        cornerR: root.cornerRadius
                        dark: root.dockDark
                        tint: root.bar ? root.bar.menuBorderColor : "#8A9AB5"
                        outline: false      // no dark hairline / shade around the dock
                    }

                    // Natural edge: with Liquid Glass (dockglass.frag) the edge light is drawn by the shader, so this Canvas is not even created.
                    // It stays for Normal Blur and as the fallback when the Dock's own shader is unavailable (a faint line in the wallpaper colour).
                    Loader {
                        anchors.fill: parent
                        active: !(root.liquidActive && root.dockGlassNew)
                        sourceComponent: CornerBorder {
                            anchors.fill: parent
                            cornerR: root.cornerRadius
                            dark: root.dockDark
                            tint: root.bar ? root.bar.menuBorderColor : "#8A9AB5"
                            amount: 0.12
                            lineW: 0.35
                            fade: false
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
                            model: dockModel

                            delegate: Item {
                                id: cell
                                required property string key
                                required property int index
                                readonly property var modelData: root.itemMap[key] || ({ kind: "sep", key: key, nA: 0, nS: 0 })
                                readonly property bool isSep: modelData.kind === "sep"
                                readonly property bool canDrag: !isSep && modelData.pinned === true && !modelData.special
                                readonly property bool torn: ui.tearing && ui.tearItem && !isSep && ui.tearItem.key === modelData.key
                                opacity: (torn ? 0.3 : (isDragged ? 0.92 : 1)) * (leavingCell ? appear : 1)
                                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                readonly property bool isDragged: ui.dragging && modelData.key === ui.dragKey

                                // app cells always show their plain icon; only window cells show a live preview
                                // (with the app's icon as a badge), grouped next to the Trash
                                readonly property var thumbWin: (!isSep && modelData.kind === "win") ? modelData.tl : null
                                // the capture only restarts when the window itself changes — refreshed Dock data hands the cell
                                // the same window again, and re-binding it used to blank the live preview for ~2 s
                                property var heldTl: null
                                readonly property string winAddr: { if (!thumbWin) return ""; var h = ui.hyprOf(thumbWin); return h ? String(h.address).replace(/^0x/, "") : ""; }
                                readonly property bool closingWin: winAddr !== "" && root.hub && root.hub.closingWins[winAddr] === true
                                onThumbWinChanged: if (thumbWin !== heldTl) heldTl = thumbWin
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

                                readonly property bool leavingCell: modelData.leaving === true
                                property real appear: modelData.fresh ? 0 : 1
                                Behavior on appear { NumberAnimation { duration: cell.leavingCell ? root.leaveMs : 320; easing.type: cell.leavingCell ? Easing.InOutCubic : Easing.OutCubic } }
                                Component.onCompleted: { heldTl = thumbWin; Qt.callLater(function () { cell.appear = cell.leavingCell ? 0 : 1; cell.bounceStep(); }); }
                                onLeavingCellChanged: appear = leavingCell ? 0 : 1
                                enabled: !leavingCell

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

                                width: isSep ? root.sepWidth * appear : root.iconSize * s * appear
                                height: root.iconSize

                                Rectangle {
                                    visible: cell.isSep
                                    width: 1
                                    height: root.iconSize * 0.85
                                    anchors.centerIn: parent
                                    color: root.dockDark ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(0, 0, 0, 0.22)
                                }

                                Image {
                                    id: img
                                    visible: false
                                    property real lift: 0
                                    width: root.iconSize * 0.99 * cell.s * cell.appear     // icon art drawn at 99%: the dock and the cells keep their size
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
                                    // icon tint: desaturate, then colourise (no shader build needed)
                                    saturation: root.iconTint ? -0.75 * root.iconTintStrength : 0.0
                                    colorization: root.iconTint ? 1.0 * root.iconTintStrength : 0.0
                                    brightness: (ma.pressed ? -0.3 : 0.0) + (root.iconTint ? 0.14 * root.iconTintStrength : 0.0)
                                    contrast: root.iconTint ? 0.04 * root.iconTintStrength : 0.0
                                    colorizationColor: root.iconTintColor
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
                                        captureSource: (root.hub && !root.hub.windowCapture) ? null : cell.heldTl
                                        // live only while the pointer is on the Dock (where you look at them); otherwise one fresh
                                        // frame every 2 s — live previews of every window were ~8% CPU at idle
                                        live: !ui.tucked && !root.previewHold && !cell.closingWin && hh.hovered
                                        Timer {
                                            interval: 2000; repeat: true; triggeredOnStart: true
                                            running: !sv.live && !ui.tucked && !root.previewHold && !cell.closingWin && sv.captureSource !== null
                                            onTriggered: if (typeof sv.captureFrame === "function") sv.captureFrame()
                                        }
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
                                        border.color: root.dockDark ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(0, 0, 0, 0.28)
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
                                    color: root.dockDark ? Qt.rgba(1, 1, 1, 0.85) : Qt.rgba(0, 0, 0, 0.6)
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: cell.height + 3
                                }

                                // ── launch bounce ──
                                // Bounces while the app launches. When the app opens, the bounce in progress finishes its landing, then a
                                // couple of smaller bounces settle it back onto the Dock. Nothing plays while the Dock is tucked away.
                                readonly property bool wantBounce: !cell.isSep && root.bounceOnLaunch && root.launching[cell.modelData.key] !== undefined
                                property bool bounceShown: false          // a bounce was actually visible, so it deserves a settle
                                function bounceStep() {
                                    if (ui.tucked) return;
                                    if (cell.wantBounce) { cell.bounceShown = true; if (!bounceAnim.running && !settleAnim.running) bounceAnim.start(); }
                                    else if (cell.bounceShown && !bounceAnim.running && !settleAnim.running) { cell.bounceShown = false; settleAnim.start(); }
                                }
                                onWantBounceChanged: bounceStep()
                                Connections {
                                    target: ui
                                    function onTuckedChanged() {
                                        if (ui.tucked) {                       // dock slid away: drop the bounce, it must not poke out
                                            bounceAnim.stop(); settleAnim.stop(); img.lift = 0; cell.bounceShown = false;
                                        } else cell.bounceStep();
                                    }
                                }
                                SequentialAnimation {
                                    id: bounceAnim
                                    NumberAnimation { target: img; property: "lift"; to: root.iconSize * 0.42
                                                      duration: 280; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: img; property: "lift"; to: 0
                                                      duration: 280; easing.type: Easing.InCubic }
                                    onFinished: cell.bounceStep()              // goes again while still launching, otherwise settles
                                }
                                SequentialAnimation {
                                    id: settleAnim
                                    NumberAnimation { target: img; property: "lift"; to: root.iconSize * 0.16
                                                      duration: 170; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: img; property: "lift"; to: 0
                                                      duration: 170; easing.type: Easing.InQuad }
                                    NumberAnimation { target: img; property: "lift"; to: root.iconSize * 0.06
                                                      duration: 120; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: img; property: "lift"; to: 0
                                                      duration: 120; easing.type: Easing.InQuad }
                                    onFinished: cell.bounceStep()              // relaunched while settling: bounce again
                                }

                                Rectangle {
                                    id: tip
                                    visible: opacity > 0
                                    opacity: (root.showLabels && !cell.isSep && ma.containsMouse && !ma.pressed && !ui.menuOpen && !ui.dragging) ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                    z: 10
                                    width: label.implicitWidth + 22
                                    height: label.implicitHeight + 10
                                    radius: 9
                                    color: Qt.rgba(0.12, 0.12, 0.13, 0.72)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.14)
                                    // dark hairline just outside, so the label keeps its edge over a bright window behind it
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: -1
                                        z: -1
                                        radius: parent.radius + 1
                                        color: "transparent"
                                        border.width: 1
                                        border.color: Qt.rgba(0, 0, 0, 0.22)
                                    }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: cell.height - img.height - img.lift - height - 10

                                    Text {
                                        id: label
                                        anchors.centerIn: parent
                                        text: cell.isSep ? "" : ((cell.modelData.kind === "win" && cell.modelData.tl && cell.modelData.tl.title) ? cell.modelData.tl.title : cell.modelData.name)
                                        color: "white"
                                        font.pixelSize: 13
                                        font.family: root.fontForWeight(font.weight, root.fontFamily)
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

                                    property real pressY: 0
                                    onPressed: mouse => {
                                        if (mouse.button === Qt.LeftButton) {
                                            var pp = ma.mapToItem(ui, mouse.x, mouse.y);
                                            pressX = pp.x; pressY = pp.y;
                                        }
                                    }
                                    onPositionChanged: mouse => {
                                        if (!(pressedButtons & Qt.LeftButton) || cell.isSep) return;
                                        var ap = ma.mapToItem(ui, mouse.x, mouse.y);
                                        // pulled up out of the Dock → tear the icon off (any app icon, pinned or running)
                                        if (ui.tearing) { ui.tearX = ap.x; ui.tearY = ap.y; return; }
                                        if (pressY - ap.y > 56 && (cell.modelData.kind === "app" || cell.modelData.kind === "win") && !cell.modelData.special) {
                                            var home = img.mapToItem(ui, img.width / 2, img.height / 2);
                                            ui.tearX = ap.x; ui.tearY = ap.y;
                                            ui.beginTear(cell.modelData, root.cellIconSrc(cell.modelData), home.x, home.y);
                                            return;
                                        }
                                        if (!cell.canDrag) return;
                                        var ax = ap.x;
                                        if (!ui.dragging) {
                                            if (Math.abs(ax - pressX) < 8) return;
                                            ui.beginDrag(cell.index, cell.modelData.key, pressX, cell.width + root.spacing);
                                        }
                                        if (cell.isDragged) ui.dragUpdate(ax);
                                    }
                                    onReleased: mouse => {
                                        if (ui.tearing) { ui.endTear(); return; }
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
                                    text: mi.isSep ? "" : (mi.armedNow ? I18n.tr("Click again to confirm") : I18n.tr(mi.modelData.label))
                                    color: mi.off ? Qt.rgba(1, 1, 1, 0.4) : "white"
                                    font.pixelSize: 13
                                    font.family: root.fontForWeight(font.weight, root.fontFamily)
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
