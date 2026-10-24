// macbar — a macOS Tahoe style menu bar for Hyprland, built on Quickshell.
//
// Part of the combined macbar + macdock shell (see shell.qml). Keep this file, MacDock.qml, shell.qml,
// liquidglass.frag and apple-logo-*.svg together in ~/.config/quickshell/macbar/ and run:  qs -c macbar
//
// Settings live in ~/.config/macbar/settings.json (Apple menu → System Settings…, or Control Center → Edit Controls).
// On first run, appearance (dark mode, accent, font, glass tuning, wallpaper) is inherited from macdock's settings.json.
//
// Hyprland (hyprland.conf syntax):
//   windowrule = float, title:^(macbar Settings)$
//   windowrule = center, title:^(macbar Settings)$
//   layerrule  = blur, macspot          (Spotlight is its own layer; the bar itself needs no blur rule)
//   layerrule  = ignorealpha 0.05, macspot
//   # the bar's background is its own layer ("macbarbg", under the bar): blur it with Hyprland like this
//   layerrule  = blur, macbarbg
//   layerrule  = ignorealpha 0.05, macbarbg
// Hyprland (Lua):
//   hl.layer_rule({ name = "macspot", match = { namespace = "macspot" }, blur = true, ignore_alpha = 0.05, no_anim = true })
//   hl.layer_rule({ name = "macbarbg", match = { namespace = "macbarbg" }, blur = true, ignore_alpha = 0.05, no_anim = true })
//
// Optional tools used by the Control Center:
//   nmcli (Wi-Fi / VPN / Ethernet), pactl (audio device routing), hyprctl (keyboard layouts), pw-dump (privacy dots),
//   wf-recorder (screen recording), hyprpicker (color picker), bluetoothctl (Bluetooth), brightnessctl (Display), hyprsunset (Night Shift),
//   systemd-inhibit (Keep Awake), grim + slurp + wl-copy + notify-send (File → Screenshot),
//   man / xdg-open (Help), wl-clipboard + cliphist (Spotlight → Clipboard, Emoji),
//   wtype (only if you set keysViaWtype: true; menu shortcuts are otherwise sent with Hyprland's sendshortcut),
//   rfkill (Airplane mode), dunstctl / makoctl / swaync-client (Focus). Missing tools just do nothing.
//
// Wi-Fi: click the Wi-Fi icon in the bar (or the Wi-Fi tile in Control Center) for a list of nearby networks (nmcli).
//
// Notifications: the bar is also a notification daemon (org.freedesktop.Notifications). Stop dunst / mako / swaync first,
// e.g. `systemctl --user disable --now dunst`, otherwise only one of them can own the D-Bus name. Popups appear top right in
// Liquid Glass; the bell in the bar opens the "Notification system" panel (history, delete, Clear All, Do Not Disturb).
// Test with: notify-send "Fitness" "Move goal achieved"
//
// Spotlight (the search icon) is built in and drawn in Liquid Glass. Bind it to a key with:
//   bind = ALT, space, exec, qs -c macbar ipc call spotlight toggle
// Hyprland (Lua):
//   hl.bind("ALT + Space", hl.dsp.exec_cmd("qs -c macbar ipc call spotlight toggle"))
//   Reduced motion: set "reduceMotion": true in ~/.config/macbar/settings.json to turn off Spotlight's pop / stagger / slide animations.
// Wallpapers: Ctrl+Alt+W opens the wallpaper picker (Liquid Glass). Bind it with:
//   hl.bind("CTRL + ALT + W", hl.dsp.exec_cmd("qs -c macbar ipc call wallpapers toggle"))
//   (hyprlang:  bind = CTRL ALT, W, exec, qs -c macbar ipc call wallpapers toggle)
// Folder: ~/Pictures/Wallpapers by default (change it inside the picker, or "wallpaperDir" in settings.json).
// Star a wallpaper to pin it to the top. Applied through Noctalia / awww / swww / hyprpaper, or your own "wallpaperCmd" ({} = image path).
// Clipboard history + Emoji live inside Spotlight (the clipboard and smiley buttons next to the search field):
//   needs wl-clipboard + cliphist (this shell starts the `wl-paste --watch cliphist store` watchers itself, unless you already run them).
//   bind = SUPER, V, exec, qs -c macbar ipc call spotlight clipboard       # Clipboard history (replace any default SUPER+V bind)
//   bind = SUPER, period, exec, qs -c macbar ipc call spotlight emoji      # Emoji picker
// Hyprland (Lua):
//   hl.bind("SUPER + V", hl.dsp.exec_cmd("qs -c macbar ipc call spotlight clipboard"))
//   hl.bind("SUPER + period", hl.dsp.exec_cmd("qs -c macbar ipc call spotlight emoji"))
//   (use the same `qs -c <name>` prefix you use for the Spotlight bind; `ipc call spotlight apps` opens the Applications panel)
// Return pastes the entry into the focused app, Shift+Return only copies it, Delete removes it from the history.
// Files runs filesCmd.
//
// Screenshots (Print key): the screen freezes and dims, drag to select an area (a size badge follows the pointer), release to capture.
// Return/Space = whole screen, Esc or right-click = cancel. Where it is saved (and clipboard / notification) is in System Settings → Menu Bar.
//   bind = , Print, exec, qs -c macbar ipc call screenshot region
//   bind = SHIFT, Print, exec, qs -c macbar ipc call screenshot screen
//   bind = ALT, Print, exec, qs -c macbar ipc call screenshot window
// Hyprland (Lua):
//   hl.bind("Print", hl.dsp.exec_cmd("qs -c macbar ipc call screenshot region"))
// Optional (no fade on the picker):  layerrule = noanim, macshot   (Lua: hl.layer_rule({ name = "macshot", match = { namespace = "macshot" }, no_anim = true }))
// Needs grim (and wl-clipboard for the clipboard copy).

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Services.Notifications
import "EmojiData.js" as EmojiData
import "I18n.js" as I18n
import "Fonts.js" as Fonts

Scope {
    id: root

    // shared helpers from shell.qml (window geometry poller, wallpaper lookup)
    property var hub: null
    // true while a screen recording / screen share runs: the glass's live window captures sit out (see shell.qml: hub.captureQuiet)
    readonly property bool captureQuiet: hub ? hub.captureQuiet : recording
    // windows opening / closing: the glass's live captures pause (it keeps its last frame; the source stays attached) - see shell.qml: hub.glassHold
    readonly property bool captureHeld: hub ? hub.glassHold : false

    // ───────────── CONFIG (all persisted to settings.json) ─────────────
    property bool barEnabled: true           // the menu bar strip itself
    // every part of the shell can be switched off on its own (the installer's feature picker writes these too)
    property bool spotlightEnabled: true     // Spotlight (the magnifier / its keybind)
    property bool reduceMotion: false        // Spotlight: no pop / stagger / slide animations (settings.json: "reduceMotion": true)
    property bool ccEnabled: true            // Control Center
    property string ccStyle: "tiles"         // tiles = every control its own glass | macos = one frosted panel behind them
    property bool notificationsEnabled: true // banners + Notification Center (off = no D-Bus daemon at all, so mako/dunst can take over)
    property bool clockAppEnabled: true      // the Clock app (alarms and timers still ring while it is on)
    readonly property bool barLayerNeeded: barEnabled || spotlightEnabled || ccEnabled || notificationsEnabled
    property bool darkMode: true             // the resolved look (true = dark); follows appearanceMode
    property string appearanceMode: "dark"   // light | dark | auto (auto = light by day, dark by night)
    // Panels (top bar menus / popovers, Spotlight, Control Center, notifications) are light or dark by what is BEHIND them
    // (panelTone, measured live, see "Auto contrast" below); the Light / Dark / Auto setting is the fallback while nothing is
    // measured yet and the tie-break when the backdrop is neither clearly bright nor clearly dark.
    // Readability only ever changes the TEXT: panelDarkMode (glass tint, cards, borders) always follows the Light / Dark setting,
    // while panelTextWhite (text + glyph colour) follows the measured backdrop.
    readonly property bool panelDarkMode: darkMode
    readonly property bool panelTextWhite: (autoContrast && panelTone !== 0) ? (panelTone === -1) : darkMode
    property color accent: "#0A84FF"
    // The UI font is Open Runde (bundled in assets/fonts, loaded by shell.qml). Settings that still say Inter move over to it.
    property string fontFamily: "Open Runde"
    readonly property string boldFontFamily: hub && hub.boldFontFamily ? hub.boldFontFamily : "Open Runde Semibold"
    // Open Runde: bold text uses its Semibold face; another selected font keeps its own family (and real bold weight)
    function fontForWeight(weight, regularFamily) { return (Number(weight) >= Font.DemiBold && regularFamily === "Open Runde") ? boldFontFamily : regularFamily; }
    onFontFamilyChanged: if (fontFamily.indexOf("Inter") === 0) fontFamily = "Open Runde"
    property int barHeight: 28
    // ── UI scale (small screens / laptops) ──
    // uiScaleAuto: shrink everything automatically on screens smaller than 1920x1080 (logical pixels, i.e. after the compositor's own
    // scaling). uiScaleManual: the user's own multiplier from Settings, applied on top. barH is the bar's real height in px.
    property bool uiScaleAuto: true
    property real uiScaleManual: 1.0
    readonly property real autoUiScale: {
        var sc = Quickshell.screens;
        if (!sc || sc.length === 0) return 1;
        var s = sc[0];
        for (var i = 0; i < sc.length; i++) if (sc[i].width * sc[i].height < s.width * s.height) s = sc[i];   // the smallest screen decides
        return Math.max(0.7, Math.min(1, Math.min(s.width / 1920, s.height / 1080)));
    }
    readonly property real uiScale: Math.max(0.5, Math.min(1.25, (uiScaleAuto ? autoUiScale : 1) * uiScaleManual))
    readonly property int barH: Math.max(14, Math.round(barHeight * uiScale))
    // The bar changed size: tiled windows move, so everything that captures the wallpaper / apps behind the bar and its popovers
    // (window geometry, the live backdrop, the screen snapshot, the measured tone behind panels) is refreshed once Hyprland has settled.
    signal barRelayout()
    onBarHeightChanged: { if (settingsReady) barRelayoutT.restart(); }
    Timer {
        id: barRelayoutT; interval: 180
        property int pass: 0
        onTriggered: {
            if (root.hub && root.hub.kickGeo) root.hub.kickGeo();
            root.barRelayout();
            pass++;
            if (pass < 2) restart(); else pass = 0;      // a second pass ~0.5 s later, after the windows finished re-tiling
        }
    }
    property string barLogoMode: "arch"       // "arch", "apple", or "custom"
    property string barCustomLogoPath: ""     // absolute path, ~/path, or file URL for the custom menu-bar logo
    // The bar-size slider scales its widget groups while the left/right groups stay pinned to their corners.
    readonly property real barWidgetScale: Math.max(0.45, Math.min(1.55, barHeight / 28 * uiScale))
    // popovers and the Control Center scale with the same slider (smaller bar -> smaller panels, down to 70 %)
    readonly property real barPopupScale: Math.max(0.5, Math.min(1.25, (1 + (barHeight - 28) / 60) * uiScale))
    property real glassOpacity: 0.42
    property string barStyle: "liquid"        // "liquid" = Apple Liquid Glass popovers, "blur" = flat translucent
    property real glassRim: 0.45
    property real glassGrain: 0.015
    property real glassLiquid: 1.0
    property real glassBlur: 5
    // ── Keyboard / Mouse / Trackpad (Settings): applied live to Hyprland with `hyprctl eval`, remembered here ──
    property int kbRepeatRate: 35
    property int kbRepeatDelay: 250
    property real mouseSens: 0
    property bool mouseNatural: false
    property bool tpNatural: true
    property bool tpTap: true
    property bool tpDwt: true
    property real tpScroll: 0.7
    readonly property string inputSig: [kbRepeatRate, kbRepeatDelay, mouseSens, mouseNatural, tpNatural, tpTap, tpDwt, tpScroll].join("|")
    onInputSigChanged: if (settingsReady) inputApplyT.restart()
    Timer { id: inputApplyT; interval: 150; onTriggered: root.applyInput() }
    function applyInput() {
        function b(v) { return v ? "true" : "false"; }
        Quickshell.execDetached(["hyprctl", "eval", "hl.config({ input = { repeat_rate = " + Math.round(kbRepeatRate) + ", repeat_delay = " + Math.round(kbRepeatDelay)
            + ", sensitivity = " + mouseSens.toFixed(2) + ", natural_scroll = " + b(mouseNatural)
            + ", touchpad = { natural_scroll = " + b(tpNatural) + ", tap_to_click = " + b(tpTap) + ", disable_while_typing = " + b(tpDwt)
            + ", scroll_factor = " + tpScroll.toFixed(2) + " } } })"]);
    }
    // ═════════ AUTO CONTRAST ═════════
    // One measuring script (assets/tone.sh) grabs the real screen (wallpaper + every window) and reports brightness + spread.
    //  • bar: the strip behind the bar → barTone (text / glyphs / glass of the bar and its buttons)
    //  • panels: the area behind the open menu / Control Center / Spotlight → panelTone. While a panel is open the area AROUND
    //    it is re-measured continuously (the panel itself is left out), so opening, closing, moving or switching apps behind it
    //    flips it between light and dark by itself.
    // The choice is made by worst-case contrast (white text on the brightest part vs dark text on the darkest part, spread
    // included), with hysteresis so it never flickers, and falls back to the system look when both read equally well.
    // ═════════ UPDATE CHECK ═════════
    // Only ASKS whether a newer MacShell exists (assets/check-update.sh: the latest release, else VERSION on the main branch of
    // github.com/0-ss/MacShell, compared with the VERSION file of this install). It never downloads or installs anything:
    // the "Update" button just opens updateUrl in the browser.
    readonly property string updateScript: decodeURIComponent(String(Qt.resolvedUrl("assets/check-update.sh")).replace(/^file:\/\//, ""))
    property string updateUrl: "https://github.com/0-ss/MacShell/releases/latest"     // ← the link the "Update" button opens
    property bool updateChecking: false
    property string updateState: ""            // "" = not checked yet | uptodate | available | error
    property string updateVersion: ""          // the new version, e.g. "1.2.0"
    property bool updateDialogOpen: false      // the "New update x.x.x" window in Settings
    property bool updateAnnounce: false        // this check may open that window
    function checkForUpdates(announce) {
        updateAnnounce = announce === true;
        if (updateProc.running) return;
        updateChecking = true;
        updateProc.command = ["sh", updateScript];
        updateProc.running = true;
    }
    function openUpdateLink() { Quickshell.execDetached(["xdg-open", updateUrl]); }
    Process {
        id: updateProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.updateChecking = false;
                var o = null;
                try { o = JSON.parse(text.trim().split("\n").pop()); } catch (e) { o = null; }
                if (!o) { root.updateState = "error"; return; }
                if (o.url) root.updateUrl = String(o.url);
                if (o.status === "available") {
                    root.updateVersion = String(o.latest || "").replace(/^v(?=[0-9])/, "");
                    root.updateState = "available";
                    if (root.updateAnnounce) root.updateDialogOpen = true;
                } else {
                    root.updateState = o.status === "uptodate" ? "uptodate" : "error";
                    root.updateDialogOpen = false;
                }
            }
        }
        onExited: root.updateChecking = false
    }

    readonly property string toneScript: decodeURIComponent(String(Qt.resolvedUrl("assets/tone.sh")).replace(/^file:\/\//, ""))
    // cur: 1 = dark text now (bright backdrop), -1 = white text now, 0 = undecided; v/sd = brightness / spread 0..1
    function pickTone(cur, v, sd, fresh) {
        v = Math.max(0, Math.min(1, v)); sd = Math.max(0, Math.min(0.5, sd || 0));
        var hi = Math.min(1, v + 0.6 * sd), lo = Math.max(0, v - 0.6 * sd);
        var cw = 1.05 / (Math.pow(hi, 2.2) + 0.05);          // contrast of white text on the brightest part
        var cd = (Math.pow(lo, 2.2) + 0.05) / 0.0623;         // contrast of dark text on the darkest part
        if (!fresh && cur === 1) return cw > cd * 1.2 ? -1 : 1;
        if (!fresh && cur === -1) return cd > cw * 1.2 ? 1 : -1;
        if (Math.abs(cw - cd) < 0.08 * Math.max(cw, cd)) return darkMode ? -1 : 1;
        return cd > cw ? 1 : -1;
    }
    property var tonePending: null
    // measure a screen rect (logical coords, in a screen scr); inner (optional) = the panel's own rect, left out of the measurement.
    function measureTone(sx, sy, sw, sh) { measureArea(null, Qt.rect(sx, sy, sw, sh), null, true); }
    function measureArea(scr, rect, inner, fresh) {
        if (!autoContrast) return;
        var x = rect.x, y = rect.y, w = rect.width, h = rect.height;
        if (scr) {                                           // clamp to the screen (grim refuses areas outside the outputs)
            var x1 = Math.max(scr.x, x), y1 = Math.max(scr.y, y), x2 = Math.min(scr.x + scr.width, x + w), y2 = Math.min(scr.y + scr.height, y + h);
            x = x1; y = y1; w = x2 - x1; h = y2 - y1;
        }
        if (w < 8 || h < 8) return;
        var args = [Number(0.1), Math.round(x), Math.round(y), Math.round(w), Math.round(h)];
        if (inner) args.push(Math.round(inner.x), Math.round(inner.y), Math.round(inner.width), Math.round(inner.height));
        var req = { args: args, fresh: fresh === true };
        if (panelToneProc.running) { tonePending = req; return; }
        runPanelTone(req);
    }
    function runPanelTone(req) {
        panelToneProc.fresh = req.fresh;
        panelToneProc.command = ["sh", toneScript].concat(req.args.map(String));
        panelToneProc.running = true;
    }
    // the area around a panel rect (what its glass shows), for measuring while the panel is open
    function measureAround(scr, panelRect, fresh) {
        var m = 160;
        measureArea(scr, Qt.rect(panelRect.x - m, panelRect.y - m, panelRect.width + 2 * m, panelRect.height + 2 * m), panelRect, fresh);
    }
    Process {
        id: panelToneProc
        property bool fresh: false
        stdout: StdioCollector {
            onStreamFinished: {
                var p = text.trim().split(/\s+/);
                var v = parseFloat(p[0]), sd = parseFloat(p[1]);
                if (isNaN(v)) return;
                root.panelTone = root.pickTone(root.panelTone, v, isNaN(sd) ? 0 : sd, panelToneProc.fresh);
            }
        }
        onRunningChanged: if (!running && root.tonePending) { var r = root.tonePending; root.tonePending = null; root.runPanelTone(r); }
    }
    // ── bar text colour: measure what is behind the bar strip (wallpaper + windows + the bar's own glass) ──
    function measureBar() {
        if (!autoContrast || !barEnabled || barToneProc.running) return;
        var sc = Quickshell.screens && Quickshell.screens.length ? Quickshell.screens[0] : null;
        if (!sc) return;
        barToneProc.command = ["sh", toneScript, "0.25", String(Math.round(sc.x)), String(Math.round(sc.y)), String(Math.max(8, Math.round(sc.width))), String(Math.max(8, Math.round(barH)))];
        barToneProc.running = true;
    }
    Timer { id: barToneT; interval: 350; onTriggered: root.measureBar() }          // debounce: after a resize / wallpaper / window change settles
    Timer { interval: 1200; repeat: true; running: root.autoContrast && root.barEnabled && !root.gaming; onTriggered: root.measureBar() }
    Connections {
        target: root
        function onBarHeightChanged() { barToneT.restart(); }
        function onDarkModeChanged() { root.panelTone = 0; barToneT.restart(); }
        function onBarEnabledChanged() { if (root.barEnabled) barToneT.restart(); }
        function onWallpaperAccentChanged() { barToneT.restart(); }
        function onGlassClientsChanged() { barToneT.restart(); }
        function onAutoContrastChanged() { if (root.autoContrast) barToneT.restart(); else { root.barTone = 0; root.panelTone = 0; } }
    }
    Process {
        id: barToneProc
        stdout: StdioCollector {
            onStreamFinished: {
                var p = text.trim().split(/\s+/);
                var v = parseFloat(p[0]), sd = parseFloat(p[1]);
                if (isNaN(v)) return;
                root.barTone = root.pickTone(root.barTone, v, isNaN(sd) ? 0 : sd, false);
            }
        }
    }
    property bool lockArtBackground: true     // lock screen: blurred album art as the background while the cover is enlarged
    // lock screen clock (Settings → Lock Screen → Clock); MacLock reads these when it starts
    property string lockClockStyle: "glass"   // preset last picked: glass | classic | serif | liquid | thin | custom
    property string lockClockFont: "rounded"   // rounded | serif | inter
    property int lockClockWeight: 680
    property string lockClockMaterial: "glass"   // solid (Apple's vibrancy) | glass (Liquid Glass)
    property real lockClockIntensity: 0.6        // solid: how bright / opaque; glass: clear (0) … frosted (1)
    property string lockClockTint: "#FFFFFF"
    property string lockClockDate: "long"        // long ("Friday, October 16") | short ("Fri Oct 16")
    readonly property var lockClockPresets: ({
        glass:   { f: "rounded",   w: 680, m: "glass", i: 0.6,  d: "long" },
        classic: { f: "rounded",   w: 600, m: "solid", i: 0.8,  d: "long" },
        serif:   { f: "serif",     w: 560, m: "solid", i: 0.85, d: "short" },
        liquid:  { f: "rounded",   w: 560, m: "glass", i: 0.12, d: "short" },
        thin:    { f: "rounded",   w: 200, m: "solid", i: 0.6,  d: "short" }
    })
    // the Condensed font is gone: saved settings that still name it move to Rounded
    onLockClockFontChanged: if (lockClockFont === "condensed") Qt.callLater(function () { lockClockFont = "rounded"; })
    // settings saved before Solid / Glass existed: move them over (presets keep their name, the rest map across)
    onLockClockMaterialChanged: Qt.callLater(function () {
        if (lockClockMaterial !== "frosted" && lockClockMaterial !== "liquid") return;
        if (lockClockPresets[lockClockStyle]) { applyLockClockPreset(lockClockStyle); return; }
        lockClockIntensity = lockClockMaterial === "liquid" ? 0.12 : 0.6;
        lockClockMaterial = "glass";
    })
    function applyLockClockPreset(name) {
        var p = lockClockPresets[name]; if (!p) return;
        lockClockFont = p.f; lockClockWeight = p.w; lockClockMaterial = p.m; lockClockIntensity = p.i; lockClockDate = p.d;
        lockClockStyle = name;
    }
    property bool uiSounds: true              // Apple-style UI sounds (volume pop, notification, screenshot, charger, lock)
    property bool gamingMode: false           // Game Mode switched on by hand
    property bool gamingAuto: true            // Game Mode turns itself on while a game is fullscreen
    property bool gamingAutoActive: false
    readonly property bool gaming: gamingMode || gamingAutoActive
    property bool ccMigGame: false            // one-time: add the Game Mode tile to an existing Control Center layout
    property bool barGlass: true              // the bar strip itself is Liquid Glass (needs barStyle "liquid")
    property real barBgOpacity: 0.10          // fill of the separate "macbarbg" layer (0 = layer hidden). Must stay above the layerrule's ignore_alpha (0.05) for Hyprland to blur it
    property bool glassRealtime: false        // live-capture every window all the time; off by default now that popovers refract a screen snapshot       // keep every window capture live all the time (no wallpaper-first delay when a popover opens)
    // Animated wallpaper inside the Liquid Glass (bar, Dock, widgets, Settings): OFF by default. Off = no video decoder exists at all and the
    // glass refracts a still frame of the wallpaper (the wallpaper itself still plays through mpvpaper). On = the glass plays a small
    // low-resolution copy (see glassVideo) so it stays cheap.
    property bool liveWallGlass: false
    property bool glassDebug: false
    property string wallpaperPath: ""
    property bool use24h: true
    property string language: "auto"        // "auto" = the system language, or a code with a table in lang/
    onLanguageChanged: Qt.uiLanguage = language === "auto" ? "" : language
    property bool showDate: true
    property bool showSeconds: false
    property bool showBatteryPercent: true
    property bool showTray: true
    property bool showSearch: true
    property bool weekStartsMonday: false
    property string terminal: "kitty"
    property string launcher: ""              // "" = built-in Spotlight; set a command (rofi, fuzzel, ...) to use an external launcher instead
    property string filesCmd: "xdg-open \"$HOME\""
    property string clipboardCmd: "cliphist list | (fuzzel --dmenu || wofi --dmenu || rofi -dmenu) | cliphist decode | wl-copy"
    property var appUsage: ({})               // launch counts, feeds the "Suggestions" row in Spotlight
    property bool clipHistory: true           // keep a clipboard history for Spotlight → Clipboard (needs wl-clipboard + cliphist)
    property bool clipAutoPaste: true         // after picking a clipboard entry / emoji, paste it into the focused app
    property var emojiRecent: []              // recently used emoji, newest first
    property string screenshotDir: ""         // where screenshots are saved ("" = ~/Pictures/Screenshots)
    property bool screenshotSave: true        // save the PNG to screenshotDir
    property bool screenshotClipboard: true   // also copy it to the clipboard
    property bool screenshotNotify: true      // "Screenshot saved" notification
    property int spotRequest: 0
    property string spotWant: "home"          // which Spotlight panel the next request opens: home | clip | emoji | apps
    property int nightTemp: 4000
    // Control Center: ids of the enabled controls, in order (edit with Control Center → Edit Controls)
    property var ccControls: ["wifi", "nowplaying", "bluetooth", "airplane", "focus", "record", "nightshift", "keepawake", "display", "sound"]
    property bool ccMigRec: false              // one-time: add the Screen Recording tile to an existing Control Center layout
    property bool recording: false
    property int recSecs: 0
    property var otherConnections: []
    property string keyboardLayout: "EN"      // two-letter label shown in the bar
    property var kbLayouts: []                // configured layouts of the main keyboard: [{ code, name }]
    property int kbIndex: 0                   // index of the active one
    property string kbMain: ""                // name of the main keyboard (Hyprland)
    property string recordFile: ""
    property string fileQuery: ""
    property string fileSearchFor: ""
    property bool fileSearchPending: false
    property var fileHits: []

    readonly property var settingKeys: ["barEnabled", "darkMode", "appearanceMode", "accent", "fontFamily", "barHeight", "uiScaleAuto", "uiScaleManual", "glassOpacity",
        "barStyle", "barGlass", "glassRim", "glassGrain", "glassLiquid", "glassBlur", "barBgOpacity", "glassRealtime", "liveWallGlass", "glassDebug", "wallpaperPath", "use24h", "language", "showDate",
        "showSeconds", "showBatteryPercent", "showTray", "showSearch",
        "spotlightEnabled", "reduceMotion", "ccEnabled", "notificationsEnabled", "clockAppEnabled", "ccStyle", "barLogoMode", "barCustomLogoPath", "barWidgets", "weekStartsMonday", "terminal", "launcher",
        "filesCmd", "clipboardCmd", "appUsage", "clipHistory", "clipAutoPaste", "emojiRecent", "screenshotDir", "screenshotSave", "screenshotClipboard", "screenshotNotify", "nightTemp", "ccControls", "ccMigRec", "wallpaperDir", "wallpaperFavs", "wallpaperCmd", "wallpaperVideo", "wpRestorePath", "uiSounds", "gamingMode", "gamingAuto", "ccMigGame", "lockArtBackground",
        "lockClockStyle", "switcherStyle", "lockClockFont", "lockClockWeight", "lockClockMaterial", "lockClockIntensity", "lockClockTint", "lockClockDate", "autoContrast", "wallpaperAppearance", "wpPairLight", "wpPairDark",
        "notifDnd", "dnd", "nightOn", "keepAwake",
        "kbRepeatRate", "kbRepeatDelay", "mouseSens", "mouseNatural", "tpNatural", "tpTap", "tpDwt", "tpScroll"]
    // Optional bar widgets; tray and Spotlight use their existing showTray/showSearch settings.
    property var barWidgets: ["appleMenu", "appMenus", "workspaces", "volume", "keyboard", "notifications", "wifi", "bluetooth", "privacy", "controlCenter", "clock"]
    function barWidgetEnabled(id) { return barWidgets.indexOf(id) >= 0; }
    function resolvedBarLogoUrl() {
        var p = String(barCustomLogoPath || "").trim();
        if (p === "") return "";
        if (p.indexOf("://") >= 0) return p;
        var home = Quickshell.env("HOME") || "";
        if (p === "~") p = home;
        else if (p.indexOf("~/") === 0) p = home + p.substring(1);
        else if (p.charAt(0) !== "/") p = home + "/" + p;
        return "file://" + encodeURI(p).replace(/#/g, "%23").replace(/\?/g, "%3F");
    }
    readonly property string barCustomLogoUrl: resolvedBarLogoUrl()
    function setBarWidget(id, enabled) {
        var next = [];
        for (var i = 0; i < barWidgets.length; i++) if (barWidgets[i] !== id) next.push(barWidgets[i]);
        if (enabled) next.push(id);
        barWidgets = next;
    }
    readonly property var accentChoices: [
        { name: "Blue", c: "#0a84ff" }, { name: "Purple", c: "#bf5af2" }, { name: "Pink", c: "#ff375f" },
        { name: "Red", c: "#ff453a" }, { name: "Orange", c: "#ff9f0a" }, { name: "Yellow", c: "#ffd60a" },
        { name: "Green", c: "#30d158" }, { name: "Graphite", c: "#8e8e93" }
    ]

    // ═════════════ CONTROL CENTER LAYOUT ═════════════
    // The Control Center is a 4-column grid. Every control has a size in grid cells; the enabled ones are packed
    // first-fit in the order of `ccControls`, so dragging a control onto another one simply reorders the list.
    readonly property var ccCatalog: [
        { id: "wifi",       label: I18n.tr("Wi-Fi"),         glyph: "wifi",       w: 2, h: 1 },
        { id: "bluetooth",  label: I18n.tr("Bluetooth"),     glyph: "bluetooth",  w: 2, h: 1 },
        { id: "airplane",   label: I18n.tr("Airplane Mode"), glyph: "airplane",   w: 1, h: 1 },
        { id: "focus",      label: I18n.tr("Focus"),         glyph: "moon",       w: 2, h: 1 },
        { id: "nightshift", label: I18n.tr("Night Shift"),   glyph: "nightshift", w: 1, h: 1 },
        { id: "keepawake",  label: I18n.tr("Keep Awake"),    glyph: "coffee",     w: 1, h: 1 },
        { id: "darkmode",   label: I18n.tr("Dark Mode"),     glyph: "contrast",   w: 1, h: 1 },
        { id: "gaming",     label: I18n.tr("Game Mode"),     glyph: "gamepad",    w: 2, h: 1 },
        { id: "record",     label: I18n.tr("Screen Recording"), glyph: "record",  w: 2, h: 1 },
        { id: "nowplaying", label: I18n.tr("Now Playing"),   glyph: "note",       w: 2, h: 2 },
        { id: "display",    label: I18n.tr("Display"),       glyph: "sun",        w: 4, h: 1 },
        { id: "sound",      label: I18n.tr("Sound"),         glyph: "speaker",    w: 4, h: 1 }
    ]
    readonly property var ccDefault: ["wifi", "nowplaying", "bluetooth", "airplane", "focus", "record", "nightshift", "keepawake", "display", "sound"]
    function ccDef(id) {
        for (var i = 0; i < ccCatalog.length; i++) if (ccCatalog[i].id === id) return ccCatalog[i];
        return null;
    }
    function ccLayout(ids) {
        var cols = 4, occ = [], out = [], seen = {}, rows = 0;
        function isFree(r, c, w, h) {
            for (var y = r; y < r + h; y++) for (var x = c; x < c + w; x++) if (occ[y] && occ[y][x]) return false;
            return true;
        }
        function mark(r, c, w, h) {
            for (var y = r; y < r + h; y++) { if (!occ[y]) occ[y] = []; for (var x = c; x < c + w; x++) occ[y][x] = true; }
        }
        for (var i = 0; i < ids.length; i++) {
            var d = ccDef(ids[i]);
            if (!d || seen[d.id]) continue;
            seen[d.id] = true;
            var placed = false;
            for (var r = 0; !placed; r++) {
                for (var c = 0; c + d.w <= cols; c++) {
                    if (isFree(r, c, d.w, d.h)) {
                        mark(r, c, d.w, d.h);
                        out.push({ id: d.id, col: c, row: r, w: d.w, h: d.h });
                        rows = Math.max(rows, r + d.h);
                        placed = true;
                        break;
                    }
                }
            }
        }
        // pixel layout: tiles sit ccGap apart; the two slider tiles (Display, Sound) keep the wider ccSliderGap around them
        var sliderRow = [], ys = [];
        for (var k = 0; k < out.length; k++) {
            if (out[k].id === "display" || out[k].id === "sound")
                for (var rr = out[k].row; rr < out[k].row + out[k].h; rr++) sliderRow[rr] = true;
        }
        for (var r2 = 0; r2 < rows; r2++)
            ys[r2] = r2 === 0 ? 0 : ys[r2 - 1] + ccCellH + ((sliderRow[r2] || sliderRow[r2 - 1]) ? ccSliderGap : ccGap);
        for (var m = 0; m < out.length; m++) {
            out[m].y = ys[out[m].row];
            out[m].hpx = ys[out[m].row + out[m].h - 1] + ccCellH - ys[out[m].row];
        }
        return { items: out, rows: rows, total: rows > 0 ? ys[rows - 1] + ccCellH : 0 };
    }
    readonly property real ccCellH: 66
    readonly property real ccGap: 6
    readonly property real ccSliderGap: 10
    readonly property var ccPlan: ccLayout(ccControls)
    function ccAdd(id) {
        if (ccControls.indexOf(id) < 0) ccControls = ccControls.concat([id]);
    }
    function ccRemove(id) {
        ccControls = ccControls.filter(function (x) { return x !== id; });
    }
    // dropped control `id` with the pointer at (px, py) in grid coordinates: it takes the slot of the nearest control
    function ccDrop(id, px, py, cw, ch, gridH) {
        var order = ccControls.slice(), from = order.indexOf(id);
        if (from < 0) return;
        var to = -1, best = 1e18, it = ccPlan.items;
        for (var i = 0; i < it.length; i++) {
            if (it[i].id === id) continue;
            var o = it[i];
            var cx = o.col * (cw + ccGap) + (o.w * cw + (o.w - 1) * ccGap) / 2;
            var cy = o.y + o.hpx / 2;
            var dd = (cx - px) * (cx - px) + (cy - py) * (cy - py);
            if (dd < best) { best = dd; to = order.indexOf(o.id); }
        }
        if (py > gridH + ccSliderGap) to = order.length - 1;
        if (to < 0 || to === from) return;
        order.splice(from, 1);
        order.splice(to, 0, id);
        ccControls = order;
    }

    readonly property string configDir: Quickshell.env("HOME") + "/.config/macbar"
    readonly property string dockConfigDir: Quickshell.env("HOME") + "/.config/macdock"
    readonly property int popRoom: 900

    function sh(cmd) { Quickshell.execDetached(["sh", "-c", cmd]); }
    // Log out of Hyprland. 0.55+ (Lua) takes a Lua expression; UWSM sessions are stopped through uwsm so the session ends cleanly.
    // Lock Screen: starts MacLock via IPC helper; does nothing if already locked
    function lockScreen() {
        sh('sh ~/.config/quickshell/MacLock/lock-via-ipc.sh');
    }
    function sleepMachine() {
        sh('sh ~/.config/quickshell/MacLock/lock-via-ipc.sh; sleep 0.5; systemctl suspend');
    }
    function logOut() {
        sh('if command -v uwsm >/dev/null 2>&1 && uwsm check is-active >/dev/null 2>&1; then uwsm stop; '
           + 'else hyprctl dispatch "hl.dsp.exit()" || hyprctl dispatch exit; fi');
    }

    // ═════════════ PALETTE ═════════════
    // Auto contrast: see "AUTO CONTRAST" above. panelTone: what is behind the open panel (1 bright, -1 dark, 0 not measured).
    property bool autoContrast: true
    property int panelTone: 0
    // System look (Settings → Appearance: Light / Dark / Auto): every panel follows it, like a normal OS, the Control Center
    // included (ccDark / ccPal are now just aliases of it, no longer measured from what is behind the panel).
    readonly property bool effDark: panelDarkMode      // every panel palette (pal) follows the measured light / dark panel look
    property real dk: effDark ? 1 : 0
    Behavior on dk { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
    function mixc(l, d) { return Qt.rgba(l.r + (d.r - l.r) * dk, l.g + (d.g - l.g) * dk, l.b + (d.b - l.b) * dk, l.a + (d.a - l.a) * dk); }
    // ── Dynamic text colour (top bar, menus / popovers, Spotlight) ──
    // The bar is clear glass over the wallpaper and the windows, so its text follows what is measured BEHIND it (barTone) and flips
    // light/dark by itself. Menus and Spotlight keep their glass tint but flip their text when the measured backdrop would make the
    // normal colour unreadable (panelTone). Colours cross-fade (ptk / btk: 1 = white text, 0 = dark text).
    property int barTone: 0                   // measured behind the bar strip: 1 bright, -1 dark, 0 not measured yet
    readonly property bool barTextDark: barTone === 1 ? true : (barTone === -1 ? false : !darkMode)
    property real btk: barTextDark ? 0 : 1
    Behavior on btk { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    function mixb(l, d) { return Qt.rgba(l.r + (d.r - l.r) * btk, l.g + (d.g - l.g) * btk, l.b + (d.b - l.b) * btk, l.a + (d.a - l.a) * btk); }
    readonly property bool panelTextDark: !panelTextWhite
    property real ptk: panelTextDark ? 0 : 1
    Behavior on ptk { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    function mixp(l, d) { return Qt.rgba(l.r + (d.r - l.r) * ptk, l.g + (d.g - l.g) * ptk, l.b + (d.b - l.b) * ptk, l.a + (d.a - l.a) * ptk); }
    // Control Center: light or dark with the panels (what is behind it)
    readonly property bool ccDark: panelDarkMode
    property real ccDk: ccDark ? 1 : 0
    Behavior on ccDk { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
    function ccMix(l, d) { return Qt.rgba(l.r + (d.r - l.r) * ccDk, l.g + (d.g - l.g) * ccDk, l.b + (d.b - l.b) * ccDk, l.a + (d.a - l.a) * ccDk); }

    // Appearance: light / dark / auto. darkMode is the resolved look; the Dock window is kept in step.
    function autoIsDark() { var h = new Date().getHours(); return h < 7 || h >= 19; }
    function setAppearance(mode) {
        if (["light", "dark", "auto"].indexOf(mode) < 0) return;
        appearanceMode = mode;
        darkMode = mode === "auto" ? autoIsDark() : mode === "dark";
        try { if (hub && hub.dock) { hub.dock.appearanceMode = mode; hub.dock.darkMode = darkMode; } } catch (e) {}
        try { if (hub && hub.about) { hub.about.darkMode = darkMode; } } catch (e2) {}
        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", darkMode ? "prefer-dark" : "prefer-light"]);
    }
    Timer {
        interval: 60000; repeat: true; triggeredOnStart: true
        running: root.appearanceMode === "auto"
        onTriggered: { var d = root.autoIsDark(); if (d !== root.darkMode) root.setAppearance("auto"); }
    }
    Process {
        id: gsettingsSchemeProc
        command: ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"]
        stdout: StdioCollector {
            onStreamFinished: {
                var s = text.trim();
                if (s.indexOf("prefer-light") >= 0 && root.darkMode && root.appearanceMode !== "dark") {
                    root.darkMode = false;
                    try { if (hub && hub.dock) hub.dock.darkMode = false; } catch(e){}
                    try { if (hub && hub.about) hub.about.darkMode = false; } catch(e2){}
                } else if (s.indexOf("prefer-dark") >= 0 && !root.darkMode && root.appearanceMode !== "light") {
                    root.darkMode = true;
                    try { if (hub && hub.dock) hub.dock.darkMode = true; } catch(e){}
                    try { if (hub && hub.about) hub.about.darkMode = true; } catch(e2){}
                }
            }
        }
    }
    Timer {
        interval: 3000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: if (!gsettingsSchemeProc.running) gsettingsSchemeProc.running = true
    }
    QtObject {
        id: bpal
        readonly property bool dark: !root.barTextDark
        readonly property string fam: root.fontFamily
        readonly property color accent: root.accent
        readonly property color fg: root.mixb(Qt.color("#1D1D1F"), Qt.color("#FFFFFF"))
        readonly property color fg2: root.mixb(Qt.rgba(0, 0, 0, 0.55), Qt.rgba(1, 1, 1, 0.62))
        readonly property color fg3: root.mixb(Qt.rgba(0, 0, 0, 0.32), Qt.rgba(1, 1, 1, 0.34))
        readonly property color tile: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.42)
        readonly property color tileBorder: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.70)
        readonly property color btnOff: dark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.10)
        readonly property color btnHover: dark ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(0, 0, 0, 0.16)
        readonly property color hover: root.mixb(Qt.rgba(0, 0, 0, 0.09), Qt.rgba(1, 1, 1, 0.14))
        readonly property color sep: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)
        readonly property color track: dark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.12)
        readonly property color content: dark ? "#1E1E1E" : "#F5F5F7"
        readonly property color card: dark ? "#2B2B2D" : "#FFFFFF"
        readonly property color cardBorder: dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.08)
        readonly property color switchOff: dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.16)
    }
    QtObject {
        id: panelPal
        readonly property bool dark: root.panelDarkMode
        readonly property string fam: root.fontFamily
        readonly property color accent: root.accent
        readonly property color fg: root.mixp(Qt.color("#1D1D1F"), Qt.color("#FFFFFF"))
        readonly property color fg2: root.mixp(Qt.rgba(0, 0, 0, 0.55), Qt.rgba(1, 1, 1, 0.62))
        readonly property color fg3: root.mixp(Qt.rgba(0, 0, 0, 0.32), Qt.rgba(1, 1, 1, 0.34))
        readonly property color tile: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.42)
        readonly property color tileBorder: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.70)
        readonly property color btnOff: dark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.10)
        readonly property color btnHover: dark ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(0, 0, 0, 0.16)
        readonly property color hover: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.09)
        readonly property color sep: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)
        readonly property color track: dark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.12)
        readonly property color content: dark ? "#1E1E1E" : "#F5F5F7"
        readonly property color card: dark ? "#2B2B2D" : "#FFFFFF"
        readonly property color cardBorder: dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.08)
        readonly property color switchOff: dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.16)
    }
    QtObject {
        id: pal
        readonly property bool dark: root.effDark
        readonly property string fam: root.fontFamily
        readonly property color accent: root.accent
        readonly property color fg: root.mixp(Qt.color("#1D1D1F"), Qt.color("#FFFFFF"))
        readonly property color fg2: root.mixp(Qt.rgba(0, 0, 0, 0.55), Qt.rgba(1, 1, 1, 0.62))
        readonly property color fg3: root.mixp(Qt.rgba(0, 0, 0, 0.32), Qt.rgba(1, 1, 1, 0.34))
        readonly property color tile: root.mixc(Qt.rgba(1, 1, 1, 0.42), Qt.rgba(1, 1, 1, 0.10))
        readonly property color tileBorder: root.mixc(Qt.rgba(1, 1, 1, 0.70), Qt.rgba(1, 1, 1, 0.16))
        readonly property color btnOff: root.mixc(Qt.rgba(0, 0, 0, 0.10), Qt.rgba(1, 1, 1, 0.20))
        readonly property color btnHover: root.mixc(Qt.rgba(0, 0, 0, 0.16), Qt.rgba(1, 1, 1, 0.30))
        readonly property color hover: root.mixc(Qt.rgba(0, 0, 0, 0.09), Qt.rgba(1, 1, 1, 0.14))
        readonly property color sep: root.mixc(Qt.rgba(0, 0, 0, 0.12), Qt.rgba(1, 1, 1, 0.14))
        readonly property color track: root.mixc(Qt.rgba(0, 0, 0, 0.12), Qt.rgba(1, 1, 1, 0.20))
        readonly property color content: dark ? "#1E1E1E" : "#F5F5F7"
        readonly property color card: dark ? "#2B2B2D" : "#FFFFFF"
        readonly property color cardBorder: root.mixc(Qt.rgba(0, 0, 0, 0.08), Qt.rgba(1, 1, 1, 0.07))
        readonly property color switchOff: root.mixc(Qt.rgba(0, 0, 0, 0.16), Qt.rgba(1, 1, 1, 0.22))
    }
    QtObject {
        id: ccPal
        readonly property bool dark: root.ccDark
        // the Control Center follows the selected UI font like everything else (Open Runde by default)
        readonly property string fam: root.fontFamily
        readonly property color accent: root.accent
        readonly property color fg: root.mixp(Qt.color("#1D1D1F"), Qt.color("#FFFFFF"))
        readonly property color fg2: root.mixp(Qt.rgba(0, 0, 0, 0.55), Qt.rgba(1, 1, 1, 0.62))
        readonly property color fg3: root.mixp(Qt.rgba(0, 0, 0, 0.32), Qt.rgba(1, 1, 1, 0.34))
        readonly property color tile: root.ccMix(Qt.rgba(1, 1, 1, 0.42), Qt.rgba(1, 1, 1, 0.10))
        readonly property color tileBorder: root.ccMix(Qt.rgba(1, 1, 1, 0.70), Qt.rgba(1, 1, 1, 0.16))
        readonly property color btnOff: root.ccMix(Qt.rgba(0, 0, 0, 0.10), Qt.rgba(1, 1, 1, 0.20))
        readonly property color btnHover: root.ccMix(Qt.rgba(0, 0, 0, 0.16), Qt.rgba(1, 1, 1, 0.30))
        readonly property color hover: root.ccMix(Qt.rgba(0, 0, 0, 0.09), Qt.rgba(1, 1, 1, 0.14))
        readonly property color sep: root.ccMix(Qt.rgba(0, 0, 0, 0.12), Qt.rgba(1, 1, 1, 0.14))
        readonly property color track: root.ccMix(Qt.rgba(0, 0, 0, 0.12), Qt.rgba(1, 1, 1, 0.20))
        readonly property color content: dark ? "#1E1E1E" : "#F5F5F7"
        readonly property color card: dark ? "#2B2B2D" : "#FFFFFF"
        readonly property color cardBorder: root.ccMix(Qt.rgba(0, 0, 0, 0.08), Qt.rgba(1, 1, 1, 0.07))
        readonly property color switchOff: root.ccMix(Qt.rgba(0, 0, 0, 0.16), Qt.rgba(1, 1, 1, 0.22))
    }

    // ═════════════ REUSABLE COMPONENTS ═════════════
    // (inline components don't see ids of this file, so everything arrives through properties / `t` = palette)

    // Hand-drawn monochrome glyphs on an 18×18 grid (no icon theme needed)
    component Glyph: Canvas {
        id: gl
        property string kind: ""
        property color color: "white"
        property real level: 3          // speaker / sun intensity 0..3, wifi bars 0..3, battery 0..100
        property bool flag: false       // "disabled" slash for wifi / bluetooth
        width: 18; height: 18
        antialiasing: true
        onKindChanged: requestPaint()
        onColorChanged: requestPaint()
        onLevelChanged: requestPaint()
        onFlagChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var s = Math.min(width, height) / 18;
            ctx.scale(s, s);
            ctx.strokeStyle = color;
            ctx.fillStyle = color;
            ctx.lineWidth = 1.5;
            ctx.lineCap = "round";
            ctx.lineJoin = "round";
            var PI = Math.PI;
            function circ(x, y, r) { ctx.beginPath(); ctx.arc(x, y, r, 0, PI * 2); }
            function line(x1, y1, x2, y2) { ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke(); }
            function poly(p, fill) {
                ctx.beginPath(); ctx.moveTo(p[0], p[1]);
                for (var i = 2; i < p.length; i += 2) ctx.lineTo(p[i], p[i + 1]);
                if (fill) { ctx.closePath(); ctx.fill(); } else ctx.stroke();
            }
            // filled polygon with rounded corners (radius r), used by the media icons
            function rpoly(p, r) {
                var n = p.length / 2;
                ctx.beginPath();
                ctx.moveTo((p[0] + p[2 * (n - 1)]) / 2, (p[1] + p[2 * (n - 1) + 1]) / 2);
                for (var q = 0; q < n; q++) {
                    var x = p[2 * q], y = p[2 * q + 1];
                    var nx = p[2 * ((q + 1) % n)], ny = p[2 * ((q + 1) % n) + 1];
                    ctx.arcTo(x, y, (x + nx) / 2, (y + ny) / 2, r);
                }
                ctx.closePath(); ctx.fill();
            }
            function rrect(x, y, w, h, r) {
                ctx.beginPath(); ctx.moveTo(x + r, y); ctx.lineTo(x + w - r, y); ctx.arcTo(x + w, y, x + w, y + r, r);
                ctx.lineTo(x + w, y + h - r); ctx.arcTo(x + w, y + h, x + w - r, y + h, r);
                ctx.lineTo(x + r, y + h); ctx.arcTo(x, y + h, x, y + h - r, r);
                ctx.lineTo(x, y + r); ctx.arcTo(x, y, x + r, y, r); ctx.closePath();
            }
            var k = kind, i2;

            if (k === "arch") {
                ctx.translate(0.43, 0);
                ctx.beginPath();
                ctx.moveTo(8.54, 0.45);
                ctx.bezierCurveTo(7.78, 2.32, 7.32, 3.54, 6.48, 5.35);
                ctx.bezierCurveTo(7, 5.9, 7.63, 6.54, 8.67, 7.26);
                ctx.bezierCurveTo(7.56, 6.81, 6.8, 6.35, 6.23, 5.87);
                ctx.bezierCurveTo(5.15, 8.13, 3.45, 11.35, 0, 17.55);
                ctx.bezierCurveTo(2.71, 15.98, 4.81, 15.02, 6.77, 14.65);
                ctx.lineTo(6.64, 13.49);
                ctx.lineTo(6.64, 13.4);
                ctx.bezierCurveTo(6.68, 11.67, 7.59, 10.33, 8.66, 10.42);
                ctx.bezierCurveTo(9.72, 10.51, 10.56, 12, 10.51, 13.73);
                ctx.lineTo(10.4, 14.66);
                ctx.bezierCurveTo(12.34, 15.04, 14.44, 16, 17.13, 17.55);
                ctx.bezierCurveTo(16.6, 16.58, 16.12, 15.71, 15.67, 14.88);
                ctx.bezierCurveTo(14.96, 14.33, 14.22, 13.61, 12.75, 12.86);
                ctx.bezierCurveTo(13.77, 13.13, 14.51, 13.44, 15.08, 13.78);
                ctx.bezierCurveTo(10.24, 6.35, 9.4, 3.82, 8.54, 0.45);
                ctx.closePath();
                ctx.fill();
            } else if (k === "wifi") {
                var radii = [3.8, 7.2, 10.6];
                for (i2 = 0; i2 < 3; i2++) {
                    if (i2 >= level) ctx.globalAlpha = 0.3; else ctx.globalAlpha = 1;
                    ctx.beginPath(); ctx.arc(9, 14.6, radii[i2], -PI * 0.75, -PI * 0.25); ctx.stroke();
                }
                ctx.globalAlpha = 1;
                circ(9, 14.6, 1.3); ctx.fill();
                if (flag) line(2.5, 2.5, 15.5, 15.5);
            } else if (k === "bluetooth") {
                poly([5, 5.5, 13, 12.5, 9, 16, 9, 2, 13, 5.5, 5, 12.5], false);
                if (flag) line(2.5, 2.5, 15.5, 15.5);
            } else if (k === "airplane") {
                line(9, 1.8, 9, 16.2);
                poly([2, 10.5, 9, 7, 16, 10.5], false);
                poly([6, 15.5, 9, 13.5, 12, 15.5], false);
            } else if (k === "moon") {
                circ(9, 9, 6.8); ctx.fill();
                ctx.globalCompositeOperation = "destination-out";
                circ(12.2, 6.4, 5.6); ctx.fill();
                ctx.globalCompositeOperation = "source-over";
            } else if (k === "sun") {
                var r = 2.2 + level * 0.5, a = r + 2.2, b = a + 1.2 + level * 0.4;
                circ(9, 9, r); ctx.stroke();
                for (i2 = 0; i2 < 8; i2++) {
                    var ang = i2 * PI / 4;
                    line(9 + Math.cos(ang) * a, 9 + Math.sin(ang) * a, 9 + Math.cos(ang) * b, 9 + Math.sin(ang) * b);
                }
            } else if (k === "nightshift") {
                ctx.beginPath(); ctx.arc(9, 11, 4, PI, PI * 2); ctx.stroke();
                line(2, 11, 16, 11);
                line(5.5, 14.5, 12.5, 14.5);
                line(9, 3.2, 9, 5);
                line(3.6, 5.6, 4.9, 6.9);
                line(14.4, 5.6, 13.1, 6.9);
            } else if (k === "coffee") {
                ctx.beginPath(); ctx.moveTo(3.5, 7.5); ctx.lineTo(12, 7.5); ctx.lineTo(12, 11.5);
                ctx.quadraticCurveTo(12, 15, 7.75, 15); ctx.quadraticCurveTo(3.5, 15, 3.5, 11.5); ctx.closePath(); ctx.stroke();
                ctx.beginPath(); ctx.arc(12.4, 10, 2.2, -PI * 0.5, PI * 0.5); ctx.stroke();
                ctx.beginPath(); ctx.moveTo(6, 2.6); ctx.quadraticCurveTo(7.2, 4, 6, 5.4); ctx.stroke();
                ctx.beginPath(); ctx.moveTo(9.4, 2.6); ctx.quadraticCurveTo(10.6, 4, 9.4, 5.4); ctx.stroke();
            } else if (k === "speaker") {
                poly([2.2, 7, 5.4, 7, 9.2, 3.6, 9.2, 14.4, 5.4, 11, 2.2, 11], true);
                if (level <= 0) {
                    line(12, 6.8, 16, 11.2); line(16, 6.8, 12, 11.2);
                } else {
                    for (i2 = 1; i2 <= Math.min(2, Math.ceil(level / 1.5)); i2++) {
                        ctx.beginPath(); ctx.arc(9.2, 9, 2.4 + i2 * 3.0, -0.62, 0.62); ctx.stroke();
                    }
                }
            } else if (k === "record") {
                circ(9, 9, 7); ctx.stroke();
                circ(9, 9, 3.7); ctx.fill();
            } else if (k === "stoprec") {
                circ(9, 9, 7); ctx.stroke();
                rrect(5.9, 5.9, 6.2, 6.2, 1.6); ctx.fill();
            } else if (k === "mic") {
                rrect(6.5, 1.8, 5, 8.6, 2.5); ctx.stroke();
                ctx.beginPath(); ctx.arc(9, 8.4, 5, 0.12, PI - 0.12, false); ctx.stroke();
                line(9, 13.4, 9, 16); line(6.2, 16, 11.8, 16);
                if (flag) line(2.5, 2.5, 15.5, 15.5);
            } else if (k === "headphones") {
                ctx.beginPath(); ctx.arc(9, 9.8, 5.9, PI, 0, false); ctx.stroke();
                rrect(2.5, 9.4, 3.3, 5.8, 1.5); ctx.fill();
                rrect(12.2, 9.4, 3.3, 5.8, 1.5); ctx.fill();
            } else if (k === "monitor") {
                rrect(2, 3, 14, 9.4, 1.8); ctx.stroke();
                line(6.4, 15.4, 11.6, 15.4); line(9, 12.4, 9, 15.4);
            } else if (k === "camera") {
                rrect(2, 4.6, 14, 9.6, 2.2); ctx.stroke();
                circ(9, 9.4, 2.7); ctx.stroke();
                line(6.8, 3, 11.2, 3);
            } else if (k === "gamepad") {
                // game controller: rounded body, d-pad, two buttons
                ctx.beginPath();
                ctx.moveTo(5, 5); ctx.lineTo(13, 5);
                ctx.bezierCurveTo(16.4, 5, 17.4, 9.5, 16.6, 12.6); ctx.bezierCurveTo(16.1, 14.4, 14.2, 14.6, 13.1, 13.2);
                ctx.lineTo(11.8, 11.6); ctx.lineTo(6.2, 11.6); ctx.lineTo(4.9, 13.2);
                ctx.bezierCurveTo(3.8, 14.6, 1.9, 14.4, 1.4, 12.6); ctx.bezierCurveTo(0.6, 9.5, 1.6, 5, 5, 5);
                ctx.closePath(); ctx.stroke();
                line(5.3, 7.4, 5.3, 10.2); line(3.9, 8.8, 6.7, 8.8);
                circ(12.4, 8.0, 0.9); ctx.fill();
                circ(14.0, 9.6, 0.9); ctx.fill();
            } else if (k === "ethernet") {
                // Apple's Ethernet symbol: <···>
                poly([5.2, 4.6, 1.6, 9, 5.2, 13.4], false);
                poly([12.8, 4.6, 16.4, 9, 12.8, 13.4], false);
                circ(6.5, 9, 1.1); ctx.fill();
                circ(9, 9, 1.1); ctx.fill();
                circ(11.5, 9, 1.1); ctx.fill();
            } else if (k === "play") {
                rpoly([5, 3.2, 15, 9, 5, 14.8], 0.8);
            } else if (k === "pause") {
                rrect(4.2, 3.4, 3.4, 11.2, 0.7); ctx.fill();
                rrect(10.4, 3.4, 3.4, 11.2, 0.7); ctx.fill();
            } else if (k === "next") {
                rpoly([1.8, 4, 8.6, 9, 1.8, 14], 0.6);
                rpoly([9.4, 4, 16.2, 9, 9.4, 14], 0.6);
            } else if (k === "prev") {
                rpoly([16.2, 4, 9.4, 9, 16.2, 14], 0.6);
                rpoly([8.6, 4, 1.8, 9, 8.6, 14], 0.6);
            } else if (k === "note") {
                line(7, 12.5, 7, 3.5); line(7, 3.5, 14, 2.2); line(14, 2.2, 14, 11);
                circ(5.2, 13, 2); ctx.fill();
                circ(12.2, 11.6, 2); ctx.fill();
            } else if (k === "search") {
                circ(7.6, 7.6, 4.8); ctx.stroke();
                line(11.2, 11.2, 15.4, 15.4);
            } else if (k === "cc") {
                rrect(2, 3, 14, 5.2, 2.6); ctx.stroke();
                circ(12.4, 5.6, 1.5); ctx.fill();
                rrect(2, 9.8, 14, 5.2, 2.6); ctx.stroke();
                circ(5.6, 12.4, 1.5); ctx.fill();
            } else if (k === "volume") {
                poly([2.2, 7, 5.4, 7, 9.2, 3.6, 9.2, 14.4, 5.4, 11, 2.2, 11], true);
                ctx.beginPath(); ctx.arc(9.2, 9, 4.4, -0.62, 0.62); ctx.stroke();
                ctx.beginPath(); ctx.arc(9.2, 9, 7.4, -0.62, 0.62); ctx.stroke();
            } else if (k === "bolt") {
                poly([10, 1.5, 4.5, 10, 8.4, 10, 7.6, 16.5, 13.5, 7.6, 9.6, 7.6], true);
            } else if (k === "appstore") {
                line(9, 2.8, 3.8, 14.6);
                line(9, 2.8, 14.2, 14.6);
                line(5.4, 11.2, 12.6, 11.2);
            } else if (k === "folder") {
                ctx.beginPath();
                ctx.moveTo(2.2, 13);
                ctx.lineTo(2.2, 5.6);
                ctx.arcTo(2.2, 3.8, 4, 3.8, 1.8);
                ctx.lineTo(6.6, 3.8);
                ctx.lineTo(8.2, 5.8);
                ctx.lineTo(14, 5.8);
                ctx.arcTo(15.8, 5.8, 15.8, 7.6, 1.8);
                ctx.lineTo(15.8, 13);
                ctx.arcTo(15.8, 15.2, 13.6, 15.2, 2.2);
                ctx.lineTo(4.4, 15.2);
                ctx.arcTo(2.2, 15.2, 2.2, 13, 2.2);
                ctx.closePath(); ctx.stroke();
            } else if (k === "layers") {
                ctx.beginPath(); ctx.moveTo(9, 2.4); ctx.lineTo(15.6, 5.8); ctx.lineTo(9, 9.2); ctx.lineTo(2.4, 5.8); ctx.closePath(); ctx.stroke();
                poly([2.4, 9.2, 9, 12.6, 15.6, 9.2], false);
                poly([2.4, 12.4, 9, 15.8, 15.6, 12.4], false);
            } else if (k === "clipboard") {
                rrect(3.6, 3.4, 10.8, 12.6, 2); ctx.stroke();
                rrect(6.4, 1.9, 5.2, 3.4, 1.2); ctx.stroke();
                line(6.4, 9, 11.6, 9);
                line(6.4, 12, 10, 12);
            } else if (k === "smile") {
                circ(9, 9, 6.6); ctx.stroke();
                circ(6.7, 7.5, 0.95); ctx.fill();
                circ(11.3, 7.5, 0.95); ctx.fill();
                ctx.beginPath(); ctx.arc(9, 9.2, 3.7, 0.25, PI - 0.25, false); ctx.stroke();
            } else if (k === "doc") {
                ctx.beginPath(); ctx.moveTo(4.6, 2.2); ctx.lineTo(10.2, 2.2); ctx.lineTo(13.8, 5.8); ctx.lineTo(13.8, 15.8); ctx.lineTo(4.6, 15.8); ctx.closePath(); ctx.stroke();
                poly([10.2, 2.2, 10.2, 5.8, 13.8, 5.8], false);
                line(6.8, 9.6, 11.6, 9.6);
                line(6.8, 12.4, 11.6, 12.4);
            } else if (k === "link") {
                ctx.save(); ctx.translate(9, 9); ctx.rotate(-PI / 4);
                rrect(-7.2, -2.7, 8.2, 5.4, 2.7); ctx.stroke();
                rrect(-1, -2.7, 8.2, 5.4, 2.7); ctx.stroke();
                ctx.restore();
            } else if (k === "photo") {
                rrect(2.4, 3.4, 13.2, 11.2, 2.2); ctx.stroke();
                circ(6.4, 7.4, 1.3); ctx.fill();
                poly([3.2, 13.4, 7.6, 9.4, 10.4, 12, 12.4, 10.2, 14.8, 13.4], false);
            } else if (k === "return") {
                poly([14.5, 4, 14.5, 10, 4.5, 10], false);
                poly([7.5, 7, 4.5, 10, 7.5, 13], false);
            } else if (k === "dots") {
                circ(3.6, 9, 1.35); ctx.fill();
                circ(9, 9, 1.35); ctx.fill();
                circ(14.4, 9, 1.35); ctx.fill();
            } else if (k === "lock") {
                rrect(3.6, 8, 10.8, 7.8, 2); ctx.stroke();
                ctx.beginPath(); ctx.moveTo(6, 8); ctx.lineTo(6, 6); ctx.arc(9, 6, 3, PI, 0, false); ctx.lineTo(12, 8); ctx.stroke();
            } else if (k === "power") {
                ctx.beginPath(); ctx.arc(9, 9.6, 6, -PI / 2 + 0.65, -PI / 2 - 0.65 + PI * 2, false); ctx.stroke();
                line(9, 2.2, 9, 8.4);
            } else if (k === "restart") {
                ctx.beginPath(); ctx.arc(9, 9, 5.8, -1.0, 4.4, false); ctx.stroke();
                poly([9.7, 2.7, 6.6, 1.6, 7.8, 5.4], true);
            } else if (k === "logout") {
                poly([9, 3, 3.5, 3, 3.5, 15, 9, 15], false);
                line(7.5, 9, 15.5, 9);
                poly([12.5, 6, 15.5, 9, 12.5, 12], false);
            } else if (k === "contrast") {
                circ(9, 9, 6.5); ctx.stroke();
                ctx.beginPath(); ctx.arc(9, 9, 6.5, -PI / 2, PI / 2, false); ctx.closePath(); ctx.fill();
            } else if (k === "check") {
                poly([3.5, 9.5, 7.5, 13.5, 14.5, 4.5], false);
            } else if (k === "chevL") {
                poly([11, 3.5, 5.5, 9, 11, 14.5], false);
            } else if (k === "chevR") {
                poly([7, 3.5, 12.5, 9, 7, 14.5], false);
            } else if (k === "bell") {
                ctx.beginPath(); ctx.moveTo(3.4, 12.9);
                ctx.bezierCurveTo(4.6, 11.8, 5.0, 10.6, 5.0, 8.2);
                ctx.bezierCurveTo(5.0, 5.6, 6.8, 3.9, 9.0, 3.9);
                ctx.bezierCurveTo(11.2, 3.9, 13.0, 5.6, 13.0, 8.2);
                ctx.bezierCurveTo(13.0, 10.6, 13.4, 11.8, 14.6, 12.9);
                ctx.closePath(); ctx.stroke();
                line(9, 2.2, 9, 3.9);
                ctx.beginPath(); ctx.arc(9, 14.3, 1.7, 0.25, PI - 0.25); ctx.stroke();
            } else if (k === "close") {
                line(5, 5, 13, 13); line(13, 5, 5, 13);
            } else if (k === "gear") {
                circ(9, 9, 2.6); ctx.stroke();
                for (i2 = 0; i2 < 8; i2++) {
                    var g2 = i2 * PI / 4;
                    line(9 + Math.cos(g2) * 5.6, 9 + Math.sin(g2) * 5.6, 9 + Math.cos(g2) * 7.6, 9 + Math.sin(g2) * 7.6);
                }
                circ(9, 9, 5.6); ctx.stroke();
            } else if (k.indexOf("m_") === 0) {
                // ── Apple-menu icons (drawn after the macOS ones; 18x18 grid, 1.5 px strokes) ──
                ctx.lineWidth = 1.4;
                var ell = function (cx, cy, rx, ry, fill) {
                    ctx.save(); ctx.translate(cx, cy); ctx.scale(rx, ry); ctx.beginPath(); ctx.arc(0, 0, 1, 0, PI * 2); ctx.restore();
                    if (fill) ctx.fill(); else ctx.stroke();
                };
                if (k === "m_about") {                       // Linux penguin (Tux), outline
                    ell(9, 9.2, 4.6, 6.6, false);
                    ctx.lineWidth = 1.1; ell(9, 11.6, 2.7, 3.5, false); ctx.lineWidth = 1.4;
                    circ(7.5, 6.2, 0.85); ctx.fill(); circ(10.5, 6.2, 0.85); ctx.fill();
                    poly([7.7, 7.6, 10.3, 7.6, 9, 9.1], true);
                    ell(6.1, 16.3, 2.1, 0.95, true); ell(11.9, 16.3, 2.1, 0.95, true);
                    line(4.5, 10, 3.1, 13.6); line(13.5, 10, 14.9, 13.6);
                } else if (k === "m_settings") {             // System Settings: ring with a half-disc
                    circ(9, 9, 6.7); ctx.stroke();
                    ctx.beginPath(); ctx.arc(9, 9, 3.2, -PI / 2, PI / 2, false); ctx.closePath(); ctx.fill();
                    line(9, 5.6, 9, 12.4);
                } else if (k === "m_sleep") {                // Sleep: ring, lower half filled
                    circ(9, 9, 6.7); ctx.stroke();
                    ctx.beginPath(); ctx.arc(9, 9, 6.7, 0, PI, false); ctx.closePath(); ctx.fill();
                } else if (k === "m_restart") {              // Restart: left-pointing triangle
                    ctx.lineWidth = 1.5;
                    poly([12.6, 3.6, 4.6, 9, 12.6, 14.4, 12.6, 3.6], false);
                } else if (k === "m_power") {                // Shut Down
                    ctx.beginPath(); ctx.arc(9, 9.6, 5.8, -PI / 2 + 0.7, -PI / 2 - 0.7 + PI * 2, false); ctx.stroke();
                    line(9, 2.6, 9, 8.4);
                } else if (k === "m_lock") {                 // Lock Screen: padlock
                    rrect(4, 8, 10, 7.6, 1.8); ctx.stroke();
                    ctx.beginPath(); ctx.moveTo(6.4, 8); ctx.lineTo(6.4, 6.4); ctx.arc(9, 6.4, 2.6, PI, 0, false); ctx.lineTo(11.6, 8); ctx.stroke();
                    circ(9, 11.8, 1.1); ctx.fill();
                } else if (k === "m_logout") {               // Log Out: ring with a person
                    circ(9, 9, 6.7); ctx.stroke();
                    circ(9, 7.2, 1.9); ctx.fill();
                    ctx.beginPath(); ctx.arc(9, 14.4, 4.2, PI * 1.22, PI * 1.78, false); ctx.stroke();
                }
            }
        }
    }

    // Liquid Glass slab (liquidglass.frag) or a flat translucent fallback
    component LGlass: Item {
        id: g
        property Item backdrop: null
        property url shaderUrl: ""
        property bool liquid: false
        property bool dark: true
        property real bx: 0                 // position of this slab inside the backdrop item
        property real by: 0
        property real cornerR: 20
        property real tint: 0.4             // 0..1, from the translucency setting
        property real thickness: 30
        property real strength: 1.0         // liquid glass strength multiplier
        property real rim: 0.45
        property real rimTint: 0            // 1 = rim + border line take a brighter shade of the glass's own local colour
        property real shadowAmt: 1          // outer drop shadow (0 = none)
        property real flatInner: 0          // 1 = no darker inner edge shading (needs the rebuilt liquidglass shader)
        property real ringW: 0              // width (px) of the thin border line along the edge, 0 = none
        property real grain: 0.03
        property real blur: 5               // backdrop blur radius, px (settings slider)
        property bool debug: false
        signal shaderError()

        Rectangle {
            visible: !g.liquid
            anchors.fill: parent
            radius: g.cornerR
            color: g.dark ? Qt.rgba(0.12, 0.12, 0.13, 0.30 + g.tint * 0.9) : Qt.rgba(1, 1, 1, 0.30 + g.tint * 0.7)
            border.width: 1
            border.color: g.dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.55)
        }
        Loader {
            anchors.fill: parent
            active: g.liquid && g.backdrop !== null && g.visible
            sourceComponent: Item {
                id: lg
                readonly property real m: 72     // extra backdrop captured around the slab (refraction + blur reach)
                readonly property real p: 10     // shader padding (drop shadow)
                // a Gaussian blur of 8 px or more doesn't need full resolution: blurring at half size is visually identical
                // and costs a quarter of the GPU work, every frame
                readonly property real ds: g.blur >= 8 ? 0.5 : 1.0
                readonly property real bn: g.blur * 1.4 * ds / 64.0     // blur amount in MultiEffect units (at the reduced size)
                ShaderEffectSource {
                    id: bsrc
                    sourceItem: g.backdrop
                    hideSource: true
                    live: true
                    visible: false
                    sourceRect: Qt.rect(g.bx - lg.p - lg.m, g.by - lg.p - lg.m,
                                        g.width + 2 * (lg.p + lg.m), g.height + 2 * (lg.p + lg.m))
                    textureSize: Qt.size(Math.max(1, Math.round(sourceRect.width * lg.ds)), Math.max(1, Math.round(sourceRect.height * lg.ds)))
                }
                MultiEffect {
                    id: bblurFx
                    source: bsrc
                    width: bsrc.sourceRect.width * lg.ds; height: bsrc.sourceRect.height * lg.ds
                    blurEnabled: true
                    blurMax: 64
                    blur: Math.min(1.0, lg.bn)
                    autoPaddingEnabled: false
                    visible: false
                }
                // real Gaussian pre-blur of the backdrop (Qt MultiEffect): the glass shader refracts THIS texture,
                // so there are no sampled copies of the background any more
                ShaderEffectSource {
                    id: bblur
                    sourceItem: bblurFx
                    live: true
                    visible: false
                }
                MultiEffect {
                    id: bblur2Fx
                    source: bblur
                    width: bsrc.sourceRect.width * lg.ds; height: bsrc.sourceRect.height * lg.ds
                    blurEnabled: lg.bn > 1.0
                    blurMax: 64
                    blur: Math.max(0.0, Math.min(1.0, lg.bn - 1.0))
                    autoPaddingEnabled: false
                    visible: false
                }
                // second Gaussian pass: only active when the slider goes past a single pass's 64 px limit
                ShaderEffectSource {
                    id: bblur2
                    // the 2nd pass is a pure copy unless the blur radius exceeds one pass: skip it then (same pixels, one GPU pass less)
                    sourceItem: lg.bn > 1.0 ? bblur2Fx : null
                    live: true
                    visible: false
                }
                ShaderEffect {
                    id: fx
                    x: -lg.p; y: -lg.p
                    width: g.width + 2 * lg.p
                    height: g.height + 2 * lg.p
                    fragmentShader: g.shaderUrl
                    onStatusChanged: {
                        console.log("[macbar-glass] shader status:", status, "(0 = compiled, 1 = uncompiled, 2 = error)", log);
                        if (status === ShaderEffect.Error) g.shaderError();
                    }
                    property variant src: lg.bn > 1.0 ? bblur2 : bblur
                    property real padPx: lg.p
                    property vector2d itemSize: Qt.vector2d(width, height)
                    property vector2d glassSize: Qt.vector2d(g.width, g.height)
                    property vector2d srcSize: Qt.vector2d(bsrc.sourceRect.width, bsrc.sourceRect.height)
                    property vector2d srcOffset: Qt.vector2d(lg.m, lg.m)
                    property real pad: lg.p
                    property real radius: g.cornerR
                    property real bezel: Math.min(g.height * 0.36, 26)
                    property real thickness: g.thickness * g.strength * 1.6      // bar popovers: boosted to match the stronger dock glass
                    property real dispersion: 0.06 * g.strength * 1.3
                    property real magnify: 0.05 * g.strength * 1.6
                    property real rim: g.rim
                    property real grain: g.grain * 0.2
                    property real blurPx: 1.5
                    property real tintMix: g.tint * 0.55
                    property real saturation: 1.25
                    property real dark: g.dark ? 1 : 0
                    property real debug: g.debug ? 1 : 0
                    property real shadowAmt: g.shadowAmt
                    property real flatInner: g.flatInner
                    property real rimTint: g.rimTint
                    property real ringW: g.ringW
                }
            }
        }
    }

    // Context for a group of glass slabs that all read ONE shared backdrop texture, so a whole panel full of
    // tiles and buttons costs a single backdrop capture instead of one per slab.
    component GlassCtx: QtObject {
        property var src: null                          // the ShaderEffectSource holding the backdrop
        property rect srcRect: Qt.rect(0, 0, 1, 1)      // where that texture sits, in `frame` coordinates
        property Item frame: null                       // coordinate space of srcRect (the popover layer)
        property bool liquid: false
        property url shaderUrl: ""
        property bool dark: true
        property real tint: 0.4
        property real strength: 1.0
        property real blur: 5               // base backdrop blur radius, px (settings slider)
        property real blurMul: 1.0          // scales the backdrop blur radius of every slab in this context
        property real liquidMul: 1.0        // scales refraction / dispersion / magnify of every slab in this context
        property real paneOpacity: 1.0      // <1 lets the compositor blur show through the shader pane
        property real rim: 0.45
        property real rimTint: 0            // 1 = rim + border line take a brighter shade of the glass's own local colour
        property real ringW: 0              // width (px) of the thin border line along the edge, 0 = none
        property color borderTint: "#8A9AB5"   // wallpaper's dominant colour, for the MenuBorder drawn over each slab
        property real borderAmount: 1          // strength of that MenuBorder
        property bool whiteEdge: true       // the light inner ring of the non-liquid pane (off for Spotlight: dark outline only)
        property real grain: 0.03
        property bool debug: false
        signal failed()
    }

    // Glass context for a bar popover, built the way the Control Center builds its own (blurred copy of the backdrop around the
    // popover + a GlassCtx), so the popover's background is drawn by the same GGlass / CornerBorder as the Control Center pages.
    component PopGlassCtx: Item {
        id: pg
        required property Item pop
        required property Item frame
        required property var source
        property real fullW: pop.width
        property real fullH: pop.height
        property bool fromCC: false                 // opened from the Control Center: keeps the global blur setting
        readonly property real topBarBlur: 42       // opened from the top bar: the stronger blur of the old version
        property alias ctx: pgc
        readonly property real m: 64 * root.barPopupScale
        ShaderEffectSource {
            id: pgSrc
            sourceItem: pg.source
            hideSource: true
            live: pg.pop.visible
            visible: false
            sourceRect: Qt.rect(pg.pop.x - pg.m, pg.pop.y - pg.m, pg.fullW * root.barPopupScale + 2 * pg.m, pg.fullH * root.barPopupScale + 2 * pg.m)
        }
        MultiEffect {
            id: pgFx
            source: pgSrc
            width: pgSrc.sourceRect.width; height: pgSrc.sourceRect.height
            blurEnabled: true
            blurMax: 64
            blur: Math.min(1.0, (pgc.blur * pgc.blurMul) * 1.4 / 64.0)
            autoPaddingEnabled: false
            visible: false
        }
        ShaderEffectSource {
            id: pgBlur
            sourceItem: pgFx
            live: pg.pop.visible
            visible: false
        }
        GlassCtx {
            id: pgc
            src: pgBlur
            srcRect: pgSrc.sourceRect
            frame: pg.frame
            liquid: root.liquidActive
            shaderUrl: root.glassShaderUrl
            dark: root.effDark
            tint: root.glassOpacity
            strength: root.glassLiquid
            rim: root.glassRim * 0.25
            rimTint: 1
            ringW: 0
            borderTint: root.menuBorderColor
            borderAmount: 1
            whiteEdge: false
            grain: root.glassGrain
            blur: pg.fromCC ? root.glassBlur : pg.topBarBlur
            debug: root.glassDebug
            onFailed: root.glassState = "failed"
        }
    }

    // One Liquid Glass slab (tile, button, pill, panel) sampling the shared backdrop of its GlassCtx
    component GGlass: Item {
        id: gg
        required property var gx
        property real cornerR: 22
        property real thickness: 24
        property real strengthMul: 1.0
        property real tintMul: 1.0
        property real shadowAmt: 0.5
        property real flatInner: 0          // 1 = drop the darker inner edge shading (needs the rebuilt liquidglass shader)
        readonly property real pad: 10

        // position inside the popover layer; reads every ancestor's x/y so it re-evaluates when anything moves
        function framePos() {
            var px = 0, py = 0, it = gg;
            while (it && it !== gx.frame) { px += it.x; py += it.y; it = it.parent; }
            return Qt.point(px, py);
        }
        readonly property point fp: framePos()

        Rectangle {
            visible: !gg.gx.liquid
            anchors.fill: parent
            radius: gg.cornerR
            // identical to the Dock's "Normal Blur" pane: a translucent tint over the compositor blur
            color: gg.gx.dark ? Qt.rgba(0.10, 0.10, 0.11, gg.gx.tint) : Qt.rgba(1, 1, 1, gg.gx.tint * 0.55)
            border.width: 1
            border.color: gg.gx.dark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(0, 0, 0, 0.12)
            Rectangle {
                anchors.fill: parent
                visible: gg.gx.whiteEdge
                anchors.margins: 1
                radius: parent.radius - 1
                color: "transparent"
                border.width: 1
                border.color: gg.gx.dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.45)
            }
        }
        Loader {
            anchors.fill: parent
            active: gg.gx.liquid && gg.gx.src !== null && gg.visible
            sourceComponent: Item {
                ShaderEffect {
                    x: -gg.pad; y: -gg.pad
                    width: gg.width + 2 * gg.pad
                    height: gg.height + 2 * gg.pad
                    fragmentShader: gg.gx.shaderUrl
                    onStatusChanged: if (status === ShaderEffect.Error) gg.gx.failed()
                    opacity: gg.gx.paneOpacity
                    property variant src: gg.gx.src
                    property vector2d itemSize: Qt.vector2d(width, height)
                    property vector2d glassSize: Qt.vector2d(gg.width, gg.height)
                    property vector2d srcSize: Qt.vector2d(gg.gx.srcRect.width, gg.gx.srcRect.height)
                    property vector2d srcOffset: Qt.vector2d(gg.fp.x - gg.pad - gg.gx.srcRect.x,
                                                             gg.fp.y - gg.pad - gg.gx.srcRect.y)
                    property real pad: gg.pad
                    property real radius: gg.cornerR
                    property real bezel: Math.min(gg.height * 0.36, 26)
                    property real thickness: gg.thickness * gg.gx.strength * gg.strengthMul * gg.gx.liquidMul * 1.6
                    property real dispersion: 0.06 * gg.gx.strength * gg.strengthMul * gg.gx.liquidMul * 1.3
                    property real magnify: 0.05 * gg.gx.strength * gg.strengthMul * gg.gx.liquidMul * 1.6
                    property real rim: gg.gx.rim
                    property real grain: gg.gx.grain * 0.2
                    property real blurPx: 1.5
                    property real tintMix: gg.gx.tint * 0.55 * gg.tintMul
                    property real saturation: 1.25
                    property real dark: gg.gx.dark ? 1 : 0
                    property real debug: gg.gx.debug ? 1 : 0
                    property real shadowAmt: gg.shadowAmt
                    property real flatInner: gg.flatInner
                    property real rimTint: gg.gx.rimTint
                    property real ringW: gg.gx.ringW
                }
            }
        }
    }

    // Control Center tile: its own Liquid Glass slab (children are laid on top of it)
    component CCTile: Item {
        id: tile
        required property var t
        required property var gx
        property real radius: 34
        // the whole tile is the button: a click anywhere fires clicked(); the round icon inside only shows the on / off state
        property bool on: false
        property string onTint: ""
        property bool clickable: false
        // small icon-only tiles (the "circle buttons"): when on, the whole tile turns white. Wide tiles keep their glass
        // (only the round icon inside them turns white), so their text colours stay as they are.
        readonly property bool whole: on && width <= 110
        readonly property color fg: whole ? Qt.rgba(0.07, 0.07, 0.09, 1) : t.fg
        readonly property color fg2: whole ? Qt.rgba(0.07, 0.07, 0.09, 0.55) : t.fg2
        signal clicked()
        scale: (clickable && tma.pressed) ? 0.97 : 1
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }
        GGlass { anchors.fill: parent; gx: tile.gx; cornerR: tile.radius; thickness: 22; shadowAmt: 0; flatInner: 1 }
        Rectangle {     // enabled (small tiles only): the whole tile background is solid white
            anchors.fill: parent
            radius: tile.radius
            color: "white"
            opacity: tile.whole ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        }
        Rectangle {
            anchors.fill: parent
            radius: tile.radius
            color: (tile.clickable && tma.containsMouse) ? (tile.t.dark ? Qt.rgba(1, 1, 1, 0.025) : Qt.rgba(1, 1, 1, 0.07)) : Qt.rgba(1, 1, 1, 0)
            Behavior on color { ColorAnimation { duration: 320; easing.type: Easing.OutCubic } }
        }
        CornerBorder { z: 2; anchors.fill: parent; cornerR: tile.radius; dark: tile.gx.dark; tint: tile.gx.borderTint; amount: tile.gx.borderAmount; lineW: 0.8 }
        MouseArea { id: tma; anchors.fill: parent; enabled: tile.clickable; hoverEnabled: true; onClicked: tile.clicked() }
    }

    // small glass pill button ("Edit Controls", "Done", "Reset")
    component CCPill: Item {
        id: pl
        required property var t
        required property var gx
        property string text: ""
        property bool strong: false
        signal clicked()
        width: plText.implicitWidth + 32; height: 28
        GGlass { anchors.fill: parent; gx: pl.gx; cornerR: 14; thickness: 14; strengthMul: 0.6; shadowAmt: 0; flatInner: 1 }
        CornerBorder { z: 2; anchors.fill: parent; cornerR: 14; dark: pl.gx.dark; tint: pl.gx.borderTint; amount: pl.gx.borderAmount; lineW: 0.8 }
        Rectangle {
            anchors.fill: parent; radius: 14
            color: pla.containsMouse ? (pl.t.dark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(1, 1, 1, 0.09)) : Qt.rgba(1, 1, 1, 0)
        }
        Text {
            id: plText
            anchors.centerIn: parent
            text: pl.text
            color: pl.t.fg; font.family: root.fontForWeight(font.weight, pl.t.fam); font.pixelSize: 12
            font.weight: pl.strong ? Font.DemiBold : Font.Normal
        }
        MouseArea { id: pla; anchors.fill: parent; hoverEnabled: true; onClicked: pl.clicked() }
    }

    // round glyph button: Liquid Glass disc, accent-coloured glass when "on"
    // Contour glow (hover): a thin light line along the rounded outline + soft halo, brightest near the cursor
    component ContourGlow: ShaderEffect {
        id: cgl
        property real cornerR: 24
        property bool hovered: false
        property point at: Qt.point(width / 2, height / 2)      // cursor, in the shape's coordinates
        property real pad: 14
        property color glowColor: "white"
        anchors.fill: parent
        anchors.margins: -pad
        fragmentShader: Qt.resolvedUrl("contourglow.frag.qsb")
        property vector2d itemSize: Qt.vector2d(width, height)
        property vector2d mouse: Qt.vector2d(at.x, at.y)
        property real cornerRadius: cornerR
        property real amount: hovered ? 1 : 0
        Behavior on amount { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        property real spread: Math.max(40, Math.min(width, height) * 0.9)
        property vector4d tint: Qt.vector4d(glowColor.r, glowColor.g, glowColor.b, 1)
        visible: amount > 0.005
    }

    component CCBtn: Item {
        id: b
        required property var t
        required property var gx
        property string kind: ""
        property bool on: false
        property real level: 3
        property bool flag: false
        property string onTint: ""
        property real d: 40
        property real shadow: 0
        signal clicked()
        property bool bounce: false
        property bool glass: true       // false: a flat circle instead of a Liquid Glass disc
        property bool matchMenuBorder: false // use the same outline primitive as Spotlight's search pill
        property bool plain: false      // icon only: no glass disc and no click area of its own (the tile is the button)
        readonly property bool inWide: plain && parent && parent.width > 110     // icon on a wide (two-cell) tile
        // icon on a small (one-cell) tile = a "circle button": a little smaller circle with a bigger icon
        readonly property bool circleBtn: plain && parent && parent.width <= 110
        width: circleBtn ? 21 : d; height: width
        scale: (bounce && bma.pressed) ? 0.88 : 1
        Behavior on scale { NumberAnimation { duration: 230; easing.type: Easing.OutBack; easing.overshoot: 3.2 } }
        GGlass { visible: !b.plain && b.glass; anchors.fill: parent; gx: b.gx; cornerR: b.d / 2; thickness: 14; strengthMul: 0.6; shadowAmt: 0; flatInner: 1 }
        CornerBorder { visible: !b.plain && b.glass && !b.matchMenuBorder; z: 2; anchors.fill: parent; cornerR: b.d / 2; dark: b.gx.dark; tint: b.gx.borderTint; amount: b.gx.borderAmount; lineW: 0.8 }
        MenuBorder { visible: !b.plain && b.glass && b.matchMenuBorder; z: 2; anchors.fill: parent; cornerR: b.d / 2; dark: root.panelDarkMode; tint: root.menuBorderColor; amount: 0.5 }
        Rectangle {
            anchors.fill: parent
            radius: b.width / 2
            // enabled: solid white fill (the icon carries the accent colour); off: grey circle only on wide tiles
            color: b.on ? "white"
                        : (b.plain ? (b.inWide ? (b.t.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.14))      // wide tile: grey circle while off
                                               : Qt.rgba(1, 1, 1, 0))                                                 // small tile: none
                                   : (!b.glass ? (b.t.dark ? Qt.rgba(1, 1, 1, bma.containsMouse ? 0.22 : 0.16) : Qt.rgba(0, 0, 0, bma.containsMouse ? 0.18 : 0.14))   // flat, no glass
                                               : (bma.containsMouse ? (b.t.dark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(1, 1, 1, 0.09)) : Qt.rgba(1, 1, 1, 0))))
            Behavior on color { ColorAnimation { duration: 320; easing.type: Easing.OutCubic } }
        }
        // state flip: the icon dips, turns a touch and springs back (motion), while the fill fades
        property real pop: 0
        onOnChanged: popAnim.restart()
        SequentialAnimation {
            id: popAnim
            NumberAnimation { target: b; property: "pop"; to: 1; duration: 120; easing.type: Easing.OutCubic }
            NumberAnimation { target: b; property: "pop"; to: 0; duration: 420; easing.type: Easing.OutQuint }
        }
        Glyph {
            scale: 1 - 0.22 * b.pop
            rotation: (b.on ? -14 : 14) * b.pop
            anchors.centerIn: parent
            width: b.circleBtn ? 23 : b.width * 0.46; height: width
            kind: b.kind; level: b.level; flag: b.flag
            color: b.on ? (b.onTint !== "" ? Qt.color(b.onTint) : b.t.accent) : b.t.fg
            Behavior on color { ColorAnimation { duration: 320; easing.type: Easing.OutCubic } }
        }
        MouseArea { id: bma; anchors.fill: parent; enabled: !b.plain; hoverEnabled: true; onClicked: b.clicked() }
    }

    // thin-line slider: icon at each end, slim rounded track between them
    component CCSlider: Item {
        id: s
        required property var t
        property real value: 0
        property string leftKind: "sun"
        property string rightKind: "sun"
        property real leftLevel: 1
        property real rightLevel: 3
        property var gx: null               // glass context: when set, the knob turns into Liquid Glass while it is held
        property real glassMul: 1.0         // refraction boost for the knob (the macOS-style panel runs its glass very softly)
        signal moved(real v)
        height: 28
        property bool tileHover: false        // the pointer is anywhere over the tile that holds this slider
        readonly property bool hovering: sma.containsMouse || sma.pressed || tileHover
        // knob animation state: hover pops a rounded square in, holding it springs it bigger and turns it to glass
        property real hoverT: hovering ? 1 : 0
        Behavior on hoverT { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
        property real pressT: sma.pressed ? 1 : 0
        Behavior on pressT { NumberAnimation { duration: sma.pressed ? 420 : 300; easing.type: Easing.OutBack; easing.overshoot: 3.0 } }
        readonly property real trackX: 28
        readonly property real trackW: Math.max(1, s.width - 28 - 26)
        // jiggle: the knob stretches, leans and wobbles when the value moves; how hard depends on how fast it moves.
        // `vel` is the smoothed speed (px/ms); `jig` chases a target set from it through a spring, so it overshoots and rings
        // out after the movement stops (the target goes back to 0 shortly after the last change).
        property real vel: 0
        property real jig: 0
        property real lastV: value
        property real lastT: 0
        Behavior on jig { SpringAnimation { spring: 3.4; damping: 0.2; epsilon: 0.004 } }
        onValueChanged: {
            var now = Date.now();
            if (lastT > 0) {
                var dt = Math.max(1, now - lastT);
                vel = vel * 0.45 + ((value - lastV) * trackW / dt) * 0.55;
                jig = Math.max(-1.5, Math.min(1.5, vel * 0.6));
            }
            lastV = value; lastT = now;
            jigIdle.restart();
        }
        Timer { id: jigIdle; interval: 70; onTriggered: { s.vel = 0; s.jig = 0; } }
        Glyph {
            x: 4; anchors.verticalCenter: parent.verticalCenter
            width: 16; height: 16
            kind: s.leftKind; level: s.leftLevel
            color: s.t.fg
        }
        Rectangle {
            x: s.trackX; width: s.trackW; height: 4; radius: 2
            anchors.verticalCenter: parent.verticalCenter
            color: s.t.track
        }
        Rectangle {
            x: s.trackX
            width: Math.max(0, Math.min(1, s.value)) * s.trackW
            height: 4; radius: 2
            anchors.verticalCenter: parent.verticalCenter
            color: s.t.fg
        }
        Glyph {
            x: s.width - 20; anchors.verticalCenter: parent.verticalCenter
            width: 16; height: 16
            kind: s.rightKind; level: s.rightLevel
            color: s.t.fg2
        }
        // the knob: a rounded square on hover; held, it grows with a little spring and becomes Liquid Glass
        Item {
            id: knob
            readonly property real kw: 21 + 6 * s.pressT
            readonly property real kh: 14 + 3 * s.pressT
            width: Math.max(1, kw); height: Math.max(1, kh)
            x: s.trackX + Math.max(0, Math.min(1, s.value)) * s.trackW - width / 2 - s.jig * 3     // trails a little behind when moving
            anchors.verticalCenter: parent.verticalCenter
            visible: s.hoverT > 0.01
            opacity: Math.min(1, s.hoverT * 1.6)
            scale: 0.5 + 0.5 * s.hoverT
            rotation: s.jig * 7
            transform: Scale {      // squash and stretch along the movement: longer and flatter the faster it goes
                origin.x: knob.width / 2; origin.y: knob.height / 2
                xScale: 1 + 0.32 * Math.min(1.5, Math.abs(s.jig))
                yScale: 1 - 0.16 * Math.min(1.5, Math.abs(s.jig))
            }
            readonly property real rad: Math.max(2, Math.min(height / 2, 8 + 3 * s.pressT))
            // solid white-ish square (fades out while the glass takes over)
            Rectangle {
                anchors.fill: parent
                radius: knob.rad
                color: s.t.fg
                opacity: s.gx ? Math.max(0, 1 - s.pressT * 1.4) : 1
            }
            Loader {
                anchors.fill: parent
                active: s.gx !== null && s.pressT > 0.02
                opacity: Math.min(1, s.pressT * 1.6)
                sourceComponent: Item {
                    GGlass { anchors.fill: parent; gx: s.gx; cornerR: knob.rad; thickness: 16; strengthMul: s.glassMul * 0.85; shadowAmt: 0.5 }
                    // the slider bar seen through the glass: the part of the track that lies under the knob
                    Item {
                        anchors.fill: parent
                        clip: true
                        Rectangle {
                            x: s.trackX - knob.x; width: s.trackW; height: 4; radius: 2
                            anchors.verticalCenter: parent.verticalCenter
                            color: Qt.rgba(s.t.fg.r, s.t.fg.g, s.t.fg.b, 0.35)
                        }
                        Rectangle {
                            x: s.trackX - knob.x
                            width: Math.max(0, Math.min(1, s.value)) * s.trackW
                            height: 4; radius: 2
                            anchors.verticalCenter: parent.verticalCenter
                            color: Qt.rgba(s.t.fg.r, s.t.fg.g, s.t.fg.b, 0.9)
                        }
                    }
                    // edge: the same border as the Control Center buttons (thin, brighter shade of the background, fading out at the top-right and bottom-left corners, a bit translucent)
                    CornerBorder { z: 2; anchors.fill: parent; cornerR: knob.rad; dark: s.gx.dark; tint: s.gx.borderTint; amount: s.gx.borderAmount; lineW: 0.8 }
                    // glassy sheen: a soft specular highlight along the top, fading out towards the middle
                    Rectangle {
                        anchors.fill: parent
                        radius: knob.rad
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, s.t.dark ? 0.12 : 0.2) }
                            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.02) }
                            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, s.t.dark ? 0.04 : 0.08) }
                        }
                    }
                }
            }
        }
        MouseArea {
            id: sma
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            function setFrom(mx) { s.moved(Math.max(0, Math.min(1, (mx - s.trackX) / s.trackW))); }
            onPressed: mouse => setFrom(mouse.x)
            onPositionChanged: mouse => { if (pressed) setFrom(mouse.x); }
        }
    }

    // one device row of the sound popover: round icon (accent when it is the active device), name, optional second line
    component AudioRow: Item {
        id: ar
        required property var t
        property string title: ""
        property string sub: ""
        property string kind: "speaker"
        property bool selected: false
        signal clicked()
        width: parent ? parent.width : 300
        height: 46
        Rectangle {
            anchors.fill: parent
            radius: 12
            color: ar.t.hover
            opacity: arMa.containsMouse ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 90 } }
        }
        Rectangle {
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 32; height: 32; radius: 16
            color: ar.selected ? ar.t.accent : ar.t.btnOff
            Behavior on color { ColorAnimation { duration: 120 } }
            Glyph { anchors.centerIn: parent; width: 16; height: 16; kind: ar.kind; level: 3; color: ar.selected ? "white" : ar.t.fg }
        }
        Column {
            x: 50
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 50 - 14
            spacing: 1
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: ar.title
                color: ar.t.fg
                font.family: root.fontForWeight(font.weight, ar.t.fam); font.pixelSize: 13
                font.weight: ar.selected ? Font.DemiBold : Font.Normal
            }
            Text {
                visible: ar.sub !== ""
                width: parent.width
                elide: Text.ElideRight
                text: ar.sub
                color: ar.t.fg2
                font.family: root.fontForWeight(font.weight, ar.t.fam); font.pixelSize: 11
            }
        }
        MouseArea { id: arMa; anchors.fill: parent; hoverEnabled: true; onClicked: ar.clicked() }
    }

    // ── notification card contents (used by the popups and by the notification centre) ──
    component NotifBody: Item {
        id: nb
        required property var t
        property string app: ""
        property string summary: ""
        property string body: ""
        property string icon: ""
        property int urgency: 1
        property real stamp: 0
        property real nowMs: 0
        property bool showClose: false
        property bool showTime: false
        signal closeClicked()
        width: parent ? parent.width : 340
        height: Math.max(74, textCol.height + 30)

        readonly property string agoText: {
            var m = Math.floor((nb.nowMs - nb.stamp) / 60000);
            return m < 1 ? "now" : (m < 60 ? m + "m ago" : (m < 1440 ? Math.floor(m / 60) + "h ago" : Math.floor(m / 1440) + "d ago"));
        }

        Item {
            x: 14; y: 15; width: 44; height: 44
            Rectangle {
                anchors.fill: parent; radius: 10
                visible: nimg.status !== Image.Ready
                color: nb.t.accent
                Glyph { anchors.centerIn: parent; width: 24; height: 24; kind: "bell"; color: "white" }
            }
            Image {
                id: nimg
                anchors.fill: parent
                visible: status === Image.Ready
                source: nb.icon
                sourceSize.width: 96; sourceSize.height: 96
                fillMode: Image.PreserveAspectFit
                asynchronous: true; smooth: true
            }
        }
        Column {
            id: textCol
            // a notification updated in place (same id, new text): blur out, refocus on the new wording
            property real refocus: 0
            layer.enabled: refocus > 0.001
            layer.effect: MultiEffect { blurEnabled: true; blurMax: 32; blur: textCol.refocus; autoPaddingEnabled: true }
            opacity: 1 - 0.5 * refocus
            NumberAnimation { id: refocusAnim; target: textCol; property: "refocus"; from: 1; to: 0; duration: 460; easing.type: Easing.OutQuint }
            Connections {
                target: nb
                function onSummaryChanged() { refocusAnim.restart(); }
                function onBodyChanged() { refocusAnim.restart(); }
            }
            x: 70; y: 14
            width: parent.width - 70 - 44
            spacing: 1
            Text {
                width: parent.width
                text: nb.urgency === 2 ? I18n.tr("TIME SENSITIVE") : nb.app
                horizontalAlignment: /[\u0590-\u08ff]/.test(text) ? Text.AlignRight : Text.AlignLeft
                visible: text !== ""
                color: nb.urgency === 2 ? nb.t.fg2 : nb.t.fg
                font.family: root.fontForWeight(font.weight, nb.t.fam); font.pixelSize: nb.urgency === 2 ? 12 : 14
                font.weight: Font.DemiBold
                font.letterSpacing: nb.urgency === 2 ? 0.4 : 0
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: nb.summary
                horizontalAlignment: /[\u0590-\u08ff]/.test(text) ? Text.AlignRight : Text.AlignLeft
                visible: text !== ""
                color: nb.t.fg
                font.family: root.fontForWeight(font.weight, nb.t.fam); font.pixelSize: 14; font.weight: Font.Bold
                wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: nb.body
                horizontalAlignment: /[\u0590-\u08ff]/.test(text) ? Text.AlignRight : Text.AlignLeft
                visible: text !== ""
                color: nb.t.fg
                font.family: root.fontForWeight(font.weight, nb.t.fam); font.pixelSize: 13
                wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
            }
        }
        Text {
            visible: nb.showTime && !nb.showClose
            anchors.right: parent.right; anchors.rightMargin: 14
            y: 15
            text: nb.agoText
            color: nb.t.fg2
            font.family: root.fontForWeight(font.weight, nb.t.fam); font.pixelSize: 12
        }
        Rectangle {
            id: xbtn
            visible: nb.showClose
            anchors.right: parent.right; anchors.rightMargin: 10
            y: 10
            width: 22; height: 22; radius: 11
            color: xma.containsMouse ? nb.t.btnHover : nb.t.btnOff
            Glyph { anchors.centerIn: parent; width: 12; height: 12; kind: "close"; color: nb.t.fg }
            MouseArea { id: xma; anchors.fill: parent; hoverEnabled: true; onClicked: nb.closeClicked() }
        }
    }

    // ── settings window pieces ──
    component PRow: Item {
        id: r
        required property var t
        property string title: ""
        default property alias control: slot.data
        width: parent ? parent.width : 0
        height: 42
        Rectangle { visible: r.y > 0.5; x: 14; width: parent.width - 14; height: 1; color: r.t.sep }
        Text {
            x: 14; anchors.verticalCenter: parent.verticalCenter
            text: r.title; color: r.t.fg
            font.family: root.fontForWeight(font.weight, r.t.fam); font.pixelSize: 13
        }
        Item {
            id: slot
            anchors.right: parent.right; anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width; height: childrenRect.height
        }
    }
    component PCard: Rectangle {
        required property var t
        default property alias content: pcol.data
        width: parent ? parent.width : 0
        height: pcol.implicitHeight
        radius: 10
        color: t.card
        border.width: 1
        border.color: t.cardBorder
        Column { id: pcol; width: parent.width }
    }
    component PSwitch: GlassSwitch {
        required property var t
        accentColor: "#30D158"
        offColor: t.switchOff
        dark: t.dark
        baseColor: t.dark ? "#2B2B2D" : "#FFFFFF"
        glass: root.liquidActive
        shaderUrl: root.glassShaderUrl
        glassLiquid: root.glassLiquid
        glassRim: root.glassRim
        glassGrain: root.glassGrain
        glassTint: root.glassOpacity
        borderTint: root.menuBorderColor
        onGlassFailed: root.glassState = "failed"
    }
    // same slider as the Control Center (see GlassSlider.qml)
    component PSlider: GlassSlider {
        required property var t
        decimals: 2
        width: 190
        fg: t.fg
        trackColor: t.track
        labelColor: t.fg2
        fontFamily: t.fam
        dark: t.dark
        baseColor: t.dark ? "#2B2B2D" : "#FFFFFF"
        glass: root.liquidActive
        shaderUrl: root.glassShaderUrl
        glassLiquid: root.glassLiquid
        glassRim: root.glassRim
        glassGrain: root.glassGrain
        glassTint: root.glassOpacity
        borderTint: root.menuBorderColor
        onGlassFailed: root.glassState = "failed"
    }
    component PSeg: Item {
        id: sg
        required property var t
        property var model: []
        property int current: 0
        property real segWidth: 100
        signal picked(int index)
        width: model.length * segWidth + 4; height: 26
        Rectangle { anchors.fill: parent; radius: 7; color: sg.t.btnOff }
        Rectangle {
            y: 2; x: 2 + sg.current * sg.segWidth; width: sg.segWidth; height: parent.height - 4; radius: 5
            color: sg.t.dark ? "#636366" : "#FFFFFF"
            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
        Row {
            x: 2; y: 2
            Repeater {
                model: sg.model
                delegate: Item {
                    required property var modelData
                    required property int index
                    width: sg.segWidth; height: sg.height - 4
                    Text {
                        anchors.centerIn: parent; text: I18n.tr(parent.modelData)
                        color: sg.t.fg
                        font.family: root.fontForWeight(font.weight, sg.t.fam); font.pixelSize: 12
                    }
                    MouseArea { anchors.fill: parent; onClicked: sg.picked(parent.index) }
                }
            }
        }
    }

    // ═════════════ STATE & DATA SOURCES ═════════════
    SystemClock { id: clock; precision: root.showSeconds ? SystemClock.Seconds : SystemClock.Minutes }

    readonly property string clockText: {
        var d = clock.date;
        var tf = root.use24h ? (root.showSeconds ? "HH:mm:ss" : "HH:mm") : (root.showSeconds ? "h:mm:ss AP" : "h:mm AP");
        var t = Qt.formatDateTime(d, tf);
        return root.showDate ? I18n.locale().toString(d, "ddd d MMM") + "  " + t : t;
    }

    // active app
    function lookup(appId) {
        if (!appId) return null;
        var e = DesktopEntries.byId(appId);
        if (!e && DesktopEntries.heuristicLookup) e = DesktopEntries.heuristicLookup(appId);
        return e;
    }
    readonly property var activeTl: ToplevelManager.activeToplevel
    readonly property string activeAppId: activeTl ? (activeTl.appId || "") : ""
    readonly property string appName: {
        if (activeAppId === "") return I18n.tr("Desktop");
        // MacShell's own windows (all "org.quickshell")
        if (activeAppId === "org.quickshell") return (activeTl.title === "Clock" || activeTl.title === "App Store") ? I18n.tr(activeTl.title)
                                                     : (activeTl.title === "macshell Settings" ? I18n.tr("System Settings") : "MacShell");
        var e = lookup(activeAppId);
        return e ? e.name : activeAppId;
    }
    // Hyprland's view of the focused window (floating / fullscreen / pinned / pid ...), refreshed when a menu opens
    property var activeWin: null
    function refreshActive() { if (!awProc.running) awProc.running = true; }
    onActiveTlChanged: { refreshActive(); swTrack(); }      // swTrack = window-switcher recent-app order
    Process {
        id: awProc
        command: ["hyprctl", "-j", "activewindow"]
        stdout: StdioCollector {
            onStreamFinished: {
                var o = null;
                try { o = JSON.parse(text); } catch (err) { o = null; }
                root.activeWin = (o && o.address) ? o : null;
            }
        }
    }
    readonly property var menuTitles: [
        { id: "apple", label: "" },
        { id: "app", label: appName, bold: true },
        { id: "file", label: I18n.tr("File") },
        { id: "edit", label: I18n.tr("Edit") },
        { id: "view", label: I18n.tr("View") },
        { id: "window", label: I18n.tr("Window") },
        { id: "help", label: I18n.tr("Help") }
    ]

    // audio
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [root.sink] }
    readonly property real volume: (sink && sink.audio) ? sink.audio.volume : 0
    readonly property bool muted: (sink && sink.audio) ? sink.audio.muted : false
    // The OSD mirrors hardware-key changes as well as changes made from this shell.
    property bool osdReady: false
    property bool osdVisible: false
    property string osdKind: "volume"
    property real osdValue: 0
    // The OSD is for hardware keys only: changes made from this shell (Control Center, volume popover, bar scroll,
    // device switching) open a short quiet window for their kind, during which the resulting change is not shown.
    property real osdQuietVolUntil: 0
    property real osdQuietBrightUntil: 0
    function osdQuiet(kind, ms) {
        var t = Date.now() + ms;
        if (kind === "brightness") osdQuietBrightUntil = Math.max(osdQuietBrightUntil, t);
        else osdQuietVolUntil = Math.max(osdQuietVolUntil, t);
    }
    // ── UI sounds (synthesized macOS-style set in ~/.local/share/sounds/macshell, see macshell-make-sounds.py) ──
    readonly property string soundDir: Quickshell.env("HOME") + "/.local/share/sounds/macshell"
    property var soundLast: ({})
    function playSound(name, vol) {
        if (!uiSounds || gaming) return;
        var now = Date.now(), last = soundLast[name] || 0;
        if (now - last < 90) return;                 // a burst of volume steps → one pop per step, not a buzz
        soundLast[name] = now;
        Quickshell.execDetached(["pw-play", "--volume=" + (vol === undefined ? 0.8 : vol), soundDir + "/" + name + ".wav"]);
    }
    onChargingChanged: if (charging && osdReady) playSound("charge")
    function showOsd(kind, value) {
        if (!osdReady) return;
        if (Date.now() < (kind === "brightness" ? osdQuietBrightUntil : osdQuietVolUntil)) return;
        if (kind === "volume") playSound("pop", 0.55 + 0.45 * Math.max(0, Math.min(1, value)));
        osdKind = kind;
        osdValue = Math.max(0, Math.min(1, value));
        osdVisible = true;
        osdTimer.restart();
    }
    onVolumeChanged: showOsd("volume", muted ? 0 : volume)
    onMutedChanged: showOsd("volume", muted ? 0 : volume)
    Timer { id: osdTimer; interval: 1500; onTriggered: root.osdVisible = false }
    Timer { interval: 1200; running: true; repeat: false; onTriggered: root.osdReady = true }
    function setVolume(v) { osdQuiet("volume", 600); if (sink && sink.audio) { sink.audio.muted = false; sink.audio.volume = Math.max(0, Math.min(1, v)); } }
    function toggleMute() { osdQuiet("volume", 600); if (sink && sink.audio) sink.audio.muted = !sink.audio.muted; }
    readonly property var micSource: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [root.micSource] }
    readonly property bool micMuted: (micSource && micSource.audio) ? micSource.audio.muted : true
    function toggleMicMute() { if (micSource && micSource.audio) micSource.audio.muted = !micSource.audio.muted; }
    readonly property real volLevel: muted || volume <= 0.001 ? 0 : (volume < 0.34 ? 1 : (volume < 0.67 ? 2 : 3))
    readonly property real micVolume: (micSource && micSource.audio) ? micSource.audio.volume : 0
    function setMicVolume(v) { if (micSource && micSource.audio) { micSource.audio.muted = false; micSource.audio.volume = Math.max(0, Math.min(1, v)); } }

    // Device lists come straight from the PipeWire graph, so plugging in headphones / a headset updates the picker at once.
    PwObjectTracker { objects: Pipewire.nodes.values }
    function audioDevices(wantOutput) {
        var ns = Pipewire.nodes.values, out = [];
        for (var i = 0; i < ns.length; i++) {
            var n = ns[i];
            if (!n || !n.audio || n.isStream) continue;
            var isOut = n.type !== undefined ? ((n.type & PwNodeType.Sink) !== 0 && (n.type & PwNodeType.Source) === 0) : n.isSink;
            var isIn = n.type !== undefined ? ((n.type & PwNodeType.Source) !== 0 && (n.type & PwNodeType.Sink) === 0) : !n.isSink;
            if (wantOutput ? isOut : isIn) out.push(n);
        }
        out.sort(function (a, b) { return String(a.description || a.name).localeCompare(String(b.description || b.name)); });
        return out;
    }
    // Group playback streams by application: one control per app, even if it owns multiple output streams.
    property int audioTick: 0
    function audioApps() {
        var tick = audioTick, ns = Pipewire.nodes.values, groups = {}, out = [];
        for (var i = 0; i < ns.length; i++) {
            var n = ns[i];
            if (!n || !n.audio || !n.isStream) continue;
            var playback = n.type !== undefined ? ((n.type & PwNodeType.AudioOutStream) !== 0) : !n.isSink;
            if (!playback) continue;
            var p = n.properties || {};
            var name = String(p["application.name"] || p["node.description"] || n.description || p["application.process.binary"] || p["node.name"] || n.name || "App");
            if (name.toLowerCase() === "peak detect") continue;
            var key = String(p["application.id"] || p["application.process.binary"] || name).toLowerCase();
            if (!groups[key]) groups[key] = { key: key, name: name, nodes: [], volume: 0, muted: true };
            var g = groups[key];
            g.nodes.push(n);
            g.volume += Math.max(0, Math.min(1, Number(n.audio.volume) || 0));
            g.muted = g.muted && !!n.audio.muted;
        }
        for (var k in groups) {
            var g = groups[k];
            g.volume /= Math.max(1, g.nodes.length);
            out.push(g);
        }
        out.sort(function (a, b) { return a.name.localeCompare(b.name); });
        return out;
    }
    readonly property var appAudioStreams: audioApps()
    // The list of apps the sliders are built from only changes when an app appears or goes away. appAudioStreams is rebuilt on
    // every volume tick, and feeding it straight to the Repeater destroyed the slider under your finger mid-drag.
    property var appAudioKeys: []
    function syncAppKeys() {
        var k = [], l = appAudioStreams;
        for (var i = 0; i < l.length; i++) k.push(l[i].key);
        if (JSON.stringify(k) !== JSON.stringify(appAudioKeys)) appAudioKeys = k;
    }
    onAppAudioStreamsChanged: syncAppKeys()
    function appByKey(key) {
        var l = appAudioStreams;
        for (var i = 0; i < l.length; i++) if (l[i].key === key) return l[i];
        return null;
    }
    function setAppVolume(app, v) {
        if (!app || !app.nodes) return;
        osdQuiet("volume", 600);
        var value = Math.max(0, Math.min(1, v));
        for (var i = 0; i < app.nodes.length; i++) {
            var n = app.nodes[i];
            if (n && n.audio) { n.audio.muted = false; n.audio.volume = value; }
        }
    }
    readonly property var audioOutputs: audioDevices(true)
    readonly property var audioInputs: audioDevices(false)
    function audioKind(n, isOut) {
        if (!isOut) return "mic";
        var p = n.properties || {}, f = String(p["device.form-factor"] || "").toLowerCase();
        var t = (String(n.description) + " " + String(n.name)).toLowerCase();
        if (f === "headphone" || f === "headset" || /headphone|headset|airpods|buds|bluez/.test(t)) return "headphones";
        if (f === "hdmi" || f === "tv" || f === "monitor" || /hdmi|displayport|display port/.test(t)) return "monitor";
        return "speaker";
    }
    // "Family 17h HD Audio Controller Analog Stereo" -> ["Family 17h HD Audio Controller", "Analog Stereo"]
    function audioSplit(d) {
        d = String(d || "");
        var m = /^(.*?)\s+((?:Analog|Digital|Pro|Stereo|Mono|Speaker|Headphones|Headset|Microphone|Line|HDMI|DisplayPort|S\/PDIF|Surround)\b.*)$/i.exec(d);
        return (m && m[1].length > 2) ? [m[1], m[2]] : [d, ""];
    }
    function chooseAudio(n) {      // make this device the default; wpctl ships with WirePlumber, pactl is the fallback
        if (!n) return;
        osdQuiet("volume", 1500);
        Quickshell.execDetached(["sh", "-c", "wpctl set-default \"$1\" 2>/dev/null || pactl \"$3\" \"$2\"", "sh", String(n.id), String(n.name),
                                 (n.type !== undefined ? ((n.type & PwNodeType.Sink) !== 0) : n.isSink) ? "set-default-sink" : "set-default-source"]);
    }

    // battery
    readonly property var bat: UPower.displayDevice
    readonly property bool hasBattery: bat !== null && bat !== undefined && bat.isPresent
    readonly property real batPct: {
        if (!hasBattery) return 0;
        var p = bat.percentage;
        return Math.round(p <= 1.0 ? p * 100 : p);
    }
    readonly property bool charging: hasBattery && (bat.state === UPowerDeviceState.Charging
                                                     || bat.state === UPowerDeviceState.FullyCharged)

    // media
    readonly property var player: {
        var ps = Mpris.players.values, best = null;
        for (var i = 0; i < ps.length; i++) {
            if (ps[i].isPlaying) return ps[i];
            if (!best) best = ps[i];
        }
        return best;
    }

    // wifi
    property bool wifiOn: true
    property string wifiSsid: ""
    property int wifiSignal: 0
    property bool ethernetUp: false             // a wired connection is up (shown with Apple's <···> symbol when Wi-Fi isn't in use)
    readonly property bool showEthernet: ethernetUp && wifiSsid === ""
    readonly property int wifiLevel: !wifiOn ? 0 : (wifiSsid === "" ? 0 : (wifiSignal > 66 ? 3 : (wifiSignal > 33 ? 2 : 1)))
    function refreshWifi() { if (!wifiProc.running) wifiProc.running = true; }
    Process {
        id: wifiProc
        command: ["sh", "-c", "nmcli radio wifi 2>/dev/null; nmcli -t -f ACTIVE,SSID,SIGNAL dev wifi 2>/dev/null | grep '^yes' | head -n1; echo; nmcli -t -f TYPE,STATE dev 2>/dev/null | grep -q '^ethernet:connected$' && echo eth || echo -"]
        stdout: StdioCollector {
            onStreamFinished: {
                var l = text.split("\n");
                root.wifiOn = (l[0] || "").trim() === "enabled";
                root.ethernetUp = l.some(function (x) { return x.trim() === "eth"; });
                var a = (l[1] || "").trim();
                if (a !== "") {
                    var parts = a.split(":");
                    root.wifiSignal = parseInt(parts[parts.length - 1]) || 0;
                    root.wifiSsid = parts.slice(1, parts.length - 1).join(":").replace(/\\/g, "");
                } else { root.wifiSsid = ""; root.wifiSignal = 0; }
            }
        }
    }
    function toggleWifi() {
        root.wifiOn = !root.wifiOn;
        Quickshell.execDetached(["nmcli", "radio", "wifi", root.wifiOn ? "on" : "off"]);
        settleTimer.restart();
    }

    // wifi network list (feeds the Wi-Fi popover)
    property var wifiNets: []                  // [{ ssid, signal, secure, inUse, saved }]
    property bool wifiScanning: false
    property string wifiBusy: ""               // ssid currently being joined
    property string wifiError: ""
    function sigLevel(s) { return s > 66 ? 3 : (s > 33 ? 2 : 1); }
    // split an `nmcli -t` line on unescaped colons (and unescape \: and \\)
    function splitNm(line) {
        var out = [], cur = "";
        for (var i = 0; i < line.length; i++) {
            var c = line[i];
            if (c === "\\" && i + 1 < line.length) { cur += line[i + 1]; i++; }
            else if (c === ":") { out.push(cur); cur = ""; }
            else cur += c;
        }
        out.push(cur);
        return out;
    }
    function nmErr(t) {
        var s = (t || "").trim().split("\n")[0].replace(/^Error:\s*/, "");
        if (/secrets were required|no secrets|password/i.test(s)) return "Incorrect password.";
        if (/no network with ssid|not found/i.test(s)) return "Network not found.";
        return s !== "" ? s : "Couldn't join the network.";
    }
    function scanWifi() {
        if (wifiListProc.running) return;
        wifiScanning = true;
        wifiListProc.running = true;
    }
    Process {
        id: wifiListProc
        command: ["sh", "-c",
            "nmcli dev wifi rescan >/dev/null 2>&1; "
            + "nmcli -t -f NAME,TYPE connection show 2>/dev/null | sed -n 's/:802-11-wireless$//p' | sed 's/^/S:/'; "
            + "nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list --rescan no 2>/dev/null | sed 's/^/N:/'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.split("\n"), saved = {}, best = {}, i, f;
                for (i = 0; i < lines.length; i++) {
                    if (lines[i].indexOf("S:") === 0) saved[root.splitNm(lines[i].substring(2))[0]] = true;
                }
                for (i = 0; i < lines.length; i++) {
                    if (lines[i].indexOf("N:") !== 0) continue;
                    f = root.splitNm(lines[i].substring(2));
                    if (f.length < 4 || f[1] === "") continue;
                    var ssid = f[1], sig = parseInt(f[2]) || 0, sec = f[3];
                    var n = { ssid: ssid, signal: sig, secure: (sec !== "" && sec !== "--"),
                              inUse: f[0] === "*", saved: saved[ssid] === true };
                    var o = best[ssid];
                    if (!o) best[ssid] = n;
                    else {
                        if (n.signal > o.signal) o.signal = n.signal;
                        if (n.inUse) o.inUse = true;
                    }
                }
                var arr = [];
                for (var k in best) arr.push(best[k]);
                arr.sort(function (a, b) {
                    if (a.inUse !== b.inUse) return a.inUse ? -1 : 1;
                    return b.signal - a.signal;
                });
                if (JSON.stringify(arr) !== JSON.stringify(root.wifiNets)) root.wifiNets = arr;
                root.wifiScanning = false;
            }
        }
        onExited: root.wifiScanning = false
    }
    function connectWifi(ssid, pw) {
        if (wifiConnProc.running) return;
        wifiError = "";
        wifiBusy = ssid;
        var cmd = ["nmcli", "--wait", "25", "dev", "wifi", "connect", ssid];
        if (pw && pw !== "") { cmd.push("password"); cmd.push(pw); }
        wifiConnProc.command = cmd;
        wifiConnProc.running = true;
    }
    Process {
        id: wifiConnProc
        stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") root.wifiError = root.nmErr(text) }
        onExited: (code, status) => {
            root.wifiBusy = "";
            if (code !== 0 && root.wifiError === "") root.wifiError = "Couldn't join the network.";
            if (code === 0) root.wifiError = "";
            wifiAfter.restart();
        }
    }
    function disconnectWifi() {
        sh("nmcli -t -f DEVICE,TYPE dev | grep ':wifi$' | cut -d: -f1 | head -n1 | xargs -r nmcli dev disconnect");
        wifiAfter.restart();
    }
    Timer { id: wifiAfter; interval: 1200; onTriggered: { root.scanWifi(); root.refreshWifi(); root.refreshConnections(); } }
    function refreshConnections() { if (!connProc.running) connProc.running = true; }
    Process {
        id: connProc
        command: ["sh", "-c", "nmcli -t -f NAME,TYPE,DEVICE connection show 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                var rows = [], lines = text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    if (!lines[i]) continue;
                    var f = root.splitNm(lines[i]);
                    if (f.length < 3) continue;
                    var type = f[1];
                    if (type !== "vpn" && type !== "802-3-ethernet") continue;
                    rows.push({ name: f[0], type: type, device: f[2] === "--" ? "" : f[2], active: f[2] !== "--" });
                }
                rows.sort(function (a,b) { return (b.active?1:0)-(a.active?1:0); });
                root.otherConnections = rows;
            }
        }
    }
    function toggleConnection(c) {
        if (!c) return;
        var args = c.active ? ["nmcli", "connection", "down", "id", c.name] : ["nmcli", "connection", "up", "id", c.name];
        Quickshell.execDetached(args); connectionRefresh.restart();
    }
    Timer { id: connectionRefresh; interval: 1200; onTriggered: root.refreshConnections() }

    // ═════════════ BLUETOOTH ═════════════
    property bool btOn: false
    property int btConnected: 0
    property string btConnectedName: ""
    property bool btScanning: false
    property var btDevices: []             // [ { mac, name, icon, connected, paired } ]
    property string btBusy: ""             // mac of device currently connecting/disconnecting
    property string btError: ""

    function btIconFor(name) {
        var n = (name || "").toLowerCase();
        if (n.indexOf("headphone") >= 0 || n.indexOf("headset") >= 0 || n.indexOf("earbud") >= 0 || n.indexOf("airpod") >= 0 || n.indexOf("buds") >= 0 || n.indexOf("wh-") >= 0 || n.indexOf("wf-") >= 0) return "headphones";
        if (n.indexOf("mouse") >= 0 || n.indexOf("trackpad") >= 0 || n.indexOf("magic mouse") >= 0) return "mouse";
        if (n.indexOf("keyboard") >= 0 || n.indexOf("keychron") >= 0) return "keyboard";
        if (n.indexOf("speaker") >= 0 || n.indexOf("soundbar") >= 0 || n.indexOf("echo") >= 0 || n.indexOf("homepod") >= 0) return "speaker";
        if (n.indexOf("controller") >= 0 || n.indexOf("gamepad") >= 0 || n.indexOf("xbox") >= 0 || n.indexOf("dualshock") >= 0 || n.indexOf("dualsense") >= 0) return "gamepad";
        if (n.indexOf("phone") >= 0 || n.indexOf("iphone") >= 0 || n.indexOf("galaxy") >= 0 || n.indexOf("pixel") >= 0) return "phone";
        return "bluetooth";
    }

    function refreshBt() { if (!btProc.running) btProc.running = true; }
    // One line per known device: D:<mac> <paired 0|1> <connected 0|1> <battery %> <name>   (tab separated).
    // Every device is asked with "bluetoothctl info", because the "devices Paired|Connected" filters only exist in
    // newer BlueZ versions: older ones ignore the argument and print every device (so everything looked connected).
    Process {
        id: btProc
        command: ["sh", "-c",
            "p=$(timeout 4 bluetoothctl show 2>/dev/null </dev/null | grep -i 'Powered:' | head -n1); echo \"P:$p\"; "
            + "timeout 4 bluetoothctl devices 2>/dev/null </dev/null | while read -r _ mac name; do "
            + "[ -n \"$mac\" ] || continue; "
            + "i=$(timeout 3 bluetoothctl info \"$mac\" 2>/dev/null </dev/null); "
            + "pr=$(printf '%s\\n' \"$i\" | grep -Ec 'Paired: yes|Bonded: yes'); "
            + "c=$(printf '%s\\n' \"$i\" | grep -c 'Connected: yes'); "
            + "b=$(printf '%s\\n' \"$i\" | sed -n 's/.*Battery Percentage: 0x[0-9a-fA-F]* (\\([0-9]*\\)).*/\\1/p' | head -n1); "
            + "printf 'D:%s\\t%s\\t%s\\t%s\\t%s\\n' \"$mac\" \"$pr\" \"$c\" \"$b\" \"$name\"; "
            + "done"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.split("\n"), on = false, devList = [], connCount = 0, firstConnName = "", i;
                for (i = 0; i < lines.length; i++) {
                    var l = lines[i].replace(/\r$/, "");
                    if (!l) continue;
                    if (l.indexOf("P:") === 0) { on = l.toLowerCase().indexOf("yes") >= 0; continue; }
                    if (l.indexOf("D:") !== 0) continue;
                    var f = l.substring(2).split("\t");
                    if (f.length < 5 || !f[0]) continue;
                    var mac = f[0], isPair = f[1] === "1", isConn = f[2] === "1", name = (f[4] || "").trim() || mac;
                    // BlueZ names an unnamed device after its address with dashes: show those last
                    if (isConn) { connCount++; if (!firstConnName) firstConnName = name; }
                    devList.push({ mac: mac, name: name, connected: isConn, paired: isPair, bat: f[3] || "", icon: root.btIconFor(name) });
                }
                root.btOn = on;
                devList.sort(function (a, b) {
                    if (a.connected !== b.connected) return a.connected ? -1 : 1;
                    if (a.paired !== b.paired) return a.paired ? -1 : 1;
                    return a.name.localeCompare(b.name);
                });
                root.btConnected = connCount;
                root.btConnectedName = connCount === 1 ? firstConnName : (connCount > 1 ? connCount + " Connected" : "");
                if (JSON.stringify(devList) !== JSON.stringify(root.btDevices)) root.btDevices = devList;
            }
        }
    }

    // Discovery only lasts while bluetoothctl stays alive (BlueZ stops it when the client exits), so "scan on" has to
    // run for a while with --timeout instead of being fired and forgotten.
    function scanBt() {
        if (!root.btOn || btScanProc.running) return;
        root.btScanning = true;
        btScanProc.running = true;
    }
    Process {
        id: btScanProc
        command: ["sh", "-c", "bluetoothctl --timeout 10 scan on >/dev/null 2>&1 </dev/null; exit 0"]
        onExited: {
            root.btScanning = false;
            root.refreshBt();
        }
    }
    Timer { interval: 2500; repeat: true; running: root.btScanning; onTriggered: root.refreshBt() }

    function connectBt(mac, connected) {
        if (btActionProc.running || !mac) return;
        root.btError = "";
        root.btBusy = mac;
        if (connected) {
            btActionProc.command = ["sh", "-c", "bluetoothctl disconnect \"$1\" >/dev/null 2>&1 </dev/null; exit 0", "sh", mac];
        } else {
            // pair first when needed (with a simple agent, no PIN prompt), trust, then connect
            btActionProc.command = ["sh", "-c",
                "d=\"$1\"; "
                + "fail() { m=$(printf '%s\\n' \"$1\" | grep -iE 'fail|error|not available|timeout|rejected|canceled' | tail -n1); "
                + "[ -n \"$m\" ] || m=\"$2\"; echo \"$m\" >&2; exit 1; }; "
                + "if ! bluetoothctl info \"$d\" 2>/dev/null </dev/null | grep -qE 'Paired: yes|Bonded: yes'; then "
                + "o=$(timeout 45 bluetoothctl --agent NoInputNoOutput pair \"$d\" 2>&1 </dev/null); "
                + "printf '%s\\n' \"$o\" | grep -qi 'Pairing successful' || fail \"$o\" 'Could not pair. Put the device in pairing mode and try again.'; "
                + "fi; "
                + "bluetoothctl trust \"$d\" >/dev/null 2>&1 </dev/null; "
                + "o=$(timeout 25 bluetoothctl connect \"$d\" 2>&1 </dev/null); "
                + "printf '%s\\n' \"$o\" | grep -qi 'Connection successful' || fail \"$o\" 'Could not connect to the device.'",
                "sh", mac];
        }
        btActionProc.running = true;
    }
    Process {
        id: btActionProc
        stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") root.btError = text.trim(); }
        onExited: (code, status) => {
            root.btBusy = "";
            if (code !== 0 && root.btError === "") root.btError = "Failed to connect to device.";
            btAfter.restart();
        }
    }
    Timer { id: btAfter; interval: 800; onTriggered: root.refreshBt() }

    // power: a soft-blocked adapter (rfkill, e.g. after Airplane Mode) refuses "power on", so unblock it first
    function toggleBt() {
        root.btOn = !root.btOn;
        Quickshell.execDetached(["sh", "-c",
            root.btOn ? "rfkill unblock bluetooth 2>/dev/null; sleep 0.3; bluetoothctl power on"
                      : "bluetoothctl power off"]);
        settleTimer.interval = 1500;
        settleTimer.restart();
    }
    readonly property bool airplane: !wifiOn && !btOn
    function toggleAirplane() {
        sh(airplane ? "rfkill unblock all; sleep 0.5; bluetoothctl power on" : "rfkill block all");
        wifiOn = airplane; btOn = airplane;
        settleTimer.restart();
    }
    Timer { id: settleTimer; interval: 900; onTriggered: { root.refreshWifi(); root.refreshBt(); } }
    Timer { interval: 6000; repeat: true; running: true; triggeredOnStart: true; onTriggered: { root.refreshWifi(); root.refreshBt(); } }

    // brightness
    property real brightness: 0.5
    function refreshBrightness() { if (!brightProc.running) brightProc.running = true; }
    Process {
        id: brightProc
        command: ["sh", "-c", "brightnessctl -m 2>/dev/null | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: {
                var f = text.trim().split(",");
                if (f.length >= 4) { var p = parseInt(f[3]); if (!isNaN(p)) root.brightness = p / 100; }
            }
        }
    }
    Timer {
        id: brightApply
        interval: 40
        onTriggered: Quickshell.execDetached(["brightnessctl", "-q", "set", Math.max(1, Math.round(root.brightness * 100)) + "%"])
    }
    function setBrightness(v) { osdQuiet("brightness", 1800); brightness = Math.max(0.01, Math.min(1, v)); brightApply.restart(); }
    onBrightnessChanged: showOsd("brightness", brightness)
    // hardware keys: like the sliders, but the on-screen display is shown (no quiet window)
    function hwVolume(d) {
        if (!sink || !sink.audio) return;
        var v = Math.max(0, Math.min(1, Math.round((sink.audio.volume + d) * 100) / 100));
        if (d > 0) sink.audio.muted = false;
        sink.audio.volume = v;
        showOsd("volume", sink.audio.muted ? 0 : v);
    }
    function hwMute() {
        if (!sink || !sink.audio) return;
        sink.audio.muted = !sink.audio.muted;
        showOsd("volume", sink.audio.muted ? 0 : sink.audio.volume);
    }
    function hwMicMute() { if (micSource && micSource.audio) micSource.audio.muted = !micSource.audio.muted; }
    function hwBrightness(d) {
        brightness = Math.max(0.01, Math.min(1, Math.round((brightness + d) * 100) / 100));
        brightApply.restart();
        showOsd("brightness", brightness);
    }
    Timer { interval: 850; repeat: true; running: true; onTriggered: root.refreshBrightness() }
    // ═════════════ KEYBOARD LAYOUT ═════════════
    // Hyprland's event gives an immediate update; a small reconciliation poll handles dropped events and
    // keyboards whose active keymap changes without a usable activelayout payload.
    readonly property var kbNames: ({
        us: "English (US)", gb: "English (UK)", ca: "Canadian", au: "English (Australian)", ie: "Irish", in: "Indian",
        ru: "Russian", ua: "Ukrainian", by: "Belarusian", bg: "Bulgarian", rs: "Serbian", hr: "Croatian", si: "Slovenian", mk: "Macedonian",
        de: "German", at: "German (Austria)", ch: "Swiss", fr: "French", be: "Belgian", es: "Spanish", latam: "Spanish (Latin American)",
        it: "Italian", pt: "Portuguese", br: "Portuguese (Brazil)", nl: "Dutch", se: "Swedish", no: "Norwegian", dk: "Danish", fi: "Finnish",
        is: "Icelandic", pl: "Polish", cz: "Czech", sk: "Slovak", hu: "Hungarian", ro: "Romanian", gr: "Greek", tr: "Turkish",
        il: "Hebrew", ara: "Arabic", ir: "Persian", pk: "Urdu", bd: "Bangla", th: "Thai", vn: "Vietnamese", jp: "Japanese", kr: "Korean",
        cn: "Chinese", tw: "Taiwanese", mn: "Mongolian", ge: "Georgian", am: "Armenian", kz: "Kazakh", ee: "Estonian", lv: "Latvian", lt: "Lithuanian"
    })
    readonly property var kbCodeAliases: ({
        "english": "EN", "us": "US", "uk": "GB", "united kingdom": "GB",
        "swedish": "SV", "svenska": "SV", "se": "SV",
        "german": "DE", "deutsch": "DE", "de": "DE",
        "french": "FR", "français": "FR", "fr": "FR",
        "spanish": "ES", "español": "ES", "es": "ES",
        "italian": "IT", "italiano": "IT", "it": "IT",
        "portuguese": "PT", "português": "PT", "pt": "PT",
        "russian": "RU", "русский": "RU", "ru": "RU",
        "ukrainian": "UA", "українська": "UA", "ua": "UA",
        "polish": "PL", "polski": "PL", "pl": "PL",
        "dutch": "NL", "nederlands": "NL", "nl": "NL",
        "norwegian": "NO", "norsk": "NO", "no": "NO",
        "danish": "DA", "dansk": "DA", "dk": "DA",
        "finnish": "FI", "suomi": "FI", "fi": "FI",
        "japanese": "JA", "jp": "JA",
        "korean": "KO", "kr": "KO",
        "chinese": "ZH", "cn": "ZH",
        "arabic": "AR", "ara": "AR",
        "hebrew": "HE", "il": "HE",
        "turkish": "TR", "tr": "TR",
        "greek": "EL", "gr": "EL"
    })
    function refreshKeyboardLayout() { if (!kbdProc.running) kbdProc.running = true; }
    Timer {
        interval: 1600; repeat: true
        running: root.barEnabled && root.barWidgetEnabled("keyboard") && root.kbLayouts.length > 1
        onTriggered: root.refreshKeyboardLayout()
    }
    Timer { id: kbEventRefresh; interval: 120; onTriggered: root.refreshKeyboardLayout() }
    Process {
        id: kbdProc
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text), ks = d.keyboards || [], k = null, i;
                    for (i = 0; i < ks.length; i++) if (ks[i].main) { k = ks[i]; break; }
                    if (!k && ks.length) k = ks[0];
                    if (!k) return;
                    var codes = String(k.layout || "").split(",");
                    var list = [];
                    for (i = 0; i < codes.length; i++) {
                        var c = codes[i].trim();
                        if (c !== "") list.push({ code: c, name: root.kbNames[c] || c.toUpperCase() });
                    }
                    if (list.length <= 1) {
                        for (var j = 0; j < ks.length; j++) {
                            var otherCodes = String(ks[j].layout || "").split(",");
                            if (otherCodes.length > list.length) {
                                var olist = [];
                                for (var m = 0; m < otherCodes.length; m++) {
                                    var oc = otherCodes[m].trim();
                                    if (oc !== "") olist.push({ code: oc, name: root.kbNames[oc] || oc.toUpperCase() });
                                }
                                if (olist.length > list.length) { list = olist; k = ks[j]; }
                            }
                        }
                    }
                    root.kbMain = k.name || "";
                    root.kbLayouts = list;
                    root.kbSetActive(k.active_keymap || "", k.active_layout_index);
                } catch (err) { }
            }
        }
    }
    function kbSetActive(name, idx) {
        var L = kbLayouts, found = -1, i;
        var n = String(name || "").toLowerCase().trim();
        if (idx !== undefined && idx !== null && idx >= 0 && idx < L.length) found = idx;
        for (i = 0; found < 0 && i < L.length; i++) {
            if (L[i].name.toLowerCase() === n || L[i].code.toLowerCase() === n) found = i;
        }
        for (i = 0; found < 0 && i < L.length; i++) {
            var firstWord = L[i].name.toLowerCase().split(" ")[0];
            if (n !== "" && (n.indexOf(firstWord) === 0 || firstWord.indexOf(n) === 0)) found = i;
        }
        if (found >= 0) {
            kbIndex = found;
            keyboardLayout = L[found].code.substring(0, 2).toUpperCase();
        } else if (n !== "") {
            var words = n.split(/[\s,()_-]+/);
            var mapped = "";
            for (var w = 0; w < words.length; w++) {
                if (root.kbCodeAliases[words[w]]) { mapped = root.kbCodeAliases[words[w]]; break; }
            }
            keyboardLayout = mapped || String(name).replace(/[^A-Za-z]/g, "").substring(0, 2).toUpperCase() || "??";
        }
    }
    function switchKeyboardLayout(i) {
        var n = kbLayouts.length;
        if (n < 2) return;
        i = ((i % n) + n) % n;
        kbIndex = i; keyboardLayout = kbLayouts[i].code.substring(0, 2).toUpperCase();    // show it right away, the event confirms it
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", String(i)]);
        kbEventRefresh.restart();
    }
    function cycleKeyboardLayout(step) { switchKeyboardLayout(kbIndex + (step === undefined ? 1 : step)); }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout") {
                var d = String(event.data), c = d.indexOf(",");
                if (c < 0) return;
                var lay = d.substring(c + 1).trim();
                root.kbSetActive(lay, undefined);
                kbEventRefresh.restart();
            } else if (event.name === "configreloaded") root.refreshKeyboardLayout();
        }
    }

    // ═════════════ PRIVACY INDICATORS ═════════════
    // Computed from the live PipeWire graph: a link only counts while it is Active, so the dots appear the moment an app starts
    // using the microphone / a camera / a screen-share and vanish as soon as it stops. No polling, no pw-dump.
    PwObjectTracker { objects: Pipewire.linkGroups.values }
    function computePrivacy() {
        var mic = [], cam = [], share = [], L = Pipewire.linkGroups.values;
        function add(list, name) { if (list.indexOf(name) < 0) list.push(name); }
        for (var i = 0; i < L.length; i++) {
            var g = L[i];
            if (!g || g.state !== PwLinkState.Active) continue;
            var s = g.source, t = g.target;
            if (!s || !t || s.type === undefined) continue;
            var tp = t.properties || {}, sp = s.properties || {};
            var who = String(tp["application.name"] || tp["node.description"] || t.description || tp["node.name"] || t.name || "An app")
                .replace(/\s+(input|output)$/i, "");
            if ((t.type & PwNodeType.AudioInStream) === PwNodeType.AudioInStream) {
                // an app is recording from a real source (a monitor of a sink is "listening to the computer", not a microphone)
                if ((s.type & PwNodeType.Sink) !== 0) continue;
                if (String(tp["media.name"]).toLowerCase() === "peak detect" || String(tp["application.id"]).indexOf("pavucontrol") >= 0) continue;
                add(mic, who);
            } else if ((t.type & PwNodeType.Video) !== 0 && (s.type & PwNodeType.Video) !== 0) {
                var isCam = sp["device.api"] !== undefined || String(sp["media.role"]) === "Camera"
                            || String(sp["node.name"]).indexOf("v4l2") === 0 || String(sp["node.name"]).indexOf("libcamera") === 0;
                add(isCam ? cam : share, who);
            }
        }
        return { mic: mic, cam: cam, share: share };
    }
    readonly property var privacy: computePrivacy()
    readonly property bool privacyAny: privacy.mic.length > 0 || privacy.cam.length > 0 || privacy.share.length > 0 || recording
    readonly property var privacyDots: {
        var a = [];
        if (privacy.mic.length > 0) a.push("#FF9F0A");
        if (privacy.cam.length > 0) a.push("#30D158");
        if (privacy.share.length > 0 || recording) a.push("#BF5AF2");
        return a;
    }
    readonly property var privacyRows: {
        var a = [];
        if (privacy.mic.length > 0) a.push({ k: "mic", glyph: "mic", c: "#FF9F0A", title: I18n.tr("Microphone"), sub: privacy.mic.join(", ") });
        if (privacy.cam.length > 0) a.push({ k: "cam", glyph: "camera", c: "#30D158", title: "Camera", sub: privacy.cam.join(", ") });
        if (privacy.share.length > 0) a.push({ k: "share", glyph: "monitor", c: "#BF5AF2", title: I18n.tr("Screen Sharing"), sub: privacy.share.join(", ") });
        if (recording) a.push({ k: "rec", glyph: "monitor", c: "#BF5AF2", title: I18n.tr("Screen Recording"), sub: I18n.tr("Recording ") + recTime() });
        return a;
    }
    // ── screen recording ──
    // A recorder and the glass's live window captures all pull frames from Hyprland; together they made it cut our Wayland
    // connection ("invalid object NN") and the shell died. So the window captures sit out while recording (hub.captureQuiet),
    // the recorder starts only after they have settled, and it can never outlive the shell: before, every crash left a
    // wf-recorder behind that kept recording (that is where the extra wf-recorder processes came from).
    property bool recRun: false                 // wf-recorder is allowed to run (it follows `recording` after a short delay)
    property real recGuardUntil: 0
    Timer { id: recStartDelay; interval: 900; onTriggered: if (root.recording) root.recRun = true }
    Process {
        id: recordProc
        command: ["sh", "-c", [
            'f="$1"; out="$2"; pf="${XDG_RUNTIME_DIR:-/tmp}/macbar-recorder.pid"; log="${XDG_RUNTIME_DIR:-/tmp}/macbar-recorder.log"',
            'mkdir -p "$(dirname "$f")"',
            '# a recorder left behind by an earlier crash would record forever: finish it first',
            'if [ -f "$pf" ]; then op=$(cat "$pf" 2>/dev/null); if [ -n "$op" ] && [ "$(cat /proc/$op/comm 2>/dev/null)" = wf-recorder ]; then kill -INT "$op" 2>/dev/null; sleep 0.6; fi; fi',
            'echo $$ > "$pf"',
            'set -- -f "$f" -p preset=veryfast -p crf=20',
            '# with more than one monitor wf-recorder stops to ask which one (and fails with no terminal): record the focused one',
            '[ -n "$out" ] && set -- "$@" -o "$out"',
            'exec 2>"$log" </dev/null',
            '# wf-recorder records at the monitor refresh rate (144 fps on a 144 Hz screen): cap it at 60',
            'if wf-recorder --help 2>&1 | grep -q -- "--framerate"; then set -- "$@" -r 60; fi',
            '# --pdeathsig: if the shell dies, the recorder is told to finish (and close the file) instead of running on',
            'if command -v setpriv >/dev/null 2>&1; then exec setpriv --pdeathsig INT wf-recorder "$@"; fi',
            'exec wf-recorder "$@"'
        ].join("\n"), "sh", root.recordFile, Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""]
        running: root.recRun
        onExited: (code, status) => {
            root.recRun = false;
            if (root.recording) root.recording = false;
            Quickshell.execDetached(["sh", "-c", "rm -f \"${XDG_RUNTIME_DIR:-/tmp}/macbar-recorder.pid\"; if [ -s \"$1\" ]; then notify-send -a macbar 'Screen Recording Saved' \"$1\"; "
                + "elif ! command -v wf-recorder >/dev/null 2>&1; then notify-send -a macbar 'Screen Recording Failed' 'wf-recorder is not installed'; "
                + "else notify-send -a macbar 'Screen Recording Failed' \"$(grep -v '^\\s*$' \"${XDG_RUNTIME_DIR:-/tmp}/macbar-recorder.log\" 2>/dev/null | tail -n 2)\"; fi", "sh", root.recordFile]);
        }
    }
    function toggleRecording() {
        if (Date.now() < recGuardUntil) return;          // a double click must not start two recorders
        recGuardUntil = Date.now() + 1500;
        if (!recording) {
            recordFile = Quickshell.env("HOME") + "/Videos/Screen-Recording-" + Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss") + ".mp4";
            recSecs = 0;
            recording = true;                            // the glass captures go quiet right away ...
            recStartDelay.restart();                     // ... and the recorder follows once they have
        } else {
            recStartDelay.stop();
            recording = false;
            if (recRun) {
                // ask the recorder to finish (SIGINT: it writes the end of the file); recRun goes false when it has exited
                Quickshell.execDetached(["sh", "-c", "kill -INT \"$(cat \"${XDG_RUNTIME_DIR:-/tmp}/macbar-recorder.pid\" 2>/dev/null)\" 2>/dev/null || pkill -INT -x wf-recorder"]);
                recKill.restart();
            }
        }
    }
    Timer { id: recKill; interval: 10000; onTriggered: root.recRun = false }      // it did not finish by itself: stop the process
    Timer { interval: 1000; repeat: true; running: root.recRun; onTriggered: root.recSecs++ }
    // recorders orphaned by an earlier crash of this shell (their parent is gone) would keep recording: finish them once at start-up
    Process {
        running: true
        command: ["sh", "-c", "for p in $(pgrep -x wf-recorder); do pp=$(ps -o ppid= -p \"$p\" | tr -d ' '); c=$(cat /proc/$pp/comm 2>/dev/null); case \"$c\" in systemd|init) kill -INT \"$p\";; esac; done; exit 0"]
    }
    function recTime() {
        var m = Math.floor(recSecs / 60), r = recSecs % 60;
        return m + ":" + (r < 10 ? "0" : "") + r;
    }
    function pickColor() { sh("c=$(hyprpicker -a) && [ -n \"$c\" ] && notify-send -a macbar 'Color copied' \"$c\""); }
    Process {
        id: fileSearchProc
        command: ["sh", "-c", "find \"$HOME\" -type f -iname \"*$1*\" -not -path '*/.cache/*' -not -path '*/.local/share/Trash/*' 2>/dev/null | head -n 60", "sh", root.fileQuery]
        stdout: StdioCollector { onStreamFinished: {
            var a=text.trim().split("\n").filter(function(x){return x!=="";});
            if (root.fileSearchFor === root.fileQuery) { root.fileHits=a; root.fileSearchPending=false; }
            else fileDebounce.restart();
        } }
        onExited: if (root.fileSearchFor !== root.fileQuery) fileDebounce.restart()
    }
    Timer { id: fileDebounce; interval: 260; onTriggered: {
        if (root.fileQuery.length > 0 && !fileSearchProc.running) { root.fileSearchFor=root.fileQuery; root.fileSearchPending=true; fileSearchProc.running=true; }
    } }
    function updateFileSearch(q) { fileQuery=q; fileHits=[]; fileSearchPending=true; fileDebounce.restart(); }

    // focus / night shift / keep awake
    property bool dnd: false
    onNotifDndChanged: if (dnd !== notifDnd) dnd = notifDnd
    onDndChanged: if (notifDnd !== dnd) notifDnd = dnd
    function toggleDnd() {
        dnd = !dnd;
        if (dnd) sh("dunstctl set-paused true 2>/dev/null || makoctl mode -a do-not-disturb 2>/dev/null || swaync-client -dn 2>/dev/null");
        else sh("dunstctl set-paused false 2>/dev/null || makoctl mode -r do-not-disturb 2>/dev/null || swaync-client -df 2>/dev/null");
    }
    property bool nightOn: false
    Process { id: nightProc; command: ["hyprsunset", "-t", String(root.nightTemp)]; running: root.nightOn }
    property bool keepAwake: false
    Process {
        id: awakeProc
        command: ["systemd-inhibit", "--what=idle:sleep", "--who=macbar", "--why=Keep Awake", "sleep", "infinity"]
        running: root.keepAwake
    }

    // ═════════════ MENUS ═════════════
    function mi(label, shortcut, run) { return { kind: "item", label: label, shortcut: shortcut || "", run: run }; }
    function mc(label, run) { return { kind: "item", label: label, shortcut: "", run: run, confirm: true }; }
    function msep() { return { kind: "sep" }; }
    function ico(item, g) { item.glyph = g; return item; }
    // Hyprland 0.55+ is configured and driven in Lua: `hyprctl dispatch` takes a Lua expression (the old "killactive" style strings fail).
    function hlx(expr) { Quickshell.execDetached(["hyprctl", "dispatch", expr]); }
    function disp(expr) { return function () { root.hlx(expr); }; }
    // Menu shortcuts are sent to the focused window with Hyprland's sendshortcut (no extra tool needed).
    // If some app ignores them, set this to true to type them with wtype instead.
    function keys(mods, k) {
        return function () {
            var targetAddr = root.activeWin ? (root.activeWin.address || "") : "";
            var modMap = {
                "ctrl": "ctrl", "control": "ctrl",
                "shift": "shift",
                "alt": "alt",
                "super": "logo", "win": "logo", "cmd": "logo"
            };
            var wtypeMods = mods.map(function(m) { return modMap[m.toLowerCase()] || m.toLowerCase(); });
            var hyprMods = mods.map(function(m) { return m.toUpperCase(); }).join(" ");
            var luaMods = mods.map(function(m) { return m.toUpperCase(); }).join(" + ");

            var kNorm = k;
            var wtypeK = k;
            if (k === "comma") { kNorm = "comma"; wtypeK = "comma"; }
            else if (k === "equal") { kNorm = "equal"; wtypeK = "equal"; }
            else if (k === "minus") { kNorm = "minus"; wtypeK = "minus"; }
            else if (k === "period") { kNorm = "period"; wtypeK = "period"; }

            var wtypeCmd = "wtype";
            for (var i = 0; i < wtypeMods.length; i++) wtypeCmd += " -M " + wtypeMods[i];
            wtypeCmd += " -k " + wtypeK;
            for (var j = wtypeMods.length - 1; j >= 0; j--) wtypeCmd += " -m " + wtypeMods[j];

            var focusCmd = targetAddr !== "" ? "hyprctl dispatch focuswindow address:" + targetAddr + " >/dev/null 2>&1; sleep 0.04; " : "sleep 0.03; ";
            var sendArg = targetAddr !== "" ? (hyprMods !== "" ? hyprMods + ", " : "") + kNorm + ", address:" + targetAddr
                                           : (hyprMods !== "" ? hyprMods + ", " : "") + kNorm + ", activewindow";

            var fullScript = focusCmd + 'if command -v wtype >/dev/null 2>&1; then ' + wtypeCmd + '; '
                           + 'elif command -v ydotool >/dev/null 2>&1; then ydotool key ' + (mods.length ? mods.join("+") + "+" : "") + kNorm + '; '
                           + 'else hyprctl dispatch sendshortcut "' + sendArg + '" 2>/dev/null || hyprctl dispatch sendshortcut "' + (hyprMods ? hyprMods + ", " : "") + kNorm + ', activewindow" 2>/dev/null || true; fi';

            Quickshell.execDetached(["sh", "-c", fullScript]);
        };
    }
    function mchk(label, shortcut, checked, run) { return { kind: "item", label: label, shortcut: shortcut || "", run: run, checked: checked === true }; }
    function dis(item, off) { if (off) item.disabled = true; return item; }

    // what kind of app is focused, so the menus can offer the right shortcuts
    function appKind(id) {
        var c = (id || "").toLowerCase();
        function any(list) { for (var i = 0; i < list.length; i++) if (c.indexOf(list[i]) >= 0) return true; return false; }
        if (any(["kitty", "alacritty", "foot", "wezterm", "ghostty", "konsole", "terminal", "xterm", "urxvt", "terminator", "tilix", "ptyxis"])) return "terminal";
        if (c === "zen" || any(["firefox", "chromium", "chrome", "brave", "zen-browser", "zen_browser", "vivaldi", "librewolf", "floorp", "waterfox", "opera", "epiphany", "falkon", "helium", "thorium", "microsoft-edge", "qutebrowser"])) return "browser";
        if (any(["nautilus", "dolphin", "thunar", "nemo", "pcmanfm", "caja", "krusader"])) return "files";
        if (any(["code", "codium", "cursor", "dev.zed", "kate", "gedit", "sublime", "geany", "neovide", "emacs", "jetbrains", "pycharm", "intellij", "clion", "webstorm"])) return "editor";
        return "";
    }
    function shot(region) {      // "" = whole screen, "sel" = pick an area (frozen-screen picker), otherwise "x,y WxH"
        if (region === "sel") shotStart();
        else shotFinish(region, "");
    }
    function shotWindow(aw) {
        if (!aw || !aw.at || !aw.size) return;
        shot(Math.round(aw.at[0]) + "," + Math.round(aw.at[1]) + " " + Math.round(aw.size[0]) + "x" + Math.round(aw.size[1]));
    }
    function aboutActive(aw, n) {
        var l = [];
        if (aw) {
            l.push("Class: " + aw["class"]);
            l.push("PID: " + aw.pid);
            if (aw.workspace) l.push("Workspace: " + aw.workspace.name);
            if (aw.title) l.push("Title: " + aw.title);
        } else l.push("Class: " + activeAppId);
        Quickshell.execDetached(["notify-send", "-a", "macbar", "About " + n, l.join("\n")]);
    }
    function forceQuitActive(aw) {
        if (aw && aw.pid > 0) Quickshell.execDetached(["kill", "-9", String(Math.floor(aw.pid))]);
    }
    function helpFor(id, n) {    // man page if there is one, otherwise a web search
        var c = (id || "").toLowerCase().replace(/[^a-z0-9._+-]/g, "");
        if (c === "") return;
        var q = encodeURIComponent(n + " linux help").replace(/'/g, "%27");
        sh("if man -w " + c + " >/dev/null 2>&1; then " + terminal + " -e man " + c + "; else xdg-open 'https://duckduckgo.com/?q=" + q + "'; fi");
    }
    function emoji() {
        sh("for c in emote bemoji smile rofimoji wofi-emoji; do command -v $c >/dev/null 2>&1 && exec $c; done");
    }
    function quitActive() {
        var tls = ToplevelManager.toplevels.values;
        for (var i = 0; i < tls.length; i++) if (tls[i].appId === activeAppId) tls[i].close();
    }
    function launchActive() {
        var e = lookup(activeAppId);
        if (e) e.execute();
    }
    function search() {
        if (!spotlightEnabled && launcher === "") return;
        spotWant = "home";
        if (launcher !== "") sh(launcher);
        else spotRequest++;                       // every bar window listens and the focused screen opens Spotlight
    }
    function spotOpen(mode) { if (!spotlightEnabled) return; spotWant = mode; spotRequest++; }
    // qs -c MacShell ipc call controlcenter toggle | open | close   (works with the menu bar switched off too)
    signal ccRequest(bool open)
    IpcHandler {
        target: "controlcenter"
        function toggle(): void { root.ccRequest(true); }
        function open(): void { root.ccRequest(true); }
        function close(): void { root.ccRequest(false); }
    }
    // Laptop / keyboard hardware keys (volume, mute, brightness). The compositor must bind the keys (the installer's
    // macshell.lua does); the shell then does the work itself, so the numbers, the on-screen display and the UI sounds
    // all stay in step.   qs -c MacShell ipc call hardware volumeUp | volumeDown | mute | micMute | brightnessUp | brightnessDown
    IpcHandler {
        target: "hardware"
        function volumeUp(): void { root.hwVolume(0.05); }
        function volumeDown(): void { root.hwVolume(-0.05); }
        function mute(): void { root.hwMute(); }
        function micMute(): void { root.hwMicMute(); }
        function brightnessUp(): void { root.hwBrightness(0.05); }
        function brightnessDown(): void { root.hwBrightness(-0.05); }
    }
    IpcHandler {
        target: "spotlight"
        function toggle(): void { root.search(); }
        function clipboard(): void { root.spotOpen("clip"); }
        function emoji(): void { root.spotOpen("emoji"); }
        function apps(): void { root.spotOpen("apps"); }
    }

    // ═════════════ CLIPBOARD HISTORY + EMOJI (Spotlight panels) ═════════════
    // History comes from cliphist; its `wl-paste --watch` watchers are started here (unless you already run them), and every
    // new entry also gets a timestamp in ~/.cache/macbar/clip-times so the list can say "Copied 4:11 pm".
    property string clipState: "unknown"      // unknown | ok | external | missing
    property var clipEntries: []              // newest first
    property bool clipLoading: false
    readonly property string clipDir: Quickshell.env("HOME") + "/.cache/macbar"
    // the system's default colour emoji font (asked from fontconfig); Noto Color Emoji until that answers
    property string emojiFont: "Noto Color Emoji"
    Process {
        running: true
        command: ["sh", "-c", "fc-match -f '%{family[0]}|%{color}' emoji 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                var p = text.trim().split("|");
                if (p.length === 2 && p[0] !== "" && p[1].toLowerCase() === "true") root.emojiFont = p[0];
            }
        }
    }

    readonly property string clipStoreCmd: "cliphist store; id=$(cliphist list | head -n1 | cut -f1); t=\"$HOME/.cache/macbar/clip-times\"; "
        + "[ -n \"$id\" ] && [ \"$id\" != \"$(tail -n1 \"$t\" 2>/dev/null | cut -f1)\" ] && printf '%s\\t%s\\n' \"$id\" \"$(date +%s)\" >> \"$t\""
    readonly property string clipListCmd: [
        "if ! command -v cliphist >/dev/null 2>&1; then echo '@@MISSING@@'; exit 0; fi",
        "d=\"$HOME/.cache/macbar\"; mkdir -p \"$d/clip\"; t=\"$d/clip-times\"; touch \"$t\"",
        "l=$(mktemp); cliphist list 2>/dev/null | head -n 300 > \"$l\"",
        "awk -F'\\t' -v now=\"$(date +%s)\" 'FILENAME==ARGV[1]{s[$1]=1;next} !($1 in s){print $1\"\\t\"now}' \"$t\" \"$l\" >> \"$t\"",
        "tail -n 3000 \"$t\" > \"$t.tmp\" && mv \"$t.tmp\" \"$t\"",
        "awk -F'\\t' '$2 ~ /^\\[\\[ binary data/ {print $1}' \"$l\" | head -n 30 | while read -r id; do [ -s \"$d/clip/$id.img\" ] || cliphist decode \"$id\" > \"$d/clip/$id.img\" 2>/dev/null; done",
        "find \"$d/clip\" -type f -mtime +3 -delete 2>/dev/null",
        "cat \"$l\"; echo '@@TIMES@@'; cat \"$t\"; rm -f \"$l\""
    ].join("\n")

    function clipStart() {
        if (clipHistory && barEnabled && settingsReady) clipProbe.running = true;
        else { clipWatchText.running = false; clipWatchImg.running = false; }
    }
    onSettingsReadyChanged: { clipStart(); emojiEnsure(); }
    onClipHistoryChanged: clipStart()
    Process {
        id: clipProbe
        command: ["sh", "-c",
            "if ! command -v wl-paste >/dev/null 2>&1 || ! command -v cliphist >/dev/null 2>&1; then echo missing; exit 0; fi; "
            + "mkdir -p \"$HOME/.cache/macbar/clip\"; "
            // look at real wl-paste processes only (`pgrep -f` also matched this very shell, so it always answered "external"
            // and the watchers below never started)
            + "ext=0; for p in $(pgrep -x wl-paste 2>/dev/null); do "
            + "if tr '\\0' ' ' < /proc/$p/cmdline 2>/dev/null | grep -q cliphist; then ext=1; fi; done; "
            + "if [ $ext = 1 ]; then echo external; else echo ok; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.clipState = text.trim();
                if (root.clipState === "ok") { clipWatchText.running = true; clipWatchImg.running = true; }
            }
        }
    }
    Process { id: clipWatchText; command: ["wl-paste", "--type", "text", "--watch", "sh", "-c", root.clipStoreCmd, "sh"] }
    Process { id: clipWatchImg; command: ["wl-paste", "--type", "image", "--watch", "sh", "-c", root.clipStoreCmd, "sh"] }

    function clipRefresh() {
        if (clipLoading) return;
        clipLoading = true;
        clipListProc.running = true;
    }
    Process {
        id: clipListProc
        command: ["sh", "-c", root.clipListCmd]
        stdout: StdioCollector {
            onStreamFinished: {
                root.clipLoading = false;
                if (text.indexOf("@@MISSING@@") === 0) { root.clipState = "missing"; root.clipEntries = []; return; }
                root.clipEntries = root.clipParse(text);
            }
        }
    }
    function clipWhen(ts) {
        if (!ts) return "";
        var d = new Date(ts * 1000), n = new Date();
        var tm = Qt.formatDateTime(d, root.use24h ? "HH:mm" : "h:mm ap");
        var today = new Date(n.getFullYear(), n.getMonth(), n.getDate()).getTime();
        var day = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
        if (day === today) return "Copied " + tm;
        if (day === today - 86400000) return "Copied Yesterday, " + tm;
        return I18n.tr("Copied ") + I18n.locale().toString(d, "d MMM") + ", " + tm;
    }
    function clipEntry(id, txt, ts) {
        var en = { id: id, text: txt, kind: "text", title: txt, label: I18n.tr("Text"), host: "", thumb: "", color: "" };
        var m = /^\[\[ binary data ([\d.]+ \w+) (\w+) (\d+x\d+) \]\]$/.exec(txt);
        if (m) {
            en.kind = "image";
            en.title = "Image " + m[3].replace("x", "\u00D7");
            en.label = "Image \u2022 " + m[2].toUpperCase() + " \u2022 " + m[1];
            en.thumb = "file://" + clipDir + "/clip/" + id + ".img";
        } else if (/^(https?|ftp):\/\/\S+$/i.test(txt) || /^www\.\S+\.\S+$/i.test(txt)) {
            en.kind = "url";
            en.host = txt.replace(/^[a-z]+:\/\//i, "").split(/[\/?#]/)[0];
            en.label = "URL \u2022 " + en.host;
        } else if (/^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(txt)) {
            en.kind = "color";
            en.color = txt;
            en.label = "Color";
        }
        var w = clipWhen(ts);
        en.sub = en.label + (w !== "" ? " \u2022 " + w : "");
        return en;
    }
    function clipParse(out) {
        var parts = out.split("@@TIMES@@\n");
        var lines = parts[0].split("\n"), tl = (parts[1] || "").split("\n"), times = {}, res = [], i;
        for (i = 0; i < tl.length; i++) {
            var p = tl[i].split("\t");
            if (p.length >= 2) times[p[0]] = parseInt(p[1]);
        }
        for (i = 0; i < lines.length; i++) {
            var tab = lines[i].indexOf("\t");
            if (tab < 1) continue;
            var id = lines[i].substring(0, tab);
            res.push(clipEntry(id, lines[i].substring(tab + 1), times[id] || 0));
        }
        return res;
    }
    function clipRunner(en) { return function () { root.clipPick(en, undefined); }; }
    function clipFiltered(q) {
        q = (q || "").trim().toLowerCase();
        var src = clipEntries, out = [];
        for (var i = 0; i < src.length && out.length < 150; i++) {
            var en = src[i];
            if (q !== "" && en.text.toLowerCase().indexOf(q) < 0 && en.label.toLowerCase().indexOf(q) < 0) continue;
            var it = {};
            for (var k in en) it[k] = en[k];
            it.confirm = false;
            it.run = clipRunner(en);
            out.push(it);
        }
        return out;
    }
    function clipPick(en, paste) {
        var id = parseInt(en.id);
        if (isNaN(id)) return;
        sh("cliphist decode " + id + " | wl-copy");
        if (paste === undefined ? clipAutoPaste : paste) pasteSoon();
    }
    // a clipboard entry dropped on the desktop: open it (image → viewer, URL → browser, text → editor)
    function clipOpen(en) {
        var id = parseInt(en.id);
        if (isNaN(id)) return;
        if (en.kind === "url") { Quickshell.execDetached(["xdg-open", /^www\./i.test(en.text) ? "https://" + en.text : en.text]); return; }
        var ext = en.kind === "image" ? (/(png|jpe?g|webp|gif|bmp)/i.exec(en.label) || ["png"])[0].toLowerCase() : "txt";
        Quickshell.execDetached(["sh", "-c", 'd="${XDG_RUNTIME_DIR:-/tmp}/macshell-clip"; mkdir -p "$d"; f="$d/clip-$1.$2"; cliphist decode "$1" > "$f" && exec xdg-open "$f"',
                                 "sh", String(id), ext]);
    }
    function clipDelete(en) {
        if (!en) return;
        var id = parseInt(en.id);
        if (isNaN(id)) return;
        clipEntries = clipEntries.filter(function (x) { return x.id !== en.id; });
        sh("printf '%s\\t\\n' " + id + " | cliphist delete; rm -f \"$HOME/.cache/macbar/clip/" + id + ".img\"");
    }
    function clipClear() {
        clipEntries = [];
        sh("cliphist wipe; rm -f \"$HOME/.cache/macbar/clip-times\" \"$HOME/.cache/macbar/clip/\"*");
    }
    // paste into the app that had focus before Spotlight (terminals paste with Ctrl+Shift+V)
    property var pasteFn: null
    function pasteSoon() {
        pasteFn = appKind(activeAppId) === "terminal" ? keys(["ctrl", "shift"], "v") : keys(["ctrl"], "v");
        pasteTimer.restart();
    }
    Timer { id: pasteTimer; interval: 230; onTriggered: if (root.pasteFn) root.pasteFn() }

    // emoji: search by name / keyword, categories, recents
    // Data comes from the system's own Unicode files when they exist (emoji-test.txt = every emoji with its official name and
    // category, CLDR annotations = search keywords), so it always matches your installed emoji font. EmojiData.js is the fallback.
    property var emojiList: EmojiData.list
    property string emojiSource: "bundled"
    property bool emojiTried: false
    readonly property var emojiIndex: {
        var m = {}, L = root.emojiList;
        for (var i = 0; i < L.length; i++) m[L[i][0]] = L[i];
        return m;
    }
    function emojiEnsure() {
        if (emojiTried) return;
        emojiTried = true;
        emojiLoadProc.running = true;
    }
    readonly property string emojiLoadCmd: [
        "t=''; for f in /usr/share/unicode/emoji/emoji-test.txt /usr/share/unicode/ucd/emoji/emoji-test.txt /usr/share/unicode-emoji/emoji-test.txt /usr/local/share/unicode/emoji/emoji-test.txt \"$HOME/.local/share/unicode/emoji-test.txt\"; do [ -r \"$f\" ] && { t=\"$f\"; break; }; done",
        "[ -z \"$t\" ] && t=$(find /usr/share /usr/local/share -maxdepth 6 -name emoji-test.txt 2>/dev/null | head -n1)",
        "[ -z \"$t\" ] && { echo '@@NONE@@'; exit 0; }",
        "echo '@@TEST@@'; grep -E '^(# (sub)?group:|[0-9A-F])' \"$t\"",
        "echo '@@CLDR@@'",
        "for d in annotations annotationsDerived; do f=''; for b in /usr/share/unicode/cldr/common /usr/share/unicode-cldr/common /usr/share/cldr/common /usr/share/unicode/cldr; do [ -r \"$b/$d/en.xml\" ] && { f=\"$b/$d/en.xml\"; break; }; done",
        "  [ -z \"$f\" ] && f=$(find /usr/share /usr/local/share -maxdepth 7 -path \"*/$d/en.xml\" 2>/dev/null | head -n1)",
        "  [ -n \"$f\" ] && grep -h '<annotation ' \"$f\"; done; true"
    ].join("\n")
    Process {
        id: emojiLoadProc
        command: ["sh", "-c", root.emojiLoadCmd]
        stdout: StdioCollector { onStreamFinished: root.emojiLoad(text) }
    }
    function emojiLoad(out) {
        var iT = out.indexOf("@@TEST@@\n"), iC = out.indexOf("@@CLDR@@\n");
        if (iT < 0 || iC < iT) return;                                  // no emoji-test.txt on this system: keep EmojiData.js
        var testTxt = out.substring(iT + 9, iC), cldrTxt = out.substring(iC + 9), m, i;
        function unesc(x) { return x.replace(/&quot;/g, "\"").replace(/&apos;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&"); }
        var kw = {}, re = /<annotation cp="([^"]+)"( type="tts")?>([^<]*)<\/annotation>/g;
        while ((m = re.exec(cldrTxt)) !== null) {
            if (m[2]) continue;
            var key = m[1].replace(/\uFE0F/g, "");
            kw[key] = (kw[key] ? kw[key] + " | " : "") + unesc(m[3]);
        }
        var cats = { "Smileys & Emotion": 0, "People & Body": 1, "Animals & Nature": 2, "Food & Drink": 3, "Travel & Places": 4,
                     "Activities": 5, "Objects": 6, "Symbols": 7, "Flags": 8 };
        var cat = -1, list = [], lines = testTxt.split("\n");
        for (i = 0; i < lines.length; i++) {
            var ln = lines[i];
            if (ln.charAt(0) === "#") {
                m = /^# group: (.+)$/.exec(ln);
                if (m) cat = cats[m[1].trim()] !== undefined ? cats[m[1].trim()] : -1;      // "Component" (skin tones, hair) -> skipped
                continue;
            }
            if (cat < 0) continue;
            m = /^[0-9A-F ]+;\s*(\S+)\s*#\s*(\S+)\s+E\d+(?:\.\d+)?\s+(.+)$/.exec(ln);
            if (!m || m[1] !== "fully-qualified") continue;
            var name = m[3].trim();
            if (name.indexOf("skin tone") >= 0) continue;                  // tone variants would triple the grid; the base emoji is kept
            var extra = (kw[m[2].replace(/\uFE0F/g, "")] || "").replace(/ \| /g, " ");
            list.push([m[2], name, extra, cat, (name + " " + extra).toLowerCase()]);
        }
        if (list.length < 800) return;                                  // looks wrong, keep the bundled list
        root.emojiList = list;
        root.emojiSource = "system";
    }
    function emojiItems(q, cat) {
        var L = root.emojiList, out = [], i;
        q = (q || "").trim().toLowerCase();
        if (q !== "") {
            var hits = [];
            for (i = 0; i < L.length; i++) {
                var p = L[i][4].indexOf(q);
                if (p < 0) continue;
                var nm = L[i][1].toLowerCase();
                // exact name, name starts with it, exact keyword (e.g. "smile" -> grinning face), a word of the name, anything else
                hits.push([nm === q ? 0 : (nm.indexOf(q) === 0 ? 1 : ((" " + L[i][2] + " ").indexOf(" " + q + " ") >= 0 ? 2
                           : (nm.indexOf(" " + q) >= 0 ? 3 : (p === 0 ? 4 : 5)))), i]);
            }
            hits.sort(function (a, b) { return a[0] - b[0] || a[1] - b[1]; });
            for (i = 0; i < hits.length && i < 240; i++) out.push(L[hits[i][1]]);
            return out;
        }
        if (cat === 0) {
            for (i = 0; i < emojiRecent.length; i++) if (emojiIndex[emojiRecent[i]]) out.push(emojiIndex[emojiRecent[i]]);
            return out;
        }
        for (i = 0; i < L.length; i++) if (L[i][3] === cat - 1) out.push(L[i]);
        return out;
    }
    function emojiPick(en) {
        if (!en) return;
        var r = [en[0]];
        for (var i = 0; i < emojiRecent.length && r.length < 24; i++) if (emojiRecent[i] !== en[0]) r.push(emojiRecent[i]);
        emojiRecent = r;
        Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" | wl-copy", "sh", en[0]]);
        if (clipAutoPaste) pasteSoon();
    }

    // the MacShell logo: the icon of MacShell's own windows in the Alt+Tab switcher
    readonly property string logoPath: decodeURIComponent(String(Qt.resolvedUrl("assets/macshell-logo.png")).replace(/^file:\/\//, ""))
    // ── applications for Spotlight ──
    function iconSrc(name) {
        var fb = Quickshell.iconPath("application-x-executable", true);
        if (!name) return fb;
        if (name.indexOf("/") === 0) return "file://" + name;
        var p = Quickshell.iconPath(name, true);
        return p !== "" ? p : fb;
    }
    readonly property var appList: {
        var vals = DesktopEntries.applications.values, out = [];
        for (var i = 0; i < vals.length; i++) if (!vals[i].noDisplay) out.push(vals[i]);
        out.sort(function (a, b) { return a.name.localeCompare(b.name); });
        return out;
    }
    readonly property var appCats: [
        ["Game", "Games"], ["Office", "Productivity & Finance"], ["Finance", "Productivity & Finance"],
        ["Network", "Internet & Social"], ["WebBrowser", "Internet & Social"], ["Development", "Developer Tools"],
        ["Graphics", "Graphics & Design"], ["AudioVideo", "Music & Video"], ["Audio", "Music & Video"],
        ["Video", "Music & Video"], ["Education", "Education & Science"], ["Science", "Education & Science"],
        ["Settings", "System"], ["System", "System"], ["Utility", "Utilities"]
    ]
    readonly property var catOrder: ["Games", "Productivity & Finance", "Internet & Social", "Developer Tools",
                                     "Graphics & Design", "Music & Video", "Education & Science", "Utilities", "System"]
    function appCategory(e) {
        var c = e.categories || [];
        for (var i = 0; i < appCats.length; i++)
            for (var j = 0; j < c.length; j++)
                if (c[j] === appCats[i][0]) return appCats[i][1];
        return "Utilities";
    }
    readonly property var appSections: {
        var list = appList, usage = appUsage, i, j;
        var used = list.filter(function (e) { return (usage[e.id] || 0) > 0; });
        used.sort(function (a, b) { return (usage[b.id] || 0) - (usage[a.id] || 0); });
        var sug = used.slice(0, 10);
        for (i = 0; i < list.length && sug.length < 5; i++) {
            var dup = false;
            for (j = 0; j < sug.length; j++) if (sug[j].id === list[i].id) { dup = true; break; }
            if (!dup) sug.push(list[i]);
        }
        var map = {};
        for (i = 0; i < list.length; i++) {
            var cat = appCategory(list[i]);
            if (!map[cat]) map[cat] = [];
            map[cat].push(list[i]);
        }
        var secs = [{ name: "Suggestions", apps: sug }];
        for (i = 0; i < catOrder.length; i++) if (map[catOrder[i]]) secs.push({ name: catOrder[i], apps: map[catOrder[i]] });
        return secs;
    }
    function searchApps(q) {
        q = (q || "").trim().toLowerCase();
        if (q === "") return [];
        var list = appList, hits = [];
        for (var i = 0; i < list.length; i++) {
            var e = list[i], n = e.name.toLowerCase(), sc = 0;
            if (n === q) sc = 100;
            else if (n.indexOf(q) === 0) sc = 80;
            else if (n.indexOf(" " + q) >= 0) sc = 60;
            else if (n.indexOf(q) >= 0) sc = 40;
            else if ((e.genericName || "").toLowerCase().indexOf(q) >= 0) sc = 25;
            else if ((e.comment || "").toLowerCase().indexOf(q) >= 0) sc = 10;
            else {
                var kw = e.keywords || [];
                for (var k = 0; k < kw.length; k++) if (String(kw[k]).toLowerCase().indexOf(q) >= 0) { sc = 15; break; }
            }
            if (sc > 0) hits.push({ e: e, s: sc + Math.min(appUsage[e.id] || 0, 20) });
        }
        hits.sort(function (a, b) { return b.s - a.s; });
        return hits.map(function (h) { return h.e; });
    }
    function appSearchSection(q) {
        var r = searchApps(q);
        return r.length > 0 ? [{ name: "Top Hits", apps: r }] : [];
    }
    function launchApp(e) {
        var u = {};
        for (var k in appUsage) u[k] = appUsage[k];
        u[e.id] = (u[e.id] || 0) + 1;
        appUsage = u;
        saveTimer.restart();
        e.execute();
    }
    function appRunner(e) { return function () { launchApp(e); }; }
    function appItems(q, limit) {
        var r = searchApps(q), out = [];
        for (var i = 0; i < r.length && i < limit; i++)
            out.push({ title: r[i].name, sub: r[i].genericName || I18n.tr("Application"), icon: iconSrc(r[i].icon),
                       glyph: "", confirm: false, run: appRunner(r[i]) });
        return out;
    }
    function actionItems(q) {
        var all = [
            { title: I18n.tr("Lock Screen"), glyph: "lock", run: function () { root.lockScreen(); } },
            { title: I18n.tr("Sleep"), glyph: "moon", run: function () { root.sleepMachine(); } },
            { title: I18n.tr("System Settings\u2026"), glyph: "gear", run: function () { openSettings(); } },
            { title: I18n.tr("Log Out"), glyph: "logout", confirm: true, run: function () { root.logOut(); } },
            { title: I18n.tr("Restart"), glyph: "restart", confirm: true, run: function () { sh("systemctl reboot"); } },
            { title: I18n.tr("Shut Down"), glyph: "power", confirm: true, run: function () { sh("systemctl poweroff"); } }
        ];
        var s = (q || "").trim().toLowerCase(), out = [];
        for (var i = 0; i < all.length; i++) {
            if (s !== "" && all[i].title.toLowerCase().indexOf(s) < 0) continue;
            out.push({ title: all[i].title, sub: I18n.tr("Action"), icon: "", glyph: all[i].glyph,
                       confirm: all[i].confirm === true, run: all[i].run });
        }
        return out;
    }
    function calcValue(expr) {
        var t=String(expr || "").replace(/[xX×]/g, "*").replace(/÷/g, "/");
        if (!/^[0-9+\-*/%.()\s]+$/.test(t) || !/[0-9]/.test(t)) return null;
        var i=0;
        function ws(){ while(i<t.length && /\s/.test(t[i])) i++; }
        function atom(){ ws(); if(t[i]==="+"){i++;return atom();} if(t[i]==="-"){i++;return -atom();} if(t[i]==="("){i++;var v=sum();ws();if(t[i]!==")")throw 0;i++;return v;} var m=t.substring(i).match(/^(?:\d+(?:\.\d*)?|\.\d+)/);if(!m)throw 0;i+=m[0].length;return Number(m[0]); }
        function term(){ var v=atom(); for(;;){ws();var op=t[i];if(op!=="*"&&op!=="/"&&op!=="%")break;i++;var r=atom();if((op==="/"||op==="%")&&r===0)throw 0;v=op==="*"?v*r:(op==="/"?v/r:v%r);}return v; }
        function sum(){var v=term();for(;;){ws();var op=t[i];if(op!=="+"&&op!=="-")break;i++;var r=term();v=op==="+"?v+r:v-r;}return v;}
        try { var v=sum(); ws(); return i===t.length && isFinite(v) ? v : null; } catch(e){ return null; }
    }
    function conversion(q) {
        var m=(q||"").trim().match(/^(-?\d+(?:\.\d+)?)\s*([a-z°]+)\s+(?:to|in)\s+([a-z°]+)$/i); if(!m)return null;
        var val=Number(m[1]), a=m[2].toLowerCase(), b=m[3].toLowerCase();
        var units={mm:["len",.001],cm:["len",.01],m:["len",1],km:["len",1000],in:["len",.0254],ft:["len",.3048],mi:["len",1609.344],g:["mass",.001],kg:["mass",1],lb:["mass",.45359237],oz:["mass",.0283495],ml:["vol",.001],l:["vol",1],gal:["vol",3.78541],ms:["time",.001],s:["time",1],min:["time",60],h:["time",3600],c:["temp",1],"°c":["temp",1],f:["temp",1],"°f":["temp",1]};
        if(!units[a]||!units[b]||units[a][0]!==units[b][0])return null;
        var result;
        if(units[a][0]==="temp") result=(a==="f"||a==="°f")?(val-32)*5/9:val, result=(b==="f"||b==="°f")?result*9/5+32:result;
        else result=val*units[a][1]/units[b][1];
        return {title:Number(result.toPrecision(7))+" "+b,sub:I18n.tr("Unit conversion"),glyph:"link",run:function(){Quickshell.execDetached(["wl-copy",String(result)]);}};
    }
    function windowItems(q) {
        var out=[], s=(q||"").trim().toLowerCase(); if(!s)return out;
        var ts=Hyprland.toplevels.values;
        for(var i=0;i<ts.length&&out.length<4;i++){
            var t=ts[i], o=t.lastIpcObject||{}, title=String(o.title||t.title||""), cls=String(o["class"]||t.appId||""), app=root.lookup(cls), label=title||app&&app.name||cls;
            if((label+" "+cls+" "+(app?app.name:" ")).toLowerCase().indexOf(s)<0)continue;
            var addr=String(o.address||t.address||""); if(addr!=="" && addr.indexOf("0x")!==0) addr="0x"+addr;
            (function(win,addr,workspace,cl,name,icon){out.push({title:name,sub:I18n.tr("Open Window"),icon:icon||"",glyph:"layers",run:function(){root.swPending={addr:addr,ws:workspace,cls:cl};swFocusTimer.restart();}});})(t,addr,o.workspace&&o.workspace.id>0?o.workspace.id:0,cls,label,app?root.iconSrc(app.icon):"");
        }
        return out;
    }
    function fileItems(q) {
        var out=[], home=Quickshell.env("HOME")||""; for(var i=0;i<fileHits.length&&out.length<60;i++){var path=fileHits[i];out.push({title:path.substring(path.lastIndexOf("/")+1)||path,sub:(home&&path.indexOf(home+"/")===0?"~"+path.substring(home.length):path),path:true,glyph:"folder",run:(function(p){return function(){Quickshell.execDetached(["xdg-open",p]);};})(path)});} return out;
    }
    function homeItems(q) {
        var out = [], s = (q || "").trim().toLowerCase();
        if (s.indexOf("file ") === 0 || s.indexOf("find ") === 0) {
            var fq=s.replace(/^(file|find)\s+/,"").trim(); if(fq!=="" && fileQuery!==fq) updateFileSearch(fq);
            out=fileItems(fq); if(out.length===0) out.push({title:fileSearchPending?I18n.tr("Searching files…"):I18n.tr("No matching files"),sub:I18n.tr("Files"),glyph:"folder",run:function(){}});
            return out;
        }
        if(s.length>0) out=appItems(q,4);
        var cv=conversion(s); if(cv) out.unshift(cv);
        else { var expr=s.replace(/^=\s*/,""); var v=calcValue(expr); if(v!==null && (s.charAt(0)==="=" || /[+*/%xX×÷()]/.test(s))) out.unshift({title:String(Number(v.toPrecision(10))),sub:I18n.tr("Calculator · Return to copy"),glyph:"search",run:function(){Quickshell.execDetached(["wl-copy",String(v)]);}}); }
        var wins=windowItems(q); for(var j=0;j<wins.length&&out.length<6;j++)out.push(wins[j]);
        var acts=actionItems(q); for(var k=0;k<acts.length&&out.length<6;k++)if(acts[k].title.toLowerCase().indexOf(s)===0)out.push(acts[k]);
        if(s.length>0 && out.length<7) out.push({title:I18n.tr("Search the web for “")+q.trim()+"”",sub:I18n.tr("Web Search · Return to open"),glyph:"search",run:function(){Quickshell.execDetached(["xdg-open","https://search.brave.com/search?q="+encodeURIComponent(q.trim())]);}});
        return out.slice(0,8);
    }

    function menuModelFor(name) {
        var m = [], i;
        if (name === "apple") {
            m.push(ico(mi("About This Linux", "", function () {
                if (hub && hub.about) hub.about.open();
                else sh(terminal + " -e sh -c 'fastfetch || neofetch; echo; read -p \"Press Enter\" _'");
            }), "m_about"));
            m.push(msep());
            m.push(ico(mi("System Settings\u2026", "", function () { root.openSettings(); }), "gear"));
            m.push(msep());
            m.push(ico(mi("Sleep", "", function () { root.sleepMachine(); }), "moon"));
            m.push(ico(mc("Restart\u2026", function () { sh("systemctl reboot"); }), "m_restart"));
            m.push(ico(mc("Shut Down\u2026", function () { sh("systemctl poweroff"); }), "m_power"));
            m.push(msep());
            m.push(ico(mi("Lock Screen", "", function () { root.lockScreen(); }), "m_lock"));
            m.push(ico(mc("Log Out\u2026", function () { root.logOut(); }), "m_logout"));
        } else {
            var id = activeAppId.toLowerCase(), kind = appKind(id), has = activeAppId !== "";
            var aw = (has && activeWin && String(activeWin["class"]).toLowerCase() === id) ? activeWin : null;
            var term = kind === "terminal", browser = kind === "browser", files = kind === "files", editor = kind === "editor";
            var floating = aw ? aw.floating === true : false, fsMode = aw ? Number(aw.fullscreen) : 0;
            var n = appName;

            if (name === "app") {
                if (!has) {
                    m.push(mi("New Terminal", "", function () { sh(terminal); }));
                    m.push(mi("Open Home Folder", "", function () { sh(filesCmd); }));
                    m.push(msep());
                    m.push(mi("Search\u2026", "", function () { root.search(); }));
                } else {
                    m.push(mi(I18n.tr("About ") + n, "", function () { root.aboutActive(aw, n); }));
                    if (editor || files) {
                        m.push(msep());
                        m.push(mi("Preferences\u2026", "Ctrl+,", keys(["ctrl"], "comma")));
                    }
                    m.push(msep());
                    m.push(mi(I18n.tr("Hide ") + n, "", disp('hl.dsp.window.move({ workspace = "special:hidden", follow = false })')));
                    m.push(mi("Show Hidden Windows", "", disp('hl.dsp.workspace.toggle_special("hidden")')));
                    m.push(msep());
                    m.push(mi(I18n.tr("Quit ") + n, "Ctrl+Q", function () { root.quitActive(); }));
                    m.push(mc("Force Quit " + n, function () { root.forceQuitActive(aw); }));
                }
            } else if (name === "file") {
                if (!has) {
                    m.push(mi("New Terminal", "", function () { sh(terminal); }));
                    m.push(mi("New Files Window", "", function () { sh(filesCmd); }));
                } else {
                    m.push(mi("New Window", "", function () { root.launchActive(); }));
                    if (browser) {
                        var ff = /firefox|librewolf|floorp|zen|waterfox/.test(id);
                        m.push(mi("New Private Window", ff ? "Ctrl+Shift+P" : "Ctrl+Shift+N", keys(["ctrl", "shift"], ff ? "p" : "n")));
                    }
                    if (browser || files) m.push(mi("New Tab", "Ctrl+T", keys(["ctrl"], "t")));
                    if (term) m.push(mi("New Tab", "Ctrl+Shift+T", keys(["ctrl", "shift"], "t")));
                    if (browser) m.push(mi("Reopen Closed Tab", "Ctrl+Shift+T", keys(["ctrl", "shift"], "t")));
                    if (!term && !files) m.push(mi("Open\u2026", "Ctrl+O", keys(["ctrl"], "o")));
                    if (!term && !files) {
                        m.push(msep());
                        m.push(mi(browser ? "Save Page As\u2026" : "Save", "Ctrl+S", keys(["ctrl"], "s")));
                        if (!browser) m.push(mi("Save As\u2026", "Ctrl+Shift+S", keys(["ctrl", "shift"], "s")));
                        m.push(mi("Print\u2026", "Ctrl+P", keys(["ctrl"], "p")));
                    }
                    m.push(msep());
                    if (browser || files || editor) m.push(mi("Close Tab", "Ctrl+W", keys(["ctrl"], "w")));
                    if (term) m.push(mi("Close Tab", "Ctrl+Shift+W", keys(["ctrl", "shift"], "w")));
                    m.push(mi("Close Window", "", disp('hl.dsp.window.close()')));
                }
                m.push(msep());
                if (aw) m.push(mi("Screenshot Window", "", function () { root.shotWindow(aw); }));
                m.push(mi("Screenshot Selection\u2026", "", function () { root.shot("sel"); }));
                m.push(mi("Screenshot Screen", "", function () { root.shot(""); }));
                m.push(mi(root.recording ? "Stop Screen Recording" : "Start Screen Recording", "", function () { root.toggleRecording(); }));
                m.push(mi("Pick Color", "", function () { root.pickColor(); }));
            } else if (name === "edit") {
                if (has && term) {
                    m.push(mi("Copy", "Ctrl+Shift+C", keys(["ctrl", "shift"], "c")));
                    m.push(mi("Paste", "Ctrl+Shift+V", keys(["ctrl", "shift"], "v")));
                } else if (has) {
                    m.push(mi("Undo", "Ctrl+Z", keys(["ctrl"], "z")));
                    m.push(mi("Redo", "Ctrl+Shift+Z", keys(["ctrl", "shift"], "z")));
                    m.push(msep());
                    m.push(mi("Cut", "Ctrl+X", keys(["ctrl"], "x")));
                    m.push(mi("Copy", "Ctrl+C", keys(["ctrl"], "c")));
                    m.push(mi("Paste", "Ctrl+V", keys(["ctrl"], "v")));
                    if (browser || editor) m.push(mi("Paste and Match Style", "Ctrl+Shift+V", keys(["ctrl", "shift"], "v")));
                    m.push(mi("Select All", "Ctrl+A", keys(["ctrl"], "a")));
                    m.push(msep());
                    m.push(mi("Find\u2026", "Ctrl+F", keys(["ctrl"], "f")));
                }
                if (has) m.push(msep());
                m.push(mi("Clipboard History\u2026", "", function () { root.spotOpen("clip"); }));
                m.push(mi("Emoji & Symbols", "", function () { root.spotOpen("emoji"); }));
            } else if (name === "view") {
                if (has) {
                    m.push(mi(fsMode === 2 ? "Exit Full Screen" : "Enter Full Screen", "", disp('hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })')));
                    m.push(msep());
                    m.push(mchk("Floating", "", floating, disp('hl.dsp.window.float({ action = "toggle" })')));
                    m.push(dis(mchk("Pin to All Workspaces", "", aw && aw.pinned === true, disp('hl.dsp.window.pin({ action = "toggle" })')), !floating));
                    m.push(dis(mi("Center Window", "", disp('hl.dsp.window.center()')), !floating));
                    m.push(dis(mi("Toggle Split Direction", "", disp('hl.dsp.layout("togglesplit")')), floating));
                    if (!term) {
                        m.push(msep());
                        m.push(mi("Actual Size", "Ctrl+0", keys(["ctrl"], "0")));
                        m.push(mi("Zoom In", "Ctrl+=", keys(["ctrl"], "equal")));
                        m.push(mi("Zoom Out", "Ctrl+-", keys(["ctrl"], "minus")));
                    }
                    if (browser || files) {
                        m.push(msep());
                        m.push(mi("Reload", "F5", keys([], "F5")));
                        if (browser) {
                            m.push(mi("Reload Ignoring Cache", "Ctrl+Shift+R", keys(["ctrl", "shift"], "r")));
                            m.push(mi("Developer Tools", "F12", keys([], "F12")));
                        }
                    }
                    m.push(msep());
                }
                m.push(mchk("Dark Mode", "", root.darkMode, function () { root.setAppearance(root.darkMode ? "light" : "dark"); }));
            } else if (name === "window") {
                if (has) {
                    m.push(mi("Minimize", "", disp('hl.dsp.window.move({ workspace = "special:minimized", follow = false })')));
                    m.push(mchk("Zoom", "", fsMode === 1, disp('hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })')));
                    m.push(mi(floating ? "Tile Window" : "Float Window", "", disp('hl.dsp.window.float({ action = "toggle" })')));
                    m.push(msep());
                    m.push(mi("Move Window Left", "", disp('hl.dsp.window.move({ direction = "left" })')));
                    m.push(mi("Move Window Right", "", disp('hl.dsp.window.move({ direction = "right" })')));
                    m.push(mi("Make Wider", "", disp('hl.dsp.window.resize({ x = 100, y = 0, relative = true })')));
                    m.push(mi("Make Narrower", "", disp('hl.dsp.window.resize({ x = -100, y = 0, relative = true })')));
                    if (Quickshell.screens.length > 1) m.push(mi("Move to Next Monitor", "", disp('hl.dsp.window.move({ monitor = "+1" })')));
                    m.push(mi("Move to Next Workspace", "", disp('hl.dsp.window.move({ workspace = "+1" })')));
                    m.push(mi("Move to Previous Workspace", "", disp('hl.dsp.window.move({ workspace = "-1" })')));
                    m.push(msep());
                }
                m.push(mi("Show Hidden Windows", "", disp('hl.dsp.workspace.toggle_special("hidden")')));
                m.push(mi("Show Minimized Windows", "", disp('hl.dsp.workspace.toggle_special("minimized")')));
                var tls = ToplevelManager.toplevels.values;
                if (tls.length > 0) m.push(msep());
                for (i = 0; i < tls.length && i < 8; i++) {
                    (function (w) {
                        var t = (w.title && w.title.length > 0) ? w.title : w.appId;
                        m.push(mchk(t, "", w.activated, function () { w.activate(); }));
                    })(tls[i]);
                }
            } else if (name === "help") {
                m.push(mi("Search\u2026", "", function () { root.search(); }));
                if (has) m.push(mi(n + " Help", "", function () { root.helpFor(id, n); }));
                m.push(msep());
                m.push(mi("Hyprland Keybinds", "", function () { Quickshell.execDetached(["xdg-open", "https://github.com/0-ss/MacShell#hyprland-configuration-lua"]); }));
                m.push(mi("Reload Hyprland Config", "", function () { Quickshell.execDetached(["hyprctl", "reload"]); }));
                m.push(msep());
                m.push(mi("Hyprland Wiki", "", function () { Quickshell.execDetached(["xdg-open", "https://wiki.hypr.land"]); }));
                m.push(mi("Quickshell Documentation", "", function () { Quickshell.execDetached(["xdg-open", "https://quickshell.org/docs"]); }));
            }
        }
        return m;
    }

    // ═════════════ SCREENSHOT (Print key) ═════════════
    // Same flow as Noctalia: every output is snapshotted first (grim), the frozen frame is shown dimmed, you drag a region and
    // the final PNG is cropped from that frozen frame, so nothing that moves while you select ends up in the picture.
    property bool shotOpen: false             // the picker overlay is showing
    property bool shotBusy: false             // taking the snapshots
    property int shotId: 0
    readonly property string shotTmp: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string shotFinishScript: [
        "d=\"$1\"; sv=\"$2\"; cl=\"$3\"; nt=\"$4\"; tmp=\"$5\"; g=\"$6\"",
        "if [ \"$g\" = '@' ]; then :; elif [ -n \"$g\" ]; then grim -g \"$g\" \"$tmp\"; else grim \"$tmp\"; fi || exit 1",
        "[ -s \"$tmp\" ] || exit 1",
        "f=\"$tmp\"",
        "if [ \"$sv\" = 1 ]; then",
        "  [ -z \"$d\" ] && d=\"$HOME/Pictures/Screenshots\"",
        "  case \"$d\" in '~') d=\"$HOME\";; '~/'*) d=\"$HOME/${d#'~/'}\";; esac",
        "  n=\"$d/Screenshot-$(date +%F_%H-%M-%S).png\"",
        "  mkdir -p \"$d\" && mv -f \"$tmp\" \"$n\" && f=\"$n\"",
        "fi",
        "[ \"$cl\" = 1 ] && wl-copy --type image/png < \"$f\"",
        "if [ \"$nt\" = 1 ]; then if [ \"$f\" = \"$tmp\" ]; then notify-send -a macbar 'Screenshot copied' 'Copied to the clipboard'; else notify-send -a macbar 'Screenshot saved' \"$f\"; fi; fi",
        "[ \"$f\" = \"$tmp\" ] && rm -f \"$tmp\"",
        "true"
    ].join("\n")
    // geom: "" = whole screen, "x,y WxH" = that area, "@" = `tmpPath` already holds the finished PNG (from the picker)
    function shotFinish(geom, tmpPath) {
        playSound("shutter", 0.8);
        var tmp = tmpPath || (shotTmp + "/macshot-out-" + Date.now() + ".png");
        var save = screenshotSave || !screenshotClipboard;          // never end up with nowhere to put it
        Quickshell.execDetached(["sh", "-c", shotFinishScript, "sh", screenshotDir, save ? "1" : "0", screenshotClipboard ? "1" : "0",
                                 screenshotNotify ? "1" : "0", tmp, geom]);
    }
    function shotStart() {
        if (shotOpen) { shotClose(); return; }
        if (shotBusy) return;
        var scr = Quickshell.screens, names = [];
        for (var i = 0; i < scr.length; i++) names.push(scr[i].name);
        if (names.length === 0) return;
        shotBusy = true;
        shotId++;
        shotSnap.command = ["sh", "-c",
            "d=\"$1\"; i=\"$2\"; shift 2; for n in \"$@\"; do grim -t ppm -o \"$n\" \"$d/macshot-$i-$n.ppm\" & done; wait; "
            + "for n in \"$@\"; do [ -s \"$d/macshot-$i-$n.ppm\" ] || exit 1; done", "sh", shotTmp, String(shotId)].concat(names);
        shotSnap.running = true;
    }
    function shotClose() {
        shotOpen = false;
        Quickshell.execDetached(["sh", "-c", "rm -f \"$1\"/macshot-*.ppm", "sh", shotTmp]);
    }
    Process {
        id: shotSnap
        onExited: (code, status) => {
            root.shotBusy = false;
            if (code === 0) root.shotOpen = true;
            else root.shotClose();
        }
    }
    IpcHandler {
        target: "screenshot"
        function region(): void { root.shotStart(); }
        function screen(): void { root.shotFinish("", ""); }
        function window(): void { root.shotWindow(root.activeWin); }
    }
    Variants {
        model: root.shotOpen ? Quickshell.screens : []
        PanelWindow {
            id: shw
            required property var modelData
            screen: modelData
            anchors { left: true; right: true; top: true; bottom: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.namespace: "macshot"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            readonly property url snap: "file://" + root.shotTmp + "/macshot-" + root.shotId + "-" + modelData.name + ".ppm"
            readonly property real k: frozen.implicitWidth > 0 ? frozen.implicitWidth / width : 1     // snapshot pixels per logical pixel
            property real ax: 0
            property real ay: 0
            property real px: 0
            property real py: 0
            property real selX: 0
            property real selY: 0
            property real selW: 0
            property real selH: 0
            property bool dragging: false
            property bool grabbing: false
            readonly property bool hasSel: selW > 1 && selH > 1

            function capture(x, y, w, h) {
                if (grabbing) return;
                grabbing = true;
                selX = Math.round(x); selY = Math.round(y); selW = Math.round(w); selH = Math.round(h);
                grabTimer.restart();
            }
            Timer {
                id: grabTimer
                interval: 40                         // let the cut-out settle at its final size before it is grabbed
                onTriggered: {
                    var out = root.shotTmp + "/macshot-out-" + Date.now() + ".png";
                    var kk = shw.k;
                    var ok = cut.grabToImage(function (res) {
                        var saved = res.saveToFile(out);
                        root.shotClose();
                        if (saved) root.shotFinish("@", out);
                    }, Qt.size(Math.max(1, Math.round(shw.selW * kk)), Math.max(1, Math.round(shw.selH * kk))));
                    if (!ok) root.shotClose();
                }
            }

            Item {
                id: sroot
                anchors.fill: parent
                focus: true
                Component.onCompleted: forceActiveFocus()
                NumberAnimation on opacity { from: 0; to: 1; duration: 120 }
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) { root.shotClose(); event.accepted = true; }
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        shw.capture(0, 0, shw.width, shw.height);
                        event.accepted = true;
                    }
                }

                Image { id: frozen; anchors.fill: parent; source: shw.snap; fillMode: Image.Stretch; smooth: true }
                Rectangle { anchors.fill: parent; color: "black"; opacity: 0.42 }

                // the selected area, undimmed. This item is what gets cropped, so nothing else may be drawn inside it
                Item {
                    id: cut
                    visible: shw.hasSel
                    x: shw.selX; y: shw.selY; width: shw.selW; height: shw.selH
                    clip: true
                    Image { x: -cut.x; y: -cut.y; width: shw.width; height: shw.height; source: shw.snap; fillMode: Image.Stretch; smooth: true }
                }
                Rectangle {
                    visible: shw.hasSel && !shw.grabbing
                    x: cut.x - 1; y: cut.y - 1; width: cut.width + 2; height: cut.height + 2
                    color: "transparent"
                    border.width: 1.5
                    border.color: "white"
                }

                // size badge follows the pointer while selecting
                Rectangle {
                    visible: shw.hasSel && !shw.grabbing
                    x: Math.max(8, Math.min(shw.width - width - 8, shw.px + 14))
                    y: Math.max(8, Math.min(shw.height - height - 8, shw.py + 18))
                    width: sizeTxt.implicitWidth + 18; height: 24; radius: 12
                    color: Qt.rgba(0, 0, 0, 0.72)
                    Text {
                        id: sizeTxt
                        anchors.centerIn: parent
                        text: Math.round(shw.selW * shw.k) + " \u00D7 " + Math.round(shw.selH * shw.k)
                        color: "white"
                        font.family: root.fontForWeight(font.weight, root.fontFamily); font.pixelSize: 12; font.weight: Font.Medium
                    }
                }
                Rectangle {
                    visible: !shw.hasSel && !shw.grabbing
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 56
                    width: hintTxt.implicitWidth + 28; height: 32; radius: 16
                    color: Qt.rgba(0, 0, 0, 0.72)
                    Text {
                        id: hintTxt
                        anchors.centerIn: parent
                        text: I18n.tr("Drag to select an area   \u2022   Return: whole screen   \u2022   Esc: cancel")
                        color: "white"
                        font.family: root.fontForWeight(font.weight, root.fontFamily); font.pixelSize: 13
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.CrossCursor
                    onPressed: m => {
                        if (m.button === Qt.RightButton) { root.shotClose(); return; }
                        if (shw.grabbing) return;
                        shw.dragging = true;
                        shw.ax = m.x; shw.ay = m.y; shw.px = m.x; shw.py = m.y;
                        shw.selX = m.x; shw.selY = m.y; shw.selW = 0; shw.selH = 0;
                    }
                    onPositionChanged: m => {
                        shw.px = m.x; shw.py = m.y;
                        if (!shw.dragging) return;
                        var x2 = Math.max(0, Math.min(shw.width, m.x)), y2 = Math.max(0, Math.min(shw.height, m.y));
                        shw.selX = Math.min(shw.ax, x2); shw.selY = Math.min(shw.ay, y2);
                        shw.selW = Math.abs(x2 - shw.ax); shw.selH = Math.abs(y2 - shw.ay);
                    }
                    onReleased: m => {
                        if (!shw.dragging) return;
                        shw.dragging = false;
                        if (shw.selW >= 4 && shw.selH >= 4) shw.capture(shw.selX, shw.selY, shw.selW, shw.selH);
                        else { shw.selW = 0; shw.selH = 0; }
                    }
                }
            }
        }
    }

    // ═════════════ ANIMATED WALLPAPER: decode only what can be seen ═════════════
    // When windows cover a monitor's desktop (or one is fullscreen) its video pauses; it resumes as soon as the desktop
    // shows again. One check per window event (open / close / move / workspace / fullscreen), nothing in between.
    readonly property bool videoWall: wallpaperVideo !== ""
    property var wallPaused: ({})          // output → paused (video wallpaper)
    // output → its desktop is completely hidden behind windows (or one is fullscreen). Always tracked: the desktop
    // widgets stop drawing on covered screens (culling), and a video wallpaper pauses there.
    property var screenCovered: ({})
    // output → a window is FULLSCREEN there: only then do the desktop widgets stop drawing (a focused or tiled
    // window that merely covers the desktop keeps them alive)
    property var screenFullscreen: ({})
    readonly property string wallPauseScript: Quickshell.env("HOME") + "/.config/hypr-macshell/scripts/macshell-wallpause.sh"
    Process {
        id: coverProbe
        command: ["sh", "-c", "printf '{\"m\":'; hyprctl -j monitors; printf ',\"c\":'; hyprctl -j clients; printf '}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var o; try { o = JSON.parse(text); } catch (e) { return; }
                var next = {}, fullMap = {};
                for (var i = 0; i < o.m.length; i++) {
                    var m = o.m[i], ws = m.activeWorkspace ? m.activeWorkspace.id : -999, mw = m.width / (m.scale || 1), mh = m.height / (m.scale || 1);
                    var area = 0, full = false;
                    for (var j = 0; j < o.c.length; j++) {
                        var c = o.c[j];
                        if (!c.mapped || c.hidden || c.monitor !== m.id || c.workspace.id !== ws) continue;
                        if (c.fullscreen > 0 || c.fullscreen === true) { full = true; break; }
                        if (!c.floating) area += Math.min(c.size[0], mw) * Math.min(c.size[1], mh);
                    }
                    next[m.name] = full || area >= mw * mh * 0.86;
                    fullMap[m.name] = full;
                }
                var sameF = true;
                for (var f in fullMap) if (fullMap[f] !== (root.screenFullscreen[f] === true)) sameF = false;
                if (!sameF) root.screenFullscreen = fullMap;
                var same = true;
                for (var q in next) if (next[q] !== (root.screenCovered[q] === true)) same = false;
                if (!same) root.screenCovered = next;
                if (!root.videoWall) return;
                for (var k in next) if (next[k] !== (root.wallPaused[k] === true))
                    Quickshell.execDetached([root.wallPauseScript, k, next[k] ? "pause" : "resume"]);
                root.wallPaused = next;
            }
        }
    }
    Timer { id: coverDelay; interval: 300; onTriggered: if (!coverProbe.running) coverProbe.running = true }
    Timer { interval: 1500; running: true; onTriggered: coverDelay.restart() }      // first check after start-up
    onVideoWallChanged: { wallPaused = ({}); if (videoWall) coverDelay.restart(); }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            var n = event.name;
            if (n === "openwindow" || n === "closewindow" || n === "movewindowv2" || n === "workspacev2" || n === "fullscreen"
                || n === "changefloatingmode" || n === "focusedmonv2" || n === "activespecialv2") coverDelay.restart();
        }
    }

    // ═════════════ ANIMATED WALLPAPER IN THE GLASS: one small copy, never the full video ═════════════
    // Every glass (bar, Dock, Settings, each desktop widget) runs its own decoder. Decoding the original (often 4K) video that many times is
    // what used to take gigabytes. The glass is blurred and refracted anyway, so it plays a 720 px / 30 fps copy instead (cached in
    // ~/.cache/macshell/glass, built once with ffmpeg at low priority). Until that copy exists the glass shows the still picture.
    // Without ffmpeg (or if the build fails) the original video is used, so the switch still works.
    property var glassProxy: ({})              // video path → small copy, ready
    property var glassProxyFailed: ({})        // video path → true when no copy could be made
    property string glassProxyFor: ""          // the video the build process is working on right now
    readonly property int glassProxyWidth: 720
    readonly property int glassProxyFps: 30
    readonly property string glassVideo: {
        if (!liveWallGlass || wallpaperVideo === "") return "";
        var p = glassProxy[wallpaperVideo];
        if (p) return p;
        return glassProxyFailed[wallpaperVideo] === true ? wallpaperVideo : "";
    }
    function glassProxyEnsure() {
        if (!liveWallGlass || wallpaperVideo === "" || glassProxy[wallpaperVideo] || glassProxyFailed[wallpaperVideo] === true) return;
        if (glassProxyBuild.running) return;                      // onExited calls this again for whatever is current by then
        glassProxyFor = wallpaperVideo;
        glassProxyBuild.command = ["sh", "-c", [
            'v="$1"; w="$2"; f="$3"',
            'command -v ffmpeg >/dev/null 2>&1 || exit 1',
            'd="$HOME/.cache/macshell/glass"; mkdir -p "$d"',
            'find "$d" -name "*.mp4" -mtime +60 -delete 2>/dev/null',
            'k="$(printf "%s:%s:%s:%s" "$v" "$(stat -c %Y "$v" 2>/dev/null)" "$w" "$f" | md5sum | cut -c1-16)"',
            'o="$d/$k.mp4"',
            'if [ ! -s "$o" ]; then',
            '  t="$d/$k.part.mp4"',
            '  nice -n 15 ffmpeg -loglevel error -y -i "$v" -an -sn -dn -vf "fps=$f,scale=\'min($w,iw)\':-2" -c:v libx264 -preset veryfast -crf 30 -pix_fmt yuv420p -g 60 -movflags +faststart -f mp4 "$t" </dev/null >/dev/null 2>&1 \\',
            '    && mv -f "$t" "$o" || { rm -f "$t"; exit 1; }',
            'fi',
            'printf "P:%s\\n" "$o"'
        ].join("\n"), "sh", glassProxyFor, String(glassProxyWidth), String(glassProxyFps)];
        glassProxyBuild.running = true;
    }
    Process {
        id: glassProxyBuild
        stdout: StdioCollector {
            onStreamFinished: {
                var m = /^P:(.+)$/m.exec(text);
                var v = root.glassProxyFor;
                if (m) { var ok = Object.assign({}, root.glassProxy); ok[v] = m[1]; root.glassProxy = ok; }
            }
        }
        onExited: (code, status) => {
            var v = root.glassProxyFor;
            if (code !== 0 && !root.glassProxy[v]) { var bad = Object.assign({}, root.glassProxyFailed); bad[v] = true; root.glassProxyFailed = bad; }
            root.glassProxyFor = "";
            root.glassProxyEnsure();
        }
    }
    onLiveWallGlassChanged: glassProxyEnsure()
    onWallpaperVideoChanged: glassProxyEnsure()
    Timer { interval: 2500; running: true; onTriggered: root.glassProxyEnsure() }      // the saved settings are in by now

    // ═════════════ GAME MODE ═════════════
    readonly property string gamingScript: Quickshell.env("HOME") + "/.config/hypr-macshell/scripts/macshell-gaming.sh"
    property bool gamingApplied: false
    onGamingChanged: gamingApply.restart()
    Timer {
        id: gamingApply
        interval: 150
        onTriggered: {
            if (!root.settingsReady || root.gaming === root.gamingApplied) return;
            root.gamingApplied = root.gaming;
            Quickshell.execDetached([root.gamingScript, root.gaming ? "on" : "off"]);
            if (root.uiSounds) Quickshell.execDetached(["pw-play", "--volume=0.6", root.soundDir + "/tink.wav"]);
        }
    }
    // a crash while Game Mode was on leaves Hyprland without blur/animations: put them back at start
    Timer { interval: 1500; running: true; onTriggered: { if (!root.gaming) Quickshell.execDetached([root.gamingScript, "off"]); else gamingApply.restart(); } }
    // Automatic: on while the focused window is a fullscreen game
    readonly property var gameClassRe: /^(steam_app_\d+|gamescope|org\.vinegarhq\.sober|sober|robloxplayer.*|minecraft.*|com\.mojang.*|lutris|heroic|.*\.exe|osu!?|cs2|dota2|hl2_linux|factorio|terraria.*|stardew.*)$/i
    Process {
        id: gameProbe
        command: ["hyprctl", "-j", "activewindow"]
        stdout: StdioCollector {
            onStreamFinished: {
                var w = {};
                try { w = JSON.parse(text || "{}"); } catch (e) { w = {}; }
                var cls = (w["class"] || w.initialClass || "");
                root.gamingAutoActive = root.gamingAuto && (w.fullscreen > 0 || w.fullscreen === true) && root.gameClassRe.test(cls);
            }
        }
    }
    Timer { id: gameProbeDelay; interval: 250; onTriggered: if (!gameProbe.running) gameProbe.running = true }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            var n = event.name;
            if (n === "fullscreen" || n === "activewindowv2" || n === "closewindow" || n === "workspacev2") gameProbeDelay.restart();
        }
    }
    onGamingAutoChanged: { if (!gamingAuto) gamingAutoActive = false; else gameProbeDelay.restart(); }

    // ═════════════ SETTINGS PERSISTENCE ═════════════
    readonly property string settingsSig: settingKeys.map(function (k) { return String(root[k]); }).join("|")
    property bool settingsReady: false
    onSettingsSigChanged: if (settingsReady) saveTimer.restart()
    Timer { id: saveTimer; interval: 400; onTriggered: root.saveSettings() }

    function saveSettings() {
        var o = {};
        for (var i = 0; i < settingKeys.length; i++) {
            var k = settingKeys[i];
            o[k] = (k === "accent") ? String(root[k]) : root[k];
        }
        store.setText(JSON.stringify(o, null, 2));
    }
    function applySettings(o, keysToApply) {
        if (!o || typeof o !== "object") return;
        for (var i = 0; i < keysToApply.length; i++) {
            var k = keysToApply[i];
            if (o[k] === undefined) continue;
            try { root[k] = o[k]; } catch (err) { }
        }
    }
    function resetSettings() {
        barEnabled = true;
        darkMode = true; appearanceMode = "dark"; accent = "#0a84ff"; fontFamily = "Open Runde"; glassOpacity = 0.42; glassBlur = 5; barBgOpacity = 0.10; glassRealtime = false; liveWallGlass = false;
        barStyle = "liquid"; use24h = true; showDate = true; showSeconds = false; showBatteryPercent = true;
        showTray = true; showSearch = true;
        spotlightEnabled = true; ccEnabled = true; notificationsEnabled = true; clockAppEnabled = true; ccStyle = "tiles";
        barLogoMode = "arch"; barCustomLogoPath = "";
        barWidgets = ["appleMenu", "appMenus", "workspaces", "volume", "keyboard", "notifications", "wifi", "bluetooth", "privacy", "controlCenter", "clock"];
        ccControls = ccDefault.slice();
        uiScaleAuto = true; uiScaleManual = 1.0;
    }

    // inherit look from macdock first, then macbar's own file wins
    FileView {
        id: dockStore
        path: root.dockConfigDir + "/settings.json"
        printErrors: false
        onLoaded: {
            try {
                var o = JSON.parse(text());
                root.applySettings(o, ["darkMode", "appearanceMode", "accent", "fontFamily", "glassOpacity", "glassRim", "glassGrain", "glassLiquid", "glassBlur", "wallpaperPath"]);
                if (o.dockStyle !== undefined) root.barStyle = (o.dockStyle === "liquid") ? "liquid" : "blur";
            } catch (err) { }
            store.path = root.configDir + "/settings.json";
        }
        onLoadFailed: store.path = root.configDir + "/settings.json"
    }
    FileView {
        id: store
        path: ""
        printErrors: false
        onLoaded: {
            try { root.applySettings(JSON.parse(text()), root.settingKeys); } catch (err) { }
            if (!root.ccMigGame) {
                root.ccMigGame = true;
                var cg = root.ccControls.slice();
                if (cg.indexOf("gaming") < 0) { var ri = cg.indexOf("record"); cg.splice(ri >= 0 ? ri + 1 : cg.length, 0, "gaming"); root.ccControls = cg; }
            }
            if (!root.ccMigRec) {
                root.ccMigRec = true;
                var cl = root.ccControls.slice();
                if (cl.indexOf("record") < 0) { var fi = cl.indexOf("focus"); cl.splice(fi >= 0 ? fi + 1 : cl.length, 0, "record"); root.ccControls = cl; }
            }
            root.settingsReady = true;
            inputApplyT.restart();
            if (root.barStyle === "liquid") root.startGlass();
        }
        onLoadFailed: { root.ccMigRec = true; root.settingsReady = true; if (root.barStyle === "liquid") root.startGlass(); }
    }

    // ═════════════ LIQUID GLASS BACKEND (same pipeline as macdock) ═════════════
    property string glassState: "idle"       // idle → building → ready | failed
    readonly property bool liquidActive: barStyle === "liquid" && glassState === "ready" && !gaming
    readonly property string glassShaderSrc: decodeURIComponent(Qt.resolvedUrl("liquidglass.frag").toString().replace("file://", ""))
    readonly property string glassShaderOut: configDir + "/liquidglass.frag.qsb"
    readonly property url glassShaderUrl: "file://" + glassShaderOut

    onBarStyleChanged: if (barStyle === "liquid") startGlass()
    onGlassStateChanged: console.log("[macbar-glass] state:", glassState)
    function startGlass() {
        if (glassState === "ready" || glassState === "building") return;
        glassState = "building";
        qsbProc.running = true;
        hub.refreshWallpaper();
    }
    Process {
        id: qsbProc
        command: ["sh", "-c",
            "mkdir -p \"$(dirname \"$2\")\"; "
            + "for q in qsb qsb6 qsb-qt6 /usr/lib/qt6/bin/qsb /usr/lib64/qt6/bin/qsb /usr/lib/qt/bin/qsb; do "
            + "  if command -v \"$q\" >/dev/null 2>&1; then \"$q\" --qt6 -o \"$2\" \"$1\" && exit 0; fi; "
            + "done; "
            + "[ -f \"$1.qsb\" ] && cp \"$1.qsb\" \"$2\" && exit 0; "
            + "[ -f \"$HOME/.config/macdock/liquidglass.frag.qsb\" ] && cp \"$HOME/.config/macdock/liquidglass.frag.qsb\" \"$2\" && exit 0; "
            + "exit 1",
            "sh", root.glassShaderSrc, root.glassShaderOut]
        stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.log("[macbar-glass] qsb:", text.trim()) }
        onExited: (code, status) => root.glassState = (code === 0 ? "ready" : "failed")
    }

    // wallpaper the glass refracts (override → Noctalia settings.toml → awww/swww/hyprpaper)
    readonly property var wallpaperMap: hub ? hub.wallpaperMap : ({})
    Binding { target: root.hub; property: "barWantsWallpaper"; value: root.liquidActive }
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
    property color wallpaperAccent: "#8A9AB5"      // most common colour of the current wallpaper
    property string wallpaperAccentFor: ""         // image the accent above was sampled from
    // the menu border: same hue as the wallpaper's dominant colour, lifted (dark panels) or deepened (light panels)
    // so it stays readable on the glass whatever the wallpaper is
    readonly property color menuBorderColor: {
        var c = wallpaperAccent;
        var h = c.hslHue < 0 ? 0 : c.hslHue, sat = c.hslSaturation, l = c.hslLightness;
        var s2 = sat < 0.06 ? sat : Math.max(0.28, Math.min(0.75, sat));     // greys stay grey
        var l2 = panelDarkMode ? Math.max(0.66, Math.min(0.86, l * 0.5 + 0.50))
                               : Math.max(0.30, Math.min(0.52, l * 0.5 + 0.05));
        return Qt.hsla(h, s2, l2, 1);
    }
    property string awwwWallpaperPath: ""
    readonly property string dominantWallpaperPath: {
        if (root.awwwWallpaperPath !== "") return root.awwwWallpaperPath;
        var screens = Quickshell.screens;
        return root.wallpaperFor(screens && screens.length ? screens[0].name : "");
    }
    property bool wallpaperSampleForce: true
    onWallpaperPathChanged: { wallpaperSampleForce = true; wallpaperColorTimer.restart(); }
    onWallpaperMapChanged: { wallpaperSampleForce = true; wallpaperColorTimer.restart(); }
    onDominantWallpaperPathChanged: { wallpaperSampleForce = true; wallpaperColorTimer.restart(); }
    function sampleWallpaperColor() {
        if (awwwQueryProc.running || wallpaperColorProc.running) { wallpaperColorTimer.restart(); return; }
        awwwQueryProc.running = true;
    }
    Timer { id: wallpaperColorTimer; interval: 500; onTriggered: root.sampleWallpaperColor() }
    // wallpapers changed from outside the shell (another tool, a script): notice within half a minute.
    // Cheap: it only re-reads the wallpaper's path and re-samples when that path differs.
    Timer { interval: 30000; repeat: true; running: root.barEnabled && !root.gaming; onTriggered: root.sampleWallpaperColor() }
    Process {
        id: awwwQueryProc
        // always exits 0 (even without awww installed) so the sampler below runs on the fallback wallpaper path
        command: ["sh", "-c", "awww query -j 2>/dev/null || swww query -j 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                var out = text.trim(), path = "";
                try {
                    var data = JSON.parse(out);
                    function findImage(v) {
                        if (!v || typeof v !== "object") return "";
                        if (typeof v.image === "string" && v.image !== "") return v.image;
                        for (var k in v) { var found = findImage(v[k]); if (found) return found; }
                        return "";
                    }
                    path = findImage(data);
                } catch (e) {
                    var match = out.match(/image:\s*(.+)/i);
                    if (match) path = match[1].trim();
                }
                if (path.indexOf("~/") === 0) path = Quickshell.env("HOME") + path.substring(1);
                if (root.awwwWallpaperPath !== path) root.awwwWallpaperPath = path;
                var fallback = root.wallpaperFor(Quickshell.screens && Quickshell.screens.length ? Quickshell.screens[0].name : "");
                var p = path || fallback;
                if (p.indexOf("file://") === 0) p = decodeURIComponent(p.substring(7));
                if (p === "") return;
                if (p === root.wallpaperAccentFor && !root.wallpaperSampleForce) return;   // same picture, nothing to do
                root.wallpaperSampleForce = false;
                wallpaperColorProc.samplePath = p;
                // [0] = first frame only (animated gifs); ImageMagick 7 (magick) or 6 (convert)
                wallpaperColorProc.command = ["sh", "-c",
                    'f="$1"; for t in magick convert; do command -v "$t" >/dev/null 2>&1 && ' +
                    '{ "$t" "${f}[0]" -alpha off -resize 64x64! -colors 8 -depth 8 -format %c histogram:info:- 2>/dev/null && exit 0; }; done; exit 0',
                    "sh", p];
                wallpaperColorProc.running = true;
            }
        }
    }
    Process {
        id: wallpaperColorProc
        property string samplePath: ""
        stdout: StdioCollector {
            onStreamFinished: {
                var rows = text.split("\n"), bestCount = -1, bestColor = "";
                for (var i = 0; i < rows.length; i++) {
                    var m = rows[i].match(/^\s*(\d+):.*?(#[0-9a-f]{6})/i);
                    if (m && Number(m[1]) > bestCount) { bestCount = Number(m[1]); bestColor = m[2]; }
                }
                if (bestColor) { root.wallpaperAccent = bestColor; root.wallpaperAccentFor = wallpaperColorProc.samplePath; }
            }
        }
    }

    // live window geometry for the backdrop (polled only while a glass popover is open)
    readonly property var monData: hub ? hub.monData : []
    readonly property var glassClients: hub ? hub.glassClients : []
    property int popCount: 0
    onBarEnabledChanged: { if (!barEnabled) popCount = 0; clipStart(); }
    Binding { target: root.hub; property: "barWantsGeo"; value: root.liquidActive }
    // window captures are admitted by the shared gate in shell.qml (hub.tlFor): 0.2 s after a window appears, one every 110 ms

    Component.onCompleted: {
        syncAppKeys();
        Quickshell.execDetached(["mkdir", "-p", configDir]);
        wallpaperColorTimer.start();
        refreshWifi();
        refreshKeyboardLayout();
        refreshConnections();
    }

    // ═════════════ SETTINGS ═════════════
    // The settings window now lives in MacDock.qml (one window for the whole shell).
    function openSettings(pane) { if (hub) hub.openSettings(pane || "menubar"); }

    // ═════════════ THE BAR ═════════════
    // ═════════════ NOTIFICATIONS ═════════════
    // Receives org.freedesktop.Notifications on D-Bus (stop dunst / mako / swaync first — only one daemon can own the name).
    // IPC: qs -c MacShell ipc call notifications open | close | clear   (opens on the focused screen)
    signal notifPopRequest(bool open)
    property bool notifDnd: false            // Do Not Disturb: still stored in the centre, but no popups
    property real notifBlur: 14              // blur of the notification glass (smooth two-pass Gaussian, same method as the Blur slider)
    property int notifUnread: 0
    property int notifSeq: 0
    property var notifRefs: ({})
    ListModel { id: notifHist }              // notification centre history, newest first
    ListModel { id: notifToasts }            // popups currently on screen, newest first

    // switched off: no daemon at all, so mako / dunst / swaync can own the D-Bus name instead
    Loader {
        active: root.notificationsEnabled
        sourceComponent: NotificationServer {
            keepOnReload: false
            bodySupported: true
            bodyMarkupSupported: false
            imageSupported: true
            actionsSupported: true
            persistenceSupported: true
            onNotification: n => root.notifReceive(n)
        }
    }
    function notifIndex(model, id) {
        for (var i = 0; i < model.count; i++) if (model.get(i).nid === id) return i;
        return -1;
    }
    // System notifications get the UI sound; apps (Discord, Spotify, browsers…) play their own, so they stay silent here
    readonly property var systemNotifApps: ["", "macbar", "macshell", "settings", "system", "notify-send", "networkmanager", "network",
        "power", "upower", "battery", "udiskie", "udisks", "disks", "polkit", "systemd", "screenshot", "grim", "hyprland", "bluetooth", "blueman", "updates", "pacman"]
    function isSystemNotif(n) {
        var app = (n.appName || "").toLowerCase();
        try { if (n.hints && (n.hints["sound-file"] || n.hints["sound-name"])) return false; } catch (e) {}
        return systemNotifApps.indexOf(app) >= 0;
    }
    function notifReceive(n) {
        n.tracked = true;
        var id = ++root.notifSeq;
        root.notifRefs[id] = n;
        var ic = "";
        if (n.image && n.image !== "") ic = n.image;
        else if (n.appIcon && n.appIcon !== "") ic = Quickshell.iconPath(n.appIcon, true);
        var urg = 1;
        if (n.urgency === NotificationUrgency.Critical) urg = 2;
        else if (n.urgency === NotificationUrgency.Low) urg = 0;
        var rec = {
            nid: id, app: n.appName || "", summary: n.summary || "", body: n.body || "",
            icon: ic || "", urgency: urg, time: Date.now(),
            timeout: n.expireTimeout > 0 ? Math.round(n.expireTimeout * 1000) : 0
        };
        notifHist.insert(0, rec);
        while (notifHist.count > 60) {
            var old = notifHist.get(notifHist.count - 1).nid;
            notifHist.remove(notifHist.count - 1);
            delete root.notifRefs[old];
        }
        if ((!root.notifDnd || urg === 2) && !root.notifOpen) {
            // the screenshot has its own shutter sound
            if (root.isSystemNotif(n) && !(rec.app === "macbar" && rec.summary.indexOf("Screenshot") === 0)) root.playSound("glass", 0.7);
            notifToasts.insert(0, rec);
            while (notifToasts.count > 4) notifToasts.remove(notifToasts.count - 1);
        }
        if (!root.notifOpen) root.notifUnread++;
        try { n.closed.connect(function () { root.notifToastRemove(id); }); } catch (e) {}
        // apps that update a notification in place (progress, now playing…): push the new text into the popup and
        // the history, the popup then blur-morphs to it
        function upd(role, val) {
            var i = notifIndex(notifToasts, id); if (i >= 0) notifToasts.setProperty(i, role, val || "");
            var j = notifIndex(notifHist, id); if (j >= 0) notifHist.setProperty(j, role, val || "");
        }
        try { n.summaryChanged.connect(function () { upd("summary", n.summary); }); } catch (e) {}
        try { n.bodyChanged.connect(function () { upd("body", n.body); }); } catch (e) {}
    }
    // ── lock screen: the unread notifications, privacy-safe (app name, app icon, time — never the text) ──
    // written to ~/.cache/macshell/lock-notifs.json, which MacLock watches
    onNotifUnreadChanged: lockNotifSave.restart()
    Connections { target: notifHist; function onCountChanged() { lockNotifSave.restart(); } }
    Timer { id: lockNotifSave; interval: 300; onTriggered: root.lockNotifWrite() }
    function appIconFor(app) {
        if (!app) return "";
        var e = null;
        try { e = DesktopEntries.heuristicLookup ? DesktopEntries.heuristicLookup(app) : null; } catch (err) { e = null; }
        var nm = (e && e.icon) ? e.icon : app.toLowerCase();
        return Quickshell.iconPath(nm, true) || "";
    }
    function lockNotifWrite() {
        var out = [], n = Math.min(notifUnread, notifHist.count, 20);
        for (var i = 0; i < n; i++) {
            var r = notifHist.get(i);
            out.push({ id: r.nid, app: r.app || "Notification", icon: appIconFor(r.app), time: r.time });
        }
        Quickshell.execDetached(["sh", "-c", "mkdir -p \"$HOME/.cache/macshell\" && printf '%s\\n' \"$1\" > \"$HOME/.cache/macshell/lock-notifs.json.tmp\" && mv -f \"$HOME/.cache/macshell/lock-notifs.json.tmp\" \"$HOME/.cache/macshell/lock-notifs.json\"",
            "sh", JSON.stringify(out)]);
    }

    property bool notifOpen: false
    function notifToastRemove(id) {
        var i = notifIndex(notifToasts, id);
        if (i >= 0) notifToasts.remove(i);
    }
    function notifDelete(id) {
        notifToastRemove(id);
        var i = notifIndex(notifHist, id);
        if (i >= 0) notifHist.remove(i);
        var n = root.notifRefs[id];
        if (n) { try { n.dismiss(); } catch (e) {} delete root.notifRefs[id]; }
    }
    // Clear All: every card in Notification Center turns to dust (staggered), then the list is emptied
    signal notifDustAll()
    property bool notifClearing: false
    property var notifMergeFrom: ({})        // nid → {x, y, w} of its popup (ui coordinates) at the moment the panel opened
    property bool notifFlying: false          // cards are flying from the popups into the panel
    onNotifMergeFromChanged: { if (Object.keys(notifMergeFrom).length > 0) { notifFlying = true; flyEnd.restart(); } }
    Timer { id: flyEnd; interval: 900; onTriggered: root.notifFlying = false }
    onNotifOpenChanged: if (!notifOpen) notifMergeFrom = ({})
    function notifClearAnimated() {
        if (notifHist.count === 0) return;
        notifClearing = true;
        notifDustAll();
        notifClearLater.interval = 950 + Math.min(notifHist.count, 12) * 55;
        notifClearLater.restart();
    }
    Timer { id: notifClearLater; onTriggered: { root.notifClear(); root.notifClearing = false; } }
    function notifClear() {
        notifToasts.clear();
        for (var i = 0; i < notifHist.count; i++) {
            var n = root.notifRefs[notifHist.get(i).nid];
            if (n) { try { n.dismiss(); } catch (e) {} }
        }
        notifHist.clear();
        root.notifRefs = ({});
        root.notifUnread = 0;
    }
    function notifActivate(id) {
        var n = root.notifRefs[id];
        if (n) {
            try {
                for (var i = 0; i < n.actions.length; i++)
                    if (n.actions[i].identifier === "default") { n.actions[i].invoke(); break; }
            } catch (e) {}
        }
        notifToastRemove(id);
    }

    // ═════════════ WALLPAPER PICKER (CTRL + ALT + W) ═════════════
    //   hl.bind("CTRL + ALT + W", hl.dsp.exec_cmd("qs -c macbar ipc call wallpapers toggle"))
    property string wallpaperDir: ""          // "" = ~/Pictures/Wallpapers
    property var wallpaperFavs: []            // favourite image paths, shown first
    property string wallpaperVideo: ""        // animated wallpaper (video) playing right now, "" = a still picture
    property string wpRestorePath: ""         // the picture the picker set last: put back at every start (awww does not keep it after a reboot)
    property var wpThumbs: ({})               // video path → cached thumbnail
    property var wpPreviews: ({})             // video path → small looping animated WebP (no video player in the shell)
    property string wallpaperCmd: ""          // "" = auto (awww / swww / hyprpaper); or your own command, {} = the image path
    property real wpBlur: 40                  // blur of the picker glass
    property bool wpOpen: false
    property string wpStatus: ""
    property var wpDirList: []                // images found in the folder
    property var wpFavOk: ({})                // favourites that still exist on disk
    property var wpFiles: []                  // favourites first, then the rest { path, name, fav }
    property string wpQuery: ""               // search filter
    readonly property var wpShown: {          // what the grid shows (wpFiles filtered by the search)
        var q = root.wpQuery.trim().toLowerCase(), f = root.wpFiles;
        if (q === "") return f;
        var out = [];
        for (var i = 0; i < f.length; i++) if (f[i].name.toLowerCase().indexOf(q) >= 0) out.push(f[i]);
        return out;
    }
    function wpResolveDir() {
        var d = (root.wallpaperDir || "").trim();
        if (d === "") d = "~/Pictures/Wallpapers";
        if (d.indexOf("~") === 0) d = Quickshell.env("HOME") + d.substring(1);
        while (d.length > 1 && d.charAt(d.length - 1) === "/") d = d.substring(0, d.length - 1);
        return d;
    }
    readonly property string wpDirEff: { root.wallpaperDir; return root.wpResolveDir(); }
    function wpName(path) {
        var n = path.substring(path.lastIndexOf("/") + 1);
        var k = n.lastIndexOf(".");
        return k > 0 ? n.substring(0, k) : n;
    }
    function wpRebuild() {
        var favs = root.wallpaperFavs || [], inDir = {}, seen = {}, out = [], i;
        for (i = 0; i < root.wpDirList.length; i++) inDir[root.wpDirList[i]] = true;
        for (i = 0; i < favs.length; i++) {
            if (!(inDir[favs[i]] || root.wpFavOk[favs[i]]) || seen[favs[i]]) continue;
            seen[favs[i]] = true;
            out.push({ path: favs[i], name: root.wpName(favs[i]), fav: true, video: root.wpIsVideo(favs[i]), thumb: root.wpThumbs[favs[i]] || "", preview: root.wpPreviews[favs[i]] || "" });
        }
        for (i = 0; i < root.wpDirList.length; i++) {
            var f = root.wpDirList[i];
            if (seen[f]) continue;
            out.push({ path: f, name: root.wpName(f), fav: false, video: root.wpIsVideo(f), thumb: root.wpThumbs[f] || "", preview: root.wpPreviews[f] || "" });
        }
        root.wpFiles = out;
    }
    function wpParse(text) {
        var lines = text.split("\n"), dir = [], ok = {}, th = {}, pv = {};
        for (var i = 0; i < lines.length; i++) {
            var l = lines[i];
            if (l.indexOf("A:") === 0) dir.push(l.substring(2));
            else if (l.indexOf("T:") === 0) { var k = l.indexOf("\t"); if (k > 2) th[l.substring(2, k)] = l.substring(k + 1); }
            else if (l.indexOf("P:") === 0) { var k2 = l.indexOf("\t"); if (k2 > 2) pv[l.substring(2, k2)] = l.substring(k2 + 1); }
            else if (l.indexOf("F:") === 0) ok[l.substring(2)] = true;
        }
        root.wpThumbs = th;
        root.wpPreviews = pv;
        root.wpDirList = dir;
        root.wpFavOk = ok;
        root.wpRebuild();

        // Return the file list immediately; build missing video thumbnails in a separate process.
        var videos = [];
        for (var j = 0; j < dir.length; j++) if (root.wpIsVideo(dir[j])) videos.push(dir[j]);
        if (videos.length && !wpThumbBuild.running) {
            var script = [
                'tc="$HOME/.cache/macshell/thumbs"; mkdir -p "$tc"',
                'for v do',
                '  t="$tc/$(printf "%s:%s" "$v" "$(stat -c %Y "$v" 2>/dev/null)" | md5sum | cut -c1-16).jpg"',
                '  if [ ! -s "$t" ]; then ffmpeg -loglevel error -y -ss 1 -i "$v" -frames:v 1 -vf "scale=360:-2" "$t" </dev/null >/dev/null 2>&1; fi',
                '  [ -s "$t" ] && printf "T:%s\\t%s\\n" "$v" "$t"',
                '  w="${t%.jpg}.webp"; if [ ! -s "$w" ] && [ -x "$HOME/.config/hypr-macshell/scripts/macshell-setwall.sh" ]; then setsid nice -n 15 "$HOME/.config/hypr-macshell/scripts/macshell-setwall.sh" --prepare "$v" >/dev/null 2>&1 </dev/null & fi',
                'done'
            ].join("\n");
            wpThumbBuild.command = ["sh", "-c", script, "sh"].concat(videos);
            wpThumbBuild.running = true;
        }
    }
    function wpMergeThumbs(text) {
        var th = Object.assign({}, root.wpThumbs || {}), lines = text.split("\n");
        for (var i = 0; i < lines.length; i++) {
            if (lines[i].indexOf("T:") !== 0) continue;
            var k = lines[i].indexOf("\t");
            if (k > 2) th[lines[i].substring(2, k)] = lines[i].substring(k + 1);
        }
        root.wpThumbs = th;
        root.wpRebuild();
    }
    function wpRefresh() {
        if (wpScan.running) return;
        var script = [
            'd="$1"; mk="$2"; shift 2',
            '[ "$mk" = "1" ] && [ ! -d "$d" ] && mkdir -p "$d" 2>/dev/null',
            'if [ -d "$d" ]; then find -L "$d" -maxdepth 3 -type f 2>/dev/null | grep -iE "[.](jpe?g|png|webp|bmp|gif|mp4|webm|mkv|mov|m4v)$" | sort -V | sed "s/^/A:/"; fi',
            'for f in "$@"; do [ -f "$f" ] && echo "F:$f"; done',
            'exit 0'
        ].join("\n");
        wpScan.command = ["sh", "-c", script, "sh", root.wpDirEff, (root.wallpaperDir || "").trim() === "" ? "1" : "0"].concat(root.wallpaperFavs || []);
        wpScan.running = true;
    }
    function wpSetDir(d) {
        root.wallpaperDir = (d || "").trim();
        root.wpStatus = "";
        root.wpRefresh();
    }
    function wpToggleFav(path) {
        var f = (root.wallpaperFavs || []).slice(), i = f.indexOf(path);
        if (i >= 0) f.splice(i, 1); else f.push(path);
        root.wallpaperFavs = f;
        root.wpRebuild();
    }
    function wpIsVideo(p) { return /[.](mp4|webm|mkv|mov|m4v)$/i.test(p || ""); }
    readonly property string setwallScript: Quickshell.env("HOME") + "/.config/hypr-macshell/scripts/macshell-setwall.sh"
    // ── light / dark wallpaper pairs (macOS "Automatic / Light / Dark / Dynamic") ──
    property string wallpaperAppearance: "auto"     // auto (follows Dark Mode) | light | dark | dynamic (time of day)
    property string wpPairLight: ""
    property string wpPairDark: ""
    readonly property bool wpHasPair: wpPairLight !== "" && wpPairDark !== ""
    readonly property string dynwallScript: Quickshell.env("HOME") + "/.config/hypr-macshell/scripts/macshell-dynwall.sh"
    // "<name>-Light.ext" ↔ "<name>-Dark.ext" in the same folder (from the folder scan)
    function wpPairOf(path) {
        var m = /^(.*[-_ ])(light|dark)(\.[a-z0-9]+)$/i.exec(path || "");
        if (!m) return null;
        var other = m[2].toLowerCase() === "light" ? "Dark" : "Light", list = root.wpDirList, cand = null;
        for (var i = 0; i < list.length; i++) {
            var mm = /^(.*[-_ ])(light|dark)(\.[a-z0-9]+)$/i.exec(list[i]);
            if (mm && mm[1] === m[1] && mm[2].toLowerCase() === other.toLowerCase()) { cand = list[i]; break; }
        }
        if (!cand) return null;
        return m[2].toLowerCase() === "light" ? { light: path, dark: cand } : { light: cand, dark: path };
    }
    function hhmmToMin(t) { var m = /T(\d+):(\d+)/.exec(t || ""); return m ? parseInt(m[1]) * 60 + parseInt(m[2]) : -1; }
    // Sets a picture as the real desktop wallpaper: awww first (its daemon is started if needed), then the other daemons.
    // $1 = image path. Also stops a running animated wallpaper (mpvpaper) so it does not stay on top of the picture.
    // Clear the watched state before stopping mpvpaper; otherwise the live-wallpaper supervisor respawns it.
    readonly property string stopVideoScript: [
        'state="$HOME/.config/macshell/wallpaper-video"',
        'rm -f "$state" "$HOME/.config/macshell/wallpaper-video-play" "$HOME/.config/macshell/wallpaper-video-glass"',
        'supfile="$HOME/.cache/macshell/wallsup.pid"',
        'if [ -f "$supfile" ]; then g=$(cat "$supfile" 2>/dev/null); case "$g" in ""|*[!0-9]*) ;; *) kill -TERM -- "-$g" 2>/dev/null ;; esac; rm -f "$supfile"; fi',
        'pkill -CONT -x mpvpaper >/dev/null 2>&1',
        'pkill -TERM -x mpvpaper >/dev/null 2>&1',
        'for i in 1 2 3 4 5; do pgrep -x mpvpaper >/dev/null || break; sleep 0.1; done',
        'pkill -KILL -x mpvpaper >/dev/null 2>&1'
    ].join("\n")
    readonly property string awwwScript: [
        'p="$1"',
        root.stopVideoScript,
        'if command -v awww >/dev/null 2>&1; then',
        '  if ! awww query >/dev/null 2>&1; then',
        '    if command -v awww-daemon >/dev/null 2>&1; then setsid awww-daemon >/dev/null 2>&1 & fi',
        '    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do awww query >/dev/null 2>&1 && break; sleep 0.3; done',
        '  fi',
        '  if awww img "$p" --transition-type fade --transition-duration 0.7; then echo "applied with: awww"; exit 0; fi',
        'fi',
        'if command -v swww >/dev/null 2>&1 && swww query >/dev/null 2>&1 && swww img "$p" --transition-type fade --transition-duration 0.7; then echo "applied with: swww"; exit 0; fi',
        'if command -v noctalia >/dev/null 2>&1 && noctalia msg wallpaper-set "$p" >/dev/null 2>&1; then echo "applied with: noctalia"; exit 0; fi',
        'if pgrep -x hyprpaper >/dev/null 2>&1; then',
        '  if hyprctl hyprpaper wallpaper ",$p" >/dev/null 2>&1 || { hyprctl hyprpaper preload "$p" >/dev/null 2>&1; hyprctl hyprpaper wallpaper ",$p" >/dev/null 2>&1; }; then echo "applied with: hyprpaper"; exit 0; fi',
        'fi',
        'if pgrep -f noctalia-shell >/dev/null 2>&1 && qs -c noctalia-shell ipc call wallpaper set "$p" "" >/dev/null 2>&1; then echo "applied with: noctalia-shell (qs ipc)"; exit 0; fi',
        'if pgrep -x swaybg >/dev/null 2>&1; then pkill -x swaybg; setsid swaybg -i "$p" -m fill >/dev/null 2>&1 & echo "applied with: swaybg"; exit 0; fi',
        'echo "no wallpaper daemon accepted the image (tried awww, swww, noctalia, hyprpaper, noctalia-shell, swaybg)" >&2',
        'notify-send "Wallpaper" "Could not set it: install awww (and start awww-daemon), or set wallpaperCmd in settings.json." 2>/dev/null',
        'exit 1'
    ].join("\n")
    property string wpAppliedPair: ""
    function wpApplyAppearance() {
        if (!wpHasPair) return;
        var mode = wallpaperAppearance === "auto" ? (darkMode ? "dark" : "light") : wallpaperAppearance;
        var rise = 390, set_ = 1110;
        try {
            var wx = root.hub && root.hub.widgets ? root.hub.widgets.weather : null;
            if (wx && wx.daily && wx.daily.sunrise) { var a = hhmmToMin(wx.daily.sunrise[0]), b2 = hhmmToMin(wx.daily.sunset[0]); if (a > 0) rise = a; if (b2 > 0) set_ = b2; }
        } catch (e) {}
        if (mode === "dynamic") { var d = new Date(), n = d.getHours() * 60 + d.getMinutes(); mode = (n >= rise && n < set_) ? "light" : "dark"; }
        var p = mode === "dark" ? wpPairDark : wpPairLight;
        if (p === "") return;
        root.wallpaperVideo = "";
        root.wallpaperPath = p;
        try { if (root.hub && root.hub.dock) root.hub.dock.wallpaperPath = p; } catch (e) {}
        if (p === root.wpAppliedPair) return;                         // already on screen
        root.wpAppliedPair = p;
        wpApplyProc.command = ["sh", "-c", root.awwwScript, "sh", p];  // the real desktop wallpaper, through awww
        wpApplyProc.running = true;
    }
    onWallpaperAppearanceChanged: wpApplyAppearance()
    onDarkModeChanged: if (wallpaperAppearance === "auto") wpApplyAppearance()
    Timer { interval: 60000; repeat: true; running: root.wpHasPair && root.wallpaperAppearance === "dynamic" && !root.gaming; onTriggered: root.wpApplyAppearance() }
    // at start: scan the folder, then pick up a pair for the wallpaper already in use
    Timer { interval: 1500; running: true; onTriggered: root.wpRefresh() }
    onWpDirListChanged: {
        if (wpHasPair) return;
        var p = wpPairOf(wallpaperPath);
        if (p) { wpPairLight = p.light; wpPairDark = p.dark; wpApplyAppearance(); }
    }
    Timer { interval: 2500; running: true; onTriggered: root.wpApplyAppearance() }

    function wpApply(path) {
        var pair = wpPairOf(path);
        if (pair) { wpPairLight = pair.light; wpPairDark = pair.dark; root.wpAppliedPair = ""; wpApplyAppearance(); return; }
        wpPairLight = ""; wpPairDark = ""; root.wpAppliedPair = "";
        // animated wallpapers go through macshell-setwall.sh (mpvpaper for videos); pictures are always set with awww below
        if (root.wpIsVideo(path)) {
            root.wallpaperVideo = path;
            setwallProc.command = [root.setwallScript, path];
            setwallProc.running = true;
            return;
        }
        root.wallpaperVideo = "";
        root.wpRestorePath = path;
        root.wallpaperPath = path;                                            // the glass refracts the new image straight away
        try { if (root.hub && root.hub.dock) root.hub.dock.wallpaperPath = path; } catch (e) {}
        var cmd = (root.wallpaperCmd || "").trim();
        var script = cmd !== "" ? root.stopVideoScript + "\n" + cmd.split("{}").join('"$1"') : root.awwwScript;
        wpApplyProc.command = ["sh", "-c", script, "sh", path];
        wpApplyProc.running = true;
    }
    // Wallpaper that survives a reboot: awww / mpvpaper start empty at login, so the shell puts the last choice back.
    // A picture is skipped when awww already shows it; light/dark pairs are handled by wpApplyAppearance.
    function wpRestore() {
        if (wpHasPair) return;
        if (wallpaperVideo !== "") {
            setwallProc.command = ["sh", "-c", '[ -x "$1" ] && exec "$1" "$2"', "sh", setwallScript, wallpaperVideo];
            setwallProc.running = true;
            return;
        }
        var p = wpRestorePath;
        if (p === "") return;
        var cmd = (wallpaperCmd || "").trim();
        var script = cmd !== "" ? '[ -f "$1" ] || exit 0\n' + root.stopVideoScript + "\n" + cmd.split("{}").join('"$1"')
                                : '[ -f "$1" ] || exit 0\nif command -v awww >/dev/null 2>&1 && awww query 2>/dev/null | grep -qF -- "$1"; then exit 0; fi\n' + root.awwwScript;
        wpApplyProc.command = ["sh", "-c", script, "sh", p];
        wpApplyProc.running = true;
    }
    Timer { interval: 3500; running: true; onTriggered: root.wpRestore() }
    Process {
        id: setwallProc
        stdout: StdioCollector {
            onStreamFinished: {
                var l = text.trim().split("\n"), still = (l[l.length - 1] || "").trim();
                if (still === "") return;
                root.wallpaperPath = still;
                try { if (root.hub && root.hub.dock) root.hub.dock.wallpaperPath = still; } catch (e) {}
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.log("[wallpaper] error:", text.trim()) }
    }
    Process {
        id: wpApplyProc
        onExited: { root.wallpaperSampleForce = true; wallpaperColorTimer.restart(); }
        stdout: StdioCollector { onStreamFinished: if (text.trim() !== "") console.log("[wallpaper]", text.trim()) }
        stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.log("[wallpaper] error:", text.trim()) }
    }
    function wpToggle() {
        root.wpOpen = !root.wpOpen;
        if (root.wpOpen) root.wpRefresh();
    }
    function wpPickFolder() {
        var script = [
            'd="$1"; [ -d "$d" ] || d="$HOME"',
            'if command -v zenity >/dev/null 2>&1; then zenity --file-selection --directory --filename="$d/" --title="Wallpaper folder" 2>/dev/null',
            'elif command -v kdialog >/dev/null 2>&1; then kdialog --getexistingdirectory "$d" 2>/dev/null',
            'elif command -v yad >/dev/null 2>&1; then yad --file --directory --filename="$d/" 2>/dev/null',
            'else echo "!nopicker"; fi',
            'exit 0'
        ].join("\n");
        wpPick.command = ["sh", "-c", script, "sh", root.wpDirEff];
        root.wpOpen = false;                       // the overlay would sit on top of the dialog, so hide it meanwhile
        wpPick.running = true;
    }
    Process { id: wpScan; stdout: StdioCollector { onStreamFinished: root.wpParse(text) } }
    Process { id: wpThumbBuild; stdout: StdioCollector { onStreamFinished: root.wpMergeThumbs(text) } }
    Process {
        id: wpPick
        stdout: StdioCollector {
            onStreamFinished: {
                var r = text.trim();
                if (r === "!nopicker") root.wpStatus = "No folder dialog found (install zenity or kdialog) - type the path instead.";
                else if (r !== "") root.wpSetDir(r);
                root.wpOpen = true;
                root.wpRefresh();
            }
        }
    }
    onWallpaperFavsChanged: if (wpOpen) wpRebuild()
    IpcHandler {
        target: "wallpapers"
        function toggle(): void { root.wpToggle(); }
        // qs -c MacShell ipc call wallpapers appearance auto|light|dark|dynamic
        function set(path: string): void { root.wpApply(path); }
        function appearance(mode: string): void { if (["auto", "light", "dark", "dynamic"].indexOf(mode) >= 0) root.wallpaperAppearance = mode; }
        function open(): void { if (!root.wpOpen) root.wpToggle(); }
        function close(): void { root.wpOpen = false; }
    }

    // ═════════════ WORKSPACES (centre of the bar) ═════════════
    function hlWorkspace(sel) {      // Hyprland 0.55+ (Lua) workspace switch
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"" + sel + "\" })"]);
    }
    // The counter shows the workspaces Hyprland really has (0.55+ creates and destroys them on demand), nothing more.
    // Set wsMin above 0 only if you want workspaces 1..wsMin to be shown even when they do not exist.
    property int wsMin: 0
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            var n = event.name;
            if (n === "createworkspacev2" || n === "destroyworkspacev2" || n === "workspacev2" || n === "moveworkspacev2" || n === "renameworkspace")
                Hyprland.refreshWorkspaces();
        }
    }
    readonly property var wsIds: {
        var ids = [], vals = Hyprland.workspaces.values;
        for (var i = 1; i <= root.wsMin; i++) ids.push(i);
        for (var j = 0; j < vals.length; j++) {
            var id = vals[j].id;
            if (id > 0 && ids.indexOf(id) < 0) ids.push(id);
        }
        var fw = Hyprland.focusedWorkspace;
        if (fw && fw.id > 0 && ids.indexOf(fw.id) < 0) ids.push(fw.id);
        if (ids.length === 0) ids.push(1);                    // never an empty counter
        ids.sort(function (a, b) { return a - b; });
        return ids;
    }
    function wsOccupied(id) {
        var vals = Hyprland.workspaces.values;
        for (var i = 0; i < vals.length; i++) if (vals[i].id === id) return (vals[i].toplevels ? vals[i].toplevels.values.length : 0) > 0;
        return false;
    }

    // ═════════════ WINDOW SWITCHER (ALT + TAB) ═════════════
    // Hyprland binds (put these in hyprland.conf, and remove any existing ALT+TAB bind):
    //   bind   = ALT, TAB, exec, qs -c macshell ipc call switcher next
    //   bind   = ALT SHIFT, TAB, exec, qs -c macshell ipc call switcher prev
    //   bindrt = ALT, Alt_L, exec, qs -c macshell ipc call switcher commit     # optional safety net: switch on ALT release
    // (use the same `qs ...` prefix you use for the Spotlight bind). Hold ALT, tap TAB to cycle, release ALT to switch.
    // Layer namespace: "macswitch" (only needed for a blur layerrule if you are NOT using the Liquid Glass style).
    property real switcherBlur: 15           // blur of the switcher glass (smooth Gaussian; less than Spotlight / notifications)
    property string switcherStyle: "glass"   // glass (Liquid Glass) | frosted | opaque — Settings → Desktop & Dock
    property bool swOpen: false
    property var swApps: []                  // open apps, most recently used first: { appId, name, icon, win, count }
    property int swIndex: 0
    property var swMru: []                   // recently focused toplevels, newest first
    function swTrack() {
        var t = root.activeTl;
        if (!t) return;
        var a = [t];
        for (var i = 0; i < root.swMru.length && a.length < 60; i++) if (root.swMru[i] !== t) a.push(root.swMru[i]);
        root.swMru = a;
    }
    function swIcon(a) {
        if (a.icon) return root.iconSrc(a.icon);
        var p = Quickshell.iconPath(a.appId, true);
        if (p === "") p = Quickshell.iconPath(a.appId.toLowerCase(), true);
        return p !== "" ? p : root.iconSrc("");
    }
    function swBuild() {
        var vals = ToplevelManager.toplevels.values, all = [];
        for (var i = 0; i < vals.length; i++) all.push(vals[i]);
        var order = [];
        if (root.activeTl && all.indexOf(root.activeTl) >= 0) order.push(root.activeTl);       // the app you are in comes first
        for (var m = 0; m < root.swMru.length; m++) if (all.indexOf(root.swMru[m]) >= 0 && order.indexOf(root.swMru[m]) < 0) order.push(root.swMru[m]);
        for (var j = 0; j < all.length; j++) if (order.indexOf(all[j]) < 0) order.push(all[j]);
        var seen = {}, apps = [];
        for (var k = 0; k < order.length; k++) {
            var t = order[k], id = t.appId || "";
            if (id === "") continue;
            // MacShell's own windows (all "org.quickshell") are separate apps: Clock, System Settings
            if (id === "org.quickshell") id = t.title === "Clock" ? "macshell-clock"
                                             : (t.title === "App Store" ? "macshell-appstore"
                                             : (t.title === "macshell Settings" ? "systemsettings" : id));
            if (seen[id] !== undefined) { apps[seen[id]].count++; continue; }
            var e = root.lookup(id);
            seen[id] = apps.length;
            apps.push({ appId: id, cls: t.appId, name: id === "systemsettings" ? "System Settings" : (id === "org.quickshell" ? "MacShell" : (e ? e.name : id)),
                        icon: id === "systemsettings" ? "preferences-system" : (id === "org.quickshell" ? root.logoPath : (e ? e.icon : "")), win: t, count: 1 });
        }
        return apps;
    }
    function swNext(dir) {
        if (!root.swOpen) {
            var apps = root.swBuild();
            if (apps.length === 0) return;
            root.swApps = apps;
            root.swIndex = 0;                // 0 = the app you are in, so the first TAB lands on the previous one
            root.swOpen = true;
        }
        var n = root.swApps.length;
        root.swIndex = (root.swIndex + (dir >= 0 ? 1 : n - 1)) % n;
    }
    // The switcher layer holds EXCLUSIVE keyboard focus while open, and Hyprland can refuse to focus / switch
    // workspace while an exclusive layer is up. So: close the layer first, then dispatch a moment later.
    property var swPending: null
    Timer {
        id: swFocusTimer
        interval: 60
        onTriggered: {
            var t = root.swPending;
            root.swPending = null;
            if (!t) return;
            // Hyprland 0.55+ is Lua: `hyprctl dispatch` takes a Lua expression, the old "focuswindow ..." strings fail.
            var lua = "";
            if (t.ws > 0) lua += "hl.dispatch(hl.dsp.focus({ workspace = \"" + t.ws + "\" })); ";
            lua += "hl.dispatch(hl.dsp.focus({ window = \"" + (t.addr !== "" ? "address:" + t.addr : "class:^(" + t.cls + ")$") + "\" })); ";
            lua += "hl.dispatch(hl.dsp.window.bring_to_top())";
            console.log("[switcher] hyprctl eval '" + lua + "'");
            Quickshell.execDetached(["hyprctl", "eval", lua]);
        }
    }
    function swCommit() {
        if (!root.swOpen) return;
        var a = root.swApps[root.swIndex];
        root.swOpen = false;
        if (!a || !a.win) return;
        try { Hyprland.refreshToplevels(); } catch (e) {}
        var ts = Hyprland.toplevels.values, hit = null, i;
        for (i = 0; i < ts.length; i++) if (ts[i].wayland === a.win) { hit = ts[i]; break; }
        if (!hit) {                                   // handle did not match: fall back to class (+ title)
            var cls = (a.cls || a.appId || "").toLowerCase(), ttl = a.win.title || "", loose = null;
            for (i = 0; i < ts.length; i++) {
                var o = ts[i].lastIpcObject || {};
                if (("" + (o["class"] || "")).toLowerCase() !== cls) continue;
                if (("" + (o.title || "")) === ttl) { hit = ts[i]; break; }
                if (!loose) loose = ts[i];
            }
            if (!hit) hit = loose;
        }
        var addr = "", ws = 0;
        if (hit) {
            addr = "" + hit.address;
            if (addr.indexOf("0x") !== 0) addr = "0x" + addr;
            var w = hit.workspace;
            if (w && w.id > 0) ws = w.id;
            else if (hit.lastIpcObject && hit.lastIpcObject.workspace && hit.lastIpcObject.workspace.id > 0) ws = hit.lastIpcObject.workspace.id;
        }
        console.log("[switcher] app=" + a.appId + " matched=" + (hit ? "yes" : "no") + " addr=" + addr + " ws=" + ws);
        if (!hit && !a.appId) { try { a.win.activate(); } catch (e2) {} return; }
        root.swPending = { addr: addr, ws: ws, cls: (a.cls || a.appId || "").replace(/[\\"']/g, "") };
        swFocusTimer.restart();
    }
    function swCancel() { root.swOpen = false; }
    IpcHandler {
        target: "switcher"
        function next(): void { root.swNext(1); }
        function prev(): void { root.swNext(-1); }
        function commit(): void { root.swCommit(); }
        function cancel(): void { root.swCancel(); }
    }

    Variants {
        model: (root.settingsReady && root.barLayerNeeded) ? Quickshell.screens : []

        Scope {
            id: perScreen
            required property var modelData

        // ═════════ the bar's background lives in its OWN layer (namespace "macbarbg") ═════════
        // Hyprland blurs a whole layer or none of it, and the bar window also carries the popovers, so the bar strip is a separate
        // layer just under the bar: it paints a translucent fill (Settings → Menu Bar → Bar background) and takes no input.
        // Blur it with:  layerrule = blur, macbarbg   +   layerrule = ignorealpha 0.05, macbarbg
        PanelWindow {
            id: barBgWin
            screen: perScreen.modelData
            visible: root.barBgOpacity > 0.001
            anchors { left: true; right: true; top: true }
            implicitHeight: root.barH
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            mask: Region { }

            WlrLayershell.namespace: "macbarbg"
            // Top, not Bottom: on Bottom it sat under the windows, so it only ever blurred the wallpaper — over a
            // window there was nothing behind it to blur. It is declared before the bar itself, so it stacks under it.
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Rectangle {
                anchors.fill: parent
                color: root.darkMode ? Qt.rgba(0.10, 0.10, 0.11, root.barBgOpacity) : Qt.rgba(1, 1, 1, root.barBgOpacity)
            }
        }

        PanelWindow {
            id: win
            property var modelData: perScreen.modelData
            screen: perScreen.modelData

            anchors { left: true; right: true; top: true }
            implicitHeight: root.barH + root.popRoom
            color: "transparent"

            exclusionMode: ExclusionMode.Normal
            exclusiveZone: root.barEnabled ? root.barH : 0

            WlrLayershell.namespace: "macbar"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: ((ui.pop === "wifi" || (ui.pop === "cc" && ui.ccPage === "wifi")) && ui.wifiPrompt !== "") ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            mask: Region { item: maskItem; Region { item: toastMask } }

            Item {
                id: ui
                anchors.fill: parent

                property string pop: ""          // "", apple, app, file, edit, view, window, help, cc, cal
                property real menuX: 0
                property var menuModel: []
                property string armed: ""
                property int calYear: 2026
                property int calMonth: 0
                property string wifiPrompt: ""      // ssid whose password field is open in the Wi-Fi popover
                property bool ccEdit: false         // Control Center is in "Edit Controls" mode
                property string ccPage: ""          // "" = the control grid, "wifi" = the Wi-Fi list shown inside the Control Center
                onCcPageChanged: wifiPrompt = ""
                property var trayItem: null         // SystemTrayItem whose menu is open in the tray popover
                property var trayStack: []          // submenu path (QsMenuEntry objects) inside that menu
                Timer { interval: 400; repeat: true; running: ui.pop === "vol"; onTriggered: root.audioTick++ }
                readonly property bool toastScreen: Quickshell.screens.length === 1 || (Hyprland.focusedMonitor !== null && Hyprland.focusedMonitor.name === win.modelData.name)
                // the Control Center IPC: the focused screen opens it
                Connections {
                    target: root
                    function onCcRequest(open) {
                        if (!ui.toastScreen || !root.ccEnabled) return;
                        ui.pop = (open && ui.pop !== "cc") ? "cc" : "";
                    }
                }
                readonly property bool toastsShown: toastScreen && notifToasts.count > 0
                // notifications arriving with no panel open: measure what's behind the banners
                onToastsShownChanged: if (toastsShown && pop === "") root.measureTone(win.modelData.x + ui.width - 374, win.modelData.y + root.barH + 8, 364, 90)

                function openTray(item, x) {
                    if (!item || !item.hasMenu) return;
                    if (pop === "tray" && trayItem === item) { pop = ""; return; }
                    trayStack = [];
                    trayItem = item;
                    menuX = x;
                    pop = "tray";
                }

                function wifiPick(n) {
                    if (n.inUse) { root.disconnectWifi(); return; }
                    if (root.wifiBusy !== "") return;
                    if (n.secure && !n.saved) { wifiPrompt = (wifiPrompt === n.ssid) ? "" : n.ssid; return; }
                    wifiPrompt = "";
                    root.connectWifi(n.ssid, "");
                }
                function wifiSubmit(ssid, pw) {
                    if (pw === "") return;
                    wifiPrompt = "";
                    root.connectWifi(ssid, pw);
                }
                Timer {
                    interval: 4000; repeat: true
                    running: (ui.pop === "wifi" || (ui.pop === "cc" && ui.ccPage === "wifi")) && ui.wifiPrompt === ""     // paused while typing so the list doesn't rebuild under the cursor
                    onTriggered: root.scanWifi()
                }
                Timer {
                    interval: 4000; repeat: true
                    running: ui.pop === "bt" || (ui.pop === "cc" && ui.ccPage === "bt")
                    onTriggered: root.scanBt()
                }

                // Spotlight state
                property string spMode: "home"          // home | actions | apps
                property string spQuery: ""
                property string spHoverLabel: ""
                property int spSel: 0
                property var spExpanded: ({})
                property bool clipMenu: false           // the round "..." menu of the Clipboard panel
                property bool spCalm: false             // Spotlight was opened by the clipboard / emoji shortcut: plain fade, no springy pop
                property bool spReqCalm: false
                property int emCat: 0                   // emoji category tab (0 = recents)
                property bool spHover: false            // spSel was just changed by the pointer, so lists must not scroll to it
                readonly property int emCols: 12
                readonly property bool spFull: spMode === "apps" || spMode === "clip" || spMode === "emoji"
                property var spResults: spMode === "actions" ? root.actionItems(spQuery)
                                        : (spMode === "clip" ? root.clipFiltered(spQuery)
                                        : (spMode === "emoji" ? root.emojiItems(spQuery, emCat)
                                        : (spQuery.trim() === "" ? [] : root.homeItems(spQuery))))

                function spSetMode(m) {
                    spMode = m; spQuery = ""; spHoverLabel = ""; spSel = 0; armed = ""; clipMenu = false;
                    spInput.text = ""; appsInput.text = ""; clipInput.text = ""; emojiInput.text = "";
                    if (m === "clip") root.clipRefresh();
                    if (m === "emoji") emCat = root.emojiRecent.length > 0 ? 0 : 1;
                    spFocusTimer.restart();
                }
                function spEscape() {
                    if (clipMenu) clipMenu = false;
                    else if (spQuery !== "") { spInput.text = ""; appsInput.text = ""; clipInput.text = ""; emojiInput.text = ""; spQuery = ""; }
                    else if (spMode !== "home") spSetMode("home");
                    else pop = "";
                }
                function spMove(d) {
                    var n = spResults.length;
                    if (n > 0) spSel = (Math.min(spSel, n - 1) + d + n) % n;
                }
                function spActivate(i) {
                    var it = spResults[i];
                    if (!it) return;
                    if (it.confirm === true && armed !== it.title) { armed = it.title; return; }
                    pop = "";
                    if (it.run) it.run();
                }
                function spEnter() {
                    if (spMode === "apps") {
                        var r = root.searchApps(spQuery);
                        if (r.length > 0) { pop = ""; root.launchApp(r[0]); }
                    } else if (spMode === "emoji") {
                        var em = spResults[Math.min(spSel, spResults.length - 1)];
                        if (em) { pop = ""; root.emojiPick(em); }
                    } else spActivate(Math.min(spSel, spResults.length - 1));
                }
                function spKey(ev) {
                    var k = ev.key, n = spResults.length;
                    if (k === Qt.Key_Escape) { spEscape(); ev.accepted = true; }
                    else if (spMode === "emoji" && (k === Qt.Key_Left || k === Qt.Key_Right || k === Qt.Key_Up || k === Qt.Key_Down)) {
                        var d = k === Qt.Key_Left ? -1 : (k === Qt.Key_Right ? 1 : (k === Qt.Key_Up ? -emCols : emCols));
                        if (n > 0) spSel = Math.max(0, Math.min(n - 1, Math.min(spSel, n - 1) + d));
                        ev.accepted = true;
                    }
                    else if (spMode === "emoji" && (k === Qt.Key_Tab || k === Qt.Key_Backtab)) {
                        if (spQuery.trim() === "") { emCat = (emCat + (k === Qt.Key_Tab ? 1 : 9)) % 10; spSel = 0; }
                        ev.accepted = true;
                    }
                    else if (k === Qt.Key_Down) { spMove(1); ev.accepted = true; }
                    else if (k === Qt.Key_Up) { spMove(-1); ev.accepted = true; }
                    else if (spMode === "clip" && k === Qt.Key_Delete) {
                        if (n > 0) root.clipDelete(spResults[Math.min(spSel, n - 1)]);
                        ev.accepted = true;
                    }
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                        if (spMode === "clip" && (ev.modifiers & Qt.ShiftModifier) && n > 0) {
                            var it = spResults[Math.min(spSel, n - 1)];
                            pop = "";
                            root.clipPick(it, false);       // Shift+Return: copy only, don't paste
                        } else spEnter();
                        ev.accepted = true;
                    }
                }
                function spToggleSection(name) {
                    var o = {};
                    for (var k in spExpanded) o[k] = spExpanded[k];
                    o[name] = !o[name];
                    spExpanded = o;
                }
                // gutter for check marks when any entry of the open menu has one
                readonly property bool menuLead: {
                    for (var i = 0; i < menuModel.length; i++) if (menuModel[i].checked !== undefined || menuModel[i].glyph !== undefined) return true;
                    return false;
                }
                Connections {
                    target: root
                    function onActiveWinChanged() { if (ui.isMenu) ui.menuModel = root.menuModelFor(ui.pop); }
                }
                // bounding box of all glass that is on screen right now (popovers, notification popups) + a refraction margin
                readonly property rect glassRect: {
                    var items = [menuPop, cc, cal, wifiPop, btPop, trayPop, notifPop, toastArea, volPop, kbPop, levelOsd], x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9, any = false;
                    for (var i = 0; i < items.length; i++) {
                        var it = items[i];
                        if (!it.visible) continue;
                        any = true;
                        x0 = Math.min(x0, it.x); y0 = Math.min(y0, it.y); x1 = Math.max(x1, it.x + it.width); y1 = Math.max(y1, it.y + it.height);
                    }
                    return any ? Qt.rect(x0 - 64, y0 - 64, x1 - x0 + 128, y1 - y0 + 128) : Qt.rect(0, 0, 0, 0);
                }
                readonly property bool isMenu: ["apple", "app", "file", "edit", "view", "window", "help"].indexOf(pop) >= 0
                readonly property bool anyVisible: menuPop.visible || cc.visible || cal.visible || wifiPop.visible || btPop.visible || trayPop.visible || notifPop.visible || toastArea.visible || volPop.visible || kbPop.visible
                onAnyVisibleChanged: root.popCount += (anyVisible ? 1 : -1)
                onPopChanged: {
                    if (pop !== "" && pop !== "spot") toneT.restart();
                    if (pop === "spot" && ui.toastScreen) root.measureTone(win.modelData.x + ui.width / 2 - 320, win.modelData.y + ui.height * 0.4 - 30, 640, 60);
                    armed = "";
                    wifiPrompt = "";
                    spHoverLabel = "";
                    if (pop !== "cc") ccEdit = false;
                    if (pop !== "cc") ccPage = "";
                    root.notifOpen = (pop === "notif");
                    if (root.notifOpen) root.notifUnread = 0;
                    if (pop === "wifi") { root.wifiError = ""; root.scanWifi(); root.refreshConnections(); }
                    if (pop === "bt") { root.btError = ""; root.scanBt(); root.refreshBt(); }
                    if (pop === "spot") {
                        spMode = "home"; spQuery = ""; spSel = 0; spExpanded = ({}); clipMenu = false;
                        spInput.text = ""; appsInput.text = ""; clipInput.text = ""; emojiInput.text = "";
                        spFocusTimer.restart();
                    }
                }
                Connections {
                    target: root
                    function onSpotRequestChanged() {
                        var fm = Hyprland.focusedMonitor;
                        if (!(!fm || fm.name === win.modelData.name || Quickshell.screens.length === 1)) return;
                        var want = root.spotWant;
                        if (ui.pop === "spot") {
                            if (want === "home" || want === ui.spMode) ui.pop = "";    // same key again closes it
                            else ui.spSetMode(want);
                        } else {
                            ui.spReqCalm = (want === "clip" || want === "emoji");
                            ui.openPop("spot", 0);
                            if (want !== "home") ui.spSetMode(want);
                        }
                    }
                }

                Connections {
                    target: root
                    function onNotifPopRequest(open) {
                        if (!ui.toastScreen) return;
                        if (open) ui.openPop("notif", bellBtn.visible ? bellBtn.mapToItem(ui, 0, 0).x : ui.width - 60); else if (ui.pop === "notif") ui.pop = "";
                    }
                }
                function openPop(name, x) {
                    if (pop === name) { pop = ""; return; }
                    if (name === "spot") { spCalm = spReqCalm; spReqCalm = false; }
                    menuX = x;
                    if (["apple", "app", "file", "edit", "view", "window", "help"].indexOf(name) >= 0) root.refreshActive();
                    if (["apple", "app", "file", "edit", "view", "window", "help"].indexOf(name) >= 0) menuModel = root.menuModelFor(name);
                    if (name === "cal") { var d = new Date(); calYear = d.getFullYear(); calMonth = d.getMonth(); }
                    pop = name;
                }
                function hoverPop(name, x) {
                    if (!isMenu || name === pop) return;
                    menuX = x;
                    menuModel = root.menuModelFor(name);
                    pop = name;
                }
                function calCells() {
                    var first = new Date(calYear, calMonth, 1);
                    var off = (first.getDay() - (root.weekStartsMonday ? 1 : 0) + 7) % 7;
                    var today = new Date(), out = [];
                    for (var i = 0; i < 42; i++) {
                        var d = new Date(calYear, calMonth, 1 - off + i);
                        out.push({ n: d.getDate(), cur: d.getMonth() === calMonth,
                                   today: d.getFullYear() === today.getFullYear() && d.getMonth() === today.getMonth() && d.getDate() === today.getDate() });
                    }
                    return out;
                }
                function shiftMonth(delta) {
                    var d = new Date(calYear, calMonth + delta, 1);
                    calYear = d.getFullYear(); calMonth = d.getMonth();
                }
                readonly property var calData: { clock.date; return calCells(); }

                // ── Liquid Glass backdrop: wallpaper + live windows behind the popovers, in screen coordinates ──
                // The backdrop (wallpaper + one capture per window) used to be built from scratch every time a popover opened,
                // which is the "wallpaper first, windows a moment later" delay. It now stays alive, so a popover opens on
                // ready-made, current window pixels.
                Loader {
                    id: glassBackdrop
                    active: root.liquidActive
                    sourceComponent: backdropComp
                    onLoaded: item.region = Qt.binding(function () { return ui.glassRect; })
                }
                // ── Layered glass, cheaply: one snapshot of the WHOLE screen (wallpaper, widgets, every window and layer) ──
                // taken while the pointer is on the bar (before a menu opens, so the menu isn't in it). Menus and popovers
                // refract that real picture of what's behind them. Falls back to the live backdrop when there's no fresh one
                // (e.g. a popover opened from the keyboard).
                ScreencopyView {
                    id: screenSnap
                    x: 0; y: 0
                    width: win.modelData.width; height: win.modelData.height
                    opacity: 0                      // only ever captured by the glass, never drawn itself
                    captureSource: root.liquidActive && !root.captureQuiet && !glassBackdrop.item ? win.modelData : null     // fallback only
                    live: false
                    paintCursor: false
                    property real takenAt: 0
                    function grab() { if (captureSource && typeof captureFrame === "function") { captureFrame(); takenAt = Date.now(); } }
                }
                property bool snapFresh: false
                // a moment after a popover starts opening (its rect is known), measure what's behind it
                Timer {
                    id: toneT; interval: 20
                    onTriggered: {
                        var r = ui.glassRect;
                        if (r.width <= 0) return;
                        root.measureTone(win.modelData.x + r.x + 64, win.modelData.y + r.y + 64, r.width - 128, r.height - 128);
                    }
                }
                // the bar changed size: the old whole-screen snapshot shows the windows where they WERE, so drop it, take a new one if
                // the pointer is on the bar, and re-measure what is behind the open panel
                Connections {
                    target: root
                    function onBarRelayout() {
                        screenSnap.takenAt = 0;
                        ui.snapFresh = false;
                        if (ui.pop !== "" && ui.pop !== "spot") toneT.restart();
                        else if (barHover.hovered && ui.pop === "") screenSnap.grab();
                    }
                }
                // The live backdrop (wallpaper + desktop widgets + live window captures) is always the source, so a window dragged
                // under an open menu keeps moving. The one-shot screen snapshot is only a fallback while the backdrop is not up.
                readonly property Item glassSrc: glassBackdrop.item ? glassBackdrop.item : ((snapFresh && screenSnap.hasContent) ? screenSnap : null)
                HoverHandler {
                    id: barHover
                    onHoveredChanged: if (hovered && ui.pop === "") screenSnap.grab()
                }
                // refresh while the pointer rests on the bar with nothing open; a snapshot is "fresh" for 3 s
                Timer { interval: 600; repeat: true; running: barHover.hovered && ui.pop === ""; onTriggered: screenSnap.grab() }
                Timer { interval: 250; repeat: true; running: true; onTriggered: ui.snapFresh = (Date.now() - screenSnap.takenAt) < 3000 || (ui.pop !== "" && ui.snapFresh) }

                // keeps the (otherwise unseen) backdrop rendering so its window captures stay valid; draws one 1%-opaque pixel
                ShaderEffectSource {
                    sourceItem: glassBackdrop.item
                    hideSource: true
                    live: true
                    width: 1; height: 1
                    opacity: 0.01
                    sourceRect: Qt.rect(0, 0, 1, 1)
                }
                Component {
                    id: backdropComp
                    Item {
                        id: bd
                        // never drawn on screen: only captured by the glass (a ShaderEffectSource ignores its source's own
                        // opacity). Without this, window captures (e.g. Spotify's player) showed through the panel mid-animation.
                        opacity: 0
                        property bool hostShown: true      // false while the window hosting this backdrop is hidden (set by its Loader)
                        property rect region: Qt.rect(0, 0, 0, 0)      // the glass that is on screen right now (set by its Loader); windows behind it stay live while recording
                        x: 0; y: 0
                        width: win.modelData.width
                        height: win.modelData.height

                        Rectangle {
                            z: -3
                            anchors.fill: parent
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "#2f6bff" }
                                GradientStop { position: 0.5; color: "#b44cff" }
                                GradientStop { position: 1.0; color: "#ff8a3d" }
                            }
                        }
                        Image {
                            z: -2
                            anchors.fill: parent
                            visible: status === Image.Ready
                            source: root.fileUrl(root.wallpaperFor(win.modelData.name))
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: bd.width
                            smooth: true
                        }
                        // animated wallpaper: plays behind the glass (menus, bar, Spotlight, switcher) only while "Animated wallpaper in glass" is on
                        // (root.glassVideo is "" otherwise, and then no decoder exists at all)
                        LiveWall {
                            z: -2
                            anchors.fill: parent
                            video: root.glassVideo
                            live: true
                            paused: root.gaming || root.screenCovered[win.modelData.name] === true
                        }

                        // the desktop widgets (they sit on the desktop layer, below every window), drawn from the same
                        // content as the real ones, so the glass shows them under the live windows
                        Repeater {
                            model: (root.hub && root.hub.widgets && Quickshell.screens.length > 0 && win.modelData.name === Quickshell.screens[0].name)
                                   ? root.hub.widgets.model : null
                            delegate: Item {
                                id: mw
                                required property string wid
                                required property string wtype
                                required property string wsrc
                                required property string wstyle
                                required property string wsize
                                required property string wmode
                                required property real wx
                                required property real wy
                                z: -1
                                x: wx; y: wy
                                width: root.hub.widgets.dims(wsize)[0]
                                height: root.hub.widgets.dims(wsize)[1]
                                WidgetVisual {
                                    anchors.fill: parent
                                    host: root.hub.widgets
                                    wtype: mw.wtype; wstyle: mw.wstyle; wsize: mw.wsize; wmode: mw.wmode; wsrc: mw.wsrc
                                    sx: mw.x; sy: mw.y
                                    sname: win.modelData.name; sw: win.modelData.width; sh: win.modelData.height
                                }
                            }
                        }

                        ListModel { id: wm }
                        Repeater {
                            id: wrep
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
                                property alias cap: sv
                                x: wx; y: wy; width: ww; height: wh; z: wz
                                readonly property var tl: { if (!root.hub || gone) return null; var t = root.hub.tlTick; return root.hub.tlFor(addr); }
                                // behind the glass that is on screen right now (popover / panel + refraction margin)?
                                readonly property bool onGlass: bd.region.width > 0 && x < bd.region.x + bd.region.width && x + width > bd.region.x
                                                                && y < bd.region.y + bd.region.height && y + height > bd.region.y
                                ScreencopyView {
                                    id: sv
                                    anchors.fill: parent
                                    captureSource: gw.tl
                                    // While a screen recording / screen share runs the window captures sit out (root.captureQuiet). `hush` follows it
                                    // with a random 0.6 s spread, so dozens of captures never start or stop in the same instant (that burst, with a
                                    // recorder pulling frames at the same time, is what the compositor choked on).
                                    property bool hush: root.captureQuiet
                                    Connections {
                                        target: root
                                        function onCaptureQuietChanged() { hushT.interval = 20 + Math.random() * 600; hushT.restart(); }
                                    }
                                    Timer { id: hushT; onTriggered: sv.hush = root.captureQuiet }
                                    // REAL-TIME: with glassRealtime every capture stays live all the time, so a popover opens on
                                    // frames that are already current and nothing is torn down / restarted when it opens (the restart
                                    // is what used to show the bare wallpaper first). Backdrops that live in a window which is
                                    // hidden right now (Spotlight, switcher, ...) are only kept warm with slow single captures.
                                    // While recording only the windows behind visible glass stay live (so the glass is real-time exactly where you see it,
                                    // e.g. a video behind the Control Center), every other window sits out.
                                    live: !gw.gone && !root.captureHeld && bd.hostShown && (!sv.hush || gw.onGlass) && (root.glassRealtime || ui.anyVisible || levelOsd.visible || spotWin.openish || swWin.visible || wpWin.visible)
                                    onCaptureSourceChanged: {
                                        // a brand-new capture grabs its first frame immediately instead of waiting for the timer
                                        // (a short delay: asking before the capture context exists only logged "no recording context is ready")
                                        if (captureSource !== null && !live && !sv.hush && !root.captureHeld) firstShot.restart();
                                    }
                                    Timer {
                                        id: firstShot
                                        interval: 90
                                        onTriggered: { if (sv.captureSource !== null && !sv.live && typeof sv.captureFrame === "function") sv.captureFrame(); }
                                    }
                                    // single captures: hidden backdrops stay warm once a second (their window goes live the moment it opens);
                                    // while recording only a backdrop that is actually on screen refreshes, slowly
                                    Timer {
                                        interval: sv.hush ? 1500 : (bd.hostShown ? 250 : 1000); repeat: true
                                        running: !root.captureHeld && !sv.live && sv.captureSource !== null
                                                 && (!sv.hush || (bd.hostShown && (ui.anyVisible || spotWin.openish || swWin.visible || wpWin.visible)))
                                        onTriggered: { if (typeof sv.captureFrame === "function") sv.captureFrame(); }
                                    }
                                }
                            }
                        }

                        // take a brand-new frame of every window (after the bar changed size and the windows moved / resized)
                        function recapture() {
                            for (var q = 0; q < wrep.count; q++) {
                                var it = wrep.itemAt(q);
                                if (it && it.cap && it.cap.captureSource !== null && typeof it.cap.captureFrame === "function") it.cap.captureFrame();
                            }
                        }
                        Connections {
                            target: root
                            function onBarRelayout() { bd.sync(); bd.recapture(); }
                        }
                        function sync() {
                            var mon = null, i;
                            for (i = 0; i < root.monData.length; i++)
                                if (root.monData[i].name === win.modelData.name) mon = root.monData[i];
                            if (!mon) return;
                            var ws = [mon.activeWorkspace ? mon.activeWorkspace.id : -999];
                            if (mon.specialWorkspace && mon.specialWorkspace.id !== 0) ws.push(mon.specialWorkspace.id);
                            var zoneBottom = bd.height;
                            var want = {};
                            var cs = root.glassClients;
                            for (var c = 0; c < cs.length; c++) {
                                var cl = cs[c];
                                if (!cl.mapped || cl.hidden || cl.monitor !== mon.id || ws.indexOf(cl.workspace.id) < 0) continue;
                                var x = cl.at[0] - mon.x, y = cl.at[1] - mon.y, w = cl.size[0], h = cl.size[1];
                                if (x + w <= 0 || x >= bd.width || y + h <= 0 || y >= zoneBottom) continue;
                                var z = cl.floating ? 100 - Math.min(cl.focusHistoryID, 90) : 0;
                                want[cl.address] = { addr: cl.address, wx: x, wy: y, ww: w, wh: h, wz: z, gone: false };
                            }
                            for (var j = wm.count - 1; j >= 0; j--) {
                                var a = wm.get(j).addr;
                                if (want[a] === undefined) { if (!wm.get(j).gone) { wm.setProperty(j, "gone", true); sweep.restart(); } }
                                else { wm.set(j, want[a]); delete want[a]; }
                            }
                            for (var k in want) wm.append(want[k]);
                        }
                        // a closed window first lets go of its capture (gone → captureSource null), the item itself is removed a moment later
                        Timer {
                            id: sweep
                            interval: 600
                            onTriggered: { for (var q = wm.count - 1; q >= 0; q--) if (wm.get(q).gone) wm.remove(q); }
                        }
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
                    x: 0; y: 0
                    width: ui.width
                    height: (ui.pop !== "" && ui.pop !== "spot") ? ui.height : root.barH
                }

                // Liquid Glass menu bar strip: the bar itself refracts the live backdrop (wallpaper + windows), like the popovers.
                // Settings → Menu Bar → "Liquid Glass bar". Sits under every bar item.
                LGlass {
                    id: barGlassStrip
                    visible: root.barGlass && root.liquidActive
                    x: 0; y: 0
                    width: ui.width
                    height: root.barH
                    backdrop: ui.glassSrc
                    shaderUrl: root.glassShaderUrl
                    liquid: root.liquidActive
                    dark: !root.barTextDark
                    bx: 0; by: 0
                    cornerR: 0
                    tint: root.glassOpacity * 0.6
                    thickness: 16
                    strength: 0.9 * root.glassLiquid
                    rim: root.glassRim
                    grain: root.glassGrain
                    blur: root.glassBlur
                    debug: root.glassDebug
                    onShaderError: root.glassState = "failed"
                }

                // click-away layer (under the popovers and the bar)
                MouseArea {
                    anchors.fill: parent
                    z: 5
                    visible: ui.pop !== "" && ui.pop !== "spot"
                    acceptedButtons: Qt.AllButtons
                    onPressed: ui.pop = ""
                }

                // Hardware-key feedback (volume / brightness): a Liquid Glass capsule at the top right, a little below the
                // menu bar like macOS Tahoe. It refracts the live backdrop through the same shader as the popovers.
                Item {
                    id: levelOsd
                    z: 1000
                    width: 256; height: 67
                    x: ui.width - width - 22
                    y: root.barH + 14
                    visible: ui.toastScreen && opacity > 0
                    opacity: root.osdVisible ? 1 : 0
                    scale: root.osdVisible ? 1 : 0.94
                    transformOrigin: Item.TopRight
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    LGlass {
                        anchors.fill: parent
                        backdrop: ui.glassSrc
                        shaderUrl: root.glassShaderUrl
                        liquid: root.liquidActive
                        dark: root.effDark
                        bx: levelOsd.x; by: levelOsd.y
                        cornerR: height / 2
                        tint: root.glassOpacity
                        thickness: 22
                        strength: 0.8 * root.glassLiquid
                        rim: root.glassRim
                        grain: root.glassGrain
                        blur: root.glassBlur
                        debug: root.glassDebug
                        onShaderError: root.glassState = "failed"
                        rimTint: 1
                        ringW: 1.4
                        shadowAmt: 0        // no outer drop shadow
                        flatInner: 1        // no darker inner edge shading
                    }
                    MenuBorder {
                        z: 2
                        anchors.fill: parent
                        cornerR: height / 2
                        dark: root.effDark
                        tint: root.menuBorderColor
                        outline: false      // no dark hairline around the capsule
                    }
                    Glyph {
                        x: 20; anchors.verticalCenter: parent.verticalCenter
                        width: 24; height: 24
                        kind: root.osdKind === "brightness" ? "sun" : "speaker"
                        level: root.osdKind === "brightness" ? 3 : (root.osdValue < 0.34 ? 1 : (root.osdValue < 0.67 ? 2 : 3))
                        color: "white"
                    }
                    // segmented level bar: bright segments are filled, the rest are dim
                    Row {
                        id: osdBar
                        x: 62; anchors.verticalCenter: parent.verticalCenter
                        readonly property int n: 22
                        readonly property real segW: (levelOsd.width - 62 - 24 - (n - 1) * 3) / n
                        spacing: 3
                        Repeater {
                            model: osdBar.n
                            Rectangle {
                                required property int index
                                width: osdBar.segW; height: 4; radius: 2
                                color: "white"
                                // partial last segment fades proportionally
                                opacity: Math.max(0.28, Math.min(1, root.osdValue * osdBar.n - index) * 0.95)
                                Behavior on opacity { NumberAnimation { duration: 90 } }
                            }
                        }
                    }
                }
                // ═════════ the bar itself ═════════
                Rectangle {
                    id: barBg
                    visible: root.barEnabled
                    z: 20
                    x: 0; y: 0
                    width: ui.width
                    height: root.barH
                    color: "transparent"      // Tahoe: the bar is fully clear, no fill and no border on any side
                    MouseArea { anchors.fill: parent; onClicked: ui.pop = "" }

                    // ── left: Apple menu + app menus ──
                    Row {
                        id: leftRow
                        x: 8
                        height: 28
                        anchors.verticalCenter: parent.verticalCenter
                        transformOrigin: Item.Left
                        scale: root.barWidgetScale
                        Repeater {
                            model: root.menuTitles.filter(function (item) {
                                return item.id === "apple" ? root.barWidgetEnabled("appleMenu") : root.barWidgetEnabled("appMenus");
                            })
                            delegate: Item {
                                id: mt
                                required property var modelData
                                readonly property bool open: ui.pop === modelData.id
                                readonly property bool activeApp: modelData.id === "app"
                                width: modelData.id === "apple" ? 30 : tl.implicitWidth + 20
                                height: 28
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width - 2
                                    height: parent.height - 6
                                    radius: 6
                                    color: mt.open ? bpal.hover : "transparent"
                                }
                                Glyph {
                                    visible: mt.modelData.id === "apple" && root.barLogoMode === "arch"
                                    anchors.centerIn: parent
                                    width: 15; height: 15
                                    kind: "arch"
                                    color: bpal.fg
                                }
                                Image {
                                    visible: mt.modelData.id === "apple" && root.barLogoMode === "apple"
                                    anchors.centerIn: parent
                                    width: 15; height: 15
                                    source: !root.barTextDark ? Qt.resolvedUrl("apple-logo-white.svg") : Qt.resolvedUrl("apple-logo-black.svg")
                                    sourceSize: Qt.size(128, 160)
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                }
                                Image {
                                    id: customBarLogo
                                    visible: mt.modelData.id === "apple" && root.barLogoMode === "custom" && root.barCustomLogoUrl !== ""
                                    anchors.centerIn: parent
                                    width: 17; height: 17
                                    source: root.barCustomLogoUrl
                                    sourceSize: Qt.size(64, 64)
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                }
                                Glyph {
                                    visible: mt.modelData.id === "apple" && root.barLogoMode === "custom"
                                             && (root.barCustomLogoUrl === "" || customBarLogo.status === Image.Error)
                                    anchors.centerIn: parent
                                    width: 15; height: 15
                                    kind: "arch"
                                    color: bpal.fg
                                }
                                Text {
                                    id: tl
                                    visible: mt.modelData.id !== "apple"
                                    anchors.centerIn: parent
                                    text: I18n.tr(mt.modelData.label)
                                    color: bpal.fg
                                    font.family: mt.activeApp ? Fonts.forWeight(font.weight, root.boldFontFamily)
                                                              : Fonts.forWeight(font.weight, "Open Runde")
                                    font.pixelSize: 14
                                    font.weight: mt.activeApp ? Font.DemiBold : Font.Normal
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: ui.openPop(mt.modelData.id, mt.mapToItem(ui, 0, 0).x)
                                    onEntered: ui.hoverPop(mt.modelData.id, mt.mapToItem(ui, 0, 0).x)
                                }
                            }
                        }
                    }

                    // ── centre: workspaces (minimal, text only) ──
                    Row {
                        id: wsRow
                        visible: root.barWidgetEnabled("workspaces")
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        height: 28
                        transformOrigin: Item.Center
                        scale: root.barWidgetScale
                        spacing: 0
                        readonly property var mon: Hyprland.monitorFor(perScreen.modelData)
                        readonly property int activeId: mon && mon.activeWorkspace ? mon.activeWorkspace.id : (Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1)
                        Repeater {
                            model: root.wsIds
                            delegate: Item {
                                id: wsi
                                required property var modelData
                                readonly property bool cur: wsRow.activeId === modelData
                                readonly property bool busy: root.wsOccupied(modelData)
                                width: 22; height: 28
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width - 2
                                    height: parent.height - 6
                                    radius: 6
                                    color: wsi.cur ? bpal.hover : "transparent"
                                    opacity: wsi.cur || wsMa.containsMouse ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 140 } }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: "" + wsi.modelData
                                    color: wsi.cur ? bpal.fg : (wsi.busy ? bpal.fg2 : bpal.fg3)
                                    font.family: root.fontForWeight(font.weight, bpal.fam)
                                    font.pixelSize: 13
                                    font.weight: wsi.cur ? Font.DemiBold : Font.Normal
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                }
                                MouseArea {
                                    id: wsMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: { ui.pop = ""; root.hlWorkspace("" + wsi.modelData); }
                                }
                            }
                        }
                        WheelHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: event => root.hlWorkspace(event.angleDelta.y > 0 ? "e-1" : "e+1")
                        }
                    }

                    // ── right: tray, status items, control center, clock ──
                    Row {
                        id: rightRow
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        height: 28
                        transformOrigin: Item.Right
                        scale: root.barWidgetScale
                        spacing: 0

                        // tray
                        Repeater {
                            model: root.showTray ? SystemTray.items : null
                            delegate: Item {
                                id: tray
                                required property var modelData
                                width: 26; height: 28
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width - 2
                                    height: parent.height - 6
                                    radius: 6
                                    color: (ui.pop === "tray" && ui.trayItem === tray.modelData) ? bpal.hover : "transparent"
                                }
                                Image {
                                    anchors.centerIn: parent
                                    width: 16; height: 16
                                    source: tray.modelData.icon
                                    sourceSize: Qt.size(32, 32)
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                    onClicked: mouse => {
                                        var p = tray.mapToItem(ui, 0, 0);
                                        if (mouse.button === Qt.RightButton || (mouse.button === Qt.LeftButton && tray.modelData.onlyMenu))
                                            ui.openTray(tray.modelData, p.x);
                                        else if (mouse.button === Qt.MiddleButton)
                                            tray.modelData.secondaryActivate();
                                        else
                                            tray.modelData.activate();
                                    }
                                }
                            }
                        }

                        // Bluetooth has its own optional widget; it remains visible when the radio is off.
                        Item {
                            id: btBtn
                            visible: root.barWidgetEnabled("bluetooth")
                            width: root.barWidgetEnabled("bluetooth") ? 26 : 0; height: 28
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width - 2; height: parent.height - 6; radius: 6
                                color: ui.pop === "bt" ? bpal.hover : "transparent"
                            }
                            Glyph { anchors.centerIn: parent; width: 15; height: 15; kind: "bluetooth"; color: root.btOn && root.btConnected > 0 ? bpal.fg : bpal.fg2 }
                            MouseArea { anchors.fill: parent; onClicked: ui.openPop("bt", btBtn.mapToItem(ui, 0, 0).x) }
                        }
                        // volume (opens a popover with just the volume slider)
                        Item {
                            id: volBtn
                            visible: root.barWidgetEnabled("volume")
                            width: root.barWidgetEnabled("volume") ? 28 : 0; height: 28
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width - 2; height: parent.height - 6; radius: 6
                                color: ui.pop === "vol" ? bpal.hover : "transparent"
                            }
                            Glyph { anchors.centerIn: parent; width: 16; height: 16; kind: "speaker"; level: root.volLevel; color: bpal.fg }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: ui.openPop("vol", volBtn.mapToItem(ui, 0, 0).x + volBtn.width / 2)
                                onWheel: wheel => root.setVolume(root.volume + (wheel.angleDelta.y > 0 ? 0.03 : -0.03))
                            }
                        }
                        // keyboard layout: click = next layout, right-click = pick from a list, scroll = cycle
                        Item {
                            id: kbBtn
                            visible: root.barWidgetEnabled("keyboard") && root.kbLayouts.length !== 1
                            width: root.barWidgetEnabled("keyboard") && root.kbLayouts.length !== 1 ? 34 : 0; height: 28
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width - 2; height: parent.height - 6; radius: 6
                                color: (ui.pop === "kb" || kbMouse.containsMouse) ? bpal.hover : "transparent"
                            }
                            Text {
                                anchors.centerIn: parent
                                text: root.keyboardLayout
                                color: bpal.fg
                                font.family: root.fontForWeight(font.weight, bpal.fam); font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                            MouseArea {
                                id: kbMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton) ui.openPop("kb", kbBtn.mapToItem(ui, 0, 0).x + kbBtn.width / 2);
                                    else root.cycleKeyboardLayout(1);
                                }
                                onWheel: wheel => root.cycleKeyboardLayout(wheel.angleDelta.y > 0 ? -1 : 1)
                            }
                        }
                        // battery
                        Item {
                            visible: root.hasBattery
                            width: root.hasBattery ? batRow.width + 14 : 0; height: 28
                            Row {
                                id: batRow
                                anchors.centerIn: parent
                                spacing: 5
                                Text {
                                    visible: root.showBatteryPercent
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.batPct + "%"
                                    color: bpal.fg
                                    font.family: root.fontForWeight(font.weight, bpal.fam); font.pixelSize: 12
                                }
                                Item {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 25; height: 12
                                    Rectangle {
                                        id: bbody
                                        width: 22; height: 12; radius: 3.5
                                        color: "transparent"
                                        border.width: 1
                                        border.color: bpal.fg2
                                        Rectangle {
                                            x: 1.5; y: 1.5
                                            width: Math.max(2, (parent.width - 3) * Math.min(1, root.batPct / 100))
                                            height: parent.height - 3
                                            radius: 2
                                            color: root.charging ? "#30D158" : (root.batPct <= 15 ? "#FF453A" : bpal.fg)
                                        }
                                    }
                                    Rectangle { x: 23; y: 4; width: 2; height: 4; radius: 1; color: bpal.fg2 }
                                    Glyph {
                                        visible: root.charging
                                        anchors.centerIn: bbody
                                        width: 9; height: 9
                                        kind: "bolt"
                                        color: bpal.dark ? "#111" : "#fff"
                                    }
                                }
                            }
                            MouseArea { anchors.fill: parent; onClicked: ui.openPop("cc", 0) }
                        }
                        // notification system (bell)
                        Item {
                            id: bellBtn
                            visible: root.barWidgetEnabled("notifications")
                            width: root.barWidgetEnabled("notifications") ? 28 : 0; height: 28
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width - 2; height: parent.height - 6; radius: 6
                                color: ui.pop === "notif" ? bpal.hover : "transparent"
                            }
                            Glyph { anchors.centerIn: parent; width: 16; height: 16; kind: "bell"; color: root.notifDnd ? bpal.fg2 : bpal.fg }
                            Rectangle {
                                visible: root.notifUnread > 0 && !root.notifDnd
                                x: parent.width / 2 + 2; y: parent.height / 2 - 8
                                width: 7; height: 7; radius: 3.5
                                color: "#FF453A"
                            }
                            MouseArea { anchors.fill: parent; onClicked: ui.openPop("notif", bellBtn.mapToItem(ui, 0, 0).x) }
                        }
                        // wifi
                        Item {
                            id: wifiBtn
                            visible: root.barWidgetEnabled("wifi")
                            width: root.barWidgetEnabled("wifi") ? 28 : 0; height: 28
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width - 2; height: parent.height - 6; radius: 6
                                color: ui.pop === "wifi" ? bpal.hover : "transparent"
                            }
                            Glyph { anchors.centerIn: parent; width: 16; height: 16; kind: root.showEthernet ? "ethernet" : "wifi"; level: root.wifiOn ? (root.wifiLevel || 1) : 3; flag: !root.wifiOn && !root.showEthernet; color: (root.wifiOn || root.showEthernet) ? bpal.fg : bpal.fg2 }
                            MouseArea { anchors.fill: parent; onClicked: ui.openPop("wifi", wifiBtn.mapToItem(ui, 0, 0).x) }
                        }
                        // search
                        Item {
                            visible: root.showSearch
                            width: root.showSearch ? 28 : 0; height: 28
                            Glyph { anchors.centerIn: parent; width: 15; height: 15; kind: "search"; color: bpal.fg }
                            MouseArea { anchors.fill: parent; onClicked: { if (root.launcher !== "") { ui.pop = ""; root.search(); } else ui.openPop("spot", 0); } }
                        }
                        // control center
                        Item {
                            id: ccBtn
                            visible: root.ccEnabled && root.barWidgetEnabled("controlCenter")
                            // the widget grows to the right while a privacy dot is showing, so the dot sits beside the icon
                            readonly property bool dotsOn: root.privacyAny && root.barWidgetEnabled("privacy")
                            width: (root.ccEnabled && root.barWidgetEnabled("controlCenter")) ? 30 + (dotsOn ? ccDots.width + 2 : 0) : 0; height: 28
                            Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width - 2; height: parent.height - 6; radius: 6
                                color: ui.pop === "cc" ? bpal.hover : "transparent"
                            }
                            Glyph { x: 7; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; kind: "cc"; color: bpal.fg }
                            // privacy dots like macOS: orange = microphone, green = camera, purple = screen sharing / recording
                            Row {
                                id: ccDots
                                visible: ccBtn.dotsOn
                                x: 27
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3
                                Repeater {
                                    model: root.privacyDots
                                    delegate: Rectangle {
                                        required property string modelData
                                        width: 7; height: 7; radius: 3.5
                                        color: modelData
                                        border.width: 0.5
                                        border.color: Qt.rgba(0, 0, 0, 0.35)
                                    }
                                }
                            }
                            MouseArea { anchors.fill: parent; onClicked: ui.openPop("cc", 0) }
                        }
                        // clock
                        Item {
                            id: clockBtn
                            visible: root.barWidgetEnabled("clock")
                            width: root.barWidgetEnabled("clock") ? clockText.implicitWidth + 16 : 0
                            height: 28
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width - 2; height: parent.height - 6; radius: 6
                                color: ui.pop === "cal" ? bpal.hover : "transparent"
                            }
                            Text {
                                id: clockText
                                anchors.centerIn: parent
                                text: root.clockText
                                color: bpal.fg
                                font.family: Fonts.forWeight(font.weight, root.boldFontFamily)
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                font.letterSpacing: 0.1
                                font.hintingPreference: Font.PreferNoHinting    // hinting snapped the x-height down and made the text look flat
                                font.kerning: true
                                renderType: Text.QtRendering
                                verticalAlignment: Text.AlignVCenter
                                anchors.verticalCenterOffset: 0.5
                            }
                            MouseArea { anchors.fill: parent; onClicked: ui.openPop("cal", 0) }
                        }
                    }
                }

                Item {
                    id: volPop
                    z: 10
                    // same morph as the Wi-Fi popover, growing out of the speaker icon (menuX is the icon's centre here)
    readonly property real ps: root.barPopupScale
                    readonly property real fullW: 330
                    readonly property real fullH: Math.min(volCol.height + 28, ui.height - root.barH - 40)
                    // the rectangle it grows from (the bar icon, in screen px) and the one it grows into
                    readonly property real srcW: 26
                    readonly property real srcH: 22
                    readonly property real srcX: ui.menuX - 13
                    readonly property real srcY: Math.max(0, (root.barH - srcH) / 2)
                    readonly property real dstX: Math.max(6, Math.min(ui.width - fullW * ps - 8, ui.menuX - fullW * ps / 2))
                    readonly property real dstY: root.barH + 6

                    readonly property bool opening: ui.pop === "vol"
                    property real openT: opening ? 1 : 0
                    Behavior on openT {
                        NumberAnimation {
                            duration: volPop.opening ? 520 : 220
                            easing.type: volPop.opening ? Easing.OutBack : Easing.InOutCubic
                            easing.overshoot: 0.7
                        }
                    }
                    readonly property real t: Math.max(0, Math.min(1, openT))
                    readonly property real contentT: Math.max(0, Math.min(1, (openT - 0.28) / 0.55))

                    width: (srcW + (fullW * ps - srcW) * openT) / ps
                    height: (srcH + (fullH * ps - srcH) * openT) / ps
                    x: srcX + (dstX - srcX) * openT
                    y: srcY + (dstY - srcY) * openT
                    opacity: Math.min(1, t * 4)
                    visible: openT > 0.002
                    scale: ps
                    transformOrigin: Item.TopLeft

                    // morph blur: only exists while the animation runs, so the open panel is drawn directly (crisp text)
                    readonly property real blurAmt: Math.pow(1 - t, 1.3)
                    readonly property bool morphing: openT > 0.002 && Math.abs(openT - 1) > 0.002
                    layer.enabled: morphing
                    layer.smooth: true
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blurMax: 48
                        blur: volPop.blurAmt * 0.9
                        autoPaddingEnabled: true
                    }

                    PopGlassCtx { id: volPopGlass; pop: volPop; frame: ui; source: ui.glassSrc; fullW: volPop.fullW; fullH: volPop.fullH }
                    GGlass { anchors.fill: parent; gx: volPopGlass.ctx; cornerR: Math.min(26, 8 + 18 * volPop.t); thickness: 22; shadowAmt: 0; flatInner: 1 }
                    MenuBorder { z: 2; anchors.fill: parent; cornerR: Math.min(26, 8 + 18 * volPop.t); dark: volPopGlass.ctx.dark; tint: volPopGlass.ctx.borderTint; amount: 1 }   // same border as the top-bar menus
                    MouseArea { anchors.fill: parent }      // clicks inside don't close the popover

                    Item {
                        anchors.fill: parent
                        anchors.margins: 1
                        clip: true
                    Item {
                        id: volBody
                        x: -1; y: -1 + 10 * (1 - volPop.contentT)
                        width: volPop.fullW; height: volPop.fullH
                        opacity: volPop.contentT
                    Flickable {
                        id: volFlick
                        x: 0; y: 14
                        width: parent.width
                        height: parent.height - 28
                        contentWidth: width
                        contentHeight: volCol.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: contentHeight > height
                        Column {
                            id: volCol
                            x: 14
                            width: volFlick.width - 28
                            spacing: 3

                            Text { x: 4; text: I18n.tr("Output"); color: pal.fg2; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 12; font.weight: Font.DemiBold; bottomPadding: 3 }
                            Item {
                                width: parent.width; height: 32
                                CCSlider {
                                    t: pal; gx: volPopGlass.ctx
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    value: root.muted ? 0 : root.volume
                                    leftKind: "speaker"; leftLevel: root.volLevel
                                    rightKind: "speaker"; rightLevel: 3
                                    onMoved: v => root.setVolume(v)
                                }
                                MouseArea { width: 28; height: parent.height; onClicked: root.toggleMute() }     // the left speaker icon mutes
                            }
                            Repeater {
                                model: root.audioOutputs
                                delegate: AudioRow {
                                    required property var modelData
                                    t: pal
                                    readonly property var parts: root.audioSplit(modelData.description || modelData.name)
                                    title: parts[0]
                                    sub: parts[1]
                                    kind: root.audioKind(modelData, true)
                                    selected: root.sink !== null && root.sink !== undefined && root.sink.id === modelData.id
                                    onClicked: root.chooseAudio(modelData)
                                }
                            }
                            Text { visible: root.audioOutputs.length === 0; x: 4; text: I18n.tr("No output devices"); color: pal.fg2; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 12; topPadding: 4; bottomPadding: 4 }
                            Item { width: 1; height: 5 }
                            Text { x: 4; text: I18n.tr("Apps"); color: pal.fg2; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 12; font.weight: Font.DemiBold; bottomPadding: 2 }
                            Repeater {
                                model: root.appAudioKeys
                                delegate: Item {
                                    id: appRow
                                    required property string modelData
                                    readonly property var app: root.appByKey(modelData)
                                    // while dragging, the knob follows the pointer instead of waiting for the next volume update
                                    property bool dragging: false
                                    property real dragV: 0
                                    readonly property real vol: dragging ? dragV : (app ? app.volume : 0)
                                    Timer { id: dragEnd; interval: 500; onTriggered: appRow.dragging = false }
                                    visible: app !== null
                                    width: volCol.width - 28; height: app ? 54 : 0
                                    Text {
                                        x: 4; y: 0; width: parent.width - 8
                                        text: (appRow.app ? appRow.app.name : "") + "  ·  " + Math.round(appRow.vol * 100) + "%"
                                        color: pal.fg; elide: Text.ElideRight
                                        font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 12
                                    }
                                    CCSlider {
                                        t: pal; gx: volPopGlass.ctx; x: 0; y: 20; width: parent.width
                                        value: appRow.vol
                                        leftKind: "speaker"; leftLevel: appRow.vol < 0.34 ? 1 : (appRow.vol < 0.67 ? 2 : 3)
                                        rightKind: "speaker"; rightLevel: 3
                                        onMoved: v => {
                                            appRow.dragV = v; appRow.dragging = true; dragEnd.restart();
                                            root.setAppVolume(appRow.app, v);
                                        }
                                    }
                                }
                            }
                            Text { visible: root.appAudioKeys.length === 0; x: 4; text: I18n.tr("No apps are playing audio"); color: pal.fg2; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 11; topPadding: 2; bottomPadding: 4 }
                            Item { width: 1; height: 5 }
                            Rectangle { width: parent.width; height: 1; color: pal.sep }
                            Item { width: 1; height: 5 }
                            Item {
                                width: parent.width; height: 32
                                Text { x: 4; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("Input"); color: pal.fg2; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 12; font.weight: Font.DemiBold }
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 30; height: 30; radius: 15
                                    color: root.micMuted ? pal.btnOff : pal.accent
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Glyph { anchors.centerIn: parent; width: 16; height: 16; kind: "mic"; flag: root.micMuted; color: root.micMuted ? pal.fg : "white" }
                                    MouseArea { anchors.fill: parent; onClicked: root.toggleMicMute() }
                                }
                            }
                            Item {
                                width: parent.width; height: 32
                                CCSlider {
                                    t: pal; gx: volPopGlass.ctx
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    value: root.micMuted ? 0 : root.micVolume
                                    leftKind: "mic"; rightKind: "mic"
                                    onMoved: v => root.setMicVolume(v)
                                }
                            }
                            Repeater {
                                model: root.audioInputs
                                delegate: AudioRow {
                                    required property var modelData
                                    t: pal
                                    readonly property var parts: root.audioSplit(modelData.description || modelData.name)
                                    title: parts[0]
                                    sub: parts[1]
                                    kind: "mic"
                                    selected: root.micSource !== null && root.micSource !== undefined && root.micSource.id === modelData.id
                                    onClicked: root.chooseAudio(modelData)
                                }
                            }
                            Text { visible: root.audioInputs.length === 0; x: 4; text: I18n.tr("No input devices"); color: pal.fg2; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 12; topPadding: 4; bottomPadding: 4 }
                        }
                    }
                    }
                    }
                }

                // ═════════ keyboard layout popover (right-click the layout label) ═════════
                Item {
                    id: kbPop
                    z: 10
                    width: 250
                    height: kbCol.height + 16
                    x: Math.max(6, Math.min(ui.width - width * root.barPopupScale - 8, ui.menuX - width / 2))
                    y: root.barH + 6
                    opacity: ui.pop === "kb" ? 1 : 0
                    visible: opacity > 0
                    scale: root.barPopupScale * (ui.pop === "kb" ? 1 : 0.96)
                    transformOrigin: Item.Top
                    Behavior on opacity { NumberAnimation { duration: 110 } }
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    LGlass {
                        anchors.fill: parent
                        backdrop: ui.glassSrc
                        shaderUrl: root.glassShaderUrl
                        liquid: root.liquidActive
                        dark: root.effDark
                        bx: kbPop.x; by: kbPop.y
                        cornerR: 22
                        tint: root.glassOpacity
                        thickness: 22
                        strength: 0.55 * root.glassLiquid
                        rim: root.glassRim
                        grain: root.glassGrain
                        blur: 42
                        debug: root.glassDebug
                        onShaderError: root.glassState = "failed"
                        rimTint: 1
                        ringW: 1.4
                    }
                    MenuBorder {
                        z: 2
                        anchors.fill: parent
                        cornerR: 22
                        dark: root.effDark
                        tint: root.menuBorderColor
                    }
                    MouseArea { anchors.fill: parent }
                    Column {
                        id: kbCol
                        x: 8; y: 8
                        width: parent.width - 16
                        Repeater {
                            model: root.kbLayouts
                            delegate: Item {
                                id: kr
                                required property var modelData
                                required property int index
                                width: parent.width; height: 40
                                Rectangle { anchors.fill: parent; radius: 12; color: pal.hover; opacity: krMa.containsMouse ? 1 : 0 }
                                Text {
                                    x: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 84
                                    elide: Text.ElideRight
                                    text: kr.modelData.name
                                    color: pal.fg
                                    font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 13
                                    font.weight: kr.index === root.kbIndex ? Font.DemiBold : Font.Normal
                                }
                                Text {
                                    anchors.right: parent.right; anchors.rightMargin: 40
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: kr.modelData.code.toUpperCase()
                                    color: pal.fg2
                                    font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 11
                                }
                                Glyph {
                                    visible: kr.index === root.kbIndex
                                    anchors.right: parent.right; anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 16; height: 16
                                    kind: "check"; color: pal.fg
                                }
                                MouseArea { id: krMa; anchors.fill: parent; hoverEnabled: true; onClicked: { root.switchKeyboardLayout(kr.index); ui.pop = ""; } }
                            }
                        }
                    }
                }

                // ═════════ notification popups (top right, under the bar) ═════════
                Item {
                    id: toastMask
                    x: toastArea.x; y: toastArea.y
                    width: ui.toastsShown ? toastArea.width : 0
                    height: ui.toastsShown ? toastArea.height : 0
                }
                Item {
                    id: toastArea
                    z: 12
                    width: 364
                    x: ui.width - width - 10
                    // a menu / popover open where the notifications are: they slide down below it, and back up after
                    readonly property real popBottom: {
                        if (ui.pop === "" || ui.pop === "spot") return 0;
                        var items = [menuPop, cc, cal, wifiPop, trayPop, volPop, kbPop], b = 0;
                        for (var i = 0; i < items.length; i++) {
                            var it = items[i];
                            if (!it || !it.visible) continue;
                            if (it.x < x + width && it.x + it.width > x) b = Math.max(b, it.y + it.height);
                        }
                        return b;
                    }
                    y: popBottom > 0 ? popBottom + 12 : root.barH + 8
                    Behavior on y { NumberAnimation { duration: 770; easing.type: Easing.OutQuint } }
                    height: toastCol.height
                    visible: ui.toastsShown && root.notificationsEnabled
                    Column {
                        id: toastCol
                        width: parent.width
                        spacing: 10
                        // the rest of the stack glides to its new place instead of jumping
                        move: Transition { NumberAnimation { properties: "y"; duration: 770; easing.type: Easing.OutQuint } }
                        Repeater {
                            model: notifToasts
                            delegate: Item {
                                id: toast
                                required property int nid
                                required property string app
                                required property string summary
                                required property string body
                                required property string icon
                                required property int urgency
                                required property real time
                                required property int timeout
                                property bool shown: false
                                property bool leaving: false
                                readonly property int life: timeout > 0 ? timeout : (urgency === 2 ? 10000 : 6000)
                                // t: 0 = a small pill at the right edge (off to the side), 1 = the full card in place
                                property real t: (shown && !leaving) ? 1 : 0
                                Behavior on t { NumberAnimation { duration: 770; easing.type: toast.leaving ? Easing.OutCubic : Easing.OutQuint } }
                                readonly property real tc: Math.max(0, Math.min(1, t))
                                width: toastCol.width
                                // the slot grows with the card, so the stack below makes room smoothly
                                height: tbody.height * (0.35 + 0.65 * tc) + (toastCol.spacing * (tc - 1))
                                opacity: Math.min(1, tc * 2.2)
                                Component.onCompleted: shown = true
                                function dismiss() { if (leaving) return; leaving = true; goneTimer.restart(); }
                                // Notification Center opened: record this popup's spot and hand over instantly — the card in the
                                // panel starts exactly here and flies into its slot (one object, no duplicate)
                                property real mergeDy: 0
                                Timer { id: handOff; interval: 30; onTriggered: root.notifToastRemove(toast.nid) }
                                Connections {
                                    target: root
                                    function onNotifOpenChanged() {
                                        if (!root.notifOpen || toast.leaving || toast.tc < 0.5) return;
                                        var g = tslab.mapToItem(ui, 0, 0);
                                        // a NEW object, or nothing is notified and the cards never start their flight
                                        var m = {}, old = root.notifMergeFrom;
                                        for (var k in old) m[k] = old[k];
                                        m[toast.nid] = { x: g.x, y: g.y, w: tslab.width };
                                        root.notifMergeFrom = m;
                                        toast.leaving = true;
                                        toast.visible = false;
                                        handOff.restart();
                                    }
                                }
                                Timer { interval: 790; id: goneTimer; onTriggered: root.notifToastRemove(toast.nid) }
                                Timer {
                                    interval: toast.life
                                    running: toast.shown && !toast.leaving && !thov.hovered
                                    onTriggered: toast.dismiss()
                                }
                                HoverHandler { id: thov }

                                LGlass {
                                    id: tslab
                                    // pill → card: narrow and short at first, anchored to the right, sliding in from the right
                                    readonly property real slide: (1 - toast.tc) * 46
                                    width: toast.width * (0.42 + 0.58 * toast.tc)
                                    height: Math.max(36, toast.height)
                                    x: toast.width - width + slide
                                    backdrop: ui.glassSrc
                                    shaderUrl: root.glassShaderUrl
                                    liquid: root.liquidActive
                                    dark: root.effDark
                                    bx: toastArea.x + toast.x + tslab.x; by: toastArea.y + toast.y
                                    cornerR: Math.min(24 + (1 - toast.tc) * 40, height / 2)
                                    tint: root.glassOpacity
                                    thickness: 22
                                    strength: 0.7 * root.glassLiquid
                                    rim: root.glassRim
                                    grain: root.glassGrain
                                    blur: root.notifBlur
                                    debug: root.glassDebug
                                    onShaderError: root.glassState = "failed"
                                    rimTint: 1
                                    ringW: 0.9
                                    shadowAmt: 0.35
                                }
                                MenuBorder {
                                    z: 2
                                    anchors.fill: tslab
                                    cornerR: Math.min(24 + (1 - toast.tc) * 40, height / 2)
                                    dark: root.effDark
                                    tint: root.menuBorderColor
                                    amount: 0.5
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: { root.notifActivate(toast.nid); toast.dismiss(); }
                                }
                                // the slab reveals the content (clip), and inside it the content comes into focus. The blur sits on an
                                // inner layer with room to spread (auto padding), so it is soft all round instead of a cut-off smear,
                                // and it eases out gradually as the card settles.
                                Item {
                                    id: tcontent
                                    x: tslab.x; width: tslab.width; height: toast.height
                                    clip: toast.tc < 0.999
                                    opacity: Math.pow(toast.tc, 1.3)
                                Item {
                                    width: toast.width; height: toast.height
                                    x: tslab.width - width
                                    layer.enabled: toast.tc < 0.999
                                    layer.smooth: true
                                    layer.effect: MultiEffect { blurEnabled: true; blurMax: 56; blur: Math.pow(1 - toast.tc, 0.8); autoPaddingEnabled: true }
                                NotifBody {
                                    id: tbody
                                    t: pal
                                    width: toast.width
                                    app: toast.app; summary: toast.summary; body: toast.body; icon: toast.icon
                                    urgency: toast.urgency; stamp: toast.time; nowMs: clock.date.getTime()
                                    showClose: thov.hovered
                                    onCloseClicked: toast.dismiss()
                                }
                                }
                                }
                            }
                        }
                    }
                }

                // ═════════ notification centre (bell) r ═════════
                Item {
                    id: notifPop
                    z: 10
                    // same morph as the Wi-Fi popover: one glass shape grows out of the bell. When popups merge in it appears
                    // at once instead (its cards are the popups) and only the chrome builds in around them.
                    // while clearing the height tracks the collapsing list frame by frame (never shorter than the empty state),
                    // so the dust and the shrink are one motion; otherwise it eases to its new size
                    property real fullH: 92 + (notifHist.count === 0 ? 70 : (root.notifClearing ? Math.max(70, nfl.height) : nfl.height)) + 14
                    Behavior on fullH { enabled: !root.notifClearing; NumberAnimation { duration: 560; easing.type: Easing.OutQuint } }
                    readonly property real ps: root.barPopupScale
                    readonly property real fullW: 380
                    readonly property real srcW: 26
                    readonly property real srcH: 22
                    readonly property real srcX: Math.max(0, Math.min(ui.width - srcW, ui.menuX + 1))
                    readonly property real srcY: Math.max(0, (root.barH - srcH) / 2)
                    readonly property real dstX: Math.max(6, ui.width - fullW * ps - 8)
                    readonly property real dstY: root.barH + 6

                    readonly property bool merging: ui.toastsShown
                    readonly property bool opening: ui.pop === "notif"
                    property real openT: opening ? 1 : 0
                    Behavior on openT {
                        enabled: !notifPop.merging
                        NumberAnimation {
                            duration: notifPop.opening ? 520 : 220
                            easing.type: notifPop.opening ? Easing.OutBack : Easing.InOutCubic
                            easing.overshoot: 0.7
                        }
                    }
                    readonly property real t: Math.max(0, Math.min(1, openT))
                    readonly property real contentT: Math.max(0, Math.min(1, (openT - 0.28) / 0.55))
                    // chrome (glass fill, header, Do Not Disturb): follows the morph, or builds in on its own while popups merge
                    property real chromeM: ui.pop === "notif" ? 1 : 0
                    Behavior on chromeM { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                    readonly property real chrome: merging ? chromeM : contentT

                    width: (srcW + (fullW * ps - srcW) * openT) / ps
                    height: (srcH + (fullH * ps - srcH) * openT) / ps
                    x: srcX + (dstX - srcX) * openT
                    y: srcY + (dstY - srcY) * openT
                    opacity: Math.min(1, t * 4)
                    visible: openT > 0.002
                    scale: ps
                    transformOrigin: Item.TopLeft

                    readonly property real blurAmt: Math.pow(1 - t, 1.3)
                    readonly property bool morphing: openT > 0.002 && Math.abs(openT - 1) > 0.002
                    layer.enabled: morphing
                    layer.smooth: true
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blurMax: 48
                        blur: notifPop.blurAmt * 0.9
                        autoPaddingEnabled: true
                    }

                    // exactly the glass + border of the Wi-Fi / Bluetooth / audio popovers (same context, blur, rim, no drop shadow, no inner shading)
                    PopGlassCtx { id: notifPopGlass; pop: notifPop; frame: ui; source: ui.glassSrc; fullW: notifPop.fullW; fullH: notifPop.fullH }
                    GGlass {
                        anchors.fill: parent
                        opacity: notifPop.merging ? notifPop.chromeM : 1
                        gx: notifPopGlass.ctx
                        cornerR: Math.min(26, 8 + 18 * notifPop.t)
                        thickness: 22
                        shadowAmt: 0
                        flatInner: 1
                    }
                    // same border as the top-bar menus (File, Edit, ...) and the Wi-Fi / audio popovers
                    MenuBorder {
                        z: 2
                        anchors.fill: parent
                        cornerR: Math.min(26, 8 + 18 * notifPop.t)
                        dark: notifPopGlass.ctx.dark
                        tint: notifPopGlass.ctx.borderTint
                        amount: 1
                    }
                    MouseArea { anchors.fill: parent }      // clicks inside the panel don't close it

                    // the content keeps its full size and is revealed by the growing glass (clipped), so nothing reflows mid-morph
                    Item {
                        anchors.fill: parent
                        clip: true
                    Item {
                        id: notifBody
                        x: 0; y: notifPop.merging ? 0 : 10 * (1 - notifPop.contentT)
                        width: notifPop.fullW; height: notifPop.fullH

                    Item {
                        x: 18; y: 14; width: parent.width - 36; height: 26
                        opacity: notifPop.chrome
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Notification system")
                            color: pal.fg
                            font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 17; font.weight: Font.DemiBold
                        }
                        Rectangle {
                            visible: notifHist.count > 0
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            width: clrText.implicitWidth + 20; height: 24; radius: 12
                            color: clrMa.containsMouse ? pal.btnHover : pal.btnOff
                            Text {
                                id: clrText
                                anchors.centerIn: parent
                                text: I18n.tr("Clear All")
                                color: pal.fg
                                font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 12; font.weight: Font.Medium
                            }
                            MouseArea { id: clrMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.notifClearAnimated() }
                        }
                    }
                    Item {
                        x: 12; y: 46; width: parent.width - 24; height: 36
                        opacity: notifPop.chrome
                        Rectangle { anchors.fill: parent; radius: 12; color: pal.tile; border.width: 1; border.color: Qt.rgba(pal.tileBorder.r, pal.tileBorder.g, pal.tileBorder.b, pal.tileBorder.a * 0.4) }
                        Glyph { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 15; height: 15; kind: "moon"; color: pal.fg }
                        Text {
                            x: 36; anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Do Not Disturb")
                            color: pal.fg
                            font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 13
                        }
                        // the same Liquid Glass switch as everywhere else (see GlassSwitch.qml)
                        PSwitch {
                            t: pal
                            anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                            checked: root.notifDnd
                            onToggled: v => root.notifDnd = v
                        }
                    }
                    Text {
                        // fades in as the list finishes collapsing (no pop at the end of Clear All)
                        opacity: notifHist.count === 0 ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
                        x: 0; y: 96; width: parent.width; height: 60
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        text: I18n.tr("No Notifications")
                        color: pal.fg2
                        font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 14
                    }
                    Flickable {
                        id: nfl
                        opacity: notifPop.merging ? 1 : notifPop.contentT
                        x: 12; y: 92
                        width: parent.width - 24
                        height: Math.min(ncol.height, 440)
                        contentHeight: ncol.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        Column {
                            id: ncol
                            width: nfl.width
                            spacing: 8
                            Repeater {
                                model: notifHist
                                delegate: Dissolve {
                                    id: hcd
                                    required property int nid
                                    required property int index
                                    required property string app
                                    required property string summary
                                    required property string body
                                    required property string icon
                                    required property int urgency
                                    required property real time
                                    width: ncol.width
                                    // entrance: grows into the list (cards below glide down), slides in from above, comes into focus
                                    property real inT: 0
                                    property bool snapIn: false
                                    Component.onCompleted: inT = 1
                                    Behavior on inT { enabled: !hcd.snapIn && !root.notifClearing; NumberAnimation { duration: 560; easing.type: Easing.OutQuint } }
                                    // morph from the popup: the card starts at the popup's spot / width and flies into its slot
                                    property real flipX: 0
                                    property real flipY: 0
                                    property real flipS: 1
                                    function flyFromPopup() {
                                        var f = root.notifMergeFrom[hcd.nid];
                                        if (!f || flipAnim.running) return;
                                        // the card's final width is the panel's list width (the list may not be laid out yet)
                                        var cw = notifPop.fullW - 24;
                                        if (!(cw > 0)) return;
                                        var here = hcd.mapToItem(ui, 0, 0);
                                        hcd.flipX = f.x + f.w - (here.x + cw);      // right edges line up (scale origin is the right edge)
                                        // starts where its popup was, but never above the list's top edge (it would be clipped there)
                                        var listTop = nfl.mapToItem(ui, 0, 0).y;
                                        hcd.flipY = Math.max(f.y, listTop) - here.y;
                                        hcd.flipS = Math.max(0.5, Math.min(1.5, f.w / cw));
                                        flyDelay.interval = 1 + Math.max(0, hcd.index) * 40;
                                        flyDelay.restart();
                                    }
                                    Timer { id: flyDelay; onTriggered: flipAnim.restart() }
                                    ParallelAnimation {
                                        id: flipAnim
                                        NumberAnimation { target: hcd; property: "flipX"; to: 0; duration: 620; easing.type: Easing.OutQuint }
                                        NumberAnimation { target: hcd; property: "flipY"; to: 0; duration: 620; easing.type: Easing.OutQuint }
                                        NumberAnimation { target: hcd; property: "flipS"; to: 1; duration: 620; easing.type: Easing.OutQuint }
                                    }
                                    Connections {
                                        target: root
                                        function onNotifMergeFromChanged() { Qt.callLater(hcd.flyFromPopup); }
                                    }
                                    height: hc.height * inT
                                    cardH: hc.height
                                    opacity: inT
                                    transform: [
                                        Scale { origin.x: hcd.width; origin.y: 0; xScale: hcd.flipS; yScale: hcd.flipS },
                                        Translate { x: hcd.flipX; y: (hcd.inT - 1) * 18 + hcd.flipY }
                                    ]
                                    z: (flipAnim.running || flyDelay.running) ? 10 : 0
                                    // after the dust: the gap closes smoothly, then the entry is removed
                                    onDone: { if (root.notifClearing) return; hcd.inT = 0; delT.restart(); }
                                    Timer { id: delT; interval: 560; onTriggered: root.notifDelete(hcd.nid) }
                                    // during Clear All the slot shrinks while the card turns to dust (one fluid motion)
                                    Timer { id: collapseT; onTriggered: collapseAnim.restart() }
                                    NumberAnimation { id: collapseAnim; target: hcd; property: "inT"; to: 0; duration: 820; easing.type: Easing.InOutCubic }
                                    Connections {
                                        target: root
                                        function onNotifDustAll() {
                                            hcd.dissolve(hcd.index * 55);
                                            collapseT.interval = 120 + hcd.index * 55; collapseT.restart();
                                        }
                                    }
                                Rectangle {
                                    id: hc
                                    readonly property int nid: hcd.nid
                                    readonly property string app: hcd.app
                                    readonly property string summary: hcd.summary
                                    readonly property string body: hcd.body
                                    readonly property string icon: hcd.icon
                                    readonly property int urgency: hcd.urgency
                                    readonly property real time: hcd.time
                                    width: hcd.width
                                    height: hbody.height
                                    radius: 18
                                    color: pal.tile
                                    border.width: 1; border.color: Qt.rgba(pal.tileBorder.r, pal.tileBorder.g, pal.tileBorder.b, pal.tileBorder.a * 0.4)
                                    HoverHandler { id: hhov }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: { root.notifActivate(hc.nid); ui.pop = ""; }
                                    }
                                    NotifBody {
                                        id: hbody
                                        t: pal
                                        width: parent.width
                                        app: hc.app; summary: hc.summary; body: hc.body; icon: hc.icon
                                        urgency: hc.urgency; stamp: hc.time; nowMs: clock.date.getTime()
                                        showTime: true
                                        showClose: hhov.hovered
                                        onCloseClicked: hcd.dissolve(1)          // dust away, then removed
                                    }
                                }
                                }
                            }
                        }
                    }
                    }
                    }
                }

                // ═════════ dropdown menu (Apple / app / File / Edit / …) ═════════
                Item {
                    id: menuPop
                    z: 10
                    width: 260
                    height: menuCol.height + 14
                    x: Math.max(6, Math.min(ui.width - width * root.barPopupScale - 6, ui.menuX - 4))
                    y: root.barH + 3
                    opacity: ui.isMenu ? 1 : 0
                    visible: opacity > 0
                    scale: root.barPopupScale * (ui.isMenu ? 1 : 0.97)
                    transformOrigin: Item.TopLeft
                    Behavior on opacity { NumberAnimation { duration: 90 } }
                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                    LGlass {
                        anchors.fill: parent
                        backdrop: ui.glassSrc
                        shaderUrl: root.glassShaderUrl
                        liquid: root.liquidActive
                        dark: root.panelDarkMode
                        bx: menuPop.x; by: menuPop.y
                        shadowAmt: 0
                        flatInner: 1
                        rimTint: 1
                        ringW: 1.4
                        cornerR: 14
                        tint: root.glassOpacity
                        thickness: 22
                        strength: 0.55 * root.glassLiquid
                        rim: root.glassRim
                        grain: root.glassGrain
                        blur: 42
                        debug: root.glassDebug
                        onShaderError: root.glassState = "failed"
                    }
                    MenuBorder {
                        id: menuBorder
                        z: 2
                        anchors.fill: parent
                        cornerR: 14
                        dark: root.panelDarkMode
                        tint: root.menuBorderColor
                    }
                    Column {
                        id: menuCol
                        x: 6; y: 7
                        width: parent.width - 12
                        Repeater {
                            model: ui.menuModel
                            delegate: Item {
                                id: it
                                required property var modelData
                                readonly property bool isSep: modelData.kind === "sep"
                                readonly property bool armedNow: !isSep && modelData.confirm === true && ui.armed === modelData.label
                                readonly property bool off: !isSep && modelData.disabled === true
                                readonly property bool hot: !isSep && !off && ima.containsMouse
                                width: menuCol.width
                                height: isSep ? 11 : 26

                                Rectangle {
                                    visible: it.isSep
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 8; width: parent.width - 16; height: 1
                                    color: panelPal.sep
                                }
                                Rectangle {
                                    visible: it.hot
                                    anchors.fill: parent
                                    radius: 6
                                    color: it.armedNow ? "#FF453A" : root.accent
                                }
                                Glyph {
                                    visible: !it.isSep && it.modelData.glyph !== undefined
                                    x: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 15; height: 15
                                    kind: it.modelData.glyph !== undefined ? it.modelData.glyph : ""
                                    color: it.hot ? "white" : (it.off ? panelPal.fg2 : panelPal.fg)
                                }
                                Text {
                                    visible: !it.isSep && it.modelData.checked === true
                                    x: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "\u2713"
                                    color: it.hot ? "white" : panelPal.fg
                                    font.family: Fonts.forWeight(font.weight, "Open Runde")
                                    font.pixelSize: 13
                                    font.weight: Font.Normal
                                }
                                Text {
                                    visible: !it.isSep
                                    x: ui.menuLead ? 28 : 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - x - 12 - (sc.visible ? sc.implicitWidth + 12 : 0)
                                    elide: Text.ElideRight
                                    text: it.isSep ? "" : (it.armedNow ? I18n.tr("Click again to confirm") : I18n.tr(it.modelData.label))
                                    color: it.hot ? "white" : (it.off ? panelPal.fg2 : panelPal.fg)
                                    font.family: Fonts.forWeight(font.weight, "Open Runde")
                                    font.pixelSize: 13
                                    font.weight: Font.Normal
                                }
                                Text {
                                    id: sc
                                    visible: !it.isSep && it.modelData.shortcut !== undefined && it.modelData.shortcut !== ""
                                    anchors.right: parent.right
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: it.isSep ? "" : (it.modelData.shortcut || "")
                                    color: it.hot ? Qt.rgba(1, 1, 1, 0.8) : panelPal.fg2
                                    font.family: Fonts.forWeight(font.weight, "Open Runde")
                                    font.pixelSize: 12
                                    font.weight: Font.Normal
                                }
                                MouseArea {
                                    id: ima
                                    anchors.fill: parent
                                    enabled: !it.isSep && !it.off
                                    hoverEnabled: true
                                    onClicked: {
                                        if (it.modelData.confirm === true && ui.armed !== it.modelData.label) {
                                            ui.armed = it.modelData.label;
                                            return;
                                        }
                                        var run = it.modelData.run;
                                        ui.pop = "";
                                        if (run) run();
                                    }
                                }
                            }
                        }
                    }
                }

                // ═════════ system tray menu (right-click a tray icon) ═════════
                Item {
                    id: trayPop
                    z: 10
                    readonly property bool shown: ui.pop === "tray"
                    readonly property var cur: ui.trayStack.length > 0 ? ui.trayStack[ui.trayStack.length - 1]
                                               : (ui.trayItem ? ui.trayItem.menu : null)
                    readonly property bool hasLead: {
                        var v = trayOpener.children ? trayOpener.children.values : [];
                        for (var i = 0; i < v.length; i++)
                            if (v[i].buttonType !== QsMenuButtonType.None || (v[i].icon && v[i].icon !== "")) return true;
                        return false;
                    }
                    function clean(t) {     // dbusmenu mnemonics: "_File" -> "File", "__" -> "_"
                        return (t || "").replace(/__/g, "\u0001").replace(/_/g, "").replace(/\u0001/g, "_");
                    }
                    width: 260
                    height: Math.min(trayCol.height + 14, root.popRoom - 20)
                    x: Math.max(6, Math.min(ui.width - width * root.barPopupScale - 6, ui.menuX - 4))
                    y: root.barH + 3
                    opacity: shown ? 1 : 0
                    visible: opacity > 0
                    scale: root.barPopupScale * (shown ? 1 : 0.97)
                    transformOrigin: Item.TopLeft
                    Behavior on opacity { NumberAnimation { duration: 90 } }
                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                    QsMenuOpener { id: trayOpener; menu: trayPop.cur }

                    LGlass {
                        anchors.fill: parent
                        backdrop: ui.glassSrc
                        shaderUrl: root.glassShaderUrl
                        liquid: root.liquidActive
                        dark: root.panelDarkMode
                        bx: trayPop.x; by: trayPop.y
                        shadowAmt: 0
                        flatInner: 1
                        rimTint: 1
                        ringW: 0
                        cornerR: 14
                        tint: root.glassOpacity
                        thickness: 22
                        strength: 0.55 * root.glassLiquid
                        rim: root.glassRim
                        grain: root.glassGrain
                        blur: 42
                        debug: root.glassDebug
                        onShaderError: root.glassState = "failed"
                    }
                    // same border as the top-bar menus (File, Edit, ...)
                    MenuBorder {
                        id: trayBorder
                        z: 2
                        anchors.fill: parent
                        cornerR: 14
                        dark: root.panelDarkMode
                        tint: root.menuBorderColor
                        amount: 1
                    }

                    Flickable {
                        id: trayFlick
                        x: 6; y: 7
                        width: parent.width - 12
                        height: parent.height - 14
                        contentWidth: width
                        contentHeight: trayCol.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: contentHeight > height
                        Connections { target: trayPop; function onCurChanged() { trayFlick.contentY = 0; } }

                        Column {
                            id: trayCol
                            width: trayFlick.width

                            // submenu header: click to go back one level
                            Item {
                                id: trayBack
                                visible: ui.trayStack.length > 0
                                width: trayCol.width
                                height: visible ? 26 : 0
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 6
                                    color: backMa.containsMouse ? root.accent : "transparent"
                                }
                                Text {
                                    x: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 24
                                    elide: Text.ElideRight
                                    text: "\u2039  " + (ui.trayStack.length > 0 ? trayPop.clean(ui.trayStack[ui.trayStack.length - 1].text) : "")
                                    color: backMa.containsMouse ? "white" : panelPal.fg
                                    font.family: root.fontForWeight(font.weight, panelPal.fam); font.pixelSize: 13; font.weight: Font.DemiBold
                                }
                                MouseArea {
                                    id: backMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: ui.trayStack = ui.trayStack.slice(0, ui.trayStack.length - 1)
                                }
                            }
                            Item {
                                visible: trayBack.visible
                                width: trayCol.width; height: visible ? 11 : 0
                                Rectangle { anchors.verticalCenter: parent.verticalCenter; x: 8; width: parent.width - 16; height: 1; color: panelPal.sep }
                            }

                            Repeater {
                                model: trayOpener.children
                                delegate: Item {
                                    id: te
                                    required property var modelData
                                    readonly property bool isSep: modelData.isSeparator
                                    readonly property bool live: !isSep && modelData.enabled
                                    readonly property bool hot: live && tma.containsMouse
                                    width: trayCol.width
                                    height: isSep ? 11 : 26

                                    Rectangle {
                                        visible: te.isSep
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: 8; width: parent.width - 16; height: 1
                                        color: panelPal.sep
                                    }
                                    Rectangle {
                                        visible: te.hot
                                        anchors.fill: parent
                                        radius: 6
                                        color: root.accent
                                    }
                                    // check mark / radio dot / app-provided icon
                                    Text {
                                        visible: !te.isSep && te.modelData.buttonType !== QsMenuButtonType.None && te.modelData.checkState === Qt.Checked
                                        x: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: te.modelData.buttonType === QsMenuButtonType.RadioButton ? I18n.tr("\u25CF") : "\u2713"
                                        color: te.hot ? "white" : (te.live ? panelPal.fg : panelPal.fg2)
                                        font.family: root.fontForWeight(font.weight, panelPal.fam)
                                        font.pixelSize: te.modelData.buttonType === QsMenuButtonType.RadioButton ? 8 : 13
                                    }
                                    Image {
                                        visible: !te.isSep && te.modelData.buttonType === QsMenuButtonType.None && te.modelData.icon !== ""
                                        x: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 16; height: 16
                                        source: te.modelData.icon
                                        sourceSize: Qt.size(32, 32)
                                        fillMode: Image.PreserveAspectFit
                                        opacity: te.live ? 1 : 0.4
                                    }
                                    Text {
                                        visible: !te.isSep
                                        x: trayPop.hasLead ? 32 : 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - x - 12 - (te.modelData.hasChildren ? 14 : 0)
                                        elide: Text.ElideRight
                                        text: te.isSep ? "" : trayPop.clean(te.modelData.text)
                                        color: te.hot ? "white" : (te.live ? panelPal.fg : panelPal.fg2)
                                        font.family: root.fontForWeight(font.weight, panelPal.fam)
                                        font.pixelSize: 13
                                    }
                                    Text {
                                        visible: !te.isSep && te.modelData.hasChildren
                                        anchors.right: parent.right
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "\u203A"
                                        color: te.hot ? "white" : panelPal.fg2
                                        font.family: root.fontForWeight(font.weight, panelPal.fam); font.pixelSize: 15
                                    }
                                    MouseArea {
                                        id: tma
                                        anchors.fill: parent
                                        enabled: te.live
                                        hoverEnabled: true
                                        onClicked: {
                                            if (te.modelData.hasChildren) {
                                                ui.trayStack = ui.trayStack.concat([te.modelData]);
                                            } else {
                                                te.modelData.triggered();
                                                ui.pop = "";
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ═════════ Wi-Fi list (shared by the top-bar popover and the Control Center page) ═════════
                Component {
                    id: wifiContent
                    Column {
                        id: wifiCol
                        property var pp: pal                // palette: the panel palette in the popover, ccPal in the Control Center
                        property bool showBack: false       // Control Center page: show the back arrow
                        signal back()
                        width: parent ? parent.width : 296
                        spacing: 6

                        // header: title + on/off switch
                        Item {
                            width: parent.width; height: 32
                            Item {
                                visible: wifiCol.showBack
                                x: 0; width: 30; height: parent.height
                                Glyph { anchors.centerIn: parent; width: 12; height: 12; kind: "chevL"; color: pp.fg }
                                MouseArea { anchors.fill: parent; onClicked: wifiCol.back() }
                            }
                            Text {
                                x: wifiCol.showBack ? 30 : 6; anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Wi-Fi")
                                color: pp.fg
                                font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 15; font.weight: Font.DemiBold
                            }
                            PSwitch {
                                t: pp
                                anchors.right: parent.right; anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                checked: root.wifiOn
                                onToggled: { root.toggleWifi(); wifiAfter.restart(); }
                            }
                        }
                        Rectangle { width: parent.width; height: 1; color: pp.sep }
                        Text { visible: root.otherConnections.length>0; width:parent.width; leftPadding:6; text:I18n.tr("Ethernet & VPN"); color:pp.fg2; font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize:11; font.weight:Font.DemiBold }
                        Column {
                            width: parent.width
                            Repeater {
                                model: root.otherConnections.slice(0,5)
                                delegate: Item {
                                    required property var modelData
                                    width: parent.width; height: 30
                                    Rectangle { anchors.fill:parent; radius:8; color:connMa.containsMouse?pp.hover:"transparent" }
                                    Glyph { x:8; anchors.verticalCenter:parent.verticalCenter; width:14; height:14; kind:modelData.type==="vpn"?"lock":"wifi"; color:pp.fg }
                                    Text { x:30; anchors.verticalCenter:parent.verticalCenter; width:parent.width-42; elide:Text.ElideRight; text:modelData.name+(modelData.active?I18n.tr(" · Connected"):""); color:pp.fg; font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize:12 }
                                    MouseArea { id:connMa; anchors.fill:parent; hoverEnabled:true; onClicked:root.toggleConnection(modelData) }
                                }
                            }
                        }

                        Text {
                            visible: !root.wifiOn
                            width: parent.width; height: 56
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            text: I18n.tr("Wi-Fi is turned off")
                            color: pp.fg2
                            font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 13
                        }
                        Text {
                            visible: root.wifiOn && root.wifiNets.length === 0
                            width: parent.width; height: 56
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            text: root.wifiScanning ? I18n.tr("Searching\u2026") : I18n.tr("No networks found")
                            color: pp.fg2
                            font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 13
                        }
                        Text {
                            visible: root.wifiOn && root.wifiNets.length > 0
                            leftPadding: 6
                            text: I18n.tr("Networks")
                            color: pp.fg2
                            font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 11; font.weight: Font.DemiBold
                        }

                        // the list
                        Flickable {
                            id: wifiFlick
                            visible: root.wifiOn && root.wifiNets.length > 0
                            width: parent.width
                            height: Math.min(wifiList.height, 300)
                            contentWidth: width
                            contentHeight: wifiList.height
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            Column {
                                id: wifiList
                                width: wifiFlick.width
                                Repeater {
                                    model: root.wifiNets
                                    delegate: Column {
                                        id: nr
                                        required property var modelData
                                        readonly property bool busy: root.wifiBusy === modelData.ssid
                                        readonly property bool prompting: ui.wifiPrompt === modelData.ssid
                                        width: wifiList.width

                                        Item {
                                            width: parent.width; height: 38
                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 8
                                                color: root.accent
                                                visible: wma.containsMouse
                                            }
                                            Glyph {
                                                visible: nr.modelData.inUse
                                                x: 9; anchors.verticalCenter: parent.verticalCenter
                                                width: 14; height: 14
                                                kind: "check"
                                                color: wma.containsMouse ? "white" : pp.fg
                                            }
                                            Text {
                                                x: 30
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - 30 - 96
                                                elide: Text.ElideRight
                                                text: nr.modelData.ssid
                                                color: wma.containsMouse ? "white" : pp.fg
                                                font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 13
                                                font.weight: nr.modelData.inUse ? Font.DemiBold : Font.Normal
                                            }
                                            Text {
                                                visible: nr.busy
                                                anchors.right: parent.right; anchors.rightMargin: 12
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: I18n.tr("Connecting\u2026")
                                                color: pp.fg2
                                                font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 12
                                            }
                                            Text {
                                                visible: !nr.busy && nr.modelData.inUse && wma.containsMouse
                                                anchors.right: parent.right; anchors.rightMargin: 12
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: I18n.tr("Disconnect")
                                                color: "white"
                                                font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 12
                                            }
                                            Row {
                                                visible: !nr.busy && !(nr.modelData.inUse && wma.containsMouse)
                                                anchors.right: parent.right; anchors.rightMargin: 10
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 7
                                                Glyph {
                                                    visible: nr.modelData.secure
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 13; height: 13
                                                    kind: "lock"
                                                    color: wma.containsMouse ? "white" : pp.fg2
                                                }
                                                Glyph {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 16; height: 16
                                                    kind: "wifi"; level: root.sigLevel(nr.modelData.signal)
                                                    color: wma.containsMouse ? "white" : pp.fg
                                                }
                                            }
                                            MouseArea {
                                                id: wma
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                enabled: !nr.busy
                                                onClicked: ui.wifiPick(nr.modelData)
                                            }
                                        }

                                        // password field (secured network that has no saved profile)
                                        Item {
                                            visible: nr.prompting
                                            width: parent.width; height: 42
                                            Rectangle {
                                                x: 30; y: 3
                                                width: parent.width - 30 - 4; height: 32; radius: 10
                                                color: pp.btnOff
                                            }
                                            Text {
                                                x: 42; y: 3; height: 32
                                                verticalAlignment: Text.AlignVCenter
                                                visible: pw.text === ""
                                                text: I18n.tr("Password")
                                                color: pp.fg3
                                                font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 13
                                            }
                                            TextInput {
                                                id: pw
                                                x: 42; y: 3
                                                width: parent.width - 42 - 62; height: 32
                                                verticalAlignment: TextInput.AlignVCenter
                                                clip: true
                                                echoMode: TextInput.Password
                                                color: pp.fg
                                                selectionColor: root.accent
                                                selectedTextColor: "white"
                                                font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 13
                                                onVisibleChanged: if (visible) { text = ""; forceActiveFocus(); }
                                                Keys.onPressed: event => {
                                                    if (event.key === Qt.Key_Escape) { ui.wifiPrompt = ""; event.accepted = true; }
                                                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                                        ui.wifiSubmit(nr.modelData.ssid, text); event.accepted = true;
                                                    }
                                                }
                                            }
                                            Text {
                                                anchors.right: parent.right; anchors.rightMargin: 16
                                                y: 3; height: 32
                                                verticalAlignment: Text.AlignVCenter
                                                text: I18n.tr("Join")
                                                color: pw.text.length > 0 ? root.accent : pp.fg3
                                                font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 13; font.weight: Font.DemiBold
                                                MouseArea {
                                                    anchors.fill: parent; anchors.margins: -6
                                                    onClicked: ui.wifiSubmit(nr.modelData.ssid, pw.text)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            visible: root.wifiError !== ""
                            width: parent.width
                            leftPadding: 6; rightPadding: 6
                            wrapMode: Text.WordWrap
                            text: root.wifiError
                            color: "#FF6961"
                            font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 12
                        }

                        Rectangle { width: parent.width; height: 1; color: pp.sep }
                        Item {
                            width: parent.width; height: 30
                            Rectangle {
                                anchors.fill: parent; radius: 8
                                color: root.accent
                                visible: wsa.containsMouse
                            }
                            Text {
                                x: 10; anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Wi-Fi Settings\u2026")
                                color: wsa.containsMouse ? "white" : pp.fg
                                font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 13
                            }
                            MouseArea {
                                id: wsa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: { ui.pop = ""; root.openSettings("wifi"); }
                            }
                        }
                    }
                }

                // ═════════ Wi-Fi networks ═════════
                Item {
                    id: wifiPop
                    z: 10
                    // ── morph: the popover is ONE glass shape that grows out of the Wi-Fi icon (or the Control Center tile)
                    // into the full menu, while the whole thing starts out of focus and sharpens as it opens. Closing folds it
                    // back into the icon and blurs it out again.
                    readonly property real ps: root.barPopupScale
                    readonly property real fullW: 320
                    readonly property real fullH: (wifiLoad.item ? wifiLoad.item.height : 120) + 24
                    readonly property bool fromCC: ui.menuX >= ui.width - 1
                    // the rectangle it grows from (in screen px)
                    readonly property real srcW: fromCC ? 44 : 26
                    readonly property real srcH: fromCC ? 30 : 22
                    readonly property real srcX: fromCC ? ui.width - 64 : ui.menuX + 1
                    readonly property real srcY: fromCC ? root.barH + 36 : Math.max(0, (root.barH - 22) / 2)
                    // the rectangle it grows into
                    readonly property real dstX: Math.max(6, Math.min(ui.width - fullW * ps - 8, ui.menuX + 14 - fullW * ps / 2))
                    readonly property real dstY: root.barH + 6

                    readonly property bool opening: ui.pop === "wifi"
                    property real openT: opening ? 1 : 0
                    Behavior on openT {
                        NumberAnimation {
                            duration: wifiPop.opening ? 520 : 220
                            easing.type: wifiPop.opening ? Easing.OutBack : Easing.InOutCubic
                            easing.overshoot: 0.7
                        }
                    }
                    // clamped copy for things that must not overshoot
                    readonly property real t: Math.max(0, Math.min(1, openT))
                    // the size follows openT (so the spring overshoots a touch), the content fades in a little later
                    readonly property real contentT: Math.max(0, Math.min(1, (openT - 0.28) / 0.55))

                    width: (srcW + (fullW * ps - srcW) * openT) / ps
                    height: (srcH + (fullH * ps - srcH) * openT) / ps
                    x: srcX + (dstX - srcX) * openT
                    y: srcY + (dstY - srcY) * openT
                    opacity: Math.min(1, t * 4)
                    visible: openT > 0.002
                    scale: ps
                    transformOrigin: Item.TopLeft

                    // morph blur: only exists while the animation runs, so the open popover is drawn directly (crisp text)
                    readonly property real blurAmt: Math.pow(1 - t, 1.3)
                    readonly property bool morphing: openT > 0.002 && Math.abs(openT - 1) > 0.002
                    layer.enabled: morphing
                    layer.smooth: true
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blurMax: 48
                        blur: wifiPop.blurAmt * 0.9
                        autoPaddingEnabled: true
                    }

                    PopGlassCtx { id: wifiPopGlass; pop: wifiPop; fromCC: wifiPop.fromCC; frame: ui; source: ui.glassSrc; fullW: wifiPop.fullW; fullH: wifiPop.fullH }
                    GGlass { anchors.fill: parent; gx: wifiPopGlass.ctx; cornerR: Math.min(26, 8 + 18 * wifiPop.t); thickness: 22; shadowAmt: 0; flatInner: 1 }
                    MenuBorder { z: 2; anchors.fill: parent; cornerR: Math.min(26, 8 + 18 * wifiPop.t); dark: wifiPopGlass.ctx.dark; tint: wifiPopGlass.ctx.borderTint; amount: 1 }   // same border as the top-bar menus
                    MouseArea { anchors.fill: parent }          // swallow clicks on empty glass so the popover doesn't close

                    // the content keeps its full size and is revealed by the growing glass (clipped), fading in and settling
                    // up from a few px below, so nothing reflows while the shape morphs
                    Item {
                        id: wifiClip
                        anchors.fill: parent
                        anchors.margins: 1
                        clip: true
                    Loader {
                        id: wifiLoad
                        sourceComponent: wifiContent
                        x: 11; y: 11 + 10 * (1 - wifiPop.contentT)
                        width: wifiPop.fullW - 24
                        opacity: wifiPop.contentT
                    }
                    }
                }

                // ═════════ Bluetooth list (shared by the top-bar popover and the Control Center page) ═════════
                Component {
                    id: btContent
                    Column {
                        id: btCol
                        property var pp: pal                // palette: the panel palette in the popover, ccPal in the Control Center
                        property bool showBack: false       // Control Center page: show the back arrow
                        signal back()
                        width: parent ? parent.width : 296
                        spacing: 6

                        // header: title + on/off switch
                        Item {
                            width: parent.width; height: 32
                            Item {
                                visible: btCol.showBack
                                x: 0; width: 30; height: parent.height
                                Glyph { anchors.centerIn: parent; width: 12; height: 12; kind: "chevL"; color: pp.fg }
                                MouseArea { anchors.fill: parent; onClicked: btCol.back() }
                            }
                            Text {
                                x: btCol.showBack ? 30 : 6; anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Bluetooth")
                                color: pp.fg
                                font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 15; font.weight: Font.DemiBold
                            }
                            PSwitch {
                                t: pp
                                anchors.right: parent.right; anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                checked: root.btOn
                                onToggled: root.toggleBt()
                            }
                        }
                        Rectangle { width: parent.width; height: 1; color: pp.sep }

                        Text {
                            visible: !root.btOn
                            width: parent.width; height: 56
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            text: I18n.tr("Bluetooth is turned off")
                            color: pp.fg2
                            font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 13
                        }

                        Text {
                            visible: root.btOn && root.btDevices.length === 0
                            width: parent.width; height: 56
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            text: root.btScanning ? I18n.tr("Searching for devices\u2026") : I18n.tr("No devices found")
                            color: pp.fg2
                            font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 13
                        }

                        Item {
                            visible: root.btOn && root.btDevices.length > 0
                            width: parent.width; height: 22
                            Text {
                                x: 6; anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Devices")
                                color: pp.fg2
                                font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 11; font.weight: Font.DemiBold
                            }
                            Row {
                                anchors.right: parent.right; anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Text {
                                    visible: root.btScanning
                                    text: I18n.tr("Scanning\u2026")
                                    color: pp.fg2; font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 11
                                }
                                Text {
                                    visible: !root.btScanning
                                    text: I18n.tr("Scan")
                                    color: root.accent; font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 11; font.weight: Font.DemiBold
                                    MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: root.scanBt() }
                                }
                            }
                        }

                        // the list
                        Flickable {
                            id: btFlick
                            visible: root.btOn && root.btDevices.length > 0
                            width: parent.width
                            height: Math.min(btList.height, 300)
                            contentWidth: width
                            contentHeight: btList.height
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            Column {
                                id: btList
                                width: btFlick.width
                                Repeater {
                                    model: root.btDevices
                                    delegate: Item {
                                        id: devRow
                                        required property var modelData
                                        readonly property bool busy: root.btBusy === modelData.mac
                                        width: btList.width; height: 38

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 8
                                            color: root.accent
                                            visible: bma.containsMouse
                                        }

                                        Glyph {
                                            visible: devRow.modelData.connected
                                            x: 9; anchors.verticalCenter: parent.verticalCenter
                                            width: 14; height: 14
                                            kind: "check"
                                            color: bma.containsMouse ? "white" : pp.fg
                                        }
                                        Glyph {
                                            visible: !devRow.modelData.connected
                                            x: 9; anchors.verticalCenter: parent.verticalCenter
                                            width: 14; height: 14
                                            kind: devRow.modelData.icon || "bluetooth"
                                            color: bma.containsMouse ? "white" : pp.fg2
                                        }

                                        Text {
                                            x: 30
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - 30 - 100
                                            elide: Text.ElideRight
                                            text: devRow.modelData.name || devRow.modelData.mac
                                            color: bma.containsMouse ? "white" : pp.fg
                                            font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 13
                                            font.weight: devRow.modelData.connected ? Font.DemiBold : Font.Normal
                                        }

                                        Text {
                                            visible: devRow.busy
                                            anchors.right: parent.right; anchors.rightMargin: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: devRow.modelData.connected ? I18n.tr("Disconnecting\u2026") : I18n.tr("Connecting\u2026")
                                            color: bma.containsMouse ? "white" : pp.fg2
                                            font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 12
                                        }

                                        Text {
                                            visible: !devRow.busy && devRow.modelData.connected && bma.containsMouse
                                            anchors.right: parent.right; anchors.rightMargin: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: I18n.tr("Disconnect")
                                            color: "white"
                                            font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 12
                                        }

                                        Text {
                                            visible: !devRow.busy && devRow.modelData.connected && !bma.containsMouse
                                            anchors.right: parent.right; anchors.rightMargin: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: I18n.tr("Connected")
                                            color: pp.fg2
                                            font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 12
                                        }

                                        Text {
                                            visible: !devRow.busy && !devRow.modelData.connected && bma.containsMouse
                                            anchors.right: parent.right; anchors.rightMargin: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: I18n.tr("Connect")
                                            color: "white"
                                            font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 12
                                        }

                                        Text {
                                            visible: !devRow.busy && !devRow.modelData.connected && !bma.containsMouse && devRow.modelData.paired
                                            anchors.right: parent.right; anchors.rightMargin: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: I18n.tr("Paired")
                                            color: pp.fg2
                                            font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 12
                                        }

                                        MouseArea {
                                            id: bma
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: !devRow.busy
                                            onClicked: root.connectBt(devRow.modelData.mac, devRow.modelData.connected)
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            visible: root.btError !== ""
                            width: parent.width
                            leftPadding: 6; rightPadding: 6
                            wrapMode: Text.WordWrap
                            text: root.btError
                            color: "#FF6961"
                            font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 12
                        }

                        Rectangle { width: parent.width; height: 1; color: pp.sep }
                        Item {
                            width: parent.width; height: 30
                            Rectangle {
                                anchors.fill: parent; radius: 8
                                color: root.accent
                                visible: bsa.containsMouse
                            }
                            Text {
                                x: 10; anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Bluetooth Settings\u2026")
                                color: bsa.containsMouse ? "white" : pp.fg
                                font.family: root.fontForWeight(font.weight, pp.fam); font.pixelSize: 13
                            }
                            MouseArea {
                                id: bsa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: { ui.pop = ""; root.openSettings("bluetooth"); }
                            }
                        }
                    }
                }

                // ═════════ bluetooth popover ═════════
                Item {
                    id: btPop
                    z: 10
                    // same morph as the Wi-Fi popover: one glass shape grows out of the bluetooth icon, blurred, and sharpens
                    // as it opens; closing folds it back into the icon.
    readonly property real ps: root.barPopupScale
                    readonly property real fullW: 320
                    readonly property real fullH: (btLoad.item ? btLoad.item.height : 120) + 24
                    // the rectangle it grows from (the bar icon, in screen px) and the one it grows into
                    readonly property real srcW: 26
                    readonly property real srcH: 22
                    readonly property real srcX: ui.menuX + 1
                    readonly property real srcY: Math.max(0, (root.barH - srcH) / 2)
                    readonly property real dstX: Math.max(6, Math.min(ui.width - fullW * ps - 8, ui.menuX + 14 - fullW * ps / 2))
                    readonly property real dstY: root.barH + 6

                    readonly property bool opening: ui.pop === "bt"
                    property real openT: opening ? 1 : 0
                    Behavior on openT {
                        NumberAnimation {
                            duration: btPop.opening ? 520 : 220
                            easing.type: btPop.opening ? Easing.OutBack : Easing.InOutCubic
                            easing.overshoot: 0.7
                        }
                    }
                    readonly property real t: Math.max(0, Math.min(1, openT))
                    readonly property real contentT: Math.max(0, Math.min(1, (openT - 0.28) / 0.55))

                    width: (srcW + (fullW * ps - srcW) * openT) / ps
                    height: (srcH + (fullH * ps - srcH) * openT) / ps
                    x: srcX + (dstX - srcX) * openT
                    y: srcY + (dstY - srcY) * openT
                    opacity: Math.min(1, t * 4)
                    visible: openT > 0.002
                    scale: ps
                    transformOrigin: Item.TopLeft

                    // morph blur: only exists while the animation runs, so the open panel is drawn directly (crisp text)
                    readonly property real blurAmt: Math.pow(1 - t, 1.3)
                    readonly property bool morphing: openT > 0.002 && Math.abs(openT - 1) > 0.002
                    layer.enabled: morphing
                    layer.smooth: true
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blurMax: 48
                        blur: btPop.blurAmt * 0.9
                        autoPaddingEnabled: true
                    }

                    PopGlassCtx { id: btPopGlass; pop: btPop; frame: ui; source: ui.glassSrc; fullW: btPop.fullW; fullH: btPop.fullH }
                    GGlass { anchors.fill: parent; gx: btPopGlass.ctx; cornerR: Math.min(26, 8 + 18 * btPop.t); thickness: 22; shadowAmt: 0; flatInner: 1 }
                    MenuBorder { z: 2; anchors.fill: parent; cornerR: Math.min(26, 8 + 18 * btPop.t); dark: btPopGlass.ctx.dark; tint: btPopGlass.ctx.borderTint; amount: 1 }   // same border as the top-bar menus
                    MouseArea { anchors.fill: parent }

                    // the content keeps its full size and is revealed by the growing glass (clipped)
                    Item {
                        anchors.fill: parent
                        anchors.margins: 1
                        clip: true
                        Loader {
                            id: btLoad
                            sourceComponent: btContent
                            x: 11; y: 11 + 10 * (1 - btPop.contentT)
                            width: btPop.fullW - 24
                            opacity: btPop.contentT
                        }
                    }
                }

                // ═════════ calendar ═════════
                Item {
                    id: cal
                    z: 10
                    width: 310
                    height: calCol.height + 28
                    x: Math.max(6, ui.width - width - 8)
                    y: root.barH + 6
                    opacity: ui.pop === "cal" ? 1 : 0
                    visible: opacity > 0
                    scale: root.barPopupScale * (ui.pop === "cal" ? 1 : 0.96)
                    transformOrigin: Item.TopRight
                    Behavior on opacity { NumberAnimation { duration: 110 } }
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                    LGlass {
                        anchors.fill: parent
                        backdrop: ui.glassSrc
                        shaderUrl: root.glassShaderUrl
                        liquid: root.liquidActive
                        dark: root.effDark
                        bx: cal.x; by: cal.y
                        cornerR: 24
                        tint: root.glassOpacity
                        thickness: 22
                        strength: 0.55 * root.glassLiquid
                        rim: root.glassRim
                        grain: root.glassGrain
                        blur: 42
                        debug: root.glassDebug
                        onShaderError: root.glassState = "failed"
                        shadowAmt: 0
                        flatInner: 1
                        rimTint: 1
                        ringW: 1.4
                    }
                    MenuBorder {
                        z: 2
                        anchors.fill: parent
                        cornerR: 24
                        dark: root.effDark
                        tint: root.menuBorderColor
                    }
                    Column {
                        id: calCol
                        x: 16; y: 14
                        width: parent.width - 32
                        spacing: 8

                        Text {
                            text: I18n.locale().toString(clock.date, "dddd")
                            color: pal.fg2
                            font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 12; font.weight: Font.DemiBold
                        }
                        Text {
                            text: I18n.locale().toString(clock.date, I18n.tr("d MMMM yyyy"))
                            color: pal.fg
                            font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 22; font.weight: Font.DemiBold
                        }
                        Item { width: 1; height: 2 }
                        Item {
                            width: parent.width; height: 26
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.locale().monthName(ui.calMonth, Locale.LongFormat) + " " + ui.calYear
                                color: pal.fg
                                font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 14; font.weight: Font.DemiBold
                            }
                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Repeater {
                                    model: [{ k: "chevL", d: -1 }, { k: "chevR", d: 1 }]
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: 26; height: 26; radius: 13
                                        color: cna.containsMouse ? pal.hover : "transparent"
                                        Glyph { anchors.centerIn: parent; width: 13; height: 13; kind: parent.modelData.k; color: pal.fg }
                                        MouseArea { id: cna; anchors.fill: parent; hoverEnabled: true; onClicked: ui.shiftMonth(parent.modelData.d) }
                                    }
                                }
                            }
                        }
                        Row {
                            Repeater {
                                model: 7
                                delegate: Text {
                                    required property int index
                                    width: calCol.width / 7
                                    horizontalAlignment: Text.AlignHCenter
                                    text: I18n.locale().dayName((index + (root.weekStartsMonday ? 1 : 0)) % 7, Locale.ShortFormat).substring(0, 2)
                                    color: pal.fg2
                                    font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 11; font.weight: Font.DemiBold
                                }
                            }
                        }
                        Grid {
                            columns: 7
                            Repeater {
                                model: ui.calData
                                delegate: Item {
                                    required property var modelData
                                    width: calCol.width / 7
                                    height: 32
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 28; height: 28; radius: 14
                                        color: parent.modelData.today ? root.accent : "transparent"
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.modelData.n
                                        color: parent.modelData.today ? "white" : (parent.modelData.cur ? pal.fg : pal.fg3)
                                        font.family: root.fontForWeight(font.weight, pal.fam)
                                        font.pixelSize: 13
                                        font.weight: parent.modelData.today ? Font.DemiBold : Font.Normal
                                    }
                                }
                            }
                        }
                    }
                }

                // ═════════ Control Center ═════════
                // No panel behind it: every tile and every button is its own piece of Liquid Glass.
                Item {
                    id: cc
                    z: 10
                    width: 300
                    height: ui.ccPage === "" ? ccCol.height : (ui.ccPage === "wifi" ? ccWifiPage.height : ccBtPage.height)
                    x: Math.max(8, ui.width - width - 10)
                    y: root.barH + 6
                    // opening (ColorOS 17): the panel springs out from the Control Center button, overshoots a little and
                    // settles, while the controls stretch up into place one row after another. Closing is quick and flat.
                    readonly property bool opening: ui.pop === "cc"
                    property int openSeq: 0
                    property real openT: opening ? 1 : 0
                    Behavior on openT {
                        NumberAnimation {
                            duration: cc.opening ? 520 : 150
                            easing.type: cc.opening ? Easing.OutBack : Easing.OutCubic
                            easing.overshoot: 1.5
                        }
                    }
                    opacity: Math.max(0, Math.min(1, openT * 2.2))
                    visible: opacity > 0
                    // morph: the panel grows out of the button a little while it springs open
                    scale: root.barPopupScale * (0.94 + 0.06 * Math.min(1.0, openT))
                    transformOrigin: Item.TopRight
                    // morph blur: the whole panel starts out of focus and sharpens as it opens; on close it blurs out again.
                    // The layer only exists while the animation runs, so the open panel is drawn directly (crisp text, no extra pass).
                    readonly property real blurAmt: Math.pow(Math.max(0, 1 - Math.min(1, openT)), 1.4)
                    readonly property bool morphing: openT > 0.002 && Math.abs(openT - 1) > 0.002
                    layer.enabled: morphing
                    layer.smooth: true
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blurMax: 40
                        blur: cc.blurAmt * 0.85
                        autoPaddingEnabled: true
                    }
                    // the panel itself never moves above the bar (the menu bar is transparent, so anything that did would
                    // show straight through it). The motion lives in the controls: they slide up into place inside it.
                    onOpeningChanged: if (opening) openSeq++
                    onVisibleChanged: if (visible) { root.refreshWifi(); root.refreshBt(); root.refreshBrightness(); }

                    // Resize refresh: when the menu bar is made smaller / bigger (or the panel itself changes size or position) the
                    // Control Center's backdrop capture used to stay stuck on the old rectangle. Every such change now drops and
                    // re-attaches the capture source for a moment (glassFlip) and forces every stage of the glass to re-render.
                    property bool glassFlip: false
                    // The panel is drawn scaled by barPopupScale around its top-right corner, but the glass shaders position every
                    // slab in the panel's own UNSCALED coordinates. So the backdrop is described twice:
                    //   capLocal  = the region in those unscaled coordinates (what the shaders map their pixels against)
                    //   capScreen = where that same region really is on screen (what is captured): scaled about the top-right corner
                    // At the default size both are identical; at any other bar size the old code captured the unscaled rectangle, so the
                    // backdrop (the tree in the wallpaper) landed in the wrong place and at the wrong size.
                    readonly property rect capLocal: Qt.rect(cc.x - 64, cc.y - 64, cc.width + 128, cc.height + 128)
                    readonly property real capS: root.barPopupScale
                    readonly property rect capScreen: Qt.rect((cc.x + cc.width) + (capLocal.x - (cc.x + cc.width)) * capS,
                                                              cc.y + (capLocal.y - cc.y) * capS,
                                                              capLocal.width * capS, capLocal.height * capS)
                    Timer {
                        id: ccRefresh
                        interval: 40
                        onTriggered: {
                            if (!cc.glassFlip) { cc.glassFlip = true; ccRefresh.restart(); }
                            else {
                                cc.glassFlip = false;
                                ccSrc.scheduleUpdate(); ccBlur.scheduleUpdate(); ccBlur2.scheduleUpdate();
                            }
                        }
                    }
                    function refreshGlass() { cc.glassFlip = false; ccRefresh.restart(); }
                    Connections { target: root; function onBarHeightChanged() { cc.refreshGlass(); } function onBarPopupScaleChanged() { cc.refreshGlass(); } }
                    onWidthChanged: refreshGlass()
                    onHeightChanged: refreshGlass()
                    onXChanged: refreshGlass()
                    onYChanged: refreshGlass()

                    ShaderEffectSource {
                        id: ccSrc
                        sourceItem: cc.glassFlip ? null : ui.glassSrc
                        hideSource: true
                        live: true
                        visible: false
                        sourceRect: cc.capScreen
                    }
                    MultiEffect {
                        id: ccBlurFx
                        source: ccSrc
                        width: ccSrc.sourceRect.width; height: ccSrc.sourceRect.height
                        blurEnabled: true
                        blurMax: 64
                        blur: Math.min(1.0, (ccg.blur * ccg.blurMul) * 1.4 / 64.0)
                        autoPaddingEnabled: false
                        visible: false
                    }
                    // real Gaussian pre-blur of the backdrop (Qt MultiEffect): the glass shader refracts THIS texture,
                    // so there are no sampled copies of the background any more
                    ShaderEffectSource {
                        id: ccBlur
                        sourceItem: ccBlurFx
                        live: true
                        visible: false
                    }
                    MultiEffect {
                        id: ccBlur2Fx
                        source: ccBlur
                        width: ccSrc.sourceRect.width; height: ccSrc.sourceRect.height
                        blurEnabled: (ccg.blur * ccg.blurMul) * 1.4 / 64.0 > 1.0
                        blurMax: 64
                        blur: Math.max(0.0, Math.min(1.0, (ccg.blur * ccg.blurMul) * 1.4 / 64.0 - 1.0))
                        autoPaddingEnabled: false
                        visible: false
                    }
                    // second Gaussian pass: only active when the slider goes past a single pass's 64 px limit
                    ShaderEffectSource {
                        id: ccBlur2
                        sourceItem: (ccg.blur * ccg.blurMul) * 1.4 / 64.0 > 1.0 ? ccBlur2Fx : null
                        live: true
                        visible: false
                    }
                    GlassCtx {
                        id: ccg
                        src: (blur * blurMul) * 1.4 / 64.0 > 1.0 ? ccBlur2 : ccBlur
                        srcRect: cc.capLocal
                        frame: ui
                        liquid: root.liquidActive
                        shaderUrl: root.glassShaderUrl
                        dark: root.ccDark
                        // macOS style: the panel is the glass, so each control only keeps a faint shape on top of it
                        tint: root.ccStyle === "macos" ? root.glassOpacity * 0.30 : root.glassOpacity
                        strength: root.ccStyle === "macos" ? root.glassLiquid * 0.30 : root.glassLiquid
                        rim: root.ccStyle === "macos" ? root.glassRim * 0.10 : root.glassRim * 0.25
                        rimTint: 1
                        ringW: 0                            // the border is the QML CornerBorder now (see component CornerBorder)
                        borderTint: root.menuBorderColor
                        borderAmount: 1                     // strength of the CornerBorder on every tile / button / the panel
                        whiteEdge: false                    // no light inner ring on the non-liquid fallback pane
                        grain: root.glassGrain
                        blur: root.glassBlur
                        debug: root.glassDebug
                        onFailed: root.glassState = "failed"
                    }

                    // ── the controls themselves (instantiated by the grid below) ──
                    function ccComp(id) {
                        switch (id) {
                        case "wifi": return cWifi;
                        case "bluetooth": return cBt;
                        case "airplane": return cAirplane;
                        case "focus": return cFocus;
                        case "nightshift": return cNight;
                        case "keepawake": return cAwake;
                        case "darkmode": return cDark;
                        case "nowplaying": return cNowPlaying;
                        case "display": return cDisplay;
                        case "sound": return cSound;
                        case "record": return cRecord;
                        case "gaming": return cGaming;
                        }
                        return null;
                    }
                    Component {
                        id: cWifi
                        CCTile {
                            id: tl
                            clickable: true
                            on: root.wifiOn
                            onClicked: root.toggleWifi()
                            t: ccPal; gx: ccg
                            CCBtn {
                                plain: true
                                t: ccPal; gx: ccg
                                x: 12; anchors.verticalCenter: parent.verticalCenter
                                kind: "wifi"; level: root.wifiOn ? (root.wifiLevel || 3) : 3
                                on: root.wifiOn
                            }
                            MouseArea {
                                // only the arrow end opens the Wi-Fi page inside the Control Center; the rest of the tile switches Wi-Fi on / off
                                x: parent.width - 48; width: 48; height: parent.height
                                onClicked: { root.wifiError = ""; root.scanWifi(); root.refreshConnections(); ui.ccPage = "wifi"; }
                            }
                            Column {
                                x: 62; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 62 - 24
                                spacing: 1
                                Text { text: I18n.tr("Wi-Fi"); color: tl.fg; font.family: root.fontForWeight(font.weight, ccPal.fam); font.pixelSize: 13; font.weight: Font.DemiBold }
                                MorphText {
                                    animateWidth: false; duration: 420
                                    width: parent.width; elide: Text.ElideRight
                                    text: !root.wifiOn ? I18n.tr("Off") : (root.wifiSsid !== "" ? root.wifiSsid : I18n.tr("Not Connected"))
                                    color: tl.fg2; font.family: root.fontForWeight(font.weight, ccPal.fam); font.pixelSize: 12
                                }
                            }
                        }
                    }
                    Component {
                        id: cBt
                        CCTile {
                            clickable: true
                            on: root.btOn
                            onClicked: root.toggleBt()
                            id: btTile
                            t: ccPal; gx: ccg
                            // one grid cell is ~70 px wide, two are ~150 px: wide = shows the label and opens the device list
                            // (the cell's `slot` is not visible from inside this Component, which left the icon unplaced)
                            readonly property bool wide: width > 110
                            CCBtn {
                                plain: true
                                t: ccPal; gx: ccg
                                x: btTile.wide ? 12 : (parent.width - width) / 2
                                anchors.verticalCenter: parent.verticalCenter
                                kind: "bluetooth"; on: root.btOn
                            }
                            MouseArea {
                                visible: btTile.wide
                                // only the arrow end opens the Bluetooth page inside the Control Center; the rest of the tile switches Bluetooth on / off
                                x: parent.width - 48; width: 48; height: parent.height
                                onClicked: { root.btError = ""; root.scanBt(); root.refreshBt(); ui.ccPage = "bt"; }
                            }
                            Column {
                                visible: btTile.wide
                                x: 62; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 62 - 24
                                spacing: 1
                                Text { text: I18n.tr("Bluetooth"); color: btTile.fg; font.family: root.fontForWeight(font.weight, ccPal.fam); font.pixelSize: 13; font.weight: Font.DemiBold }
                                MorphText {
                                    animateWidth: false; duration: 420
                                    width: parent.width; elide: Text.ElideRight
                                    text: !root.btOn ? I18n.tr("Off") : (root.btConnected > 0 ? (root.btConnectedName || (root.btConnected + I18n.tr(" Connected"))) : I18n.tr("Not Connected"))
                                    color: btTile.fg2; font.family: root.fontForWeight(font.weight, ccPal.fam); font.pixelSize: 12
                                }
                            }
                        }
                    }
                    Component {
                        id: cAirplane
                        CCTile {
                            id: tl
                            clickable: true
                            on: root.airplane
                            onClicked: root.toggleAirplane()
                            t: ccPal; gx: ccg
                            CCBtn {
                                plain: true
                                t: ccPal; gx: ccg; anchors.centerIn: parent
                                kind: "airplane"; on: root.airplane
                            }
                        }
                    }
                    Component {
                        id: cFocus
                        CCTile {
                            id: tl
                            clickable: true
                            on: root.dnd
                            onClicked: root.toggleDnd()
                            t: ccPal; gx: ccg
                            CCBtn {
                                plain: true
                                t: ccPal; gx: ccg
                                x: 12; anchors.verticalCenter: parent.verticalCenter
                                kind: "moon"; on: root.dnd
                            }
                            Column {
                                x: 62; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 62 - 10
                                spacing: 1
                                Text { width: parent.width; elide: Text.ElideRight; text: I18n.tr("Focus"); color: tl.fg; font.family: root.fontForWeight(font.weight, ccPal.fam); font.pixelSize: 13; font.weight: Font.DemiBold }
                                MorphText { animateWidth: false; duration: 420; width: parent.width; elide: Text.ElideRight; text: root.dnd ? I18n.tr("On") : I18n.tr("Off"); color: tl.fg2; font.family: root.fontForWeight(font.weight, ccPal.fam); font.pixelSize: 12 }
                            }
                        }
                    }
                    Component {
                        id: cGaming
                        CCTile {
                            id: tl
                            clickable: true
                            on: root.gaming
                            onTint: "#30D158"
                            onClicked: root.gamingMode = !root.gaming
                            t: ccPal; gx: ccg
                            CCBtn {
                                plain: true
                                t: ccPal; gx: ccg
                                x: 12; anchors.verticalCenter: parent.verticalCenter
                                kind: "gamepad"; on: root.gaming; onTint: "#30D158"
                            }
                            Column {
                                x: 62; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 62 - 10
                                spacing: 1
                                Text { width: parent.width; elide: Text.ElideRight; text: I18n.tr("Game Mode"); color: tl.fg; font.family: root.fontForWeight(font.weight, ccPal.fam); font.pixelSize: 13; font.weight: Font.DemiBold }
                                MorphText { animateWidth: false; duration: 420; width: parent.width; elide: Text.ElideRight; text: root.gamingAutoActive && !root.gamingMode ? I18n.tr("On (game detected)") : (root.gaming ? I18n.tr("On") : (root.gamingAuto ? I18n.tr("Auto") : I18n.tr("Off")))
                                       color: tl.fg2; font.family: root.fontForWeight(font.weight, ccPal.fam); font.pixelSize: 12 }
                            }
                        }
                    }
                    Component {
                        id: cRecord
                        CCTile {
                            id: tl
                            clickable: true
                            on: root.recording
                            onTint: "#FF453A"
                            onClicked: root.toggleRecording()
                            t: ccPal; gx: ccg
                            CCBtn {
                                plain: true
                                t: ccPal; gx: ccg
                                x: 12; anchors.verticalCenter: parent.verticalCenter
                                kind: root.recording ? "stoprec" : "record"; on: root.recording; onTint: "#FF453A"
                            }
                            Column {
                                x: 62; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 62 - 10
                                spacing: 1
                                MorphText { animateWidth: false; duration: 420; width: parent.width; elide: Text.ElideRight; text: root.recording ? "Stop" : I18n.tr("Record"); color: tl.fg; font.family: root.fontForWeight(font.weight, ccPal.fam); font.pixelSize: 13; font.weight: Font.DemiBold }
                                MorphText { animateWidth: false; duration: 420; width: parent.width; elide: Text.ElideRight; text: root.recording ? root.recTime() : I18n.tr("Screen"); color: tl.fg2; font.family: root.fontForWeight(font.weight, ccPal.fam); font.pixelSize: 12 }
                            }
                        }
                    }
                    Component {
                        id: cNight
                        CCTile {
                            id: tl
                            clickable: true
                            on: root.nightOn
                            onClicked: root.nightOn = !root.nightOn
                            t: ccPal; gx: ccg
                            CCBtn {
                                plain: true
                                t: ccPal; gx: ccg; anchors.centerIn: parent
                                kind: "nightshift"; on: root.nightOn
                            }
                        }
                    }
                    Component {
                        id: cAwake
                        CCTile {
                            id: tl
                            clickable: true
                            on: root.keepAwake
                            onClicked: root.keepAwake = !root.keepAwake
                            t: ccPal; gx: ccg
                            CCBtn {
                                plain: true
                                t: ccPal; gx: ccg; anchors.centerIn: parent
                                kind: "coffee"; on: root.keepAwake
                            }
                        }
                    }
                    Component {
                        id: cDark
                        CCTile {
                            id: tl
                            clickable: true
                            on: root.darkMode
                            onClicked: root.setAppearance(root.darkMode ? "light" : "dark")
                            t: ccPal; gx: ccg
                            CCBtn {
                                plain: true
                                t: ccPal; gx: ccg; anchors.centerIn: parent
                                kind: "contrast"; on: root.darkMode
                            }
                        }
                    }
                    Component {
                        id: cNowPlaying
                        CCTile {
                            id: np
                            t: ccPal; gx: ccg
                            readonly property var pl: root.player
                            Rectangle {
                                id: art
                                x: 12; y: 12
                                width: 52; height: 52; radius: 10
                                color: ccPal.btnOff
                                Glyph { visible: artImg.status !== Image.Ready; anchors.centerIn: parent; width: 22; height: 22; kind: "note"; color: ccPal.fg2 }
                                // `clip: true` only clips to a plain rectangle, so the cover is masked with a rounded shape instead
                                Item {
                                    id: artMask
                                    anchors.fill: parent
                                    visible: false
                                    layer.enabled: true
                                    layer.smooth: true
                                    Rectangle { anchors.fill: parent; radius: art.radius; color: "black" }
                                }
                                Image {
                                    id: artImg
                                    anchors.fill: parent
                                    source: np.pl && np.pl.trackArtUrl ? np.pl.trackArtUrl : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    smooth: true
                                    layer.enabled: true
                                    layer.smooth: true
                                    layer.effect: MultiEffect {
                                        maskEnabled: true
                                        maskSource: artMask
                                        maskThresholdMin: 0.5
                                        maskSpreadAtMin: 1.0
                                    }
                                }
                                // hairline edge like the macOS cover art
                                Rectangle {
                                    anchors.fill: parent
                                    radius: art.radius
                                    color: "transparent"
                                    border.width: 1
                                    border.color: ccPal.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10)
                                }
                            }
                            Column {
                                x: 12; y: 66
                                width: parent.width - 24
                                spacing: 1
                                Text {
                                    width: parent.width; elide: Text.ElideRight
                                    text: np.pl && np.pl.trackTitle ? np.pl.trackTitle : I18n.tr("Now Playing")
                                    color: np.pl ? ccPal.fg : ccPal.fg2
                                    font.family: root.fontForWeight(font.weight, ccPal.fam); font.pixelSize: 13; font.weight: Font.DemiBold
                                }
                                Text {
                                    visible: np.pl !== null && np.pl !== undefined
                                    width: parent.width; elide: Text.ElideRight
                                    text: np.pl && np.pl.trackArtist ? np.pl.trackArtist : ""
                                    color: ccPal.fg2; font.family: root.fontForWeight(font.weight, ccPal.fam); font.pixelSize: 12
                                }
                            }
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: parent.height - 38
                                spacing: 2
                                opacity: np.pl ? 1 : 0.4
                                Repeater {
                                    model: ["prev", "play", "next"]
                                    delegate: Item {
                                        id: pbtn
                                        required property string modelData
                                        width: 32; height: 30
                                        Glyph {
                                            anchors.centerIn: parent
                                            width: 26; height: 26
                                            kind: pbtn.modelData === "play" ? (np.pl && np.pl.isPlaying ? "pause" : "play") : pbtn.modelData
                                            color: ccPal.fg
                                            scale: pma.pressed ? 0.88 : 1
                                            Behavior on scale { NumberAnimation { duration: 230; easing.type: Easing.OutBack; easing.overshoot: 3.2 } }
                                        }
                                        MouseArea {
                                            id: pma
                                            anchors.fill: parent
                                            enabled: np.pl !== null && np.pl !== undefined
                                            onClicked: {
                                                if (pbtn.modelData === "prev") np.pl.previous();
                                                else if (pbtn.modelData === "next") np.pl.next();
                                                else np.pl.togglePlaying();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Component {
                        id: cDisplay
                        CCTile {
                            t: ccPal; gx: ccg
                            radius: 26
                            Text {
                                x: 14; y: 8
                                text: I18n.tr("Display")
                                color: ccPal.fg; font.family: root.fontForWeight(font.weight, ccPal.fam); font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                            HoverHandler { id: tileHovDisplay }
                            CCSlider {
                                tileHover: tileHovDisplay.hovered
                                t: ccPal
                                gx: ccg; glassMul: root.ccStyle === "macos" ? 3 : 1
                                x: 12; y: 28
                                width: parent.width - 24
                                value: root.brightness
                                leftKind: "sun"; leftLevel: 1
                                rightKind: "sun"; rightLevel: 3
                                onMoved: v => root.setBrightness(v)
                            }
                        }
                    }
                    Component {
                        id: cSound
                        CCTile {
                            t: ccPal; gx: ccg
                            radius: 26
                            Text {
                                x: 14; y: 8
                                text: I18n.tr("Sound")
                                color: ccPal.fg; font.family: root.fontForWeight(font.weight, ccPal.fam); font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                            HoverHandler { id: tileHovSound }
                            CCSlider {
                                tileHover: tileHovSound.hovered
                                t: ccPal
                                gx: ccg; glassMul: root.ccStyle === "macos" ? 3 : 1
                                x: 12; y: 28
                                width: parent.width - 24 - 36
                                value: root.muted ? 0 : root.volume
                                leftKind: "speaker"; leftLevel: 1
                                rightKind: "speaker"; rightLevel: 3
                                onMoved: v => root.setVolume(v)
                            }
                            CCBtn {
                                t: ccPal; gx: ccg
                                d: 28
                                glass: false
                                x: parent.width - 12 - 28; y: 28
                                kind: "speaker"; level: root.muted ? 0 : 3
                                on: root.muted
                                onClicked: root.toggleMute()
                            }
                        }
                    }

                    // macOS Control Center: one frosted slab behind everything (the tiles sit on it, instead of each
                    // control being its own piece of glass)
                    Loader {
                        active: root.ccStyle === "macos"
                        x: -12; y: -12
                        width: cc.width + 24; height: cc.height + 24
                        sourceComponent: Item {
                            GGlass { anchors.fill: parent; gx: ccg; cornerR: 24; thickness: 26; strengthMul: 1.0; shadowAmt: 0.6 }
                            CornerBorder { z: 2; anchors.fill: parent; cornerR: 24; dark: ccg.dark; tint: root.menuBorderColor; amount: ccg.borderAmount; lineW: 0.8 }
                        }
                    }

                    // Wi-Fi page: the network list opens inside the Control Center (back arrow in the header) instead of
                    // switching to the top-bar Wi-Fi popover
                    Item {
                        id: ccWifiPage
                        readonly property bool shown: ui.ccPage === "wifi"
                        width: parent.width
                        height: wifiPageLoad.height + 24
                        opacity: shown ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        GGlass { visible: root.ccStyle !== "macos"; anchors.fill: parent; gx: ccg; cornerR: 26; thickness: 22; shadowAmt: 0.45 }
                        CornerBorder { visible: root.ccStyle !== "macos"; z: 2; anchors.fill: parent; cornerR: 26; dark: ccg.dark; tint: ccg.borderTint; amount: ccg.borderAmount; lineW: 0.8 }
                        MouseArea { anchors.fill: parent }
                        Loader {
                            id: wifiPageLoad
                            active: ccWifiPage.shown || ccWifiPage.visible
                            x: 12; y: 12
                            width: parent.width - 24
                            sourceComponent: wifiContent
                            onLoaded: { item.pp = ccPal; item.showBack = true; item.back.connect(function () { ui.ccPage = ""; }); }
                        }
                    }

                    // Bluetooth page: the device list opens inside the Control Center, like the Wi-Fi page
                    Item {
                        id: ccBtPage
                        readonly property bool shown: ui.ccPage === "bt"
                        width: parent.width
                        height: btPageLoad.height + 24
                        opacity: shown ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        GGlass { visible: root.ccStyle !== "macos"; anchors.fill: parent; gx: ccg; cornerR: 26; thickness: 22; shadowAmt: 0.45 }
                        CornerBorder { visible: root.ccStyle !== "macos"; z: 2; anchors.fill: parent; cornerR: 26; dark: ccg.dark; tint: ccg.borderTint; amount: ccg.borderAmount; lineW: 0.8 }
                        MouseArea { anchors.fill: parent }
                        Loader {
                            id: btPageLoad
                            active: ccBtPage.shown || ccBtPage.visible
                            x: 12; y: 12
                            width: parent.width - 24
                            sourceComponent: btContent
                            onLoaded: { item.pp = ccPal; item.showBack = true; item.back.connect(function () { ui.ccPage = ""; }); }
                        }
                    }

                    Column {
                        id: ccCol
                        x: 0; y: 0
                        width: parent.width
                        spacing: 10
                        opacity: ui.ccPage === "" ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                        // ── privacy: a small glass pill (icons + the apps using them), only while something is active ──
                        Item {
                            id: ccPriv
                            visible: root.privacyAny && root.barWidgetEnabled("privacy")
                            width: parent.width
                            height: visible ? 32 : 0
                            // one icon per kind of use (screen sharing and recording share the purple one)
                            readonly property var icons: {
                                var a = [], seen = {};
                                for (var i = 0; i < root.privacyRows.length; i++) {
                                    var r = root.privacyRows[i];
                                    if (seen[r.c + r.glyph]) continue;
                                    seen[r.c + r.glyph] = true;
                                    a.push({ glyph: r.glyph, c: r.c });
                                }
                                return a;
                            }
                            // every app using the mic / camera / screen, once each
                            readonly property string names: {
                                var all = root.privacy.mic.concat(root.privacy.cam).concat(root.privacy.share), out = [];
                                for (var i = 0; i < all.length; i++) if (out.indexOf(all[i]) < 0) out.push(all[i]);
                                if (out.length === 0 && root.recording) return "Screen Recording " + root.recTime();
                                return out.join(", ");
                            }
                            Item {
                                id: privPill
                                anchors.horizontalCenter: parent.horizontalCenter
                                height: 32
                                width: Math.min(parent.width, 14 + privIcons.width + 8 + privText.implicitWidth + (root.recording ? 8 + 44 : 0) + 14)
                                CCTile { anchors.fill: parent; t: ccPal; gx: ccg; radius: 16 }
                                Row {
                                    id: privIcons
                                    x: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4
                                    Repeater {
                                        model: ccPriv.icons
                                        delegate: Rectangle {
                                            required property var modelData
                                            width: 18; height: 18; radius: 9
                                            color: modelData.c
                                            Glyph { anchors.centerIn: parent; width: 10; height: 10; kind: modelData.glyph; color: "white" }
                                        }
                                    }
                                }
                                Text {
                                    id: privText
                                    x: 14 + privIcons.width + 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(implicitWidth, privPill.width - x - 14 - (root.recording ? 52 : 0))
                                    elide: Text.ElideRight
                                    text: ccPriv.names
                                    color: ccPal.fg
                                    font.family: root.fontForWeight(font.weight, ccPal.fam); font.pixelSize: 13; font.weight: Font.Medium
                                }
                                // while recording, the pill also carries the Stop button
                                Rectangle {
                                    visible: root.recording
                                    anchors.right: parent.right; anchors.rightMargin: 7
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 44; height: 20; radius: 10
                                    color: "#FF453A"
                                    Text { anchors.centerIn: parent; text: "Stop"; color: "white"; font.family: root.fontForWeight(font.weight, ccPal.fam); font.pixelSize: 11; font.weight: Font.DemiBold }
                                    MouseArea { anchors.fill: parent; onClicked: root.toggleRecording() }
                                }
                            }
                        }

                        // ── the control grid ──
                        Item {
                            id: ccGrid
                            width: parent.width
                            height: Math.max(66, root.ccPlan.total)
                            readonly property real cw: (width - 3 * root.ccGap) / 4
                            readonly property real chh: root.ccCellH

                            Text {
                                visible: root.ccPlan.items.length === 0
                                anchors.centerIn: parent
                                text: I18n.tr("No controls. Use Edit Controls to add some.")
                                color: ccPal.fg2; font.family: root.fontForWeight(font.weight, ccPal.fam); font.pixelSize: 12
                            }

                            Repeater {
                                model: root.ccCatalog
                                delegate: Item {
                                    id: ct
                                    required property var modelData
                                    readonly property var slot: {
                                        var it = root.ccPlan.items;
                                        for (var i = 0; i < it.length; i++) if (it[i].id === modelData.id) return it[i];
                                        return null;
                                    }
                                    property real dx: 0
                                    property real dy: 0
                                    property bool dragging: false

                                    visible: slot !== null
                                    x: (slot ? slot.col * (ccGrid.cw + root.ccGap) : 0) + dx
                                    y: (slot ? slot.y : 0) + dy
                                    width: slot ? slot.w * ccGrid.cw + (slot.w - 1) * root.ccGap : 0
                                    height: slot ? slot.hpx : 0
                                    z: dragging ? 100 : 0
                                    // stretch-and-settle, a touch later for each row / column (ColorOS 17)
                                    property real ap: 1
                                    Connections {
                                        target: cc
                                        function onOpenSeqChanged() { ct.ap = 0; tileIn.restart(); }
                                    }
                                    SequentialAnimation {
                                        id: tileIn
                                        PauseAnimation { duration: ct.slot ? Math.min(220, ct.slot.row * 55 + ct.slot.col * 18) : 0 }
                                        NumberAnimation { target: ct; property: "ap"; from: 0; to: 1; duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                                    }
                                    transform: Translate { y: (1 - ct.ap) * 16 }
                                    opacity: Math.max(0, Math.min(1, ct.ap * 1.6))
                                    scale: dragging ? 1.04 : 1
                                    Behavior on x { enabled: !ct.dragging; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    Behavior on y { enabled: !ct.dragging; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                                    // one-cell controls (the circle buttons) are drawn as a smaller circle centred in their grid cell
                                    readonly property bool small: slot !== null && slot.w === 1 && slot.h === 1
                                    Loader {
                                        anchors.centerIn: parent
                                        width: ct.small ? 63 : ct.width
                                        height: ct.small ? 63 : ct.height
                                        active: ct.slot !== null
                                        sourceComponent: cc.ccComp(ct.modelData.id)
                                    }

                                    // edit mode: this layer sits above the control, so clicks drag it instead of using it
                                    MouseArea {
                                        id: dragArea
                                        anchors.fill: parent
                                        z: 50
                                        enabled: ui.ccEdit
                                        visible: ui.ccEdit      // a hidden area can't leave the grab cursor behind
                                        preventStealing: true
                                        cursorShape: !ui.ccEdit ? Qt.ArrowCursor : (ct.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                                        property point startP: Qt.point(0, 0)
                                        onPressed: mouse => {
                                            var q = mapToItem(ccGrid, mouse.x, mouse.y);
                                            startP = Qt.point(q.x, q.y);
                                            ct.dragging = true;
                                        }
                                        onPositionChanged: mouse => {
                                            if (!pressed) return;
                                            var q = mapToItem(ccGrid, mouse.x, mouse.y);
                                            ct.dx = q.x - startP.x;
                                            ct.dy = q.y - startP.y;
                                        }
                                        onReleased: mouse => {
                                            var q = mapToItem(ccGrid, mouse.x, mouse.y);
                                            ct.dragging = false;
                                            ct.dx = 0; ct.dy = 0;
                                            root.ccDrop(ct.modelData.id, q.x, q.y, ccGrid.cw, ccGrid.chh, ccGrid.height);
                                        }
                                        onCanceled: { ct.dragging = false; ct.dx = 0; ct.dy = 0; }
                                    }

                                    // remove badge
                                    Rectangle {
                                        visible: ui.ccEdit
                                        z: 60
                                        x: -5; y: -5
                                        width: 22; height: 22; radius: 11
                                        color: ccPal.dark ? "#636366" : "#8E8E93"
                                        border.width: 1.5
                                        border.color: ccPal.dark ? Qt.rgba(1, 1, 1, 0.35) : "white"
                                        Rectangle { anchors.centerIn: parent; width: 10; height: 2; radius: 1; color: "white" }
                                        MouseArea {
                                            anchors.fill: parent; anchors.margins: -3
                                            onClicked: root.ccRemove(ct.modelData.id)
                                        }
                                    }
                                }
                            }
                        }

                        // ── edit mode: controls that are not on the grid yet ──
                        Column {
                            visible: ui.ccEdit && ccAddRep.count > 0
                            width: parent.width
                            spacing: 8
                            Text {
                                leftPadding: 4
                                text: I18n.tr("Add Controls")
                                color: ccPal.fg2
                                font.family: root.fontForWeight(font.weight, ccPal.fam); font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                            Flow {
                                width: parent.width
                                spacing: 8
                                Repeater {
                                    id: ccAddRep
                                    model: root.ccCatalog.filter(function (d) { return root.ccControls.indexOf(d.id) < 0; })
                                    delegate: CCTile {
                                        id: chip
                                        required property var modelData
                                        t: ccPal; gx: ccg
                                        radius: 17
                                        width: chipRow.implicitWidth + 24; height: 34
                                        Row {
                                            id: chipRow
                                            anchors.centerIn: parent
                                            spacing: 7
                                            Rectangle {
                                                width: 18; height: 18; radius: 9
                                                color: "#30D158"
                                                anchors.verticalCenter: parent.verticalCenter
                                                Text { anchors.centerIn: parent; text: "+"; color: "white"; font.family: Fonts.forWeight(font.weight, pal.fam); font.pixelSize: 14; font.weight: Font.Bold }
                                            }
                                            Glyph {
                                                width: 16; height: 16
                                                anchors.verticalCenter: parent.verticalCenter
                                                kind: chip.modelData.glyph; color: ccPal.fg
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: I18n.tr(chip.modelData.label)
                                                color: ccPal.fg; font.family: root.fontForWeight(font.weight, ccPal.fam); font.pixelSize: 12
                                            }
                                        }
                                        MouseArea { anchors.fill: parent; onClicked: root.ccAdd(chip.modelData.id) }
                                    }
                                }
                            }
                        }

                        // ── edit controls / done ──
                        Item {
                            id: ccEditRow
                            width: parent.width; height: 28
                            // same stretch-and-settle as the control tiles, arriving after the last row
                            property real ap: 1
                            Connections {
                                target: cc
                                function onOpenSeqChanged() { ccEditRow.ap = 0; editIn.restart(); }
                            }
                            SequentialAnimation {
                                id: editIn
                                PauseAnimation { duration: Math.min(220, root.ccPlan.rows * 55 + 40) }
                                NumberAnimation { target: ccEditRow; property: "ap"; from: 0; to: 1; duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                            }
                            transform: Translate { y: (1 - ccEditRow.ap) * 16 }
                            opacity: Math.max(0, Math.min(1, ccEditRow.ap * 1.6))
                            Row {
                                anchors.centerIn: parent
                                spacing: 8
                                CCPill {
                                    visible: ui.ccEdit
                                    t: ccPal; gx: ccg
                                    text: I18n.tr("Reset")
                                    onClicked: root.ccControls = root.ccDefault.slice()
                                }
                                CCPill {
                                    t: ccPal; gx: ccg
                                    text: ui.ccEdit ? I18n.tr("Done") : I18n.tr("Edit Controls")
                                    strong: ui.ccEdit
                                    onClicked: ui.ccEdit = !ui.ccEdit
                                }
                            }
                        }
                    }
                }
            }
        }

        // ═════════ Window switcher (ALT + TAB) lives in its OWN layer (namespace "macswitch") ═════════
        PanelWindow {
            id: swWin
            screen: perScreen.modelData
            visible: (root.swOpen && ui.toastScreen) || swPanel.opacity > 0
            onVisibleChanged: root.popCount += (visible ? 1 : -1)     // keeps the window-geometry poller running while it is open
            anchors { left: true; right: true; top: true; bottom: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.namespace: "macswitch"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: (root.swOpen && ui.toastScreen) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            Item {
                id: swRoot
                anchors.fill: parent
                focus: true

                // releasing ALT switches to the selected app; TAB / SHIFT+TAB / arrows cycle; ESC cancels
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Right) { root.swNext(1); event.accepted = true; }
                    else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Left) { root.swNext(-1); event.accepted = true; }
                    else if (event.key === Qt.Key_Escape) { root.swCancel(); event.accepted = true; }
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.swCommit(); event.accepted = true; }
                }
                Keys.onReleased: event => {
                    if (event.key === Qt.Key_Alt && !event.isAutoRepeat) { root.swCommit(); event.accepted = true; }
                }

                Loader {
                    id: swBackdrop
                    active: root.liquidActive          // stays loaded (warm) so the window opens on ready-made frames
                    sourceComponent: backdropComp
                    onLoaded: { item.hostShown = Qt.binding(function () { return swWin.visible; });
                                item.region = Qt.binding(function () { return Qt.rect(swPanel.x - 96, swPanel.y - 96, swPanel.width + 192, swPanel.height + 192); }); }
                }
                MouseArea { anchors.fill: parent; onPressed: root.swCancel() }      // click outside cancels

                Item {
                    id: swPanel
                    z: 10
                    readonly property int n: root.swApps.length
                    readonly property real cw: Math.min(92, (swRoot.width - 160) / Math.max(n, 1))
                    readonly property real ico: Math.round(cw * 0.7)
                    readonly property real pad: 14
                    readonly property real cellH: Math.round(cw * 0.8)
                    readonly property real padY: 9
                    width: n * cw + 2 * pad
                    height: padY + cellH + 25
                    x: Math.round((swRoot.width - width) / 2)
                    y: Math.round(swRoot.height * 0.42 - height / 2)
                    // opens with motion + blur: grows from 92 % while coming into focus; closes quicker
                    readonly property bool shown: root.swOpen && ui.toastScreen
                    opacity: shown ? 1 : 0
                    visible: opacity > 0
                    scale: shown ? 1 : 0.92
                    transformOrigin: Item.Center
                    Behavior on opacity { NumberAnimation { duration: swPanel.shown ? 220 : 160; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: swPanel.shown ? 420 : 200; easing.type: Easing.OutQuint } }
                    property real soft: shown ? 0 : 1
                    Behavior on soft { NumberAnimation { duration: swPanel.shown ? 300 : 160; easing.type: Easing.OutCubic } }
                    layer.enabled: soft > 0.01
                    layer.effect: MultiEffect { blurEnabled: true; blurMax: 32; blur: swPanel.soft * 0.8; autoPaddingEnabled: true }

                    readonly property string style: root.switcherStyle
                    LGlass {
                        anchors.fill: parent
                        visible: swPanel.style !== "opaque"
                        backdrop: swBackdrop.item
                        shaderUrl: root.glassShaderUrl
                        liquid: root.liquidActive
                        dark: root.effDark
                        bx: swPanel.x; by: swPanel.y
                        cornerR: 26
                        // frosted: the same glass with no refraction, a heavier blur and more tint
                        tint: swPanel.style === "frosted" ? Math.max(0.5, root.glassOpacity) : root.glassOpacity
                        thickness: swPanel.style === "frosted" ? 6 : 20
                        strength: swPanel.style === "frosted" ? 0.0 : 0.75 * root.glassLiquid
                        rim: swPanel.style === "frosted" ? 0.15 : root.glassRim
                        grain: root.glassGrain
                        blur: swPanel.style === "frosted" ? 30 : root.switcherBlur
                        debug: root.glassDebug
                        onShaderError: root.glassState = "failed"
                        rimTint: 1
                        ringW: 1.4
                    }
                    MenuBorder {
                        z: 2
                        anchors.fill: parent
                        visible: swPanel.style !== "opaque"
                        cornerR: 26
                        dark: root.effDark
                        tint: root.menuBorderColor
                    }
                    Rectangle {
                        anchors.fill: parent
                        visible: swPanel.style === "opaque"
                        radius: 26
                        color: root.effDark ? "#232325" : "#F2F2F5"
                        border.width: 1; border.color: root.effDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10)
                        layer.enabled: true
                        layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 1.0; shadowOpacity: 0.35; shadowVerticalOffset: 8 }
                    }

                    // selection highlight (slides between apps)
                    Rectangle {
                        visible: swPanel.n > 0
                        x: swPanel.pad + root.swIndex * swPanel.cw
                        y: swPanel.padY
                        width: swPanel.cw; height: swPanel.cellH
                        radius: 17
                        color: root.darkMode ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.11)
                        border.width: 1
                        border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)
                        Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutQuint } }
                    }
                    Repeater {
                        model: root.swApps
                        delegate: Item {
                            id: swCell
                            required property int index
                            required property var modelData
                            x: swPanel.pad + index * swPanel.cw
                            y: swPanel.padY
                            width: swPanel.cw; height: swPanel.cellH
                            Image {
                                anchors.centerIn: parent
                                width: swPanel.ico; height: swPanel.ico
                                source: root.swIcon(swCell.modelData)
                                sourceSize.width: 128; sourceSize.height: 128
                                fillMode: Image.PreserveAspectFit
                                smooth: true; mipmap: true
                                asynchronous: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onPositionChanged: root.swIndex = swCell.index      // only on real mouse movement, so TAB keeps control
                                onClicked: { root.swIndex = swCell.index; root.swCommit(); }
                            }
                        }
                    }
                    // name of the selected app, under its icon
                    // the name blur-morphs into the next app's while it glides under the new icon
                    // (a fixed-width box centred on the new icon: it starts moving the instant the selection changes, so the
                    //  name glides and morphs at the same time — its position never waits on the morphing text's width)
                    TextMetrics { id: swNameM; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 13; font.weight: Font.Medium; text: swName.text }
                    Item {
                        id: swNameBox
                        visible: swPanel.n > 0
                        width: 260; height: swName.implicitHeight
                        readonly property real cx: swPanel.pad + root.swIndex * swPanel.cw + swPanel.cw / 2
                        readonly property real tw: Math.min(swNameM.advanceWidth, swPanel.width - 20)
                        // keep the whole name inside the panel
                        readonly property real cxc: Math.max(10 + tw / 2, Math.min(swPanel.width - 10 - tw / 2, cx))
                        x: cxc - width / 2
                        y: swPanel.padY + swPanel.cellH + 3
                        Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutQuint } }
                        MorphText {
                            id: swName
                            width: parent.width
                            text: root.swApps.length > root.swIndex ? root.swApps[root.swIndex].name : ""
                            color: swPanel.style === "opaque" ? (root.effDark ? "white" : "#1D1D1F") : pal.fg
                            font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 13; font.weight: Font.Medium
                            horizontalAlignment: Text.AlignHCenter
                            animateWidth: false
                            duration: 320
                        }
                    }
                }
            }
        }

        // ═════════ Wallpaper picker (CTRL + ALT + W) lives in its OWN layer (namespace "macwall") ═════════
        PanelWindow {
            id: wpWin
            screen: perScreen.modelData
            visible: (root.wpOpen && ui.toastScreen) || wpPanel.opacity > 0
            onVisibleChanged: root.popCount += (visible ? 1 : -1)     // keeps the window-geometry poller running while it is open
            anchors { left: true; right: true; top: true; bottom: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.namespace: "macwall"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: (root.wpOpen && ui.toastScreen) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            Item {
                id: wpRoot
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: event => { if (root.wpQuery !== "") root.wpQuery = ""; else root.wpOpen = false; event.accepted = true; }
                Connections {
                    target: root
                    function onWpOpenChanged() { if (root.wpOpen) { root.wpQuery = ""; wpGrid.currentIndex = 0; wpGrid.forceActiveFocus(); } }
                    function onWpQueryChanged() {
                        if (wpSearch.text !== root.wpQuery) wpSearch.text = root.wpQuery;
                        wpGrid.currentIndex = 0;
                        wpGrid.positionViewAtBeginning();
                    }
                }

                Loader {
                    id: wpBackdrop
                    active: root.liquidActive          // stays loaded (warm) so the window opens on ready-made frames
                    sourceComponent: backdropComp
                    onLoaded: { item.hostShown = Qt.binding(function () { return wpWin.visible; });
                                item.region = Qt.binding(function () { return Qt.rect(wpPanel.x - 96, wpPanel.y - 96, wpPanel.width + 192, wpPanel.height + 192); }); }
                }
                MouseArea { anchors.fill: parent; onPressed: root.wpOpen = false }      // click outside closes

                Item {
                    id: wpPanel
                    z: 10
                    width: Math.min(980, wpRoot.width - 120)
                    height: Math.min(640, wpRoot.height - 160)
                    x: Math.round((wpRoot.width - width) / 2)
                    y: Math.round((wpRoot.height - height) / 2)
                    opacity: (root.wpOpen && ui.toastScreen) ? 1 : 0
                    visible: opacity > 0
                    scale: (root.wpOpen && ui.toastScreen) ? 1 : 0.96
                    transformOrigin: Item.Center
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    LGlass {
                        anchors.fill: parent
                        backdrop: wpBackdrop.item
                        shaderUrl: root.glassShaderUrl
                        liquid: root.liquidActive
                        dark: root.effDark
                        bx: wpPanel.x; by: wpPanel.y
                        cornerR: 28
                        tint: root.glassOpacity
                        thickness: 22
                        strength: 0.75 * root.glassLiquid
                        rim: root.glassRim
                        grain: root.glassGrain
                        blur: root.wpBlur
                        debug: root.glassDebug
                        onShaderError: root.glassState = "failed"
                        rimTint: 1
                        ringW: 1.4
                    }
                    MenuBorder {
                        z: 2
                        anchors.fill: parent
                        cornerR: 28
                        dark: root.effDark
                        tint: root.menuBorderColor
                    }

                    // ── header: title, folder path, Choose… ──
                    Item {
                        id: wpHead
                        x: 22; y: 14
                        width: parent.width - 44; height: 34
                        Text {
                            id: wpTitle
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Wallpapers")
                            color: pal.fg
                            font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 15; font.weight: Font.DemiBold
                        }
                        Rectangle {
                            id: wpChoose
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 84; height: 30; radius: 10
                            color: wpChooseMa.containsMouse ? pal.btnHover : pal.btnOff
                            Text { anchors.centerIn: parent; text: I18n.tr("Choose\u2026"); color: pal.fg; font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 12; font.weight: Font.Medium }
                            MouseArea { id: wpChooseMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.wpPickFolder() }
                        }
                        Rectangle {
                            anchors.left: wpTitle.right; anchors.leftMargin: 18
                            anchors.right: wpChoose.left; anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            height: 30; radius: 10
                            color: pal.tile
                            border.width: 1
                            border.color: dirInput.activeFocus ? pal.accent : pal.tileBorder
                            TextInput {
                                id: dirInput
                                anchors.fill: parent
                                anchors.leftMargin: 10; anchors.rightMargin: 10
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                selectByMouse: true
                                color: pal.fg
                                selectionColor: pal.accent
                                font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 12
                                text: root.wpDirEff
                                onAccepted: { root.wpSetDir(text); wpGrid.forceActiveFocus(); }
                                Connections { target: root; function onWpDirEffChanged() { dirInput.text = root.wpDirEff; } }
                            }
                        }
                    }
                    // ── search + status ──
                    Rectangle {
                        id: wpSearchBox
                        x: 22; y: 54
                        width: Math.min(260, parent.width * 0.4); height: 28; radius: 10
                        color: pal.tile
                        border.width: 1
                        border.color: wpSearch.activeFocus ? pal.accent : pal.tileBorder
                        Glyph { x: 9; anchors.verticalCenter: parent.verticalCenter; width: 13; height: 13; kind: "search"; color: pal.fg2 }
                        TextInput {
                            id: wpSearch
                            anchors.fill: parent
                            anchors.leftMargin: 30; anchors.rightMargin: 26
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            selectByMouse: true
                            color: pal.fg
                            selectionColor: pal.accent
                            font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 12
                            onTextChanged: if (root.wpQuery !== text) root.wpQuery = text
                            Keys.onDownPressed: wpGrid.forceActiveFocus()
                            Keys.onReturnPressed: {
                                if (root.wpShown.length > 0) { root.wpApply(root.wpShown[Math.max(0, wpGrid.currentIndex)].path); root.wpOpen = false; }
                            }
                            Text {
                                visible: wpSearch.text === "" && !wpSearch.activeFocus
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Search")
                                color: pal.fg3
                                font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 12
                            }
                        }
                        Rectangle {
                            visible: root.wpQuery !== ""
                            anchors.right: parent.right; anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16; height: 16; radius: 8
                            color: pal.btnOff
                            Text { anchors.centerIn: parent; text: "\u00d7"; color: pal.fg; font.family: Fonts.forWeight(font.weight, pal.fam); font.pixelSize: 12 }
                            MouseArea { anchors.fill: parent; onClicked: { root.wpQuery = ""; wpGrid.forceActiveFocus(); } }
                        }
                    }
                    Text {
                        id: wpSub
                        anchors.left: wpSearchBox.right; anchors.leftMargin: 14
                        anchors.right: parent.right; anchors.rightMargin: 22
                        y: 54; height: 28
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: root.wpStatus !== "" ? root.wpStatus
                              : (root.wpShown.length + (root.wpShown.length === 1 ? " image" : " images")
                                 + ((root.wallpaperFavs || []).length > 0 ? "  \u00b7  \u2605 first" : "")
                                 + "  \u00b7  Type to search, Enter apply, Space favourite")
                        color: pal.fg3
                        font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 11
                    }

                    // ── grid ──
                    GridView {
                        id: wpGrid
                        x: 16; y: 94
                        width: parent.width - 38; height: parent.height - 94 - 14
                        clip: true
                        readonly property int cols: Math.max(2, Math.floor(width / 210))
                        cellWidth: Math.floor(width / cols)
                        cellHeight: Math.round(cellWidth * 0.64)
                        model: root.wpShown
                        currentIndex: 0
                        keyNavigationEnabled: true
                        highlightMoveDuration: 0
                        Keys.onPressed: event => {
                            var ok = currentIndex >= 0 && currentIndex < root.wpShown.length;
                            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && ok) {
                                root.wpApply(root.wpShown[currentIndex].path); root.wpOpen = false; event.accepted = true;
                            } else if (event.key === Qt.Key_Space && ok) {
                                root.wpToggleFav(root.wpShown[currentIndex].path); event.accepted = true;
                            } else if (event.key === Qt.Key_Slash || (event.text.length === 1 && event.text > " " && event.text !== "\u007f"
                                       && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)))) {
                                // typing anywhere starts a search
                                wpSearch.forceActiveFocus();
                                if (event.key !== Qt.Key_Slash) root.wpQuery += event.text;
                                wpSearch.cursorPosition = wpSearch.length;
                                event.accepted = true;
                            }
                        }

                        delegate: Item {
                            id: wc
                            required property int index
                            required property var modelData
                            width: wpGrid.cellWidth; height: wpGrid.cellHeight
                            readonly property bool sel: wpGrid.currentIndex === index
                            readonly property bool cur: modelData.video ? root.wallpaperVideo === modelData.path
                                                                        : (root.wallpaperVideo === "" && root.wallpaperPath === modelData.path)
                            Item {
                                id: wcBox
                                anchors.fill: parent
                                anchors.margins: 5
                                Item {
                                    id: wcMask
                                    anchors.fill: parent
                                    visible: false
                                    layer.enabled: true
                                    layer.smooth: true
                                    Rectangle { anchors.fill: parent; radius: 12; color: "black" }
                                }
                                Item {
                                    anchors.fill: parent
                                    layer.enabled: true
                                    layer.smooth: true
                                    layer.effect: MultiEffect {
                                        maskEnabled: true
                                        maskSource: wcMask
                                        maskThresholdMin: 0.5
                                        maskSpreadAtMin: 1.0
                                    }
                                    Rectangle { anchors.fill: parent; color: pal.btnOff }
                                    Image {
                                        anchors.fill: parent
                                        source: root.fileUrl(wc.modelData.video ? wc.modelData.thumb : wc.modelData.path)
                                        sourceSize.width: 420
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: true
                                        smooth: true
                                    }
                                    Rectangle {
                                        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                        height: 26
                                        color: Qt.rgba(0, 0, 0, 0.5)
                                        opacity: (wc.sel || wcMa.containsMouse) ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 120 } }
                                        Text {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10; anchors.rightMargin: 36
                                            verticalAlignment: Text.AlignVCenter
                                            elide: Text.ElideRight
                                            text: wc.modelData.name
                                            color: "white"
                                            font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 11
                                        }
                                    }
                                    // animated wallpaper: its looping preview plays while hovered or selected
                                    Loader {
                                        anchors.fill: parent
                                        active: wc.modelData.video && wc.modelData.preview !== "" && (wcMa.containsMouse || wc.sel) && root.wpOpen
                                        sourceComponent: AnimatedImage {
                                            source: root.fileUrl(wc.modelData.preview)
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            cache: false
                                            playing: true
                                        }
                                    }
                                    Rectangle {
                                        visible: wc.modelData.video
                                        x: 8; y: 8
                                        width: wcBadge.implicitWidth + 14; height: 20; radius: 10
                                        color: Qt.rgba(0, 0, 0, 0.5)
                                        Text {
                                            id: wcBadge
                                            anchors.centerIn: parent
                                            text: I18n.tr("\u25B6  Animated")
                                            color: "white"
                                            font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 10; font.weight: Font.DemiBold
                                        }
                                    }
                                }
                                // selection / current-wallpaper ring
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 12
                                    color: "transparent"
                                    border.width: wc.sel ? 3 : (wc.cur ? 2 : 0)
                                    border.color: wc.sel ? pal.accent : "white"
                                }
                                MouseArea {
                                    id: wcMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onPositionChanged: wpGrid.currentIndex = wc.index      // real mouse movement only, so the keyboard keeps control
                                    onClicked: { root.wpApply(wc.modelData.path); root.wpOpen = false; }
                                }
                                // favourite star
                                Rectangle {
                                    anchors.right: parent.right; anchors.top: parent.top
                                    anchors.margins: 7
                                    width: 26; height: 26; radius: 13
                                    visible: wc.modelData.fav || wcMa.containsMouse || wcStarMa.containsMouse
                                    color: Qt.rgba(0, 0, 0, wcStarMa.containsMouse ? 0.62 : 0.45)
                                    Text {
                                        anchors.centerIn: parent
                                        text: wc.modelData.fav ? "\u2605" : "\u2606"
                                        color: wc.modelData.fav ? "#ffd60a" : "white"
                                        font.family: Fonts.forWeight(font.weight, pal.fam); font.pixelSize: 15
                                    }
                                    MouseArea {
                                        id: wcStarMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.wpToggleFav(wc.modelData.path)
                                    }
                                }
                            }
                        }
                    }
                    // ── scrollbar ──
                    Item {
                        id: wpTrack
                        visible: wpGrid.contentHeight > wpGrid.height + 1
                        x: parent.width - 16; y: wpGrid.y + 2
                        width: 10; height: wpGrid.height - 4
                        readonly property real ratio: Math.min(1, wpGrid.visibleArea.heightRatio)
                        readonly property real thumbH: Math.max(32, ratio * height)
                        readonly property real maxY: Math.max(1, height - thumbH)
                        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 4; height: parent.height; radius: 2; color: pal.track; opacity: 0.6 }
                        MouseArea {                      // click the track to jump
                            anchors.fill: parent
                            onPressed: mouse => wpTrack.jumpTo(mouse.y - wpTrack.thumbH / 2)
                        }
                        function jumpTo(ty) {
                            var f = Math.max(0, Math.min(1, ty / wpTrack.maxY));
                            wpGrid.contentY = wpGrid.originY + f * Math.max(0, wpGrid.contentHeight - wpGrid.height);
                        }
                        Rectangle {
                            id: wpThumb
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: wpThumbMa.containsMouse || wpThumbMa.drag.active ? 7 : 5
                            height: wpTrack.thumbH
                            radius: width / 2
                            color: wpThumbMa.drag.active ? pal.fg2 : pal.fg3
                            Behavior on width { NumberAnimation { duration: 100 } }
                            Binding {
                                target: wpThumb; property: "y"
                                when: !wpThumbMa.drag.active
                                value: (1 - wpTrack.ratio) > 0.0001 ? Math.max(0, Math.min(wpTrack.maxY, wpGrid.visibleArea.yPosition / (1 - wpTrack.ratio) * wpTrack.maxY)) : 0
                            }
                            MouseArea {
                                id: wpThumbMa
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                drag.target: wpThumb
                                drag.axis: Drag.YAxis
                                drag.minimumY: 0
                                drag.maximumY: wpTrack.maxY
                                onPositionChanged: if (drag.active) wpTrack.jumpTo(wpThumb.y)
                            }
                        }
                    }
                    Text {
                        visible: root.wpShown.length === 0
                        anchors.centerIn: parent
                        width: parent.width - 80
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: root.wpQuery !== "" ? I18n.tr("No wallpapers match \u201c") + root.wpQuery + "\u201d"
                              : I18n.tr("No images in ") + root.wpDirEff + I18n.tr("\nDrop some in, or pick another folder with Choose\u2026")
                        color: pal.fg2
                        font.family: root.fontForWeight(font.weight, pal.fam); font.pixelSize: 13
                    }
                }
            }
        }

        // ═════════ Spotlight lives in its OWN layer (namespace "macspot") ═════════
        // Hyprland blurs a whole layer or none of it, so Spotlight has its own layer: put the blur layerrule on
        // "macspot" and leave "macbar" without blur.
        PanelWindow {
            id: spotWin
            screen: perScreen.modelData
            // The layer stays mapped: creating / destroying it on every open restarted the glass's window captures and
            // Hyprland's layer animation, which is what made Spotlight flicker or vanish. Closed = invisible + click-through.
            visible: root.spotlightEnabled
            readonly property bool openish: ui.pop === "spot" || spot.vis > 0
            onOpenishChanged: root.popCount += (openish ? 1 : -1)     // keeps the window-geometry poller running while Spotlight is open
            mask: Region { item: spotWin.openish ? spotRoot : spotNoInput }
            Item { id: spotNoInput; width: 0; height: 0 }
            // Auto contrast, live: while a panel (menu, Control Center, Spotlight) is open on this screen, the area around it is
            // re-measured, so opening / closing / switching apps behind it flips it light <-> dark. Windows opening or closing
            // trigger a measurement at once; otherwise it polls.
            function panelRect() {
                if (ui.pop === "spot") return Qt.rect(perScreen.modelData.x + spot.x, perScreen.modelData.y + spot.y, spot.width, spot.height);
                var r = ui.glassRect;
                if (r.width <= 128) return null;
                return Qt.rect(perScreen.modelData.x + r.x + 64, perScreen.modelData.y + r.y + 64, r.width - 128, r.height - 128);
            }
            function measureLive() {
                if (!root.autoContrast || ui.pop === "" || !ui.toastScreen) return;
                var pr = panelRect();
                if (pr) root.measureAround(perScreen.modelData, pr, false);
            }
            Timer { interval: 700; repeat: true; running: root.autoContrast && ui.pop !== "" && ui.toastScreen; onTriggered: spotWin.measureLive() }
            Timer { id: liveKick; interval: 180; onTriggered: spotWin.measureLive() }
            Connections { target: root; function onGlassClientsChanged() { if (ui.pop !== "") liveKick.restart(); } }
            anchors { left: true; right: true; top: true; bottom: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.namespace: "macspot"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: ui.pop === "spot" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            Item {
                id: spotRoot
                anchors.fill: parent

                Loader {
                    id: spotBackdrop
                    active: root.liquidActive          // stays loaded (warm) so the window opens on ready-made frames
                    sourceComponent: backdropComp
                    onLoaded: { item.hostShown = Qt.binding(function () { return !root.gaming; });
                                item.region = Qt.binding(function () { return Qt.rect(spot.x - 128, spot.y - 128, spot.width + 256, spot.height + 256); }); }
                }

                // a clipboard entry being dragged out of Spotlight
                Item {
                    id: clipGhost
                    z: 50
                    property var en: null
                    property real px: 0
                    property real py: 0
                    property real zoom: 1
                    property real wob: 0
                    property real homeX: 0
                    property real homeY: 0
                    visible: en !== null
                    width: 220; height: en && en.kind === "image" ? 150 : 64
                    x: px - width / 2; y: py - height / 2
                    scale: zoom; rotation: wob
                    function start(e) { en = e; zoom = 1.06; opacity = 1; homeX = px; homeY = py; wiggleClip.restart(); }
                    function drop(out) {
                        wiggleClip.stop();
                        if (out) { clipLaunch.restart(); }
                        else { clipBack.restart(); }
                    }
                    Rectangle {
                        anchors.fill: parent; radius: 14
                        color: root.panelDarkMode ? Qt.rgba(0.16, 0.16, 0.18, 0.92) : Qt.rgba(0.97, 0.97, 0.98, 0.95)
                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.18)
                    }
                    Image {
                        visible: clipGhost.en && clipGhost.en.kind === "image"
                        anchors.fill: parent; anchors.margins: 6
                        source: clipGhost.en && clipGhost.en.thumb ? clipGhost.en.thumb : ""
                        fillMode: Image.PreserveAspectCrop; asynchronous: true
                    }
                    Text {
                        visible: !(clipGhost.en && clipGhost.en.kind === "image")
                        anchors.fill: parent; anchors.margins: 12
                        text: clipGhost.en ? clipGhost.en.text : ""
                        wrapMode: Text.Wrap; elide: Text.ElideRight; maximumLineCount: 2
                        color: root.panelTextWhite ? "white" : "#1d1d1f"; font.family: root.fontForWeight(font.weight, root.fontFamily); font.pixelSize: 13
                    }
                    SequentialAnimation {
                        id: wiggleClip; loops: Animation.Infinite
                        NumberAnimation { target: clipGhost; property: "wob"; to: 3; duration: 90; easing.type: Easing.InOutSine }
                        NumberAnimation { target: clipGhost; property: "wob"; to: -3; duration: 180; easing.type: Easing.InOutSine }
                        NumberAnimation { target: clipGhost; property: "wob"; to: 0; duration: 90; easing.type: Easing.InOutSine }
                    }
                    SequentialAnimation {
                        id: clipLaunch
                        ParallelAnimation {
                            NumberAnimation { target: clipGhost; property: "zoom"; to: 2.2; duration: 460; easing.type: Easing.OutQuint }
                            NumberAnimation { target: clipGhost; property: "opacity"; to: 0; duration: 460; easing.type: Easing.OutCubic }
                            NumberAnimation { target: clipGhost; property: "wob"; to: 0; duration: 200 }
                        }
                        ScriptAction { script: { var e = clipGhost.en; clipGhost.en = null; ui.pop = ""; if (e) root.clipOpen(e); } }
                    }
                    SequentialAnimation {
                        id: clipBack
                        ParallelAnimation {
                            NumberAnimation { target: clipGhost; property: "px"; to: clipGhost.homeX; duration: 380; easing.type: Easing.OutQuint }
                            NumberAnimation { target: clipGhost; property: "py"; to: clipGhost.homeY; duration: 380; easing.type: Easing.OutQuint }
                            NumberAnimation { target: clipGhost; property: "wob"; to: 0; duration: 200 }
                            NumberAnimation { target: clipGhost; property: "opacity"; to: 0; duration: 380; easing.type: Easing.InCubic }
                        }
                        ScriptAction { script: clipGhost.en = null }
                    }
                }

                // click outside Spotlight closes it
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    onPressed: ui.pop = ""
                }

                // Backdrop capture + blur for Spotlight's glass. Deliberately NOT inside `spot`: as children they inherited
                // spot's opacity while it faded, so the glass refracted a half-transparent backdrop and turned into a milky
                // blob mid-fade (the fade looked broken). Out here they always produce the real backdrop.
                readonly property rect spCapLocal: Qt.rect(spot.x - 128, spot.y - 128, spot.width + 256, 684)
                readonly property real spCapS: root.barPopupScale
                readonly property rect spCapScreen: {
                    var cx = spot.x + spot.width / 2, cy = spot.y + spot.height / 2, k = spCapS, l = spCapLocal;
                    return Qt.rect(cx + (l.x - cx) * k, cy + (l.y - cy) * k, l.width * k, l.height * k);
                }
                ShaderEffectSource {
                    id: spSrc
                    sourceItem: spotBackdrop.item     // wallpaper + live windows, captured inside this layer
                    hideSource: true
                    live: spotWin.openish
                    visible: false
                    // The Spotlight is drawn scaled by the UI scale around its centre, but the glass shaders map pixels in its UNSCALED
                    // coordinates (spg.srcRect = spCapLocal). So the capture (spCapScreen) is where that same region really is on screen.
                    sourceRect: spotRoot.spCapScreen
                }
                MultiEffect {
                    id: spBlurFx
                    source: spSrc
                    width: spSrc.sourceRect.width; height: spSrc.sourceRect.height
                    blurEnabled: true
                    blurMax: 64                              // same single-pass blur the Control Center / popovers use
                    blur: Math.min(1.0, (spg.blur * spg.blurMul) * 1.4 / 64.0)
                    autoPaddingEnabled: false
                    visible: false
                }
                ShaderEffectSource {
                    id: spBlur
                    sourceItem: spBlurFx
                    live: spotWin.openish
                    mipmap: true                    // liquidglass.frag samples this with textureLod(): it needs mip levels (see its header)
                    visible: false
                }
                GlassCtx {
                    id: spg
                    src: spBlur
                    srcRect: spotRoot.spCapLocal
                    frame: spotRoot
                    liquid: root.liquidActive
                    shaderUrl: root.glassShaderUrl
                    dark: root.panelDarkMode
                    tint: root.glassOpacity
                    strength: root.glassLiquid               // full refraction, like the Dock / Control Center
                    rim: root.glassRim                       // same wallpaper-coloured rim + border line as the top-bar menus
                    rimTint: 1
                    ringW: 0.9
                    whiteEdge: false
                    grain: root.glassGrain
                    blur: 15                                // Spotlight has its own blur: it ignores the global blur slider
                    blurMul: 10.0                   // strong smooth blur (two stacked Gaussian passes); lower to see more refraction, raise to frost more
                    debug: root.glassDebug
                    onFailed: root.glassState = "failed"
                }

                // ═════════ Spotlight (Liquid Glass) ═════════
                Item {
                    id: spot
                    z: 10
                    width: 640
                    readonly property var curPanel: ui.spMode === "apps" ? appsPanel : (ui.spMode === "clip" ? clipPanel : emojiPanel)
                    height: ui.spFull ? curPanel.height : (resPanel.visible ? resPanel.y + resPanel.height : spRow.height)
                    x: Math.round((spotRoot.width - width) / 2)
                    // the search pill sits a little above the vertical centre of the screen (0.4 of the height; 0.5 = dead centre); the Applications panel centres itself instead
                    y: Math.round(spotRoot.height * 0.4 - (ui.spFull ? curPanel.height / 2 : 24))
                    Behavior on y { enabled: spot.vis > 0.99; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    // opens with a springy pop; dismiss: quick fade + shrink
                    property real vis: 0
                    opacity: vis
                    visible: vis > 0.001
                    readonly property real uiS: root.barPopupScale      // Settings → Menu Bar → UI scale
                    scale: uiS * (ui.spCalm ? 0.98 : 0.97)
                    transformOrigin: Item.Center
                    states: State {
                        name: "open"
                        when: ui.pop === "spot"
                        PropertyChanges { target: spot; vis: 1; scale: spot.uiS }
                    }
                    transitions: [
                        Transition {
                            from: ""; to: "open"
                            ParallelAnimation {
                                // opening: 220 ms OutCubic, opacity 0 -> 1 and scale 0.97 -> 1 (no bounce: the surface is revealed, it doesn't fly in)
                                NumberAnimation { property: "vis"; duration: root.reduceMotion ? 0 : 220; easing.type: Easing.OutCubic }
                                NumberAnimation { property: "scale"; duration: root.reduceMotion ? 0 : 220; easing.type: Easing.OutCubic }
                            }
                        },
                        Transition {
                            from: "open"; to: ""
                            ParallelAnimation {
                                // closing: faster than opening (160 ms InCubic), opacity 1 -> 0 and scale 1 -> 0.98
                                NumberAnimation { property: "vis"; duration: root.reduceMotion ? 0 : 160; easing.type: Easing.InCubic }
                                NumberAnimation { property: "scale"; to: spot.uiS * 0.98; duration: root.reduceMotion ? 0 : 160; easing.type: Easing.InCubic }
                            }
                        }
                    ]

                    Timer { id: spHoverClear; interval: 350; onTriggered: ui.spHoverLabel = "" }
                    Timer {
                        id: spFocusTimer
                        interval: 60
                        onTriggered: (ui.spMode === "apps" ? appsInput : (ui.spMode === "clip" ? clipInput : (ui.spMode === "emoji" ? emojiInput : spInput))).forceActiveFocus()
                    }

                    // ── search pill + the five round buttons ──
                    Row {
                        id: spRow
                        spacing: 12
                        opacity: !ui.spFull ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                        Item {
                            id: spPill
                            width: spot.width - 5 * 60
                            height: 48
                            GGlass { anchors.fill: parent; gx: spg; cornerR: 24; thickness: 22; strengthMul: 1.0; shadowAmt: 0.08 }
                            HoverHandler { id: pillHover }
                            ContourGlow { cornerR: 24; hovered: pillHover.hovered; at: pillHover.point.position; glowColor: root.panelDarkMode ? "white" : root.accent }
                            MenuBorder { amount: 0.5; anchors.fill: parent; cornerR: 24; dark: root.panelDarkMode; tint: root.menuBorderColor }
                            Glyph {
                                x: 18; anchors.verticalCenter: parent.verticalCenter
                                width: 18; height: 18
                                kind: "search"; color: panelPal.fg2
                            }
                            // placeholder: blur-morphs between "Spotlight Search" and the hovered button's name
                            MorphText {
                                x: spInput.x + 3
                                width: spInput.width
                                anchors.verticalCenter: parent.verticalCenter
                                visible: spInput.text === ""
                                animateWidth: false
                                duration: 460
                                blurMax: 48
                                text: ui.spHoverLabel !== "" ? ui.spHoverLabel : I18n.tr("Spotlight Search")
                                color: panelPal.fg2
                                font.family: root.fontForWeight(font.weight, panelPal.fam); font.pixelSize: 17
                                elide: Text.ElideRight
                            }
                            TextInput {
                                id: spInput
                                x: 46
                                width: parent.width - 46 - 44          // constant width: the field never changes size while typing
                                anchors.verticalCenter: parent.verticalCenter
                                clip: true
                                color: panelPal.fg
                                selectionColor: root.accent
                                selectedTextColor: "white"
                                font.family: root.fontForWeight(font.weight, panelPal.fam); font.pixelSize: 17
                                horizontalAlignment: /[\u0590-\u08ff]/.test(text) ? Text.AlignRight : Text.AlignLeft
                                onTextChanged: { if (!ui.spFull) { ui.spQuery = text; ui.spSel = 0; ui.armed = ""; if (/^(file|find)\s+/i.test(text)) root.updateFileSearch(text.replace(/^(file|find)\s+/i, "").trim()); } }
                                Keys.onPressed: event => ui.spKey(event)
                            }
                            // clear button: appears once there is a query; keeps focus in the field
                            Item {
                                id: spClear
                                anchors.right: parent.right; anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22; height: 22
                                opacity: spInput.text !== "" && !ui.spFull ? 1 : 0
                                visible: opacity > 0
                                scale: 0.8 + 0.2 * opacity
                                Behavior on opacity { NumberAnimation { duration: root.reduceMotion ? 0 : 140; easing.type: Easing.OutCubic } }
                                Rectangle {
                                    anchors.fill: parent; radius: 11
                                    color: root.panelDarkMode ? Qt.rgba(1, 1, 1, clearMa.containsMouse ? 0.24 : 0.14) : Qt.rgba(0, 0, 0, clearMa.containsMouse ? 0.16 : 0.09)
                                    Behavior on color { ColorAnimation { duration: root.reduceMotion ? 0 : 120 } }
                                }
                                Glyph { anchors.centerIn: parent; width: 14; height: 14; kind: "close"; color: panelPal.fg2 }
                                MouseArea {
                                    id: clearMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: { spInput.text = ""; spInput.forceActiveFocus(); }
                                }
                            }
                        }
                        Repeater {
                            model: [
                                { k: "appstore", id: "apps", label: I18n.tr("Apps") }, { k: "folder", id: "files", label: I18n.tr("Files") },
                                { k: "layers", id: "actions", label: I18n.tr("Actions") }, { k: "clipboard", id: "clip", label: I18n.tr("Clipboard") }, { k: "smile", id: "emoji", label: I18n.tr("Emoji") }
                            ]
                            delegate: CCBtn {
                                id: navBtn
                                required property var modelData
                                required property int index
                                t: pal; gx: spg
                                d: 48
                                matchMenuBorder: true
                                // entrance when Spotlight opens: fade + scale 0.88 -> 1 + rise 4 px, 24 ms stagger (never blocks clicks / keys)
                                property real inT: 1
                                opacity: inT
                                transform: [
                                    Translate { y: (1 - navBtn.inT) * 4 },
                                    Scale { origin.x: navBtn.d / 2; origin.y: navBtn.d / 2; xScale: 0.88 + 0.12 * navBtn.inT; yScale: 0.88 + 0.12 * navBtn.inT }
                                ]
                                SequentialAnimation {
                                    id: navEnter
                                    PropertyAction { target: navBtn; property: "inT"; value: 0 }
                                    PauseAnimation { duration: navBtn.index * 24 }
                                    NumberAnimation { target: navBtn; property: "inT"; to: 1; duration: 200; easing.type: Easing.OutCubic }
                                }
                                Connections {
                                    target: ui
                                    function onPopChanged() { if (ui.pop === "spot" && !root.reduceMotion && !ui.spCalm) navEnter.restart(); }
                                }
                                bounce: true
                                shadow: 0.18
                                kind: modelData.k
                                on: ui.spMode === modelData.id
                                HoverHandler {
                                    id: btnHover
                                    // crossing the gap to the next button must not flash "Spotlight Search": only go back
                                    // to it once the pointer has been off every button for 0.35 s
                                    onHoveredChanged: {
                                        if (hovered) { spHoverClear.stop(); ui.spHoverLabel = modelData.label; }
                                        else if (ui.spHoverLabel === modelData.label) spHoverClear.restart();
                                    }
                                }
                                ContourGlow { cornerR: 24; hovered: btnHover.hovered; at: btnHover.point.position; glowColor: root.panelDarkMode ? "white" : root.accent }
                                onClicked: {
                                    if (modelData.id === "apps") ui.spSetMode(ui.spMode === "apps" ? "home" : "apps");
                                    else if (modelData.id === "actions") ui.spSetMode(ui.spMode === "actions" ? "home" : "actions");
                                    else if (modelData.id === "files") {
                                        // Files = file search: prefill the "file " prefix in the Spotlight field (click again to clear)
                                        if (ui.spMode !== "home") ui.spSetMode("home");
                                        if (/^(file|find)\s/i.test(spInput.text)) { spInput.text = ""; }
                                        else { spInput.text = "file "; spInput.cursorPosition = spInput.text.length; }
                                        spInput.forceActiveFocus();
                                    }
                                    else if (modelData.id === "clip") ui.spSetMode(ui.spMode === "clip" ? "home" : "clip");
                                    else ui.spSetMode(ui.spMode === "emoji" ? "home" : "emoji");
                                }
                            }
                        }
                    }

                    // ── results under the pill ──
                    Item {
                        id: resPanel
                        y: spRow.height + 10
                        width: spot.width
                        readonly property var items: ui.spFull ? [] : ui.spResults      // clipboard / emoji / apps have their own panels
                        property int keep: 1                         // last non-empty row count, so the panel shrinks while it fades out
                        onItemsChanged: if (items.length > 0) keep = items.length
                        onSelIdxChanged: {
                            // keep the selected row inside the 5-row window (pointer hover must not scroll)
                            if (ui.spHover) { ui.spHover = false; return; }
                            var top = selIdx * 46, vh = resFlick.height;
                            if (top < resFlick.contentY) resFlick.contentY = top;
                            else if (top + 46 > resFlick.contentY + vh) resFlick.contentY = top + 46 - vh;
                        }
                        readonly property int selIdx: Math.max(0, Math.min(ui.spSel, items.length - 1))
                        opacity: (!ui.spFull && items.length > 0) ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: root.reduceMotion ? 0 : 160; easing.type: Easing.OutCubic } }
                        // file search shows 5 rows at a time; more results scroll
                        readonly property int maxRows: /^(file|find)\s+/i.test(ui.spQuery) ? 5 : 99
                        height: Math.min(items.length > 0 ? items.length : keep, maxRows) * 46 + 16
                        // expands / contracts downward only: the pill above never moves
                        Behavior on height { NumberAnimation { duration: root.reduceMotion ? 0 : 220; easing.type: Easing.OutCubic } }
                        GGlass { anchors.fill: parent; gx: spg; cornerR: 26; thickness: 26; strengthMul: 1.0; shadowAmt: 0.10 }
                        MenuBorder { amount: 0.5; anchors.fill: parent; cornerR: 26; dark: root.panelDarkMode; tint: root.menuBorderColor }
                        Item {
                            x: 8; y: 8
                            width: parent.width - 16
                            height: parent.height - 16
                            clip: true
                        Flickable {
                            id: resFlick
                            anchors.fill: parent
                            contentWidth: width
                            contentHeight: resPanel.items.length * 46
                            boundsBehavior: Flickable.StopAtBounds
                            interactive: contentHeight > height
                            flickableDirection: Flickable.VerticalFlick
                            Behavior on contentY { enabled: !resFlick.moving && !resFlick.dragging; NumberAnimation { duration: root.reduceMotion ? 0 : 120; easing.type: Easing.OutCubic } }
                            Rectangle {
                                y: resPanel.selIdx * 46
                                width: parent.width; height: 46; radius: 16
                                color: (resPanel.items[resPanel.selIdx] && resPanel.items[resPanel.selIdx].confirm === true
                                        && ui.armed === resPanel.items[resPanel.selIdx].title) ? "#FF453A" : root.accent
                                Behavior on y { NumberAnimation { duration: root.reduceMotion ? 0 : 120; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: root.reduceMotion ? 0 : 120 } }
                            }
                        Column {
                            width: parent.width
                            Repeater {
                                model: resPanel.items
                                delegate: Item {
                                    id: rr
                                    required property var modelData
                                    required property int index
                                    readonly property string ico: (modelData && modelData.icon) ? String(modelData.icon) : ""
                                    readonly property bool twoLine: !!(modelData && modelData.path)
                                    readonly property bool sel: index === Math.min(ui.spSel, resPanel.items.length - 1)
                                    readonly property bool armedNow: modelData.confirm === true && ui.armed === modelData.title
                                    width: parent.width
                                    height: 46
                                    // Entrance: fade + rise 4 px, 16 ms stagger. Delegates are rebuilt on every keystroke, so this only
                                    // plays while the results panel itself is still (almost) invisible, i.e. when results first appear.
                                    property real enterY: 0
                                    transform: Translate { y: rr.enterY }
                                    Component.onCompleted: {
                                        if (!root.reduceMotion && resPanel.opacity < 0.5) { rr.opacity = 0; rr.enterY = 4; rowEnter.start(); }
                                    }
                                    SequentialAnimation {
                                        id: rowEnter
                                        PauseAnimation { duration: Math.min(rr.index, 7) * 16 }
                                        ParallelAnimation {
                                            NumberAnimation { target: rr; property: "opacity"; to: 1; duration: 160; easing.type: Easing.OutCubic }
                                            NumberAnimation { target: rr; property: "enterY"; to: 0; duration: 160; easing.type: Easing.OutCubic }
                                        }
                                    }
                                    Item {
                                        x: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 30; height: 30
                                        Image {
                                            visible: rr.ico !== ""
                                            anchors.fill: parent
                                            source: rr.ico
                                            sourceSize: Qt.size(64, 64)
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                            smooth: true
                                        }
                                        Glyph {
                                            visible: rr.ico === ""
                                            anchors.centerIn: parent
                                            width: 20; height: 20
                                            kind: (rr.modelData && rr.modelData.glyph) ? rr.modelData.glyph : ""
                                            color: rr.sel ? "white" : panelPal.fg
                                        }
                                    }
                                    Text {
                                        x: 54
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.verticalCenterOffset: rr.twoLine ? -8 : 0
                                        width: rr.twoLine ? parent.width - 54 - 16
                                               : parent.width - 54 - 16 - Math.min(rowSub.implicitWidth, parent.width * 0.4) - 12
                                        elide: Text.ElideRight
                                        text: rr.armedNow ? I18n.tr("Press Return again to confirm") : (rr.modelData ? rr.modelData.title : "")
                                        color: rr.sel ? "white" : panelPal.fg
                                        font.family: root.fontForWeight(font.weight, panelPal.fam); font.pixelSize: 14
                                    }
                                    Text {
                                        id: rowSub
                                        // file results: the path sits on its own line under the name, so long names/paths never overlap
                                        x: rr.twoLine ? 54 : parent.width - 16 - width
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.verticalCenterOffset: rr.twoLine ? 9 : 0
                                        width: rr.twoLine ? parent.width - 54 - 16 : Math.min(implicitWidth, parent.width * 0.4)
                                        elide: rr.twoLine ? Text.ElideMiddle : Text.ElideRight
                                        text: rr.modelData ? rr.modelData.sub : ""
                                        color: rr.sel ? Qt.rgba(1, 1, 1, 0.8) : panelPal.fg2
                                        font.family: root.fontForWeight(font.weight, panelPal.fam); font.pixelSize: rr.twoLine ? 11 : 12
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onEntered: { if (ui.spSel !== rr.index) { ui.spHover = true; ui.spSel = rr.index; } }
                                        onClicked: ui.spActivate(rr.index)
                                    }
                                }
                            }
                        }
                        }
                        LiquidScrollBar { flick: resFlick; compact: true; alwaysVisible: true; anchors.right: parent.right; anchors.rightMargin: 2; anchors.top: parent.top; anchors.topMargin: 6; anchors.bottom: parent.bottom; anchors.bottomMargin: 6; dark: root.panelDarkMode }
                        }
                    }

                    // ── Clipboard history panel (macOS Tahoe style) ──
                    Item {
                        id: clipPanel
                        opacity: ui.spMode === "clip" ? 1 : 0
                        visible: opacity > 0
                        scale: ui.spMode === "clip" ? 1 : 0.96
                        transformOrigin: Item.Top
                        Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        width: spot.width
                        readonly property var items: ui.spMode === "clip" ? ui.spResults : []
                        readonly property int rowH: 56
                        readonly property int shown: Math.min(items.length, 7)
                        readonly property string emptyTitle: root.clipState === "missing" ? "Clipboard history isn't set up"
                            : (!root.clipHistory ? "Clipboard history is off"
                            : (root.clipLoading && root.clipEntries.length === 0 ? "Loading\u2026"
                            : (ui.spQuery.trim() !== "" ? "No Results" : "Nothing copied yet")))
                        readonly property string emptySub: root.clipState === "missing" ? "Install cliphist and wl-clipboard, then open this tab again"
                            : (!root.clipHistory ? "Turn it on in System Settings \u2192 Menu Bar"
                            : (ui.spQuery.trim() === "" && !root.clipLoading ? "Copy some text or an image and it will show up here" : ""))
                        height: 64 + (items.length > 0 ? shown * rowH + 14 : 118)
                        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        GGlass { anchors.fill: parent; gx: spg; cornerR: 32; thickness: 34; strengthMul: 1.0; shadowAmt: 0.22 }
                        MenuBorder { amount: 0.5; anchors.fill: parent; cornerR: 32; dark: root.panelDarkMode; tint: root.menuBorderColor }

                        Item {
                            id: clipHeader
                            x: 20
                            width: parent.width - 40
                            height: 64
                            Rectangle {
                                id: clipChip
                                anchors.verticalCenter: parent.verticalCenter
                                width: 34; height: 34; radius: 10
                                color: root.accent
                                Glyph { anchors.centerIn: parent; width: 20; height: 20; kind: "clipboard"; color: "white" }
                            }
                            Text {
                                id: clipLabel
                                x: 46
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Clipboard")
                                color: panelPal.fg
                                font.family: root.fontForWeight(font.weight, panelPal.fam); font.pixelSize: 24; font.weight: Font.Medium
                            }
                            TextInput {
                                id: clipInput
                                x: clipLabel.x + clipLabel.width + 14
                                width: parent.width - x - 48
                                anchors.verticalCenter: parent.verticalCenter
                                clip: true
                                color: panelPal.fg
                                selectionColor: root.accent
                                selectedTextColor: "white"
                                font.family: root.fontForWeight(font.weight, panelPal.fam); font.pixelSize: 24
                                onTextChanged: { if (ui.spMode === "clip") { ui.spQuery = text; ui.spSel = 0; } }
                                Keys.onPressed: event => ui.spKey(event)
                            }
                            CCBtn {
                                t: pal; gx: spg
                                d: 34
                                bounce: true
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                kind: "dots"
                                on: ui.clipMenu
                                onClicked: ui.clipMenu = !ui.clipMenu
                            }
                        }

                        ListView {
                            id: clipListView
                            x: 8; y: 64
                            width: parent.width - 16
                            height: clipPanel.shown * clipPanel.rowH
                            visible: clipPanel.items.length > 0
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            model: clipPanel.items
                            Connections {
                                target: ui
                                function onSpSelChanged() {
                                    if (ui.spHover) { ui.spHover = false; return; }
                                    if (ui.spMode === "clip" && clipPanel.items.length > 0)
                                        clipListView.positionViewAtIndex(Math.min(ui.spSel, clipPanel.items.length - 1), ListView.Contain);
                                }
                            }
                            delegate: Item {
                                id: cr
                                required property var modelData
                                required property int index
                                readonly property bool sel: index === Math.min(ui.spSel, clipPanel.items.length - 1)
                                width: ListView.view.width
                                height: clipPanel.rowH
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.topMargin: 2; anchors.bottomMargin: 2
                                    radius: 16
                                    color: root.accent
                                    opacity: cr.sel ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 90 } }
                                }
                                Item {
                                    x: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 36; height: 36
                                    Rectangle {
                                        visible: cr.modelData.kind === "text" || cr.modelData.kind === "url"
                                        anchors.fill: parent
                                        radius: 10
                                        color: cr.sel ? Qt.rgba(1, 1, 1, 0.22) : (root.panelDarkMode ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06))
                                        Glyph {
                                            anchors.centerIn: parent
                                            width: 20; height: 20
                                            kind: cr.modelData.kind === "url" ? "link" : "doc"
                                            color: cr.sel ? "white" : panelPal.fg2
                                        }
                                    }
                                    Rectangle {
                                        visible: cr.modelData.kind === "color"
                                        anchors.fill: parent
                                        radius: 10
                                        color: cr.modelData.kind === "color" ? cr.modelData.color : "transparent"
                                        border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.25)
                                    }
                                    Item {
                                        visible: cr.modelData.kind === "image"
                                        anchors.fill: parent
                                        Rectangle { anchors.fill: parent; radius: 10; color: root.panelDarkMode ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06) }
                                        Image {
                                            anchors.fill: parent
                                            source: cr.modelData.kind === "image" ? cr.modelData.thumb : ""
                                            sourceSize: Qt.size(72, 72)
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            layer.enabled: true
                                            layer.effect: MultiEffect {
                                                maskEnabled: true
                                                maskSource: thMask
                                                maskThresholdMin: 0.5
                                                maskSpreadAtMin: 1.0
                                            }
                                        }
                                        Item {
                                            id: thMask
                                            anchors.fill: parent
                                            visible: false
                                            layer.enabled: true
                                            Rectangle { anchors.fill: parent; radius: 10; color: "black" }
                                        }
                                    }
                                }
                                Text {
                                    x: 62; y: 9
                                    width: parent.width - 62 - 56
                                    elide: Text.ElideRight
                                    text: cr.modelData ? cr.modelData.title : ""
                                    color: cr.sel ? "white" : panelPal.fg
                                    font.family: root.fontForWeight(font.weight, panelPal.fam); font.pixelSize: 14
                                }
                                Text {
                                    x: 62; y: 31
                                    width: parent.width - 62 - 56
                                    elide: Text.ElideRight
                                    text: cr.modelData ? cr.modelData.sub : ""
                                    color: cr.sel ? Qt.rgba(1, 1, 1, 0.8) : panelPal.fg2
                                    font.family: root.fontForWeight(font.weight, panelPal.fam); font.pixelSize: 12
                                }
                                Glyph {
                                    visible: cr.sel
                                    anchors.right: parent.right
                                    anchors.rightMargin: 18
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 18; height: 18
                                    kind: "return"; color: "white"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    property point press: Qt.point(0, 0)
                                    property bool dragged: false
                                    onEntered: { if (ui.spSel !== cr.index) { ui.spHover = true; ui.spSel = cr.index; } }
                                    onPressed: mouse => { press = mapToItem(spotRoot, mouse.x, mouse.y); dragged = false; }
                                    onPositionChanged: mouse => {
                                        if (!pressed) return;
                                        var p = mapToItem(spotRoot, mouse.x, mouse.y);
                                        if (!dragged && Math.abs(p.x - press.x) + Math.abs(p.y - press.y) > 14) { dragged = true; clipGhost.start(cr.modelData); }
                                        if (dragged) { clipGhost.px = p.x; clipGhost.py = p.y; }
                                    }
                                    onReleased: mouse => {
                                        if (!dragged) return;
                                        var p = mapToItem(spotRoot, mouse.x, mouse.y);
                                        // outside Spotlight = on the desktop → open it; inside → it flies back
                                        var out = p.x < spot.x || p.x > spot.x + spot.width || p.y < spot.y || p.y > spot.y + spot.height;
                                        clipGhost.drop(out);
                                    }
                                    onClicked: if (!dragged) ui.spActivate(cr.index)
                                }
                            }
                        }

                        Column {
                            visible: clipPanel.items.length === 0
                            x: 20; y: 64
                            width: parent.width - 40
                            height: 118
                            spacing: 6
                            topPadding: 30
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: clipPanel.emptyTitle
                                color: panelPal.fg
                                font.family: root.fontForWeight(font.weight, panelPal.fam); font.pixelSize: 15; font.weight: Font.Medium
                            }
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                text: clipPanel.emptySub
                                color: panelPal.fg2
                                font.family: root.fontForWeight(font.weight, panelPal.fam); font.pixelSize: 12
                            }
                        }

                        // the round "..." menu
                        MouseArea { anchors.fill: parent; z: 4; visible: ui.clipMenu; onClicked: ui.clipMenu = false }
                        Item {
                            id: clipMenuPop
                            z: 5
                            visible: ui.clipMenu
                            x: parent.width - width - 20
                            y: 58
                            width: 250
                            height: 3 * 40 + 12
                            GGlass { anchors.fill: parent; gx: spg; cornerR: 20; thickness: 26; strengthMul: 1.0; shadowAmt: 0.26 }
                            MenuBorder { amount: 0.5; anchors.fill: parent; cornerR: 20; dark: root.panelDarkMode; tint: root.menuBorderColor }
                            Column {
                                x: 6; y: 6
                                width: parent.width - 12
                                Repeater {
                                    model: ["auto", "del", "clear"]
                                    delegate: Item {
                                        id: cm
                                        required property string modelData
                                        width: parent.width; height: 40
                                        readonly property bool armedNow: modelData === "clear" && ui.armed === "clipclear"
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 14
                                            color: cm.armedNow ? "#FF453A" : root.accent
                                            opacity: cmMa.containsMouse ? 1 : 0
                                        }
                                        Glyph {
                                            visible: cm.modelData === "auto" && root.clipAutoPaste
                                            x: 12; anchors.verticalCenter: parent.verticalCenter
                                            width: 16; height: 16
                                            kind: "check"; color: cmMa.containsMouse ? "white" : panelPal.fg
                                        }
                                        Text {
                                            x: 38
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: cm.modelData === "auto" ? I18n.tr("Paste Automatically")
                                                  : (cm.modelData === "del" ? "Delete Selected"
                                                  : (cm.armedNow ? "Click again to confirm" : "Clear History"))
                                            color: cmMa.containsMouse ? "white" : ((cm.modelData === "clear") ? "#FF453A" : panelPal.fg)
                                            font.family: root.fontForWeight(font.weight, panelPal.fam); font.pixelSize: 14
                                        }
                                        MouseArea {
                                            id: cmMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                if (cm.modelData === "auto") root.clipAutoPaste = !root.clipAutoPaste;
                                                else if (cm.modelData === "del") {
                                                    var n = clipPanel.items.length;
                                                    if (n > 0) root.clipDelete(clipPanel.items[Math.min(ui.spSel, n - 1)]);
                                                    ui.clipMenu = false;
                                                } else {
                                                    if (ui.armed === "clipclear") { ui.armed = ""; root.clipClear(); ui.clipMenu = false; }
                                                    else ui.armed = "clipclear";
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Emoji panel ──
                    Item {
                        id: emojiPanel
                        opacity: ui.spMode === "emoji" ? 1 : 0
                        visible: opacity > 0
                        scale: ui.spMode === "emoji" ? 1 : 0.96
                        transformOrigin: Item.Top
                        Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        width: spot.width
                        readonly property int cell: 50
                        readonly property int gridRows: 6
                        readonly property var items: ui.spMode === "emoji" ? ui.spResults : []
                        readonly property var cur: items[Math.min(ui.spSel, items.length - 1)]
                        height: 64 + 42 + gridRows * cell + 46
                        GGlass { anchors.fill: parent; gx: spg; cornerR: 32; thickness: 34; strengthMul: 1.0; shadowAmt: 0.22 }
                        MenuBorder { amount: 0.5; anchors.fill: parent; cornerR: 32; dark: root.panelDarkMode; tint: root.menuBorderColor }

                        Item {
                            x: 20
                            width: parent.width - 40
                            height: 64
                            Rectangle {
                                id: emojiChip
                                anchors.verticalCenter: parent.verticalCenter
                                width: 34; height: 34; radius: 10
                                color: root.accent
                                Glyph { anchors.centerIn: parent; width: 20; height: 20; kind: "smile"; color: "white" }
                            }
                            Text {
                                id: emojiLabel
                                x: 46
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Emoji")
                                color: panelPal.fg
                                font.family: root.fontForWeight(font.weight, panelPal.fam); font.pixelSize: 24; font.weight: Font.Medium
                            }
                            TextInput {
                                id: emojiInput
                                x: emojiLabel.x + emojiLabel.width + 14
                                width: parent.width - x
                                anchors.verticalCenter: parent.verticalCenter
                                clip: true
                                color: panelPal.fg
                                selectionColor: root.accent
                                selectedTextColor: "white"
                                font.family: root.fontForWeight(font.weight, panelPal.fam); font.pixelSize: 24
                                onTextChanged: { if (ui.spMode === "emoji") { ui.spQuery = text; ui.spSel = 0; } }
                                Keys.onPressed: event => ui.spKey(event)
                            }
                        }

                        // category tabs
                        Row {
                            x: 20; y: 64
                            opacity: ui.spQuery.trim() === "" ? 1 : 0.35
                            Repeater {
                                model: ["\uD83D\uDD58", "\uD83D\uDE00", "\uD83E\uDDD1", "\uD83D\uDC3B", "\uD83C\uDF54", "\u2708\uFE0F", "\u26BD", "\uD83D\uDCA1", "\uD83D\uDD23", "\uD83C\uDFF3\uFE0F"]
                                delegate: Item {
                                    id: tab
                                    required property string modelData
                                    required property int index
                                    width: 60; height: 36
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 48; height: 32; radius: 12
                                        color: root.accent
                                        opacity: (ui.emCat === tab.index && ui.spQuery.trim() === "") ? 0.9 : (tabMa.containsMouse ? 0.25 : 0)
                                        Behavior on opacity { NumberAnimation { duration: 100 } }
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: tab.modelData
                                        font.family: root.emojiFont; font.pixelSize: 22
                                    }
                                    MouseArea {
                                        id: tabMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            emojiInput.text = "";
                                            ui.emCat = tab.index; ui.spSel = 0;
                                            emojiInput.forceActiveFocus();
                                        }
                                    }
                                }
                            }
                        }

                        GridView {
                            id: emojiGrid
                            x: 20; y: 64 + 42
                            width: ui.emCols * emojiPanel.cell
                            height: emojiPanel.gridRows * emojiPanel.cell
                            cellWidth: emojiPanel.cell
                            cellHeight: emojiPanel.cell
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            model: emojiPanel.items
                            Connections {
                                target: ui
                                function onSpSelChanged() {
                                    if (ui.spHover) { ui.spHover = false; return; }
                                    if (ui.spMode === "emoji" && emojiPanel.items.length > 0)
                                        emojiGrid.positionViewAtIndex(Math.min(ui.spSel, emojiPanel.items.length - 1), GridView.Contain);
                                }
                            }
                            delegate: Item {
                                id: ec
                                required property var modelData
                                required property int index
                                readonly property bool sel: index === Math.min(ui.spSel, emojiPanel.items.length - 1)
                                width: emojiPanel.cell; height: emojiPanel.cell
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width - 4; height: parent.height - 4
                                    radius: 14
                                    color: root.accent
                                    opacity: ec.sel ? 1 : 0
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: ec.modelData ? ec.modelData[0] : ""
                                    font.family: root.emojiFont; font.pixelSize: 36
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: { if (ui.spSel !== ec.index) { ui.spHover = true; ui.spSel = ec.index; } }
                                    onClicked: { ui.pop = ""; root.emojiPick(ec.modelData); }
                                }
                            }
                        }
                        Text {
                            visible: emojiPanel.items.length === 0
                            x: 20; y: 64 + 42
                            width: parent.width - 40
                            height: emojiPanel.gridRows * emojiPanel.cell
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: ui.spQuery.trim() !== "" ? I18n.tr("No Results") : I18n.tr("No recently used emoji")
                            color: panelPal.fg2
                            font.family: root.fontForWeight(font.weight, panelPal.fam); font.pixelSize: 14
                        }

                        // footer: name of the highlighted emoji
                        Item {
                            x: 20; y: parent.height - 46
                            width: parent.width - 40; height: 46
                            Rectangle { width: parent.width; height: 1; color: panelPal.sep }
                            Text {
                                x: 4
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 180
                                elide: Text.ElideRight
                                text: emojiPanel.cur ? (emojiPanel.cur[0] + "  " + emojiPanel.cur[1]) : ""
                                color: panelPal.fg2
                                font.family: root.fontForWeight(font.weight, panelPal.fam); font.pixelSize: 13
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.clipAutoPaste ? I18n.tr("Return to insert") : I18n.tr("Return to copy")
                                color: panelPal.fg3
                                font.family: root.fontForWeight(font.weight, panelPal.fam); font.pixelSize: 12
                            }
                        }
                    }

                    // ── Applications panel ──
                    Item {
                        id: appsPanel
                        opacity: ui.spMode === "apps" ? 1 : 0
                        visible: opacity > 0
                        scale: ui.spMode === "apps" ? 1 : 0.96
                        transformOrigin: Item.Top
                        Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        width: spot.width
                        height: Math.min(64 + appsCol.height + 14, 520)
                        GGlass { anchors.fill: parent; gx: spg; cornerR: 32; thickness: 34; strengthMul: 1.0; shadowAmt: 0.22 }
                        MenuBorder { amount: 0.5; anchors.fill: parent; cornerR: 32; dark: root.panelDarkMode; tint: root.menuBorderColor }

                        Item {
                            id: appsHeader
                            x: 24
                            width: parent.width - 48
                            height: 64
                            Glyph {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 24; height: 24
                                kind: "appstore"; color: panelPal.fg2
                            }
                            Text {
                                x: 40 + 3
                                anchors.verticalCenter: parent.verticalCenter
                                visible: appsInput.text === ""
                                text: I18n.tr("Applications")
                                color: panelPal.fg3
                                font.family: root.fontForWeight(font.weight, panelPal.fam); font.pixelSize: 24
                            }
                            TextInput {
                                id: appsInput
                                x: 40
                                width: parent.width - 40 - 48
                                anchors.verticalCenter: parent.verticalCenter
                                clip: true
                                color: panelPal.fg
                                selectionColor: root.accent
                                selectedTextColor: "white"
                                font.family: root.fontForWeight(font.weight, panelPal.fam); font.pixelSize: 24
                                onTextChanged: { if (ui.spMode === "apps") { ui.spQuery = text; ui.spSel = 0; } }
                                Keys.onPressed: event => ui.spKey(event)
                            }
                            CCBtn {
                                t: pal; gx: spg
                                d: 34
                                bounce: true
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                kind: "dots"
                                onClicked: ui.spSetMode("home")
                            }
                        }

                        Flickable {
                            id: appsFlick
                            y: 64
                            width: parent.width
                            height: parent.height - 64 - 6
                            contentWidth: width
                            contentHeight: appsCol.height + 8
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            Column {
                                id: appsCol
                                x: 24
                                width: appsFlick.width - 48

                                Repeater {
                                    id: appsRep
                                    model: ui.spQuery.trim() === "" ? root.appSections : root.appSearchSection(ui.spQuery)
                                    delegate: Column {
                                        id: sec
                                        required property var modelData
                                        readonly property bool searching: ui.spQuery.trim() !== ""
                                        readonly property bool expanded: searching || ui.spExpanded[modelData.name] === true
                                        readonly property int shown: expanded ? modelData.apps.length : Math.min(5, modelData.apps.length)
                                        width: appsCol.width

                                        Rectangle { width: parent.width; height: 1; color: panelPal.sep }
                                        Item {
                                            width: parent.width
                                            height: 38
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: I18n.tr(sec.modelData.name)
                                                color: panelPal.fg
                                                font.family: root.fontForWeight(font.weight, panelPal.fam); font.pixelSize: 13; font.weight: Font.Bold
                                            }
                                            Text {
                                                visible: !sec.searching && sec.modelData.apps.length > 5
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: sec.expanded ? I18n.tr("Show Less") : I18n.tr("Show More")
                                                color: root.accent
                                                font.family: root.fontForWeight(font.weight, panelPal.fam); font.pixelSize: 12; font.weight: Font.Bold
                                                MouseArea {
                                                    anchors.fill: parent
                                                    anchors.margins: -6
                                                    onClicked: ui.spToggleSection(sec.modelData.name)
                                                }
                                            }
                                        }
                                        Grid {
                                            columns: 5
                                            Repeater {
                                                model: sec.shown
                                                delegate: Item {
                                                    id: cell
                                                    required property int index
                                                    readonly property var e: sec.modelData.apps[index]
                                                    width: appsCol.width / 5
                                                    height: 96
                                                                                                                                                            Rectangle {
                                                        anchors.fill: parent
                                                        anchors.margins: 2
                                                        radius: 16
                                                        color: cma.containsMouse ? panelPal.hover : "transparent"
                                                    }
                                                    Image {
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        y: 10
                                                        width: 56; height: 56
                                                        source: root.iconSrc(cell.e.icon)
                                                        sourceSize: Qt.size(128, 128)
                                                        fillMode: Image.PreserveAspectFit
                                                        asynchronous: true
                                                        smooth: true
                                                    }
                                                    Text {
                                                        y: 72
                                                        width: parent.width - 8
                                                        x: 4
                                                        horizontalAlignment: Text.AlignHCenter
                                                        elide: Text.ElideRight
                                                        text: cell.e.name
                                                        color: panelPal.fg
                                                        font.family: root.fontForWeight(font.weight, panelPal.fam); font.pixelSize: 12
                                                    }
                                                    MouseArea {
                                                        id: cma
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        onClicked: { ui.pop = ""; root.launchApp(cell.e); }
                                                    }
                                                }
                                            }
                                        }
                                        Item { width: 1; height: 10 }
                                    }
                                }
                                Text {
                                    visible: ui.spQuery.trim() !== "" && appsRep.count === 0
                                    width: parent.width
                                    height: 90
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: I18n.tr("No Results")
                                    color: panelPal.fg2
                                    font.family: root.fontForWeight(font.weight, panelPal.fam); font.pixelSize: 14
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
