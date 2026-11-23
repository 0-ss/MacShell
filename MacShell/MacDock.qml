// macdock v2 — a macOS-style dock for Hyprland, built on Quickshell. vSuol
//
// Part of the combined macbar + macdock shell (see shell.qml). Keep this file, MacBar.qml, shell.qml and
// liquidglass.frag together in ~/.config/quickshell/macbar/ and run:  qs -c macbar
// Pins are saved to ~/.config/macdock/pinned.json once you use "Keep in Dock".
//
// Settings are saved to ~/.config/macdock/settings.json (right-click the dock → Dock Preferences…).
// The settings window is frameless and always opens floating + centred: the shell registers the Hyprland window rule for it
// itself (registerSettingsRule below), so nothing has to be added to the Hyprland config.
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
    property bool desktopIcons: true     // show files, folders and .desktop shortcuts from the XDG Desktop directory
    property int desktopIconSize: 48     // Desktop icon size in logical pixels
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

    function openTerminalCommand(command) {
        var preferred = bar && bar.terminal ? bar.terminal : "kitty";
        Quickshell.execDetached(["sh", "-c",
            "for t in \"$1\" kitty foot alacritty wezterm konsole xterm; do " +
            "  [ -n \"$t\" ] && command -v \"$t\" >/dev/null 2>&1 || continue; " +
            "  exec \"$t\" -e sh -c 'eval \"$1\"; echo; printf \"Done. Press Enter to close \"; read -r _' sh \"$2\"; " +
            "done; " +
            "if command -v gnome-terminal >/dev/null 2>&1; then exec gnome-terminal -- sh -c 'eval \"$1\"; echo; printf \"Done. Press Enter to close \"; read -r _' sh \"$2\"; fi; " +
            "notify-send 'MacShell' 'No terminal emulator found for the sudo command' 2>/dev/null || true",
            "sh", preferred, command]);
    }

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
        stdout: StdioCollector { onStreamFinished: {
            try { root.monList = JSON.parse(text); } catch (e) {}
            if (root.savedModesPending) { root.savedModesPending = false; root.applySavedModes(true); }
        } }
    }
    function modeOf(m) { return m.width + "x" + m.height + "@" + Number(m.refreshRate).toFixed(2); }
    function applyMode(out, mode) {
        var m = null;
        for (var i = 0; i < monList.length; i++) if (monList[i].name === out) m = monList[i];
        var pos = m ? (m.x + "x" + m.y) : "auto", sc = m ? m.scale : 1;
        Quickshell.execDetached(["hyprctl", "eval", "hl.monitor({ output = \"" + out + "\", mode = \"" + mode + "\", position = \"" + pos + "\", scale = " + sc + " })"]);
        monRefreshSoon.restart();
    }
    // saved entry: legacy "WxH@Hz" string or { mode, position, scale }; missing position/scale come from the live monitor, else auto / 1
    function normalizeModeEntry(entry, liveMon) {
        var e = typeof entry === "string" ? { mode: entry } : (entry || {});
        if (typeof e.mode !== "string" || !/^[A-Za-z0-9.@]+$/.test(e.mode)) return null;
        var pos = typeof e.position === "string" && /^(auto|-?[0-9]+x-?[0-9]+)$/.test(e.position) ? e.position
                : (liveMon ? liveMon.x + "x" + liveMon.y : "auto");
        var sc = typeof e.scale === "number" && e.scale > 0 ? e.scale : (liveMon && liveMon.scale > 0 ? liveMon.scale : 1);
        return { mode: e.mode, position: pos, scale: sc };
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
        var lm = null;
        for (var i = 0; i < monList.length; i++) if (monList[i].name === pendingOut) lm = monList[i];
        mm[pendingOut] = { mode: pendingMode, position: lm ? (lm.x + "x" + lm.y) : "auto", scale: lm && lm.scale > 0 ? lm.scale : 1 };
        displays = { primary: d.primary || "", modes: mm };
        saveDisplays();
        pendingOut = ""; pendingMode = "";
    }
    function revertMode() {
        revertTimer.stop();
        if (pendingOut !== "" && pendingPrev !== "") applyMode(pendingOut, pendingPrev);
        pendingOut = ""; pendingMode = "";
    }
    property bool savedModesPending: false
    function applySavedModes(retried) {
        var mm = displays.modes || {};
        // live positions/scales are needed for legacy entries: wait for the first monitor list (once)
        if (!retried && Object.keys(mm).length > 0 && monList.length === 0) { savedModesPending = true; refreshMons(); return; }
        for (var k in mm) {
            var lm = null;
            for (var i = 0; i < monList.length; i++) if (monList[i].name === k) lm = monList[i];
            var e = normalizeModeEntry(mm[k], lm);
            if (!e || !/^[A-Za-z0-9._-]+$/.test(k)) continue;
            Quickshell.execDetached(["hyprctl", "eval", "hl.monitor({ output = \"" + k + "\", mode = \"" + e.mode + "\", position = \"" + e.position + "\", scale = " + e.scale + " })"]);
        }
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
    property bool showRunningApps: true   // icons for running apps that aren't pinned. might want it off for pinned-only Dock.
    onShowRunningAppsChanged: rebuild()
    property bool iconTile: true   // rounded tile with the icon's dominant color and a light edge behind each icon. could be turned off if somebody prefer the old look.
    readonly property real iconRim: 1.0   // strength of the edge light. fixed value.
    readonly property real iconEdge: 2.0   // how soft the icon edge is. fixed value.
    readonly property real iconScale: 1.0   // how big the icon is inside its cell. fixed at 1.
    readonly property string iconShape: "rounded"   // only rounded here.
    readonly property real iconCorner: 0.245   // corner radius as a fraction of the icon width. 0.245 is probably close to the usual icon corner.
    readonly property real iconPower: iconShape === "squircle" ? 5.0 : 2.0
    readonly property vector4d iconRadii: Qt.vector4d(iconCorner, iconCorner, iconCorner, iconCorner)
    property bool bounceOnLaunch: true
    property bool showThumbs: true       // open windows get a live preview cell next to the Trash
    property bool windowCapture: true    // live window capture for those previews (off: the cells show the app icon, nothing is captured). Liquid Glass is not affected
    property string minimizeEffect: "genie" // genie | fade | instant (built-in MinimizeFx)
    property real minimizeSpeed: 0.42       // Genie duration in seconds (0.2 .. 1.2)
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

    // grouped like macOS System Settings (sec = sidebar section; a gap is drawn between sections)
    readonly property var settingsPanes: [
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
        { id: "dock",       sec: 3, name: "Desktop & Dock",  glyph: "dock",     c1: "#2C2C2E", c2: "#1C1C1E", keys: "size icon magnification zoom spacing margin distance corner radius round square edge hide auto labels indicators bounce trash monitor preview app switcher alt tab titlebar titlebars traffic lights minimize genie animation mission control expose stage manager hot corners tiling snap reveal desktop multitasking quick note" },
        { id: "menubar",    sec: 3, name: "Menu Bar",        glyph: "menubar",  c1: "#3D9BFF", c2: "#0A6CFF", keys: "panel bar height clock date seconds 24 hour battery tray search spotlight week monday style liquid bluetooth screenshots" },
        { id: "controlcenter", sec: 3, name: "Control Center", wg: "cc",       c1: "#8E8E93", c2: "#636366", keys: "modules tiles controls" },
        { id: "widgets",    sec: 3, name: "Widgets",         glyph: "widgets",  c1: "#FF9F0A", c2: "#FF7A00", keys: "desktop widgets weather clock calendar player image photo gif sysmon reminders batteries notes photos alarms stocks add remove arrange edit size temperature fahrenheit celsius city location" },
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

    SettingsWindow {
        id: prefsWindow
        dock: root
    }

    readonly property real effMag: magnificationEnabled ? magnification : 1
    // hover labels and the right-click menu scale with the Dock (52 px icons = the reference size)
    readonly property real labelK: Math.max(0.7, Math.min(2.2, iconSize / 52))
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
        desktopIcons = true; desktopIconSize = 48;
        iconSize = 52; magnification = 1.7; magnificationEnabled = true;
        spacing = 6; margin = 6; cornerRadius = 18;
        darkMode = true; appearanceMode = "dark"; glassOpacity = 0.42; glassBlur = 5; glassLiquid = 1.0; dockStyle = "blur"; accent = "#0a84ff"; fontFamily = "Open Runde";
        iconTint = false; iconTintColor = "#0a84ff"; iconTintStrength = 1.0;
        hideMode = "smart"; hideDelay = 450; monitor = "";
        showTrash = true; showLabels = true; showIndicators = true; showRunningApps = true; iconTile = true; bounceOnLaunch = true; showThumbs = true; windowCapture = true; glassLive = true;
        minimizeEffect = "genie"; minimizeSpeed = 0.42;
        if (hub && hub.decor) { hub.decor.enabled = false; hub.decor.showTitle = true; }
    }

    // ── settings persistence (~/.config/macdock/settings.json) ──
    readonly property string settingsSig: [dockEnabled, settingsEnabled, desktopIcons, desktopIconSize, iconSize, magnification, magnificationEnabled, spacing, margin,
        cornerRadius, darkMode, appearanceMode, glassOpacity, glassBlur, glassLiquid, dockStyle, wallpaperPath, String(accent), fontFamily, hideMode, hideDelay, monitor,
        showTrash, showLabels, showIndicators, bounceOnLaunch, showThumbs, windowCapture, glassLive, iconTint, iconTintColor, iconTintStrength, showRunningApps, iconTile,
        minimizeEffect, minimizeSpeed].join("|")
    property bool settingsReady: false
    onSettingsSigChanged: if (settingsReady) saveTimer.restart()
    onShowTrashChanged: { rebuild(); if (showTrash) trashCheck(); }
    onShowThumbsChanged: rebuild()
    onWindowCaptureChanged: rebuild()

    function saveSettings() {
        var o = {
            dockEnabled: dockEnabled, settingsEnabled: settingsEnabled, desktopIcons: desktopIcons, desktopIconSize: desktopIconSize, iconSize: iconSize, magnification: magnification, magnificationEnabled: magnificationEnabled,
            spacing: spacing, margin: margin, cornerRadius: cornerRadius,
            darkMode: darkMode, appearanceMode: appearanceMode, glassOpacity: glassOpacity, dockStyle: dockStyle, wallpaperPath: wallpaperPath, glassDebug: glassDebug,
            glassRim: glassRim, glassGrain: glassGrain, glassLiquid: glassLiquid, glassBlur: glassBlur,
            accent: String(accent), fontFamily: fontFamily,
            hideMode: hideMode, hideDelay: hideDelay, monitor: monitor,
            showTrash: showTrash, showLabels: showLabels, showIndicators: showIndicators, showRunningApps: showRunningApps, iconTile: iconTile,
            bounceOnLaunch: bounceOnLaunch, showThumbs: showThumbs, windowCapture: windowCapture, glassLive: glassLive,
            iconTint: iconTint, iconTintColor: iconTintColor, iconTintStrength: iconTintStrength,
            minimizeEffect: minimizeEffect, minimizeSpeed: minimizeSpeed
        };
        settingsStore.setText(JSON.stringify(o, null, 2));
    }

    function applySettings(o) {
        if (!o || typeof o !== "object") return;
        var keys = ["dockEnabled", "settingsEnabled", "desktopIcons", "desktopIconSize", "iconSize", "magnification", "magnificationEnabled", "spacing", "margin", "cornerRadius",
                    "darkMode", "appearanceMode", "glassOpacity", "dockStyle", "wallpaperPath", "glassDebug", "glassRim", "glassGrain", "glassLiquid", "glassBlur", "accent", "fontFamily", "hideMode", "hideDelay", "monitor",
                    "showTrash", "showLabels", "showIndicators", "showRunningApps", "iconTile", "bounceOnLaunch", "showThumbs", "windowCapture", "glassLive", "iconTint", "iconTintColor", "iconTintStrength",
                    "minimizeEffect", "minimizeSpeed"];
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
    readonly property string appsIconPath: decodeURIComponent(String(Qt.resolvedUrl("assets/apps-dock.svg")).replace(/^file:\/\//, ""))
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

    // ── drops onto the Trash from other surfaces (the desktop's icons) ──
    // every Dock window registers its `ui` item under its screen's name
    property var trashProbes: ({})
    function trashHit(screenName, x, y) {
        var u = trashProbes[screenName];
        return u ? u.trashHit(x, y) === true : false;
    }
    // centre of the Trash cell in screen coordinates (null when the Dock has none to show)
    function trashCenter(screenName) {
        var u = trashProbes[screenName];
        return u ? u.trashCenter() : null;
    }
    // the Trash icon hops once: something has just landed in it
    // an icon is being dragged over the Trash (on = true) or has left it again: the Trash icon lifts to say "let go to throw it away"
    function trashArm(screenName, on) {
        var u = trashProbes[screenName];
        if (u) u.trashArmed = on === true;
    }
    function trashPulse(screenName) {
        var u = trashProbes[screenName];
        if (u) u.trashKick++;
    }
    // an icon from the desktop is held near the bottom edge: slide an auto-hidden Dock up so the Trash can be reached (and back down after)
    function trashReveal(screenName, on) {
        var u = trashProbes[screenName];
        if (u) u.dragReveal(on === true);
    }

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
    property int trashCount: 0
    property bool trashCountKnown: false
    property real trashExpectAt: 0
    function trashExpect() { trashExpectAt = Date.now(); }
    function trashPulseAll() { for (var nm in trashProbes) trashPulse(nm); }
    // Empty Trash animation: the Trash icon on every screen shakes and hops once
    function trashEmptyAnimAll() { for (var nm in trashProbes) { var u = trashProbes[nm]; if (u) u.trashEmptyKick++; } }
    function trashCheck() { if (!trashCheckProc.running) trashCheckProc.running = true; }
    Process {
        id: trashCheckProc
        command: ["sh", "-c", "mkdir -p \"$1\"; n=$(ls -A \"$1\" 2>/dev/null | wc -l); if [ \"$n\" -gt 0 ]; then s=1; else s=0; fi; "
                              + "if command -v inotifywait >/dev/null 2>&1; then w=w; else w=p; fi; echo \"$s $w $n\"", "sh", root.trashDir]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = text.trim().split(" ");
                root.trashFull = t[0] === "1";
                root.trashPoll = t[1] === "p";
                // something new landed in the Trash (file manager, terminal, another app): the Trash icon hops too, unless the
                // desktop has just thrown it in itself (that has its own fly-in and hops at the end of it)
                var n = Number(t[2]);
                if (!isNaN(n)) {
                    if (root.trashCountKnown && n > root.trashCount && Date.now() - root.trashExpectAt > 2500) root.trashPulseAll();
                    root.trashCount = n; root.trashCountKnown = true;
                }
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
        trashEmptyAnimAll();
        if (bar) bar.playSound("trash", 0.8);
    }
    // the icon turns "empty" as the hop starts (≈ 520 ms in); the real check follows and corrects it if needed
    Timer { id: trashAfterEmpty; interval: 520; onTriggered: { root.trashFull = false; root.trashCheck(); } }
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

    // Optional genie minimize (see contrib/genie): when ~/.local/bin/macshell-genie exists, Dock clicks go through it, because
    // a window minimized with the genie sits on a hidden special workspace where Hyprland ignores activate().
    // Without the helper nothing changes.
    readonly property string genieHelper: Quickshell.env("HOME") + "/.local/bin/macshell-genie"
    readonly property string genieRuntime: Quickshell.env("XDG_RUNTIME_DIR") || Quickshell.env("HOME") + "/.cache"
    FileView { id: genieProbe; path: root.genieHelper; printErrors: false }
    function genieAddr(tl) {
        var v = Hyprland.toplevels.values;
        for (var i = 0; i < v.length; i++) if (v[i].wayland === tl) return "0x" + String(v[i].address).replace(/^0x/, "");
        return "";
    }
    function genieDock(chosen, all) {
        if (!genieProbe.loaded) return false;
        var a = genieAddr(chosen);
        if (!a) return false;
        var args = [genieHelper, "dock", a];
        for (var i = 0; i < all.length; i++) { var b = genieAddr(all[i]); if (b) args.push(b); }
        Quickshell.execDetached(args);
        return true;
    }

    function iconRectFor(screenName, appId) {
        var p = trashProbes[screenName];
        if (!p || typeof p.iconRect !== "function") return null;
        return p.iconRect(appId);
    }
    function restoreNativeTracked(tl) {
        if (!tl || !hub || !hub.hasMinimizedRecord || !hub.restoreWindow) return false;
        var a = genieAddr(tl);
        return a !== "" && hub.hasMinimizedRecord(a) && hub.restoreWindow(a);
    }
    function restoreIfMinimized(tl) {
        if (!tl || !hub || !hub.restoreWindow) return false;
        var a = genieAddr(tl);
        return a !== "" && hub.restoreWindow(a);
    }
    function activate(item, forceNew) {
        if (item.kind === "win") {
            if (item.tl && !restoreNativeTracked(item.tl) && !genieDock(item.tl, [item.tl]) && !restoreIfMinimized(item.tl)) item.tl.activate();
            return;
        }
        if (item.special === "apps") { if (bar) bar.spotOpen("apps"); return; }
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
            var chosen = wins[(idx + 1) % wins.length];
            if (!restoreNativeTracked(chosen) && !genieDock(chosen, wins) && !restoreIfMinimized(chosen)) chosen.activate();
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
            if (it.kind === "app" && it.pinned && (!it.special || it.special === "apps")) vis.push(it);
            else break;
        }
        if (from < 0) return;
        if (from >= vis.length) {
            // "Apps" dragged out of its default spot (after the separators / windows) into the pinned block
            var ai = items[from];
            if (!ai || ai.special !== "apps") return;
            vis.splice(Math.max(0, Math.min(to, vis.length)), 0, ai);
        } else {
            var moved = vis.splice(from, 1)[0];
            vis.splice(Math.max(0, Math.min(to, vis.length)), 0, moved);
        }

        var out = [], have = {};
        for (var v = 0; v < vis.length; v++) { out.push(vis[v].special === "apps" ? "__apps" : vis[v].entry.id); have[vis[v].key] = true; }
        for (var p = 0; p < pinned.length; p++) {
            var id = String(pinned[p]).replace(/\.desktop$/, "");
            if (!have[id.toLowerCase()]) out.push(pinned[p]);
        }
        pinned = out;
        store.setText(JSON.stringify(out, null, 2));
        rebuild();
    }

    function resetAppsSlot() {
        var out = [];
        for (var i = 0; i < pinned.length; i++) if (String(pinned[i]) !== "__apps") out.push(pinned[i]);
        pinned = out;
        store.setText(JSON.stringify(out, null, 2));
        rebuild();
    }

    function menuFor(item) {
        var m = [];
        if (item.kind === "win") {
            m.push({ kind: "item", label: I18n.tr("Show"), run: function () { activate(item, false); } });
            m.push({ kind: "item", label: I18n.tr("Close"), run: function () { var t = item.tl; if (!t) return; if (root.hub) root.hub.closeQuietly(function () { if (t) t.close(); }); else t.close(); } });
            m.push({ kind: "sep" });
            m.push({ kind: "item", label: I18n.tr("Settings\u2026"), run: function() { root.openPrefs(); } });
            return m;
        }
        if (item.special === "apps") {
            m.push({ kind: "item", label: I18n.tr("Open"), run: function () { activate(item, false); } });
            if (item.pinned) m.push({ kind: "item", label: I18n.tr("Reset Position"), run: function () { resetAppsSlot(); } });
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
            m.push({ kind: "item", label: I18n.tr("Show All Windows"),
                     run: function () {
                         if (root.hub && root.hub.mc) root.hub.mc.openExpose(item.appId || item.key, "");
                     } });
            m.push({ kind: "sep" });
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
                var closeAll = function () { for (var j = 0; j < ws.length; j++) { try { if (ws[j]) ws[j].close(); } catch (err) { } } };
                if (root.hub) root.hub.closeQuietly(closeAll); else closeAll();
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
        var appsItem = { kind: "app", key: "__apps", name: I18n.tr("Apps"), icon: Quickshell.iconPath("view-app-grid", true) !== "" ? "view-app-grid" : appsIconPath,
                         entry: null, running: false, pinned: false, special: "apps" };
        var appsPlaced = false;
        for (var p = 0; p < pinned.length; p++) {
            if (String(pinned[p]) === "__apps") {
                if (!appsPlaced) { appsItem.pinned = true; list.push(appsItem); appsPlaced = true; }
                continue;
            }
            var e = DesktopEntries.byId(String(pinned[p]).replace(/\.desktop$/, ""));
            if (!e) continue;
            var ek = e.id.toLowerCase();
            if (seen[ek]) continue;
            seen[ek] = true;
            list.push({ kind: "app", key: ek, appId: e.id, name: e.name, icon: e.icon, entry: e,
                        running: !!running[ek], pinned: true });
        }

        var extras = [];
        for (var r = 0; r < runOrder.length; r++) if (!seen[runOrder[r].key] && root.showRunningApps) extras.push(runOrder[r]);
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
                if (winAge(tl) < 250) { if (!youngWin.running) youngWin.start(); continue; }     // no preview (= no capture) for brand-new windows
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

        // [apps…] | [windows…] | Apps (Spotlight's application list) | Trash
        list.push({ kind: "sep", key: "sep:win" });
        for (var wj = 0; wj < winItems.length; wj++) list.push(winItems[wj]);
        if (winItems.length > 0) list.push({ kind: "sep", key: "sep:trash" });
        if (!appsPlaced) list.push(appsItem);
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
    property bool backdropLoaded: liquidActive
    property bool backdropDraining: false
    onLiquidActiveChanged: {
        if (liquidActive) { backdropUnloadT.stop(); backdropDraining = false; backdropLoaded = true; }
        else if (backdropLoaded) { backdropDraining = true; backdropUnloadT.restart(); }
    }
    Timer { id: backdropUnloadT; interval: 450; onTriggered: if (!root.liquidActive) { root.backdropLoaded = false; root.backdropDraining = false; } }
    // Settings' own glass (back / forward pill, knobs of switches and sliders): available whenever the shader is built,
    // whatever the Dock style is
    readonly property bool settingsGlass: glassState === "ready" && !(bar && bar.gaming)
    // < > pill glass: glass on + this window's position on its monitor is known (also gates the hidden wallpaper capture)
    readonly property bool winGlassBg: settingsGlass && prefsWindow.glassGeoOk
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
    // titles and screencast announcements move nothing on screen (shell.qml filters the same events)
    function shouldRefreshDockForEvent(name) {
        return name !== "windowtitle" && name !== "windowtitlev2"
            && name !== "activewindow" && name !== "screencast" && name !== "screencastv2";
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (!root.shouldRefreshDockForEvent(event.name)) return;
            busyDebounce.restart(); tickDebounce.restart();
        }
    }
    Timer { id: busyDebounce; interval: 120; onTriggered: root.refreshBusy() }

    // The Settings window has to be floating from its FIRST frame, otherwise Hyprland tiles it full size and it only jumps to
    // floating afterwards (the float dispatches below can only run once the window is mapped). A static window rule is applied
    // at map time, so the shell registers one itself (Hyprland 0.55+ Lua, `hyprctl eval`): no Hyprland config edit needed.
    // force = false keeps it idempotent (one rule per Hyprland session); a config reload drops it, so that re-registers it.
    function registerSettingsRule(force) {
        var rule = 'hl.window_rule({ name = "macshell-settings-float", match = { title = "^(macshell Settings)$" }, float = true, center = true, border_size = 0 })';
        Quickshell.execDetached(["hyprctl", "eval", force ? ('macshell_settings_rule = ' + rule) : ('macshell_settings_rule = macshell_settings_rule or ' + rule)]);
    }
    Timer { id: ruleReload; interval: 400; onTriggered: root.registerSettingsRule(true) }
    Connections {
        target: Hyprland
        function onRawEvent(event) { if (event.name === "configreloaded") ruleReload.restart(); }
    }

    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", configDir]);
        registerSettingsRule(false);
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
                    property var oldTl: null
                    visible: shown && opacity > 0.01
                    opacity: 0
                    transformOrigin: Item.Center
                    RectangularShadow { anchors.fill: parent; radius: 10; blur: 30; offset.y: 8; color: Qt.rgba(0, 0, 0, 0.30) }
                    Rectangle { anchors.fill: parent; radius: 10; color: Qt.rgba(0.09, 0.08, 0.09, 0.88) }
                    SafeCapture {
                        id: oldSv
                        anchors.fill: parent
                        want: oldSnap.oldTl
                        wantLive: false
                        hold: true
                        healOnResize: false
                        graceMs: 250
                        layer.enabled: true
                        layer.effect: MultiEffect { maskEnabled: true; maskSource: oldMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                    }
                    Item { id: oldMask; anchors.fill: parent; visible: false; layer.enabled: true; Rectangle { anchors.fill: parent; radius: 10; color: "black" } }
                    ParallelAnimation {
                        id: oldOut
                        NumberAnimation { target: oldSnap; property: "opacity"; from: 1; to: 0; duration: 340; easing.type: Easing.OutCubic }
                        NumberAnimation { target: oldSnap; property: "scale"; from: 1; to: 0.94; duration: 420; easing.type: Easing.OutQuint }
                        onFinished: { oldSnap.shown = false; oldSnap.oldTl = null; }
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
                    SafeCapture {
                        id: gsv
                        visible: tearGhost.isWin && gsv.hasContent === true && gsv.held === gsv.want
                        anchors.fill: parent
                        want: (tearGhost.isWin && tearWin.visible && ui.tearItem && ui.tearItem.tl) ? ui.tearItem.tl : null
                        wantLive: tearGhost.isWin && tearWin.visible && tearGhost.visible && !root.previewHold
                        hold: root.previewHold
                        healOnResize: false
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

                // Is the screen point (sx, sy) over this Dock's Trash cell? (the Dock's surface only covers the bottom of the screen,
                // so the point is turned into this surface's own coordinates first)
                function trashHit(sx, sy) {
                    if (!root.showTrash || tucked) return false;
                    var ly = sy - (win.modelData.height - win.height);
                    for (var i = 0; i < rep.count; i++) {
                        var c = rep.itemAt(i);
                        if (!c || !c.modelData || c.modelData.special !== "trash") continue;
                        var p = c.mapToItem(ui, 0, 0), pad = 18;
                        return sx >= p.x - pad && sx <= p.x + c.width + pad && ly >= p.y - 44 && ly <= p.y + c.height + pad;
                    }
                    return false;
                }
                property int trashKick: 0
                property int trashEmptyKick: 0
                property bool trashArmed: false
                function dragReveal(on) {
                    if (on) { hideTimer.stop(); revealed = true; }
                    else hideTimer.restart();
                }
                function trashCenter() {
                    for (var i = 0; i < rep.count; i++) {
                        var c = rep.itemAt(i);
                        if (!c || !c.modelData || c.modelData.special !== "trash") continue;
                        var p = c.mapToItem(ui, c.width / 2, c.height / 2);
                        return Qt.point(p.x, p.y + (win.modelData.height - win.height));
                    }
                    return null;
                }
                Component.onCompleted: { var m = root.trashProbes; m[win.modelData.name] = ui; root.trashProbes = m; genieRectsTimer.restart(); }
                Component.onDestruction: { var m = root.trashProbes; delete m[win.modelData.name]; root.trashProbes = m; }

                // Optional genie minimize (see contrib/genie): where each app icon sits on screen (global logical px), so the
                // genie can aim at the app's own icon on the window's monitor.
                // Only written when the helper is installed.
                FileView {
                    id: genieRectsFile
                    path: root.genieRuntime + "/macshell-dock-rects-" + win.modelData.name.replace(/[^a-zA-Z0-9_.-]/g, "_") + ".json"
                    printErrors: false
                    atomicWrites: true
                }
                Timer { id: genieRectsTimer; interval: 300; onTriggered: ui.genieWriteRects() }
                Connections { target: row; function onWidthChanged() { genieRectsTimer.restart(); } function onXChanged() { genieRectsTimer.restart(); } }
                Connections { target: root; function onItemsChanged() { genieRectsTimer.restart(); } }
                function iconRect(appId) {
                    var want = String(appId || "").toLowerCase();
                    var wantKey = want !== "" ? root.keyOf(appId) : "";
                    var top = win.modelData.y + win.modelData.height - win.height;
                    for (var i = 0; i < rep.count; i++) {
                        var c = rep.itemAt(i);
                        if (!c || c.isSep || c.modelData.kind !== "app") continue;
                        var k = String(c.modelData.key || "").toLowerCase();
                        var aid = String(c.modelData.appId || "").toLowerCase();
                        if ((want !== "" && (k === want || aid === want)) || (wantKey !== "" && k === wantKey)) {
                            var icon = c.iconImg;
                            var p = icon.mapToItem(null, 0, 0);
                            return { x: Math.round(win.modelData.x + p.x), y: Math.round(top + p.y), width: Math.round(icon.width), height: Math.round(icon.height) };
                        }
                    }
                    return null;
                }
                function genieWriteRects() {
                    if (!genieProbe.loaded) return;
                    var map = {};
                    var top = win.modelData.y + win.modelData.height - win.height;
                    for (var i = 0; i < rep.count; i++) {
                        var c = rep.itemAt(i);
                        if (!c || c.isSep || c.modelData.kind !== "app") continue;
                        var icon = c.iconImg;
                        var p = icon.mapToItem(null, 0, 0);
                        var r = [Math.round(win.modelData.x + p.x), Math.round(top + p.y), Math.round(icon.width), Math.round(icon.height)];
                        if (c.modelData.key) map[String(c.modelData.key).toLowerCase()] = r;
                        if (c.modelData.appId) map[String(c.modelData.appId).toLowerCase()] = r;
                    }
                    genieRectsFile.setText(JSON.stringify(map));
                }

                // pointer x, followed EXACTLY (no animation). This used to ease over 55 ms, restarted on every pointer event: moving
                // the mouse quickly left the magnification a few frames behind the pointer, worse with many icons
                property real mx: 0
                // raw pointer x as the events arrive; ui.mx (which every cell's scale is bound to) takes it once per FRAME. A 1000 Hz mouse
                // used to re-evaluate every cell's bindings + the Row layout hundreds of times a second, more with more pinned apps.
                property real rawMx: 0
                FrameAnimation {
                    running: hh.hovered && !ui.dragging
                    onTriggered: if (ui.mx !== ui.rawMx && (!ui.menuOpen || hh.point.position.y > ui.activeTop)) ui.mx = ui.rawMx
                }
                property bool revealed: false
                property var menuItem: null
                property var menuModel: []
                property string armed: ""            // label of a confirm-type entry that was clicked once (e.g. Empty Trash)
                property real menuTailX: -1
                function updateMenuTail() {
                    if (!menuOpen) return;
                    var w = menuW;
                    var idealX = menuCx - w / 2;
                    var clampedX = Math.max(8, Math.min(ui.width - w - 8, idealX));
                    menuTailX = Math.round(menuCx - clampedX);
                }
                onMenuItemChanged: {
                    armed = "";
                    if (menuItem === null) {
                        menuCell = null;
                        menuIconTop = -1;
                        menuTailX = -1;
                    } else {
                        updateMenuTail();
                    }
                }
                // the cell the right-click menu belongs to: while the menu is open it follows that icon (its centre and its top edge), the
                // way the hover label does, as the icons magnify and the Dock widens / narrows
                property Item menuCell: null
                property real menuIconTop: -1
                function syncMenu() {
                    var c = menuCell;
                    if (!c || !c.iconImg) return;
                    var p = c.mapToItem(ui, c.width / 2, 0);
                    if (Math.abs(p.x - menuCx) > 0.05) menuCx = p.x;
                    var t = c.iconImg.mapToItem(ui, 0, 0).y;
                    if (Math.abs(t - menuIconTop) > 0.05) menuIconTop = t;
                    if (menuTailX < 0) updateMenuTail();
                }
                FrameAnimation { running: ui.menuOpen && ui.menuCell !== null; onTriggered: ui.syncMenu() }
                property real menuCx: 0
                // the menu is as wide as its longest entry (measured here whenever a menu is built)
                property real menuTextW: 0
                readonly property real menuW: Math.max(Math.round(168 * root.labelK), Math.min(Math.round(360 * root.labelK), Math.ceil(menuTextW) + Math.round(38 * root.labelK)))
                TextMetrics {
                    id: menuTm
                    font.pixelSize: Math.max(9, Math.round(13 * root.labelK))
                    font.family: root.fontForWeight(Font.Normal, root.fontFamily)
                }
                function measureMenu() {
                    var w = 0;
                    for (var i = 0; i < menuModel.length; i++) {
                        var e = menuModel[i];
                        if (e.kind === "sep") continue;
                        menuTm.text = I18n.tr(e.label);
                        w = Math.max(w, menuTm.advanceWidth);
                        if (e.confirm === true) { menuTm.text = I18n.tr("Click again to confirm"); w = Math.max(w, menuTm.advanceWidth); }
                    }
                    menuTextW = w;
                }
                onMenuModelChanged: {
                    measureMenu();
                    updateMenuTail();
                }
                readonly property bool menuOpen: menuItem !== null
                readonly property bool wantsHide: root.hideMode === "always"
                    || (root.hideMode === "smart" && root.busyMonitors[win.modelData.name] === true)
                property bool dragging: false
                property int dragIndex: -1
                property int dragTarget: -1
                property string dragKey: ""
                property bool dragTail: false          // "Apps" is being dragged out of its default spot (everything between shifts, separators included)
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
                NumberAnimation {
                    id: ghostFade
                    target: tearGhost; property: "opacity"; to: 0; duration: 180; easing.type: Easing.OutCubic
                    onFinished: if (!ui.tearing) ui.tearItem = null
                }
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
                        oldSnap.shown = false; oldOut.stop(); oldSnap.oldTl = null;
                        oldVisible = !!(o && o.at && o.workspace && mon0 && mon0.activeWorkspace && o.workspace.id === mon0.activeWorkspace.id);
                        if (oldVisible) {
                            oldSnap.x = o.at[0] - win.modelData.x; oldSnap.y = o.at[1] - win.modelData.y;
                            oldSnap.width = o.size[0]; oldSnap.height = o.size[1];
                            oldSnap.oldTl = item.tl;          // one still frame (live: false)
                        }
                    } else {
                        oldSnap.shown = false; oldOut.stop(); oldSnap.oldTl = null;
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
                    oldSnap.oldTl = null;
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
                        if (it.kind === "app" && it.pinned && (!it.special || it.special === "apps")) n++;
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
                    dragTail = index >= pinnedCount();
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
                    // from its default spot "Apps" only moves once it is dropped among the pinned icons
                    if (dragTail) { dragTarget = (t >= P) ? dragIndex : t; return; }
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
                    dragTail = false;
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
                readonly property bool active: dragging || (hh.hovered && !tucked && (hh.point.position.y > activeTop || (menuOpen && hh.point.position.y > menu.y)))
                property real strength: active ? 1 : 0
                Behavior on strength { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                HoverHandler {
                    id: hh
                    onPointChanged: {
                        if (!hovered || ui.dragging) return;
                        ui.rawMx = point.position.x;
                        if (ui.strength < 0.02) ui.mx = ui.rawMx;     // coming in from outside: start under the pointer
                    }
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
                    active: root.backdropLoaded
                    // opaque wrapper: translucent windows (btop in a transparent terminal, Settings...) leave alpha < 1 in the backdrop,
                    // which made the Dock's hover label / right-click menu see-through to the REAL screen (sharp, weakly blurred).
                    // The backdrop is rendered once into the wrapper over an opaque base, so the glass always gets alpha 1.
                    sourceComponent: Item {
                        id: flatRoot
                        x: 0
                        y: -(win.modelData.height - ui.height)
                        width: win.modelData.width
                        height: win.modelData.height
                        Rectangle { x: -160; y: -160; width: parent.width + 320; height: parent.height + 320; color: "#000000" }
                        ShaderEffectSource {
                            id: flatSrc
                            anchors.fill: parent
                            sourceItem: bd
                            live: !ui.tucked
                            hideSource: false
                        }
                        // Edge padding: the glass blurs and refracts up to ~64 px beyond the screen edge, where the backdrop used to be empty (alpha 0),
                        // which pulled the blur toward see-through near the screen edges (e.g. popovers on the right). Mirror the edge pixels outward instead.
                        ShaderEffectSource { x: flatRoot.width; y: 0; width: 160; height: flatRoot.height; sourceItem: flatSrc; sourceRect: Qt.rect(flatRoot.width - 160, 0, 160, flatRoot.height); textureMirroring: ShaderEffectSource.MirrorHorizontally; live: !ui.tucked; hideSource: false }
                        ShaderEffectSource { x: -160; y: 0; width: 160; height: flatRoot.height; sourceItem: flatSrc; sourceRect: Qt.rect(0, 0, 160, flatRoot.height); textureMirroring: ShaderEffectSource.MirrorHorizontally; live: !ui.tucked; hideSource: false }
                        ShaderEffectSource { x: 0; y: -160; width: flatRoot.width; height: 160; sourceItem: flatSrc; sourceRect: Qt.rect(0, 0, flatRoot.width, 160); textureMirroring: ShaderEffectSource.MirrorVertically; live: !ui.tucked; hideSource: false }
                        ShaderEffectSource { x: 0; y: flatRoot.height; width: flatRoot.width; height: 160; sourceItem: flatSrc; sourceRect: Qt.rect(0, flatRoot.height - 160, flatRoot.width, 160); textureMirroring: ShaderEffectSource.MirrorVertically; live: !ui.tucked; hideSource: false }
                    Item {
                        id: bd
                        x: 0; y: 0
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
                            id: wrep
                            model: wm
                            delegate: Item {
                                id: gw
                                property alias cap: sc
                                required property string addr
                                required property real wx
                                required property real wy
                                required property real ww
                                required property real wh
                                required property real wz
                                required property bool gone      // window closed / left this workspace: hidden at once, its capture is released shortly after
                                x: wx; y: wy; width: ww; height: wh; z: wz
                                visible: !gone                    // a window of the workspace we just left must not linger behind the Dock
                                onGoneChanged: if (!gone && !sc.wantLive && sc.armed) sc.snap()
                                // the closing window's own capture stops the moment Hyprland announces the close
                                readonly property bool closing: !!root.hub && root.hub.closingWins[String(addr || "").replace(/^0x/i, "").trim().toLowerCase()] === true
                                readonly property var tl: { if (!root.hub || gone || closing || root.backdropDraining) return null; var t = root.hub.tlTick; return root.hub.tlFor(addr); }
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
                                // SafeCapture (not a Loader + bare ScreencopyView): a capture is never destroyed while a frame is in flight.
                                // `want` going null stops the stream at once but keeps the source for a moment (see SafeCapture.qml); that is
                                // what used to crash the shell when a window was closed soon after it opened.
                                GlassCapture {
                                    id: sc
                                    anchors.fill: parent
                                    placeholder: (root.bar ? root.bar.darkMode : true) ? "#1e1e20" : "#f2f2f7"
                                    glassOn: !ui.tucked
                                    want: (gw.near && !gw.gone && !gw.closing && !root.backdropDraining) ? gw.tl : null
                                    // Real-time glass ON: a window that reaches the Dock STREAMS (live: every frame the compositor renders), windows
                                    // elsewhere refresh at 30 Hz-ish single shots (5 Hz when far away) so they are fresh the moment they slide under the Dock.
                                    // Real-time glass OFF: the old behaviour (15 fps polling, paused while windows open / close).
                                    readonly property bool quiet: root.backdropDraining || root.glassHold || (!!root.hub && root.hub.captureQuiet)
                                    readonly property bool canRun: !quiet && !ui.menuOpen && !gw.gone && !gw.closing && (root.glassRT
                                        ? !(root.bar && root.bar.gaming)
                                        : !ui.tucked)
                                    hold: quiet || gw.gone || gw.closing
                                    wantLive: root.glassRT && canRun && gw.overlap && !ui.tucked
                                    Timer {
                                        interval: root.glassRT ? (gw.overlap ? 33 : (ui.tucked ? 3000 : 1200)) : 66
                                        repeat: true
                                        running: sc.canRun && !sc.wantLive && sc.armed && (!ui.tucked || gw.overlap)
                                        onTriggered: sc.snap()
                                    }
                                    onHeldChanged: { if (held !== null && sc.canRun) firstShot.restart(); }
                                    Timer {
                                        id: firstShot
                                        interval: 60
                                        onTriggered: { if (sc.armed && !sc.wantLive && sc.canRun) sc.snap(); }
                                    }
                                }
                            }
                        }

                        // The layout changed (a window opened / closed / was re-tiled): Hyprland fails the running captures of the windows that moved.
                        // About 0.3 / 0.6 / 0.9 s later every capture that lost its picture is rebuilt at once and the others take a fresh frame, so the Dock
                        // glass follows the windows while they slide into place.
                        property int settleN: 0
                        // off unless MACSHELL_BURST=1 is set in the environment: the extra rebuilds / frames right after a layout change are experimental
                        function burst() { if (Quickshell.env("MACSHELL_BURST") !== "1") return; settleN = 0; glassSettle.restart(); }
                        function rearm() {
                            for (var q = 0; q < wrep.count; q++) {
                                var it = wrep.itemAt(q);
                                if (!it || !it.cap || it.gone || !it.cap.canRun) continue;
                                it.cap.kick();
                                if (!it.cap.wantLive) it.cap.snap();
                            }
                        }
                        Timer {
                            id: glassSettle
                            interval: 300; repeat: true
                            onTriggered: { bd.rearm(); if (++bd.settleN >= 3) stop(); }
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
                                var cur = wm.get(j), a = cur.addr;
                                if (want[a] === undefined) { if (!cur.gone) { wm.setProperty(j, "gone", true); sweep.restart(); } }
                                else {
                                    var nw = want[a];
                                    if (cur.wx !== nw.wx || cur.wy !== nw.wy || cur.ww !== nw.ww || cur.wh !== nw.wh || cur.wz !== nw.wz || cur.gone !== nw.gone)
                                        wm.set(j, nw);
                                    delete want[a];
                                }
                            }
                            for (var k in want) wm.append(want[k]);
                            bd.lastCount = wm.count;
                        }
                        Timer {
                            id: sweep
                            interval: 700
                            onTriggered: {
                                var retry = false;
                                for (var q = wm.count - 1; q >= 0; q--) {
                                    if (!wm.get(q).gone) continue;
                                    var it = wrep.itemAt(q);
                                    if (it && it.cap && it.cap.held !== null) { retry = true; continue; }
                                    wm.remove(q);
                                }
                                bd.lastCount = wm.count;
                                if (retry) restart();
                            }
                        }
                        property int lastCount: -1
                        Connections {
                            target: root
                            function onGlassClientsChanged() { bd.sync(); bd.burst(); }
                            function onMonDataChanged() { bd.sync(); }
                        }
                        Component.onCompleted: sync()
                    }
                    }
                }

                Item {
                    id: maskItem
                    // The input region only changes in 64 px steps while the Dock breathes under magnification (it used to follow dock.width
                    // exactly: a new Wayland input region every frame of every pointer move). Always a superset of the Dock.
                    readonly property real maskW: hh.hovered ? Math.min(ui.width, Math.ceil((dock.width + 8) / 64) * 64) : dock.width
                    x: ui.menuOpen ? 0 : (ui.width - maskW) / 2
                    width: ui.menuOpen ? ui.width : maskW
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

                            // The backdrop is captured over a FIXED rectangle: the Dock at its widest (fully magnified), in 128 px steps, centred on the
                            // Dock. It used to follow dock.width, and the Dock gets wider and narrower with every pointer move while icons magnify, so
                            // 3-5 GPU textures (this capture, both blur passes, the blur's own buffers) were re-allocated on EVERY pointer move, and
                            // the more icons were pinned the bigger they were. That was the stutter / lag of the magnification. Now the textures keep
                            // their size and only the shader's offset moves.
                            readonly property real magExtra: root.iconSize * (root.effMag - 1) * (root.magRadius / (root.iconSize + root.spacing) + 1)
                            readonly property real capInner: Math.min(Math.ceil(Math.max(dock.width, root.totalW0 + 2 * root.hPad + magExtra) / 128) * 128,
                                                                      win.modelData.width + 320 - 2 * (padPx + margin))   // the mirrored edge padding is 160 px each side
                            readonly property real capW: capInner + 2 * (padPx + margin)
                            readonly property real capH: dock.height + 2 * (padPx + margin)
                            readonly property real capX: (ui.width - capW) / 2                                   // the Dock is centred in the window
                            readonly property real capY: ui.height - root.margin - dock.height + (win.modelData.height - ui.height) - padPx - margin   // untucked position
                            ShaderEffectSource {
                                id: bsrc
                                sourceItem: glassBackdrop.item
                                hideSource: true
                                live: !ui.tucked && !ui.menuOpen
                                visible: false
                                sourceRect: Qt.rect(dg.capX, dg.capY, dg.capW, dg.capH)
                                textureSize: Qt.size(Math.max(1, Math.round(dg.capW * dg.ds)), Math.max(1, Math.round(dg.capH * dg.ds)))
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
                                live: !ui.tucked && !ui.menuOpen
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
                                live: !ui.tucked && !ui.menuOpen
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
                                property vector2d srcSize: Qt.vector2d(dg.capW, dg.capH)
                                // where this item's top-left sits inside the (fixed) capture; follows the Dock as it widens / tucks
                                property vector2d srcOffset: Qt.vector2d(dock.x - padPx - dg.capX,
                                                                         dock.y + (win.modelData.height - ui.height) - padPx - dg.capY)
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

                    // The dark hairline of the real macOS Dock: ~1.5 px wide, centred ON the edge of the glass (half outside, half inside),
                    // about 12% dark along the straight left and right sides, easing out around the corners until it is gone where the
                    // top and bottom edges start (those carry the bright line from the glass shader instead). Plain black with alpha, so it
                    // darkens whatever is behind it and follows the wallpaper. The canvas is 3 px larger than the Dock on every side so
                    // the outer half of the line can be drawn; it only repaints when the Dock's size, corner radius or mode changes.
                    // Drawn as two small end caps (left, right = mirrored) instead of one Canvas over the whole Dock. The hairline fades out
                    // within one corner radius of each end and the Dock's HEIGHT never changes, so a cap looks the same whatever the width. The old
                    // full-width Canvas repainted (a CPU raster + texture upload) on every pointer move while the Dock widened under magnification,
                    // and the wider the Dock (more pinned apps) the slower that got. The caps are painted once (again on size / radius change).
                    Repeater {
                        model: 2
                        delegate: Canvas {
                            id: cap
                            required property int index
                            readonly property real fadeW: Math.min(root.cornerRadius, root.bgHeight / 2) * 1.05
                            anchors.top: parent.top;       anchors.topMargin: -3
                            anchors.bottom: parent.bottom; anchors.bottomMargin: -3
                            width: Math.ceil(3 + fadeW) + 3
                            antialiasing: true
                            // index 0 hugs the left edge; index 1 is the same picture mirrored on the right edge
                            x: index === 0 ? -3 : parent.width + 3 - width
                            transform: Scale { origin.x: cap.width / 2; xScale: cap.index === 0 ? 1 : -1 }
                            readonly property real strength: root.dockDark ? 0.14 : 0.12
                            onStrengthChanged: requestPaint()
                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()
                            Connections { target: root; function onCornerRadiusChanged() { cap.requestPaint(); } }
                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.reset();
                                var m = 3, H = height;
                                var h = H - 2 * m;                         // the Dock's height
                                if (h < 4) return;
                                var r = Math.max(2, Math.min(root.cornerRadius, h / 2));
                                var fade = r * 1.05;
                                // paint as if the Dock were wide: only its near end shows inside this narrow canvas
                                var w = 2 * (fade + r) + 8;
                                var g = ctx.createLinearGradient(m, 0, m + w, 0);
                                var N = 24;
                                for (var k = 0; k <= N; k++) {
                                    var u = k / N, sm = u * u * u * (u * (u * 6 - 15) + 10), al = (strength * (1 - sm)).toFixed(4);
                                    g.addColorStop(u * fade / w, "rgba(0,0,0," + al + ")");
                                    g.addColorStop(1 - u * fade / w, "rgba(0,0,0," + al + ")");
                                }
                                ctx.strokeStyle = g;
                                ctx.lineWidth = 1.6;
                                ctx.beginPath();
                                ctx.moveTo(m + r, m);
                                ctx.lineTo(m + w - r, m);
                                ctx.arc(m + w - r, m + r, r, 1.5 * Math.PI, 2 * Math.PI, false);
                                ctx.lineTo(m + w, m + h - r);
                                ctx.arc(m + w - r, m + h - r, r, 0, 0.5 * Math.PI, false);
                                ctx.lineTo(m + r, m + h);
                                ctx.arc(m + r, m + h - r, r, 0.5 * Math.PI, Math.PI, false);
                                ctx.lineTo(m, m + r);
                                ctx.arc(m + r, m + r, r, Math.PI, 1.5 * Math.PI, false);
                                ctx.closePath();
                                ctx.stroke();
                            }
                        }
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
                                readonly property bool canDrag: !isSep && ((modelData.pinned === true && !modelData.special) || modelData.special === "apps")
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
                                readonly property string winAddr: { if (!thumbWin) return ""; var h = ui.hyprOf(thumbWin); return h ? String(h.address || "").replace(/^0x/i, "").trim().toLowerCase() : ""; }
                                readonly property bool closingWin: winAddr !== "" && root.hub && root.hub.closingWins[winAddr] === true
                                onThumbWinChanged: if (thumbWin !== heldTl) heldTl = thumbWin
                                readonly property bool useThumb: thumbWin !== null
                                readonly property bool thumbReady: useThumb && !leavingCell && !closingWin && sv.hasContent === true && sv.held !== null && sv.held === sv.want

                                property real dx: {
                                    if (!ui.dragging) return 0;
                                    if (isSep && !ui.dragTail) return 0;
                                    if (isDragged) return ui.dragDelta;
                                    return ui.shiftFor(index);
                                }
                                Behavior on dx {
                                    enabled: !cell.isDragged
                                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                                }
                                transform: Translate { x: cell.dx }
                                z: isDragged ? 100 : 0

                                readonly property Item iconImg: img
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
                                    // Empty Trash shake: rotation (deg), pivot at the icon's bottom
                                    property real wob: 0
                                    // lifted while an icon from the desktop is held over the Trash (drop it to throw it away)
                                    property real armLift: (ui.trashArmed && cell.modelData.special === "trash") ? root.iconSize * 0.22 : 0
                                    Behavior on armLift { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    // icon art drawn at ~99%: the dock and the cells keep their size. Whole pixels only: at rest this was
                                    // 51.48 px wide and centred on a fractional x, so the GPU re-sampled the icon texture (blurry) until the
                                    // magnification made it big enough that the blur was no longer noticeable
                                    readonly property real full: Math.max(1, Math.round(root.iconSize * 0.99 * cell.s * cell.appear))
                                    width: cell.useThumb ? full : Math.max(1, Math.round(full * root.iconScale))
                                    height: width
                                    readonly property real tile: width - 2 * Math.round(width * 0.0975) + 2
                                    x: Math.round((parent.width - width) / 2)
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: Math.round(lift + armLift) + Math.round((full - width) / 2)
                                    source: cell.isSep ? "" : root.cellIconSrc(cell.modelData)
                                    sourceSize: Qt.size(Math.ceil(root.iconSize * root.magnification * 1.25),
                                                        Math.ceil(root.iconSize * root.magnification * 1.25))
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                    asynchronous: true
                                }
                                MultiEffect {
                                    id: iconFx
                                    visible: !cell.isSep && !cell.thumbReady
                                    z: 1
                                    maskSource: tileMask
                                    maskThresholdMin: 0.5
                                    maskSpreadAtMin: 1.0
                                        source: img
                                        anchors.fill: img
                                        rotation: img.wob
                                        shadowEnabled: false
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

                                IconClass {
                                    id: domCanvas
                                    icon: root.iconTile && !cell.isSep && !cell.thumbReady ? img : null
                                    corner: root.iconCorner
                                    power: root.iconPower
                                }
                                Item {
                                    id: tileMask
                                    width: img.width
                                    height: img.height
                                    visible: false
                                    layer.enabled: true
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: width * 0.245
                                        color: "black"
                                    }
                                }
                                Rectangle {
                                    id: tileFill
                                    width: img.tile
                                    height: width
                                    color: domCanvas.dom
                                    visible: false
                                    layer.enabled: true
                                }
                                MultiEffect {
                                    id: fillFx
                                    source: tileFill
                                    width: tileFill.width
                                    height: width
                                    saturation: root.iconTint ? -0.75 * root.iconTintStrength : 0.0
                                    colorization: root.iconTint ? 1.0 * root.iconTintStrength : 0.0
                                    brightness: (ma.pressed ? -0.3 : 0.0) + (root.iconTint ? 0.14 * root.iconTintStrength : 0.0)
                                    contrast: root.iconTint ? 0.04 * root.iconTintStrength : 0.0
                                    colorizationColor: root.iconTintColor
                                }
                                ShaderEffectSource {
                                    id: fillTex
                                    readonly property bool needed: root.iconTile && !cell.isSep && !cell.thumbReady
                                    sourceItem: needed ? fillFx : null
                                    hideSource: true
                                    live: needed && !ui.tucked
                                    visible: false
                                }
                                ShaderEffect {
                                    visible: root.iconTile && !cell.isSep && !cell.thumbReady
                                    anchors.centerIn: img
                                    width: tileFill.width
                                    height: width
                                    z: 0
                                    property variant source: fillTex
                                    property vector2d itemSize: Qt.vector2d(width, height)
                                    property real power: root.iconPower
                                    property real box: 1.0
                                    property real fillCorner: 0
                                    property real soft: root.iconEdge
                                    property vector4d radii: root.iconRadii
                                    fragmentShader: Qt.resolvedUrl("iconclip.frag.qsb")
                                }
                                ShaderEffect {
                                    visible: !cell.isSep && !cell.thumbReady
                                    anchors.centerIn: img
                                    width: img.tile
                                    height: width
                                    z: 2
                                    property vector2d itemSize: Qt.vector2d(width, height)
                                    property real power: root.iconPower
                                    property vector4d radii: root.iconRadii
                                    property real strength: root.iconRim
                                    property real soft: root.iconEdge
                                    fragmentShader: Qt.resolvedUrl("iconrim.frag.qsb")
                                    opacity: root.iconTile ? 1 : 0
                                }
                                ShaderEffectSource {
                                    id: iconTex
                                    readonly property bool needed: root.iconTile && !cell.isSep && !cell.thumbReady
                                    sourceItem: needed ? iconFx : null
                                    hideSource: root.iconTile
                                    live: needed && !ui.tucked
                                    smooth: true
                                    mipmap: true
                                    visible: false
                                }
                                ShaderEffect {
                                    visible: root.iconTile && !cell.isSep && !cell.thumbReady
                                    anchors.fill: img
                                    z: 1
                                    scale: ((domCanvas.proper || domCanvas.square) ? img.tile / img.width : 0.66 * domCanvas.fit) / norm
                                    property variant source: iconTex
                                    property vector2d itemSize: Qt.vector2d(width, height)
                                    property real power: root.iconPower
                                    property real norm: domCanvas.art >= 0.8 ? domCanvas.art : (domCanvas.proper ? 0.88 : 1.0)
                                    property real box: (domCanvas.proper || domCanvas.square) ? norm : 2.0
                                    property real soft: root.iconEdge
                                    property real fillCorner: domCanvas.proper ? 1.0 : 0.0
                                    property vector4d radii: root.iconRadii
                                    fragmentShader: Qt.resolvedUrl("iconclip.frag.qsb")
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
                                    SafeCapture {
                                        id: sv
                                        anchors.centerIn: parent
                                        want: ((root.hub && !root.hub.windowCapture) || cell.closingWin || cell.leavingCell) ? null : cell.heldTl
                                        graceMs: 220        // strictly shorter than leaveMs + 30 (370 ms), so held is always null before cell is destroyed
                                        hold: root.previewHold || cell.closingWin || cell.leavingCell || (!!root.hub && root.hub.churn)
                                        healOnResize: false
                                        // live only while the pointer is on the Dock (where you look at them); otherwise one fresh
                                        // frame every 2 s — live previews of every window were ~8% CPU at idle
                                        wantLive: !ui.tucked && !root.previewHold && !cell.closingWin && !cell.leavingCell && hh.hovered
                                        Timer {
                                            interval: 4000; repeat: true; triggeredOnStart: true
                                            running: !sv.wantLive && !ui.tucked && !root.previewHold && !cell.closingWin && sv.armed
                                            onTriggered: sv.snap()
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
                                // something was just thrown into the Trash: the icon hops once and settles with a small bounce
                                Connections {
                                    target: ui
                                    function onTrashKickChanged() { if (cell.modelData.special === "trash" && !ui.tucked) { trashHop.restart(); } }
                                }
                                SequentialAnimation {
                                    id: trashHop
                                    NumberAnimation { target: img; property: "lift"; to: root.iconSize * 0.30; duration: 150; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: img; property: "lift"; to: 0; duration: 420; easing.type: Easing.OutBounce }
                                }

                                // ── Empty Trash: a short shake and one hop ──
                                Connections {
                                    target: ui
                                    function onTrashEmptyKickChanged() { if (cell.modelData.special === "trash" && !ui.tucked) trashEmpty.restart(); }
                                }
                                SequentialAnimation {
                                    id: trashEmpty
                                    NumberAnimation { target: img; property: "wob"; to: -7; duration: 70 }
                                    NumberAnimation { target: img; property: "wob"; to: 7; duration: 110 }
                                    NumberAnimation { target: img; property: "wob"; to: 0; duration: 80 }
                                    NumberAnimation { target: img; property: "lift"; to: root.iconSize * 0.34; duration: 160; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: img; property: "lift"; to: 0; duration: 420; easing.type: Easing.OutBounce }
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

                                // ── hover label ──
                                // macOS Tahoe style: a heavily blurred Liquid Glass bubble with a pointer tail, light / dark with the system
                                // appearance, sized from the Dock (see DockGlassPanel.qml). It is only built while it is shown.
                                // The label is a whole glass bubble (3 canvases, a masked blur capture, a shadow). It used to be built for EVERY icon the
                                // pointer crossed, so a fast sweep over many pinned apps built and tore down a bubble per icon (a hitch each): that was the
                                // "laggy when the mouse moves a bit fast, worse with many apps". It now appears once the pointer rests on an icon for a moment.
                                property bool hoverSettled: false
                                Timer { id: tipDwell; interval: 90; running: ma.containsMouse && !cell.isSep; onTriggered: cell.hoverSettled = true }
                                Connections { target: ma; function onContainsMouseChanged() { if (!ma.containsMouse) cell.hoverSettled = false; } }
                                readonly property bool tipOn: root.showLabels && !cell.isSep && cell.hoverSettled && ma.containsMouse && !ma.pressed && !ui.menuOpen && !ui.dragging
                                Loader {
                                    id: tip
                                    z: 10
                                    opacity: cell.tipOn ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                    active: cell.tipOn || opacity > 0
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    // (no explicit width / height: the Loader takes the bubble's size from it)
                                    // the tail's tip sits just above the icon (above the magnified / bouncing icon, too)
                                    y: cell.height - img.height - img.lift - height - Math.round(9 * root.labelK)
                                    sourceComponent: DockGlassPanel {
                                        id: lp
                                        readonly property string title: cell.isSep ? "" : ((cell.modelData.kind === "win" && cell.modelData.tl && cell.modelData.tl.title) ? cell.modelData.tl.title : cell.modelData.name)
                                        // a window cell names its window and, underneath, the app it belongs to
                                        readonly property string sub: (!cell.isSep && cell.modelData.kind === "win" && cell.modelData.name && cell.modelData.name !== title) ? cell.modelData.name : ""
                                        readonly property real fs: Math.max(9, Math.round(13 * k))
                                        backdrop: glassBackdrop.item
                                        live: root.liquidActive && glassBackdrop.item !== null
                                        dark: root.darkMode
                                        k: root.labelK
                                        radius: Math.min(11.7 * k, bodyH / 2)
                                        tailW: 21 * k
                                        tailH: 5.8 * k
                                        tailTipR: 2.4 * k
                                        bodyH: sub !== "" ? 32 * k : 26 * k
                                        width: Math.ceil(Math.max(tt.width, st.visible ? st.width : 0)) + 2 * Math.round(12 * k)

                                        Text {
                                            id: tt
                                            text: lp.title
                                            width: Math.min(implicitWidth, Math.round(320 * lp.k))
                                            elide: Text.ElideRight
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.verticalCenter: parent.top
                                            anchors.verticalCenterOffset: lp.sub !== "" ? 9.2 * lp.k : lp.bodyH / 2 + 0.5 * lp.k
                                            color: lp.dark ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(0, 0, 0, 0.86)
                                            font.pixelSize: lp.fs
                                            font.family: root.fontForWeight(Font.Normal, root.fontFamily)
                                        }
                                        Text {
                                            id: st
                                            visible: lp.sub !== ""
                                            text: lp.sub
                                            width: Math.min(implicitWidth, Math.round(320 * lp.k))
                                            elide: Text.ElideRight
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.verticalCenter: parent.top
                                            anchors.verticalCenterOffset: 22.4 * lp.k
                                            color: lp.dark ? Qt.rgba(1, 1, 1, 0.60) : Qt.rgba(0, 0, 0, 0.58)
                                            font.pixelSize: Math.max(8, Math.round(10.2 * lp.k))
                                            font.family: root.fontForWeight(Font.Normal, root.fontFamily)
                                        }
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
                                            ui.menuCell = cell;
                                            ui.menuItem = cell.modelData;
                                            ui.syncMenu();
                                        } else if ((mouse.modifiers & Qt.ShiftModifier) !== 0 && cell.modelData.kind === "app" && !cell.modelData.special
                                                   && root.windowsFor(cell.modelData.key).length > 0 && root.hub && root.hub.mc) {
                                            root.hub.mc.openExpose(cell.modelData.appId || cell.modelData.key, win.modelData.name);
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

                // ── right-click menu ──
                // Same Tahoe Liquid Glass bubble as the hover label: blurred, light / dark, pointer tail towards the icon, scaled with the
                // Dock. Rows are 22 pt with capsule highlights, as in macOS 26.
                DockGlassPanel {
                    id: menu
                    shadow: false
                    z: 60
                    visible: opacity > 0
                    opacity: ui.menuOpen ? 1 : 0
                    scale: ui.menuOpen ? 1 : 0.96
                    transformOrigin: Item.Bottom
                    Behavior on opacity { NumberAnimation { duration: 110 } }
                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                    backdrop: glassBackdrop.item
                    live: root.liquidActive && glassBackdrop.item !== null
                    frozen: ui.menuOpen      // the menu's glass stops updating while it is open
                    dark: root.darkMode
                    k: root.labelK
                    radius: 16 * k
                    tailW: 24 * k
                    tailH: 9 * k
                    tailTipR: 3.6 * k
                    readonly property real pad: Math.round(5 * k)

                    width: ui.menuW
                    bodyH: menuCol.height + 2 * pad
                    x: Math.max(8, Math.min(ui.width - width - 8, ui.menuCx - width / 2))
                    y: ui.menuIconTop >= 0 ? ui.menuIconTop - Math.round(10 * k) - height
                                           : ui.height - root.margin - root.bgHeight - root.iconSize * (root.effMag - 1) - Math.round(10 * k) - height
                    // The tail points at the icon the menu belongs to. Its position along the bubble is locked when the menu opens:
                    // re-evaluating tailX while the menu follows its icon during magnification changed shapeKey on every frame,
                    // repainting all of the bubble's canvases (blurred shadow included) on the CPU and causing severe magnification lag.
                    tailX: ui.menuTailX >= 0 ? ui.menuTailX : width / 2

                    Column {
                        id: menuCol
                        x: menu.pad
                        y: menu.pad
                        width: menu.width - 2 * menu.pad

                        Repeater {
                            model: ui.menuModel

                            delegate: Item {
                                id: mi
                                required property var modelData
                                readonly property bool isSep: modelData.kind === "sep"
                                readonly property bool off: !isSep && modelData.disabled === true
                                readonly property bool armedNow: !isSep && modelData.confirm === true && ui.armed === modelData.label
                                width: menuCol.width
                                height: isSep ? Math.round(11 * menu.k) : Math.round(22 * menu.k)

                                Rectangle {
                                    visible: mi.isSep
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: 1
                                    color: menu.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)
                                }
                                Rectangle {
                                    visible: !mi.isSep && !mi.off && mia.containsMouse
                                    anchors.fill: parent
                                    radius: Math.round(8 * menu.k)          // softly rounded selection
                                    color: mi.armedNow ? "#FF453A" : root.accent
                                }
                                Text {
                                    visible: !mi.isSep
                                    x: Math.round(11 * menu.k)
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 2 * Math.round(11 * menu.k)
                                    elide: Text.ElideRight
                                    text: mi.isSep ? "" : (mi.armedNow ? I18n.tr("Click again to confirm") : I18n.tr(mi.modelData.label))
                                    color: (!mi.isSep && !mi.off && mia.containsMouse) ? "white"
                                         : (mi.off ? (menu.dark ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(0, 0, 0, 0.28))
                                                   : (menu.dark ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(0, 0, 0, 0.86)))
                                    font.pixelSize: Math.max(9, Math.round(13 * menu.k))
                                    font.family: root.fontForWeight(Font.Normal, root.fontFamily)
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
