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

Scope {
    id: root

    // shared helpers from shell.qml (window geometry poller, wallpaper lookup)
    property var hub: null
    // close through the shell, so its window captures are released first (see shell.qml → hideWindow)
    function hideWin(w) { if (root.hub && root.hub.hideWindow) root.hub.hideWindow(w); else w.visible = false; }
    property bool dockEnabled: true      // false = no Dock at all (settings window stays available)
    property var bar: hub ? hub.bar : null
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
    // Frame budget for the live captures behind the Dock's glass: the main display's own refresh rate, so the
    // refraction moves as smoothly as the screen it is on (it used to be pinned at 15 fps, which read as lag).
    readonly property int mainHz: {
        var ms = hub ? (hub.monData || []) : [], want = monitorPrimary || monitor, best = 0, any = 0;
        for (var i = 0; i < ms.length; i++) {
            var hz = Math.round(Number(ms[i].refreshRate) || 0);
            if (hz > any) any = hz;
            if (want && ms[i].name === want) best = hz;
        }
        var hz2 = best || any || 60;
        return Math.max(30, Math.min(240, hz2));
    }
    readonly property int frameMs: Math.max(4, Math.round(1000 / mainHz))
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

    // ───────────── CONFIG ───────────── Lachowski
    property string monitor: ""          // "" = every monitor, or e.g. "DP-1"
    property int iconSizePref: 52        // the size you picked in Settings
    property real magnification: 1.7     // peak icon scale
    property int spacing: 6
    property int hPad: 10
    property int topPad: 8
    property int bottomPad: 9            // room under icons (running dots live here)
    property int cornerRadius: 18
    property int margin: 6
    property bool darkMode: true
    property string dockStyle: "liquid" // "liquid" = Apple Liquid Glass, "blur" = Normal Blur
    // new windows open floating (macOS-like) instead of tiling; written to a Lua file the session config reads
    property bool windowsFloat: true
    onWindowsFloatChanged: if (settingsReady) applyWindowsFloat()
    function applyWindowsFloat() {
        var rule = windowsFloat ? "hl.window_rule({ match = { class = \".*\" }, float = true })\n" : "";
        Quickshell.execDetached(["sh", "-c",
            "mkdir -p \"$HOME/.config/macshell\"; printf '%s' \"$1\" > \"$HOME/.config/macshell/windows.lua\"; "
            + "if [ -n \"$1\" ]; then hyprctl eval \"$1\" >/dev/null 2>&1; else hyprctl reload >/dev/null 2>&1; fi", "sh", rule]);
    }
    // Liquid Glass tuning (settings.json): rim = edge highlight, grain = noise, liquid = refraction depth
    property real glassRim: 0.45
    property real glassGrain: 0.03
    property real glassLiquid: 1.0
    readonly property bool glassRT: bar ? (bar.glassRealtime && !bar.underLoad) : true   // real-time glass (Menu Bar settings)
    readonly property bool underLoad: bar ? bar.underLoad : false
    property real glassBlur: 5            // Liquid Glass backdrop blur radius, px (settings slider)
    property bool glassDebug: false       // settings.json only: draw the raw Liquid Glass backdrop texture
    property string wallpaperPath: ""    // optional override for the wallpaper the Liquid Glass refracts
    // Opaque material or Game Mode: the Dock and Settings are solid too
    readonly property bool solidLook: bar ? bar.solidAll : false
    property real glassOpacity: 0.42     // 0 = fully clear; below the layerrule's ignore_alpha (0.2) the blur turns off
    // "smart"  = hide while a non-floating window is open on that monitor's workspace
    // "always" = always auto-hide, "never" = always visible and reserves space
    property string hideMode: "smart"
    property bool showTrash: true
    // the Clock window draws Liquid Glass when the shader is built and Game Mode is off
    readonly property string boldFontFamily: hub && hub.boldFontFamily ? hub.boldFontFamily : "Open Runde Semibold"
    function fontForWeight(weight, regularFamily) { return Number(weight) >= Font.DemiBold ? boldFontFamily : regularFamily; }
    readonly property bool settingsGlass: glassState === "ready" && !(bar && bar.gaming)
    property string fontFamily: "Open Runde"  // bundled in assets/fonts (shell.qml loads it); falls back to the system font if missing
    onFontFamilyChanged: {
        if (fontFamily.indexOf("Inter") === 0) fontFamily = "Open Runde";
        if (bar && bar.fontFamily !== fontFamily) bar.fontFamily = fontFamily;
    }
    property bool magnificationEnabled: true
    property bool showLabels: true       // hover tooltips
    property bool showIndicators: true   // dots under running apps
    property bool bounceOnLaunch: true
    property bool showThumbs: true       // open windows get a live preview cell next to the Trash
    property bool windowCapture: true    // live window capture for those previews (off: the cells show the app icon, nothing is captured). Liquid Glass is not affected
    property int hideDelay: 450          // ms before the dock hides after the pointer leaves
    readonly property var accentChoices: [
        { name: I18n.tr("Blue"),     c: "#0a84ff" }, { name: I18n.tr("Purple"), c: "#bf5af2" },
        { name: I18n.tr("Pink"),     c: "#ff375f" }, { name: I18n.tr("Red"),    c: "#ff453a" },
        { name: I18n.tr("Orange"),   c: "#ff9f0a" }, { name: I18n.tr("Yellow"), c: "#ffd60a" },
        { name: I18n.tr("Green"),    c: "#30d158" }, { name: I18n.tr("Graphite"), c: "#8e8e93" }
    ]
    property color accent: "#0A84FF"     // menu highlight (macOS blue)
    readonly property var defaultPinned: [
        "org.gnome.Nautilus", "org.kde.dolphin", "thunar",
        "firefox", "zen", "chromium", "google-chrome",
        "kitty", "com.mitchellh.ghostty", "Alacritty", "foot",
        "code", "discord", "spotify", "steam", "obsidian"
    ]   // used until you change pins from the dock; unknown ids are skipped
    property var pinned: defaultPinned
    // App icons: follow the appearance, or stay on the light / dark set. Writes the GTK and Qt icon theme.
    property string iconMode: "auto"
    function iconThemeName(mode) {
        var base = "MacTahoe";
        var m = mode === "auto" ? (darkMode ? "dark" : "light") : mode;
        return base + "-" + m;
    }
    function setIconMode(mode) {
        iconMode = mode;
        applyIconTheme();
        saveSettings();
    }
    function applyIconTheme() {
        var name = iconThemeName(iconMode);
        Quickshell.execDetached(["sh", "-c",
            "t=\"$1\"; "
            // only switch to a theme that is actually installed
            + "[ -d \"$HOME/.local/share/icons/$t\" ] || [ -d \"/usr/share/icons/$t\" ] || exit 0; "
            + "gsettings set org.gnome.desktop.interface icon-theme \"$t\" 2>/dev/null; "
            + "mkdir -p \"$HOME/.config/qt6ct\"; f=\"$HOME/.config/qt6ct/qt6ct.conf\"; "
            + "if [ -f \"$f\" ] && grep -q '^icon_theme=' \"$f\"; then sed -i \"s|^icon_theme=.*|icon_theme=$t|\" \"$f\"; "
            + "elif [ -f \"$f\" ]; then printf 'icon_theme=%s\\n' \"$t\" >> \"$f\"; else printf '[Appearance]\\nicon_theme=%s\\n' \"$t\" > \"$f\"; fi; "
            + "k=\"$HOME/.config/kdeglobals\"; [ -f \"$k\" ] && grep -q '^Theme=' \"$k\" && sed -i \"s|^Theme=.*|Theme=$t|\" \"$k\"; "
            + "exit 0", "sh", name]);
    }
    onDarkModeChanged: {
        if (settingsReady && iconMode === "auto") applyIconTheme();
        if (bar && bar.darkMode !== darkMode) bar.darkMode = darkMode;
    }
    onAccentChanged: if (bar && String(bar.accent) !== String(accent)) bar.accent = accent
    // How minimising looks: "genie" (the window pours into the Dock, the macOS default), "fade" (0.35 s), "instant".
    property string minimizeEffect: "genie"
    property real minimizeSecs: 0.42
    // Settings → Mouse → Pointer: Apple's macOS cursors (black "macOS" or "macOS-White") and their size
    property string cursorTheme: "macOS"
    property int cursorSize: 24
    function applyCursor() {
        Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr-macshell/scripts/macshell-cursor.sh", cursorTheme, String(cursorSize)]);
    }
    onCursorThemeChanged: if (settingsReady) applyCursor()
    onCursorSizeChanged: if (settingsReady) applyCursor()          // how long Magic Lamp takes (Settings → Desktop & Dock → Speed)
    // Settings → Icons: "default" or "tinted" (every app icon in one colour, like macOS Tahoe); only with Frosted
    // or Liquid Glass. iconTint "" = the accent colour
    property string iconStyle: "default"
    property string iconTint: ""
    // Clear and Tinted are glass looks: every glass material has them (Liquid Glass, Frosted, Blur, Custom); only
    // Opaque (and Game Mode, which makes everything solid) falls back to Default
    readonly property string glassKind: !bar ? "liquid" : (bar.material === "custom" ? (bar.barStyle === "liquid" ? "liquid" : "blur") : bar.material)
    readonly property bool tintAllowed: bar ? (bar.material !== "opaque" && !bar.solidAll) : true
    // Settings → Icons → Icon style, like macOS Tahoe: Default, Dark, Clear (glass) or Tinted (one colour)
    readonly property string iconLookWanted: (iconStyle === "clear" || iconStyle === "tinted") && !tintAllowed ? "default" : iconStyle
    // what the icons show right now: changes half-way through the switch animation (iconSwap), never abruptly
    property string iconLook: "default"
    property real iconSwap: 0                 // 0 resting … 1 the icons are faded out mid-switch
    onIconLookWantedChanged: {
        if (!settingsReady) { iconLook = iconLookWanted; return; }
        if (iconLook !== iconLookWanted) iconSwitch.restart();
    }
    SequentialAnimation {
        id: iconSwitch
        NumberAnimation { target: root; property: "iconSwap"; to: 1; duration: 160; easing.type: Easing.InOutQuad }
        ScriptAction { script: root.iconLook = root.iconLookWanted }
        NumberAnimation { target: root; property: "iconSwap"; to: 0; duration: 260; easing.type: Easing.InOutQuad }
    }
    readonly property bool iconsTinted: iconLook === "clear" || iconLook === "tinted"
    readonly property color iconTintColor: iconTint !== "" ? iconTint : accent
    // Clear follows the material: Liquid Glass is the clearest (see-through, bright), Frosted a milky white,
    // Blur a soft white that stays most solid
    readonly property real iconColorize: iconLook === "tinted" ? 1.0 : (iconLook === "clear" ? (glassKind === "liquid" ? 0.97 : glassKind === "frosted" ? 0.92 : 0.85) : 0)
    readonly property color iconColorizeColor: iconLook === "clear" ? "#FFFFFF" : iconTintColor
    readonly property real iconBright: iconLook === "clear" ? (glassKind === "liquid" ? 0.18 : glassKind === "frosted" ? 0.08 : 0.02) : (iconLook === "tinted" ? 0.12 : 0)
    // Tinted: the colour has to read clearly, not as a faint wash over grey
    readonly property real iconSat: iconLook === "tinted" ? 0.6 : 0
    readonly property real iconAlpha: iconLook === "clear" ? (glassKind === "liquid" ? 0.66 : glassKind === "frosted" ? 0.8 : 0.9) : 1
    property var uiByScreen: ({})          // each screen's Dock, so the minimise effect knows where to aim
    // Where a window should pour into: its own preview cell in the Dock if it has one, otherwise its app's icon.
    // Returned in global (layout) coordinates, or null when the Dock isn't on that screen.
    function minimizeTarget(waylandTl, screenName) {
        var ui = uiByScreen[screenName];
        var scr = null, ss = Quickshell.screens;
        for (var s = 0; s < ss.length; s++) if (ss[s].name === screenName) { scr = ss[s]; break; }
        if (!ui || !scr) return null;
        var idx = -1, i;
        if (waylandTl) {
            var wk = "win:" + winIdFor(waylandTl);
            for (i = 0; i < dockModel.count; i++) if (dockModel.get(i).key === wk) { idx = i; break; }
            if (idx < 0) {
                var ak = keyOf(appOf(waylandTl));
                for (i = 0; i < dockModel.count; i++) if (dockModel.get(i).key === ak) { idx = i; break; }
            }
        }
        var cx = idx >= 0 ? ui.naturalCenter(idx) : ui.width / 2;
        var size = iconSize;
        return { x: scr.x + cx - size / 2, y: scr.y + scr.height - margin - bottomPad - size, width: size, height: size };
    }
    // Internet Sharing: kept here (and saved) so the name, password and band survive closing Settings
    property string hotspotSsid: ""
    property string hotspotPass: ""
    property string hotspotBand: "bg"       // bg = 2.4 GHz, a = 5 GHz
    property string hotspotPrevWifi: ""     // the network to re-join when sharing is switched off
    property bool desktopIcons: true    // files, folders and apps shown on the desktop
    property var pinnedFolders: []      // folder paths pinned next to the Trash
    function pinFolder(p) {
        if (pinnedFolders.indexOf(p) >= 0) return;
        pinnedFolders = pinnedFolders.concat([p]);
        saveSettings(); rebuild();
        if (bar) bar.playSound("pop", 0.6);
    }
    // qs -c MacShell ipc call dock pinfolder <path> | stack <path>
    signal stackRequest(string path)
    IpcHandler {
        target: "dock"
        function pinfolder(p: string): void { root.pinFolder(p); }
        function unpinfolder(p: string): void { root.unpinFolder(p); }
        function stack(p: string): void { root.stackRequest(p); }
        // Settings → Icons → Icon style: default | dark | clear | tinted
        function iconstyle(v: string): void { if (["default", "dark", "clear", "tinted"].indexOf(v) >= 0) root.iconStyle = v; }
    }
    property string stackPath: ""
    property var stackFiles: []
    function loadStack(path) {
        stackPath = path;
        stackFiles = [];
        stackProc.running = false;
        stackProc.command = ["sh", "-c",
            "cd \"$1\" 2>/dev/null || exit 0; find . -mindepth 1 -maxdepth 1 ! -name '.*' -printf '%y\\t%f\\n' 2>/dev/null "
            + "| LC_ALL=C sort -t\"$(printf '\\t')\" -k1,1 -k2,2f | head -6", "sh", path];
        stackProc.running = true;
    }
    function unpinFolder(p) { pinnedFolders = pinnedFolders.filter(function (x) { return x !== p; }); saveSettings(); rebuild(); }
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
    component SSwitch: LiquidSwitch {
        required property var t
        accent: t.accent; offColor: t.switchOff; dark: root.darkMode
        material: root.bar ? root.bar.material : "liquid"
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
        width: 230
        height: leftLabel !== "" || rightLabel !== "" ? 40 : 24
        opacity: enabled ? 1 : 0.4
        LiquidSlider {
            width: parent.width
            value: s.to > s.from ? (s.value - s.from) / (s.to - s.from) : 0
            stepSize: s.stepSize > 0 && s.to > s.from ? s.stepSize / (s.to - s.from) : 0
            accent: s.t.accent; trackColor: s.t.track; dark: root.darkMode
            material: root.bar ? root.bar.material : "liquid"
            onMoved: v => s.moved(Math.round((s.from + v * (s.to - s.from)) * 1000) / 1000)
        }
        Text {
            visible: s.leftLabel !== ""
            y: 26
            text: s.leftLabel
            color: s.t.text2
            font.family: s.t.fam
            font.pixelSize: 11
        }
        Text {
            visible: s.rightLabel !== ""
            y: 26
            x: s.width - implicitWidth
            text: s.rightLabel
            color: s.t.text2
            font.family: s.t.fam
            font.pixelSize: 11
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
                    font.pixelSize: 10
                    font.bold: true
                }
            }
        }
    }

    // ─────────────────────────── THE WINDOW ───────────────────────────
    Window {
        id: prefsWindow
        // Super + Q, Super + W, the Dock's Quit: same careful close as the traffic light
        onClosing: close => { close.accepted = false; root.hideWin(prefsWindow); }
        title: "macshell Settings"
        width: 820
        height: 600
        minimumWidth: 700
        minimumHeight: 500
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
            readonly property real x: ok ? g.x : 0
            readonly property real y: ok ? g.y : 0
            readonly property real mw: ok ? g.mw : 1
            readonly property real mh: ok ? g.mh : 1
            readonly property string mon: ok ? g.mon : ""
        }

        // ── navigation state ──
        property int cur: 0
        property var backStack: []
        property var fwdStack: []
        property string query: ""

        // grouped like macOS System Settings (sec = sidebar section; a gap is drawn between sections)
        readonly property var panes: [
            { id: "wifi",       sec: 1, name: I18n.tr("Wi-Fi"),           wg: "wifi",       c1: "#3D9BFF", c2: "#0A6CFF", keys: "wireless network internet ssid join" },
            { id: "bluetooth",  sec: 1, name: I18n.tr("Bluetooth"),       wg: "bluetooth",  c1: "#3D9BFF", c2: "#0A6CFF", keys: "devices pair headphones mouse keyboard" },
            { id: "sharing",    sec: 1, name: I18n.tr("Internet Sharing"), wg: "wifi",      c1: "#30D158", c2: "#15A52F", keys: "hotspot tether share wifi ap access point 2.0 passpoint" },
            { id: "network",    sec: 1, name: I18n.tr("Network"),         wg: "ethernet",   c1: "#3D9BFF", c2: "#0A6CFF", keys: "ethernet ip address vpn tailscale connection" },
            { id: "battery",    sec: 1, name: I18n.tr("Battery"),         wg: "bolt",       c1: "#4CD964", c2: "#28A745", keys: "power energy charge profile performance game mode" },
            { id: "general",    sec: 2, name: I18n.tr("General"),         glyph: "behavior", c1: "#9A9AA0", c2: "#636366", keys: "language enable disable dock menu bar panel show hide off on widgets sound game" },
            { id: "appearance", sec: 2, name: I18n.tr("Appearance"),      glyph: "appearance", c1: "#5A5A5F", c2: "#2C2C2E", keys: "theme dark light mode accent color glass liquid apple style translucency blur corner radius font" },
            { id: "icons",      sec: 2, name: I18n.tr("Icons"),           glyph: "apps",     c1: "#FF7AB6", c2: "#D63384", keys: "icon tinted tint colour color style dark light set dock app icons" },
            { id: "controlcenter", sec: 2, name: I18n.tr("Control Center"), wg: "cc",       c1: "#7D7AFF", c2: "#5856D6", keys: "modules tiles controls" },
            { id: "dock",       sec: 2, name: I18n.tr("Desktop & Dock"),  glyph: "dock",     c1: "#3D9BFF", c2: "#0A54D6", keys: "size icon magnification zoom spacing margin distance edge hide auto labels indicators bounce trash monitor preview minimise minimize genie fade effect" },
            { id: "widgets",    sec: 2, name: I18n.tr("Widgets"),         glyph: "widgets",  c1: "#FF9F0A", c2: "#FF7A00", keys: "desktop widgets weather clock calendar player image photo notes reminders stocks batteries alarms add remove arrange" },
            { id: "displays",   sec: 2, name: I18n.tr("Displays"),        wg: "sun",        c1: "#3D9BFF", c2: "#0A6CFF", keys: "brightness night shift monitor resolution refresh scale" },
            { id: "menubar",    sec: 2, name: I18n.tr("Menu Bar"),        glyph: "menubar",  c1: "#3D9BFF", c2: "#0A6CFF", keys: "panel bar height clock date seconds 24 hour battery tray search spotlight week monday style liquid bluetooth widget" },
            { id: "wallpaper",  sec: 2, name: I18n.tr("Wallpaper"),       glyph: "wallpaper", c1: "#5AC8FA", c2: "#007AFF", keys: "wallpaper background picture image video animated live motion desktop dynamic" },
            { id: "notifications", sec: 3, name: I18n.tr("Notifications"), wg: "bell",      c1: "#FF5E57", c2: "#E8342A", keys: "alerts banners popups do not disturb" },
            { id: "sound",      sec: 3, name: I18n.tr("Sound"),           wg: "speaker",    c1: "#FF5E7E", c2: "#E8344F", keys: "volume output input microphone speakers headphones effects" },
            { id: "focus",      sec: 3, name: I18n.tr("Focus"),           wg: "moon",       c1: "#BF5AF2", c2: "#8944AB", keys: "do not disturb keep awake sleep" },
            { id: "update",     sec: 4, name: I18n.tr("Software Update"), wg: "gear",       c1: "#FFB340", c2: "#FF8A00", keys: "update version changelog release notes upgrade" },
            { id: "lockscreen", sec: 4, name: I18n.tr("Lock Screen"),     wg: "lock",       c1: "#7D7AFF", c2: "#4B49C8", keys: "lock password album lyrics media clock" },
            { id: "users",      sec: 4, name: I18n.tr("Users & Groups"),  wg: "smile",      c1: "#3D9BFF", c2: "#0A6CFF", keys: "account user name picture avatar" },
            { id: "shortcuts",  sec: 5, name: I18n.tr("Keyboard Shortcuts"), wg: "command", c1: "#3D9BFF", c2: "#0A54D6", keys: "keybind shortcut hotkey spotlight switcher binds" },
            { id: "keyboard",   sec: 5, name: I18n.tr("Keyboard"),        wg: "keyboard",   c1: "#9A9AA0", c2: "#6E6E73", keys: "repeat rate delay layout typing" },
            { id: "mouse",      sec: 5, name: I18n.tr("Mouse"),           wg: "mouse",      c1: "#64D2FF", c2: "#0A84FF", keys: "tracking speed scroll natural" },
            { id: "trackpad",   sec: 5, name: I18n.tr("Trackpad"),        wg: "trackpad",   c1: "#4CD964", c2: "#1E9E3A", keys: "tap click natural scroll touchpad gestures" },
            { id: "apps",       sec: 6, name: I18n.tr("Applications"),    glyph: "apps",     c1: "#FFB340", c2: "#FF9500", keys: "pinned apps keep remove reset dock" },
            { id: "about",      sec: 6, name: I18n.tr("About"),           glyph: "about",    c1: "#C77DFF", c2: "#8944AB", keys: "version reset config folder macdock macbar macshell" }
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
        onCurChanged: flick.contentY = -flick.topMargin

        Shortcut { sequences: ["Escape", "Ctrl+W"]; onActivated: root.hideWin(prefsWindow) }

        // ── palette ──
        QtObject {
            id: pal
            readonly property bool dark: root.darkMode
            readonly property string fam: root.fontFamily
            property color accent: root.accent
            Behavior on accent { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            readonly property bool glass: root.liquidActive
            property color content: glass ? (dark ? Qt.rgba(0.09, 0.09, 0.10, 0.58) : Qt.rgba(0.97, 0.97, 0.98, 0.62))
                                                   : (dark ? "#1E1E1E" : "#F5F5F7")
            Behavior on content { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color sidebar: dark ? "#292929" : "#E9E9EC"
            Behavior on sidebar { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color card: glass ? (dark ? Qt.rgba(1, 1, 1, 0.065) : Qt.rgba(1, 1, 1, 0.55))
                                                : (dark ? "#2B2B2D" : "#FFFFFF")
            Behavior on card { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color cardBorder: dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.07)
            Behavior on cardBorder { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color windowBorder: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.22)
            Behavior on windowBorder { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            // two-tone macOS window edge: a thin dark line outside, a soft highlight just inside it
            property color edgeOuter: dark ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(0, 0, 0, 0.28)
            Behavior on edgeOuter { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color edgeInner: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.65)
            Behavior on edgeInner { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color sep: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.09)
            Behavior on sep { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color text: dark ? "#F5F5F7" : "#1D1D1F"
            Behavior on text { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color text2: dark ? Qt.rgba(1, 1, 1, 0.56) : Qt.rgba(0, 0, 0, 0.52)
            Behavior on text2 { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color text3: dark ? Qt.rgba(1, 1, 1, 0.32) : Qt.rgba(0, 0, 0, 0.30)
            Behavior on text3 { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color track: dark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.13)
            Behavior on track { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color switchOff: dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.14)
            Behavior on switchOff { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color ctrl: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06)
            Behavior on ctrl { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color ctrlSel: dark ? "#636366" : "#FFFFFF"
            Behavior on ctrlSel { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color button: dark ? Qt.rgba(1, 1, 1, 0.13) : "#FFFFFF"
            Behavior on button { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color buttonPressed: dark ? Qt.rgba(1, 1, 1, 0.24) : "#E4E4E7"
            Behavior on buttonPressed { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color buttonBorder: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.14)
            Behavior on buttonBorder { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color field: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.06)
            Behavior on field { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color hover: dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)
            Behavior on hover { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color selInactive: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)
            Behavior on selInactive { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color lightOff: dark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.15)
            Behavior on lightOff { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color danger: "#FF453A"
            Behavior on danger { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        }

        NumberAnimation { id: fadeIn; target: paneLoader; property: "opacity"; from: 0; to: 1; duration: 160 }

        // ── frame ──
        Rectangle {
            id: frame
            anchors.fill: parent
            radius: 12
            color: pal.content
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
                // Liquid Glass: a floating, inset glass sidebar like macOS Tahoe; otherwise the classic flat one
                x: pal.glass ? 8 : 1; y: pal.glass ? 8 : 1
                width: pal.glass ? 224 : 232
                height: parent.height - (pal.glass ? 16 : 2)
                radius: pal.glass ? 18 : 11
                // frosted: a translucent pane over Hyprland's blur of what's behind the window (no Liquid Glass shader)
                color: pal.glass ? (pal.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.35)) : pal.sidebar
                border.width: pal.glass ? 1 : 0
                border.color: pal.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)
                Rectangle { visible: !pal.glass; anchors.right: parent.right; width: 12; height: parent.height; color: parent.color }
                Rectangle { visible: !pal.glass; anchors.right: parent.right; width: 1; height: parent.height; color: pal.sep }

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
                            property real rimTint: 0
                            property real ringW: 0
                            property real flatInner: 0
                            property real saturation: 1.25
                            property real dark: root.darkMode ? 1 : 0
                            property real debug: 0
                            property real shadowAmt: 0.6
                        }
                    }
                }

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
                                color: (modelData.on && ((root.bar && root.bar.tlColorOnHover) ? lightsMa.containsMouse : (prefsWindow.active || lightsMa.containsMouse)))
                                       ? modelData.c : pal.lightOff
                                border.width: 1
                                border.color: Qt.rgba(0, 0, 0, 0.14)
                                Text {
                                    anchors.centerIn: parent
                                    visible: parent.modelData.on && (lightsMa.containsMouse || (root.bar && root.bar.tlAlwaysSymbols))
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
                            if (mouse.x < 22) root.hideWin(prefsWindow);
                            else if (mouse.x < 44) { if (root.hub && root.hub.minimizeWindow) root.hub.minimizeWindow(prefsWindow.title); else prefsWindow.showMinimized(); }
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
                        text: I18n.tr("Search")
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
                        Text { text: root.userName; color: prefsWindow.cur === acct.idx && prefsWindow.active ? "white" : pal.text; font.family: pal.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
                        Text { text: I18n.tr("Local Account"); color: prefsWindow.cur === acct.idx && prefsWindow.active ? Qt.rgba(1, 1, 1, 0.8) : pal.text2; font.family: pal.fam; font.pixelSize: 11 }
                    }
                    MouseArea { id: acctMa; anchors.fill: parent; hoverEnabled: true; onClicked: prefsWindow.go(acct.idx) }
                }

                // pane list (scrolls; sections separated by a gap, like System Settings)
                Flickable {
                    id: navFlick
                    x: 10; y: acct.visible ? 150 : 92
                    width: parent.width - 20
                    height: parent.height - y - 8
                    contentHeight: navCol.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    // feathered ends: items fade out as they scroll under the account card (and off the bottom) instead
                    // of being cut off. Only while there is something to scroll past that edge.
                    layer.enabled: navFlick.contentHeight > navFlick.height
                    layer.effect: ShaderEffect {
                        fragmentShader: Qt.resolvedUrl("fade.frag.qsb")
                        property real fadeTop: navFlick.contentY > 2 ? Math.min(0.14, 26 / Math.max(1, navFlick.height)) : 0.0015
                        property real fadeBottom: navFlick.contentY < navFlick.contentHeight - navFlick.height - 2 ? Math.min(0.14, 26 / Math.max(1, navFlick.height)) : 0.0015
                        Behavior on fadeTop { NumberAnimation { duration: 180 } }
                        Behavior on fadeBottom { NumberAnimation { duration: 180 } }
                    }
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
                    }

                    Text {
                        visible: prefsWindow.filtered.length === 0
                        width: parent.width
                        topPadding: 14
                        horizontalAlignment: Text.AlignHCenter
                        text: I18n.tr("No Results")
                        color: pal.text2
                        font.family: pal.fam
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

                // Liquid Glass, Frosted and Blur: the page scrolls UNDER the toolbar (macOS Tahoe), the toolbar blurs what
                // passes beneath it, and back / forward sit in a live glass pill — the Control Center's own liquid glass
                // shader (GlassSlab), refracting the page under it as it moves, over the window's own live blur.
                // Opaque (and Game Mode): the classic solid toolbar with plain chevrons.
                readonly property string navLook: root.solidLook ? "plain"
                    : (root.bar && (root.bar.material === "liquid" || (root.bar.material === "custom" && root.bar.barStyle === "liquid"))) ? "liquid"
                    : (root.bar && root.bar.material === "frosted") ? "frosted"
                    : (root.bar && root.bar.material === "opaque") ? "plain" : "blur"
                readonly property bool layered: navLook !== "plain"
                // the toolbar still moves the window (the page under it must not take the drag)
                DragHandler { target: null; onActiveChanged: if (active) prefsWindow.startSystemMove() }
                // what the toolbar sees: the strip of the page under it right now, over the window's own tint (live)
                Item {
                    id: tbBackdrop
                    // only the glass materials need it (tbSrc hides it there); in Opaque it would sit on top of the page
                    // as a solid strip 24 px taller than the toolbar and cut off the first row
                    visible: header.layered
                    width: header.width; height: header.height + 24
                    Rectangle { anchors.fill: parent; color: pal.content }
                    ShaderEffectSource {
                        anchors.fill: parent
                        sourceItem: header.layered ? paneLoader : null
                        live: true
                        sourceRect: Qt.rect(-paneLoader.x, flick.contentY - paneLoader.y, width, height)
                    }
                }
                ShaderEffectSource { id: tbSrc; sourceItem: header.layered ? tbBackdrop : null; hideSource: true; live: true; mipmap: true; visible: false }
                // the toolbar's edge: the page goes soft as it slides under (shows once something is under it)
                Item {
                    id: tbFade
                    width: tbBackdrop.width; height: tbBackdrop.height
                    visible: false
                    layer.enabled: true
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "white" }
                            GradientStop { position: 0.74; color: "white" }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }
                }
                MultiEffect {
                    visible: header.layered && opacity > 0.01
                    width: tbBackdrop.width; height: tbBackdrop.height
                    source: tbSrc
                    blurEnabled: true; blurMax: 32
                    blur: header.navLook === "liquid" ? 0.7 : 1.0
                    saturation: 0.2
                    autoPaddingEnabled: false
                    maskEnabled: true; maskSource: tbFade
                    opacity: (flick.contentY + flick.topMargin) > 1 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                }
                GlassSlab {
                    id: navPill
                    visible: header.layered
                    x: 10
                    y: (header.height - height) / 2
                    width: 66; height: 34
                    cornerR: 17
                    src: tbSrc
                    srcSize: Qt.size(tbBackdrop.width, tbBackdrop.height)
                    origin: Qt.point(x, y)
                    glass: root.glassState === "ready"
                    shaderUrl: root.glassShaderUrl
                    dark: pal.dark
                    // Liquid Glass bends the page at its rim; Frosted is a milky pane over it; Blur a plain soft pane
                    thickness: header.navLook === "liquid" ? 14 : 0
                    strengthMul: header.navLook === "liquid" ? 0.6 : 0
                    liquid: root.glassLiquid
                    // the edge is a subtle contour glow (below), not a drawn border
                    rim: header.navLook === "liquid" ? 0.12 : (header.navLook === "frosted" ? 0.06 : 0.02)
                    grain: root.glassGrain
                    tint: root.glassOpacity
                    tintMul: header.navLook === "frosted" ? 1.7 : (header.navLook === "blur" ? 1.2 : 1.0)
                    blurPx: header.navLook === "liquid" ? 1.5 : (header.navLook === "frosted" ? 10 : 6)
                    shadowAmt: 0
                    // Frosted: the milky white layer of frosted glass over the live blur
                    Rectangle {
                        visible: header.navLook === "frosted"
                        anchors.fill: parent; radius: height / 2
                        color: pal.dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0.45)
                    }
                    // contour glow: a faint light traced along the outline, brighter near the pointer while hovered
                    HoverHandler { id: pillHover }
                    ShaderEffect {
                        readonly property real gpad: 8
                        x: -gpad; y: -gpad
                        width: navPill.width + 2 * gpad; height: navPill.height + 2 * gpad
                        fragmentShader: Qt.resolvedUrl("contourglow.frag.qsb")
                        property vector2d itemSize: Qt.vector2d(width, height)
                        property vector2d mouse: pillHover.hovered ? Qt.vector2d(pillHover.point.position.x, pillHover.point.position.y)
                                                                   : Qt.vector2d(navPill.width * 0.3, 0)
                        property real pad: gpad
                        property real cornerR: navPill.height / 2
                        property real amount: pillHover.hovered ? 0.75 : (pal.dark ? 0.32 : 0.45)
                        Behavior on amount { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                        property real spread: 46
                        property vector4d tint: Qt.vector4d(1, 1, 1, 1)
                    }
                    // a hair-thin divider between the two buttons
                    Rectangle {
                        anchors.centerIn: parent
                        width: 1; height: parent.height - 14
                        color: pal.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
                    }
                }
                Row {
                    x: header.navLook === "plain" ? 14 : 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: header.navLook === "plain" ? 2 : 0
                    Repeater {
                        model: [ { g: "\u2039", dir: -1 }, { g: "\u203A", dir: 1 } ]
                        delegate: Item {
                            id: navBtn
                            required property var modelData
                            readonly property bool ok: modelData.dir < 0 ? prefsWindow.backStack.length > 0
                                                                           : prefsWindow.fwdStack.length > 0
                            width: header.navLook === "plain" ? 26 : 33; height: header.navLook === "plain" ? 28 : 34
                            // hover / press: a faint light inside the pill half
                            Rectangle {
                                visible: header.navLook !== "plain"
                                anchors.fill: parent; anchors.margins: 3
                                radius: height / 2
                                color: (navBtn.ok && navMa.containsMouse) ? (pal.dark ? Qt.rgba(1, 1, 1, navMa.pressed ? 0.14 : 0.08) : Qt.rgba(0, 0, 0, navMa.pressed ? 0.10 : 0.05)) : "transparent"
                                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            }
                            Text {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -2
                                text: navBtn.modelData.g
                                font.pixelSize: header.navLook === "plain" ? 28 : 26
                                font.weight: header.navLook === "plain" ? Font.Normal : Font.DemiBold
                                color: navBtn.ok ? (header.navLook === "plain" ? pal.text2 : pal.text) : pal.text3
                                opacity: navBtn.ok ? 1 : 0.5
                                scale: (navBtn.ok && navMa.pressed) ? 0.86 : 1
                                Behavior on scale { NumberAnimation { duration: 230; easing.type: Easing.OutBack; easing.overshoot: 3 } }
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
                    x: header.navLook === "plain" ? 74 : 88
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
                    opacity: (flick.contentY + flick.topMargin) > 4 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
            }

            // ───────── scrolling content ─────────
            Flickable {
                id: flick
                x: sidebar.x + sidebar.width + 1
                y: header.layered ? 0 : 52
                width: parent.width - sidebar.x - sidebar.width - 2
                height: parent.height - y - 1
                topMargin: header.layered ? 52 : 0
                // the sharp page fades out as it slides under the toolbar; the toolbar shows it blurred instead
                layer.enabled: header.layered
                layer.effect: MultiEffect { maskEnabled: true; maskSource: flickFade }
                contentWidth: width
                contentHeight: paneLoader.height + 36
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick

                Loader {
                    id: paneLoader
                    // nothing of Settings stays built while the window is closed
                    active: prefsWindow.visible
                    x: 22
                    y: 6
                    width: flick.width - 44
                    sourceComponent: ({
                        wifi: paneWifi, bluetooth: paneBt, network: paneNetwork, battery: paneBattery,
                        general: paneGeneral, appearance: paneAppearance, icons: paneIcons, controlcenter: paneCC, dock: paneDesktopDock,
                        widgets: paneWidgets, displays: paneDisplays, menubar: paneMenuBar, wallpaper: paneWallpaper,
                        notifications: paneNotif, sound: paneSound, focus: paneFocus,
                        update: paneUpdate, shortcuts: paneShortcuts, sharing: paneSharing, lockscreen: paneLock, users: paneUsers, keyboard: paneKeyboard, mouse: paneMouse, trackpad: paneTrackpad,
                        apps: paneApps, about: paneAbout
                    })[prefsWindow.panes[prefsWindow.cur].id]
                    onLoaded: fadeIn.restart()
                }
            }
            Item {
                id: flickFade
                width: flick.width; height: flick.height
                visible: false
                layer.enabled: true
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 42 / Math.max(1, flickFade.height); color: "transparent" }
                        GradientStop { position: 58 / Math.max(1, flickFade.height); color: "white" }
                        GradientStop { position: 1.0; color: "white" }
                    }
                }
            }
            Rectangle {   // thin overlay scrollbar
                visible: flick.contentHeight > flick.height + 1
                x: frame.width - 8
                y: 52 + Math.max(0, flick.visibleArea.yPosition) * (flick.height - flick.topMargin)
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
                    text: I18n.tr("If you turn both off, Super + , (comma) opens this window again.")
                }

                SLabel { t: pal; header: true; text: I18n.tr("More") }
                SCard {
                    t: pal
                    Repeater {
                        model: [{ id: "about", n: "About", d: "This shell, its configuration folder, and restarting or resetting it" },
                                { id: "update", n: "Software Update", d: "Get the latest MacShell" },
                                { id: "users", n: "Users & Groups", d: "Your name and picture" },
                                { id: "shortcuts", n: "Keyboard Shortcuts", d: "Every shortcut, editable" }]
                        delegate: Item {
                            id: navRow
                            required property var modelData
                            width: parent ? parent.width : 0
                            height: navSRow.height
                            SRow {
                                id: navSRow
                                t: pal
                                title: navRow.modelData.n
                                subtitle: navRow.modelData.d
                                Text { text: "\u203A"; color: pal.text3; font.family: pal.fam; font.pixelSize: 20 }
                            }
                            Rectangle { visible: navRow.y > 0.5; x: 14; width: parent.width - 14; height: 1; color: pal.sep }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: { for (var i = 0; i < prefsWindow.panes.length; i++) if (prefsWindow.panes[i].id === navRow.modelData.id) { prefsWindow.go(i); break; } }
                            }
                        }
                    }
                }
            }
        }

        // ── Icons ──
        Component {
            id: paneIcons
            Column {
                spacing: 10
                // a live preview: the first apps in your Dock, drawn the way the Dock draws them
                SCard {
                    t: pal
                    Item {
                        width: parent.width; height: 96
                        Row {
                            anchors.centerIn: parent
                            spacing: 14
                            Repeater {
                                model: root.items.filter(function (it) { return it.kind === "app"; }).slice(0, 7)
                                delegate: Item {
                                    required property var modelData
                                    width: 52; height: 52
                                    Image {
                                        id: pvImg
                                        anchors.fill: parent
                                        source: root.cellIconSrc(parent.modelData)
                                        sourceSize: Qt.size(104, 104)
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true; mipmap: true; asynchronous: true
                                        visible: false
                                    }
                                    MultiEffect {
                                        anchors.fill: pvImg
                                        source: pvImg
                                        shadowEnabled: true; shadowColor: "black"; shadowOpacity: 0.3; shadowBlur: 0.5; shadowVerticalOffset: 2
                                        colorization: root.iconColorize
                                        colorizationColor: root.iconColorizeColor
                                        brightness: root.iconBright
                                        saturation: root.iconSat
                                        opacity: root.iconAlpha * (1 - root.iconSwap)
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
                        title: I18n.tr("Icon style")
                        subtitle: root.tintAllowed ? I18n.tr("Like macOS Tahoe: Dark icons, Clear glass (follows your material) or Tinted in one colour")
                                                   : "Clear and Tinted need a glass material: Liquid Glass, Frosted or Blur (Appearance \u2192 Material)"
                        SSegmented {
                            t: pal
                            model: ["Default", "Dark", "Clear", "Tinted"]
                            segWidth: 66
                            current: Math.max(0, ["default", "dark", "clear", "tinted"].indexOf(root.iconStyle))
                            onPicked: i => root.iconStyle = ["default", "dark", "clear", "tinted"][i]
                        }
                    }
                    SRow {
                        t: pal
                        visible: root.iconLook === "tinted"
                        title: I18n.tr("Tint colour")
                        Row {
                            spacing: 8
                            Repeater {
                                model: ["", "#0A84FF", "#BF5AF2", "#FF375F", "#FF453A", "#FF9F0A", "#FFD60A", "#30D158", "#8E8E93"]
                                delegate: Rectangle {
                                    required property string modelData
                                    readonly property bool sel: root.iconTint === modelData
                                    width: 20; height: 20; radius: 10
                                    color: modelData === "" ? root.accent : modelData
                                    border.width: sel ? 2 : 0
                                    border.color: pal.text
                                    scale: tMa.containsMouse ? 1.12 : 1
                                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                    // the first one is "the accent colour": it follows Appearance
                                    Text { visible: parent.modelData === ""; anchors.centerIn: parent; text: "A"; color: "white"; font.pixelSize: 10; font.bold: true }
                                    MouseArea { id: tMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.iconTint = parent.modelData }
                                }
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
                        title: I18n.tr("Menu Bar and widget size")
                        subtitle: I18n.tr("Scales the bar widgets; the left and right groups stay tucked into the screen corners")
                        SSlider {
                            t: pal; from: 22; to: 48; stepSize: 1
                            value: root.bar ? root.bar.barHeight : 28
                            leftLabel: I18n.tr("Compact"); rightLabel: I18n.tr("Large")
                            onMoved: v => { if (root.bar) root.bar.barHeight = Math.round(v); }
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
                                    font.family: pal.fam
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
                                    font.family: pal.fam
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
                        subtitle: I18n.tr("A translucent strip behind the menu bar that blurs the wallpaper under it")
                        SSlider {
                            t: pal
                            from: 0; to: 0.6; stepSize: 0.01
                            value: root.bar ? root.bar.barBgOpacity : 0.10
                            leftLabel: I18n.tr("Hidden"); rightLabel: I18n.tr("Tinted")
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
                        subtitle: I18n.tr("Whatever moves under a panel moves under the glass too \u2014 live, not a snapshot. Costs a few percent of a core while the Dock or a panel is on screen; turn it off for the cheaper snapshot.")
                        SSwitch {
                            t: pal
                            checked: root.bar ? root.bar.glassRealtime : true
                            onToggled: v => { if (root.bar) root.bar.glassRealtime = v; }
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

                SLabel { t: pal; header: true; text: I18n.tr("Clipboard") }
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
                    text: I18n.tr("Translucency, accent color, appearance and font are in Appearance. Commands (terminal, launcher, files, clipboard) can be edited in ~/.config/macbar/settings.json.")
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
                        color: root.darkMode ? Qt.rgba(0.10, 0.10, 0.11, root.solidLook ? 1 : root.glassOpacity)
                                             : Qt.rgba(root.solidLook ? 0.97 : 1, root.solidLook ? 0.97 : 1, root.solidLook ? 0.98 : 1, root.solidLook ? 1 : root.glassOpacity * 0.55)
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
                        title: I18n.tr("Size")
                        SSlider {
                            t: pal
                            from: 32; to: 128; stepSize: 1
                            value: root.iconSizePref
                            leftLabel: I18n.tr("Small"); rightLabel: I18n.tr("Large")
                            onMoved: v => root.iconSizePref = Math.round(v)
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
                            onMoved: v => root.magnification = v
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
                            onMoved: v => root.margin = Math.round(v)
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
                        title: I18n.tr("Material")
                        subtitle: I18n.tr("Sets the menu bar, Dock, Spotlight, Control Center, notifications, the switcher and the widgets in one go")
                        SSegmented {
                            t: pal
                            model: ["Liquid Glass", "Frosted", "Blur", "Opaque"]
                            segWidth: 86
                            current: { var m = root.bar ? root.bar.material : "liquid"; return ["liquid", "frosted", "blur", "opaque"].indexOf(m); }
                            onPicked: i => { if (root.bar) root.bar.applyMaterial(["liquid", "frosted", "blur", "opaque"][i]); }
                        }
                    }
                    // every material but Opaque blurs what is behind it
                    SRow {
                        t: pal
                        visible: root.bar && root.bar.material !== "opaque"
                        title: I18n.tr("Blur")
                        subtitle: I18n.tr("How much the menus, Control Center, notifications and Spotlight blur what's behind them")
                        SSlider {
                            t: pal
                            width: 220
                            from: 0; to: 60; stepSize: 1
                            value: root.bar ? root.bar.glassBlur : 16
                            leftLabel: I18n.tr("Clear"); rightLabel: I18n.tr("Very blurry")
                            onMoved: v => { if (root.bar) root.bar.glassBlur = Math.round(v); }
                        }
                    }
                    // Tint belongs to the two materials that have glass to tint
                    SRow {
                        t: pal
                        visible: root.bar && (root.bar.material === "liquid" || root.bar.material === "frosted" || root.bar.material === "custom")
                        title: I18n.tr("Tint")
                        subtitle: I18n.tr("How much colour the glass carries. Frosted and Liquid Glass only.")
                        SSlider {
                            t: pal
                            width: 220
                            from: 0; to: 1; stepSize: 0.01
                            value: root.bar ? root.bar.glassOpacity : 0.42
                            leftLabel: I18n.tr("Clear"); rightLabel: I18n.tr("Tinted")
                            onMoved: v => { if (root.bar) { root.bar.glassOpacity = v; root.bar.materialTouched(); } }
                        }
                    }
                    SRow {
                        t: pal
                        visible: root.bar && (root.bar.material === "liquid" || root.bar.material === "frosted" || root.bar.material === "custom")
                        title: I18n.tr("Tint colour")
                        subtitle: I18n.tr("Neutral glass, or glass that picks up the accent colour")
                        SSegmented {
                            t: pal
                            model: ["Neutral", "Accent"]
                            segWidth: 86
                            current: (root.bar && root.bar.tintAccent) ? 1 : 0
                            onPicked: i => { if (root.bar) { root.bar.tintAccent = (i === 1); root.bar.materialTouched(); } }
                        }
                    }
                    SRow {
                        t: pal
                        visible: root.bar && root.bar.material === "custom"
                        title: I18n.tr("Material: Custom")
                        subtitle: I18n.tr("You changed one of the pieces below by hand. Pick a material above to set everything again.")
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Appearance")
                        subtitle: I18n.tr("Applies to the Dock, the Menu Bar and this window")
                        Row {
                            spacing: 14
                            SThemeTile {
                                t: pal; label: I18n.tr("Light"); dark: false
                                selected: !root.darkMode
                                onClicked: root.setLook("darkMode", false)
                            }
                            SThemeTile {
                                t: pal; label: I18n.tr("Dark"); dark: true
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
                                    width: 28; height: 28
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
                                        width: 24; height: 24; radius: 12
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
                        title: I18n.tr("Translucency")
                        subtitle: root.dockStyle === "liquid" ? I18n.tr("How much tint the glass adds over the refraction")
                                                              : "How frosted the Dock's glass looks"
                        SSlider {
                            t: pal
                            from: 0.0; to: 0.85; stepSize: 0.01
                            value: root.glassOpacity
                            leftLabel: I18n.tr("Clear"); rightLabel: I18n.tr("Frosted")
                            onMoved: v => root.setLook("glassOpacity", v)
                        }
                    }
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
                            onMoved: v => root.setLook("glassLiquid", v)
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
                            onMoved: v => root.cornerRadius = Math.round(v)
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
                            segWidth: 86
                            current: root.fontFamily === "Open Runde" ? 0 : (root.fontFamily === "Noto Sans" ? 1 : 2)
                            onPicked: i => root.setLook("fontFamily", ["Open Runde", "Noto Sans", "sans-serif"][i])
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
                        title: I18n.tr("Minimise windows using")
                        subtitle: root.minimizeEffect === "genie" ? I18n.tr("Magic Lamp: the window pours into the Dock, and back out again")
                                : (root.minimizeEffect === "fade" ? "An elegant fade (0.35 s) into the Dock"
                                                                   : "No animation: the window just goes")
                        SSegmented {
                            t: pal
                            model: ["Magic Lamp", "Fade", "Instant"]
                            segWidth: 84
                            current: root.minimizeEffect === "fade" ? 1 : (root.minimizeEffect === "instant" ? 2 : 0)
                            onPicked: i => root.minimizeEffect = ["genie", "fade", "instant"][i]
                        }
                    }
                    SRow {
                        t: pal
                        visible: root.minimizeEffect === "genie"
                        title: I18n.tr("Magic Lamp speed")
                        subtitle: root.minimizeSecs.toFixed(2) + " s"
                        SSlider {
                            t: pal
                            width: 220
                            // left = fast: the slider value is the duration, reversed
                            from: 0; to: 1; stepSize: 0.01
                            value: (0.9 - root.minimizeSecs) / 0.65
                            leftLabel: I18n.tr("Slow"); rightLabel: I18n.tr("Fast")
                            onMoved: v => root.minimizeSecs = Math.round((0.9 - v * 0.65) * 100) / 100
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Automatically hide and show the Dock")
                        subtitle: root.hideMode === "smart" ? I18n.tr("Hides while a window fills the screen — maximised, fullscreen or tiled")
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
                        title: I18n.tr("Hide delay")
                        SSlider {
                            t: pal
                            from: 0; to: 1500; stepSize: 50
                            value: root.hideDelay
                            leftLabel: I18n.tr("Instant"); rightLabel: "1.5 s"
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
                                  ? "Connected" + (wifiPane.eth.ip !== "" ? " · " + wifiPane.eth.ip : "") + (parseInt(wifiPane.eth.speed) > 0 ? " · " + wifiPane.eth.speed + " Mb/s" : "")
                                  : "Cable unplugged")
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
                                    else { root.hideWin(prefsWindow); root.bar.wifiJoin(modelData.ssid); }
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

        // ── Bluetooth ──
        Component {
            id: paneBt
            Column {
                id: btPane
                spacing: 10
                property var devs: []
                function refresh() { if (!btList.running) btList.running = true; }
                Component.onCompleted: refresh()
                Timer { interval: 3000; repeat: true; running: prefsWindow.visible; onTriggered: btPane.refresh() }
                Process {
                    id: btList
                    command: ["sh", "-c", "bluetoothctl devices Paired 2>/dev/null | while read -r _ mac name; do c=$(bluetoothctl info \"$mac\" 2>/dev/null | grep -c 'Connected: yes'); b=$(bluetoothctl info \"$mac\" 2>/dev/null | sed -n 's/.*Battery Percentage: 0x[0-9a-fA-F]* (\\([0-9]*\\)).*/\\1/p'); printf '%s\\t%s\\t%s\\t%s\\n' \"$mac\" \"$name\" \"$c\" \"$b\"; done"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            var out = [], l = text.split("\n");
                            for (var i = 0; i < l.length; i++) { var f = l[i].split("\t"); if (f.length >= 3 && f[0] !== "") out.push({ mac: f[0], name: f[1], on: f[2] === "1", bat: f[3] || "" }); }
                            btPane.devs = out;
                        }
                    }
                }
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: I18n.tr("Bluetooth")
                        subtitle: root.bar && root.bar.btOn ? I18n.tr("This computer is discoverable as \"") + root.userName + "\"" : I18n.tr("Off")
                        SSwitch { t: pal; checked: root.bar ? root.bar.btOn : false; onToggled: v => { if (root.bar && root.bar.btOn !== v) root.bar.toggleBt(); } }
                    }
                }
                SLabel { t: pal; header: true; text: I18n.tr("My Devices"); visible: btPane.devs.length > 0 }
                SCard {
                    t: pal
                    visible: btPane.devs.length > 0
                    Repeater {
                        model: btPane.devs
                        delegate: SRow {
                            required property var modelData
                            t: pal
                            title: modelData.name
                            subtitle: (modelData.on ? I18n.tr("Connected") : I18n.tr("Not Connected")) + (modelData.bat !== "" ? " · " + modelData.bat + "%" : "")
                            SButton {
                                t: pal; text: modelData.on ? I18n.tr("Disconnect") : I18n.tr("Connect")
                                onClicked: { Quickshell.execDetached(["bluetoothctl", modelData.on ? "disconnect" : "connect", modelData.mac]); btLater.restart(); }
                            }
                        }
                    }
                }
                Timer { id: btLater; interval: 2500; onTriggered: btPane.refresh() }
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
                            title: ({ ethernet: I18n.tr("Ethernet"), wifi: "Wi-Fi", tun: modelData.dev === "tailscale0" ? "Tailscale" : "VPN" })[modelData.type] || modelData.dev
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
                            Text { text: batPane.pct + "%"; color: pal.text; font.family: pal.fam; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
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
                        subtitle: I18n.tr("Turns off blur, shadows, animations and Liquid Glass, pauses an animated wallpaper and uses High Power")
                        SSwitch { t: pal; checked: root.bar ? root.bar.gamingMode : false; onToggled: v => { if (root.bar) root.bar.gamingMode = v; } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Turn on automatically for fullscreen games")
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
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Animate when it opens")
                        subtitle: I18n.tr("Off: it simply appears, with no slide or stagger")
                        SSwitch { t: pal; checked: root.bar ? root.bar.ccAnimate : true; onToggled: v => { if (root.bar) root.bar.ccAnimate = v; } }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Style")
                        subtitle: I18n.tr("Tiles gives every control its own piece of Liquid Glass; macOS puts them on one frosted panel")
                        SSegmented {
                            t: pal; model: ["Tiles", "macOS"]; segWidth: 80
                            current: root.bar && root.bar.ccStyle === "macos" ? 1 : 0
                            onPicked: i => { if (root.bar) root.bar.ccStyle = i === 1 ? "macos" : "tiles"; }
                        }
                    }
                }
                SLabel { t: pal; text: I18n.tr("Choose which controls appear in Control Center. You can also drag them around in Control Center → Edit Controls.") }
                SCard {
                    t: pal
                    Repeater {
                        model: root.bar ? root.bar.ccCatalog : []
                        delegate: SRow {
                            required property var modelData
                            t: pal
                            title: modelData.label
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
                SLabel { t: pal; header: true; text: I18n.tr("Dock Behaviour") }
                Loader { width: parent.width; sourceComponent: paneBehavior }

                SLabel { t: pal; header: true; text: I18n.tr("Desktop") }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Show items on the desktop")
                        subtitle: I18n.tr("Files, folders and apps in ~/Desktop. Drag to move, double-click to open, drop one onto another to make a folder.")
                        SSwitch { t: pal; checked: root.desktopIcons; onToggled: v => root.desktopIcons = v }
                    }
                }
                SLabel { t: pal; text: I18n.tr("Widgets have their own page: System Settings \u2192 Widgets.") }

                SLabel { t: pal; header: true; text: I18n.tr("Windows") }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Always show window button symbols")
                        subtitle: I18n.tr("The × − ↗ marks stay visible instead of appearing when you point at them")
                        SSwitch { t: pal; checked: root.bar ? root.bar.tlAlwaysSymbols : false; onToggled: v => { if (root.bar) root.bar.tlAlwaysSymbols = v; } }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Colour the window buttons only on hover")
                        subtitle: I18n.tr("They stay grey until you point at them, even in the active window")
                        SSwitch { t: pal; checked: root.bar ? root.bar.tlColorOnHover : false; onToggled: v => { if (root.bar) root.bar.tlColorOnHover = v; } }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Open windows floating")
                        subtitle: I18n.tr("New windows float like on macOS instead of tiling. Takes effect for windows opened from now on.")
                        SSwitch { t: pal; checked: root.windowsFloat; onToggled: v => root.windowsFloat = v }
                    }
                }

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
                            onPicked: i => { if (root.bar) { root.bar.switcherStyle = ["glass", "frosted", "opaque"][i]; root.bar.materialTouched(); } }
                        }
                    }
                }
            }
        }

        // ── Displays ──
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
                            { type: "image",    name: I18n.tr("Image"),    hint: I18n.tr("Your own picture (you choose the file)"), styles: [["normal", I18n.tr("Photo")]] },
                            { type: "batteries", name: I18n.tr("Batteries"), hint: I18n.tr("This computer and your Bluetooth devices"), styles: [["liquid", I18n.tr("Liquid Glass")], ["normal", I18n.tr("Normal")]] },
                            { type: "notes",     name: I18n.tr("Notes"),     hint: I18n.tr("A note you write in notes.md"), styles: [["liquid", I18n.tr("Liquid Glass")], ["normal", I18n.tr("Normal")]] },
                            { type: "photos",    name: I18n.tr("Photos"),    hint: I18n.tr("A picture from ~/Pictures, a new one every 15 minutes"), styles: [["liquid", I18n.tr("Liquid Glass")], ["normal", I18n.tr("Normal")]] },
                            { type: "reminders", name: I18n.tr("Reminders"), hint: I18n.tr("Your list from reminders.md; click a circle to tick it off"), styles: [["liquid", I18n.tr("Liquid Glass")], ["normal", I18n.tr("Normal")]] },
                            { type: "alarms",    name: I18n.tr("Alarms"),    hint: I18n.tr("Alarms, the timer and the stopwatch from the Clock app"), styles: [["liquid", I18n.tr("Liquid Glass")], ["normal", I18n.tr("Normal")]] },
                            { type: "stocks",    name: I18n.tr("Stocks"),    hint: I18n.tr("A small watchlist"), styles: [["liquid", I18n.tr("Liquid Glass")], ["normal", I18n.tr("Normal")]] }
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
                        SSlider { t: pal; value: root.bar ? root.bar.brightness : 0.5; onMoved: v => { if (root.bar) root.bar.setBrightness(v); } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Night Shift")
                        subtitle: I18n.tr("Warmer colours to reduce blue light")
                        SSwitch { t: pal; checked: root.bar ? root.bar.nightOn : false; onToggled: v => { if (root.bar) root.bar.nightOn = v; } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Colour Temperature"); visible: root.bar && root.bar.nightOn
                        SSlider {
                            t: pal; leftLabel: I18n.tr("Less Warm"); rightLabel: I18n.tr("More Warm")
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
                        color: pal.text; font.family: pal.fam; font.pixelSize: 13; font.weight: Font.DemiBold
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
                    SButton { t: pal; text: "Send Test Notification"; onClicked: Quickshell.execDetached(["notify-send", "-a", "Settings", "Test notification", "Notifications are working"]) }
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
                        SSlider { t: pal; value: root.bar ? (root.bar.muted ? 0 : root.bar.volume) : 0; onMoved: v => { if (root.bar) root.bar.setVolume(v); } }
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
                        SSlider { t: pal; value: sndPane.src && sndPane.src.audio ? sndPane.src.audio.volume : 0; onMoved: v => { if (sndPane.src && sndPane.src.audio) sndPane.src.audio.volume = v; } }
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

        // ── Internet Sharing (a Wi-Fi hotspot, what Windows calls Mobile Hotspot) ──
        Component {
            id: paneSharing
            Column {
                id: shPane
                spacing: 10
                property bool on: false
                // kept on the shell, not on this page, so closing Settings doesn't forget them
                property string ssid: root.hotspotSsid
                property string pass: root.hotspotPass
                property string band: root.hotspotBand
                onSsidChanged: root.hotspotSsid = ssid
                onPassChanged: root.hotspotPass = pass
                onBandChanged: root.hotspotBand = band
                property string status: ""
                property int clients: 0
                Component.onCompleted: { shPane.refresh(); capProc.running = true; }
                Timer { interval: 4000; repeat: true; running: prefsWindow.visible && prefsWindow.panes[prefsWindow.cur].id === "sharing"; onTriggered: shPane.refresh() }
                // Can this radio run a client and an access point at once, and is the helper that makes
                // the AP interface there? If both, sharing never touches the Wi-Fi connection.
                property string apMode: "checking"      // checking | shared | takeover
                Process {
                    id: capProc
                    command: [Quickshell.env("HOME") + "/.config/hypr-macshell/scripts/macshell-sharing.sh", "mode"]
                    stdout: StdioCollector { onStreamFinished: shPane.apMode = text.trim() === "shared" ? "shared" : "takeover" }
                }
                function refresh() { if (!hsProc.running) hsProc.running = true; }
                Process {
                    id: hsProc
                    command: ["sh", "-c",
                        "nmcli -t -f NAME con show --active 2>/dev/null | grep -Fx MacShell-Hotspot | head -1; "
                        + "dev=$(nmcli -t -f NAME,DEVICE con show --active 2>/dev/null | awk -F: '$1==\"MacShell-Hotspot\"{print $2; exit}'); "
                        + "[ -n \"$dev\" ] && iw dev \"$dev\" station dump 2>/dev/null | grep -c '^Station' || echo 0"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            var l = text.split("\n");
                            shPane.on = (l[0] || "").trim() === "MacShell-Hotspot";
                            shPane.clients = shPane.on ? (parseInt((l[1] || "0").trim()) || 0) : 0;
                            if (shPane.ssid === "") shPane.ssid = (Quickshell.env("USER") || "MacShell") + "'s MacShell";
                        }
                    }
                }
                function start() {
                    shPane.status = "Starting\u2026";
                    // remember the network we are on, so switching sharing back off puts us back on it
                    if (root.bar && root.bar.wifiSsid !== "") root.hotspotPrevWifi = root.bar.wifiSsid;
                    hsStart.running = false;
                    hsStart.command = [Quickshell.env("HOME") + "/.config/hypr-macshell/scripts/macshell-sharing.sh", "start",
                                       shPane.ssid, shPane.pass, shPane.band];
                    hsStart.running = true;
                }
                function stop() {
                    shPane.status = "Stopping\u2026";
                    hsStop.running = false;
                    // and re-join whatever we were on before, so the Wi-Fi menu is not left empty
                    hsStop.command = [Quickshell.env("HOME") + "/.config/hypr-macshell/scripts/macshell-sharing.sh", "stop",
                                      root.hotspotPrevWifi];
                    hsStop.running = true;
                }
                Process {
                    id: hsStart
                    stdout: StdioCollector { onStreamFinished: { shPane.status = text.trim().indexOf("success") >= 0 || text.trim() === "" ? "" : text.trim(); shPane.refresh(); } }
                    onExited: (code) => { if (code !== 0 && shPane.status === "") shPane.status = "Couldn't start the hotspot."; shPane.refresh(); }
                }
                Process { id: hsStop; onExited: { shPane.status = ""; shPane.refresh(); if (root.bar) root.bar.scanWifi(); } }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Share this computer's connection")
                        subtitle: shPane.on ? (shPane.clients > 0 ? shPane.clients + (shPane.clients === 1 ? I18n.tr(" device connected") : I18n.tr(" devices connected")) : I18n.tr("On \u2014 waiting for devices"))
                                 : (shPane.apMode === "shared" ? "Other devices can join. Your Wi\u2011Fi connection stays up."
                                 : (shPane.apMode === "checking" ? "\u2026"
                                 : "Takes the Wi\u2011Fi adapter over while it is on"))
                        SSwitch {
                            t: pal
                            checked: shPane.on
                            onToggled: v => { if (v) shPane.start(); else shPane.stop(); }
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Network name")
                        Rectangle {
                            width: 230; height: 26; radius: 7; color: pal.field
                            TextInput {
                                x: 9; width: parent.width - 18; anchors.verticalCenter: parent.verticalCenter
                                text: shPane.ssid
                                onTextChanged: shPane.ssid = text
                                enabled: !shPane.on
                                color: shPane.on ? pal.text3 : pal.text; font.family: pal.fam; font.pixelSize: 13
                                selectByMouse: true
                            }
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Password")
                        subtitle: I18n.tr("At least 8 characters. Left empty, it uses \"macshell1\". Remembered for next time.")
                        Rectangle {
                            width: 230; height: 26; radius: 7; color: pal.field
                            TextInput {
                                x: 9; width: parent.width - 18; anchors.verticalCenter: parent.verticalCenter
                                text: shPane.pass
                                onTextChanged: shPane.pass = text
                                enabled: !shPane.on
                                echoMode: TextInput.Password
                                color: shPane.on ? pal.text3 : pal.text; font.family: pal.fam; font.pixelSize: 13
                                selectByMouse: true
                            }
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Band")
                        subtitle: I18n.tr("5 GHz is faster, 2.4 GHz reaches further and more devices support it")
                        SSegmented {
                            t: pal; model: ["2.4 GHz", "5 GHz"]; segWidth: 80
                            current: shPane.band === "a" ? 1 : 0
                            onPicked: i => shPane.band = i === 1 ? "a" : "bg"
                        }
                    }
                    SRow {
                        t: pal
                        visible: shPane.status !== ""
                        title: shPane.status
                    }
                }
                // Sharing without dropping Wi-Fi needs one small helper installed as root; until it is
                // there, sharing works the old way and takes the adapter.
                SCard {
                    t: pal
                    visible: shPane.apMode === "takeover"
                    SRow {
                        t: pal
                        title: I18n.tr("Keep Wi\u2011Fi connected while sharing")
                        subtitle: I18n.tr("Runs the hotspot on its own interface, the way Windows and KDE do. Needs a small ")
                                + "helper installed once (it can only add or remove that interface)."
                        SButton {
                            t: pal
                            text: I18n.tr("Set Up\u2026")
                            onClicked: {
                                var inst = Quickshell.env("HOME") + "/.local/share/macshell/bin/macshell-install";
                                var term = root.bar ? root.bar.terminal : "kitty";
                                Quickshell.execDetached(["sh", "-c", term + " -e sh -c '\"$0\" --hotspot; echo; echo Press Enter to close; read x'", inst]);
                            }
                        }
                    }
                }
            }
        }

        // ── Keyboard Shortcuts ──
        // Every MacShell shortcut, editable. What you set is written to ~/.config/macshell/keybinds.lua, which the
        // session config reads after its own binds, so your choice wins and an update never overwrites it.
        Component {
            id: paneShortcuts
            Column {
                id: scPane
                spacing: 10
                property string capturing: ""          // the id of the shortcut listening for a key
                property var pending: null             // the Hyprland bind being moved
                property string filter: ""
                property var hyprAll: []
                readonly property var hyprShown: {
                    var f = scPane.filter, out = [];
                    for (var i = 0; i < hyprAll.length; i++) {
                        var b = hyprAll[i];
                        if (f === "" || b.desc.toLowerCase().indexOf(f) >= 0 || b.combo.toLowerCase().indexOf(f) >= 0
                            || (b.dispatcher || "").toLowerCase().indexOf(f) >= 0) out.push(b);
                        if (out.length >= 300) break;
                    }
                    return out;
                }
                function isOff(combo) { var m = root.hyprBinds || ({}); return m[combo] !== undefined && !m[combo].combo; }
                function comboNow(combo) { var m = root.hyprBinds || ({}); return (m[combo] && m[combo].combo) ? m[combo].combo : combo; }
                function setEnabled(b, on) {
                    var m = {}; for (var k in (root.hyprBinds || ({}))) m[k] = root.hyprBinds[k];
                    if (on) delete m[b.combo];
                    else m[b.combo] = { combo: "", action: "", desc: b.desc };
                    root.hyprBinds = m; root.saveSettings(); scPane.write();
                }
                function moveBind(b, combo) {
                    var m = {}; for (var k in (root.hyprBinds || ({}))) m[k] = root.hyprBinds[k];
                    m[b.combo] = { combo: combo, action: b.action, desc: b.desc };
                    root.hyprBinds = m; root.saveSettings(); scPane.write();
                }
                // what Hyprland currently has bound
                Process {
                    id: bindsProc
                    running: true
                    command: ["sh", "-c", "hyprctl binds -j 2>/dev/null || echo '[]'"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            var list = [];
                            try { list = JSON.parse(text); } catch (e) { list = []; }
                            var mods = [[1, "SHIFT"], [4, "CTRL"], [8, "ALT"], [64, "SUPER"]], out = [], seen = {};
                            for (var i = 0; i < list.length; i++) {
                                var b = list[i];
                                if (!b.key && !b.keycode) continue;
                                var parts = [];
                                for (var m = 0; m < mods.length; m++) if ((b.modmask & mods[m][0]) !== 0) parts.push(mods[m][1]);
                                parts.push(b.key || ("code:" + b.keycode));
                                var combo = parts.join(" + ");
                                if (seen[combo]) continue;
                                seen[combo] = true;
                                var lua = b.dispatcher === "__lua";
                                out.push({
                                    combo: combo,
                                    desc: (b.description && b.description !== "") ? b.description
                                          : (lua ? "Hyprland shortcut" : (b.dispatcher + (b.arg ? " " + b.arg : ""))),
                                    named: !!(b.description && b.description !== ""),
                                    dispatcher: b.dispatcher, arg: b.arg || "", lua: lua,
                                    // what we would re-bind it to on another key: a Lua action is looked up by its
                                    // description (the session keeps them in MACSHELL_ACTIONS)
                                    action: lua ? (b.description ? "MACSHELL_ACTIONS[" + JSON.stringify(b.description) + "]" : "")
                                                : ("hl.dsp." + b.dispatcher + "(" + (b.arg ? '"' + String(b.arg).replace(/"/g, '\\"') + '"' : "") + ")")
                                });
                            }
                            // the ones that say what they do come first
                            out.sort(function (x, y) {
                                if (x.named !== y.named) return x.named ? -1 : 1;
                                return x.desc.localeCompare(y.desc) || x.combo.localeCompare(y.combo);
                            });
                            scPane.hyprAll = out;
                        }
                    }
                }
                readonly property var defs: [
                    { id: "spotlight",  name: I18n.tr("Spotlight"),            def: "SUPER + Space",     cmd: "spotlight toggle" },
                    { id: "clipboard",  name: I18n.tr("Clipboard history"),    def: "SUPER + V",         cmd: "spotlight clipboard" },
                    { id: "emoji",      name: I18n.tr("Emoji picker"),         def: "SUPER + Period",    cmd: "spotlight emoji" },
                    { id: "apps",       name: I18n.tr("All applications"),     def: "SUPER + A",         cmd: "spotlight apps" },
                    { id: "cc",         name: I18n.tr("Control Center"),       def: "SUPER + C",         cmd: "controlcenter toggle" },
                    { id: "notifs",     name: I18n.tr("Notification Center"),  def: "SUPER + N",         cmd: "notifications open" },
                    { id: "clock",      name: "Clock",                def: "SUPER + T",         cmd: "clock open" },
                    { id: "settings",   name: I18n.tr("System Settings"),      def: "SUPER + Comma",     cmd: "settings open" },
                    { id: "shot",       name: I18n.tr("Screenshot a region"),  def: "SUPER + SHIFT + S", cmd: "screenshot region" },
                    { id: "wallpapers", name: I18n.tr("Wallpapers"),           def: "CTRL + ALT + W",    cmd: "wallpapers toggle" },
                    { id: "gaming",     name: I18n.tr("Game Mode"),            def: "SUPER + G",         cmd: "gaming toggle" },
                    { id: "minimize",   name: I18n.tr("Minimize window"),      def: "SUPER + M",         dsp: 'hl.dsp.exec_cmd("qs -c MacShell ipc call window minimize")' },
                    { id: "unminimize", name: I18n.tr("Bring back the last minimized window"), def: "SUPER + SHIFT + M", dsp: 'hl.dsp.exec_cmd("qs -c MacShell ipc call window restorelast")' },
                    { id: "closewin",   name: I18n.tr("Close window"),         def: "SUPER + W",         dsp: "hl.dsp.window.close()" },
                    { id: "zoomwin",    name: I18n.tr("Zoom (fullscreen)"),    def: "SUPER + F",         dsp: "hl.dsp.window.fullscreen_state({ internal = 2, client = 0 })" }
                ]
                // a lone modifier (tapping Super) fires when it is let go
                function relOpt(combo) { return /(SUPER_L|SUPER_R)$/.test(combo) ? ", release = true" : ""; }
                // while listening, Hyprland's shortcuts are paused (an empty submap), or Super + W would close Settings
                // instead of being recorded; back to normal when done, and after 15 s whatever happens
                onCapturingChanged: {
                    Quickshell.execDetached(["hyprctl", "dispatch", capturing !== "" ? 'hl.dsp.submap("macshell-keys")' : 'hl.dsp.submap("reset")']);
                    if (capturing !== "") capSafety.restart(); else capSafety.stop();
                }
                Component.onDestruction: if (capturing !== "") Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.submap("reset")'])
                Timer { id: capSafety; interval: 15000; onTriggered: scPane.capturing = "" }
                property bool soloSuper: false
                function keyOf(id) { var m = root.shortcuts || ({}); var d = scPane.defs; for (var i = 0; i < d.length; i++) if (d[i].id === id) return m[id] !== undefined ? m[id] : d[i].def; return ""; }
                function setKey(id, combo) {
                    var m = {}; for (var k in (root.shortcuts || ({}))) m[k] = root.shortcuts[k];
                    // a key belongs to one shortcut: whichever had it before gives it up (switched off)
                    if (combo !== "") for (var i = 0; i < scPane.defs.length; i++) if (scPane.defs[i].id !== id && scPane.keyOf(scPane.defs[i].id) === combo) m[scPane.defs[i].id] = "";
                    if (combo === "") delete m[id]; else m[id] = combo;
                    root.shortcuts = m;
                    root.saveSettings();
                    scPane.write();
                }
                function write() {
                    var mac = "qs -c MacShell ipc call ";
                    // Hyprland fires EVERY binding made for a key, so the session's default for a shortcut is dropped
                    // first (and the key it moves to cleared), or one key press would run it twice
                    var lines = ["-- written by MacShell (Settings → Keyboard Shortcuts)",
                                 "local function free(k) for _ = 1, 4 do hl.unbind(k) end end"];
                    // every key involved is freed first, then everything is bound: a key one shortcut gives up and
                    // another takes is never unbound again after it has been taken
                    var binds = [];
                    for (var i = 0; i < scPane.defs.length; i++) {
                        var d = scPane.defs[i], k = scPane.keyOf(d.id);
                        lines.push('free("' + d.def + '")');
                        if (k === "") continue;
                        if (k !== d.def) lines.push('free("' + k + '")');
                        var action = d.dsp ? d.dsp : 'hl.dsp.exec_cmd("' + mac + d.cmd + '")';
                        binds.push('hl.bind("' + k + '", ' + action + ', { description = "MacShell: ' + d.name + '"' + scPane.relOpt(k) + ' })');
                    }
                    lines = lines.concat(binds);
                    // a Super tap only exists when a shortcut is recorded as "Tap Super" (older sessions bound one by default)
                    lines.splice(2, 0, 'free("SUPER + SUPER_L")');
                    // shortcuts you moved or switched off in the Hyprland list
                    var hm = root.hyprBinds || ({});
                    for (var h in hm) {
                        lines.push('free("' + h + '")');
                        var v = hm[h];
                        if (v && v.combo && v.action) lines.push('if ' + v.action + ' then free("' + v.combo + '"); hl.bind("' + v.combo + '", ' + v.action + ', { description = ' + JSON.stringify(v.desc || "Hyprland") + scPane.relOpt(v.combo) + ' }) end');
                    }
                    Quickshell.execDetached(["sh", "-c",
                        "mkdir -p \"$HOME/.config/macshell\"; printf '%s\\n' \"$1\" > \"$HOME/.config/macshell/keybinds.lua\"; hyprctl reload >/dev/null 2>&1",
                        "sh", lines.join("\n")]);
                }
                Component.onCompleted: scPane.write()
                SLabel { t: pal; text: I18n.tr("Click a shortcut, then press the keys you want. Esc clears it, and Restore Defaults puts them all back.") }
                SCard {
                    t: pal
                    Repeater {
                        model: scPane.defs
                        delegate: SRow {
                            required property var modelData
                            t: pal
                            title: modelData.name
                            Rectangle {
                                width: 190; height: 26; radius: 7
                                color: scPane.capturing === modelData.id ? root.accent : pal.ctrl
                                border.width: 1; border.color: scPane.capturing === modelData.id ? root.accent : pal.cardBorder
                                Behavior on color { ColorAnimation { duration: 140 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: scPane.capturing === modelData.id ? I18n.tr("Press keys\u2026") : (scPane.keyOf(modelData.id) === "" ? I18n.tr("Off") : scPane.keyOf(modelData.id)).replace(/^SUPER \+ SUPER_[LR]$/, I18n.tr("Tap Super")).replace(/ \+ /g, "  ")
                                    color: scPane.capturing === modelData.id ? "white" : pal.text
                                    font.family: pal.fam; font.pixelSize: 12
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: { scPane.capturing = scPane.capturing === modelData.id ? "" : modelData.id; if (scPane.capturing !== "") keyCatcher.forceActiveFocus(); }
                                }
                            }
                        }
                    }
                }
                Row {
                    spacing: 8
                    SButton { t: pal; text: I18n.tr("Restore Defaults"); onClicked: { root.shortcuts = ({}); root.saveSettings(); scPane.write(); } }
                }

                SLabel { t: pal; header: true; text: I18n.tr("Hyprland") }
                SLabel { t: pal; text: I18n.tr("Every shortcut your compositor has. Click one to move it, or switch it off. Ones written in Lua keep their action, so they can only be switched off here \u2014 move those in your Hyprland config.") }
                Rectangle {
                    width: parent.width; height: 30; radius: 8
                    color: pal.ctrl
                    border.width: 1; border.color: pal.cardBorder
                    Text { x: 10; anchors.verticalCenter: parent.verticalCenter; visible: hyprSearch.text === ""; text: I18n.tr("Search shortcuts"); color: pal.text3; font.family: pal.fam; font.pixelSize: 12 }
                    TextInput {
                        id: hyprSearch
                        x: 10; width: parent.width - 20; anchors.verticalCenter: parent.verticalCenter
                        color: pal.text; font.family: pal.fam; font.pixelSize: 12
                        selectByMouse: true
                        onTextChanged: scPane.filter = text.toLowerCase()
                    }
                }
                SCard {
                    t: pal
                    Repeater {
                        model: scPane.hyprShown
                        delegate: SRow {
                            id: hyprRow
                            required property var modelData
                            t: pal
                            title: modelData.desc
                            subtitle: modelData.lua ? I18n.tr("Defined in your Hyprland config") : (modelData.dispatcher + (modelData.arg ? " " + modelData.arg : ""))
                            Row {
                                spacing: 8
                                Rectangle {
                                    width: 170; height: 26; radius: 7
                                    color: scPane.capturing === "hypr:" + hyprRow.modelData.combo ? root.accent : pal.ctrl
                                    border.width: 1; border.color: scPane.capturing === "hypr:" + hyprRow.modelData.combo ? root.accent : pal.cardBorder
                                    opacity: scPane.isOff(hyprRow.modelData.combo) ? 0.45 : 1
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: scPane.capturing === "hypr:" + hyprRow.modelData.combo ? I18n.tr("Press keys\u2026")
                                              : scPane.comboNow(hyprRow.modelData.combo).replace(/ \+ /g, "  ")
                                        color: scPane.capturing === "hypr:" + hyprRow.modelData.combo ? "white" : pal.text
                                        font.family: pal.fam; font.pixelSize: 12
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: !hyprRow.modelData.lua
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: {
                                            scPane.capturing = scPane.capturing === "hypr:" + hyprRow.modelData.combo ? "" : "hypr:" + hyprRow.modelData.combo;
                                            scPane.pending = hyprRow.modelData;
                                            if (scPane.capturing !== "") keyCatcher.forceActiveFocus();
                                        }
                                    }
                                }
                                SSwitch {
                                    t: pal
                                    checked: !scPane.isOff(hyprRow.modelData.combo)
                                    onToggled: v => scPane.setEnabled(hyprRow.modelData, v)
                                }
                            }
                        }
                    }
                    SRow {
                        t: pal
                        visible: scPane.hyprShown.length === 0
                        title: scPane.hyprAll.length === 0 ? I18n.tr("Reading shortcuts\u2026") : I18n.tr("Nothing matches that search")
                    }
                }
                // catches the key you press while a shortcut is listening
                Item {
                    id: keyCatcher
                    width: 0; height: 0
                    focus: scPane.capturing !== ""
                    Keys.onPressed: event => {
                        if (scPane.capturing === "") return;
                        event.accepted = true;
                        if (event.key === Qt.Key_Escape) {
                            if (scPane.capturing.indexOf("hypr:") !== 0) scPane.setKey(scPane.capturing, "");
                            scPane.capturing = "";
                            return;
                        }
                        if (event.key === Qt.Key_Meta || event.key === Qt.Key_Super_L) { scPane.soloSuper = true; return; }
                        scPane.soloSuper = false;
                        if (event.key === Qt.Key_Control || event.key === Qt.Key_Shift || event.key === Qt.Key_Alt) return;
                        var parts = [];
                        if (event.modifiers & Qt.MetaModifier) parts.push("SUPER");
                        if (event.modifiers & Qt.ControlModifier) parts.push("CTRL");
                        if (event.modifiers & Qt.AltModifier) parts.push("ALT");
                        if (event.modifiers & Qt.ShiftModifier) parts.push("SHIFT");
                        var name = root.keyName(event.key, event.text);
                        if (name === "") return;
                        parts.push(name);
                        if (scPane.capturing.indexOf("hypr:") === 0) {
                            if (scPane.pending) scPane.moveBind(scPane.pending, parts.join(" + "));
                        } else scPane.setKey(scPane.capturing, parts.join(" + "));
                        scPane.capturing = "";
                    }
                    // Super pressed and let go with nothing else: the shortcut is a tap of Super
                    Keys.onReleased: event => {
                        if (scPane.capturing === "" || !scPane.soloSuper) return;
                        if (event.key !== Qt.Key_Meta && event.key !== Qt.Key_Super_L) return;
                        event.accepted = true;
                        scPane.soloSuper = false;
                        if (scPane.capturing.indexOf("hypr:") === 0) { if (scPane.pending) scPane.moveBind(scPane.pending, "SUPER + SUPER_L"); }
                        else scPane.setKey(scPane.capturing, "SUPER + SUPER_L");
                        scPane.capturing = "";
                    }
                }
            }
        }

        // ── Software Update ──
        Component {
            id: paneUpdate
            Column {
                id: updPane
                spacing: 10
                property string status: ""
                property var notes: []
                property string localVer: ""
                property bool checking: false
                Component.onCompleted: { verProc.running = true; updPane.check(); }
                function check() {
                    if (checking) return;
                    checking = true; status = "Checking for updates\u2026";
                    notesProc.running = false; notesProc.running = true;
                }
                // Update, right here: the installer runs in the background and its output scrolls in the card below,
                // instead of a terminal window opening over Settings.
                property bool updating: false
                property string log: ""
                // The installer runs on its own (setsid), not as a child of the shell: the update swaps the shell's files
                // and restarts it at the end, and a child process would die with it half way. Its output goes to a log
                // file that this card follows.
                readonly property string logFile: Quickshell.env("HOME") + "/.cache/macshell/update.log"
                function runUpdate() {
                    if (updating) return;
                    updating = true;
                    log = "Updating MacShell\u2026\n";
                    Quickshell.execDetached(["sh", "-c",
                        "mkdir -p \"$HOME/.cache/macshell\"; : > \"$1\"; "
                        + "setsid -f sh -c '\"$HOME/.local/share/macshell/bin/macshell-update\" update --yes >>\"$0\" 2>&1; echo \"[exit $?]\" >>\"$0\"' \"$1\"",
                        "sh", updPane.logFile]);
                    logPoll.restart();
                }
                FileView {
                    id: logView
                    path: updPane.updating ? updPane.logFile : ""
                    printErrors: false
                    onLoaded: {
                        // plain text only: an older installer still writes terminal colour codes
                        var t = text().replace(/\x1b\[[0-9;]*[A-Za-z]/g, "");
                        updPane.log = "Updating MacShell\u2026\n" + (t.length > 8000 ? t.slice(-8000) : t);
                        var m = /\[exit (\d+)\]/.exec(t);
                        if (m) {
                            updPane.updating = false; logPoll.stop();
                            updPane.log += m[1] === "0" ? "\nDone. MacShell restarts on the new version." : "\nThe update failed: nothing was changed.";
                            updPane.check();
                        }
                    }
                }
                Timer { id: logPoll; interval: 700; repeat: true; onTriggered: logView.reload() }
                // what is installed: the version the installer stamped
                Process {
                    id: verProc
                    command: ["sh", "-c", "v=$(\"$HOME/.local/share/macshell/bin/macshell-update\" status 2>/dev/null | sed -n 's/^installed : //p' | head -1); echo \"${v:-unknown}\""]
                    stdout: StdioCollector { onStreamFinished: updPane.localVer = text.trim() }
                }
                // what is on GitHub: the latest commits on the main branch, used as the release notes
                Process {
                    id: notesProc
                    command: ["sh", "-c", "curl -sL --max-time 15 'https://api.github.com/repos/0-ss/MacShell/commits?sha=main&per_page=12'"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            updPane.checking = false;
                            var o = null;
                            try { o = JSON.parse(text); } catch (e) { o = null; }
                            if (!o || !o.length) { updPane.status = "Couldn't reach GitHub."; return; }
                            var out = [];
                            for (var i = 0; i < o.length; i++) {
                                var m = (o[i].commit && o[i].commit.message) ? o[i].commit.message.split("\n")[0] : "";
                                var d = (o[i].commit && o[i].commit.committer) ? o[i].commit.committer.date.substring(0, 10) : "";
                                if (m !== "" && m.indexOf("Merge ") !== 0) out.push({ sha: o[i].sha.substring(0, 7), msg: m, date: d });
                            }
                            updPane.notes = out;
                            var head = out.length ? out[0].sha : "";
                            updPane.status = updPane.localVer === "unknown" ? "Installed version unknown: updating installs the latest."
                                           : (updPane.localVer.indexOf(head) === 0 ? "MacShell is up to date." : "An update is available.");
                        }
                    }
                }
                SCard {
                    t: pal
                    Item {
                        width: parent.width; height: 92
                        Image {
                            x: 18; anchors.verticalCenter: parent.verticalCenter
                            width: 42; height: 42
                            source: Qt.resolvedUrl(pal.dark ? "apple-logo-white.svg" : "apple-logo-black.svg")
                            sourceSize: Qt.size(96, 96); fillMode: Image.PreserveAspectFit; smooth: true
                        }
                        Column {
                            x: 74; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 74 - 130
                            spacing: 3
                            Text { text: I18n.tr("MacShell \u2014 Tahoe edition"); color: pal.text; font.family: pal.fam; font.pixelSize: 15; font.weight: Font.DemiBold }
                            Text { text: updPane.status; color: pal.text2; font.family: pal.fam; font.pixelSize: 12 }
                            Text { text: updPane.localVer !== "" ? I18n.tr("Installed: ") + updPane.localVer : ""; color: pal.text3; font.family: pal.fam; font.pixelSize: 11 }
                        }
                        SButton {
                            t: pal
                            anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                            text: updPane.checking ? I18n.tr("Checking\u2026") : I18n.tr("Check Now")
                            onClicked: updPane.check()
                        }
                    }
                }
                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Update MacShell")
                        subtitle: I18n.tr("Downloads the latest version and installs it next to the running one, then switches over. Your settings are kept, and the version you had is saved in ~/.local/share/macshell/backups (macshell-update rollback brings it back).")
                        SButton {
                            t: pal
                            text: updPane.updating ? I18n.tr("Updating\u2026") : I18n.tr("Update Now")
                            enabled: !updPane.updating
                            onClicked: updPane.runUpdate()
                        }
                    }
                    Text {
                        visible: updPane.log !== ""
                        x: 14; width: parent.width - 28; topPadding: 4; bottomPadding: 12
                        text: updPane.log.split("\n").slice(-12).join("\n")
                        wrapMode: Text.WrapAnywhere
                        color: pal.text2; font.family: pal.fam; font.pixelSize: 11
                    }
                }
                SLabel { t: pal; header: true; text: I18n.tr("What's New") }
                SCard {
                    t: pal
                    Repeater {
                        model: updPane.notes
                        delegate: Item {
                            required property var modelData
                            width: parent.width; height: Math.max(42, noteTxt.implicitHeight + 20)
                            Rectangle { visible: y > 0.5; x: 14; width: parent.width - 14; height: 1; color: pal.sep }
                            Text {
                                id: noteTxt
                                x: 14; y: 10; width: parent.width - 100
                                text: modelData.msg; wrapMode: Text.WordWrap
                                color: pal.text; font.family: pal.fam; font.pixelSize: 12.5 > 0 ? 12 : 12
                            }
                            Text {
                                anchors.right: parent.right; anchors.rightMargin: 14; y: 11
                                text: modelData.date
                                color: pal.text3; font.family: pal.fam; font.pixelSize: 11
                            }
                        }
                    }
                    Text {
                        visible: updPane.notes.length === 0
                        x: 14; topPadding: 14; bottomPadding: 14
                        text: updPane.checking ? I18n.tr("Loading\u2026") : I18n.tr("No notes.")
                        color: pal.text3; font.family: pal.fam; font.pixelSize: 12
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
                SLabel { t: pal; text: "Clock"; font.weight: Font.DemiBold; topPadding: 6 }
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
                                    { id: "glass",   name: I18n.tr("Glass"),   fam: "Roboto Flex",        w: 680, tall: true,  liquid: false },
                                    { id: "classic", name: I18n.tr("Classic"), fam: fNunito.status === FontLoader.Ready ? fNunito.name : "Nunito",             w: 640, tall: false, liquid: false },
                                    { id: "serif",   name: I18n.tr("Serif"),   fam: fSerif.status === FontLoader.Ready ? fSerif.name : "Noto Serif Display", w: 560, tall: false, liquid: false },
                                    { id: "liquid",  name: I18n.tr("Liquid"),  fam: "Roboto Flex",        w: 560, tall: true,  liquid: true },
                                    { id: "thin",    name: I18n.tr("Thin"),    fam: fNunito.status === FontLoader.Ready ? fNunito.name : "Nunito",             w: 220, tall: false, liquid: true }
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
                                            font.family: tile.modelData.fam; font.pixelSize: tile.modelData.tall ? 40 : 30
                                            font.weight: Math.max(100, Math.min(900, tile.modelData.w))
                                            font.variableAxes: tile.modelData.fam === "Roboto Flex"
                                                ? ({ "wght": tile.modelData.w, "wdth": tile.modelData.tall ? 40 : 100, "YTFI": tile.modelData.tall ? 788 : 712, "opsz": 144 })
                                                : ({ "wght": tile.modelData.w })
                                            color: tile.modelData.liquid ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.78)
                                            style: tile.modelData.liquid ? Text.Outline : Text.Normal
                                            styleColor: Qt.rgba(1, 1, 1, 0.85)
                                        }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.bar) root.bar.applyLockClockPreset(tile.modelData.id) }
                                    }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.modelData.name; color: tile.sel ? pal.accent : pal.text; font.family: pal.fam; font.pixelSize: 12; font.weight: tile.sel ? Font.DemiBold : Font.Normal }
                                }
                            }
                        }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Font")
                        SPopUp {
                            t: pal
                            model: ["Condensed", "Rounded", "Serif", "Default"]
                            readonly property var ids: ["condensed", "rounded", "serif", "inter"]
                            current: Math.max(0, ids.indexOf(root.bar ? root.bar.lockClockFont : "condensed"))
                            onPicked: i => { if (root.bar) { root.bar.lockClockFont = ids[i]; root.bar.lockClockStyle = "custom"; } }
                        }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Weight")
                        SSlider {
                            t: pal; width: 220; from: 100; to: 1000; stepSize: 10
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
                            t: pal; width: 220; from: 0; to: 1
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
                        t: pal; title: I18n.tr("Tall digits")
                        subtitle: I18n.tr("Stretches the Condensed font to fill the space, like iOS 26")
                        SSwitch {
                            t: pal
                            enabled: root.bar && root.bar.lockClockFont === "condensed"
                            checked: root.bar ? root.bar.lockClockTall : true
                            onToggled: v => { if (root.bar) { root.bar.lockClockTall = v; root.bar.lockClockStyle = "custom"; } }
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
                            var cfg = JSON.stringify({ f: b.lockClockFont, w: b.lockClockWeight, m: b.lockClockMaterial, i: b.lockClockIntensity, c: b.lockClockTint, t: b.lockClockTall, d: b.lockClockDate });
                            Quickshell.execDetached(["sh", "-c", "MACLOCK_PREVIEW=1 MACLOCK_CLOCK=\"$1\" timeout 6 qs -c MacLock >/dev/null 2>&1", "sh", cfg]);
                        }
                    }
                    SButton { t: pal; text: "Lock Screen Now"; onClicked: { root.hideWin(prefsWindow); Quickshell.execDetached(["loginctl", "lock-session"]); } }
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
                    Text { anchors.top: upic.bottom; anchors.topMargin: 8; anchors.horizontalCenter: parent.horizontalCenter; text: root.userName; color: pal.text; font.family: pal.fam; font.pixelSize: 17; font.weight: Font.DemiBold }
                }
                SCard {
                    t: pal
                    SRow { t: pal; title: I18n.tr("Full name"); Text { text: root.userName; color: pal.text2; font.family: pal.fam; font.pixelSize: 13 } }
                    SRow { t: pal; title: I18n.tr("Account name"); Text { text: Quickshell.env(I18n.tr("USER")); color: pal.text2; font.family: pal.fam; font.pixelSize: 13 } }
                    SRow { t: pal; title: I18n.tr("Home folder"); Text { text: Quickshell.env(I18n.tr("HOME")); color: pal.text2; font.family: pal.fam; font.pixelSize: 13 } }
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
                        SSlider { t: pal; leftLabel: I18n.tr("Slow"); rightLabel: I18n.tr("Fast"); from: 10; to: 80; value: root.bar ? root.bar.kbRepeatRate : 35; onMoved: v => { if (root.bar) root.bar.kbRepeatRate = Math.round(v); } }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Delay until repeat")
                        SSlider { t: pal; leftLabel: I18n.tr("Long"); rightLabel: I18n.tr("Short"); from: 0; to: 1; value: root.bar ? 1 - (root.bar.kbRepeatDelay - 150) / 650 : 0.6; onMoved: v => { if (root.bar) root.bar.kbRepeatDelay = Math.round(150 + (1 - v) * 650); } }
                    }
                }
                SLabel { t: pal; text: I18n.tr("Layout: ") + "us" + I18n.tr(". Changes apply right away.") }
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
                        t: pal; title: I18n.tr("Pointer")
                        subtitle: I18n.tr("Apple's macOS pointer: softly rounded, with a gentle shadow")
                        SSegmented {
                            t: pal
                            model: ["Black", "White"]
                            segWidth: 72
                            current: root.cursorTheme === "macOS-White" ? 1 : 0
                            onPicked: i => root.cursorTheme = ["macOS", "macOS-White"][i]
                        }
                    }
                    SRow {
                        t: pal; title: I18n.tr("Pointer size")
                        SSegmented {
                            t: pal
                            model: ["Normal", "Large", "Larger"]
                            segWidth: 72
                            current: root.cursorSize >= 48 ? 2 : (root.cursorSize >= 32 ? 1 : 0)
                            onPicked: i => root.cursorSize = [24, 32, 48][i]
                        }
                    }
                }
                SCard {
                    t: pal
                    SRow {
                        t: pal; title: I18n.tr("Tracking speed")
                        SSlider { t: pal; leftLabel: I18n.tr("Slow"); rightLabel: I18n.tr("Fast"); from: -1; to: 1; value: root.bar ? root.bar.mouseSens : 0; onMoved: v => { if (root.bar) root.bar.mouseSens = v; } }
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
                        SSlider { t: pal; leftLabel: I18n.tr("Slow"); rightLabel: I18n.tr("Fast"); from: 0.2; to: 2; value: root.bar ? root.bar.tpScroll : 0.7; onMoved: v => { if (root.bar) root.bar.tpScroll = v; } }
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
                property int filter: 0          // 0 all, 1 pictures, 2 animated
                readonly property var files: root.bar ? root.bar.wpFiles : []
                readonly property var shown: {
                    var out = [], f = files;
                    for (var i = 0; i < f.length; i++)
                        if (filter === 0 || (filter === 1 && !f[i].video) || (filter === 2 && f[i].video)) out.push(f[i]);
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
                                color: pal.text; font.family: pal.fam; font.pixelSize: 15; font.weight: Font.DemiBold
                            }
                            Text {
                                width: parent.width
                                text: wpPane.curVideo !== "" ? I18n.tr("Animated wallpaper") : I18n.tr("Picture")
                                color: pal.text2; font.family: pal.fam; font.pixelSize: 12
                            }
                            Text {
                                width: parent.width; wrapMode: Text.WordWrap
                                visible: wpPane.curVideo !== ""
                                text: I18n.tr("Plays on every display and pauses behind fullscreen windows. The Liquid Glass and the lock screen use it too.")
                                color: pal.text3; font.family: pal.fam; font.pixelSize: 11
                            }
                            Row {
                                spacing: 8
                                topPadding: 4
                                SButton { t: pal; text: I18n.tr("Open Folder"); onClicked: { if (root.hub && root.hub.openFolder) root.hub.openFolder(root.bar ? root.bar.wpDirEff : ""); } }
                                SButton { t: pal; text: I18n.tr("Refresh"); onClicked: if (root.bar) root.bar.wpRefresh() }
                            }
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
                        model: ["All", "Pictures", "Animated"]
                        segWidth: 80
                        current: wpPane.filter
                        onPicked: i => wpPane.filter = i
                    }
                }

                Flow {
                    id: wpFlow
                    width: parent.width
                    spacing: 10
                    readonly property real tileW: Math.floor((width - 2 * spacing) / 3)
                    Repeater {
                        model: wpPane.shown
                        delegate: Item {
                            id: wt
                            required property var modelData
                            width: wpFlow.tileW
                            height: Math.round(width * 0.625) + 22
                            readonly property bool cur: modelData.video ? wpPane.curVideo === modelData.path
                                                                        : (wpPane.curVideo === "" && wpPane.curStill === modelData.path)
                            Item {
                                id: wtBox
                                width: parent.width; height: parent.height - 22
                                scale: wtMa.pressed ? 0.96 : (wtMa.containsMouse ? 1.025 : 1)
                                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
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
                                        sourceSize.width: 360
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
                                            color: "white"; font.family: pal.fam; font.pixelSize: 9; font.weight: Font.DemiBold
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
                            }
                            Text {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideMiddle
                                text: wt.modelData.name
                                color: wt.cur ? pal.text : pal.text2
                                font.family: pal.fam; font.pixelSize: 11
                            }
                        }
                    }
                }
                SLabel {
                    t: pal
                    visible: wpPane.shown.length === 0
                    text: wpPane.filter === 2 ? I18n.tr("No animated wallpapers yet. Drop .mp4 / .webm videos into ") + (root.bar ? root.bar.wpDirEff : "~/Pictures/Wallpapers") + "."
                                              : "Nothing here yet."
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
                            font.family: pal.fam
                            font.pixelSize: 21
                            font.weight: Font.DemiBold
                        }
                        Text {
                            y: 138
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: I18n.tr("Version 2 \u2022 Hyprland \u2022 Quickshell")
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
                        title: I18n.tr("Configuration")
                        Text {
                            text: "~/.config/macdock"
                            color: pal.text2
                            font.family: pal.fam
                            font.pixelSize: 13
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Open configuration folder")
                        SButton {
                            t: pal
                            text: I18n.tr("Open")
                            onClicked: { if (root.hub && root.hub.openFolder) root.hub.openFolder(root.configDir); else Quickshell.execDetached(["xdg-open", root.configDir]); }
                        }
                    }
                }

                SLabel { t: pal; header: true; text: I18n.tr("System") }
                SCard {
                    t: pal
                    Component.onCompleted: sysProc.running = true
                    Process {
                        id: sysProc
                        command: ["sh", "-c",
                            ". /etc/os-release 2>/dev/null; printf '%s\\n' \"${PRETTY_NAME:-Linux}\"; "
                            + "uname -r; "
                            + "LC_ALL=C lscpu 2>/dev/null | sed -n 's/^Model name:[[:space:]]*//p' | head -1; "
                            + "awk '/MemTotal/ {printf \"%.0f GB\\n\", $2/1048576}' /proc/meminfo; "
                            + "(lspci 2>/dev/null | sed -n 's/.*VGA compatible controller: //p' | head -2 | paste -sd ', ') ; echo; "
                            + "hyprctl version 2>/dev/null | head -1 | sed 's/^Hyprland //; s/ built.*//'; "
                            + "qs --version 2>/dev/null | head -1"]
                        stdout: StdioCollector {
                            onStreamFinished: {
                                var l = text.split("\n");
                                root.sysInfo = { os: (l[0] || "").trim(), kernel: (l[1] || "").trim(), cpu: (l[2] || "").trim(),
                                                 mem: (l[3] || "").trim(), gpu: (l[4] || "").trim(), hypr: (l[5] || "").trim(), qs: (l[6] || "").trim() };
                            }
                        }
                    }
                    Repeater {
                        model: [["Operating System", root.sysInfo.os], ["Kernel", root.sysInfo.kernel], ["Processor", root.sysInfo.cpu],
                                ["Memory", root.sysInfo.mem], ["Graphics", root.sysInfo.gpu], ["Compositor", root.sysInfo.hypr ? "Hyprland " + root.sysInfo.hypr : ""],
                                ["Shell", root.sysInfo.qs]]
                        delegate: SRow {
                            required property var modelData
                            t: pal
                            visible: String(modelData[1] || "") !== ""
                            title: modelData[0]
                            Text {
                                width: 330; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
                                text: modelData[1] || ""
                                color: pal.text2; font.family: pal.fam; font.pixelSize: 13
                            }
                        }
                    }
                }

                SCard {
                    t: pal
                    SRow {
                        t: pal
                        title: I18n.tr("Logs")
                        subtitle: I18n.tr("Everything the shell reported since it started (~/.cache/macshell/shell.log). Copy it into a bug report when something misbehaves.")
                        Row {
                            spacing: 8
                            SButton {
                                t: pal; text: I18n.tr("Open")
                                onClicked: Quickshell.execDetached(["sh", "-c", "f=\"$HOME/.cache/macshell/shell.log\"; [ -f \"$f\" ] && xdg-open \"$f\""])
                            }
                            SButton {
                                t: pal; text: copiedT.running ? I18n.tr("Copied") : I18n.tr("Copy")
                                onClicked: {
                                    Quickshell.execDetached(["sh", "-c",
                                        "d=\"$HOME/.cache/macshell\"; { echo '## MacShell bug report'; cat \"$HOME/.local/share/macshell/version\" 2>/dev/null; uname -sr; hyprctl version 2>/dev/null | head -1; qs --version 2>/dev/null | head -1; "
                                        + "echo; echo '## this run'; tail -n 300 \"$d/shell.log\" 2>/dev/null; echo; echo '## previous run'; tail -n 120 \"$d/shell.prev.log\" 2>/dev/null; } | wl-copy"]);
                                    copiedT.restart();
                                }
                                Timer { id: copiedT; interval: 1600 }
                            }
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Restart the shell")
                        subtitle: I18n.tr("Reloads MacShell. Your settings, pinned apps and widgets are kept.")
                        SButton {
                            t: pal
                            text: I18n.tr("Restart")
                            onClicked: {
                                root.hideWin(prefsWindow);
                                // the autostart loop brings it straight back; -x -f never matched the real command line
                                Quickshell.execDetached(["sh", "-c", "sleep 0.3; qs kill -c MacShell"]);
                            }
                        }
                    }
                    SRow {
                        t: pal
                        title: I18n.tr("Install dependencies")
                        subtitle: I18n.tr("Shows what MacShell needs and what you already have, then installs the rest. Nothing you have is replaced or partially upgraded.")
                        SButton {
                            t: pal
                            text: I18n.tr("Open\u2026")
                            onClicked: { if (root.hub && root.hub.installer) { root.hideWin(prefsWindow); root.hub.installer.open(); } }
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
                            { img: "assets/credits/0-ss.jpg", name: I18n.tr("Rickky"), gh: "0-ss",
                              role: "Owner — the menu bar, the Dock, the Liquid Glass the widgets and more... The one who actually knew what he was doing" },
                            { img: "assets/credits/vsoultann.png", name: I18n.tr("vSuol"), gh: "vsoultann",
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
                                Text { text: cr.modelData.name; color: pal.text; font.family: pal.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
                                Text { width: parent.width; text: cr.modelData.role; wrapMode: Text.WordWrap; color: pal.text2; font.family: pal.fam; font.pixelSize: 11 }
                            }
                            Text {
                                anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                                text: "@" + cr.modelData.gh
                                color: pal.accent; font.family: pal.fam; font.pixelSize: 12
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
                    color: pal.text3; font.family: pal.fam; font.pixelSize: 11
                }

                // (keep scrolling…)
                Item { width: 1; height: 900 }

                // ── AppleCare+ — nobody asked. The button does something. ──
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
                            color: pal.text; font.family: pal.fam; font.pixelSize: 17; font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter; y: 90
                            width: parent.width - 60; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                            text: I18n.tr("Unlimited repairs for accidental damage, 24/7 priority access to Apple experts, and battery service coverage. Same price as for a MacBook Pro.")
                            color: pal.text2; font.family: pal.fam; font.pixelSize: 12
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter; y: 136
                            text: "$279.00 for 3 years or $99.99/yr."
                            color: pal.text; font.family: pal.fam; font.pixelSize: 13; font.weight: Font.Medium
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter; y: 166
                            width: 150; height: 32; radius: 16
                            color: careMa.pressed ? Qt.darker(pal.accent, 1.15) : pal.accent
                            scale: careMa.pressed ? 0.96 : 1
                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }
                            Text { anchors.centerIn: parent; text: I18n.tr("Add AppleCare+"); color: "white"; font.family: pal.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
                            MouseArea {
                                id: careMa
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Quickshell.execDetached(["xdg-open", "https://www.youtube.com/watch?v=dQw4w9WgXcQ"]);
                                    if (root.bar) root.bar.playSound("pop", 0.7);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // With a lot of apps open the Dock would run off the screen, so the icons shrink to fit, the way macOS does.
    // dockRoom is the narrowest screen the Dock shows on, less a margin at each end.
    readonly property real dockRoom: {
        var ss = Quickshell.screens, m = 0;
        for (var i = 0; i < ss.length; i++) {
            if (monitor !== "" && ss[i].name !== monitor) continue;
            var w = ss[i].width - 2 * (hPad + 24);
            if (m === 0 || w < m) m = w;
        }
        return m;
    }
    readonly property real rawW: Math.max(0, appCount * (iconSizePref + spacing) + sepCount * (sepWidth + spacing) - spacing)
    property real fitScale: (dockRoom > 120 && rawW > dockRoom) ? Math.max(0.42, dockRoom / rawW) : 1
    Behavior on fitScale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    readonly property int iconSize: Math.max(20, Math.round(iconSizePref * fitScale))

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
    Timer { id: floatOnce; interval: 1200; onTriggered: root.applyWindowsFloat() }
    property var shortcuts: ({})
    property var hyprBinds: ({})       // Hyprland shortcuts moved or switched off from Settings            // shortcut id → key combo, empty = the default
    // Qt key code → the name Hyprland uses
    function keyName(k, text) {
        if (k >= Qt.Key_A && k <= Qt.Key_Z) return String.fromCharCode(65 + (k - Qt.Key_A));
        if (k >= Qt.Key_0 && k <= Qt.Key_9) return String.fromCharCode(48 + (k - Qt.Key_0));
        if (k >= Qt.Key_F1 && k <= Qt.Key_F12) return "F" + (1 + k - Qt.Key_F1);
        var m = {};
        m[Qt.Key_Space] = "Space"; m[Qt.Key_Tab] = "Tab"; m[Qt.Key_Return] = "Return"; m[Qt.Key_Enter] = "Return";
        m[Qt.Key_Period] = "Period"; m[Qt.Key_Comma] = "Comma"; m[Qt.Key_Slash] = "Slash"; m[Qt.Key_Backslash] = "Backslash";
        m[Qt.Key_Semicolon] = "Semicolon"; m[Qt.Key_Apostrophe] = "Apostrophe"; m[Qt.Key_Minus] = "Minus"; m[Qt.Key_Equal] = "Equal";
        m[Qt.Key_BracketLeft] = "BracketLeft"; m[Qt.Key_BracketRight] = "BracketRight"; m[Qt.Key_Backspace] = "BackSpace";
        m[Qt.Key_Delete] = "Delete"; m[Qt.Key_Home] = "Home"; m[Qt.Key_End] = "End"; m[Qt.Key_PageUp] = "Prior"; m[Qt.Key_PageDown] = "Next";
        m[Qt.Key_Left] = "Left"; m[Qt.Key_Right] = "Right"; m[Qt.Key_Up] = "Up"; m[Qt.Key_Down] = "Down"; m[Qt.Key_Grave] = "Grave";
        return m[k] !== undefined ? m[k] : "";
    }
    property var sysInfo: ({ os: "", kernel: "", cpu: "", mem: "", gpu: "", hypr: "", qs: "" })
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
        dockEnabled = true; windowsFloat = true;
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
        iconSizePref = 52; magnification = 1.7; magnificationEnabled = true;
        spacing = 6; margin = 6; cornerRadius = 18;
        darkMode = true; glassOpacity = 0.42; glassBlur = 5; glassLiquid = 1.0; dockStyle = "liquid"; accent = "#0a84ff"; fontFamily = "Open Runde";
        hideMode = "smart"; hideDelay = 450; monitor = "";
        showTrash = true; showLabels = true; showIndicators = true; bounceOnLaunch = true; showThumbs = true; windowCapture = true;
    }

    // ── settings persistence (~/.config/macdock/settings.json) ──
    readonly property string settingsSig: [dockEnabled, windowsFloat, minimizeEffect, minimizeSecs, cursorTheme, cursorSize, iconStyle, iconTint, hotspotSsid, hotspotPass, hotspotBand, iconSizePref, magnification, magnificationEnabled, spacing, margin,
        cornerRadius, darkMode, glassOpacity, glassBlur, glassLiquid, dockStyle, wallpaperPath, String(accent), fontFamily, hideMode, hideDelay, monitor,
        showTrash, showLabels, showIndicators, bounceOnLaunch, showThumbs, windowCapture].join("|")
    property bool settingsReady: false
    onSettingsSigChanged: if (settingsReady) saveTimer.restart()
    // a setting changed, not an app closing: rebuild without playing the "closed" animation
    property bool skipLeave: false
    Timer { id: skipLeaveOff; interval: 400; onTriggered: root.skipLeave = false }
    function rebuildNow() { skipLeave = true; leaving = ({}); rebuild(); skipLeaveOff.restart(); }
    onShowTrashChanged: { rebuildNow(); if (showTrash) trashCheck(); }
    onShowThumbsChanged: rebuildNow()
    onWindowCaptureChanged: rebuildNow()

    function saveSettings() {
        var o = {
            dockEnabled: dockEnabled, windowsFloat: windowsFloat, shortcuts: shortcuts, hyprBinds: hyprBinds, pinnedFolders: pinnedFolders, desktopIcons: desktopIcons, iconMode: iconMode, minimizeEffect: minimizeEffect, minimizeSecs: minimizeSecs, cursorTheme: cursorTheme, cursorSize: cursorSize, iconStyle: iconStyle, iconTint: iconTint, hotspotSsid: hotspotSsid, hotspotPass: hotspotPass, hotspotBand: hotspotBand, iconSize: iconSizePref, magnification: magnification, magnificationEnabled: magnificationEnabled,
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
        var keys = ["dockEnabled", "windowsFloat", "shortcuts", "hyprBinds", "pinnedFolders", "desktopIcons", "iconMode", "magnification", "magnificationEnabled", "spacing", "margin", "cornerRadius",
                    "darkMode", "glassOpacity", "dockStyle", "wallpaperPath", "glassDebug", "glassRim", "glassGrain", "glassLiquid", "glassBlur", "accent", "fontFamily", "hideMode", "hideDelay", "monitor",
                    "showTrash", "showLabels", "showIndicators", "bounceOnLaunch", "showThumbs", "windowCapture",
                    "hotspotSsid", "hotspotPass", "hotspotBand", "minimizeEffect", "minimizeSecs", "iconStyle", "iconTint", "cursorTheme", "cursorSize"];
        for (var i = 0; i < keys.length; i++) {
            if (o[keys[i]] === undefined) continue;
            try { root[keys[i]] = o[keys[i]]; } catch (err) { }
        }
        if (o.iconSize !== undefined) root.iconSizePref = o.iconSize;     // saved under its old name
    }

    FileView {
        id: settingsStore
        path: root.configDir + "/settings.json"
        printErrors: false
        onLoaded: {
            try { root.applySettings(JSON.parse(text())); } catch (err) { }
            root.settingsReady = true; root.iconLook = root.iconLookWanted;
            floatOnce.restart();            // make sure the Lua file matches the setting at least once per session
            // always built: the widgets use this shader whatever the Dock style is
            root.startGlass();
        }
        onLoadFailed: { root.settingsReady = true; floatOnce.restart(); root.startGlass(); }
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

    readonly property url folderIcon: Qt.resolvedUrl("folder.svg")
    // Settings → Icons → Dark: real dark icons, not a filter — the dark set MacOS-Like (github.com/Scrimas/MacOS-Like,
    // GPL-3.0) builds from MacTahoe (dark Finder, dark glass instead of white tiles), built by ./install.sh --icons
    // into ~/.local/share/macshell/icons-build. Icons it has no dark version of stay as they are.
    readonly property string darkIconDir: Quickshell.env("HOME") + "/.local/share/macshell/icons-build/icons/MacOS-Like-Dark/apps/scalable"
    property var darkIcons: ({})
    Process {
        running: true
        command: ["sh", "-c", "ls \"$1\" 2>/dev/null | sed -n 's/\\.svg$//p'", "sh", root.darkIconDir]
        stdout: StdioCollector {
            onStreamFinished: {
                var m = {}, l = text.split("\n");
                for (var i = 0; i < l.length; i++) if (l[i] !== "") m[l[i]] = true;
                root.darkIcons = m;
            }
        }
    }
    function iconSrc(icon) {
        if (icon === "folder") return folderIcon;
        if (!icon) return Quickshell.iconPath("application-x-executable");
        if (icon.charAt(0) === "/") return "file://" + icon;
        if (iconLook === "dark" && darkIcons[icon]) return "file://" + darkIconDir + "/" + icon + ".svg";
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
        // Wrapped so it cannot outlive the shell: a hard restart orphaned the watcher and left one
        // inotifywait running for ever, one more on every restart.
        command: ["sh", "-c",
                  "p=$PPID; inotifywait -m -q -e create -e delete -e moved_to -e moved_from \"$1\" & w=$!; "
                  + "while kill -0 \"$p\" 2>/dev/null; do sleep 5; done; kill \"$w\" 2>/dev/null",
                  "sh", root.trashDir]
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

    // MacShell's own windows all have the app id "org.quickshell", so the title says which app a window
    // belongs to. Every one of them is listed here: the ones that weren't showed up as a bare gear.
    readonly property var ownApps: ({
        "Clock": "macshell-clock", "macshell Settings": "macshell-settings",
        "Install Dependencies": "macshell-installer"
    })
    // windows that aren't apps: they never get a Dock icon (or an Alt+Tab entry), e.g. Flameshot's capture overlay
    readonly property var hiddenApps: ({ "flameshot": true })
    function appOf(tl) {
        if (hiddenApps[String(tl.appId).toLowerCase()]) return "";
        if (tl.appId !== "org.quickshell") return tl.appId;
        var a = ownApps[tl.title];
        return a ? a : tl.appId;
    }
    function windowsFor(key) {
        var out = [];
        var tls = ToplevelManager.toplevels.values;
        for (var i = 0; i < tls.length; i++) {
            if (tls[i].appId && keyOf(appOf(tls[i])) === key) out.push(tls[i]);
        }
        return out;
    }

    // the Hyprland side of a Wayland window, for minimising from the Dock
    function hyprTl(tl) { return root.hub && root.hub.hyprWin ? root.hub.hyprWin(function (t) { return t.wayland === tl; }) : null; }
    function tlMinimized(tl) { var h = hyprTl(tl); return h && root.hub.isMinimized ? root.hub.isMinimized(h) : false; }
    function minimizeTl(tl) {
        var h = hyprTl(tl);
        if (!h || !root.hub || !root.hub.minimizeHyprWin) return false;
        root.hub.minimizeHyprWin(h);
        return true;
    }
    function activate(item, forceNew) {
        // a minimised window comes back out of the Dock with the minimise effect played in reverse
        if (item.kind === "win") {
            if (!item.tl) return;
            if (root.hub && root.hub.restoreIfMinimized && root.hub.restoreIfMinimized(item.tl)) return;
            // the window in front: clicking its thumbnail puts it away, like clicking it in a taskbar
            if (item.tl.activated && root.minimizeTl(item.tl)) return;
            item.tl.activate();
            return;
        }
        if (item.kind === "folder") { root.loadStack(item.path); return; }
        if (item.special === "trash") {
            // Finder, at the Trash (Dolphin's trash:/ shows what is in it and can put things back)
            if (root.hub && root.hub.openFolder) { root.hub.openFolder("trash:/"); return; }
            Quickshell.execDetached(["xdg-open", "trash:/"]);
            return;
        }
        var wins = windowsFor(item.key);
        if (wins.length > 0 && !forceNew) {
            // the app in front: its window goes down into the icon (Magic Lamp / Fade / Instant, Settings → Desktop & Dock)
            for (var i = 0; i < wins.length; i++)
                if (wins[i].activated && !root.tlMinimized(wins[i]) && root.minimizeTl(wins[i])) return;
            // an app in the background: bring its window forward
            for (var j = wins.length - 1; j >= 0; j--)
                if (!root.tlMinimized(wins[j])) { wins[j].activate(); return; }
            // everything minimised: the last one comes back out
            if (root.hub && root.hub.restoreIfMinimized) root.hub.restoreIfMinimized(wins[wins.length - 1]);
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

    Process {
        id: stackProc
        stdout: StdioCollector {
            onStreamFinished: {
                var out = [], ls = text.split("\n");
                for (var i = 0; i < ls.length; i++) {
                    var c = ls[i].split("\t");
                    if (c.length < 2) continue;
                    var e = c[1].toLowerCase().split(".").pop();
                    out.push({ name: c[1], path: root.stackPath + "/" + c[1], isDir: c[0] === "d",
                               isImage: ["png", "jpg", "jpeg", "webp", "gif", "bmp", "avif"].indexOf(e) >= 0 });
                }
                root.stackFiles = out;
            }
        }
    }
    function menuFor(item) {
        var m = [];
        if (item.kind === "folder") {
            m.push({ kind: "item", label: I18n.tr("Open in Finder"), run: function () { root.activate(item, false); } });
            m.push({ kind: "item", label: "Open in Finder", run: function () { if (root.hub && root.hub.openFolder) root.hub.openFolder(item.path); else Quickshell.execDetached(["xdg-open", item.path]); } });
            m.push({ kind: "sep" });
            m.push({ kind: "item", label: I18n.tr("Remove from Dock"), run: function () { root.unpinFolder(item.path); } });
            return m;
        }
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
                        name: own ? I18n.tr("MacShell") : (e2 ? e2.name : extras[x].appId),
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
                                name: own3 ? (tl.title || I18n.tr("MacShell")) : (e3 ? e3.name : tl.appId),
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
        for (var pf = 0; pf < pinnedFolders.length; pf++) {
            var fp = pinnedFolders[pf];
            list.push({ kind: "folder", key: "folder:" + fp, name: fp.split("/").pop(), icon: "folder",
                        path: fp, entry: null, running: false, pinned: true });
        }
        if (showTrash) {
            list.push({ kind: "app", key: "__trash", name: I18n.tr("Trash"), icon: "user-trash",
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
                if (skipLeave) continue;
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

    // wallpaper the glass refracts: MacShell's own (wallpaperPath), else whatever awww / swww / hyprpaper shows
    readonly property var wallpaperMap: hub ? hub.wallpaperMap : ({})
    Binding { target: root.hub; property: "dockWantsWallpaper"; value: root.liquidActive }
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

    function computeBusy(clients) {
        var busy = {};
        for (var m = 0; m < monData.length; m++) {
            var mon = monData[m];
            var ids = [mon.activeWorkspace ? mon.activeWorkspace.id : -999];
            if (mon.specialWorkspace && mon.specialWorkspace.id !== 0) ids.push(mon.specialWorkspace.id);
            for (var c = 0; c < clients.length; c++) {
                var cl = clients[c];
                if (!cl.mapped || cl.hidden) continue;
                // Windows open floating here, so "floating" alone can't mean "out of the way": a floating
                // window that has been maximised (Super+D) or made fullscreen needs the whole screen too.
                if (cl.floating && !(cl.fullscreen > 0)) continue;
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
                if (Array.isArray(a)) {
                    root.pinned = a; root.rebuild();
                }
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
                Component.onCompleted: root.uiByScreen[win.modelData.name] = ui

                property real mx: 0
                Behavior on mx { NumberAnimation { duration: 55; easing.type: Easing.OutQuad } }
                property bool revealed: false
                property var menuItem: null
                property var menuModel: []
                property string armed: ""            // label of a confirm-type entry that was clicked once (e.g. Empty Trash)
                onMenuItemChanged: armed = ""
                property real menuCx: 0
                Connections {
                    target: root
                    function onStackRequest(path) {
                        if (!path || path === "") { ui.stackItem = null; return; }
                        for (var i = 0; i < root.items.length; i++) {
                            if (root.items[i].kind === "folder" && root.items[i].path === path) {
                                ui.stackCx = ui.naturalCenter(i) || ui.width / 2;
                                ui.stackItem = root.items[i];
                                root.loadStack(path);
                                return;
                            }
                        }
                    }
                }
                property var stackItem: null      // the pinned folder whose fan is open
                property real stackCx: 0
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
                    // Dragging a window out of the Dock while you are somewhere else: bring it to THIS monitor first
                    // (a workspace lives on one monitor, so moving it to this workspace alone left it on the other screen),
                    // then onto this workspace.
                    if (mon && mon.name) Hyprland.dispatch('hl.dsp.window.move({ monitor = "' + mon.name + '", ' + sel + ' })');
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
                        Image {
                            anchors.fill: parent
                            visible: status === Image.Ready
                            onStatusChanged: if (status === Image.Error) console.log("[macdock-glass] wallpaper could not be loaded:", source)
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
                                // Only the windows that actually reach the Dock (+ refraction margin) are captured.
                                // Real-time keeps them live even while the Dock is tucked away, so a revealed Dock never
                                // starts from the bare wallpaper — but a window nowhere near the Dock is never copied:
                                // capturing every window all the time cost about a fifth of a core.
                                readonly property bool nearNow: (root.glassRT || !ui.tucked)
                                    && x < dock.x + dock.width + 48 && x + width > dock.x - 48
                                    && y < dock.y + bd.height - ui.height + dock.height + 48
                                    && y + height > dock.y + bd.height - ui.height - 48
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
                                        // 15 fps, not the window's own rate: the glass only shows a blurred, refracted copy, and
                                        // copying every frame of a busy window (a terminal, a video) cost several % CPU
                                        live: false
                                        readonly property bool wantFrames: !root.glassHold && (root.glassRT || !ui.tucked)
                                        // At the main display's refresh rate while the Dock is on screen — that is what makes the
                                        // refraction move with the window. Tucked away there is nothing to refract, so it idles
                                        // at 2 fps instead of burning a core on captures nobody sees.
                                        readonly property bool onScreen: !ui.tucked || hh.hovered || ui.menuOpen || ui.stackItem !== null
                                        Timer {
                                            // the main display's refresh rate while you are at the Dock, a calmer 15 fps when
                                            // it is just sitting there, and 2 fps while it is tucked away
                                            // while the machine is busy building or installing something, the previews
                                            // stop chasing the display's refresh rate and tick along instead
                                            interval: !sc.onScreen ? 500
                                                      : (root.underLoad ? 400
                                                      : ((hh.hovered || ui.menuOpen || ui.stackItem !== null) ? root.frameMs : Math.max(root.frameMs, 66)))
                                            repeat: true
                                            running: sc.wantFrames && sc.captureSource !== null
                                            onTriggered: if (typeof sc.captureFrame === "function") sc.captureFrame()
                                        }
                                        onCaptureSourceChanged: { if (captureSource !== null && !root.glassHold) firstShot.restart(); }
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
                    readonly property bool wide: ui.menuOpen || ui.stackItem !== null
                    x: wide ? 0 : dock.x
                    width: wide ? ui.width : dock.width
                    y: wide ? 0 : (ui.tucked ? ui.height - 3 : (hh.hovered ? ui.activeTop : dock.y))
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
                                    if (status === ShaderEffect.Error) { console.log("[macdock-glass] shader failed:", log); root.glassState = "failed"; }
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
                                property real rimTint: 0
                                property real ringW: 0
                                property real flatInner: 0
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
                        color: root.darkMode ? Qt.rgba(0.10, 0.10, 0.11, root.solidLook ? 1 : root.glassOpacity)
                                             : Qt.rgba(root.solidLook ? 0.97 : 1, root.solidLook ? 0.97 : 1, root.solidLook ? 0.98 : 1, root.solidLook ? 1 : root.glassOpacity * 0.55)
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
                                Component.onCompleted: { heldTl = thumbWin; Qt.callLater(function () { cell.appear = cell.leavingCell ? 0 : 1; }); }
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
                                    // Settings → Icons → Icon style (Dark / Clear / Tinted), keeping each icon's shading
                                    colorization: root.iconColorize
                                    colorizationColor: root.iconColorizeColor
                                    saturation: root.iconSat
                                    // switching the icon style: a simple fade out and back in (iconSwitch)
                                    opacity: root.iconAlpha * (1 - root.iconSwap)
                                    brightness: (ma.pressed ? -0.3 : 0.0) + root.iconBright
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
                                    readonly property bool lit: !cell.isSep && cell.modelData.running && root.showIndicators
                                    opacity: lit ? 1 : 0
                                    scale: lit ? 1 : 0.2
                                    visible: opacity > 0.01
                                    Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
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
                                    opacity: (root.showLabels && !cell.isSep && ma.containsMouse && !ma.pressed && !ui.menuOpen && !ui.dragging && ui.stackItem === null) ? 1 : 0
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
                                        } else if (cell.modelData.kind === "folder") {
                                            if (ui.stackItem && ui.stackItem.key === cell.modelData.key) { ui.stackItem = null; return; }
                                            ui.stackCx = cell.mapToItem(ui, cell.width / 2, 0).x;
                                            ui.stackItem = cell.modelData;
                                            root.loadStack(cell.modelData.path);
                                            if (root.bar) root.bar.playSound("pop", 0.5);
                                        } else {
                                            root.activate(cell.modelData, mouse.button === Qt.MiddleButton);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // A folder pinned to the Dock fans its contents up into an arc, the way a macOS stack does: every item
                // flies out of the icon along the curve, tilting as it goes, and its name fades in underneath it.
                // Move the pointer away and the fan folds back into the icon by itself.
                Item {
                    id: stack
                    z: 55
                    anchors.fill: parent
                    visible: ui.stackItem !== null || stackT.running
                    readonly property bool shown: ui.stackItem !== null
                    // just above the Dock: only part of the magnification headroom is reserved, so the fan starts at the folder
                    readonly property real baseY: ui.height - root.margin - root.bgHeight - root.iconSize * (root.effMag - 1) * 0.4 - 6
                    readonly property int n: Math.max(1, root.stackFiles.length)
                    // the fan always sways to the right, unless the folder sits so close to the right edge
                    // that the arc would run off the screen
                    readonly property real lean: (ui.stackCx > ui.width - 260 ? -1 : 1)
                    readonly property real step: Math.max(48, Math.min(56, (baseY - 40) / (n + 0.6)))
                    property real t: 0
                    Behavior on t { NumberAnimation { id: stackT; duration: 460; easing.type: Easing.OutQuint } }


                    // Folds itself away when you stop looking at it — but not before you have had a chance to reach it:
                    // it stays put until the pointer has been over it once, or a couple of seconds have passed.
                    // Hover is counted on the fan's own items. (It used to be a HoverHandler filling the whole Dock
                    // layer, so the pointer always counted as "on the fan" and it never folded itself away.)
                    property int hovers: 0
                    readonly property bool fanHovered: hovers > 0
                    property bool everHovered: false
                    property bool settled: false
                    onShownChanged: {
                        t = shown ? 1 : 0;
                        everHovered = false; settled = false; hovers = 0;
                        if (shown) stackGrace.restart();
                    }
                    onFanHoveredChanged: if (fanHovered) everHovered = true
                    Timer { id: stackGrace; interval: 1800; onTriggered: stack.settled = true }
                    // "on the Dock" has to be a geometric test: while the fan is open the Dock's input mask covers the
                    // whole fan, so hh.hovered alone was true everywhere above the Dock and the fan never folded.
                    readonly property bool onDock: hh.hovered && hh.point.position.y > ui.activeTop
                    Timer {
                        id: stackLeave
                        interval: 500
                        running: stack.shown && !stack.fanHovered && !stack.onDock && (stack.everHovered || stack.settled)
                        onTriggered: ui.stackItem = null
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.AllButtons
                        onPressed: ui.stackItem = null
                    }
                    Repeater {
                        model: root.stackFiles
                        delegate: Item {
                            id: fanItem
                            required property var modelData
                            required property int index
                            readonly property real delay: index * 0.1
                            readonly property real p: Math.max(0, Math.min(1, (stack.t - delay) / Math.max(0.0001, 1 - delay)))
                            readonly property real ease: 1 - Math.pow(1 - p, 3)
                            // the sway: each step out leans further from the icon, and tilts with it
                            readonly property real angle: (index / Math.max(1, stack.n - 1)) * 0.62 * stack.lean
                            // the first item sits just above the folder, then one step per item
                            readonly property real rr: (12 + stack.step * index) * ease
                            width: 52; height: 54
                            x: ui.stackCx - width / 2 + Math.sin(angle) * rr * 0.78
                            y: stack.baseY - height - rr
                            opacity: Math.min(1, ease * 1.6)
                            scale: 0.4 + 0.6 * ease
                            rotation: angle * 26 * ease
                            z: stack.n - index

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -4
                                radius: 11
                                color: fanMa.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : "transparent"
                                Behavior on color { ColorAnimation { duration: 140 } }
                            }
                            Image {
                                id: fanIcon
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 0
                                width: 40; height: 40
                                asynchronous: true; cache: true; smooth: true; mipmap: true
                                sourceSize: Qt.size(80, 80)
                                fillMode: fanItem.modelData.isImage ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                                source: fanItem.modelData.isImage ? "file://" + fanItem.modelData.path
                                      : (fanItem.modelData.isDir ? root.folderIcon : root.iconSrc("text-x-generic"))
                            }
                            // the name sits under the icon and travels with it: one motion, not icons first and names after
                            Item {
                                id: labelWrap
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 42
                                width: parent.width + 26; height: lbl.implicitHeight
                                readonly property real lp: Math.min(1, fanItem.ease * 1.6)
                                opacity: lp * (fanMa.containsMouse ? 1 : 0.82)
                                Behavior on opacity { NumberAnimation { duration: 140 } }
                                // the icons tilt with the arc, the names stay upright and readable
                                rotation: -fanItem.rotation
                                transform: Translate { y: (1 - labelWrap.lp) * 6 }
                                Text {
                                    id: lbl
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideMiddle
                                    text: fanItem.modelData.name
                                    color: "white"
                                    font.family: root.fontFamily; font.pixelSize: 10
                                    style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.6)
                                }
                                layer.enabled: labelWrap.lp < 0.98
                                layer.effect: MultiEffect { blurEnabled: true; blurMax: 16; blur: 1 - labelWrap.lp; autoPaddingEnabled: true }
                            }
                            MouseArea {
                                id: fanMa
                                anchors.fill: parent; anchors.margins: -4
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onContainsMouseChanged: stack.hovers += containsMouse ? 1 : -1
                                onClicked: {
                                    var it = fanItem.modelData;
                                    ui.stackItem = null;
                                    if (it.isDir) { if (root.hub && root.hub.openFolder) root.hub.openFolder(it.path); }
                                    else if (root.hub && root.hub.openPath) root.hub.openPath(it.path);
                                    else Quickshell.execDetached(["xdg-open", it.path]);
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
                    // grows up out of the Dock, stretching into shape as it comes into focus; closing runs it back
                    property real popT: ui.menuOpen ? 1 : 0
                    Behavior on popT { NumberAnimation { duration: ui.menuOpen ? 440 : 220; easing.type: ui.menuOpen ? Easing.OutQuint : Easing.OutCubic } }
                    visible: popT > 0.002
                    opacity: Math.min(1, popT * 1.7)
                    transform: [
                        Scale { origin.x: menu.width / 2; origin.y: menu.height; xScale: 0.9 + 0.1 * menu.popT; yScale: 0.74 + 0.26 * menu.popT },
                        Translate { y: 10 * (1 - menu.popT) }
                    ]
                    layer.enabled: popT < 0.995
                    layer.effect: MultiEffect { blurEnabled: true; blurMax: 28; blur: 1 - menu.popT; autoPaddingEnabled: true }

                    width: 230
                    height: menuCol.height + 10
                    x: Math.max(8, Math.min(ui.width - width - 8, ui.menuCx - width / 2))
                    y: ui.height - root.margin - root.bgHeight - root.iconSize * (root.effMag - 1) - 14 - height
                    radius: 10
                    color: root.darkMode ? Qt.rgba(0.14, 0.14, 0.15, 0.62) : Qt.rgba(0.97, 0.97, 0.98, 0.78)
                    Behavior on color { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    border.width: 1
                    border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12)

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
                                    color: root.darkMode ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)
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
                                    text: mi.isSep ? "" : (mi.armedNow ? I18n.tr("Click again to confirm") : mi.modelData.label)
                                    color: mia.containsMouse && !mi.off ? "white"
                                         : (root.darkMode ? (mi.off ? Qt.rgba(1, 1, 1, 0.4) : "white") : (mi.off ? Qt.rgba(0, 0, 0, 0.35) : "#1d1d1f"))
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
