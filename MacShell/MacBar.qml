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
// Wallpapers: Ctrl+Alt+W opens the wallpaper picker (Liquid Glass). Bind it with:
//   hl.bind("CTRL + ALT + W", hl.dsp.exec_cmd("qs -c macbar ipc call wallpapers toggle"))
//   (hyprlang:  bind = CTRL ALT, W, exec, qs -c macbar ipc call wallpapers toggle)
// Folder: ~/Pictures/Wallpapers by default (change it inside the picker, or "wallpaperDir" in settings.json).
// Star a wallpaper to pin it to the top. Applied through awww / swww / hyprpaper, or your own "wallpaperCmd" ({} = image path).
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
import QtMultimedia
import Quickshell.Services.Notifications
import "EmojiData.js" as EmojiData
import "I18n.js" as I18n

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
    property bool ccEnabled: true            // Control Center
    property string ccStyle: "tiles"         // tiles = every control its own glass | macos = one frosted panel behind them
    // window title bars (Settings, Clock, App Store): how the traffic lights behave
    property bool tlAlwaysSymbols: false     // true = always draw × − ↗, not only on hover
    property bool tlColorOnHover: false      // true = grey until you hover the window's lights
    property bool ccAnimate: true            // false = it just appears, with no slide / stagger
    // ── one material for the whole shell ──
    // Settings → Appearance → Material. Sets the menu bar, its popovers, the Dock, Spotlight, the switcher,
    // notifications, Control Center and the desktop widgets in one go. "custom" = you changed a piece by hand.
    property string material: "liquid"       // liquid | frosted | blur | opaque | custom
    property bool applyingMaterial: false
    onGlassOpacityChanged: materialTouched()
    onGlassBlurChanged: materialTouched()
    onGlassLiquidChanged: materialTouched()
    onSwitcherStyleChanged: materialTouched()
    onNotifBlurChanged: materialTouched()
    function applyMaterial(m) {
        if (m === "custom") { material = "custom"; return; }
        applyingMaterial = true;
        var dock = hub ? hub.dock : null, wid = hub ? hub.widgets : null;
        if (m === "liquid") {
            barStyle = "liquid"; glassOpacity = 0.42; glassBlur = 5; glassLiquid = 1.0; barBgOpacity = 0.10;
            switcherStyle = "glass"; notifBlur = 14;
            if (dock) dock.dockStyle = "liquid";
            if (wid) { wid.style = "glass"; wid.glassAmt = 0.5; wid.blurAmt = 0.5; }
        } else if (m === "frosted") {
            barStyle = "blur"; glassOpacity = 0.55; glassBlur = 26; glassLiquid = 0.0; barBgOpacity = 0.22;
            switcherStyle = "frosted"; notifBlur = 30;
            if (dock) dock.dockStyle = "blur";
            if (wid) { wid.style = "frosted"; wid.blurAmt = 0.8; }
        } else if (m === "blur") {
            barStyle = "blur"; glassOpacity = 0.30; glassBlur = 16; glassLiquid = 0.0; barBgOpacity = 0.12;
            switcherStyle = "frosted"; notifBlur = 18;
            if (dock) dock.dockStyle = "blur";
            if (wid) { wid.style = "frosted"; wid.blurAmt = 0.45; }
        } else if (m === "opaque") {
            barStyle = "blur"; glassOpacity = 1.0; glassBlur = 0; glassLiquid = 0.0; barBgOpacity = 1.0;
            switcherStyle = "opaque"; notifBlur = 0;
            if (dock) dock.dockStyle = "blur";
            if (wid) { wid.style = "opaque"; }
        }
        applyingMaterial = false;
        material = m;
    }
    // changing any single piece by hand means the material is no longer one of the presets
    function materialTouched() { if (settingsReady && !applyingMaterial && material !== "custom") material = "custom"; }
    property bool notificationsEnabled: true // banners + Notification Center (off = no D-Bus daemon at all, so mako/dunst can take over)
    property bool clockAppEnabled: true      // the Clock app (alarms and timers still ring while it is on)
    readonly property bool barLayerNeeded: barEnabled || spotlightEnabled || ccEnabled || notificationsEnabled
    property bool darkMode: true
    property color accent: "#0A84FF"
    // "Inter" renders with the single variable file: the static Inter.ttc got mapped once per face (~25×13 MB of RSS)
    property string fontFamily: "Open Runde"
    onFontFamilyChanged: {
        if (fontFamily.indexOf("Inter") === 0) fontFamily = "Open Runde";
        if (hub && hub.dock && hub.dock.fontFamily !== fontFamily) hub.dock.fontFamily = fontFamily;
    }
    property int barHeight: 28
    property string barLogoMode: "arch"       // "arch", "apple", or "custom"
    property string barCustomLogoPath: ""     // absolute path, ~/path, or file URL for the custom menu-bar logo
    // The bar-size slider scales its widget groups while the left/right groups stay pinned to their corners.
    readonly property real barWidgetScale: Math.max(0.8, Math.min(1.55, barHeight / 28))
    readonly property real barPopupScale: Math.max(0.9, Math.min(1.25, 1 + (barHeight - 28) / 88))
    property real glassOpacity: 0.42
    // Opaque, and Game Mode: nothing anywhere is see-through — the shell's surfaces are solid and every window is
    // drawn at full opacity without blur (macshell-solid.sh); leaving it puts your window opacity / blur back
    readonly property bool solidAll: material === "opaque" || gaming
    readonly property real effGlassOpacity: solidAll ? 1.0 : glassOpacity
    readonly property real effBarBg: solidAll ? 1.0 : barBgOpacity
    property bool solidApplied: false
    function applySolid() {
        if (!settingsReady || solidAll === solidApplied) return;
        solidApplied = solidAll;
        Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr-macshell/scripts/macshell-solid.sh", solidAll ? "on" : "off"]);
    }
    onSolidAllChanged: solidDelay.restart()
    // after Game Mode turns off it restores blur; if Opaque is still chosen, windows go solid again right after
    Timer { id: solidDelay; interval: 400; onTriggered: root.applySolid() }
    // a Hyprland config reload (Settings → Keyboard Shortcuts saves one) puts the window opacity back: solid again
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded" && root.solidAll)
                Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr-macshell/scripts/macshell-solid.sh", "on"]);
        }
    }
    property string barStyle: "liquid"        // "liquid" = Apple Liquid Glass popovers, "blur" = flat translucent
    property real glassRim: 0.45
    property real glassGrain: 0.015
    property bool tintAccent: false        // glass picks up the accent colour instead of neutral grey
    property bool windowBar: false         // Apple-style window controls floating on every window (off: see WindowBar.qml)
    property bool windowBarTitle: true     // …with the app's icon and name beside them
    property string userDisplayName: ""    // the name you go by (kept from older versions' first-run screen)
    // Control Center: battery, Internet Sharing, screen mirroring and the keyboard backlight
    property string powerProfile: "balanced"
    property bool hotspotOn: false
    property bool localsendRunning: false
    property int keyLight: 0
    property int keyLightMax: 0
    property bool mirrorOn: false           // read back from Hyprland (a monitor with mirrorOf set), not assumed
    property int displayCount: 1
    // switches at once in the UI; if the system refuses, it says why and shows the real profile again
    function setPowerProfile(p) {
        powerProfile = p;
        ppSet.want = p;
        ppSet.command = ["sh", "-c", "powerprofilesctl set \"$1\" 2>&1 >/dev/null; echo \"[now $(powerprofilesctl get 2>/dev/null)]\"", "sh", p];
        ppSet.running = true;
    }
    Process {
        id: ppSet
        property string want: ""
        stdout: StdioCollector {
            onStreamFinished: {
                var m = /\[now ([a-z-]*)\]/.exec(text), now = m ? m[1] : "";
                if (now !== "" && now !== ppSet.want) {
                    root.powerProfile = now;
                    var why = text.replace(/\[now [a-z-]*\]/, "").trim();
                    var busy = /busy|intel_pstate/i.test(why);
                    root.notify(ppSet.want === "power-saver" ? "Low Power Mode couldn't turn on" : "The power mode couldn't change",
                                busy ? "Something else is holding the CPU in its performance governor (max-performance on this system). Run: sudo ~/max-performance-fix.sh"
                                     : (why || "power-profiles-daemon refused the change"));
                }
            }
        }
    }
    // the power profile can change from anywhere (powerprofilesctl, the battery saver, Game Mode): keep it current
    Process {
        id: ppProc
        command: ["sh", "-c", "powerprofilesctl get 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: { var p = text.trim(); if (p !== "" && p !== root.powerProfile) root.powerProfile = p; } }
    }
    Timer { interval: 5000; repeat: true; running: true; triggeredOnStart: true; onTriggered: if (!ppProc.running) ppProc.running = true }
    function toggleLowPower() { setPowerProfile(powerProfile === "power-saver" ? "balanced" : "power-saver"); }
    // the same Internet Sharing as Settings → Sharing: your network name, password and band, and (with the helper)
    // without dropping the Wi-Fi you are on. It used to start a hotspot of its own with a fixed name and password.
    function toggleHotspot() {
        hotspotOn = !hotspotOn;
        var d = hub ? hub.dock : null;
        var s = Quickshell.env("HOME") + "/.config/hypr-macshell/scripts/macshell-sharing.sh";
        if (hotspotOn) {
            if (d && wifiSsid !== "") d.hotspotPrevWifi = wifiSsid;
            Quickshell.execDetached([s, "start", d ? d.hotspotSsid : "", d ? d.hotspotPass : "", d ? d.hotspotBand : "bg"]);
        } else Quickshell.execDetached([s, "stop", d ? d.hotspotPrevWifi : ""]);
    }
    // the thin border around the desktop widgets and the Clock window: a soft shade of the accent
    readonly property color menuBorderColor: {
        var c = Qt.color(accent);
        var h = c.hslHue < 0 ? 0 : c.hslHue, sat = Math.max(0.28, Math.min(0.75, c.hslSaturation));
        return darkMode ? Qt.hsla(h, sat, 0.74, 1) : Qt.hsla(h, sat * 0.8, 0.42, 1);
    }
    // Lock Screen: starts MacLock via its IPC helper; does nothing if it is already locked
    function lockScreen() { sh('sh ~/.config/quickshell/MacLock/lock-via-ipc.sh'); }
    function sleepMachine() { sh('sh ~/.config/quickshell/MacLock/lock-via-ipc.sh; sleep 0.5; systemctl suspend'); }
    property string language: "auto"        // "auto" = the system language, or a code with a table in lang/ (I18n.js)
    onLanguageChanged: Qt.uiLanguage = language === "auto" ? "" : language
    function setKeyLight(v) {
        keyLight = Math.max(0, Math.min(keyLightMax, Math.round(v)));
        Quickshell.execDetached(["sh", "-c", "brightnessctl -d \"$(ls /sys/class/leds | grep -i kbd_backlight | head -1)\" set \"$1\" >/dev/null 2>&1", "sh", String(keyLight)]);
    }
    function toggleMirror() {
        // every other display shows the one you are on, or they go back to being displays of their own.
        // (It used "hyprctl keyword monitor", which the Lua config no longer has, so it never did anything.)
        if (displayCount < 2 && !mirrorOn) {
            Quickshell.execDetached(["notify-send", "-a", "Screen Mirroring", "Screen Mirroring", "Connect another display to mirror this one to."]);
            return;
        }
        mirrorOn = !mirrorOn;
        Quickshell.execDetached(["sh", "-c", mirrorOn
            ? "m=$(hyprctl activeworkspace -j | jq -r .monitor); "
              + "for o in $(hyprctl monitors -j | jq -r '.[].name'); do [ \"$o\" = \"$m\" ] || "
              + "hyprctl eval \"hl.monitor({ output = \\\"$o\\\", mode = \\\"preferred\\\", position = \\\"auto\\\", scale = 1, mirror = \\\"$m\\\" })\" >/dev/null; done"
            // the config's own monitor rules (and stretchres) put every display back
            : "hyprctl reload >/dev/null"]);
        mirrorCheck.restart();
    }
    Timer { id: mirrorCheck; interval: 1500; onTriggered: ccPoll.triggered() }
    Process {
        id: ccStateProc
        stdout: StdioCollector {
            onStreamFinished: {
                var l = text.split("\n");
                root.powerProfile = (l[0] || "balanced").trim() || "balanced";
                root.hotspotOn = (l[1] || "").trim() === "yes";
                root.localsendRunning = (l[2] || "").trim() === "yes";
                root.keyLight = parseInt((l[3] || "0").trim()) || 0;
                root.keyLightMax = parseInt((l[4] || "0").trim()) || 0;
                var dm = (l[5] || "").trim().split(/\s+/);
                if (dm.length === 2) { root.displayCount = parseInt(dm[0]) || 1; root.mirrorOn = (parseInt(dm[1]) || 0) > 0; }
            }
        }
    }
    property bool ccVisible: false
    property string ccGeom: ""
    Timer { interval: 1200; running: true; onTriggered: ccPoll.triggered() }
    Timer {
        id: ccPoll
        // open: every five seconds. Closed: once at startup, so the tiles are right the moment it opens.
        interval: 5000; repeat: true; running: root.ccVisible
        triggeredOnStart: true
        onTriggered: {
            if (ccStateProc.running) return;
            ccStateProc.command = ["sh", "-c",
                "powerprofilesctl get 2>/dev/null || echo balanced; "
                + "nmcli -t -f NAME connection show --active 2>/dev/null | grep -qFx MacShell-Hotspot && echo yes || echo no; "
                + "pgrep -x localsend_app >/dev/null && echo yes || echo no; "
                + "d=$(ls /sys/class/leds 2>/dev/null | grep -i kbd_backlight | head -1); "
                + "if [ -n \"$d\" ]; then cat /sys/class/leds/$d/brightness; cat /sys/class/leds/$d/max_brightness; else echo 0; echo 0; fi; "
                // displays: how many, and how many are mirroring another
                + "hyprctl monitors all -j 2>/dev/null | jq -r '[length, (map(select(.mirrorOf != \"none\" and .mirrorOf != null)) | length)] | @tsv'"];
            ccStateProc.running = true;
        }
    }
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
    // measure brightness behind a screen rect (logical coords): one tiny grim grab, mean luminance
    function measureTone(sx, sy, sw, sh) {
        if (!autoContrast || toneProc.running) return;
        // perceived brightness of the sRGB means (a "gray" conversion in ImageMagick is linear-light and reads mid-tones far too dark)
        toneProc.command = ["sh", "-c", "grim -s 0.08 -g \"$1,$2 $3x$4\" - 2>/dev/null | magick - -format '%[fx:0.299*mean.r+0.587*mean.g+0.114*mean.b]' info: 2>/dev/null",
                            "sh", String(Math.round(sx)), String(Math.round(sy)), String(Math.max(8, Math.round(sw))), String(Math.max(8, Math.round(sh)))];
        toneProc.running = true;
    }
    Process {
        id: toneProc
        stdout: StdioCollector {
            onStreamFinished: {
                var v = parseFloat(text);
                if (isNaN(v)) return;
                // Only change anything when the normal text would NOT be readable. v is perceived (gamma) brightness of
                // what's behind; turn it into relative luminance, put the panel's own tint over it, and test the WCAG
                // contrast of the normal text colour. Below 3:1 → flip to the other style; otherwise keep the user's.
                var L = Math.pow(Math.max(0, Math.min(1, v)), 2.2);
                var tint = Math.min(0.6, root.glassOpacity * 0.55 + 0.05);
                if (root.darkMode) {
                    var effD = L * (1 - tint) + 0.004 * tint;                 // dark glass tint
                    root.bgTone = (1.05 / (effD + 0.05)) < 3 ? 1 : 0;        // white text unreadable → dark text
                } else {
                    var effL = L * (1 - tint) + 1.0 * tint;                   // light glass tint
                    root.bgTone = ((effL + 0.05) / 0.062) < 3 ? -1 : 0;       // dark text unreadable → white text
                }
            }
        }
    }
    property bool lockArtBackground: true     // lock screen: blurred album art as the background while the cover is enlarged
    // lock screen clock (Settings → Lock Screen → Clock); MacLock reads these when it starts
    property string lockClockStyle: "glass"   // preset last picked: glass | classic | serif | liquid | thin | custom
    property string lockClockFont: "condensed"   // condensed | rounded | serif | inter
    property int lockClockWeight: 680
    property string lockClockMaterial: "glass"   // solid (Apple's vibrancy) | glass (Liquid Glass)
    property real lockClockIntensity: 0.6        // solid: how bright / opaque; glass: clear (0) … frosted (1)
    property string lockClockTint: "#FFFFFF"
    property bool lockClockTall: true
    property string lockClockDate: "long"        // long ("Friday, October 16") | short ("Fri Oct 16")
    readonly property var lockClockPresets: ({
        glass:   { f: "condensed", w: 680, m: "glass", i: 0.6,  t: true,  d: "long" },
        classic: { f: "rounded",   w: 600, m: "solid", i: 0.8,  t: false, d: "long" },
        serif:   { f: "serif",     w: 560, m: "solid", i: 0.85, t: false, d: "short" },
        liquid:  { f: "condensed", w: 560, m: "glass", i: 0.12, t: true,  d: "short" },
        thin:    { f: "rounded",   w: 200, m: "solid", i: 0.6,  t: false, d: "short" }
    })
    // settings saved before Solid / Glass existed: move them over (presets keep their name, the rest map across)
    onLockClockMaterialChanged: Qt.callLater(function () {
        if (lockClockMaterial !== "frosted" && lockClockMaterial !== "liquid") return;
        if (lockClockPresets[lockClockStyle]) { applyLockClockPreset(lockClockStyle); return; }
        lockClockIntensity = lockClockMaterial === "liquid" ? 0.12 : 0.6;
        lockClockMaterial = "glass";
    })
    function applyLockClockPreset(name) {
        var p = lockClockPresets[name]; if (!p) return;
        lockClockFont = p.f; lockClockWeight = p.w; lockClockMaterial = p.m; lockClockIntensity = p.i; lockClockTall = p.t; lockClockDate = p.d;
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
    // Live refraction: whatever moves under a liquid panel or the Control Center is refracted as it moves. On by default;
    // only the windows actually behind glass that is on screen are kept live, so the cost stays where you can see it.
    property bool glassRealtime: true
    // ── Under load (a build, an update, a big install) the shell gets out of the way ──
    // Live refraction and the window captures are the expensive part; while the machine is busy they
    // stop being live and the glass keeps its last frame, so the desktop stays responsive.
    property real sysLoad: 0
    readonly property int sysCores: coreCount
    // engages at 60 % of the machine and lets go at 40 %, so it doesn't flap around the threshold
    property bool underLoad: false
    onSysLoadChanged: {
        if (sysCores <= 0) return;
        var per = sysLoad / sysCores;
        if (!underLoad && per > 0.6) underLoad = true;
        else if (underLoad && per < 0.4) underLoad = false;
    }
    FileView {
        id: loadFile
        path: "/proc/loadavg"
        printErrors: false
        onLoaded: {
            var v = parseFloat(String(text()).split(" ")[0]);
            if (!isNaN(v)) root.sysLoad = v;
        }
    }
    Timer {
        interval: 4000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: loadFile.reload()
    }
    Process {
        id: coreProc
        running: true
        command: ["sh", "-c", "nproc 2>/dev/null || echo 4"]
        stdout: StdioCollector { onStreamFinished: { var n = parseInt(text.trim()); if (n > 0) root.coreCount = n; } }
    }
    property int coreCount: 4
    property bool glassDebug: false
    property string wallpaperPath: ""
    property bool use24h: true
    property bool showDate: true
    property bool showSeconds: false
    property bool showBatteryPercent: true
    property bool showTray: true
    property bool showSearch: true
    property bool weekStartsMonday: false
    property string terminal: "kitty"
    property string launcher: ""              // "" = built-in Spotlight; set a command (rofi, fuzzel, ...) to use an external launcher instead
    property string filesCmd: "qs -c MacShell ipc call finder open || xdg-open \"$HOME\""
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
    property bool ccMigTahoe: false            // one-time: add battery, Internet Sharing, AirDrop, mirroring, Lock Screen and Sleep
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

    readonly property var settingKeys: ["barEnabled", "darkMode", "accent", "fontFamily", "barHeight", "glassOpacity",
        "barStyle", "barGlass", "glassRim", "glassGrain", "glassLiquid", "glassBlur", "barBgOpacity", "glassRealtime", "glassDebug", "wallpaperPath", "use24h", "language", "showDate",
        "showSeconds", "showBatteryPercent", "showTray", "showSearch",
        "spotlightEnabled", "ccEnabled", "notificationsEnabled", "clockAppEnabled", "ccStyle", "userDisplayName", "ccAnimate", "material", "tlAlwaysSymbols", "tlColorOnHover", "tintAccent", "windowBar", "windowBarTitle", "barLogoMode", "barCustomLogoPath", "barWidgets", "weekStartsMonday", "terminal", "launcher",
        "filesCmd", "clipboardCmd", "appUsage", "clipHistory", "clipAutoPaste", "emojiRecent", "screenshotDir", "screenshotSave", "screenshotClipboard", "screenshotNotify", "nightTemp", "ccControls", "ccMigRec", "wallpaperDir", "wallpaperFavs", "wallpaperCmd", "wallpaperVideo", "uiSounds", "gamingMode", "gamingAuto", "ccMigGame", "ccMigTahoe", "lockArtBackground",
        "lockClockStyle", "switcherStyle", "barTone", "lockClockFont", "lockClockWeight", "lockClockMaterial", "lockClockIntensity", "lockClockTint", "lockClockTall", "lockClockDate", "autoContrast", "wallpaperAppearance", "wpPairLight", "wpPairDark",
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
        { name: I18n.tr("Blue"), c: "#0a84ff" }, { name: I18n.tr("Purple"), c: "#bf5af2" }, { name: I18n.tr("Pink"), c: "#ff375f" },
        { name: I18n.tr("Red"), c: "#ff453a" }, { name: I18n.tr("Orange"), c: "#ff9f0a" }, { name: I18n.tr("Yellow"), c: "#ffd60a" },
        { name: I18n.tr("Green"), c: "#30d158" }, { name: I18n.tr("Graphite"), c: "#8e8e93" }
    ]

    // ═════════════ CONTROL CENTER LAYOUT ═════════════
    // The Control Center is a 4-column grid. Every control has a size in grid cells; the enabled ones are packed
    // first-fit in the order of `ccControls`, so dragging a control onto another one simply reorders the list.
    readonly property var ccCatalog: [
        { id: "wifi",       label: I18n.tr("Wi-Fi"),         glyph: "wifi",       w: 2, h: 1 },
        { id: "bluetooth",  label: I18n.tr("Bluetooth"),     glyph: "bluetooth",  w: 1, h: 1 },
        { id: "airplane",   label: I18n.tr("Airplane Mode"), glyph: "airplane",   w: 1, h: 1 },
        { id: "focus",      label: I18n.tr("Focus"),         glyph: "moon",       w: 2, h: 1 },
        { id: "nightshift", label: I18n.tr("Night Shift"),   glyph: "nightshift", w: 1, h: 1 },
        { id: "keepawake",  label: I18n.tr("Keep Awake"),    glyph: "coffee",     w: 1, h: 1 },
        { id: "darkmode",   label: I18n.tr("Dark Mode"),     glyph: "contrast",   w: 1, h: 1 },
        { id: "gaming",     label: I18n.tr("Game Mode"),     glyph: "gamepad",    w: 2, h: 1 },
        { id: "record",     label: I18n.tr("Screen Recording"), glyph: "record",  w: 2, h: 1 },
        { id: "nowplaying", label: I18n.tr("Now Playing"),   glyph: "note",       w: 2, h: 2 },
        { id: "display",    label: I18n.tr("Display"),       glyph: "sun",        w: 4, h: 1 },
        { id: "sound",      label: I18n.tr("Sound"),         glyph: "speaker",    w: 4, h: 1 },
        { id: "battery",    label: I18n.tr("Battery"),       glyph: "battery",    w: 2, h: 1 },
        { id: "hotspot",    label: I18n.tr("Internet Sharing"), glyph: "hotspot", w: 2, h: 1 },
        { id: "lockscreen", label: I18n.tr("Lock Screen"),   glyph: "lock",       w: 1, h: 1 },
        { id: "sleep",      label: I18n.tr("Sleep"),         glyph: "power",      w: 1, h: 1 },
        { id: "mirror",     label: I18n.tr("Screen Mirroring"), glyph: "mirror",  w: 2, h: 1 },
        { id: "keylight",   label: I18n.tr("Keyboard Brightness"), glyph: "keyboard", w: 4, h: 1 }
    ]
    readonly property var ccDefault: ["wifi", "nowplaying", "bluetooth", "airplane", "focus", "record", "nightshift", "keepawake",
                                      "battery", "hotspot", "mirror", "lockscreen", "sleep", "display", "sound"]
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
        return { items: out, rows: rows };
    }
    // controls for hardware this computer doesn't have are left out, here and in Edit Controls (a keyboard
    // brightness slider on a keyboard with no backlight did nothing)
    function ccUsable(id) { return ccDef(id) !== null && (id !== "keylight" || keyLightMax > 0); }
    readonly property var ccPlan: ccLayout(ccControls.filter(ccUsable))
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
            var cx = o.col * (cw + 10) + (o.w * cw + (o.w - 1) * 10) / 2;
            var cy = o.row * (ch + 10) + (o.h * ch + (o.h - 1) * 10) / 2;
            var dd = (cx - px) * (cx - px) + (cy - py) * (cy - py);
            if (dd < best) { best = dd; to = order.indexOf(o.id); }
        }
        if (py > gridH + 10) to = order.length - 1;
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
    function logOut() {
        sh('if command -v uwsm >/dev/null 2>&1 && uwsm check is-active >/dev/null 2>&1; then uwsm stop; '
           + 'else hyprctl dispatch "hl.dsp.exit()" || hyprctl dispatch exit; fi');
    }

    // ═════════════ PALETTE ═════════════
    // Auto contrast: what's behind an opening panel is measured (bgTone: 1 bright, -1 dark, 0 unknown) and the panel
    // switches to dark text / light glass on bright backgrounds and the reverse on dark ones; colours cross-fade.
    property bool autoContrast: true
    property int bgTone: 0
    // The menu bar strip has no fill of its own, so its text has to follow whatever is behind it — exactly what
    // macOS does with the desktop picture. Without this, Light mode over a dark wallpaper is near-black on black.
    property int barTone: 0                  // 1 bright behind the bar → dark text · -1 dark behind → white text
    readonly property bool barDark: (autoContrast && barTone !== 0) ? barTone < 0 : darkMode
    // every control that switches appearance goes through here, so the Dock, Settings and the app windows follow
    function setDark(on) {
        if (hub && hub.dock && hub.dock.setLook) hub.dock.setLook("darkMode", on);
        else darkMode = on;
    }
    // Measured from the wallpaper's top edge, not from the screen: macOS follows the desktop picture, and reading
    // the picture costs one command per wallpaper change instead of a screen grab on a timer.
    property bool barToneLive: false
    function measureBarTone(sx, sy, sw, sh) {
        if (!autoContrast || gaming || barToneProc.running) return;
        barToneProc.command = ["sh", "-c",
            "if [ -n \"$5\" ] && [ -r \"$5\" ] && magick \"$5\" -resize 200x200^ -gravity north -crop 200x14+0+0 +repage "
            + "-format '%[fx:0.299*mean.r+0.587*mean.g+0.114*mean.b]' info: 2>/dev/null; then exit 0; fi; "
            + "grim -s 0.06 -g \"$1,$2 $3x$4\" - 2>/dev/null | magick - -format '%[fx:0.299*mean.r+0.587*mean.g+0.114*mean.b]' info: 2>/dev/null",
            "sh", String(Math.round(sx)), String(Math.round(sy)), String(Math.max(8, Math.round(sw))), String(Math.max(8, Math.round(sh))),
            // a moving wallpaper has no still that stays true: measure what is really on screen
            root.wallpaperVideo !== "" ? "" : root.wallpaperPath];
        barToneLive = root.wallpaperVideo !== "" || root.wallpaperPath === "";
        barToneProc.running = true;
    }
    Process {
        id: barToneProc
        stdout: StdioCollector {
            onStreamFinished: {
                var v = parseFloat(text);
                if (isNaN(v)) return;
                // measured live, the strip includes the bar's own tint: take it back out, or the tint would keep choosing itself
                if (root.barToneLive && root.effBarBg < 0.95) {
                    var a = root.effBarBg, f = root.barDark ? 0.10 : 1.0;
                    v = Math.max(0, Math.min(1, (v - a * f) / (1 - a)));
                }
                var L = Math.pow(Math.max(0, Math.min(1, v)), 2.2);
                // whichever of the two text colours has the better WCAG contrast against what is behind the strip
                root.barTone = (1.05 / (L + 0.05)) >= ((L + 0.05) / 0.062) ? -1 : 1;
            }
        }
    }
    readonly property bool effDark: (autoContrast && bgTone !== 0) ? bgTone < 0 : darkMode
    property real dk: effDark ? 1 : 0
    Behavior on dk { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
    function mixc(l, d) { return Qt.rgba(l.r + (d.r - l.r) * dk, l.g + (d.g - l.g) * dk, l.b + (d.b - l.b) * dk, l.a + (d.a - l.a) * dk); }
    QtObject {
        id: bpal
        readonly property bool dark: root.barDark
        readonly property string fam: root.fontFamily
        property color accent: root.accent
        Behavior on accent { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color fg: dark ? "#FFFFFF" : "#1D1D1F"
        Behavior on fg { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color fg2: dark ? Qt.rgba(1, 1, 1, 0.62) : Qt.rgba(0, 0, 0, 0.55)
        Behavior on fg2 { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color fg3: dark ? Qt.rgba(1, 1, 1, 0.34) : Qt.rgba(0, 0, 0, 0.32)
        Behavior on fg3 { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color tile: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.42)
        Behavior on tile { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color tileBorder: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.70)
        Behavior on tileBorder { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color btnOff: dark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.10)
        Behavior on btnOff { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color btnHover: dark ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(0, 0, 0, 0.16)
        Behavior on btnHover { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color hover: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.09)
        Behavior on hover { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color sep: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)
        Behavior on sep { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color track: dark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.12)
        Behavior on track { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color content: dark ? "#1E1E1E" : "#F5F5F7"
        Behavior on content { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color card: dark ? "#2B2B2D" : "#FFFFFF"
        Behavior on card { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color cardBorder: dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.08)
        Behavior on cardBorder { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color switchOff: dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.16)
        Behavior on switchOff { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
    }
    QtObject {
        id: pal
        readonly property bool dark: root.effDark
        readonly property string fam: root.fontFamily
        property color accent: root.accent
        Behavior on accent { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color fg: root.mixc(Qt.color("#1D1D1F"), Qt.color("#FFFFFF"))
        Behavior on fg { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color fg2: root.mixc(Qt.rgba(0, 0, 0, 0.55), Qt.rgba(1, 1, 1, 0.62))
        Behavior on fg2 { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color fg3: root.mixc(Qt.rgba(0, 0, 0, 0.32), Qt.rgba(1, 1, 1, 0.34))
        Behavior on fg3 { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color tile: root.mixc(Qt.rgba(1, 1, 1, 0.42), Qt.rgba(1, 1, 1, 0.10))
        Behavior on tile { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color tileBorder: root.mixc(Qt.rgba(1, 1, 1, 0.70), Qt.rgba(1, 1, 1, 0.16))
        Behavior on tileBorder { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color btnOff: root.mixc(Qt.rgba(0, 0, 0, 0.10), Qt.rgba(1, 1, 1, 0.20))
        Behavior on btnOff { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color btnHover: root.mixc(Qt.rgba(0, 0, 0, 0.16), Qt.rgba(1, 1, 1, 0.30))
        Behavior on btnHover { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color hover: root.mixc(Qt.rgba(0, 0, 0, 0.09), Qt.rgba(1, 1, 1, 0.14))
        Behavior on hover { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color sep: root.mixc(Qt.rgba(0, 0, 0, 0.12), Qt.rgba(1, 1, 1, 0.14))
        Behavior on sep { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color track: root.mixc(Qt.rgba(0, 0, 0, 0.12), Qt.rgba(1, 1, 1, 0.20))
        Behavior on track { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color content: dark ? "#1E1E1E" : "#F5F5F7"
        Behavior on content { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color card: dark ? "#2B2B2D" : "#FFFFFF"
        Behavior on card { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color cardBorder: root.mixc(Qt.rgba(0, 0, 0, 0.08), Qt.rgba(1, 1, 1, 0.07))
        Behavior on cardBorder { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property color switchOff: root.mixc(Qt.rgba(0, 0, 0, 0.16), Qt.rgba(1, 1, 1, 0.22))
        Behavior on switchOff { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
    }

    // ═════════════ REUSABLE COMPONENTS ═════════════
    // (inline components don't see ids of this file, so everything arrives through properties / `t` = palette)

    // Hand-drawn monochrome glyphs on an 18×18 grid (no icon theme needed)
    component Glyph: Canvas {
        id: gl
        property string kind: ""
        property color color: "white"
        property real level: 3          // speaker / sun intensity 0..3, wifi bars 0..3, battery 0..100
        property real frac: -1          // continuous 0..1 intensity; overrides level where a glyph supports it
        property string parts: ""       // draw only one piece of a composite glyph, so the pieces can animate apart
        property bool flag: false       // "disabled" slash for wifi / bluetooth
        width: 18; height: 18
        antialiasing: true
        onKindChanged: requestPaint()
        onFracChanged: requestPaint()
        onPartsChanged: requestPaint()
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
                // the rays shrink to stubs as the level drops, the way the macOS brightness key glyph does
                var lv = frac >= 0 ? Math.max(0, Math.min(1, frac)) : Math.max(0, Math.min(1, level / 3));
                // a clear gap between the circle and its rays (stroke width and round caps included)
                var r = 2.5 + lv * 0.8, a = r + 2.3, b = a + 0.4 + lv * 2.6;
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
                if (parts === "" || parts === "body")
                    poly([2.2, 7, 5.4, 7, 9.2, 3.6, 9.2, 14.4, 5.4, 11, 2.2, 11], true);
                if (parts === "mute") {
                    line(12, 6.8, 16, 11.2); line(16, 6.8, 12, 11.2);
                } else if (parts === "w1" || parts === "w2") {
                    ctx.beginPath(); ctx.arc(9.2, 9, 2.4 + (parts === "w1" ? 3.0 : 6.0), -0.62, 0.62); ctx.stroke();
                } else if (parts === "") {
                    if (level <= 0) {
                        line(12, 6.8, 16, 11.2); line(16, 6.8, 12, 11.2);
                    } else {
                        for (i2 = 1; i2 <= Math.min(2, Math.ceil(level / 1.5)); i2++) {
                            ctx.beginPath(); ctx.arc(9.2, 9, 2.4 + i2 * 3.0, -0.62, 0.62); ctx.stroke();
                        }
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
            } else if (k === "battery") {
                rrect(1.6, 5.4, 12.4, 7.2, 2.2); ctx.stroke();
                rrect(15.0, 7.6, 1.6, 2.8, 0.7); ctx.fill();
                // the fill shows the charge, and goes yellow in Low Power Mode
                var bw = Math.max(1.2, 10.4 * Math.max(0, Math.min(1, gl.level / 100)));
                rrect(2.8, 6.6, bw, 4.8, 1.2); ctx.fill();
            } else if (k === "hotspot") {
                circ(9, 11.6, 1.9); ctx.fill();
                ctx.beginPath(); ctx.arc(9, 11.6, 4.4, Math.PI * 1.25, Math.PI * 1.75); ctx.stroke();
                ctx.beginPath(); ctx.arc(9, 11.6, 7.2, Math.PI * 1.25, Math.PI * 1.75); ctx.stroke();
            } else if (k === "airdrop") {
                // the AirDrop mark: an arc, a smaller arc, and the arrow in the middle
                ctx.beginPath(); ctx.arc(9, 9.6, 6.6, Math.PI * 1.15, Math.PI * 1.85); ctx.stroke();
                ctx.beginPath(); ctx.arc(9, 9.6, 3.6, Math.PI * 1.15, Math.PI * 1.85); ctx.stroke();
                line(9, 15.2, 9, 8.6);
                line(6.2, 11.2, 9, 8.3); line(9, 8.3, 11.8, 11.2);
            } else if (k === "mirror") {
                rrect(1.4, 3.6, 9.2, 7.4, 1.6); ctx.stroke();
                rrect(7.4, 7.6, 9.2, 7.4, 1.6); ctx.stroke();
            } else if (k === "keyboard") {
                rrect(1.4, 4.4, 15.2, 9.6, 2); ctx.stroke();
                for (var ky = 0; ky < 2; ky++) for (var kx = 0; kx < 4; kx++) { rrect(3.4 + kx * 2.9, 6.4 + ky * 2.6, 1.6, 1.6, 0.5); ctx.fill(); }
                rrect(6.2, 11.6, 5.6, 1.4, 0.7); ctx.fill();
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
        property color tintHue: "transparent"   // Settings → Appearance → Tint colour (Accent)
        property real thickness: 30
        property real strength: 1.0         // liquid glass strength multiplier
        property real rim: 0.45
        property real grain: 0.03
        property real blur: 5               // backdrop blur radius, px (settings slider)
        property bool debug: false
        signal shaderError()

        // Blur / Frosted: the same backdrop the Liquid Glass shader uses, Gaussian-blurred and clipped to the slab.
        // (It used to be a flat translucent rectangle, which is why "Blur" and "Frosted" looked like nothing happened.)
        Loader {
            anchors.fill: parent
            active: !g.liquid && g.backdrop !== null && g.visible && g.blur > 0.5
            sourceComponent: Item {
                id: fl
                // Blur and Frosted are meant to be properly blurry (the slider used to move ~1.4 px per step and barely
                // showed): 2.5× the Liquid Glass radius, blurred at half / quarter size so the strong end stays cheap
                readonly property real px: g.blur * 2.5
                readonly property real m: Math.max(24, px * 1.2)     // backdrop captured around the slab, so the blur has pixels to pull in
                readonly property real ds: px >= 48 ? 0.25 : (px >= 8 ? 0.5 : 1.0)
                anchors.fill: parent
                ShaderEffectSource {
                    id: fsrc
                    sourceItem: g.backdrop
                    hideSource: true
                    live: true
                    visible: false
                    sourceRect: Qt.rect(g.bx - fl.m, g.by - fl.m, g.width + 2 * fl.m, g.height + 2 * fl.m)
                    textureSize: Qt.size(Math.max(1, Math.round(sourceRect.width * fl.ds)), Math.max(1, Math.round(sourceRect.height * fl.ds)))
                }
                Rectangle {
                    id: fmask
                    width: g.width; height: g.height
                    radius: g.cornerR
                    color: "black"
                    visible: false
                    layer.enabled: true
                }
                Item {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: MultiEffect { maskEnabled: true; maskSource: fmask }
                    MultiEffect {
                        x: -fl.m; y: -fl.m
                        width: g.width + 2 * fl.m; height: g.height + 2 * fl.m
                        source: fsrc
                        blurEnabled: true
                        blurMax: 64
                        blur: Math.min(1.0, fl.px * fl.ds / 32.0)
                        autoPaddingEnabled: false
                        saturation: 0.25            // frosted glass desaturates a little, like macOS
                    }
                }
            }
        }
        Rectangle {
            visible: !g.liquid
            anchors.fill: parent
            radius: g.cornerR
            // lighter than it was: the tint hid the blur under it
            // full tint (Opaque / Game Mode) is a solid card
            color: g.tint >= 0.99 ? (g.dark ? Qt.rgba(0.12, 0.12, 0.13, 1) : Qt.rgba(0.97, 0.97, 0.98, 1))
                 : (g.dark ? Qt.rgba(0.12, 0.12, 0.13, 0.16 + g.tint * 0.62) : Qt.rgba(1, 1, 1, 0.18 + g.tint * 0.55))
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
                        if (status === ShaderEffect.Error) { console.log("[macbar-glass] shader failed:", log); g.shaderError(); }
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
                    property real rimTint: 0
                    property real ringW: 0
                    property real flatInner: 0
                    property real saturation: 1.25
                    property real dark: g.dark ? 1 : 0
                    property real debug: g.debug ? 1 : 0
                    property real shadowAmt: 1
                }
            }
        }

        // Settings → Appearance → Tint colour: an accent wash over the finished slab, so it reads on
        // Liquid Glass and Frosted alike (under the glass it was simply painted over).
        Rectangle {
            anchors.fill: parent
            radius: g.cornerR
            visible: g.tintHue.a > 0
            color: Qt.rgba(g.tintHue.r, g.tintHue.g, g.tintHue.b, 0.08 + g.tint * 0.18)
        }
    }

    // Context for a group of glass slabs that all read ONE shared backdrop texture, so a whole panel full of
    // tiles and buttons costs a single backdrop capture instead of one per slab.
    component GlassCtx: QtObject {
        property var src: null                          // the ShaderEffectSource holding the backdrop
        property rect srcRect: Qt.rect(0, 0, 1, 1)      // where that texture sits, in `frame` coordinates
        property Item frame: null                       // coordinate space of srcRect (the popover layer)
        property bool liquid: false
        // Frosted / Blur: the same backdrop, no refraction. Without this the non-liquid materials fell back to a
        // flat translucent rectangle that relied on a compositor blur rule the bar layer never had.
        property bool blurred: false
        property url shaderUrl: ""
        property bool dark: true
        property real tint: 0.4
        property real strength: 1.0
        property real blur: 5               // base backdrop blur radius, px (settings slider)
        property real blurMul: 1.0          // scales the backdrop blur radius of every slab in this context
        property real liquidMul: 1.0        // scales refraction / dispersion / magnify of every slab in this context
        property real paneOpacity: 1.0      // <1 lets the compositor blur show through the shader pane
        property real rim: 0.45
        property real grain: 0.03
        property bool debug: false
        signal failed()
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
        readonly property real pad: 10

        // position inside the popover layer; reads every ancestor's x/y so it re-evaluates when anything moves
        function framePos() {
            var px = 0, py = 0, it = gg;
            while (it && it !== gx.frame) { px += it.x; py += it.y; it = it.parent; }
            return Qt.point(px, py);
        }
        readonly property point fp: framePos()

        readonly property bool shaded: (gg.gx.liquid || gg.gx.blurred) && gg.gx.src !== null
        Rectangle {
            visible: !gg.shaded
            anchors.fill: parent
            radius: gg.cornerR
            // no backdrop to work with (Opaque, or the shader failed): a plain card. Full tint (Opaque / Game Mode)
            // is solid in both looks: light used to stop at 55 % white, so in Opaque the light tiles were see-through.
            color: gg.gx.tint >= 0.99 ? (gg.gx.dark ? Qt.rgba(0.10, 0.10, 0.11, 1) : Qt.rgba(0.97, 0.97, 0.98, 1))
                 : (gg.gx.dark ? Qt.rgba(0.10, 0.10, 0.11, gg.gx.tint) : Qt.rgba(1, 1, 1, gg.gx.tint * 0.55))
            border.width: 1
            border.color: gg.gx.dark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(0, 0, 0, 0.12)
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                color: "transparent"
                border.width: 1
                border.color: gg.gx.dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.45)
            }
        }
        Loader {
            anchors.fill: parent
            active: gg.shaded && gg.visible
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
                    readonly property real liq: gg.gx.liquid ? 1 : 0
                    property real thickness: liq * gg.thickness * gg.gx.strength * gg.strengthMul * gg.gx.liquidMul * 1.6
                    property real dispersion: liq * 0.06 * gg.gx.strength * gg.strengthMul * gg.gx.liquidMul * 1.3
                    property real magnify: liq * 0.05 * gg.gx.strength * gg.strengthMul * gg.gx.liquidMul * 1.6
                    property real rim: gg.gx.liquid ? gg.gx.rim : gg.gx.rim * 0.35
                    property real grain: gg.gx.grain * 0.2
                    property real blurPx: 1.5
                    property real tintMix: gg.gx.tint * 0.55 * gg.tintMul
                    property real rimTint: 0
                    property real ringW: 0
                    property real flatInner: 0
                    property real saturation: 1.25
                    property real dark: gg.gx.dark ? 1 : 0
                    property real debug: gg.gx.debug ? 1 : 0
                    property real shadowAmt: gg.shadowAmt
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
        GGlass { anchors.fill: parent; gx: tile.gx; cornerR: tile.radius; thickness: 22; shadowAmt: 0.45 }
        // a subtle light line follows the outline while the pointer is over the tile, brightest near the pointer
        HoverHandler { id: tileHov }
        ContourGlow {
            z: 50; pad: 8
            cornerR: tile.radius
            hovered: tileHov.hovered
            at: tileHov.point.position
            glowColor: tile.t.dark ? "white" : tile.t.accent
            opacity: 0.55
        }
    }

    // small glass pill button ("Edit Controls", "Done", "Reset")
    component CCPill: Item {
        id: pl
        required property var t
        required property var gx
        property string text: ""
        property bool strong: false
        signal clicked()
        // whole, even pixels so the padding is identical on both sides
        width: 2 * Math.round((plText.implicitWidth + 34) / 2); height: 28
        GGlass { anchors.fill: parent; gx: pl.gx; cornerR: 14; thickness: 14; strengthMul: 0.6; shadowAmt: 0.4 }
        Rectangle {
            anchors.fill: parent; radius: 14
            color: pla.containsMouse ? (pl.t.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.34)) : Qt.rgba(1, 1, 1, 0)
        }
        Text {
            id: plText
            anchors.centerIn: parent
            text: pl.text
            color: pl.t.fg; font.family: pl.t.fam; font.pixelSize: 12
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
        property bool glass: true          // false when the tile under it already is the glass (1×1 buttons fill their tile)
        signal clicked()
        property bool bounce: false
        width: d; height: d
        scale: (bounce && bma.pressed) ? 0.88 : 1
        Behavior on scale { NumberAnimation { duration: 230; easing.type: Easing.OutBack; easing.overshoot: 3.2 } }
        GGlass { visible: b.glass; anchors.fill: parent; gx: b.gx; cornerR: b.d / 2; thickness: 14; strengthMul: 0.6; shadowAmt: b.shadow }
        Rectangle {
            anchors.fill: parent
            radius: b.d / 2
            color: b.on ? (b.onTint !== "" ? Qt.color(b.onTint) : Qt.rgba(b.t.accent.r, b.t.accent.g, b.t.accent.b, 0.92))
                        : (bma.containsMouse ? (b.t.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.34)) : Qt.rgba(1, 1, 1, 0))
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
            width: b.d * 0.46; height: width
            kind: b.kind; level: b.level; flag: b.flag
            color: b.on ? "white" : b.t.fg
            Behavior on color { ColorAnimation { duration: 320; easing.type: Easing.OutCubic } }
        }
        MouseArea { id: bma; anchors.fill: parent; hoverEnabled: true; onClicked: b.clicked() }
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
                    Rectangle { z: 2; anchors.fill: parent; radius: knob.rad; color: "transparent"; border.width: 0.8; border.color: Qt.rgba(1, 1, 1, s.gx.dark ? 0.32 : 0.6) }
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
                font.family: ar.t.fam; font.pixelSize: 13
                font.weight: ar.selected ? Font.DemiBold : Font.Normal
            }
            Text {
                visible: ar.sub !== ""
                width: parent.width
                elide: Text.ElideRight
                text: ar.sub
                color: ar.t.fg2
                font.family: ar.t.fam; font.pixelSize: 11
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
                font.family: nb.t.fam; font.pixelSize: nb.urgency === 2 ? 12 : 14
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
                font.family: nb.t.fam; font.pixelSize: 14; font.weight: Font.Bold
                wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: nb.body
                horizontalAlignment: /[\u0590-\u08ff]/.test(text) ? Text.AlignRight : Text.AlignLeft
                visible: text !== ""
                color: nb.t.fg
                font.family: nb.t.fam; font.pixelSize: 13
                wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
            }
        }
        Text {
            visible: nb.showTime && !nb.showClose
            anchors.right: parent.right; anchors.rightMargin: 14
            y: 15
            text: nb.agoText
            color: nb.t.fg2
            font.family: nb.t.fam; font.pixelSize: 12
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
            text: r.title; color: r.t.dark ? "#F5F5F7" : "#1D1D1F"
            font.family: r.t.fam; font.pixelSize: 13
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
    component PSwitch: LiquidSwitch {
        required property var t
        accent: t.accent; offColor: t.switchOff; dark: root.effDark; material: root.material
    }
    component PSlider: Item {
        id: ps
        required property var t
        property real from: 0
        property real to: 1
        property real value: 0
        signal moved(real v)
        width: 190; height: 24
        LiquidSlider {
            width: parent.width
            value: ps.to > ps.from ? (ps.value - ps.from) / (ps.to - ps.from) : 0
            accent: ps.t.accent; trackColor: ps.t.track; dark: root.effDark; material: root.material
            onMoved: v => ps.moved(Math.round((ps.from + v * (ps.to - ps.from)) * 100) / 100)
        }
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
                        anchors.centerIn: parent; text: parent.modelData
                        color: sg.t.dark ? "#F5F5F7" : "#1D1D1F"
                        font.family: sg.t.fam; font.pixelSize: 12
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
        return root.showDate ? Qt.formatDateTime(d, "ddd d MMM") + "  " + t : t;
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
        if (activeAppId === "") return "Desktop";
        // MacShell's own windows (all "org.quickshell")
        // MacShell's own windows, and apps standing in for them (Swift / Cider as Apple Music): the Dock's names
        var d = hub ? hub.dock : null;
        var id = d ? (activeAppId === "org.quickshell" ? (d.ownApps[activeTl.title] || "") : activeAppId) : activeAppId;
        if (id === "") return "MacShell";
        var e = lookup(id);
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
        // muted (or turned all the way down) means silent: interface sounds too
        if (!uiSounds || gaming || muted || volume < 0.005) return;
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
    onMutedChanged: { showOsd("volume", muted ? 0 : volume); syncMuteLed("speaker", muted); }
    // the laptop's mute / mic-mute key lights follow the sound card's own switches: keep those in step
    function syncMuteLed(what, on) {
        Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr-macshell/scripts/macshell-mute-led.sh", what, on ? "on" : "off"]);
    }
    Timer { interval: 2500; running: true; onTriggered: { root.syncMuteLed("speaker", root.muted); root.syncMuteLed("mic", root.micMuted); } }
    Timer { id: osdTimer; interval: 1500; onTriggered: root.osdVisible = false }
    Timer { interval: 1200; running: true; repeat: false; onTriggered: root.osdReady = true }
    function setVolume(v) { osdQuiet("volume", 600); if (sink && sink.audio) { sink.audio.muted = false; sink.audio.volume = Math.max(0, Math.min(1, v)); } }
    function toggleMute() { osdQuiet("volume", 600); if (sink && sink.audio) sink.audio.muted = !sink.audio.muted; }
    readonly property var micSource: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [root.micSource] }
    readonly property bool micMuted: (micSource && micSource.audio) ? micSource.audio.muted : true
    function toggleMicMute() { osdQuiet("volume", 600); if (micSource && micSource.audio) micSource.audio.muted = !micSource.audio.muted; }
    // the mic-mute key (or Alt + mute) shows the HUD with the microphone, crossed out while muted
    onMicMutedChanged: { showOsd("mic", micMuted ? 0 : micVolume); syncMuteLed("mic", micMuted); }
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
    // Media players that really exist: Quickshell can keep a player whose app has quit (a closed Firefox tab stays
    // "Playing" forever), and picking that one made the controls and the lyrics talk to nothing. The bus is asked
    // which players are there; when that can't be answered, nothing is filtered.
    property var liveMpris: ({})
    Process {
        id: mprisBusProc
        command: ["sh", "-c", "busctl --user --no-pager --no-legend list 2>/dev/null | awk '$1 ~ /^org\\.mpris\\.MediaPlayer2\\./ && $2 != \"-\" {print $1}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var m = {}, l = text.split("\n"), any = false;
                for (var i = 0; i < l.length; i++) if (l[i].trim() !== "") { m[l[i].trim()] = true; any = true; }
                if (JSON.stringify(m) !== JSON.stringify(root.liveMpris)) root.liveMpris = any ? m : ({});
            }
        }
    }
    Timer { interval: 3000; repeat: true; running: true; triggeredOnStart: true; onTriggered: if (!mprisBusProc.running) mprisBusProc.running = true }
    function playerAlive(p) {
        var m = root.liveMpris, k;
        for (k in m) return m[p.dbusName] === true;     // known list: the player must be on it
        return true;                                    // nothing known (no busctl): trust Quickshell
    }
    readonly property var player: {
        var ps = Mpris.players.values, best = null;
        for (var i = 0; i < ps.length; i++) {
            if (!root.playerAlive(ps[i])) continue;
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
        // while we are the hotspot the adapter cannot scan, so the list would otherwise go empty
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
                var hs = root.hub && root.hub.dock ? root.hub.dock.hotspotSsid : "";
                var arr = [], k;
                for (k in best) {
                    if (hs !== "" && k === hs) continue;        // our own hotspot is not somewhere to join
                    arr.push(best[k]);
                }
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

    // bluetooth
    property bool btOn: false
    property int btConnected: 0
    function refreshBt() { if (!btProc.running) btProc.running = true; }
    Process {
        id: btProc
        command: ["sh", "-c", "bluetoothctl show 2>/dev/null | grep -i 'Powered:' | head -n1; bluetoothctl devices Connected 2>/dev/null | wc -l"]
        stdout: StdioCollector {
            onStreamFinished: {
                var l = text.split("\n");
                root.btOn = (l[0] || "").toLowerCase().indexOf("yes") >= 0;
                root.btConnected = parseInt(l[1]) || 0;
            }
        }
    }
    function toggleBt() {
        root.btOn = !root.btOn;
        Quickshell.execDetached(["bluetoothctl", "power", root.btOn ? "on" : "off"]);
        settleTimer.restart();
    }
    readonly property bool airplane: !wifiOn && !btOn
    function toggleAirplane() {
        sh(airplane ? "rfkill unblock all" : "rfkill block all");
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
    // The backlight file changes the instant the key is pressed, so the HUD appears with the key instead of up to
    // 850 ms later. The slow poll stays as a safety net for machines where the file cannot be watched.
    property string backlightDev: ""
    Process {
        running: true
        command: ["sh", "-c", "ls /sys/class/backlight 2>/dev/null | head -n1"]
        stdout: StdioCollector { onStreamFinished: root.backlightDev = text.trim() }
    }
    property real backlightMax: 0
    FileView {
        path: root.backlightDev === "" ? "" : "/sys/class/backlight/" + root.backlightDev + "/max_brightness"
        printErrors: false
        onLoaded: root.backlightMax = parseFloat(text()) || 0
    }
    FileView {
        id: backlightNow
        path: root.backlightDev === "" ? "" : "/sys/class/backlight/" + root.backlightDev + "/brightness"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            if (root.backlightMax <= 0) return;
            var v = (parseFloat(text()) || 0) / root.backlightMax;
            if (Math.abs(v - root.brightness) < 0.004) return;
            root.brightness = Math.max(0, Math.min(1, v));
        }
    }
    Timer { interval: root.backlightDev === "" ? 850 : 5000; repeat: true; running: true; onTriggered: root.refreshBrightness() }
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
    // ═════════════ KEYBOARD LAYOUT ═════════════
    // Hyprland announces every change with an `activelayout` event, so the label updates immediately (no polling).
    // `hyprctl devices` is only read at start-up and after a config reload, to learn which layouts are configured.
    readonly property var kbNames: ({
        us: "English (US)", gb: "English (UK)", ca: "Canadian", au: "English (Australian)", ie: "Irish", in: "Indian",
        ru: "Russian", ua: "Ukrainian", by: "Belarusian", bg: "Bulgarian", rs: "Serbian", hr: "Croatian", si: "Slovenian", mk: "Macedonian",
        de: "German", at: "German (Austria)", ch: "Swiss", fr: "French", be: "Belgian", es: "Spanish", latam: "Spanish (Latin American)",
        it: "Italian", pt: "Portuguese", br: "Portuguese (Brazil)", nl: "Dutch", se: "Swedish", no: "Norwegian", dk: "Danish", fi: "Finnish",
        is: "Icelandic", pl: "Polish", cz: "Czech", sk: "Slovak", hu: "Hungarian", ro: "Romanian", gr: "Greek", tr: "Turkish",
        il: "Hebrew", ara: "Arabic", ir: "Persian", pk: "Urdu", bd: "Bangla", th: "Thai", vn: "Vietnamese", jp: "Japanese", kr: "Korean",
        cn: "Chinese", tw: "Taiwanese", mn: "Mongolian", ge: "Georgian", am: "Armenian", kz: "Kazakh", ee: "Estonian", lv: "Latvian", lt: "Lithuanian"
    })
    function refreshKeyboardLayout() { if (!kbdProc.running) kbdProc.running = true; }
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
                    root.kbMain = k.name || "";
                    root.kbLayouts = list;
                    root.kbSetActive(k.active_keymap || "", k.active_layout_index);
                } catch (err) { }
            }
        }
    }
    function kbSetActive(name, idx) {
        var L = kbLayouts, found = -1, i;
        var n = String(name || "").toLowerCase();
        if (idx !== undefined && idx !== null && idx >= 0 && idx < L.length) found = idx;
        for (i = 0; found < 0 && i < L.length; i++) if (L[i].name.toLowerCase() === n) found = i;
        for (i = 0; found < 0 && i < L.length; i++) if (n !== "" && n.indexOf(L[i].name.toLowerCase().split(" ")[0]) === 0) found = i;
        if (found >= 0) {
            kbIndex = found;
            keyboardLayout = L[found].code.substring(0, 2).toUpperCase();
        } else if (n !== "") {
            keyboardLayout = String(name).replace(/[^A-Za-z]/g, "").substring(0, 2).toUpperCase() || "??";
        }
    }
    function switchKeyboardLayout(i) {
        var n = kbLayouts.length;
        if (n < 2) return;
        i = ((i % n) + n) % n;
        kbIndex = i; keyboardLayout = kbLayouts[i].code.substring(0, 2).toUpperCase();    // show it right away, the event confirms it
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", String(i)]);
    }
    function cycleKeyboardLayout(step) { switchKeyboardLayout(kbIndex + (step === undefined ? 1 : step)); }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout") {
                var d = String(event.data), c = d.indexOf(",");
                if (c < 0) return;
                if (root.kbMain !== "" && d.substring(0, c) !== root.kbMain) return;
                root.kbSetActive(d.substring(c + 1), undefined);
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
        if (privacy.cam.length > 0) a.push({ k: "cam", glyph: "camera", c: "#30D158", title: I18n.tr("Camera"), sub: privacy.cam.join(", ") });
        if (privacy.share.length > 0) a.push({ k: "share", glyph: "monitor", c: "#BF5AF2", title: I18n.tr("Screen Sharing"), sub: privacy.share.join(", ") });
        if (recording) a.push({ k: "rec", glyph: "monitor", c: "#BF5AF2", title: I18n.tr("Screen Recording"), sub: "Recording " + recTime() });
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
        command: ["sh", "-c", "find \"$HOME\" -type f -iname \"*$1*\" -not -path '*/.cache/*' -not -path '*/.local/share/Trash/*' 2>/dev/null | head -n 8", "sh", root.fileQuery]
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
    // Hyprland 0.55+ is configured and driven in Lua: `hyprctl dispatch` takes a Lua expression (the old "killactive" style strings fail).
    function hlx(expr) { Quickshell.execDetached(["hyprctl", "dispatch", expr]); }
    function disp(expr) { return function () { root.hlx(expr); }; }
    // Menu shortcuts are sent to the focused window with Hyprland's sendshortcut (no extra tool needed).
    // If some app ignores them, set this to true to type them with wtype instead.
    readonly property bool keysViaWtype: false
    function keys(mods, k) {
        return function () {
            if (root.keysViaWtype) {
                var a = ["wtype"], i;
                for (i = 0; i < mods.length; i++) a.push("-M", mods[i]);
                a.push("-k", k);
                for (i = mods.length - 1; i >= 0; i--) a.push("-m", mods[i]);
                Quickshell.execDetached(a);
            } else {
                var m = mods.map(function (x) { return x.toUpperCase(); }).join(" + ");
                root.hlx('hl.dsp.send_shortcut({ mods = "' + m + '", key = "' + k + '" })');
            }
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
        if (region === "sel") shotRegion();
        else shotFinish(region, "");
    }
    // Picking an area goes to Flameshot when it is installed (draw, blur, pin, upload…), otherwise to the built-in picker
    readonly property string flameshotCmd: Quickshell.env("HOME") + "/.config/hypr-macshell/scripts/macshell-flameshot.sh"
    property bool useFlameshot: false
    Process {
        running: true
        command: ["sh", "-c", "[ -x \"$1\" ] && exec \"$1\" --check", "sh", root.flameshotCmd]
        onExited: (code, status) => root.useFlameshot = code === 0
    }
    function shotRegion() {
        if (useFlameshot) Quickshell.execDetached([flameshotCmd, "gui"]);
        else shotStart();
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
    function closeCC() { ccRequest(false); }
    // Settings → Wi-Fi → Join…: the Wi-Fi menu opens with that network's password field
    signal wifiJoinRequest(string ssid)
    function wifiJoin(ssid) { wifiJoinRequest(ssid); }
    function notify(title, body) { Quickshell.execDetached(["notify-send", "-a", "MacShell", String(title), String(body || "")]); }
    IpcHandler {
        target: "controlcenter"
        function toggle(): void { root.ccRequest(true); }
        function open(): void { root.ccRequest(true); }
        function close(): void { root.ccRequest(false); }
        // Settings → Control Center → "Animate when opening"; here too, for scripts and demos
        function animate(on: bool): void { root.ccAnimate = on; }
        // where the panel is on screen, as "x y w h" (screen coordinates) — empty when it is closed
        function geometry(): string { return root.ccGeom; }
    }
    // qs -c MacShell ipc call appearance material liquid|frosted|blur|opaque — the whole system at once
    IpcHandler {
        target: "appearance"
        function material(m: string): void { root.applyMaterial(m); root.material = m; }
        // one switch for the whole system: the bar, the Dock, Settings, every app window and the widgets
        function dark(on: bool): void {
            if (root.hub && root.hub.dock && root.hub.dock.setLook) root.hub.dock.setLook("darkMode", on);
            else root.darkMode = on;
        }
        function light(): void { root.hub && root.hub.dock ? root.hub.dock.setLook("darkMode", false) : root.darkMode = false; }
        function accent(c: string): void { root.accent = c; }
        function tint(v: real): void { root.glassOpacity = Math.max(0, Math.min(1, v)); root.materialTouched(); }
        function tintcolor(k: string): void { root.tintAccent = (k === "accent"); root.materialTouched(); }
        function realtime(on: bool): void { root.glassRealtime = on; }
        function barglass(on: bool): void { root.barGlass = on; }
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
    onSettingsReadyChanged: { clipStart(); emojiEnsure(); solidDelay.restart(); }
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
        return "Copied " + Qt.formatDateTime(d, "d MMM") + ", " + tm;
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
        var secs = [{ name: I18n.tr("Suggestions"), apps: sug }];
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
        return r.length > 0 ? [{ name: I18n.tr("Top Hits"), apps: r }] : [];
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
            out.push({ title: r[i].name, sub: r[i].genericName || "Application", icon: iconSrc(r[i].icon),
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
            out.push({ title: all[i].title, sub: "Action", icon: "", glyph: all[i].glyph,
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
        return {title:Number(result.toPrecision(7))+" "+b,sub:"Unit conversion",glyph:"link",run:function(){Quickshell.execDetached(["wl-copy",String(result)]);}};
    }
    function windowItems(q) {
        var out=[], s=(q||"").trim().toLowerCase(); if(!s)return out;
        var ts=Hyprland.toplevels.values;
        for(var i=0;i<ts.length&&out.length<4;i++){
            var t=ts[i], o=t.lastIpcObject||{}, title=String(o.title||t.title||""), cls=String(o["class"]||t.appId||""), app=root.lookup(cls), label=title||app&&app.name||cls;
            if((label+" "+cls+" "+(app?app.name:" ")).toLowerCase().indexOf(s)<0)continue;
            var addr=String(o.address||t.address||""); if(addr!=="" && addr.indexOf("0x")!==0) addr="0x"+addr;
            (function(win,addr,workspace,cl,name,icon){out.push({title:name,sub:"Open Window",icon:icon||"",glyph:"layers",run:function(){root.swPending={addr:addr,ws:workspace,cls:cl};swFocusTimer.restart();}});})(t,addr,o.workspace&&o.workspace.id>0?o.workspace.id:0,cls,label,app?root.iconSrc(app.icon):"");
        }
        return out;
    }
    function fileItems(q) {
        var out=[]; for(var i=0;i<fileHits.length&&out.length<5;i++){var path=fileHits[i];out.push({title:path.substring(path.lastIndexOf("/")+1)||path,sub:path,glyph:"folder",run:(function(p){return function(){if(hub&&hub.openPath)hub.openPath(p);else Quickshell.execDetached(["xdg-open",p]);};})(path)});} return out;
    }
    function homeItems(q) {
        var out = [], s = (q || "").trim().toLowerCase();
        if (s.indexOf("file ") === 0 || s.indexOf("find ") === 0) {
            var fq=s.replace(/^(file|find)\s+/,"").trim(); if(fq!=="" && fileQuery!==fq) updateFileSearch(fq);
            out=fileItems(fq); if(out.length===0) out.push({title:fileSearchPending?I18n.tr("Searching files…"):I18n.tr("No matching files"),sub:"Files",glyph:"folder",run:function(){}});
            return out;
        }
        if(s.length>0) out=appItems(q,4);
        var cv=conversion(s); if(cv) out.unshift(cv);
        else { var expr=s.replace(/^=\s*/,""); var v=calcValue(expr); if(v!==null && (s.charAt(0)==="=" || /[+*/%xX×÷()]/.test(s))) out.unshift({title:String(Number(v.toPrecision(10))),sub:"Calculator · Return to copy",glyph:"search",run:function(){Quickshell.execDetached(["wl-copy",String(v)]);}}); }
        var wins=windowItems(q); for(var j=0;j<wins.length&&out.length<6;j++)out.push(wins[j]);
        var acts=actionItems(q); for(var k=0;k<acts.length&&out.length<6;k++)if(acts[k].title.toLowerCase().indexOf(s)===0)out.push(acts[k]);
        if(s.length>0 && out.length<7) out.push({title:"Search the web for “"+q.trim()+"”",sub:"Web Search · Return to open",glyph:"search",run:function(){Quickshell.execDetached(["xdg-open","https://search.brave.com/search?q="+encodeURIComponent(q.trim())]);}});
        return out.slice(0,8);
    }

    function menuModelFor(name) {
        var m = [], i;
        if (name === "apple") {
            m.push(mi(I18n.tr("About This Computer"), "", function () {
                if (hub && hub.about) hub.about.open();
                else root.openSettings("about");
            }));
            m.push(msep());
            m.push(mi(I18n.tr("System Settings\u2026"), "", function () { root.openSettings("general"); }));
            m.push(msep());
            m.push(mi(I18n.tr("Lock Screen"), "", function () { root.lockScreen(); }));
            m.push(mi(I18n.tr("Sleep"), "", function () { root.sleepMachine(); }));
            m.push(msep());
            m.push(mc("Restart\u2026", function () { sh("systemctl reboot"); }));
            m.push(mc("Shut Down\u2026", function () { sh("systemctl poweroff"); }));
            m.push(msep());
            m.push(mc("Log Out\u2026", function () { root.logOut(); }));
        } else {
            var id = activeAppId.toLowerCase(), kind = appKind(id), has = activeAppId !== "";
            var aw = (has && activeWin && String(activeWin["class"]).toLowerCase() === id) ? activeWin : null;
            var term = kind === "terminal", browser = kind === "browser", files = kind === "files", editor = kind === "editor";
            var floating = aw ? aw.floating === true : false, fsMode = aw ? Number(aw.fullscreen) : 0;
            var n = appName;

            if (name === "app") {
                if (!has) {
                    m.push(mi(I18n.tr("New Terminal"), "", function () { sh(terminal); }));
                    m.push(mi(I18n.tr("Open Home Folder"), "", function () { if (hub && hub.openFolder) hub.openFolder(Quickshell.env("HOME")); else sh(filesCmd); }));
                    m.push(msep());
                    m.push(mi(I18n.tr("Search\u2026"), "", function () { root.search(); }));
                } else {
                    m.push(mi(I18n.tr("About ") + n, "", function () { root.aboutActive(aw, n); }));
                    if (editor || files) {
                        m.push(msep());
                        m.push(mi(I18n.tr("Preferences\u2026"), "Ctrl+,", keys(["ctrl"], "comma")));
                    }
                    m.push(msep());
                    m.push(mi(I18n.tr("Hide ") + n, "", disp('hl.dsp.window.move({ workspace = "special:hidden", follow = false })')));
                    m.push(mi(I18n.tr("Show Hidden Windows"), "", disp('hl.dsp.workspace.toggle_special("hidden")')));
                    m.push(msep());
                    m.push(mi(I18n.tr("Quit ") + n, "Ctrl+Q", function () { root.quitActive(); }));
                    m.push(mc("Force Quit " + n, function () { root.forceQuitActive(aw); }));
                }
            } else if (name === "file") {
                if (!has) {
                    m.push(mi(I18n.tr("New Terminal"), "", function () { sh(terminal); }));
                    m.push(mi(I18n.tr("New Finder Window"), "", function () { if (hub && hub.openFolder) hub.openFolder(Quickshell.env("HOME")); else sh(filesCmd); }));
                } else {
                    m.push(mi(I18n.tr("New Window"), "", function () { root.launchActive(); }));
                    if (browser) {
                        var ff = /firefox|librewolf|floorp|zen|waterfox/.test(id);
                        m.push(mi(I18n.tr("New Private Window"), ff ? "Ctrl+Shift+P" : "Ctrl+Shift+N", keys(["ctrl", "shift"], ff ? "p" : "n")));
                    }
                    if (browser || files) m.push(mi(I18n.tr("New Tab"), "Ctrl+T", keys(["ctrl"], "t")));
                    if (term) m.push(mi(I18n.tr("New Tab"), "Ctrl+Shift+T", keys(["ctrl", "shift"], "t")));
                    if (browser) m.push(mi(I18n.tr("Reopen Closed Tab"), "Ctrl+Shift+T", keys(["ctrl", "shift"], "t")));
                    if (!term && !files) m.push(mi(I18n.tr("Open\u2026"), "Ctrl+O", keys(["ctrl"], "o")));
                    if (!term && !files) {
                        m.push(msep());
                        m.push(mi(browser ? "Save Page As\u2026" : "Save", "Ctrl+S", keys(["ctrl"], "s")));
                        if (!browser) m.push(mi(I18n.tr("Save As\u2026"), "Ctrl+Shift+S", keys(["ctrl", "shift"], "s")));
                        m.push(mi(I18n.tr("Print\u2026"), "Ctrl+P", keys(["ctrl"], "p")));
                    }
                    m.push(msep());
                    if (browser || files || editor) m.push(mi(I18n.tr("Close Tab"), "Ctrl+W", keys(["ctrl"], "w")));
                    if (term) m.push(mi(I18n.tr("Close Tab"), "Ctrl+Shift+W", keys(["ctrl", "shift"], "w")));
                    m.push(mi(I18n.tr("Close Window"), "", disp('hl.dsp.window.close()')));
                }
                m.push(msep());
                if (aw) m.push(mi(I18n.tr("Screenshot Window"), "", function () { root.shotWindow(aw); }));
                m.push(mi(I18n.tr("Screenshot Selection\u2026"), "", function () { root.shot("sel"); }));
                m.push(mi(I18n.tr("Screenshot Screen"), "", function () { root.shot(""); }));
                m.push(mi(root.recording ? "Stop Screen Recording" : "Start Screen Recording", "", function () { root.toggleRecording(); }));
                m.push(mi(I18n.tr("Pick Color"), "", function () { root.pickColor(); }));
            } else if (name === "edit") {
                if (has && term) {
                    m.push(mi(I18n.tr("Copy"), "Ctrl+Shift+C", keys(["ctrl", "shift"], "c")));
                    m.push(mi(I18n.tr("Paste"), "Ctrl+Shift+V", keys(["ctrl", "shift"], "v")));
                } else if (has) {
                    m.push(mi(I18n.tr("Undo"), "Ctrl+Z", keys(["ctrl"], "z")));
                    m.push(mi(I18n.tr("Redo"), "Ctrl+Shift+Z", keys(["ctrl", "shift"], "z")));
                    m.push(msep());
                    m.push(mi(I18n.tr("Cut"), "Ctrl+X", keys(["ctrl"], "x")));
                    m.push(mi(I18n.tr("Copy"), "Ctrl+C", keys(["ctrl"], "c")));
                    m.push(mi(I18n.tr("Paste"), "Ctrl+V", keys(["ctrl"], "v")));
                    if (browser || editor) m.push(mi(I18n.tr("Paste and Match Style"), "Ctrl+Shift+V", keys(["ctrl", "shift"], "v")));
                    m.push(mi(I18n.tr("Select All"), "Ctrl+A", keys(["ctrl"], "a")));
                    m.push(msep());
                    m.push(mi(I18n.tr("Find\u2026"), "Ctrl+F", keys(["ctrl"], "f")));
                }
                if (has) m.push(msep());
                m.push(mi(I18n.tr("Clipboard History\u2026"), "", function () { root.spotOpen("clip"); }));
                m.push(mi(I18n.tr("Emoji & Symbols"), "", function () { root.spotOpen("emoji"); }));
            } else if (name === "view") {
                if (has) {
                    m.push(mi(fsMode === 2 ? "Exit Full Screen" : "Enter Full Screen", "", disp('hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })')));
                    m.push(msep());
                    m.push(mchk("Floating", "", floating, disp('hl.dsp.window.float({ action = "toggle" })')));
                    m.push(dis(mchk("Pin to All Workspaces", "", aw && aw.pinned === true, disp('hl.dsp.window.pin({ action = "toggle" })')), !floating));
                    m.push(dis(mi(I18n.tr("Center Window"), "", disp('hl.dsp.window.center()')), !floating));
                    m.push(dis(mi(I18n.tr("Toggle Split Direction"), "", disp('hl.dsp.layout("togglesplit")')), floating));
                    if (!term) {
                        m.push(msep());
                        m.push(mi(I18n.tr("Actual Size"), "Ctrl+0", keys(["ctrl"], "0")));
                        m.push(mi(I18n.tr("Zoom In"), "Ctrl+=", keys(["ctrl"], "equal")));
                        m.push(mi(I18n.tr("Zoom Out"), "Ctrl+-", keys(["ctrl"], "minus")));
                    }
                    if (browser || files) {
                        m.push(msep());
                        m.push(mi(I18n.tr("Reload"), "F5", keys([], "F5")));
                        if (browser) {
                            m.push(mi(I18n.tr("Reload Ignoring Cache"), "Ctrl+Shift+R", keys(["ctrl", "shift"], "r")));
                            m.push(mi(I18n.tr("Developer Tools"), "F12", keys([], "F12")));
                        }
                    }
                    m.push(msep());
                }
                m.push(mchk("Dark Mode", "", root.darkMode, function () { root.setDark(!root.darkMode); }));
            } else if (name === "window") {
                if (has) {
                    m.push(mi(I18n.tr("Minimize"), "\u2318M", function () { if (root.hub && root.hub.minimizeActive) root.hub.minimizeActive(); }));
                    m.push(mchk("Zoom", "", fsMode === 1, disp('hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })')));
                    m.push(mi(floating ? "Tile Window" : "Float Window", "", disp('hl.dsp.window.float({ action = "toggle" })')));
                    m.push(msep());
                    m.push(mi(I18n.tr("Move Window Left"), "", disp('hl.dsp.window.move({ direction = "left" })')));
                    m.push(mi(I18n.tr("Move Window Right"), "", disp('hl.dsp.window.move({ direction = "right" })')));
                    m.push(mi(I18n.tr("Make Wider"), "", disp('hl.dsp.window.resize({ x = 100, y = 0, relative = true })')));
                    m.push(mi(I18n.tr("Make Narrower"), "", disp('hl.dsp.window.resize({ x = -100, y = 0, relative = true })')));
                    if (Quickshell.screens.length > 1) m.push(mi(I18n.tr("Move to Next Monitor"), "", disp('hl.dsp.window.move({ monitor = "+1" })')));
                    m.push(mi(I18n.tr("Move to Next Workspace"), "", disp('hl.dsp.window.move({ workspace = "+1" })')));
                    m.push(mi(I18n.tr("Move to Previous Workspace"), "", disp('hl.dsp.window.move({ workspace = "-1" })')));
                    m.push(msep());
                }
                m.push(mi(I18n.tr("Show Hidden Windows"), "", disp('hl.dsp.workspace.toggle_special("hidden")')));
                m.push(mi(I18n.tr("Bring Back Minimized Window"), "\u21E7\u2318M", function () { if (root.hub && root.hub.restoreLast) root.hub.restoreLast(); }));
                var tls = ToplevelManager.toplevels.values;
                if (tls.length > 0) m.push(msep());
                for (i = 0; i < tls.length && i < 8; i++) {
                    (function (w) {
                        var t = (w.title && w.title.length > 0) ? w.title : w.appId;
                        m.push(mchk(t, "", w.activated, function () { w.activate(); }));
                    })(tls[i]);
                }
            } else if (name === "help") {
                m.push(mi(I18n.tr("Search\u2026"), "", function () { root.search(); }));
                if (has) m.push(mi(n + " Help", "", function () { root.helpFor(id, n); }));
                m.push(msep());
                m.push(mi(I18n.tr("Hyprland Keybinds"), "", function () { sh(terminal + " -e sh -c 'hyprctl binds | less'"); }));
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
        function region(): void { root.shotRegion(); }
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
                        font.family: root.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
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
                        font.family: root.fontFamily; font.pixelSize: 13
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

    // ═════════════ GAME MODE ═════════════
    readonly property string gamingScript: Quickshell.env("HOME") + "/.config/hypr-macshell/scripts/macshell-gaming.sh"
    property bool gamingApplied: false
    // after Game Mode turns off it restores blur; if Opaque is still chosen, windows go solid again right after
    onGamingChanged: { gamingApply.restart(); if (!gaming && material === "opaque") { solidApplied = false; solidDelay.interval = 900; solidDelay.restart(); } }
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
        darkMode = true; accent = "#0a84ff"; fontFamily = "Open Runde"; glassOpacity = 0.42; glassBlur = 5; barBgOpacity = 0.10; glassRealtime = true;
        barStyle = "liquid"; use24h = true; showDate = true; showSeconds = false; showBatteryPercent = true;
        showTray = true; showSearch = true;
        spotlightEnabled = true; ccEnabled = true; notificationsEnabled = true; clockAppEnabled = true; ccStyle = "tiles"; ccAnimate = true; material = "liquid"; tlAlwaysSymbols = false; tlColorOnHover = false;
        barLogoMode = "arch"; barCustomLogoPath = "";
        barWidgets = ["appleMenu", "appMenus", "workspaces", "volume", "keyboard", "notifications", "wifi", "bluetooth", "privacy", "controlCenter", "clock"];
        ccControls = ccDefault.slice();
    }

    // inherit look from macdock first, then macbar's own file wins
    FileView {
        id: dockStore
        path: root.dockConfigDir + "/settings.json"
        printErrors: false
        onLoaded: {
            try {
                var o = JSON.parse(text());
                root.applySettings(o, ["darkMode", "accent", "fontFamily", "glassOpacity", "glassRim", "glassGrain", "glassLiquid", "glassBlur", "wallpaperPath"]);
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
            if (!root.ccMigTahoe) {
                root.ccMigTahoe = true;
                var ct = root.ccControls.slice();
                var add = ["battery", "hotspot", "mirror", "lockscreen", "sleep"];
                for (var ai = 0; ai < add.length; ai++) if (ct.indexOf(add[ai]) < 0) ct.push(add[ai]);
                root.ccControls = ct;
            }
            root.settingsReady = true;
            inputApplyT.restart();
            if (root.barStyle === "liquid") root.startGlass();
        }
        onLoadFailed: { root.ccMigRec = true; root.ccMigTahoe = true; root.settingsReady = true; if (root.barStyle === "liquid") root.startGlass(); }
    }

    // ═════════════ LIQUID GLASS BACKEND (same pipeline as macdock) ═════════════
    property string glassState: "idle"       // idle → building → ready | failed
    readonly property bool liquidActive: barStyle === "liquid" && glassState === "ready" && !gaming
    // Blur and Frosted need the same backdrop (wallpaper + live windows) that Liquid Glass refracts — without it
    // there is nothing to blur. Opaque needs none.
    readonly property bool wantBackdrop: liquidActive || (!solidAll && glassBlur > 0.5)
    readonly property string glassShaderSrc: decodeURIComponent(Qt.resolvedUrl("liquidglass.frag").toString().replace("file://", ""))
    readonly property string glassShaderOut: configDir + "/liquidglass.frag.qsb"
    readonly property url glassShaderUrl: "file://" + glassShaderOut

    onBarStyleChanged: { materialTouched(); if (barStyle === "liquid") startGlass(); }
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

    // wallpaper the glass refracts (MacShell's own → whatever awww / swww / hyprpaper shows)
    readonly property var wallpaperMap: hub ? hub.wallpaperMap : ({})
    Binding { target: root.hub; property: "barWantsWallpaper"; value: root.wantBackdrop }
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

    // live window geometry for the backdrop (polled only while a glass popover is open)
    readonly property var monData: hub ? hub.monData : []
    readonly property var glassClients: hub ? hub.glassClients : []
    property int popCount: 0
    onBarEnabledChanged: { if (!barEnabled) popCount = 0; clipStart(); }
    Binding { target: root.hub; property: "barWantsGeo"; value: root.wantBackdrop }
    // window captures are admitted by the shared gate in shell.qml (hub.tlFor): 0.2 s after a window appears, one every 110 ms

    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", configDir]);
        refreshBrightness();
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
    }
    function wpRefresh() {
        if (wpScan.running) return;
        var script = [
            'd="$1"; mk="$2"; shift 2',
            '[ "$mk" = "1" ] && [ ! -d "$d" ] && mkdir -p "$d" 2>/dev/null',
            'if [ -d "$d" ]; then find -L "$d" -maxdepth 3 -type f 2>/dev/null | grep -iE "[.](jpe?g|png|webp|bmp|gif|mp4|webm|mkv|mov|m4v)$" | sort -V | sed "s/^/A:/"; fi',
            // animated wallpapers: a cached thumbnail frame per video
            'tc="$HOME/.cache/macshell/thumbs"; mkdir -p "$tc"',
            'if [ -d "$d" ]; then find -L "$d" -maxdepth 3 -type f 2>/dev/null | grep -iE "[.](mp4|webm|mkv|mov|m4v)$" | while IFS= read -r v; do',
            '  t="$tc/$(printf "%s:%s" "$v" "$(stat -c %Y "$v" 2>/dev/null)" | md5sum | cut -c1-16).jpg"',
            '  [ -s "$t" ] || ffmpeg -loglevel error -y -ss 1 -i "$v" -frames:v 1 -vf "scale=480:-2" "$t" </dev/null >/dev/null 2>&1',
            '  [ -s "$t" ] && printf "T:%s\\t%s\\n" "$v" "$t"',
            // animated preview + optimized playback copy: built once, in the background, at low priority
            '  w="${t%.jpg}.webp"',
            '  if [ -s "$w" ]; then printf "P:%s\\t%s\\n" "$v" "$w"; else setsid nice -n 15 "$HOME/.config/hypr-macshell/scripts/macshell-setwall.sh" --prepare "$v" >/dev/null 2>&1 </dev/null & fi',
            'done; fi',
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
    function wpApplyAppearance() {
        if (!wpHasPair || dynProc.running) return;
        var mode = wallpaperAppearance === "auto" ? (darkMode ? "dark" : "light") : wallpaperAppearance;
        var rise = 390, set_ = 1110;
        try {
            var wx = root.hub && root.hub.widgets ? root.hub.widgets.weather : null;
            if (wx && wx.daily && wx.daily.sunrise) { var a = hhmmToMin(wx.daily.sunrise[0]), b = hhmmToMin(wx.daily.sunset[0]); if (a > 0) rise = a; if (b > 0) set_ = b; }
        } catch (e) {}
        dynProc.command = [dynwallScript, wpPairLight, wpPairDark, mode, String(rise), String(set_)];
        dynProc.running = true;
    }
    Process {
        id: dynProc
        stdout: StdioCollector {
            onStreamFinished: {
                var p = text.trim();
                if (p === "") return;
                root.wallpaperVideo = "";
                root.wallpaperPath = p;
                try { if (root.hub && root.hub.dock) root.hub.dock.wallpaperPath = p; } catch (e) {}
            }
        }
    }
    onWallpaperAppearanceChanged: wpApplyAppearance()
    // the accent is one system setting too: the Dock, Settings and the app windows read the Dock's copy
    onAccentChanged: if (hub && hub.dock && String(hub.dock.accent) !== String(accent)) hub.dock.accent = accent
    onDarkModeChanged: {
        if (wallpaperAppearance === "auto") wpApplyAppearance();
        // Appearance is one system setting: the Dock, Settings and every app window read the Dock's copy, so whichever
        // control was used — Control Center, the Apple menu, Settings, the IPC — both halves stay in step.
        if (hub && hub.dock && hub.dock.darkMode !== darkMode) hub.dock.darkMode = darkMode;
    }
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
        if (pair) { wpPairLight = pair.light; wpPairDark = pair.dark; wpApplyAppearance(); return; }
        wpPairLight = ""; wpPairDark = "";
        // animated wallpapers (and, with no custom wallpaperCmd, pictures too) go through macshell-setwall.sh:
        // mpvpaper for videos, awww for pictures; it prints the still image the glass should refract
        if (root.wpIsVideo(path) || (root.wallpaperCmd || "").trim() === "") {
            root.wallpaperVideo = root.wpIsVideo(path) ? path : "";
            if (!root.wpIsVideo(path)) {
                root.wallpaperPath = path;
                try { if (root.hub && root.hub.dock) root.hub.dock.wallpaperPath = path; } catch (e) {}
            }
            setwallProc.command = [root.setwallScript, path];
            setwallProc.running = true;
            return;
        }
        root.wallpaperPath = path;                                            // the glass refracts the new image straight away
        try { if (root.hub && root.hub.dock) root.hub.dock.wallpaperPath = path; } catch (e) {}
        var cmd = (root.wallpaperCmd || "").trim();
        var script = cmd !== "" ? cmd.split("{}").join('"$1"') : [
            'p="$1"',
            // awww needs its daemon; start it if it is installed but not running yet
            'if command -v awww >/dev/null 2>&1; then',
            '  if ! awww query >/dev/null 2>&1; then',
            '    if command -v awww-daemon >/dev/null 2>&1; then setsid awww-daemon >/dev/null 2>&1 & fi',
            '    for i in 1 2 3 4 5 6 7 8 9 10; do awww query >/dev/null 2>&1 && break; sleep 0.3; done',
            '  fi',
            '  if awww img "$p" --transition-type fade --transition-duration 0.7; then echo "applied with: awww"; exit 0; fi',
            'fi',
            'if command -v swww >/dev/null 2>&1 && swww query >/dev/null 2>&1 && swww img "$p" --transition-type fade --transition-duration 0.7; then echo "applied with: swww"; exit 0; fi',
            'if pgrep -x hyprpaper >/dev/null 2>&1; then',
            '  if hyprctl hyprpaper wallpaper ",$p" >/dev/null 2>&1 || { hyprctl hyprpaper preload "$p" >/dev/null 2>&1; hyprctl hyprpaper wallpaper ",$p" >/dev/null 2>&1; }; then echo "applied with: hyprpaper"; exit 0; fi',
            'fi',
            'if pgrep -x swaybg >/dev/null 2>&1; then pkill -x swaybg; setsid swaybg -i "$p" -m fill >/dev/null 2>&1 & echo "applied with: swaybg"; exit 0; fi',
            'echo "no wallpaper daemon accepted the image (tried awww, swww, hyprpaper, swaybg)" >&2',
            'echo "running: $(ps -eo comm= | grep -E "^(awww-daemon|swww-daemon|hyprpaper|swaybg|wpaperd)$" | sort -u | tr "\\n" " ")" >&2',
            'notify-send "Wallpaper" "Could not set it: no supported wallpaper daemon found. Set wallpaperCmd in settings.json." 2>/dev/null',
            'exit 1'
        ].join("\n");
        wpApplyProc.command = ["sh", "-c", script, "sh", path];
        wpApplyProc.running = true;
    }
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
    property int wsMin: 4                    // always show at least workspaces 1..wsMin (set 0 to show only existing ones)
    readonly property var wsIds: {
        var ids = [], vals = Hyprland.workspaces.values;
        for (var i = 1; i <= root.wsMin; i++) ids.push(i);
        for (var j = 0; j < vals.length; j++) {
            var id = vals[j].id;
            if (id > 0 && ids.indexOf(id) < 0) ids.push(id);
        }
        var fw = Hyprland.focusedWorkspace;
        if (fw && fw.id > 0 && ids.indexOf(fw.id) < 0) ids.push(fw.id);
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
            if (id === "" || (hub && hub.dock && hub.dock.hiddenApps[id.toLowerCase()])) continue;
            // MacShell's own windows (all "org.quickshell") are separate apps: Clock, System Settings
            if (id === "org.quickshell") id = t.title === "Clock" ? "macshell-clock"
                                             : (t.title === "macshell Settings" ? "systemsettings" : id);
            if (seen[id] !== undefined) { apps[seen[id]].count++; continue; }
            var e = root.lookup(id);
            seen[id] = apps.length;
            apps.push({ appId: id, cls: t.appId, name: id === "systemsettings" ? I18n.tr("System Settings") : (id === "org.quickshell" ? I18n.tr("MacShell") : (e ? e.name : id)),
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
            var sel = t.addr !== "" ? "address:" + t.addr : "class:^(" + t.cls + ")$";
            lua += "hl.dispatch(hl.dsp.focus({ window = \"" + sel + "\" })); ";
            // and bring it to the front: a floating window buried under another one used to stay buried
            lua += "hl.dispatch(hl.dsp.window.bring_to_top({ window = \"" + sel + "\" }))";
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
            // only while the menu bar is shown: switched off, the wallpaper shows all the way to the top
            visible: root.barEnabled && root.effBarBg > 0.001
            anchors { left: true; right: true; top: true }
            implicitHeight: root.barHeight
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
                // the strip's tint follows what is behind it, like the text does: dark over a dark wallpaper, light over a light one
                color: root.barDark ? Qt.rgba(0.10, 0.10, 0.11, root.effBarBg) : Qt.rgba(1, 1, 1, root.effBarBg)
                Behavior on color { ColorAnimation { duration: 420; easing.type: Easing.OutCubic } }
            }
        }

        PanelWindow {
            id: win
            property var modelData: perScreen.modelData
            screen: perScreen.modelData

            anchors { left: true; right: true; top: true }
            implicitHeight: root.barHeight + root.popRoom
            color: "transparent"

            exclusionMode: ExclusionMode.Normal
            exclusiveZone: root.barEnabled ? root.barHeight : 0

            WlrLayershell.namespace: "macbar"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: (ui.pop === "wifi" && ui.wifiPrompt !== "") ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            mask: Region { item: maskItem; Region { item: toastMask } }

            Item {
                id: ui
                anchors.fill: parent

                property string pop: ""          // "", apple, app, file, edit, view, window, help, cc, cal
                // the Control Center's own state (battery profile, hotspot, keyboard backlight) is only read while it is open
                property real menuX: 0
                property var menuModel: []
                property string armed: ""
                property int calYear: 2026
                property int calMonth: 0
                property string wifiPrompt: ""      // ssid whose password field is open in the Wi-Fi popover
                property bool ccEdit: false         // Control Center is in "Edit Controls" mode
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
                    function onWifiJoinRequest(ssid) {
                        if (!ui.toastScreen) return;
                        if (ui.pop !== "wifi") ui.openPop("wifi", wifiBtn.mapToItem(ui, 0, 0).x);
                        ui.wifiPrompt = ssid;
                        root.scanWifi();
                    }
                }
                readonly property bool toastsShown: toastScreen && notifToasts.count > 0
                // notifications arriving with no panel open: measure what's behind the banners
                onToastsShownChanged: if (toastsShown && pop === "") root.measureTone(win.modelData.x + ui.width - 374, win.modelData.y + root.barHeight + 8, 364, 90)

                // what is behind the menu bar strip, so its text stays readable on any wallpaper (macOS does the same)
                function sampleBar() {
                    if (!ui.toastScreen || !root.barEnabled) return;
                    root.measureBarTone(win.modelData.x, win.modelData.y, ui.width, Math.max(10, root.barHeight));
                }
                // once at startup, then only when something that changes the answer changes
                Timer {
                    interval: 1200
                    running: root.autoContrast && !root.gaming && ui.toastScreen
                    onTriggered: ui.sampleBar()
                }
                // a video wallpaper changes under the bar all the time: follow it
                Timer {
                    interval: 4000; repeat: true
                    running: root.autoContrast && !root.gaming && ui.toastScreen && root.wallpaperVideo !== ""
                    onTriggered: ui.sampleBar()
                }
                Connections {
                    target: root
                    function onWallpaperPathChanged() { ui.sampleBar(); }
                    function onDarkModeChanged() { ui.sampleBar(); }
                function onWallpaperVideoChanged() { ui.sampleBar(); }
                }

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
                    running: ui.pop === "wifi" && ui.wifiPrompt === ""     // paused while typing so the list doesn't rebuild under the cursor
                    onTriggered: root.scanWifi()
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
                    for (var i = 0; i < menuModel.length; i++) if (menuModel[i].checked !== undefined) return true;
                    return false;
                }
                Connections {
                    target: root
                    function onActiveWinChanged() { if (ui.isMenu) ui.menuModel = root.menuModelFor(ui.pop); }
                }
                // bounding box of all glass that is on screen right now (popovers, notification popups) + a refraction margin
                readonly property rect glassRect: {
                    var items = [menuPop, cc, cal, wifiPop, trayPop, notifPop, toastArea, volPop, kbPop, levelOsd], x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9, any = false;
                    for (var i = 0; i < items.length; i++) {
                        var it = items[i];
                        if (!it.visible) continue;
                        any = true;
                        x0 = Math.min(x0, it.x); y0 = Math.min(y0, it.y); x1 = Math.max(x1, it.x + it.width); y1 = Math.max(y1, it.y + it.height);
                    }
                    return any ? Qt.rect(x0 - 64, y0 - 64, x1 - x0 + 128, y1 - y0 + 128) : Qt.rect(0, 0, 0, 0);
                }
                readonly property bool isMenu: ["apple", "app", "file", "edit", "view", "window", "help"].indexOf(pop) >= 0
                readonly property bool anyVisible: menuPop.visible || cc.visible || cal.visible || wifiPop.visible || trayPop.visible || notifPop.visible || toastArea.visible || volPop.visible || kbPop.visible
                onAnyVisibleChanged: root.popCount += (anyVisible ? 1 : -1)
                onPopChanged: {
                    if (ui.toastScreen) root.ccVisible = (pop === "cc");
                    if (pop === "cc") ccGeomT.restart(); else if (ui.toastScreen) root.ccGeom = "";
                    if (pop !== "" && pop !== "spot") toneT.restart();
                    if (pop === "spot" && ui.toastScreen) root.measureTone(win.modelData.x + ui.width / 2 - 320, win.modelData.y + ui.height * 0.4 - 30, 640, 60);
                    armed = "";
                    wifiPrompt = "";
                    spHoverLabel = "";
                    if (pop !== "cc") ccEdit = false;
                    root.notifOpen = (pop === "notif");
                    if (root.notifOpen) root.notifUnread = 0;
                    if (pop === "wifi") { root.wifiError = ""; root.scanWifi(); root.refreshConnections(); }
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
                        if (open) ui.openPop("notif", ui.width); else if (ui.pop === "notif") ui.pop = "";
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
                    active: root.wantBackdrop
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
                    captureSource: (root.wantBackdrop && !root.captureQuiet) ? win.modelData : null
                    live: false
                    paintCursor: false
                    property real takenAt: 0
                    function grab() { if (captureSource && typeof captureFrame === "function") { captureFrame(); takenAt = Date.now(); } }
                }
                property bool snapFresh: false
                // a moment after a popover starts opening (its rect is known), measure what's behind it
                Timer {
                    id: ccGeomT
                    interval: 60
                    onTriggered: {
                        var r = ui.glassRect;
                        if (r.width > 0) root.ccGeom = Math.round(win.modelData.x + r.x) + " " + Math.round(win.modelData.y + r.y)
                                                     + " " + Math.round(r.width) + " " + Math.round(r.height);
                    }
                }
                Timer {
                    id: toneT; interval: 20
                    onTriggered: {
                        var r = ui.glassRect;
                        if (r.width <= 0) return;
                        root.measureTone(win.modelData.x + r.x + 64, win.modelData.y + r.y + 64, r.width - 128, r.height - 128);
                    }
                }
                // Real-time glass refracts the LIVE backdrop (wallpaper + every window captured as it changes), so anything
                // moving under a panel moves under the glass too. The still whole-screen snapshot is the cheap path: it also
                // catches other layers, but it is frozen for as long as the panel is open — which is what "no real-time
                // Liquid Glass" looked like. Screen capture can't be used live here: it would contain the glass itself.
                // Is any glass actually on screen right now? Only then is the live backdrop worth rendering — keeping it
                // alive while nothing is open cost a fifth of a core for pixels nobody saw.
                readonly property bool glassOnScreen: anyVisible || toastsShown || levelOsd.visible || spotWin.openish || swWin.visible || wpWin.visible
                // The composed backdrop (wallpaper + the windows behind us) is the one that never contains the shell
                // itself. The whole-screen snapshot does — refracting it is what drew a ghost of the menu bar inside
                // its own glass — so it is only the fallback while the backdrop is still coming up.
                readonly property Item glassSrc: glassBackdrop.item ? glassBackdrop.item
                                               : ((snapFresh && screenSnap.hasContent) ? screenSnap : null)
                HoverHandler {
                    id: barHover
                    onHoveredChanged: if (hovered && ui.pop === "") screenSnap.grab()
                }
                // refresh while the pointer rests on the bar with nothing open; a snapshot is "fresh" for 3 s
                Timer { interval: 600; repeat: true; running: barHover.hovered && ui.pop === ""; onTriggered: screenSnap.grab() }
                // only while there is a snapshot whose freshness can still change, not for ever
                Timer { interval: 250; repeat: true; running: ui.snapFresh || ui.pop !== ""; onTriggered: ui.snapFresh = (Date.now() - screenSnap.takenAt) < 3000 || (ui.pop !== "" && ui.snapFresh) }

                // keeps the (otherwise unseen) backdrop rendering so its window captures stay valid; draws one 1%-opaque pixel
                ShaderEffectSource {
                    id: backdropAlive
                    sourceItem: glassBackdrop.item
                    hideSource: true
                    // this one pixel is what keeps the whole backdrop rendering: every frame while a panel is open,
                    // and a gentle 10 fps when only the menu bar strip is made of glass
                    live: ui.glassOnScreen
                    width: 1; height: 1
                    opacity: 0.01
                    sourceRect: Qt.rect(0, 0, 1, 1)
                    Timer {
                        interval: 100; repeat: true
                        running: !ui.glassOnScreen && root.barGlass && root.liquidActive && glassBackdrop.item !== null
                        onTriggered: backdropAlive.scheduleUpdate()
                    }
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
                            // always there, under the video: whatever moment the video's first frame arrives, the glass
                            // never shows anything but the wallpaper (the gradient above is only for "no wallpaper at all")
                            visible: status === Image.Ready
                            source: root.fileUrl(root.wallpaperFor(win.modelData.name))
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: bd.width
                            smooth: true
                        }
                        // ── an animated (video) wallpaper: the glass refracts the video itself, frame for frame ──
                        // While glass is on screen, the same file mpvpaper is playing plays here too (muted, hardware
                        // decoded), kept in step with the wallpaper through mpvpaper's control socket: its position is read
                        // when the glass appears and every 3 s, and this copy is nudged back whenever it drifts.
                        Item {
                            id: bdVideo
                            anchors.fill: parent
                            readonly property string sock: Quickshell.env("XDG_RUNTIME_DIR") + "/macshell-mpv-" + win.modelData.name + ".sock"
                            readonly property bool wanted: root.wallpaperVideo !== "" && !root.gaming && bd.hostShown && ui.glassOnScreen
                            property string file: ""
                            property real mpvPos: -1          // seconds, as of mpvAt
                            property real mpvAt: 0
                            readonly property bool showing: wanted && file !== "" && vplayer.playbackState === MediaPlayer.PlayingState && vplayer.position > 0
                            onWantedChanged: { if (wanted) { mpvQ.running = false; mpvQ.running = true; } else vplayer.stop(); }
                            Process {
                                id: mpvQ
                                command: ["sh", "-c", "printf '%s\\n' '{\"command\":[\"get_property\",\"path\"]}' '{\"command\":[\"get_property\",\"time-pos\"]}' | nc -U -N \"$1\" 2>/dev/null", "sh", bdVideo.sock]
                                stdout: StdioCollector {
                                    onStreamFinished: {
                                        var l = text.trim().split("\n");
                                        try {
                                            var f = JSON.parse(l[0]).data, t = JSON.parse(l[1]).data;
                                            if (typeof f !== "string" || typeof t !== "number") return;
                                            bdVideo.mpvPos = t; bdVideo.mpvAt = Date.now();
                                            if (bdVideo.file !== f) bdVideo.file = f;
                                            bdVideo.sync();
                                        } catch (e) {}
                                    }
                                }
                            }
                            Timer { interval: 3000; repeat: true; running: bdVideo.wanted; onTriggered: { if (!mpvQ.running) mpvQ.running = true; } }
                            function sync() {
                                if (!wanted || file === "") return;
                                if (vplayer.source.toString() !== "file://" + file) vplayer.source = "file://" + file;
                                if (vplayer.playbackState !== MediaPlayer.PlayingState) vplayer.play();
                                var d = vplayer.duration > 0 ? vplayer.duration : 0;
                                var want = (mpvPos + (Date.now() - mpvAt) / 1000) * 1000;
                                if (d > 0) want = want % d;
                                if (Math.abs(vplayer.position - want) > 120 && vplayer.seekable) vplayer.position = Math.round(want + 40);
                            }
                            MediaPlayer {
                                id: vplayer
                                loops: MediaPlayer.Infinite
                                videoOutput: vout
                                onMediaStatusChanged: if (mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) bdVideo.sync()
                            }
                            VideoOutput {
                                id: vout
                                anchors.fill: parent
                                fillMode: VideoOutput.PreserveAspectCrop
                                visible: bdVideo.showing
                            }
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
                                    // Real-time only pays off for the windows actually behind glass that is on screen. Keeping every
                                    // window live was what made the refraction lag and tear: the capture arrived a frame or two after
                                    // the window had already moved, so the glass showed the old frame at the new position.
                                    live: !gw.gone && !root.captureHeld && bd.hostShown && (!sv.hush || gw.onGlass)
                                          && ((root.glassRealtime && !root.underLoad && gw.onGlass) || ui.anyVisible || levelOsd.visible || spotWin.openish || swWin.visible || wpWin.visible)
                                    onCaptureSourceChanged: {
                                        // a brand-new capture grabs its first frame immediately instead of waiting for the timer
                                        // (a short delay: asking before the capture context exists only logged "no recording context is ready")
                                        if (captureSource !== null && !live && !sv.hush && !root.captureHeld) firstShot.restart();
                                    }
                                    // a window that just moved or resized grabs a frame at its new size straight away,
                                    // so the glass never refracts the previous frame stretched over the new geometry
                                    Connections {
                                        target: gw
                                        function onWxChanged() { freshShot.restart(); }
                                        function onWyChanged() { freshShot.restart(); }
                                        function onWwChanged() { freshShot.restart(); }
                                        function onWhChanged() { freshShot.restart(); }
                                    }
                                    Timer {
                                        id: freshShot
                                        interval: 30
                                        onTriggered: { if (sv.captureSource !== null && !sv.live && !sv.hush && !root.captureHeld && typeof sv.captureFrame === "function") sv.captureFrame(); }
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
                    height: (ui.pop !== "" && ui.pop !== "spot") ? ui.height : root.barHeight
                }

                // Liquid Glass menu bar strip: the bar itself refracts the live backdrop (wallpaper + windows), like the popovers.
                // Settings → Menu Bar → "Liquid Glass bar". Sits under every bar item.
                LGlass {
                    id: barGlassStrip
                    visible: root.barGlass && root.liquidActive
                    x: 0; y: 0
                    width: ui.width
                    height: root.barHeight
                    backdrop: ui.glassSrc
                    shaderUrl: root.glassShaderUrl
                    liquid: root.liquidActive
                    dark: root.effDark
                    bx: 0; by: 0
                    cornerR: 0
                    tint: root.solidAll ? 1.0 : root.glassOpacity * 0.6
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
                    y: root.barHeight + 14
                    visible: ui.toastScreen && opacity > 0
                    opacity: root.osdVisible ? 1 : 0
                    scale: root.osdVisible ? 1 : 0.88
                    transformOrigin: Item.TopRight
                    transform: Translate { y: root.osdVisible ? 0 : -10 }
                    Behavior on opacity { NumberAnimation { duration: root.osdVisible ? 150 : 260; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.5 } }
                    LGlass {
                        anchors.fill: parent
                        backdrop: ui.glassSrc
                        shaderUrl: root.glassShaderUrl
                        liquid: root.liquidActive
                        dark: root.effDark
                        bx: levelOsd.x; by: levelOsd.y
                        cornerR: height / 2
                        tint: root.effGlassOpacity
                        tintHue: root.tintAccent ? root.accent : "transparent"
                        thickness: 22
                        strength: 0.8 * root.glassLiquid
                        rim: root.glassRim
                        grain: root.glassGrain
                        blur: root.glassBlur
                        debug: root.glassDebug
                        onShaderError: root.glassState = "failed"
                    }
                    // The sun turns a full revolution on every step and its rays grow out of the core as it brightens;
                    // the speaker's waves and its mute cross fade and spring in and out instead of popping.
                    Item {
                        id: osdIcon
                        x: 18; anchors.verticalCenter: parent.verticalCenter
                        width: 28; height: 28
                        readonly property bool bright: root.osdKind === "brightness"
                        readonly property bool mic: root.osdKind === "mic"
                        property real kick: 0
                        property real spin: 0
                        // a small turn per step (with the brightness going up: clockwise), not a whole revolution
                        property real lastBright: 0
                        onSpinChanged: lastBright = root.osdValue
                        scale: 1 + kick * 0.16
                        Behavior on spin { NumberAnimation { duration: 680; easing.type: Easing.OutCubic } }
                        SequentialAnimation {
                            id: kickAnim
                            NumberAnimation { target: osdIcon; property: "kick"; to: 1; duration: 90; easing.type: Easing.OutCubic }
                            NumberAnimation { target: osdIcon; property: "kick"; to: 0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                        }
                        Connections {
                            target: root
                            function onOsdValueChanged() {
                                kickAnim.restart();
                                if (root.osdKind === "brightness") osdIcon.spin += root.osdValue > osdIcon.lastBright ? 30 : -30;
                            }
                        }
                        Glyph {
                            anchors.fill: parent
                            kind: "sun"
                            frac: root.osdValue
                            color: "white"
                            rotation: osdIcon.spin
                            opacity: osdIcon.bright ? 1 : 0
                            scale: osdIcon.bright ? 1 : 0.55
                            visible: opacity > 0.01
                            Behavior on frac { NumberAnimation { duration: 280; easing.type: Easing.OutQuint } }
                            Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                        }
                        Glyph {
                            anchors.fill: parent
                            kind: "mic"
                            flag: root.micMuted
                            color: "white"
                            opacity: osdIcon.mic ? 1 : 0
                            scale: osdIcon.mic ? 1 : 0.55
                            visible: opacity > 0.01
                            Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                        }
                        Item {
                            id: osdSpk
                            anchors.fill: parent
                            readonly property real v: root.osdValue
                            opacity: osdIcon.bright || osdIcon.mic ? 0 : 1
                            scale: osdIcon.bright || osdIcon.mic ? 0.55 : 1
                            visible: opacity > 0.01
                            Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                            Glyph { anchors.fill: parent; kind: "speaker"; parts: "body"; color: "white" }
                            Glyph {
                                anchors.fill: parent; kind: "speaker"; parts: "mute"; color: "white"
                                transformOrigin: Item.Center
                                opacity: osdSpk.v < 0.005 ? 1 : 0
                                scale: osdSpk.v < 0.005 ? 1 : 0.5
                                visible: opacity > 0.01
                                Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                            }
                            Glyph {
                                anchors.fill: parent; kind: "speaker"; parts: "w1"; color: "white"
                                transformOrigin: Item.Center
                                opacity: osdSpk.v >= 0.005 ? 1 : 0
                                scale: osdSpk.v >= 0.005 ? 1 : 0.45
                                visible: opacity > 0.01
                                Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
                            }
                            Glyph {
                                anchors.fill: parent; kind: "speaker"; parts: "w2"; color: "white"
                                transformOrigin: Item.Center
                                opacity: osdSpk.v >= 0.34 ? 1 : 0
                                scale: osdSpk.v >= 0.34 ? 1 : 0.45
                                visible: opacity > 0.01
                                Behavior on opacity { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
                            }
                        }
                    }
                    // one continuous fill that glides to the new level, with the track showing through behind it
                    Item {
                        id: osdBar
                        x: 62; anchors.verticalCenter: parent.verticalCenter
                        width: levelOsd.width - 62 - 26
                        height: 8
                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: Qt.rgba(1, 1, 1, 0.22)
                        }
                        Rectangle {
                            width: Math.max(parent.height, parent.width * Math.max(0, Math.min(1, root.osdValue)))
                            height: parent.height
                            radius: height / 2
                            color: "white"
                            Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
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
                    height: root.barHeight
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
                                    source: root.barDark ? Qt.resolvedUrl("apple-logo-white.svg") : Qt.resolvedUrl("apple-logo-black.svg")
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
                                    text: mt.modelData.label
                                    color: bpal.fg
                                    font.family: bpal.fam
                                    font.pixelSize: 13
                                    font.weight: mt.modelData.bold ? Font.Bold : Font.Normal
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
                                    font.family: bpal.fam
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
                            visible: root.barWidgetEnabled("bluetooth")
                            width: root.barWidgetEnabled("bluetooth") ? 26 : 0; height: 28
                            Glyph { anchors.centerIn: parent; width: 15; height: 15; kind: "bluetooth"; color: root.btOn && root.btConnected > 0 ? bpal.fg : bpal.fg2 }
                            MouseArea { anchors.fill: parent; onClicked: ui.openPop("cc", 0) }
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
                                font.family: bpal.fam; font.pixelSize: 12; font.weight: Font.DemiBold
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
                                    font.family: bpal.fam; font.pixelSize: 12
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
                                            // like macOS: green while charging, yellow in Low Power Mode, red when low
                                            color: root.charging ? "#30D158" : (root.powerProfile === "power-saver" ? "#FFD60A" : (root.batPct <= 15 ? "#FF453A" : bpal.fg))
                                            Behavior on color { ColorAnimation { duration: 320; easing.type: Easing.OutCubic } }
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
                            MorphGlyph {
                                id: bellGlyph
                                anchors.centerIn: parent
                                width: 16; height: 16
                                kind: root.notifDnd ? "moon" : "bell"
                                color: root.notifDnd ? bpal.fg2 : bpal.fg
                                Behavior on color { ColorAnimation { duration: 320 } }
                                property real dip: 0
                                scale: 1 - 0.18 * dip
                                rotation: -8 * dip
                                Connections {
                                    target: root
                                    function onNotifDndChanged() { dndPop.restart(); }
                                }
                                SequentialAnimation {
                                    id: dndPop
                                    NumberAnimation { target: bellGlyph; property: "dip"; to: 1; duration: 120; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: bellGlyph; property: "dip"; to: 0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.6 }
                                }
                            }
                            Rectangle {
                                visible: root.notifUnread > 0 && !root.notifDnd
                                x: parent.width / 2 + 2; y: parent.height / 2 - 8
                                width: 7; height: 7; radius: 3.5
                                color: "#FF453A"
                            }
                            MouseArea { anchors.fill: parent; onClicked: ui.openPop("notif", 0) }
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
                                font.family: bpal.fam
                                font.pixelSize: 13
                            }
                            MouseArea { anchors.fill: parent; onClicked: ui.openPop("cal", 0) }
                        }
                    }
                }

                Item {
                    id: volPop
                    z: 10
                    width: 330
                    height: Math.min(volCol.height + 28, ui.height - root.barHeight - 40)
                    x: Math.max(6, Math.min(ui.width - width * root.barPopupScale - 8, ui.menuX - width / 2))
                    y: root.barHeight + 6
                    // opening: it grows out of the menu bar, stretching into shape as it comes into focus; closing runs it back, faster
                    readonly property bool popShown: ui.pop === "vol"
                    property real popT: popShown ? 1 : 0
                    Behavior on popT { NumberAnimation { duration: volPop.popShown ? 460 : 230; easing.type: volPop.popShown ? Easing.OutQuint : Easing.OutCubic } }
                    opacity: Math.min(1, popT * 1.7)
                    visible: popT > 0.002
                    scale: root.barPopupScale
                    transformOrigin: Item.Top
                    transform: [
                        Scale { origin.x: volPop.width / 2; origin.y: 0; xScale: 0.9 + 0.1 * volPop.popT; yScale: 0.74 + 0.26 * volPop.popT },
                        Translate { y: -10 * (1 - volPop.popT) }
                    ]
                    layer.enabled: popT < 0.995
                    layer.effect: MultiEffect { blurEnabled: true; blurMax: 28; blur: 1 - volPop.popT; autoPaddingEnabled: true }
                    LGlass {
                        anchors.fill: parent
                        backdrop: ui.glassSrc
                        shaderUrl: root.glassShaderUrl
                        liquid: root.liquidActive
                        dark: root.effDark
                        bx: volPop.x; by: volPop.y
                        cornerR: 26
                        tint: root.effGlassOpacity
                        tintHue: root.tintAccent ? root.accent : "transparent"
                        thickness: 22
                        strength: 0.7 * root.glassLiquid
                        rim: root.glassRim
                        grain: root.glassGrain
                        blur: root.glassBlur
                        debug: root.glassDebug
                        onShaderError: root.glassState = "failed"
                    }
                    // the sliders' knobs turn to Liquid Glass while held (upstream's CCSlider): they sample this backdrop
                    ShaderEffectSource {
                        id: volSrc
                        sourceItem: volPop.visible ? ui.glassSrc : null
                        live: volPop.visible
                        visible: false
                        sourceRect: Qt.rect(volPop.x - 64, volPop.y - 64, volPop.width + 128, volPop.height + 128)
                    }
                    MultiEffect {
                        id: volBlurFx
                        source: volSrc
                        width: volSrc.sourceRect.width; height: volSrc.sourceRect.height
                        blurEnabled: true; blurMax: 64
                        blur: Math.min(1.0, volg.blur * 1.4 / 64.0)
                        autoPaddingEnabled: false
                        visible: false
                    }
                    ShaderEffectSource { id: volBlur; sourceItem: volPop.visible ? volBlurFx : null; live: true; visible: false }
                    GlassCtx {
                        id: volg
                        src: volBlur
                        srcRect: volSrc.sourceRect
                        frame: ui
                        liquid: root.liquidActive
                        blurred: !root.liquidActive && root.wantBackdrop
                        shaderUrl: root.glassShaderUrl
                        dark: root.effDark
                        tint: root.effGlassOpacity
                        strength: root.glassLiquid
                        rim: root.glassRim
                        grain: root.glassGrain
                        blur: root.liquidActive ? root.glassBlur : root.glassBlur * 2.5
                        debug: root.glassDebug
                        onFailed: root.glassState = "failed"
                    }
                    MouseArea { anchors.fill: parent }      // clicks inside don't close the popover
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

                            Text { x: 4; text: I18n.tr("Output"); color: pal.fg2; font.family: pal.fam; font.pixelSize: 12; font.weight: Font.DemiBold; bottomPadding: 3 }
                            Item {
                                width: parent.width; height: 32
                                CCSlider {
                                    t: pal; gx: volg
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
                            Text { visible: root.audioOutputs.length === 0; x: 4; text: I18n.tr("No output devices"); color: pal.fg2; font.family: pal.fam; font.pixelSize: 12; topPadding: 4; bottomPadding: 4 }
                            Item { width: 1; height: 5 }
                            Text { x: 4; text: I18n.tr("Apps"); color: pal.fg2; font.family: pal.fam; font.pixelSize: 12; font.weight: Font.DemiBold; bottomPadding: 2 }
                            Repeater {
                                model: root.appAudioStreams
                                delegate: Item {
                                    required property var modelData
                                    width: volCol.width - 28; height: 54
                                    Text {
                                        x: 4; y: 0; width: parent.width - 8
                                        text: modelData.name + "  ·  " + Math.round(modelData.volume * 100) + "%"
                                        color: pal.fg; elide: Text.ElideRight
                                        font.family: pal.fam; font.pixelSize: 12
                                    }
                                    CCSlider {
                                        t: pal; gx: volg; x: 0; y: 20; width: parent.width
                                        value: modelData.volume
                                        leftKind: "speaker"; leftLevel: modelData.volume < 0.34 ? 1 : (modelData.volume < 0.67 ? 2 : 3)
                                        rightKind: "speaker"; rightLevel: 3
                                        onMoved: v => root.setAppVolume(modelData, v)
                                    }
                                }
                            }
                            Text { visible: root.appAudioStreams.length === 0; x: 4; text: I18n.tr("No apps are playing audio"); color: pal.fg2; font.family: pal.fam; font.pixelSize: 11; topPadding: 2; bottomPadding: 4 }
                            Item { width: 1; height: 5 }
                            Rectangle { width: parent.width; height: 1; color: pal.sep }
                            Item { width: 1; height: 5 }
                            Item {
                                width: parent.width; height: 32
                                Text { x: 4; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("Input"); color: pal.fg2; font.family: pal.fam; font.pixelSize: 12; font.weight: Font.DemiBold }
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
                                    t: pal; gx: volg
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
                            Text { visible: root.audioInputs.length === 0; x: 4; text: I18n.tr("No input devices"); color: pal.fg2; font.family: pal.fam; font.pixelSize: 12; topPadding: 4; bottomPadding: 4 }
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
                    y: root.barHeight + 6
                    // opening: it grows out of the menu bar, stretching into shape as it comes into focus; closing runs it back, faster
                    readonly property bool popShown: ui.pop === "kb"
                    property real popT: popShown ? 1 : 0
                    Behavior on popT { NumberAnimation { duration: kbPop.popShown ? 460 : 230; easing.type: kbPop.popShown ? Easing.OutQuint : Easing.OutCubic } }
                    opacity: Math.min(1, popT * 1.7)
                    visible: popT > 0.002
                    scale: root.barPopupScale
                    transformOrigin: Item.Top
                    transform: [
                        Scale { origin.x: kbPop.width / 2; origin.y: 0; xScale: 0.9 + 0.1 * kbPop.popT; yScale: 0.74 + 0.26 * kbPop.popT },
                        Translate { y: -10 * (1 - kbPop.popT) }
                    ]
                    layer.enabled: popT < 0.995
                    layer.effect: MultiEffect { blurEnabled: true; blurMax: 28; blur: 1 - kbPop.popT; autoPaddingEnabled: true }
                    LGlass {
                        anchors.fill: parent
                        backdrop: ui.glassSrc
                        shaderUrl: root.glassShaderUrl
                        liquid: root.liquidActive
                        dark: root.effDark
                        bx: kbPop.x; by: kbPop.y
                        cornerR: 22
                        tint: root.effGlassOpacity
                        tintHue: root.tintAccent ? root.accent : "transparent"
                        thickness: 22
                        strength: 0.7 * root.glassLiquid
                        rim: root.glassRim
                        grain: root.glassGrain
                        blur: root.glassBlur
                        debug: root.glassDebug
                        onShaderError: root.glassState = "failed"
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
                                    font.family: pal.fam; font.pixelSize: 13
                                    font.weight: kr.index === root.kbIndex ? Font.DemiBold : Font.Normal
                                }
                                Text {
                                    anchors.right: parent.right; anchors.rightMargin: 40
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: kr.modelData.code.toUpperCase()
                                    color: pal.fg2
                                    font.family: pal.fam; font.pixelSize: 11
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
                    y: popBottom > 0 ? popBottom + 12 : root.barHeight + 8
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
                                    tint: root.effGlassOpacity
                                    tintHue: root.tintAccent ? root.accent : "transparent"
                                    thickness: 22
                                    strength: 0.7 * root.glassLiquid
                                    rim: root.glassRim
                                    grain: root.glassGrain
                                    blur: root.notifBlur
                                    debug: root.glassDebug
                                    onShaderError: root.glassState = "failed"
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
                    width: 380
                    // while clearing it tracks the collapsing list frame by frame (never shorter than the empty state),
                    // so the dust and the shrink are one motion; otherwise it eases to its new size
                    height: 92 + (notifHist.count === 0 ? 70 : (root.notifClearing ? Math.max(70, nfl.height) : nfl.height)) + 14
                    Behavior on height { enabled: !root.notifClearing; NumberAnimation { duration: 560; easing.type: Easing.OutQuint } }
                    x: Math.max(6, ui.width - width - 8)
                    y: root.barHeight + 6
                    opacity: ui.pop === "notif" ? 1 : 0
                    visible: opacity > 0
                    scale: root.barPopupScale * (ui.pop === "notif" ? 1 : 0.96)
                    transformOrigin: Item.TopRight
                    // popups merging in: the panel appears at once (its cards are the popups, solid from the first frame) and only
                    // its chrome (glass, header, Do Not Disturb) builds in around them
                    readonly property bool merging: ui.toastsShown
                    property real chrome: ui.pop === "notif" ? 1 : 0
                    Behavior on chrome { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                    Behavior on opacity { enabled: !notifPop.merging; NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                    Behavior on scale { enabled: !notifPop.merging; NumberAnimation { duration: 420; easing.type: Easing.OutQuint } }

                    LGlass {
                        anchors.fill: parent
                        opacity: notifPop.chrome
                        backdrop: ui.glassSrc
                        shaderUrl: root.glassShaderUrl
                        liquid: root.liquidActive
                        dark: root.effDark
                        bx: notifPop.x; by: notifPop.y
                        cornerR: 26
                        tint: root.effGlassOpacity
                        tintHue: root.tintAccent ? root.accent : "transparent"
                        thickness: 26
                        strength: 0.8 * root.glassLiquid
                        rim: root.glassRim
                        grain: root.glassGrain
                        blur: root.notifBlur
                        debug: root.glassDebug
                        onShaderError: root.glassState = "failed"
                    }
                    MouseArea { anchors.fill: parent }      // clicks inside the panel don't close it

                    Item {
                        x: 18; y: 14; width: parent.width - 36; height: 26
                        opacity: notifPop.chrome
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Notification system")
                            color: pal.fg
                            font.family: pal.fam; font.pixelSize: 17; font.weight: Font.DemiBold
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
                                font.family: pal.fam; font.pixelSize: 12; font.weight: Font.Medium
                            }
                            MouseArea { id: clrMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.notifClearAnimated() }
                        }
                    }
                    Item {
                        x: 12; y: 46; width: parent.width - 24; height: 36
                        opacity: notifPop.chrome
                        Rectangle { anchors.fill: parent; radius: 12; color: pal.tile; border.width: 1; border.color: pal.tileBorder }
                        Glyph { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 15; height: 15; kind: "moon"; color: pal.fg }
                        Text {
                            x: 36; anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Do Not Disturb")
                            color: pal.fg
                            font.family: pal.fam; font.pixelSize: 13
                        }
                        PSwitch {
                            t: pal
                            anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
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
                        font.family: pal.fam; font.pixelSize: 14
                    }
                    Flickable {
                        id: nfl
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
                                        var cw = notifPop.width - 24;
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
                                    border.width: 1; border.color: pal.tileBorder
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

                // ═════════ dropdown menu (Apple / app / File / Edit / …) ═════════
                Item {
                    id: menuPop
                    z: 10
                    width: 260
                    height: menuCol.height + 14
                    x: Math.max(6, Math.min(ui.width - width * root.barPopupScale - 6, ui.menuX - 4))
                    y: root.barHeight + 3
                    // opening: it grows out of the menu bar, stretching into shape as it comes into focus; closing runs it back, faster
                    readonly property bool popShown: ui.isMenu
                    property real popT: popShown ? 1 : 0
                    Behavior on popT { NumberAnimation { duration: menuPop.popShown ? 460 : 230; easing.type: menuPop.popShown ? Easing.OutQuint : Easing.OutCubic } }
                    opacity: Math.min(1, popT * 1.7)
                    visible: popT > 0.002
                    scale: root.barPopupScale
                    transformOrigin: Item.TopLeft
                    transform: [
                        Scale { origin.x: 0; origin.y: 0; xScale: 0.9 + 0.1 * menuPop.popT; yScale: 0.74 + 0.26 * menuPop.popT },
                        Translate { y: -10 * (1 - menuPop.popT) }
                    ]
                    layer.enabled: popT < 0.995
                    layer.effect: MultiEffect { blurEnabled: true; blurMax: 28; blur: 1 - menuPop.popT; autoPaddingEnabled: true }
                    // moving from one menu to the next: the panel slides and reshapes while the items blur out and
                    // the new ones come into focus — all at once, rather than snapping
                    Behavior on x { enabled: ui.isMenu; NumberAnimation { duration: 320; easing.type: Easing.OutQuint } }
                    Behavior on height { enabled: ui.isMenu; NumberAnimation { duration: 320; easing.type: Easing.OutQuint } }
                    property string shownMenu: ""
                    property real swapT: 1
                    Connections {
                        target: ui
                        function onPopChanged() {
                            if (!ui.isMenu) { menuPop.shownMenu = ""; menuPop.swapT = 1; return; }
                            if (ui.pop === menuPop.shownMenu) return;
                            var first = menuPop.shownMenu === "";
                            menuPop.shownMenu = ui.pop;
                            if (first) { menuPop.swapT = 1; return; }
                            menuPop.swapT = 0; menuSwap.restart();
                        }
                    }
                    NumberAnimation { id: menuSwap; target: menuPop; property: "swapT"; from: 0; to: 1; duration: 300; easing.type: Easing.OutCubic }

                    LGlass {
                        anchors.fill: parent
                        backdrop: ui.glassSrc
                        shaderUrl: root.glassShaderUrl
                        liquid: root.liquidActive
                        dark: root.effDark
                        bx: menuPop.x; by: menuPop.y
                        cornerR: 14
                        tint: root.effGlassOpacity
                        tintHue: root.tintAccent ? root.accent : "transparent"
                        thickness: 22
                        strength: 0.55 * root.glassLiquid
                        rim: root.glassRim
                        grain: root.glassGrain
                        blur: root.glassBlur
                        debug: root.glassDebug
                        onShaderError: root.glassState = "failed"
                    }
                    Column {
                        id: menuCol
                        x: 6; y: 7
                        width: parent.width - 12
                        opacity: Math.min(1, menuPop.swapT * 1.4)
                        transform: Translate { x: (1 - menuPop.swapT) * 10 }
                        layer.enabled: menuPop.swapT < 0.99
                        layer.effect: MultiEffect { blurEnabled: true; blurMax: 24; blur: 1 - menuPop.swapT; autoPaddingEnabled: true }
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
                                    color: pal.sep
                                }
                                Rectangle {
                                    visible: it.hot
                                    anchors.fill: parent
                                    radius: 6
                                    color: it.armedNow ? "#FF453A" : root.accent
                                }
                                Text {
                                    visible: !it.isSep && it.modelData.checked === true
                                    x: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "\u2713"
                                    color: it.hot ? "white" : pal.fg
                                    font.family: pal.fam
                                    font.pixelSize: 13
                                }
                                Text {
                                    visible: !it.isSep
                                    x: ui.menuLead ? 28 : 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - x - 12 - (sc.visible ? sc.implicitWidth + 12 : 0)
                                    elide: Text.ElideRight
                                    text: it.isSep ? "" : (it.armedNow ? I18n.tr("Click again to confirm") : it.modelData.label)
                                    color: it.hot ? "white" : (it.off ? pal.fg2 : pal.fg)
                                    font.family: pal.fam
                                    font.pixelSize: 13
                                }
                                Text {
                                    id: sc
                                    visible: !it.isSep && it.modelData.shortcut !== undefined && it.modelData.shortcut !== ""
                                    anchors.right: parent.right
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: it.isSep ? "" : (it.modelData.shortcut || "")
                                    color: it.hot ? Qt.rgba(1, 1, 1, 0.8) : pal.fg2
                                    font.family: pal.fam
                                    font.pixelSize: 12
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
                    y: root.barHeight + 3
                    // opening: it grows out of the menu bar, stretching into shape as it comes into focus; closing runs it back, faster
                    readonly property bool popShown: shown
                    property real popT: popShown ? 1 : 0
                    Behavior on popT { NumberAnimation { duration: trayPop.popShown ? 460 : 230; easing.type: trayPop.popShown ? Easing.OutQuint : Easing.OutCubic } }
                    opacity: Math.min(1, popT * 1.7)
                    visible: popT > 0.002
                    scale: root.barPopupScale
                    transformOrigin: Item.TopLeft
                    transform: [
                        Scale { origin.x: 0; origin.y: 0; xScale: 0.9 + 0.1 * trayPop.popT; yScale: 0.74 + 0.26 * trayPop.popT },
                        Translate { y: -10 * (1 - trayPop.popT) }
                    ]
                    layer.enabled: popT < 0.995
                    layer.effect: MultiEffect { blurEnabled: true; blurMax: 28; blur: 1 - trayPop.popT; autoPaddingEnabled: true }

                    QsMenuOpener { id: trayOpener; menu: trayPop.cur }

                    LGlass {
                        anchors.fill: parent
                        backdrop: ui.glassSrc
                        shaderUrl: root.glassShaderUrl
                        liquid: root.liquidActive
                        dark: root.effDark
                        bx: trayPop.x; by: trayPop.y
                        cornerR: 14
                        tint: root.effGlassOpacity
                        tintHue: root.tintAccent ? root.accent : "transparent"
                        thickness: 22
                        strength: 0.55 * root.glassLiquid
                        rim: root.glassRim
                        grain: root.glassGrain
                        blur: root.glassBlur
                        debug: root.glassDebug
                        onShaderError: root.glassState = "failed"
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
                                    color: backMa.containsMouse ? "white" : pal.fg
                                    font.family: pal.fam; font.pixelSize: 13; font.weight: Font.DemiBold
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
                                Rectangle { anchors.verticalCenter: parent.verticalCenter; x: 8; width: parent.width - 16; height: 1; color: pal.sep }
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
                                        color: pal.sep
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
                                        color: te.hot ? "white" : (te.live ? pal.fg : pal.fg2)
                                        font.family: pal.fam
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
                                        color: te.hot ? "white" : (te.live ? pal.fg : pal.fg2)
                                        font.family: pal.fam
                                        font.pixelSize: 13
                                    }
                                    Text {
                                        visible: !te.isSep && te.modelData.hasChildren
                                        anchors.right: parent.right
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "\u203A"
                                        color: te.hot ? "white" : pal.fg2
                                        font.family: pal.fam; font.pixelSize: 15
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

                // ═════════ Wi-Fi networks ═════════
                Item {
                    id: wifiPop
                    z: 10
                    width: 320
                    height: wifiCol.height + 24
                    x: Math.max(6, Math.min(ui.width - width * root.barPopupScale - 8, ui.menuX + 14 - width / 2))
                    y: root.barHeight + 6
                    // opening: it grows out of the menu bar, stretching into shape as it comes into focus; closing runs it back, faster
                    readonly property bool popShown: ui.pop === "wifi"
                    property real popT: popShown ? 1 : 0
                    Behavior on popT { NumberAnimation { duration: wifiPop.popShown ? 460 : 230; easing.type: wifiPop.popShown ? Easing.OutQuint : Easing.OutCubic } }
                    opacity: Math.min(1, popT * 1.7)
                    visible: popT > 0.002
                    scale: root.barPopupScale
                    transformOrigin: Item.Top
                    transform: [
                        Scale { origin.x: wifiPop.width / 2; origin.y: 0; xScale: 0.9 + 0.1 * wifiPop.popT; yScale: 0.74 + 0.26 * wifiPop.popT },
                        Translate { y: -10 * (1 - wifiPop.popT) }
                    ]
                    layer.enabled: popT < 0.995
                    layer.effect: MultiEffect { blurEnabled: true; blurMax: 28; blur: 1 - wifiPop.popT; autoPaddingEnabled: true }

                    LGlass {
                        anchors.fill: parent
                        backdrop: ui.glassSrc
                        shaderUrl: root.glassShaderUrl
                        liquid: root.liquidActive
                        dark: root.effDark
                        bx: wifiPop.x; by: wifiPop.y
                        cornerR: 22
                        tint: root.effGlassOpacity
                        tintHue: root.tintAccent ? root.accent : "transparent"
                        thickness: 24
                        strength: 0.7 * root.glassLiquid
                        rim: root.glassRim
                        grain: root.glassGrain
                        blur: root.glassBlur
                        debug: root.glassDebug
                        onShaderError: root.glassState = "failed"
                    }
                    MouseArea { anchors.fill: parent }          // swallow clicks on empty glass so the popover doesn't close

                    Column {
                        id: wifiCol
                        x: 12; y: 12
                        width: parent.width - 24
                        spacing: 6

                        // header: title + on/off switch
                        Item {
                            width: parent.width; height: 32
                            Text {
                                x: 6; anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Wi-Fi")
                                color: pal.fg
                                font.family: pal.fam; font.pixelSize: 15; font.weight: Font.DemiBold
                            }
                            PSwitch {
                                t: pal
                                anchors.right: parent.right; anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                checked: root.wifiOn
                                onToggled: { root.toggleWifi(); wifiAfter.restart(); }
                            }
                        }
                        Rectangle { width: parent.width; height: 1; color: pal.sep }
                        Text { visible: root.otherConnections.length>0; width:parent.width; leftPadding:6; text:I18n.tr("Ethernet & VPN"); color:pal.fg2; font.family:pal.fam; font.pixelSize:11; font.weight:Font.DemiBold }
                        Column {
                            width: parent.width
                            Repeater {
                                model: root.otherConnections.slice(0,5)
                                delegate: Item {
                                    required property var modelData
                                    width: parent.width; height: 30
                                    Rectangle { anchors.fill:parent; radius:8; color:connMa.containsMouse?pal.hover:"transparent" }
                                    Glyph { x:8; anchors.verticalCenter:parent.verticalCenter; width:14; height:14; kind:modelData.type==="vpn"?"lock":(modelData.type==="wifi"?"wifi":"ethernet"); color:pal.fg }
                                    Text { x:30; anchors.verticalCenter:parent.verticalCenter; width:parent.width-42; elide:Text.ElideRight; text:modelData.name+(modelData.active?I18n.tr(" · Connected"):""); color:pal.fg; font.family:pal.fam; font.pixelSize:12 }
                                    MouseArea { id:connMa; anchors.fill:parent; hoverEnabled:true; onClicked:root.toggleConnection(modelData) }
                                }
                            }
                        }

                        Text {
                            visible: !root.wifiOn
                            width: parent.width; height: 56
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            text: I18n.tr("Wi-Fi is turned off")
                            color: pal.fg2
                            font.family: pal.fam; font.pixelSize: 13
                        }
                        Text {
                            visible: root.wifiOn && root.wifiNets.length === 0
                            width: parent.width; height: 56
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            text: root.wifiScanning ? I18n.tr("Searching\u2026") : I18n.tr("No networks found")
                            color: pal.fg2
                            font.family: pal.fam; font.pixelSize: 13
                        }
                        Text {
                            visible: root.wifiOn && root.wifiNets.length > 0
                            leftPadding: 6
                            text: I18n.tr("Networks")
                            color: pal.fg2
                            font.family: pal.fam; font.pixelSize: 11; font.weight: Font.DemiBold
                        }
                        // only shown on adapters that cannot share and stay connected at the same time
                        Text {
                            visible: root.wifiOn && root.hotspotOn && root.wifiSsid === ""
                            leftPadding: 6; rightPadding: 6
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: I18n.tr("This adapter can't share and stay connected at once, so Internet Sharing has it.")
                            color: pal.fg2
                            font.family: pal.fam; font.pixelSize: 11
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
                                                color: wma.containsMouse ? "white" : pal.fg
                                            }
                                            Text {
                                                x: 30
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - 30 - 96
                                                elide: Text.ElideRight
                                                text: nr.modelData.ssid
                                                color: wma.containsMouse ? "white" : pal.fg
                                                font.family: pal.fam; font.pixelSize: 13
                                                font.weight: nr.modelData.inUse ? Font.DemiBold : Font.Normal
                                            }
                                            Text {
                                                visible: nr.busy
                                                anchors.right: parent.right; anchors.rightMargin: 12
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: I18n.tr("Connecting\u2026")
                                                color: pal.fg2
                                                font.family: pal.fam; font.pixelSize: 12
                                            }
                                            Text {
                                                visible: !nr.busy && nr.modelData.inUse && wma.containsMouse
                                                anchors.right: parent.right; anchors.rightMargin: 12
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: I18n.tr("Disconnect")
                                                color: "white"
                                                font.family: pal.fam; font.pixelSize: 12
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
                                                    color: wma.containsMouse ? "white" : pal.fg2
                                                }
                                                Glyph {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 16; height: 16
                                                    kind: "wifi"; level: root.sigLevel(nr.modelData.signal)
                                                    color: wma.containsMouse ? "white" : pal.fg
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
                                                color: pal.btnOff
                                            }
                                            Text {
                                                x: 42; y: 3; height: 32
                                                verticalAlignment: Text.AlignVCenter
                                                visible: pw.text === ""
                                                text: I18n.tr("Password")
                                                color: pal.fg3
                                                font.family: pal.fam; font.pixelSize: 13
                                            }
                                            TextInput {
                                                id: pw
                                                x: 42; y: 3
                                                width: parent.width - 42 - 62; height: 32
                                                verticalAlignment: TextInput.AlignVCenter
                                                clip: true
                                                echoMode: TextInput.Password
                                                color: pal.fg
                                                selectionColor: root.accent
                                                selectedTextColor: "white"
                                                font.family: pal.fam; font.pixelSize: 13
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
                                                color: pw.text.length > 0 ? root.accent : pal.fg3
                                                font.family: pal.fam; font.pixelSize: 13; font.weight: Font.DemiBold
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
                            font.family: pal.fam; font.pixelSize: 12
                        }

                        Rectangle { width: parent.width; height: 1; color: pal.sep }
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
                                color: wsa.containsMouse ? "white" : pal.fg
                                font.family: pal.fam; font.pixelSize: 13
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

                // ═════════ calendar ═════════
                Item {
                    id: cal
                    z: 10
                    width: 310
                    height: calCol.height + 28
                    x: Math.max(6, ui.width - width - 8)
                    y: root.barHeight + 6
                    // opening: it grows out of the menu bar, stretching into shape as it comes into focus; closing runs it back, faster
                    readonly property bool popShown: ui.pop === "cal"
                    property real popT: popShown ? 1 : 0
                    Behavior on popT { NumberAnimation { duration: cal.popShown ? 460 : 230; easing.type: cal.popShown ? Easing.OutQuint : Easing.OutCubic } }
                    opacity: Math.min(1, popT * 1.7)
                    visible: popT > 0.002
                    scale: root.barPopupScale
                    transformOrigin: Item.TopRight
                    transform: [
                        Scale { origin.x: cal.width; origin.y: 0; xScale: 0.9 + 0.1 * cal.popT; yScale: 0.74 + 0.26 * cal.popT },
                        Translate { y: -10 * (1 - cal.popT) }
                    ]
                    layer.enabled: popT < 0.995
                    layer.effect: MultiEffect { blurEnabled: true; blurMax: 28; blur: 1 - cal.popT; autoPaddingEnabled: true }

                    LGlass {
                        anchors.fill: parent
                        backdrop: ui.glassSrc
                        shaderUrl: root.glassShaderUrl
                        liquid: root.liquidActive
                        dark: root.effDark
                        bx: cal.x; by: cal.y
                        cornerR: 24
                        tint: root.effGlassOpacity
                        tintHue: root.tintAccent ? root.accent : "transparent"
                        thickness: 26
                        strength: 0.8 * root.glassLiquid
                        rim: root.glassRim
                        grain: root.glassGrain
                        blur: root.glassBlur
                        debug: root.glassDebug
                        onShaderError: root.glassState = "failed"
                    }
                    Column {
                        id: calCol
                        x: 16; y: 14
                        width: parent.width - 32
                        spacing: 8

                        Text {
                            text: Qt.formatDateTime(clock.date, "dddd")
                            color: pal.fg2
                            font.family: pal.fam; font.pixelSize: 12; font.weight: Font.DemiBold
                        }
                        Text {
                            text: Qt.formatDateTime(clock.date, I18n.tr("d MMMM yyyy"))
                            color: pal.fg
                            font.family: pal.fam; font.pixelSize: 22; font.weight: Font.DemiBold
                        }
                        Item { width: 1; height: 2 }
                        Item {
                            width: parent.width; height: 26
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Qt.locale().monthName(ui.calMonth, Locale.LongFormat) + " " + ui.calYear
                                color: pal.fg
                                font.family: pal.fam; font.pixelSize: 14; font.weight: Font.DemiBold
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
                                    text: Qt.locale().dayName((index + (root.weekStartsMonday ? 1 : 0)) % 7, Locale.ShortFormat).substring(0, 2)
                                    color: pal.fg2
                                    font.family: pal.fam; font.pixelSize: 11; font.weight: Font.DemiBold
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
                                        font.family: pal.fam
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
                    width: 340
                    height: ccCol.height
                    x: Math.max(8, ui.width - width - 10)
                    y: root.barHeight + 6
                    // opening (ColorOS 17): the panel springs out from the Control Center button, overshoots a little and
                    // settles, while the controls stretch up into place one row after another. Closing is quick and flat.
                    readonly property bool opening: ui.pop === "cc"
                    property int openSeq: 0
                    property real openT: opening ? 1 : 0
                    Behavior on openT {
                        NumberAnimation {
                            duration: !root.ccAnimate ? 110 : (cc.opening ? 520 : 150)
                            easing.type: (root.ccAnimate && cc.opening) ? Easing.OutBack : Easing.OutCubic
                            easing.overshoot: 1.5
                        }
                    }
                    opacity: Math.max(0, Math.min(1, openT * 2.2))
                    visible: opacity > 0
                    scale: root.barPopupScale
                    transformOrigin: Item.TopRight
                    // the panel itself never moves above the bar (the menu bar is transparent, so anything that did would
                    // show straight through it). The motion lives in the controls: they slide up into place inside it.
                    onOpeningChanged: if (opening) openSeq++
                    onVisibleChanged: if (visible) { root.refreshWifi(); root.refreshBt(); root.refreshBrightness(); }

                    ShaderEffectSource {
                        id: ccSrc
                        sourceItem: ui.glassSrc
                        hideSource: true
                        live: true
                        visible: false
                        sourceRect: Qt.rect(cc.x - 64 * root.barPopupScale, cc.y - 64 * root.barPopupScale,
                                            cc.width + 128 * root.barPopupScale, cc.height + 128 * root.barPopupScale)
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
                        srcRect: ccSrc.sourceRect
                        frame: ui
                        liquid: root.liquidActive
                        blurred: !root.liquidActive && root.wantBackdrop
                        shaderUrl: root.glassShaderUrl
                        dark: root.effDark
                        // macOS style: the panel is the glass, so each control only keeps a faint shape on top of it
                        tint: root.solidAll ? 1.0 : (root.ccStyle === "macos" ? root.glassOpacity * 0.30 : root.glassOpacity)
                        strength: root.ccStyle === "macos" ? root.glassLiquid * 0.30 : root.glassLiquid
                        rim: root.ccStyle === "macos" ? root.glassRim * 0.45 : root.glassRim
                        grain: root.glassGrain
                        blur: root.liquidActive ? root.glassBlur : root.glassBlur * 2.5
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
                        case "battery": return cBattery;
                        case "hotspot": return cHotspot;
                        case "lockscreen": return cLockScreen;
                        case "sleep": return cSleep;
                        case "mirror": return cMirror;
                        case "keylight": return cKeyLight;
                        }
                        return null;
                    }
                    Component {
                        id: cWifi
                        CCTile {
                            t: pal; gx: ccg
                            CCBtn {
                                t: pal; gx: ccg
                                x: 12; anchors.verticalCenter: parent.verticalCenter
                                kind: "wifi"; level: root.wifiOn ? (root.wifiLevel || 3) : 3
                                on: root.wifiOn
                                onClicked: root.toggleWifi()
                            }
                            MouseArea {
                                x: 56; width: parent.width - 56; height: parent.height
                                onClicked: ui.openPop("wifi", ui.width)
                            }
                            Glyph {
                                x: parent.width - 22; anchors.verticalCenter: parent.verticalCenter
                                width: 12; height: 12
                                kind: "chevR"; color: pal.fg2
                            }
                            Column {
                                x: 62; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 62 - 24
                                spacing: 1
                                Text { text: I18n.tr("Wi-Fi"); color: pal.fg; font.family: pal.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
                                MorphText {
                                    animateWidth: false; duration: 420
                                    width: parent.width; elide: Text.ElideRight
                                    text: !root.wifiOn ? I18n.tr("Off") : (root.wifiSsid !== "" ? root.wifiSsid : I18n.tr("Not Connected"))
                                    color: pal.fg2; font.family: pal.fam; font.pixelSize: 12
                                }
                            }
                        }
                    }
                    Component {
                        id: cBt
                        CCTile {
                            t: pal; gx: ccg
                            CCBtn {
                                t: pal; gx: ccg; anchors.fill: parent; d: Math.min(parent.width, parent.height); glass: false
                                kind: "bluetooth"; on: root.btOn
                                onClicked: root.toggleBt()
                            }
                        }
                    }
                    Component {
                        id: cAirplane
                        CCTile {
                            t: pal; gx: ccg
                            CCBtn {
                                t: pal; gx: ccg; anchors.fill: parent; d: Math.min(parent.width, parent.height); glass: false
                                kind: "airplane"; on: root.airplane
                                onClicked: root.toggleAirplane()
                            }
                        }
                    }
                    Component {
                        id: cFocus
                        CCTile {
                            t: pal; gx: ccg
                            CCBtn {
                                t: pal; gx: ccg
                                x: 12; anchors.verticalCenter: parent.verticalCenter
                                kind: "moon"; on: root.dnd
                                onClicked: root.toggleDnd()
                            }
                            Column {
                                x: 62; anchors.verticalCenter: parent.verticalCenter
                                spacing: 1
                                Text { text: I18n.tr("Focus"); color: pal.fg; font.family: pal.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
                                MorphText { animateWidth: false; duration: 420; text: root.dnd ? I18n.tr("Do Not Disturb") : I18n.tr("Off"); color: pal.fg2; font.family: pal.fam; font.pixelSize: 12 }
                            }
                        }
                    }
                    Component {
                        id: cGaming
                        CCTile {
                            t: pal; gx: ccg
                            CCBtn {
                                t: pal; gx: ccg
                                x: 12; anchors.verticalCenter: parent.verticalCenter
                                kind: "gamepad"; on: root.gaming; onTint: "#30D158"
                                onClicked: root.gamingMode = !root.gaming
                            }
                            Column {
                                x: 62; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 62 - 10
                                spacing: 1
                                Text { width: parent.width; elide: Text.ElideRight; text: I18n.tr("Game Mode"); color: pal.fg; font.family: pal.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
                                MorphText { animateWidth: false; duration: 420; width: parent.width; elide: Text.ElideRight; text: root.gamingAutoActive && !root.gamingMode ? I18n.tr("On (game detected)") : (root.gaming ? I18n.tr("On") : (root.gamingAuto ? I18n.tr("Auto") : I18n.tr("Off")))
                                       color: root.gaming ? "#30D158" : pal.fg2; font.family: pal.fam; font.pixelSize: 12 }
                            }
                        }
                    }
                    Component {
                        id: cRecord
                        CCTile {
                            t: pal; gx: ccg
                            CCBtn {
                                t: pal; gx: ccg
                                x: 12; anchors.verticalCenter: parent.verticalCenter
                                kind: root.recording ? "stoprec" : "record"; on: root.recording; onTint: "#FF453A"
                                onClicked: root.toggleRecording()
                            }
                            Column {
                                x: 62; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 62 - 10
                                spacing: 1
                                MorphText { animateWidth: false; duration: 420; width: parent.width; elide: Text.ElideRight; text: root.recording ? I18n.tr("Stop") : I18n.tr("Record"); color: pal.fg; font.family: pal.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
                                MorphText { animateWidth: false; duration: 420; width: parent.width; elide: Text.ElideRight; text: root.recording ? root.recTime() : I18n.tr("Screen"); color: root.recording ? "#FF453A" : pal.fg2; font.family: pal.fam; font.pixelSize: 12 }
                            }
                        }
                    }
                    Component {
                        id: cNight
                        CCTile {
                            t: pal; gx: ccg
                            CCBtn {
                                t: pal; gx: ccg; anchors.fill: parent; d: Math.min(parent.width, parent.height); glass: false
                                kind: "nightshift"; on: root.nightOn
                                onClicked: root.nightOn = !root.nightOn
                            }
                        }
                    }
                    Component {
                        id: cAwake
                        CCTile {
                            t: pal; gx: ccg
                            CCBtn {
                                t: pal; gx: ccg; anchors.fill: parent; d: Math.min(parent.width, parent.height); glass: false
                                kind: "coffee"; on: root.keepAwake
                                onClicked: root.keepAwake = !root.keepAwake
                            }
                        }
                    }
                    Component {
                        id: cBattery
                        CCTile {
                            t: pal; gx: ccg
                            CCBtn {
                                t: pal; gx: ccg
                                x: 12; anchors.verticalCenter: parent.verticalCenter
                                kind: "battery"; on: root.powerProfile === "power-saver"; onTint: "#FFD60A"
                                onClicked: root.toggleLowPower()
                            }
                            Column {
                                x: 62; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 72
                                spacing: 1
                                Text { width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 2; lineHeight: 0.92; text: I18n.tr("Battery"); color: pal.fg; font.family: pal.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
                                MorphText {
                                    animateWidth: false; duration: 420; width: parent.width; elide: Text.ElideRight
                                    text: root.powerProfile === "power-saver" ? I18n.tr("Low Power Mode") : (root.powerProfile === "performance" ? I18n.tr("High Power") : I18n.tr("Balanced"))
                                    color: root.powerProfile === "power-saver" ? "#FFD60A" : pal.fg2; font.family: pal.fam; font.pixelSize: 12
                                }
                            }
                        }
                    }
                    Component {
                        id: cHotspot
                        CCTile {
                            t: pal; gx: ccg
                            CCBtn {
                                t: pal; gx: ccg
                                x: 12; anchors.verticalCenter: parent.verticalCenter
                                kind: "hotspot"; on: root.hotspotOn
                                onClicked: root.toggleHotspot()
                            }
                            Column {
                                x: 62; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 72
                                spacing: 1
                                Text { width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 2; lineHeight: 0.92; text: I18n.tr("Internet Sharing"); color: pal.fg; font.family: pal.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
                                MorphText { animateWidth: false; duration: 420; width: parent.width; elide: Text.ElideRight; text: root.hotspotOn ? I18n.tr("On") : I18n.tr("Off")
                                       color: root.hotspotOn ? root.accent : pal.fg2; font.family: pal.fam; font.pixelSize: 12 }
                            }
                        }
                    }
                    Component {
                        id: cLockScreen
                        CCTile {
                            t: pal; gx: ccg
                            CCBtn {
                                t: pal; gx: ccg; anchors.fill: parent; d: Math.min(parent.width, parent.height); glass: false
                                kind: "lock"; on: false
                                onClicked: { root.closeCC(); root.lockScreen(); }
                            }
                        }
                    }
                    Component {
                        id: cSleep
                        CCTile {
                            t: pal; gx: ccg
                            CCBtn {
                                t: pal; gx: ccg; anchors.fill: parent; d: Math.min(parent.width, parent.height); glass: false
                                kind: "power"; on: false
                                onClicked: { root.closeCC(); root.sleepMachine(); }
                            }
                        }
                    }
                    Component {
                        id: cMirror
                        CCTile {
                            t: pal; gx: ccg
                            CCBtn {
                                t: pal; gx: ccg
                                x: 12; anchors.verticalCenter: parent.verticalCenter
                                kind: "mirror"; on: root.mirrorOn
                                onClicked: root.toggleMirror()
                            }
                            Column {
                                x: 62; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 72
                                spacing: 1
                                Text { width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 2; lineHeight: 0.92; text: I18n.tr("Screen Mirroring"); color: pal.fg; font.family: pal.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
                                MorphText { animateWidth: false; duration: 420; width: parent.width; elide: Text.ElideRight; text: root.mirrorOn ? I18n.tr("Mirroring") : (root.displayCount < 2 ? I18n.tr("No other display") : I18n.tr("Off"))
                                       color: root.mirrorOn ? root.accent : pal.fg2; font.family: pal.fam; font.pixelSize: 12 }
                            }
                        }
                    }
                    Component {
                        id: cKeyLight
                        CCTile {
                            t: pal; gx: ccg
                            Column {
                                anchors.fill: parent; anchors.margins: 12
                                spacing: 6
                                Text { text: I18n.tr("Keyboard Brightness"); color: pal.fg; font.family: pal.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
                                CCSlider {
                                    t: pal; gx: ccg; glassMul: root.ccStyle === "macos" ? 3 : 1
                                    width: parent.width
                                    enabled: root.keyLightMax > 0
                                    opacity: root.keyLightMax > 0 ? 1 : 0.4
                                    value: root.keyLightMax > 0 ? root.keyLight / root.keyLightMax : 0
                                    leftKind: "keyboard"; leftLevel: 1
                                    rightKind: "keyboard"; rightLevel: 3
                                    onMoved: v => root.setKeyLight(v * root.keyLightMax)
                                }
                            }
                        }
                    }
                    Component {
                        id: cDark
                        CCTile {
                            t: pal; gx: ccg
                            CCBtn {
                                t: pal; gx: ccg; anchors.fill: parent; d: Math.min(parent.width, parent.height); glass: false
                                kind: "contrast"; on: root.darkMode
                                onClicked: root.setDark(!root.darkMode)
                            }
                        }
                    }
                    Component {
                        id: cNowPlaying
                        CCTile {
                            id: np
                            t: pal; gx: ccg
                            readonly property var pl: root.player
                            Rectangle {
                                id: art
                                x: 12; y: 12
                                width: 52; height: 52; radius: 10
                                color: pal.btnOff
                                Glyph { visible: artImg.status !== Image.Ready; anchors.centerIn: parent; width: 22; height: 22; kind: "note"; color: pal.fg2 }
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
                                    border.color: pal.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10)
                                }
                            }
                            Column {
                                x: 12; y: 66
                                width: parent.width - 24
                                spacing: 1
                                Text {
                                    width: parent.width; elide: Text.ElideRight
                                    text: np.pl && np.pl.trackTitle ? np.pl.trackTitle : I18n.tr("Now Playing")
                                    color: np.pl ? pal.fg : pal.fg2
                                    font.family: pal.fam; font.pixelSize: 13; font.weight: Font.DemiBold
                                }
                                Text {
                                    visible: np.pl !== null && np.pl !== undefined
                                    width: parent.width; elide: Text.ElideRight
                                    text: np.pl && np.pl.trackArtist ? np.pl.trackArtist : ""
                                    color: pal.fg2; font.family: pal.fam; font.pixelSize: 12
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
                                            color: pal.fg
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
                            t: pal; gx: ccg
                            radius: 26
                            Text {
                                x: 14; y: 8
                                text: I18n.tr("Display")
                                color: pal.fg; font.family: pal.fam; font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                            CCSlider {
                                t: pal; gx: ccg; glassMul: root.ccStyle === "macos" ? 3 : 1
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
                            t: pal; gx: ccg
                            radius: 26
                            Text {
                                x: 14; y: 8
                                text: I18n.tr("Sound")
                                color: pal.fg; font.family: pal.fam; font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                            CCSlider {
                                t: pal; gx: ccg; glassMul: root.ccStyle === "macos" ? 3 : 1
                                x: 12; y: 28
                                width: parent.width - 24 - 36
                                value: root.muted ? 0 : root.volume
                                leftKind: "speaker"; leftLevel: 1
                                rightKind: "speaker"; rightLevel: 3
                                onMoved: v => root.setVolume(v)
                            }
                            CCBtn {
                                t: pal; gx: ccg
                                d: 28
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
                        width: cc.width + 24; height: ccCol.height + 24
                        sourceComponent: Item {
                            GGlass { anchors.fill: parent; gx: ccg; cornerR: 24; thickness: 26; strengthMul: 1.0; shadowAmt: 0.6 }
                        }
                    }

                    Column {
                        id: ccCol
                        x: 0; y: 0
                        width: parent.width
                        spacing: 10

                        // ── privacy: which apps use the microphone / camera / screen (only while something is active) ──
                        Item {
                            id: ccPriv
                            visible: root.privacyAny && root.barWidgetEnabled("privacy")
                            width: parent.width
                            height: visible ? root.privacyRows.length * 46 + 14 : 0
                            CCTile { anchors.fill: parent; t: pal; gx: ccg; radius: 22 }
                            Column {
                                x: 8; y: 7
                                width: parent.width - 16
                                Repeater {
                                    model: root.privacyRows
                                    delegate: Item {
                                        id: pr
                                        required property var modelData
                                        width: parent.width; height: 46
                                        Rectangle {
                                            x: 4
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 30; height: 30; radius: 15
                                            color: pr.modelData.c
                                            Glyph { anchors.centerIn: parent; width: 15; height: 15; kind: pr.modelData.glyph; color: "white" }
                                        }
                                        Column {
                                            x: 44
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - 44 - (pr.modelData.k === "rec" ? 70 : 6)
                                            spacing: 1
                                            Text { width: parent.width; elide: Text.ElideRight; text: pr.modelData.title; color: pal.fg; font.family: pal.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
                                            Text { width: parent.width; elide: Text.ElideRight; text: pr.modelData.sub; color: pal.fg2; font.family: pal.fam; font.pixelSize: 11 }
                                        }
                                        Rectangle {
                                            visible: pr.modelData.k === "rec"
                                            anchors.right: parent.right; anchors.rightMargin: 4
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 54; height: 24; radius: 12
                                            color: "#FF453A"
                                            Text { anchors.centerIn: parent; text: I18n.tr("Stop"); color: "white"; font.family: pal.fam; font.pixelSize: 12; font.weight: Font.DemiBold }
                                            MouseArea { anchors.fill: parent; onClicked: root.toggleRecording() }
                                        }
                                    }
                                }
                            }
                        }

                        // ── the control grid ──
                        Item {
                            id: ccGrid
                            width: parent.width
                            height: Math.max(66, root.ccPlan.rows * 76 - 10)
                            readonly property real cw: (width - 30) / 4
                            readonly property real chh: 66

                            Text {
                                visible: root.ccPlan.items.length === 0
                                anchors.centerIn: parent
                                text: I18n.tr("No controls. Use Edit Controls to add some.")
                                color: pal.fg2; font.family: pal.fam; font.pixelSize: 12
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
                                    x: (slot ? slot.col * (ccGrid.cw + 10) : 0) + dx
                                    y: (slot ? slot.row * (ccGrid.chh + 10) : 0) + dy
                                    width: slot ? slot.w * ccGrid.cw + (slot.w - 1) * 10 : 0
                                    height: slot ? slot.h * ccGrid.chh + (slot.h - 1) * 10 : 0
                                    z: dragging ? 100 : 0
                                    // stretch-and-settle, a touch later for each row / column (ColorOS 17)
                                    property real ap: 1
                                    Connections {
                                        target: cc
                                        function onOpenSeqChanged() { ct.ap = 0; tileIn.restart(); }
                                    }
                                    SequentialAnimation {
                                        id: tileIn
                                        PauseAnimation { duration: (root.ccAnimate && ct.slot) ? Math.min(220, ct.slot.row * 55 + ct.slot.col * 18) : 0 }
                                        NumberAnimation { target: ct; property: "ap"; from: 0; to: 1; duration: root.ccAnimate ? 460 : 1; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                                    }
                                    transform: Translate { y: (1 - ct.ap) * 16 }
                                    opacity: Math.max(0, Math.min(1, ct.ap * 1.6))
                                    scale: dragging ? 1.04 : 1
                                    Behavior on x { enabled: !ct.dragging; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    Behavior on y { enabled: !ct.dragging; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                                    Loader {
                                        anchors.fill: parent
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
                                        color: pal.dark ? "#636366" : "#8E8E93"
                                        border.width: 1.5
                                        border.color: pal.dark ? Qt.rgba(1, 1, 1, 0.35) : "white"
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
                                color: pal.fg2
                                font.family: pal.fam; font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                            Flow {
                                width: parent.width
                                spacing: 8
                                Repeater {
                                    id: ccAddRep
                                    model: root.ccCatalog.filter(function (d) { return root.ccControls.indexOf(d.id) < 0 && root.ccUsable(d.id); })
                                    delegate: CCTile {
                                        id: chip
                                        required property var modelData
                                        t: pal; gx: ccg
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
                                                Text { anchors.centerIn: parent; text: "+"; color: "white"; font.pixelSize: 14; font.weight: Font.Bold }
                                            }
                                            Glyph {
                                                width: 16; height: 16
                                                anchors.verticalCenter: parent.verticalCenter
                                                kind: chip.modelData.glyph; color: pal.fg
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: chip.modelData.label
                                                color: pal.fg; font.family: pal.fam; font.pixelSize: 12
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
                            // comes in with the controls, a beat after the last row
                            property real ap: 1
                            Connections {
                                target: cc
                                function onOpenSeqChanged() { ccEditRow.ap = 0; editIn.restart(); }
                            }
                            SequentialAnimation {
                                id: editIn
                                PauseAnimation { duration: root.ccAnimate ? Math.min(260, root.ccPlan.rows * 55 + 40) : 0 }
                                NumberAnimation { target: ccEditRow; property: "ap"; from: 0; to: 1; duration: root.ccAnimate ? 460 : 1; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                            }
                            opacity: Math.max(0, Math.min(1, ap * 1.6))
                            transform: Translate { y: (1 - ccEditRow.ap) * 16 }
                            Row {
                                anchors.centerIn: parent
                                spacing: 8
                                CCPill {
                                    visible: ui.ccEdit
                                    t: pal; gx: ccg
                                    text: I18n.tr("Reset")
                                    onClicked: root.ccControls = root.ccDefault.slice()
                                }
                                CCPill {
                                    t: pal; gx: ccg
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
                        tint: root.solidAll ? 1.0 : (swPanel.style === "frosted" ? Math.max(0.5, root.glassOpacity) : root.glassOpacity)
                        thickness: swPanel.style === "frosted" ? 6 : 20
                        strength: swPanel.style === "frosted" ? 0.0 : 0.75 * root.glassLiquid
                        rim: swPanel.style === "frosted" ? 0.15 : root.glassRim
                        grain: root.glassGrain
                        blur: swPanel.style === "frosted" ? 30 : root.switcherBlur
                        debug: root.glassDebug
                        onShaderError: root.glassState = "failed"
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
                                // the selected app's icon lifts a little
                                scale: root.swIndex === swCell.index ? 1.06 : 0.96
                                Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutQuint } }
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
                    TextMetrics { id: swNameM; font.family: pal.fam; font.pixelSize: 13; font.weight: Font.Medium; text: swName.text }
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
                            font.family: pal.fam; font.pixelSize: 13; font.weight: Font.Medium
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
                        tint: root.effGlassOpacity
                        tintHue: root.tintAccent ? root.accent : "transparent"
                        thickness: 22
                        strength: 0.75 * root.glassLiquid
                        rim: root.glassRim
                        grain: root.glassGrain
                        blur: root.wpBlur
                        debug: root.glassDebug
                        onShaderError: root.glassState = "failed"
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
                            font.family: pal.fam; font.pixelSize: 15; font.weight: Font.DemiBold
                        }
                        Rectangle {
                            id: wpChoose
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 84; height: 30; radius: 10
                            color: wpChooseMa.containsMouse ? pal.btnHover : pal.btnOff
                            Text { anchors.centerIn: parent; text: I18n.tr("Choose\u2026"); color: pal.fg; font.family: pal.fam; font.pixelSize: 12; font.weight: Font.Medium }
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
                                font.family: pal.fam; font.pixelSize: 12
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
                            font.family: pal.fam; font.pixelSize: 12
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
                                font.family: pal.fam; font.pixelSize: 12
                            }
                        }
                        Rectangle {
                            visible: root.wpQuery !== ""
                            anchors.right: parent.right; anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16; height: 16; radius: 8
                            color: pal.btnOff
                            Text { anchors.centerIn: parent; text: "\u00d7"; color: pal.fg; font.pixelSize: 12 }
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
                        font.family: pal.fam; font.pixelSize: 11
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
                                        // decode at the size the cell shows: decoding whole 4K files is what made the grid crawl
                                        sourceSize.width: Math.max(160, Math.round(wpGrid.cellWidth))
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
                                            font.family: pal.fam; font.pixelSize: 11
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
                                            font.family: pal.fam; font.pixelSize: 10; font.weight: Font.DemiBold
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
                                        font.pixelSize: 15
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
                              : "No images in " + root.wpDirEff + "\nDrop some in, or pick another folder with Choose\u2026"
                        color: pal.fg2
                        font.family: pal.fam; font.pixelSize: 13
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
            anchors { left: true; right: true; top: true; bottom: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.namespace: "macspot"
            // Overlay while it is open: a fullscreen window covers the Top layer, so Spotlight opened but stayed hidden
            WlrLayershell.layer: spotWin.openish ? WlrLayer.Overlay : WlrLayer.Top
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
                        color: root.darkMode ? Qt.rgba(0.16, 0.16, 0.18, 0.92) : Qt.rgba(0.97, 0.97, 0.98, 0.95)
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
                        color: root.darkMode ? "white" : "#1d1d1f"; font.family: root.fontFamily; font.pixelSize: 13
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
                ShaderEffectSource {
                    id: spSrc
                    sourceItem: spotBackdrop.item     // wallpaper + live windows, captured inside this layer
                    hideSource: true
                    live: spotWin.openish
                    visible: false
                    sourceRect: Qt.rect(spot.x - 128, spot.y - 128, spot.width + 256, 684)
                }
                MultiEffect {
                    id: spBlurFx
                    source: spSrc
                    width: spSrc.sourceRect.width; height: spSrc.sourceRect.height
                    blurEnabled: true
                    blurMax: 6
                    blur: Math.min(1.0, (spg.blur * spg.blurMul) * 1.4 / 6.0)
                    autoPaddingEnabled: false
                    visible: false
                }
                // real Gaussian pre-blur of the backdrop (Qt MultiEffect): the glass shader refracts THIS texture,
                // so there are no sampled copies of the background any more
                ShaderEffectSource {
                    id: spBlur
                    sourceItem: spBlurFx
                    live: spotWin.openish
                    visible: false
                }
                MultiEffect {
                    id: spBlur2Fx
                    source: spBlur
                    width: spSrc.sourceRect.width; height: spSrc.sourceRect.height
                    blurEnabled: true
                    blurMax: 64
                    blur: Math.max(0.0, Math.min(1.0, (spg.blur * spg.blurMul) * 1.4 / 64.0 - 1.0))
                    autoPaddingEnabled: false
                    visible: false
                }
                // second Gaussian pass: stacks on the first one so Spotlight can blur past a single pass's 64 px limit
                ShaderEffectSource {
                    id: spBlur2
                    sourceItem: spBlur2Fx
                    live: spotWin.openish
                    visible: false
                }
                GlassCtx {
                    id: spg
                    src: spBlur2
                    srcRect: spSrc.sourceRect
                    frame: spotRoot
                    liquid: root.liquidActive
                    blurred: !root.liquidActive && root.wantBackdrop
                    shaderUrl: root.glassShaderUrl
                    dark: root.effDark
                    tint: root.effGlassOpacity
                    strength: root.glassLiquid * 0.6        // Spotlight: gentler refraction than the Dock
                    rim: root.glassRim * 0.4                 // and a subtle rim (no heavy outline)
                    grain: root.glassGrain
                    blur: root.glassBlur
                    blurMul: 12.0                   // Spotlight: strong smooth blur (two stacked Gaussian passes); lower to soften, raise to blur more
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
                    Behavior on y { enabled: spot.vis > 0.99; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    // opens with a springy pop; dismiss: quick fade + shrink
                    property real vis: 0
                    opacity: vis
                    visible: vis > 0.001
                    scale: ui.spCalm ? 0.98 : 0.94
                    transformOrigin: Item.Center
                    states: State {
                        name: "open"
                        when: ui.pop === "spot"
                        PropertyChanges { target: spot; vis: 1; scale: 1 }
                    }
                    transitions: [
                        Transition {
                            from: ""; to: "open"
                            ParallelAnimation {
                                NumberAnimation { property: "vis"; duration: 520; easing.type: Easing.OutCubic }
                                NumberAnimation { property: "scale"; duration: ui.spCalm ? 460 : 580; easing.type: Easing.OutQuint }
                            }
                        },
                        Transition {
                            from: "open"; to: ""
                            ParallelAnimation {
                                NumberAnimation { property: "vis"; duration: 400; easing.type: Easing.OutCubic }
                                NumberAnimation { property: "scale"; to: 0.95; duration: 400; easing.type: Easing.OutCubic }
                            }
                        }
                    ]

                    Timer { id: spHoverClear; interval: 350; onTriggered: ui.spHoverLabel = "" }
                    Timer {
                        id: spFocusTimer
                        interval: 60
                        onTriggered: (ui.spMode === "apps" ? appsInput : (ui.spMode === "clip" ? clipInput : (ui.spMode === "emoji" ? emojiInput : spInput))).forceActiveFocus()
                    }

                    // ── search pill + the four round buttons ──
                    Row {
                        id: spRow
                        spacing: 12
                        opacity: !ui.spFull ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                        Item {
                            id: spPill
                            width: spot.width - 5 * 60
                            height: 48
                            GGlass { anchors.fill: parent; gx: spg; cornerR: 24; thickness: 18; strengthMul: 0.7; shadowAmt: 0.18 }
                            HoverHandler { id: pillHover }
                            ContourGlow { cornerR: 24; hovered: pillHover.hovered; at: pillHover.point.position; glowColor: root.darkMode ? "white" : root.accent }
                            Glyph {
                                x: 18; anchors.verticalCenter: parent.verticalCenter
                                width: 18; height: 18
                                kind: "search"; color: pal.fg2
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
                                color: pal.fg2
                                font.family: pal.fam; font.pixelSize: 17
                                elide: Text.ElideRight
                            }
                            TextInput {
                                id: spInput
                                x: 46
                                width: parent.width - 46 - 18
                                anchors.verticalCenter: parent.verticalCenter
                                clip: true
                                color: pal.fg
                                selectionColor: root.accent
                                selectedTextColor: "white"
                                font.family: pal.fam; font.pixelSize: 17
                                horizontalAlignment: /[\u0590-\u08ff]/.test(text) ? Text.AlignRight : Text.AlignLeft
                                onTextChanged: { if (!ui.spFull) { ui.spQuery = text; ui.spSel = 0; ui.armed = ""; if (/^(file|find)\s+/i.test(text)) root.updateFileSearch(text.replace(/^(file|find)\s+/i, "").trim()); } }
                                Keys.onPressed: event => ui.spKey(event)
                            }
                        }
                        Repeater {
                            model: [
                                { k: "appstore", id: "apps", label: I18n.tr("Apps") }, { k: "folder", id: "files", label: I18n.tr("Files") },
                                { k: "layers", id: "actions", label: I18n.tr("Actions") }, { k: "clipboard", id: "clip", label: I18n.tr("Clipboard") }, { k: "smile", id: "emoji", label: I18n.tr("Emoji") }
                            ]
                            delegate: CCBtn {
                                required property var modelData
                                t: pal; gx: spg
                                d: 48
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
                                ContourGlow { cornerR: 24; hovered: btnHover.hovered; at: btnHover.point.position; glowColor: root.darkMode ? "white" : root.accent }
                                onClicked: {
                                    if (modelData.id === "apps") ui.spSetMode(ui.spMode === "apps" ? "home" : "apps");
                                    else if (modelData.id === "actions") ui.spSetMode(ui.spMode === "actions" ? "home" : "actions");
                                    else if (modelData.id === "files") { ui.pop = ""; if (hub && hub.openFolder) hub.openFolder(Quickshell.env("HOME")); else root.sh(root.filesCmd); }
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
                        readonly property int selIdx: Math.max(0, Math.min(ui.spSel, items.length - 1))
                        opacity: (!ui.spFull && items.length > 0) ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                        height: (items.length > 0 ? items.length : keep) * 46 + 16
                        Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutQuint } }
                        GGlass { anchors.fill: parent; gx: spg; cornerR: 26; thickness: 22; strengthMul: 0.75; shadowAmt: 0.22 }
                        Item {
                            x: 8; y: 8
                            width: parent.width - 16
                            height: parent.height - 16
                            clip: true
                            Rectangle {
                                y: resPanel.selIdx * 46
                                width: parent.width; height: 46; radius: 16
                                color: (resPanel.items[resPanel.selIdx] && resPanel.items[resPanel.selIdx].confirm === true
                                        && ui.armed === resPanel.items[resPanel.selIdx].title) ? "#FF453A" : root.accent
                                Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 120 } }
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
                                    readonly property bool sel: index === Math.min(ui.spSel, resPanel.items.length - 1)
                                    readonly property bool armedNow: modelData.confirm === true && ui.armed === modelData.title
                                    width: parent.width
                                    height: 46
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
                                            color: rr.sel ? "white" : pal.fg
                                        }
                                    }
                                    Text {
                                        x: 54
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 54 - 140
                                        elide: Text.ElideRight
                                        text: rr.armedNow ? I18n.tr("Press Return again to confirm") : (rr.modelData ? rr.modelData.title : "")
                                        color: rr.sel ? "white" : pal.fg
                                        font.family: pal.fam; font.pixelSize: 14
                                    }
                                    Text {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 16
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: rr.modelData ? rr.modelData.sub : ""
                                        color: rr.sel ? Qt.rgba(1, 1, 1, 0.8) : pal.fg2
                                        font.family: pal.fam; font.pixelSize: 12
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onEntered: ui.spSel = rr.index
                                        onClicked: ui.spActivate(rr.index)
                                    }
                                }
                            }
                        }
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
                        GGlass { anchors.fill: parent; gx: spg; cornerR: 32; thickness: 30; strengthMul: 0.85; shadowAmt: 0.5 }

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
                                color: pal.fg
                                font.family: pal.fam; font.pixelSize: 24; font.weight: Font.Medium
                            }
                            TextInput {
                                id: clipInput
                                x: clipLabel.x + clipLabel.width + 14
                                width: parent.width - x - 48
                                anchors.verticalCenter: parent.verticalCenter
                                clip: true
                                color: pal.fg
                                selectionColor: root.accent
                                selectedTextColor: "white"
                                font.family: pal.fam; font.pixelSize: 24
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
                                        color: cr.sel ? Qt.rgba(1, 1, 1, 0.22) : (root.darkMode ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06))
                                        Glyph {
                                            anchors.centerIn: parent
                                            width: 20; height: 20
                                            kind: cr.modelData.kind === "url" ? "link" : "doc"
                                            color: cr.sel ? "white" : pal.fg2
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
                                        Rectangle { anchors.fill: parent; radius: 10; color: root.darkMode ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06) }
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
                                    color: cr.sel ? "white" : pal.fg
                                    font.family: pal.fam; font.pixelSize: 14
                                }
                                Text {
                                    x: 62; y: 31
                                    width: parent.width - 62 - 56
                                    elide: Text.ElideRight
                                    text: cr.modelData ? cr.modelData.sub : ""
                                    color: cr.sel ? Qt.rgba(1, 1, 1, 0.8) : pal.fg2
                                    font.family: pal.fam; font.pixelSize: 12
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
                                color: pal.fg
                                font.family: pal.fam; font.pixelSize: 15; font.weight: Font.Medium
                            }
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                text: clipPanel.emptySub
                                color: pal.fg2
                                font.family: pal.fam; font.pixelSize: 12
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
                            GGlass { anchors.fill: parent; gx: spg; cornerR: 20; thickness: 22; strengthMul: 0.8; shadowAmt: 0.6 }
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
                                            kind: "check"; color: cmMa.containsMouse ? "white" : pal.fg
                                        }
                                        Text {
                                            x: 38
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: cm.modelData === "auto" ? I18n.tr("Paste Automatically")
                                                  : (cm.modelData === "del" ? "Delete Selected"
                                                  : (cm.armedNow ? "Click again to confirm" : "Clear History"))
                                            color: cmMa.containsMouse ? "white" : ((cm.modelData === "clear") ? "#FF453A" : pal.fg)
                                            font.family: pal.fam; font.pixelSize: 14
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
                        GGlass { anchors.fill: parent; gx: spg; cornerR: 32; thickness: 30; strengthMul: 0.85; shadowAmt: 0.5 }

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
                                color: pal.fg
                                font.family: pal.fam; font.pixelSize: 24; font.weight: Font.Medium
                            }
                            TextInput {
                                id: emojiInput
                                x: emojiLabel.x + emojiLabel.width + 14
                                width: parent.width - x
                                anchors.verticalCenter: parent.verticalCenter
                                clip: true
                                color: pal.fg
                                selectionColor: root.accent
                                selectedTextColor: "white"
                                font.family: pal.fam; font.pixelSize: 24
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
                            color: pal.fg2
                            font.family: pal.fam; font.pixelSize: 14
                        }

                        // footer: name of the highlighted emoji
                        Item {
                            x: 20; y: parent.height - 46
                            width: parent.width - 40; height: 46
                            Rectangle { width: parent.width; height: 1; color: pal.sep }
                            Text {
                                x: 4
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 180
                                elide: Text.ElideRight
                                text: emojiPanel.cur ? (emojiPanel.cur[0] + "  " + emojiPanel.cur[1]) : ""
                                color: pal.fg2
                                font.family: pal.fam; font.pixelSize: 13
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.clipAutoPaste ? I18n.tr("Return to insert") : I18n.tr("Return to copy")
                                color: pal.fg3
                                font.family: pal.fam; font.pixelSize: 12
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
                        GGlass { anchors.fill: parent; gx: spg; cornerR: 32; thickness: 30; strengthMul: 0.85; shadowAmt: 0.5 }

                        Item {
                            id: appsHeader
                            x: 24
                            width: parent.width - 48
                            height: 64
                            Glyph {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 24; height: 24
                                kind: "appstore"; color: pal.fg2
                            }
                            Text {
                                x: 40 + 3
                                anchors.verticalCenter: parent.verticalCenter
                                visible: appsInput.text === ""
                                text: I18n.tr("Applications")
                                color: pal.fg3
                                font.family: pal.fam; font.pixelSize: 24
                            }
                            TextInput {
                                id: appsInput
                                x: 40
                                width: parent.width - 40 - 48
                                anchors.verticalCenter: parent.verticalCenter
                                clip: true
                                color: pal.fg
                                selectionColor: root.accent
                                selectedTextColor: "white"
                                font.family: pal.fam; font.pixelSize: 24
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
                            // feathered ends: apps fade out as they scroll past, instead of being sliced
                            layer.enabled: appsFlick.contentHeight > appsFlick.height
                            layer.effect: ShaderEffect {
                                fragmentShader: Qt.resolvedUrl("fade.frag.qsb")
                                property real fadeTop: appsFlick.contentY > 2 ? Math.min(0.12, 30 / Math.max(1, appsFlick.height)) : 0.0015
                                property real fadeBottom: appsFlick.contentY < appsFlick.contentHeight - appsFlick.height - 2 ? Math.min(0.12, 30 / Math.max(1, appsFlick.height)) : 0.0015
                                Behavior on fadeTop { NumberAnimation { duration: 180 } }
                                Behavior on fadeBottom { NumberAnimation { duration: 180 } }
                            }

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

                                        Rectangle { width: parent.width; height: 1; color: pal.sep }
                                        Item {
                                            width: parent.width
                                            height: 38
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: sec.modelData.name
                                                color: pal.fg
                                                font.family: pal.fam; font.pixelSize: 13; font.weight: Font.Bold
                                            }
                                            Text {
                                                visible: !sec.searching && sec.modelData.apps.length > 5
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: sec.expanded ? I18n.tr("Show Less") : I18n.tr("Show More")
                                                color: root.accent
                                                font.family: pal.fam; font.pixelSize: 12; font.weight: Font.Bold
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
                                                        color: cma.containsMouse ? pal.hover : "transparent"
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
                                                        color: pal.fg
                                                        font.family: pal.fam; font.pixelSize: 12
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
                                    color: pal.fg2
                                    font.family: pal.fam; font.pixelSize: 14
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
