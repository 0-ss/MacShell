// macbar — a macOS Tahoe style menu bar for Hyprland, built on Quickshell.
//
// Part of the combined macbar + macdock shell (see shell.qml). Keep this file, MacDock.qml, shell.qml and
// liquidglass.frag together in ~/.config/quickshell/macbar/ and run:  qs -c macbar
//
// Settings live in ~/.config/macbar/settings.json (Apple menu → System Settings…, or Control Center → Edit Controls).
// On first run, appearance (dark mode, accent, font, glass tuning, wallpaper) is inherited from macdock's settings.json.
//
// Hyprland (hyprland.conf syntax):
//   windowrule = float, title:^(macbar Settings)$
//   windowrule = center, title:^(macbar Settings)$
//   layerrule  = blur, macspot          (Spotlight is its own layer; the bar itself needs no blur rule)
//   layerrule  = ignorealpha 0.05, macspot
// Hyprland (Lua):
//   hl.layer_rule({ name = "macspot", match = { namespace = "macspot" }, blur = true, ignore_alpha = 0.05, no_anim = true })
//
// Optional tools used by the Control Center:
//   nmcli (Wi-Fi), bluetoothctl (Bluetooth), brightnessctl (Display), hyprsunset (Night Shift),
//   systemd-inhibit (Keep Awake), grim + slurp + wl-copy + notify-send (File → Screenshot),
//   man / xdg-open (Help), an emoji picker such as emote/bemoji/rofimoji (Edit → Emoji & Symbols),
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
// Star a wallpaper to pin it to the top. Applied through Noctalia / awww / swww / hyprpaper, or your own "wallpaperCmd" ({} = image path).
// Its Clipboard button uses cliphist + wl-copy (command: clipboardCmd), Files runs filesCmd.

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

Scope {
    id: root

    // shared helpers from shell.qml (window geometry poller, wallpaper lookup)
    property var hub: null

    // ───────────── CONFIG (all persisted to settings.json) ─────────────
    property bool barEnabled: true           // false = no menu bar / Spotlight / Control Center at all
    property bool darkMode: true
    property color accent: "#0A84FF"
    property string fontFamily: "Inter"
    property int barHeight: 28
    property real glassOpacity: 0.42
    property string barStyle: "liquid"        // "liquid" = Apple Liquid Glass popovers, "blur" = flat translucent
    property real glassRim: 0.45
    property real glassGrain: 0.015
    property real glassLiquid: 1.0
    property real glassBlur: 5
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
    property string filesCmd: "xdg-open \"$HOME\""
    property string clipboardCmd: "cliphist list | (fuzzel --dmenu || wofi --dmenu || rofi -dmenu) | cliphist decode | wl-copy"
    property var appUsage: ({})               // launch counts, feeds the "Suggestions" row in Spotlight
    property int spotRequest: 0
    property int nightTemp: 4000
    // Control Center: ids of the enabled controls, in order (edit with Control Center → Edit Controls)
    property var ccControls: ["wifi", "nowplaying", "bluetooth", "airplane", "focus", "nightshift", "keepawake", "display", "sound"]

    readonly property var settingKeys: ["barEnabled", "darkMode", "accent", "fontFamily", "barHeight", "glassOpacity",
        "barStyle", "glassRim", "glassGrain", "glassLiquid", "glassBlur", "glassDebug", "wallpaperPath", "use24h", "showDate",
        "showSeconds", "showBatteryPercent", "showTray", "showSearch", "weekStartsMonday", "terminal", "launcher",
        "filesCmd", "clipboardCmd", "appUsage", "nightTemp", "ccControls", "wallpaperDir", "wallpaperFavs", "wallpaperCmd"]
    readonly property var accentChoices: [
        { name: "Blue", c: "#0a84ff" }, { name: "Purple", c: "#bf5af2" }, { name: "Pink", c: "#ff375f" },
        { name: "Red", c: "#ff453a" }, { name: "Orange", c: "#ff9f0a" }, { name: "Yellow", c: "#ffd60a" },
        { name: "Green", c: "#30d158" }, { name: "Graphite", c: "#8e8e93" }
    ]

    // ═════════════ CONTROL CENTER LAYOUT ═════════════
    // The Control Center is a 4-column grid. Every control has a size in grid cells; the enabled ones are packed
    // first-fit in the order of `ccControls`, so dragging a control onto another one simply reorders the list.
    readonly property var ccCatalog: [
        { id: "wifi",       label: "Wi-Fi",         glyph: "wifi",       w: 2, h: 1 },
        { id: "bluetooth",  label: "Bluetooth",     glyph: "bluetooth",  w: 1, h: 1 },
        { id: "airplane",   label: "Airplane Mode", glyph: "airplane",   w: 1, h: 1 },
        { id: "focus",      label: "Focus",         glyph: "moon",       w: 2, h: 1 },
        { id: "nightshift", label: "Night Shift",   glyph: "nightshift", w: 1, h: 1 },
        { id: "keepawake",  label: "Keep Awake",    glyph: "coffee",     w: 1, h: 1 },
        { id: "darkmode",   label: "Dark Mode",     glyph: "contrast",   w: 1, h: 1 },
        { id: "nowplaying", label: "Now Playing",   glyph: "note",       w: 2, h: 2 },
        { id: "display",    label: "Display",       glyph: "sun",        w: 4, h: 1 },
        { id: "sound",      label: "Sound",         glyph: "speaker",    w: 4, h: 1 }
    ]
    readonly property var ccDefault: ["wifi", "nowplaying", "bluetooth", "airplane", "focus", "nightshift", "keepawake", "display", "sound"]
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
    readonly property int popRoom: 620

    function sh(cmd) { Quickshell.execDetached(["sh", "-c", cmd]); }
    // Log out of Hyprland. 0.55+ (Lua) takes a Lua expression; UWSM sessions are stopped through uwsm so the session ends cleanly.
    function logOut() {
        sh('if command -v uwsm >/dev/null 2>&1 && uwsm check is-active >/dev/null 2>&1; then uwsm stop; '
           + 'else hyprctl dispatch "hl.dsp.exit()" || hyprctl dispatch exit; fi');
    }

    // ═════════════ PALETTE ═════════════
    QtObject {
        id: pal
        readonly property bool dark: root.darkMode
        readonly property string fam: root.fontFamily
        readonly property color accent: root.accent
        readonly property color fg: dark ? "#FFFFFF" : "#1D1D1F"
        readonly property color fg2: dark ? Qt.rgba(1, 1, 1, 0.62) : Qt.rgba(0, 0, 0, 0.55)
        readonly property color fg3: dark ? Qt.rgba(1, 1, 1, 0.34) : Qt.rgba(0, 0, 0, 0.32)
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
        property real thickness: 30
        property real strength: 1.0         // liquid glass strength multiplier
        property real rim: 0.45
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
                ShaderEffectSource {
                    id: bsrc
                    sourceItem: g.backdrop
                    hideSource: true
                    live: true
                    visible: false
                    sourceRect: Qt.rect(g.bx - lg.p - lg.m, g.by - lg.p - lg.m,
                                        g.width + 2 * (lg.p + lg.m), g.height + 2 * (lg.p + lg.m))
                }
                MultiEffect {
                    id: bblurFx
                    source: bsrc
                    width: bsrc.sourceRect.width; height: bsrc.sourceRect.height
                    blurEnabled: true
                    blurMax: 64
                    blur: Math.min(1.0, (g.blur) * 1.4 / 64.0)
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
                    width: bsrc.sourceRect.width; height: bsrc.sourceRect.height
                    blurEnabled: (g.blur) * 1.4 / 64.0 > 1.0
                    blurMax: 64
                    blur: Math.max(0.0, Math.min(1.0, (g.blur) * 1.4 / 64.0 - 1.0))
                    autoPaddingEnabled: false
                    visible: false
                }
                // second Gaussian pass: only active when the slider goes past a single pass's 64 px limit
                ShaderEffectSource {
                    id: bblur2
                    sourceItem: bblur2Fx
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
                    property variant src: bblur2
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
                    property real shadowAmt: 1
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
    component CCBtn: Item {
        id: b
        required property var t
        required property var gx
        property string kind: ""
        property bool on: false
        property real level: 3
        property bool flag: false
        property real d: 40
        property real shadow: 0
        signal clicked()
        property bool bounce: false
        width: d; height: d
        scale: (bounce && bma.pressed) ? 0.88 : 1
        Behavior on scale { NumberAnimation { duration: 230; easing.type: Easing.OutBack; easing.overshoot: 3.2 } }
        GGlass { anchors.fill: parent; gx: b.gx; cornerR: b.d / 2; thickness: 14; strengthMul: 0.6; shadowAmt: b.shadow }
        Rectangle {
            anchors.fill: parent
            radius: b.d / 2
            color: b.on ? Qt.rgba(b.t.accent.r, b.t.accent.g, b.t.accent.b, 0.92)
                        : (bma.containsMouse ? (b.t.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.34)) : Qt.rgba(1, 1, 1, 0))
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        Glyph {
            anchors.centerIn: parent
            width: b.d * 0.46; height: width
            kind: b.kind; level: b.level; flag: b.flag
            color: b.on ? "white" : b.t.fg
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
        signal moved(real v)
        height: 28
        readonly property real trackX: 28
        readonly property real trackW: Math.max(1, s.width - 28 - 26)
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
        MouseArea {
            anchors.fill: parent
            preventStealing: true
            function setFrom(mx) { s.moved(Math.max(0, Math.min(1, (mx - s.trackX) / s.trackW))); }
            onPressed: mouse => setFrom(mouse.x)
            onPositionChanged: mouse => { if (pressed) setFrom(mouse.x); }
        }
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
            x: 70; y: 14
            width: parent.width - 70 - 44
            spacing: 1
            Text {
                width: parent.width
                text: nb.urgency === 2 ? "TIME SENSITIVE" : nb.app
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
                visible: text !== ""
                color: nb.t.fg
                font.family: nb.t.fam; font.pixelSize: 14; font.weight: Font.Bold
                wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: nb.body
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
    component PSwitch: Item {
        id: sw
        required property var t
        property bool checked: false
        signal toggled(bool value)
        width: 38; height: 22
        Rectangle { anchors.fill: parent; radius: 11; color: sw.checked ? sw.t.accent : sw.t.switchOff }
        Rectangle {
            x: sw.checked ? 18 : 2; y: 2; width: 18; height: 18; radius: 9; color: "white"
            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
        MouseArea { anchors.fill: parent; onClicked: sw.toggled(!sw.checked) }
    }
    component PSlider: Item {
        id: ps
        required property var t
        property real from: 0
        property real to: 1
        property real value: 0
        signal moved(real v)
        width: 190; height: 22
        readonly property real pos: to > from ? Math.max(0, Math.min(1, (value - from) / (to - from))) : 0
        Rectangle { y: 9; width: parent.width; height: 4; radius: 2; color: ps.t.track }
        Rectangle { y: 9; width: ps.pos * (ps.width - 20) + 10; height: 4; radius: 2; color: ps.t.accent }
        Rectangle {
            x: ps.pos * (ps.width - 20); y: 1; width: 20; height: 20; radius: 10; color: "white"
            border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.16)
        }
        MouseArea {
            anchors.fill: parent
            preventStealing: true
            function setFrom(mx) {
                var p = Math.max(0, Math.min(1, (mx - 10) / (ps.width - 20)));
                ps.moved(Math.round((ps.from + p * (ps.to - ps.from)) * 100) / 100);
            }
            onPressed: mouse => setFrom(mouse.x)
            onPositionChanged: mouse => { if (pressed) setFrom(mouse.x); }
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
        { id: "file", label: "File" },
        { id: "edit", label: "Edit" },
        { id: "view", label: "View" },
        { id: "window", label: "Window" },
        { id: "help", label: "Help" }
    ]

    // audio
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [root.sink] }
    readonly property real volume: (sink && sink.audio) ? sink.audio.volume : 0
    readonly property bool muted: (sink && sink.audio) ? sink.audio.muted : false
    function setVolume(v) { if (sink && sink.audio) { sink.audio.muted = false; sink.audio.volume = Math.max(0, Math.min(1, v)); } }
    function toggleMute() { if (sink && sink.audio) sink.audio.muted = !sink.audio.muted; }
    readonly property real volLevel: muted || volume <= 0.001 ? 0 : (volume < 0.34 ? 1 : (volume < 0.67 ? 2 : 3))

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
    readonly property int wifiLevel: !wifiOn ? 0 : (wifiSsid === "" ? 0 : (wifiSignal > 66 ? 3 : (wifiSignal > 33 ? 2 : 1)))
    function refreshWifi() { if (!wifiProc.running) wifiProc.running = true; }
    Process {
        id: wifiProc
        command: ["sh", "-c", "nmcli radio wifi 2>/dev/null; nmcli -t -f ACTIVE,SSID,SIGNAL dev wifi 2>/dev/null | grep '^yes' | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: {
                var l = text.split("\n");
                root.wifiOn = (l[0] || "").trim() === "enabled";
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
    Timer { id: wifiAfter; interval: 1200; onTriggered: { root.scanWifi(); root.refreshWifi(); } }

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
    function setBrightness(v) { brightness = Math.max(0.01, Math.min(1, v)); brightApply.restart(); }

    // focus / night shift / keep awake
    property bool dnd: false
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
    function shot(region) {      // "" = whole screen, "sel" = pick an area, otherwise "x,y WxH"
        var g = region === "" ? "" : (region === "sel" ? "-g \"$(slurp)\"" : "-g '" + region + "'");
        sh("d=\"$HOME/Pictures\"; mkdir -p \"$d\"; f=\"$d/Screenshot-$(date +%F_%H-%M-%S).png\"; "
           + "grim " + g + " \"$f\" && { wl-copy < \"$f\"; notify-send -a macbar 'Screenshot saved' \"$f\"; }");
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
        if (launcher !== "") sh(launcher);
        else spotRequest++;                       // every bar window listens and the focused screen opens Spotlight
    }
    IpcHandler {
        target: "spotlight"
        function toggle(): void { root.search(); }
    }

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
            out.push({ title: r[i].name, sub: r[i].genericName || "Application", icon: iconSrc(r[i].icon),
                       glyph: "", confirm: false, run: appRunner(r[i]) });
        return out;
    }
    function actionItems(q) {
        var all = [
            { title: "Lock Screen", glyph: "lock", run: function () { sh("loginctl lock-session"); } },
            { title: "Sleep", glyph: "moon", run: function () { sh("systemctl suspend"); } },
            { title: "System Settings\u2026", glyph: "gear", run: function () { openSettings(); } },
            { title: "Log Out", glyph: "logout", confirm: true, run: function () { root.logOut(); } },
            { title: "Restart", glyph: "restart", confirm: true, run: function () { sh("systemctl reboot"); } },
            { title: "Shut Down", glyph: "power", confirm: true, run: function () { sh("systemctl poweroff"); } }
        ];
        var s = (q || "").trim().toLowerCase(), out = [];
        for (var i = 0; i < all.length; i++) {
            if (s !== "" && all[i].title.toLowerCase().indexOf(s) < 0) continue;
            out.push({ title: all[i].title, sub: "Action", icon: "", glyph: all[i].glyph,
                       confirm: all[i].confirm === true, run: all[i].run });
        }
        return out;
    }
    function homeItems(q) {
        var out = appItems(q, 7), s = (q || "").trim().toLowerCase();
        if (s.length >= 2) {
            var acts = actionItems(q);
            for (var i = 0; i < acts.length && out.length < 8; i++)
                if (acts[i].title.toLowerCase().indexOf(s) === 0) out.push(acts[i]);
        }
        return out;
    }

    function menuModelFor(name) {
        var m = [], i;
        if (name === "apple") {
            m.push(mi("About This Linux", "", function () { sh(terminal + " -e sh -c 'fastfetch || neofetch; echo; read -p \"Press Enter\" _'"); }));
            m.push(msep());
            m.push(mi("System Settings\u2026", "", function () { root.openSettings(); }));
            m.push(msep());
            m.push(mi("Lock Screen", "", function () { sh("loginctl lock-session"); }));
            m.push(mi("Sleep", "", function () { sh("systemctl suspend"); }));
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
                    m.push(mi("New Terminal", "", function () { sh(terminal); }));
                    m.push(mi("Open Home Folder", "", function () { sh(filesCmd); }));
                    m.push(msep());
                    m.push(mi("Search\u2026", "", function () { root.search(); }));
                } else {
                    m.push(mi("About " + n, "", function () { root.aboutActive(aw, n); }));
                    if (editor || files) {
                        m.push(msep());
                        m.push(mi("Preferences\u2026", "Ctrl+,", keys(["ctrl"], "comma")));
                    }
                    m.push(msep());
                    m.push(mi("Hide " + n, "", disp('hl.dsp.window.move({ workspace = "special:hidden", follow = false })')));
                    m.push(mi("Show Hidden Windows", "", disp('hl.dsp.workspace.toggle_special("hidden")')));
                    m.push(msep());
                    m.push(mi("Quit " + n, "Ctrl+Q", function () { root.quitActive(); }));
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
                m.push(mi("Clipboard History\u2026", "", function () { sh(clipboardCmd); }));
                m.push(mi("Emoji & Symbols", "", function () { root.emoji(); }));
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
                m.push(mchk("Dark Mode", "", root.darkMode, function () { root.darkMode = !root.darkMode; }));
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
                m.push(mi("Hyprland Keybinds", "", function () { sh(terminal + " -e sh -c 'hyprctl binds | less'"); }));
                m.push(mi("Reload Hyprland Config", "", function () { Quickshell.execDetached(["hyprctl", "reload"]); }));
                m.push(msep());
                m.push(mi("Hyprland Wiki", "", function () { Quickshell.execDetached(["xdg-open", "https://wiki.hypr.land"]); }));
                m.push(mi("Quickshell Documentation", "", function () { Quickshell.execDetached(["xdg-open", "https://quickshell.org/docs"]); }));
            }
        }
        return m;
    }

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
        darkMode = true; accent = "#0a84ff"; fontFamily = "Inter"; glassOpacity = 0.42; glassBlur = 5;
        barStyle = "liquid"; use24h = true; showDate = true; showSeconds = false; showBatteryPercent = true;
        showTray = true; showSearch = true;
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
            root.settingsReady = true;
            if (root.barStyle === "liquid") root.startGlass();
        }
        onLoadFailed: { root.settingsReady = true; if (root.barStyle === "liquid") root.startGlass(); }
    }

    // ═════════════ LIQUID GLASS BACKEND (same pipeline as macdock) ═════════════
    property string glassState: "idle"       // idle → building → ready | failed
    readonly property bool liquidActive: barStyle === "liquid" && glassState === "ready"
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

    // live window geometry for the backdrop (polled only while a glass popover is open)
    readonly property var monData: hub ? hub.monData : []
    readonly property var glassClients: hub ? hub.glassClients : []
    property int popCount: 0
    onBarEnabledChanged: if (!barEnabled) popCount = 0
    Binding { target: root.hub; property: "barWantsGeo"; value: root.liquidActive && root.popCount > 0 }
    function tlFor(addr) {
        var a = String(addr).replace(/^0x/, "");
        var ts = Hyprland.toplevels.values;
        for (var i = 0; i < ts.length; i++) if (ts[i].address === a) return ts[i].wayland;
        return null;
    }
    property int windowTick: 0
    Connections {
        target: Hyprland
        function onRawEvent(event) { tickDebounce.restart(); }
    }
    Timer { id: tickDebounce; interval: 120; onTriggered: root.windowTick++ }

    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", configDir]);
        refreshBrightness();
    }

    // ═════════════ SETTINGS ═════════════
    // The settings window now lives in MacDock.qml (one window for the whole shell).
    function openSettings(pane) { if (hub) hub.openSettings(pane || "menubar"); }

    // ═════════════ THE BAR ═════════════
    // ═════════════ NOTIFICATIONS ═════════════
    // Receives org.freedesktop.Notifications on D-Bus (stop dunst / mako / swaync first — only one daemon can own the name).
    property bool notifDnd: false            // Do Not Disturb: still stored in the centre, but no popups
    property real notifBlur: 64              // blur of the notification glass (smooth two-pass Gaussian, same method as the Blur slider)
    property int notifUnread: 0
    property int notifSeq: 0
    property var notifRefs: ({})
    ListModel { id: notifHist }              // notification centre history, newest first
    ListModel { id: notifToasts }            // popups currently on screen, newest first

    NotificationServer {
        id: notifServer
        keepOnReload: false
        bodySupported: true
        bodyMarkupSupported: false
        imageSupported: true
        actionsSupported: true
        persistenceSupported: true
        onNotification: n => root.notifReceive(n)
    }
    function notifIndex(model, id) {
        for (var i = 0; i < model.count; i++) if (model.get(i).nid === id) return i;
        return -1;
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
        if (!root.notifDnd || urg === 2) {
            notifToasts.insert(0, rec);
            while (notifToasts.count > 4) notifToasts.remove(notifToasts.count - 1);
        }
        if (!root.notifOpen) root.notifUnread++;
        try { n.closed.connect(function () { root.notifToastRemove(id); }); } catch (e) {}
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
            out.push({ path: favs[i], name: root.wpName(favs[i]), fav: true });
        }
        for (i = 0; i < root.wpDirList.length; i++) {
            var f = root.wpDirList[i];
            if (seen[f]) continue;
            out.push({ path: f, name: root.wpName(f), fav: false });
        }
        root.wpFiles = out;
    }
    function wpParse(text) {
        var lines = text.split("\n"), dir = [], ok = {};
        for (var i = 0; i < lines.length; i++) {
            var l = lines[i];
            if (l.indexOf("A:") === 0) dir.push(l.substring(2));
            else if (l.indexOf("F:") === 0) ok[l.substring(2)] = true;
        }
        root.wpDirList = dir;
        root.wpFavOk = ok;
        root.wpRebuild();
    }
    function wpRefresh() {
        if (wpScan.running) return;
        var script = [
            'd="$1"; mk="$2"; shift 2',
            '[ "$mk" = "1" ] && [ ! -d "$d" ] && mkdir -p "$d" 2>/dev/null',
            'if [ -d "$d" ]; then find -L "$d" -maxdepth 3 -type f 2>/dev/null | grep -iE "[.](jpe?g|png|webp|bmp|gif)$" | sort -V | sed "s/^/A:/"; fi',
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
    function wpApply(path) {
        root.wallpaperPath = path;                                            // the glass refracts the new image straight away
        try { if (root.hub && root.hub.dock) root.hub.dock.wallpaperPath = path; } catch (e) {}
        var cmd = (root.wallpaperCmd || "").trim();
        var script = cmd !== "" ? cmd.split("{}").join('"$1"') : [
            'p="$1"',
            // Noctalia (its settings.toml is where the glass wallpaper is read from): `noctalia msg wallpaper-set <path>`
            'if command -v noctalia >/dev/null 2>&1 && noctalia msg wallpaper-set "$p"; then echo "applied with: noctalia"; exit 0; fi',
            // awww needs its daemon; start it if it is installed but not running yet
            'if command -v awww >/dev/null 2>&1; then',
            '  if ! awww query >/dev/null 2>&1; then',
            '    if command -v awww-daemon >/dev/null 2>&1; then setsid awww-daemon >/dev/null 2>&1 & fi',
            '    for i in 1 2 3 4 5 6 7 8 9 10; do awww query >/dev/null 2>&1 && break; sleep 0.3; done',
            '  fi',
            '  if awww img "$p" --transition-type fade --transition-duration 0.7; then echo "applied with: awww"; exit 0; fi',
            'fi',            'if command -v swww >/dev/null 2>&1 && swww query >/dev/null 2>&1 && swww img "$p" --transition-type fade --transition-duration 0.7; then echo "applied with: swww"; exit 0; fi',
            'if pgrep -x hyprpaper >/dev/null 2>&1; then',
            '  if hyprctl hyprpaper wallpaper ",$p" >/dev/null 2>&1 || { hyprctl hyprpaper preload "$p" >/dev/null 2>&1; hyprctl hyprpaper wallpaper ",$p" >/dev/null 2>&1; }; then echo "applied with: hyprpaper"; exit 0; fi',
            'fi',
            // older Noctalia (QML): qs -c noctalia-shell ipc call wallpaper set <path> <monitor>
            'if pgrep -f noctalia-shell >/dev/null 2>&1 && qs -c noctalia-shell ipc call wallpaper set "$p" ""; then echo "applied with: noctalia-shell (qs ipc)"; exit 0; fi',
            'if pgrep -x swaybg >/dev/null 2>&1; then pkill -x swaybg; setsid swaybg -i "$p" -m fill >/dev/null 2>&1 & echo "applied with: swaybg"; exit 0; fi',
            'echo "no wallpaper daemon accepted the image (tried noctalia, awww, swww, hyprpaper, noctalia-shell, swaybg)" >&2',
            'echo "running: $(ps -eo comm= | grep -E "^(noctalia|noctalia-shell|awww-daemon|swww-daemon|hyprpaper|swaybg|wpaperd)$" | sort -u | tr "\\n" " ")" >&2',
            'notify-send "Wallpaper" "Could not set it: no supported wallpaper daemon found. Set wallpaperCmd in settings.json." 2>/dev/null',
            'exit 1'
        ].join("\n");
        wpApplyProc.command = ["sh", "-c", script, "sh", path];
        wpApplyProc.running = true;
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
    property real switcherBlur: 40           // blur of the switcher glass (smooth Gaussian; less than Spotlight / notifications)
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
            if (seen[id] !== undefined) { apps[seen[id]].count++; continue; }
            var e = root.lookup(id);
            seen[id] = apps.length;
            apps.push({ appId: id, name: e ? e.name : id, icon: e ? e.icon : "", win: t, count: 1 });
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
            lua += "hl.dispatch(hl.dsp.focus({ window = \"" + (t.addr !== "" ? "address:" + t.addr : "class:^(" + t.cls + ")$") + "\" }))";
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
            var cls = (a.appId || "").toLowerCase(), ttl = a.win.title || "", loose = null;
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
        root.swPending = { addr: addr, ws: ws, cls: (a.appId || "").replace(/[\\"']/g, "") };
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
        model: (root.settingsReady && root.barEnabled) ? Quickshell.screens : []

        Scope {
            id: perScreen
            required property var modelData

        PanelWindow {
            id: win
            property var modelData: perScreen.modelData
            screen: perScreen.modelData

            anchors { left: true; right: true; top: true }
            implicitHeight: root.barHeight + root.popRoom
            color: "transparent"

            exclusionMode: ExclusionMode.Normal
            exclusiveZone: root.barHeight

            WlrLayershell.namespace: "macbar"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: (ui.pop === "wifi" && ui.wifiPrompt !== "") ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

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
                property var trayItem: null         // SystemTrayItem whose menu is open in the tray popover
                property var trayStack: []          // submenu path (QsMenuEntry objects) inside that menu
                readonly property bool toastScreen: Quickshell.screens.length === 1 || (Hyprland.focusedMonitor !== null && Hyprland.focusedMonitor.name === win.modelData.name)
                readonly property bool toastsShown: toastScreen && notifToasts.count > 0

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
                property int spSel: 0
                property var spExpanded: ({})
                property var spResults: spMode === "actions" ? root.actionItems(spQuery)
                                        : (spQuery.trim() === "" ? [] : root.homeItems(spQuery))

                function spSetMode(m) {
                    spMode = m; spQuery = ""; spSel = 0; armed = "";
                    spInput.text = ""; appsInput.text = "";
                    spFocusTimer.restart();
                }
                function spEscape() {
                    if (spQuery !== "") { spInput.text = ""; appsInput.text = ""; spQuery = ""; }
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
                    } else spActivate(Math.min(spSel, spResults.length - 1));
                }
                function spKey(ev) {
                    if (ev.key === Qt.Key_Escape) { spEscape(); ev.accepted = true; }
                    else if (ev.key === Qt.Key_Down) { spMove(1); ev.accepted = true; }
                    else if (ev.key === Qt.Key_Up) { spMove(-1); ev.accepted = true; }
                    else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) { spEnter(); ev.accepted = true; }
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
                readonly property bool isMenu: ["apple", "app", "file", "edit", "view", "window", "help"].indexOf(pop) >= 0
                readonly property bool anyVisible: menuPop.visible || cc.visible || cal.visible || wifiPop.visible || trayPop.visible || notifPop.visible || toastArea.visible || volPop.visible
                onAnyVisibleChanged: root.popCount += (anyVisible ? 1 : -1)
                onPopChanged: {
                    armed = "";
                    wifiPrompt = "";
                    if (pop !== "cc") ccEdit = false;
                    root.notifOpen = (pop === "notif");
                    if (pop === "notif") root.notifUnread = 0;
                    if (pop === "wifi") { root.wifiError = ""; root.scanWifi(); }
                    if (pop === "spot") {
                        spMode = "home"; spQuery = ""; spSel = 0; spExpanded = ({});
                        spInput.text = ""; appsInput.text = "";
                        spFocusTimer.restart();
                    }
                }
                Connections {
                    target: root
                    function onSpotRequestChanged() {
                        var fm = Hyprland.focusedMonitor;
                        if (!fm || fm.name === win.modelData.name || Quickshell.screens.length === 1) ui.openPop("spot", 0);
                    }
                }

                function openPop(name, x) {
                    if (pop === name) { pop = ""; return; }
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
                Loader {
                    id: glassBackdrop
                    active: root.liquidActive && (ui.anyVisible || ui.toastsShown)
                    sourceComponent: backdropComp
                }
                Component {
                    id: backdropComp
                    Item {
                        id: bd
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
                            visible: status === Image.Ready
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
                                x: wx; y: wy; width: ww; height: wh; z: wz
                                readonly property var tl: { root.windowTick; return root.tlFor(addr); }
                                ScreencopyView {
                                    anchors.fill: parent
                                    captureSource: gw.tl
                                    live: ui.anyVisible || spotWin.visible || swWin.visible || wpWin.visible
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
                                want[cl.address] = { addr: cl.address, wx: x, wy: y, ww: w, wh: h, wz: z };
                            }
                            for (var j = wm.count - 1; j >= 0; j--) {
                                var a = wm.get(j).addr;
                                if (want[a] === undefined) wm.remove(j);
                                else { wm.set(j, want[a]); delete want[a]; }
                            }
                            for (var k in want) wm.append(want[k]);
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

                // click-away layer (under the popovers and the bar)
                MouseArea {
                    anchors.fill: parent
                    z: 5
                    visible: ui.pop !== "" && ui.pop !== "spot"
                    acceptedButtons: Qt.AllButtons
                    onPressed: ui.pop = ""
                }

                // ═════════ the bar itself ═════════
                Rectangle {
                    id: barBg
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
                        height: parent.height
                        Repeater {
                            model: root.menuTitles
                            delegate: Item {
                                id: mt
                                required property var modelData
                                readonly property bool open: ui.pop === modelData.id
                                width: modelData.id === "apple" ? 30 : tl.implicitWidth + 20
                                height: barBg.height
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width - 2
                                    height: parent.height - 6
                                    radius: 6
                                    color: mt.open ? pal.hover : "transparent"
                                }
                                Glyph {
                                    visible: mt.modelData.id === "apple"
                                    anchors.centerIn: parent
                                    width: 15; height: 15
                                    kind: "arch"
                                    color: pal.fg
                                }
                                Text {
                                    id: tl
                                    visible: mt.modelData.id !== "apple"
                                    anchors.centerIn: parent
                                    text: mt.modelData.label
                                    color: pal.fg
                                    font.family: pal.fam
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
                        anchors.horizontalCenter: parent.horizontalCenter
                        height: parent.height
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
                                width: 22; height: barBg.height
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width - 2
                                    height: parent.height - 6
                                    radius: 6
                                    color: wsi.cur ? pal.hover : "transparent"
                                    opacity: wsi.cur || wsMa.containsMouse ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 140 } }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: "" + wsi.modelData
                                    color: wsi.cur ? pal.fg : (wsi.busy ? pal.fg2 : pal.fg3)
                                    font.family: pal.fam
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
                        height: parent.height
                        spacing: 0

                        // tray
                        Repeater {
                            model: root.showTray ? SystemTray.items : null
                            delegate: Item {
                                id: tray
                                required property var modelData
                                width: 26; height: barBg.height
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width - 2
                                    height: parent.height - 6
                                    radius: 6
                                    color: (ui.pop === "tray" && ui.trayItem === tray.modelData) ? pal.hover : "transparent"
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

                        // bluetooth
                        Item {
                            visible: root.btOn
                            width: 26; height: barBg.height
                            Glyph { anchors.centerIn: parent; width: 15; height: 15; kind: "bluetooth"; color: root.btConnected > 0 ? pal.fg : pal.fg2 }
                            MouseArea { anchors.fill: parent; onClicked: ui.openPop("cc", 0) }
                        }
                        // volume (opens a popover with just the volume slider)
                        Item {
                            id: volBtn
                            width: 28; height: barBg.height
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width - 2; height: parent.height - 6; radius: 6
                                color: ui.pop === "vol" ? pal.hover : "transparent"
                            }
                            Glyph { anchors.centerIn: parent; width: 16; height: 16; kind: "speaker"; level: root.volLevel; color: pal.fg }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: ui.openPop("vol", volBtn.mapToItem(ui, 0, 0).x + volBtn.width / 2)
                                onWheel: wheel => root.setVolume(root.volume + (wheel.angleDelta.y > 0 ? 0.03 : -0.03))
                            }
                        }
                        // battery
                        Item {
                            visible: root.hasBattery
                            width: batRow.width + 14; height: barBg.height
                            Row {
                                id: batRow
                                anchors.centerIn: parent
                                spacing: 5
                                Text {
                                    visible: root.showBatteryPercent
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.batPct + "%"
                                    color: pal.fg
                                    font.family: pal.fam; font.pixelSize: 12
                                }
                                Item {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 25; height: 12
                                    Rectangle {
                                        id: bbody
                                        width: 22; height: 12; radius: 3.5
                                        color: "transparent"
                                        border.width: 1
                                        border.color: pal.fg2
                                        Rectangle {
                                            x: 1.5; y: 1.5
                                            width: Math.max(2, (parent.width - 3) * Math.min(1, root.batPct / 100))
                                            height: parent.height - 3
                                            radius: 2
                                            color: root.charging ? "#30D158" : (root.batPct <= 15 ? "#FF453A" : pal.fg)
                                        }
                                    }
                                    Rectangle { x: 23; y: 4; width: 2; height: 4; radius: 1; color: pal.fg2 }
                                    Glyph {
                                        visible: root.charging
                                        anchors.centerIn: bbody
                                        width: 9; height: 9
                                        kind: "bolt"
                                        color: pal.dark ? "#111" : "#fff"
                                    }
                                }
                            }
                            MouseArea { anchors.fill: parent; onClicked: ui.openPop("cc", 0) }
                        }
                        // notification system (bell)
                        Item {
                            id: bellBtn
                            width: 28; height: barBg.height
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width - 2; height: parent.height - 6; radius: 6
                                color: ui.pop === "notif" ? pal.hover : "transparent"
                            }
                            Glyph { anchors.centerIn: parent; width: 16; height: 16; kind: "bell"; color: root.notifDnd ? pal.fg2 : pal.fg }
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
                            width: 28; height: barBg.height
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width - 2; height: parent.height - 6; radius: 6
                                color: ui.pop === "wifi" ? pal.hover : "transparent"
                            }
                            Glyph { anchors.centerIn: parent; width: 16; height: 16; kind: "wifi"; level: root.wifiOn ? (root.wifiLevel || 1) : 3; flag: !root.wifiOn; color: root.wifiOn ? pal.fg : pal.fg2 }
                            MouseArea { anchors.fill: parent; onClicked: ui.openPop("wifi", wifiBtn.mapToItem(ui, 0, 0).x) }
                        }
                        // search
                        Item {
                            visible: root.showSearch
                            width: 28; height: barBg.height
                            Glyph { anchors.centerIn: parent; width: 15; height: 15; kind: "search"; color: pal.fg }
                            MouseArea { anchors.fill: parent; onClicked: { if (root.launcher !== "") { ui.pop = ""; root.search(); } else ui.openPop("spot", 0); } }
                        }
                        // control center
                        Item {
                            id: ccBtn
                            width: 30; height: barBg.height
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width - 2; height: parent.height - 6; radius: 6
                                color: ui.pop === "cc" ? pal.hover : "transparent"
                            }
                            Glyph { anchors.centerIn: parent; width: 16; height: 16; kind: "cc"; color: pal.fg }
                            MouseArea { anchors.fill: parent; onClicked: ui.openPop("cc", 0) }
                        }
                        // clock
                        Item {
                            id: clockBtn
                            width: clockText.implicitWidth + 16
                            height: barBg.height
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width - 2; height: parent.height - 6; radius: 6
                                color: ui.pop === "cal" ? pal.hover : "transparent"
                            }
                            Text {
                                id: clockText
                                anchors.centerIn: parent
                                text: root.clockText
                                color: pal.fg
                                font.family: pal.fam
                                font.pixelSize: 13
                            }
                            MouseArea { anchors.fill: parent; onClicked: ui.openPop("cal", 0) }
                        }
                    }
                }

                // ═════════ volume popover (speaker icon): just the volume slider ═════════
                Item {
                    id: volPop
                    z: 10
                    width: 250
                    height: 52
                    x: Math.max(6, Math.min(ui.width - width - 8, ui.menuX - width / 2))
                    y: root.barHeight + 6
                    opacity: ui.pop === "vol" ? 1 : 0
                    visible: opacity > 0
                    scale: ui.pop === "vol" ? 1 : 0.96
                    transformOrigin: Item.Top
                    Behavior on opacity { NumberAnimation { duration: 110 } }
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                    LGlass {
                        anchors.fill: parent
                        backdrop: glassBackdrop.item
                        shaderUrl: root.glassShaderUrl
                        liquid: root.liquidActive
                        dark: root.darkMode
                        bx: volPop.x; by: volPop.y
                        cornerR: 26
                        tint: root.glassOpacity
                        thickness: 22
                        strength: 0.7 * root.glassLiquid
                        rim: root.glassRim
                        grain: root.glassGrain
                        blur: root.glassBlur
                        debug: root.glassDebug
                        onShaderError: root.glassState = "failed"
                    }
                    MouseArea { anchors.fill: parent }      // clicks inside don't close the popover
                    CCSlider {
                        t: pal
                        x: 14; y: 12
                        width: parent.width - 28
                        value: root.muted ? 0 : root.volume
                        leftKind: "speaker"; leftLevel: 1
                        rightKind: "speaker"; rightLevel: 3
                        onMoved: v => root.setVolume(v)
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
                    y: root.barHeight + 8
                    height: toastCol.height
                    visible: ui.toastsShown
                    Column {
                        id: toastCol
                        width: parent.width
                        spacing: 10
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
                                width: toastCol.width
                                height: tbody.height
                                opacity: (shown && !leaving) ? 1 : 0
                                scale: (shown && !leaving) ? 1 : 0.96
                                transformOrigin: Item.Top
                                Behavior on opacity { NumberAnimation { duration: 180 } }
                                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                Component.onCompleted: shown = true
                                function dismiss() { leaving = true; goneTimer.restart(); }
                                Timer { interval: 200; id: goneTimer; onTriggered: root.notifToastRemove(toast.nid) }
                                Timer {
                                    interval: toast.life
                                    running: toast.shown && !toast.leaving && !thov.hovered
                                    onTriggered: toast.dismiss()
                                }
                                HoverHandler { id: thov }

                                LGlass {
                                    anchors.fill: parent
                                    backdrop: glassBackdrop.item
                                    shaderUrl: root.glassShaderUrl
                                    liquid: root.liquidActive
                                    dark: root.darkMode
                                    bx: toastArea.x + toast.x; by: toastArea.y + toast.y
                                    cornerR: 24
                                    tint: root.glassOpacity
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
                                NotifBody {
                                    id: tbody
                                    t: pal
                                    width: parent.width
                                    app: toast.app; summary: toast.summary; body: toast.body; icon: toast.icon
                                    urgency: toast.urgency; stamp: toast.time; nowMs: clock.date.getTime()
                                    showClose: thov.hovered
                                    onCloseClicked: toast.dismiss()
                                }
                            }
                        }
                    }
                }

                // ═════════ notification centre (bell) ═════════
                Item {
                    id: notifPop
                    z: 10
                    width: 380
                    height: 92 + (notifHist.count === 0 ? 70 : nfl.height) + 14
                    x: Math.max(6, ui.width - width - 8)
                    y: root.barHeight + 6
                    opacity: ui.pop === "notif" ? 1 : 0
                    visible: opacity > 0
                    scale: ui.pop === "notif" ? 1 : 0.96
                    transformOrigin: Item.TopRight
                    Behavior on opacity { NumberAnimation { duration: 110 } }
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                    LGlass {
                        anchors.fill: parent
                        backdrop: glassBackdrop.item
                        shaderUrl: root.glassShaderUrl
                        liquid: root.liquidActive
                        dark: root.darkMode
                        bx: notifPop.x; by: notifPop.y
                        cornerR: 26
                        tint: root.glassOpacity
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
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Notification system"
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
                                text: "Clear All"
                                color: pal.fg
                                font.family: pal.fam; font.pixelSize: 12; font.weight: Font.Medium
                            }
                            MouseArea { id: clrMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.notifClear() }
                        }
                    }
                    Item {
                        x: 12; y: 46; width: parent.width - 24; height: 36
                        Rectangle { anchors.fill: parent; radius: 12; color: pal.tile; border.width: 1; border.color: pal.tileBorder }
                        Glyph { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 15; height: 15; kind: "moon"; color: pal.fg }
                        Text {
                            x: 36; anchors.verticalCenter: parent.verticalCenter
                            text: "Do Not Disturb"
                            color: pal.fg
                            font.family: pal.fam; font.pixelSize: 13
                        }
                        Rectangle {
                            anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                            width: 38; height: 22; radius: 11
                            color: root.notifDnd ? pal.accent : pal.switchOff
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Rectangle {
                                y: 2; width: 18; height: 18; radius: 9; color: "white"
                                x: root.notifDnd ? 18 : 2
                                Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.notifDnd = !root.notifDnd }
                        }
                    }
                    Text {
                        visible: notifHist.count === 0
                        x: 0; y: 96; width: parent.width; height: 60
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        text: "No Notifications"
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
                                delegate: Rectangle {
                                    id: hc
                                    required property int nid
                                    required property string app
                                    required property string summary
                                    required property string body
                                    required property string icon
                                    required property int urgency
                                    required property real time
                                    width: ncol.width
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
                                        onCloseClicked: root.notifDelete(hc.nid)
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
                    x: Math.max(6, Math.min(ui.width - width - 6, ui.menuX - 4))
                    y: root.barHeight + 3
                    opacity: ui.isMenu ? 1 : 0
                    visible: opacity > 0
                    scale: ui.isMenu ? 1 : 0.97
                    transformOrigin: Item.TopLeft
                    Behavior on opacity { NumberAnimation { duration: 90 } }
                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                    LGlass {
                        anchors.fill: parent
                        backdrop: glassBackdrop.item
                        shaderUrl: root.glassShaderUrl
                        liquid: root.liquidActive
                        dark: root.darkMode
                        bx: menuPop.x; by: menuPop.y
                        cornerR: 14
                        tint: root.glassOpacity
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
                                    text: it.isSep ? "" : (it.armedNow ? "Click again to confirm" : it.modelData.label)
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
                    x: Math.max(6, Math.min(ui.width - width - 6, ui.menuX - 4))
                    y: root.barHeight + 3
                    opacity: shown ? 1 : 0
                    visible: opacity > 0
                    scale: shown ? 1 : 0.97
                    transformOrigin: Item.TopLeft
                    Behavior on opacity { NumberAnimation { duration: 90 } }
                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                    QsMenuOpener { id: trayOpener; menu: trayPop.cur }

                    LGlass {
                        anchors.fill: parent
                        backdrop: glassBackdrop.item
                        shaderUrl: root.glassShaderUrl
                        liquid: root.liquidActive
                        dark: root.darkMode
                        bx: trayPop.x; by: trayPop.y
                        cornerR: 14
                        tint: root.glassOpacity
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
                                        text: te.modelData.buttonType === QsMenuButtonType.RadioButton ? "\u25CF" : "\u2713"
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
                    x: Math.max(6, Math.min(ui.width - width - 8, ui.menuX + 14 - width / 2))
                    y: root.barHeight + 6
                    opacity: ui.pop === "wifi" ? 1 : 0
                    visible: opacity > 0
                    scale: ui.pop === "wifi" ? 1 : 0.96
                    transformOrigin: Item.Top
                    Behavior on opacity { NumberAnimation { duration: 110 } }
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                    LGlass {
                        anchors.fill: parent
                        backdrop: glassBackdrop.item
                        shaderUrl: root.glassShaderUrl
                        liquid: root.liquidActive
                        dark: root.darkMode
                        bx: wifiPop.x; by: wifiPop.y
                        cornerR: 22
                        tint: root.glassOpacity
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
                                text: "Wi-Fi"
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

                        Text {
                            visible: !root.wifiOn
                            width: parent.width; height: 56
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            text: "Wi-Fi is turned off"
                            color: pal.fg2
                            font.family: pal.fam; font.pixelSize: 13
                        }
                        Text {
                            visible: root.wifiOn && root.wifiNets.length === 0
                            width: parent.width; height: 56
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            text: root.wifiScanning ? "Searching\u2026" : "No networks found"
                            color: pal.fg2
                            font.family: pal.fam; font.pixelSize: 13
                        }
                        Text {
                            visible: root.wifiOn && root.wifiNets.length > 0
                            leftPadding: 6
                            text: "Networks"
                            color: pal.fg2
                            font.family: pal.fam; font.pixelSize: 11; font.weight: Font.DemiBold
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
                                                text: "Connecting\u2026"
                                                color: pal.fg2
                                                font.family: pal.fam; font.pixelSize: 12
                                            }
                                            Text {
                                                visible: !nr.busy && nr.modelData.inUse && wma.containsMouse
                                                anchors.right: parent.right; anchors.rightMargin: 12
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "Disconnect"
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
                                                text: "Password"
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
                                                text: "Join"
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
                                text: "Wi-Fi Settings\u2026"
                                color: wsa.containsMouse ? "white" : pal.fg
                                font.family: pal.fam; font.pixelSize: 13
                            }
                            MouseArea {
                                id: wsa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: { ui.pop = ""; root.sh("nm-connection-editor 2>/dev/null || " + root.terminal + " -e nmtui"); }
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
                    opacity: ui.pop === "cal" ? 1 : 0
                    visible: opacity > 0
                    scale: ui.pop === "cal" ? 1 : 0.96
                    transformOrigin: Item.TopRight
                    Behavior on opacity { NumberAnimation { duration: 110 } }
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                    LGlass {
                        anchors.fill: parent
                        backdrop: glassBackdrop.item
                        shaderUrl: root.glassShaderUrl
                        liquid: root.liquidActive
                        dark: root.darkMode
                        bx: cal.x; by: cal.y
                        cornerR: 24
                        tint: root.glassOpacity
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
                            text: Qt.formatDateTime(clock.date, "d MMMM yyyy")
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
                    opacity: ui.pop === "cc" ? 1 : 0
                    visible: opacity > 0
                    scale: ui.pop === "cc" ? 1 : 0.96
                    transformOrigin: Item.TopRight
                    Behavior on opacity { NumberAnimation { duration: 110 } }
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    onVisibleChanged: if (visible) { root.refreshWifi(); root.refreshBt(); root.refreshBrightness(); }

                    ShaderEffectSource {
                        id: ccSrc
                        sourceItem: glassBackdrop.item
                        hideSource: true
                        live: true
                        visible: false
                        sourceRect: Qt.rect(cc.x - 64, cc.y - 64, cc.width + 128, cc.height + 128)
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
                        sourceItem: ccBlur2Fx
                        live: true
                        visible: false
                    }
                    GlassCtx {
                        id: ccg
                        src: ccBlur2
                        srcRect: ccSrc.sourceRect
                        frame: ui
                        liquid: root.liquidActive
                        shaderUrl: root.glassShaderUrl
                        dark: root.darkMode
                        tint: root.glassOpacity
                        strength: root.glassLiquid
                        rim: root.glassRim
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
                                Text { text: "Wi-Fi"; color: pal.fg; font.family: pal.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
                                Text {
                                    width: parent.width; elide: Text.ElideRight
                                    text: !root.wifiOn ? "Off" : (root.wifiSsid !== "" ? root.wifiSsid : "Not Connected")
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
                                t: pal; gx: ccg; anchors.centerIn: parent
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
                                t: pal; gx: ccg; anchors.centerIn: parent
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
                                Text { text: "Focus"; color: pal.fg; font.family: pal.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
                                Text { text: root.dnd ? "Do Not Disturb" : "Off"; color: pal.fg2; font.family: pal.fam; font.pixelSize: 12 }
                            }
                        }
                    }
                    Component {
                        id: cNight
                        CCTile {
                            t: pal; gx: ccg
                            CCBtn {
                                t: pal; gx: ccg; anchors.centerIn: parent
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
                                t: pal; gx: ccg; anchors.centerIn: parent
                                kind: "coffee"; on: root.keepAwake
                                onClicked: root.keepAwake = !root.keepAwake
                            }
                        }
                    }
                    Component {
                        id: cDark
                        CCTile {
                            t: pal; gx: ccg
                            CCBtn {
                                t: pal; gx: ccg; anchors.centerIn: parent
                                kind: "contrast"; on: root.darkMode
                                onClicked: root.darkMode = !root.darkMode
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
                                width: 52; height: 52; radius: 5
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
                                    text: np.pl && np.pl.trackTitle ? np.pl.trackTitle : "Now Playing"
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
                                text: "Display"
                                color: pal.fg; font.family: pal.fam; font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                            CCSlider {
                                t: pal
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
                                text: "Sound"
                                color: pal.fg; font.family: pal.fam; font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                            CCSlider {
                                t: pal
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

                    Column {
                        id: ccCol
                        x: 0; y: 0
                        width: parent.width
                        spacing: 10

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
                                text: "No controls. Use Edit Controls to add some."
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
                                text: "Add Controls"
                                color: pal.fg2
                                font.family: pal.fam; font.pixelSize: 12; font.weight: Font.DemiBold
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
                            width: parent.width; height: 28
                            Row {
                                anchors.centerIn: parent
                                spacing: 8
                                CCPill {
                                    visible: ui.ccEdit
                                    t: pal; gx: ccg
                                    text: "Reset"
                                    onClicked: root.ccControls = root.ccDefault.slice()
                                }
                                CCPill {
                                    t: pal; gx: ccg
                                    text: ui.ccEdit ? "Done" : "Edit Controls"
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
                    active: root.liquidActive && swWin.visible
                    sourceComponent: backdropComp
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
                    opacity: (root.swOpen && ui.toastScreen) ? 1 : 0
                    visible: opacity > 0
                    scale: (root.swOpen && ui.toastScreen) ? 1 : 0.94
                    transformOrigin: Item.Center
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

                    LGlass {
                        anchors.fill: parent
                        backdrop: swBackdrop.item
                        shaderUrl: root.glassShaderUrl
                        liquid: root.liquidActive
                        dark: root.darkMode
                        bx: swPanel.x; by: swPanel.y
                        cornerR: 26
                        tint: root.glassOpacity
                        thickness: 20
                        strength: 0.75 * root.glassLiquid
                        rim: root.glassRim
                        grain: root.glassGrain
                        blur: root.switcherBlur
                        debug: root.glassDebug
                        onShaderError: root.glassState = "failed"
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
                        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
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
                    Text {
                        visible: swPanel.n > 0
                        text: root.swApps.length > root.swIndex ? root.swApps[root.swIndex].name : ""
                        color: pal.fg
                        font.family: pal.fam; font.pixelSize: 13; font.weight: Font.Medium
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, swPanel.width - 20)
                        x: Math.max(10, Math.min(swPanel.width - width - 10, swPanel.pad + root.swIndex * swPanel.cw + swPanel.cw / 2 - width / 2))
                        y: swPanel.padY + swPanel.cellH + 3
                        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
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
                    active: root.liquidActive && wpWin.visible
                    sourceComponent: backdropComp
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
                        dark: root.darkMode
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
                    }

                    // ── header: title, folder path, Choose… ──
                    Item {
                        id: wpHead
                        x: 22; y: 14
                        width: parent.width - 44; height: 34
                        Text {
                            id: wpTitle
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Wallpapers"
                            color: pal.fg
                            font.family: pal.fam; font.pixelSize: 15; font.weight: Font.DemiBold
                        }
                        Rectangle {
                            id: wpChoose
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 84; height: 30; radius: 10
                            color: wpChooseMa.containsMouse ? pal.btnHover : pal.btnOff
                            Text { anchors.centerIn: parent; text: "Choose\u2026"; color: pal.fg; font.family: pal.fam; font.pixelSize: 12; font.weight: Font.Medium }
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
                                text: "Search"
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
                            readonly property bool cur: root.wallpaperPath === modelData.path
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
                                        source: root.fileUrl(wc.modelData.path)
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
                                            font.family: pal.fam; font.pixelSize: 11
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
                        text: root.wpQuery !== "" ? "No wallpapers match \u201c" + root.wpQuery + "\u201d"
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
            visible: ui.pop === "spot" || spot.opacity > 0
            onVisibleChanged: root.popCount += (visible ? 1 : -1)     // keeps the window-geometry poller running while Spotlight is open
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
                    active: root.liquidActive && spotWin.visible
                    sourceComponent: backdropComp
                }

                // click outside Spotlight closes it
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    onPressed: ui.pop = ""
                }

                // ═════════ Spotlight (Liquid Glass) ═════════
                Item {
                    id: spot
                    z: 10
                    width: 640
                    height: ui.spMode === "apps" ? appsPanel.height : (resPanel.visible ? resPanel.y + resPanel.height : spRow.height)
                    x: Math.round((spotRoot.width - width) / 2)
                    // the search pill sits a little above the vertical centre of the screen (0.4 of the height; 0.5 = dead centre); the Applications panel centres itself instead
                    y: Math.round(spotRoot.height * 0.4 - (ui.spMode === "apps" ? appsPanel.height / 2 : 24))
                    Behavior on y { enabled: spot.opacity > 0.99; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    // opens with a springy pop; dismiss: quick fade + shrink
                    opacity: 0
                    visible: opacity > 0
                    scale: 0.8
                    transformOrigin: Item.Center
                    states: State {
                        name: "open"
                        when: ui.pop === "spot"
                        PropertyChanges { target: spot; opacity: 1; scale: 1 }
                    }
                    transitions: [
                        Transition {
                            from: ""; to: "open"
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; duration: 100 }
                                NumberAnimation { property: "scale"; duration: 360; easing.type: Easing.OutBack; easing.overshoot: 3.4 }
                            }
                        },
                        Transition {
                            from: "open"; to: ""
                            NumberAnimation { properties: "opacity,scale"; duration: 100; easing.type: Easing.InCubic }
                        }
                    ]

                    ShaderEffectSource {
                        id: spSrc
                        sourceItem: spotBackdrop.item     // wallpaper + live windows, captured inside this layer
                        hideSource: true
                        live: spotWin.visible
                        visible: false
                        sourceRect: Qt.rect(spot.x - 128, spot.y - 128, spot.width + 256, 684)
                    }
                    MultiEffect {
                        id: spBlurFx
                        source: spSrc
                        width: spSrc.sourceRect.width; height: spSrc.sourceRect.height
                        blurEnabled: true
                        blurMax: 64
                        blur: Math.min(1.0, (spg.blur * spg.blurMul) * 1.4 / 64.0)
                        autoPaddingEnabled: false
                        visible: false
                    }
                    // real Gaussian pre-blur of the backdrop (Qt MultiEffect): the glass shader refracts THIS texture,
                    // so there are no sampled copies of the background any more
                    ShaderEffectSource {
                        id: spBlur
                        sourceItem: spBlurFx
                        live: spotWin.visible
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
                        live: spotWin.visible
                        visible: false
                    }
                    GlassCtx {
                        id: spg
                        src: spBlur2
                        srcRect: spSrc.sourceRect
                        frame: spotRoot
                        liquid: root.liquidActive
                        shaderUrl: root.glassShaderUrl
                        dark: root.darkMode
                        tint: root.glassOpacity
                        strength: root.glassLiquid
                        rim: root.glassRim
                        grain: root.glassGrain
                        blur: root.glassBlur
                        blurMul: 12.0                   // Spotlight: strong smooth blur (two stacked Gaussian passes); lower to soften, raise to blur more
                        debug: root.glassDebug
                        onFailed: root.glassState = "failed"
                    }
                    Timer {
                        id: spFocusTimer
                        interval: 60
                        onTriggered: (ui.spMode === "apps" ? appsInput : spInput).forceActiveFocus()
                    }

                    // ── search pill + the four round buttons ──
                    Row {
                        id: spRow
                        spacing: 12
                        opacity: ui.spMode !== "apps" ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 160 } }

                        Item {
                            id: spPill
                            width: spot.width - 4 * 60
                            height: 48
                            GGlass { anchors.fill: parent; gx: spg; cornerR: 24; thickness: 20; strengthMul: 0.7; shadowAmt: 0.45 }
                            Glyph {
                                x: 18; anchors.verticalCenter: parent.verticalCenter
                                width: 18; height: 18
                                kind: "search"; color: pal.fg2
                            }
                            Text {
                                x: spInput.x + 3
                                anchors.verticalCenter: parent.verticalCenter
                                visible: spInput.text === ""
                                text: ui.spMode === "actions" ? "Actions" : "Spotlight Search"
                                color: pal.fg2
                                font.family: pal.fam; font.pixelSize: 17
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
                                onTextChanged: { if (ui.spMode !== "apps") { ui.spQuery = text; ui.spSel = 0; ui.armed = ""; } }
                                Keys.onPressed: event => ui.spKey(event)
                            }
                        }
                        Repeater {
                            model: [
                                { k: "appstore", id: "apps" }, { k: "folder", id: "files" },
                                { k: "layers", id: "actions" }, { k: "clipboard", id: "clip" }
                            ]
                            delegate: CCBtn {
                                required property var modelData
                                t: pal; gx: spg
                                d: 48
                                bounce: true
                                shadow: 0.45
                                kind: modelData.k
                                on: ui.spMode === modelData.id
                                onClicked: {
                                    if (modelData.id === "apps") ui.spSetMode(ui.spMode === "apps" ? "home" : "apps");
                                    else if (modelData.id === "actions") ui.spSetMode(ui.spMode === "actions" ? "home" : "actions");
                                    else if (modelData.id === "files") { ui.pop = ""; root.sh(root.filesCmd); }
                                    else { ui.pop = ""; root.sh(root.clipboardCmd); }
                                }
                            }
                        }
                    }

                    // ── results under the pill ──
                    Item {
                        id: resPanel
                        y: spRow.height + 10
                        width: spot.width
                        readonly property var items: ui.spResults
                        property int keep: 1                         // last non-empty row count, so the panel shrinks while it fades out
                        onItemsChanged: if (items.length > 0) keep = items.length
                        readonly property int selIdx: Math.max(0, Math.min(ui.spSel, items.length - 1))
                        opacity: (ui.spMode !== "apps" && items.length > 0) ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 140 } }
                        height: (items.length > 0 ? items.length : keep) * 46 + 16
                        Behavior on height { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
                        GGlass { anchors.fill: parent; gx: spg; cornerR: 26; thickness: 26; strengthMul: 0.8; shadowAmt: 0.5 }
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
                                    readonly property bool sel: index === Math.min(ui.spSel, resPanel.items.length - 1)
                                    readonly property bool armedNow: modelData.confirm === true && ui.armed === modelData.title
                                    width: parent.width
                                    height: 46
                                    Item {
                                        x: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 30; height: 30
                                        Image {
                                            visible: rr.modelData.icon !== ""
                                            anchors.fill: parent
                                            source: rr.modelData.icon
                                            sourceSize: Qt.size(64, 64)
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                            smooth: true
                                        }
                                        Glyph {
                                            visible: rr.modelData.icon === ""
                                            anchors.centerIn: parent
                                            width: 20; height: 20
                                            kind: rr.modelData.glyph
                                            color: rr.sel ? "white" : pal.fg
                                        }
                                    }
                                    Text {
                                        x: 54
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 54 - 140
                                        elide: Text.ElideRight
                                        text: rr.armedNow ? "Press Return again to confirm" : rr.modelData.title
                                        color: rr.sel ? "white" : pal.fg
                                        font.family: pal.fam; font.pixelSize: 14
                                    }
                                    Text {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 16
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: rr.modelData.sub
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

                    // ── Applications panel ──
                    Item {
                        id: appsPanel
                        opacity: ui.spMode === "apps" ? 1 : 0
                        visible: opacity > 0
                        scale: ui.spMode === "apps" ? 1 : 0.96
                        transformOrigin: Item.Top
                        Behavior on opacity { NumberAnimation { duration: 160 } }
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
                                text: "Applications"
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
                                                text: sec.expanded ? "Show Less" : "Show More"
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
                                    text: "No Results"
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
