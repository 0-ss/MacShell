// MacShell Installer — a graphical front end for install.sh, built like the shell's own System Settings and About windows:
// frameless window with the two-tone macOS edge, traffic lights, a translucent sidebar with coloured icons and a search field,
// a toolbar with back / forward, grouped cards with rows, glass-style switches and segmented controls.
//
// Run it with:  macshell-installer   (installed by install.sh)   or, from a clone:  qs -p MacInstaller
// Every action calls install.sh, so the window and the terminal installer always behave the same.
// Look (dark / light, accent, font) follows ~/.config/macbar/settings.json, like the shell does.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "I18n.js" as I18n
import "Fonts.js" as Fonts

Scope {
    id: root

    // ───────────── paths ─────────────
    readonly property string home: Quickshell.env("HOME")
    readonly property string script: Quickshell.env("MACSHELL_INSTALL_SH") || (Quickshell.shellDir + "/../install.sh")
    readonly property string binDir: home + "/.local/bin"
    readonly property string dataDir: (Quickshell.env("XDG_DATA_HOME") || (home + "/.local/share")) + "/macshell"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/macshell"
    readonly property string projectUrl: "https://github.com/0-ss/MacShell"
    readonly property string bindHelpUrl: projectUrl + "#hyprland-configuration-lua"
    property string windowTitle: "MacShell Installer"

    // ───────────── look (follows the shell's settings) ─────────────
    property bool darkMode: true
    // Liquid Glass: the shell's own liquidglass shader (compiled copy shipped next to this file). If it fails to load, the
    // controls fall back to plain ones.
    readonly property string build: "glass+fixed-12"
    property bool featherBlur: true       // scroll-under blur across the top of the page (testing)
    property bool glassOk: false          // turns on once the shader is ready; off again if it fails to load
    onGlassOkChanged: if (!glassOk && glassShaderUrl.toString() !== "") console.log("[macinstaller] glass shader failed to load:", glassShaderUrl)
    property url glassShaderUrl: ""
    // Same as the shell: use the shader it already built for this machine (~/.config/macdock/liquidglass.frag.qsb), else build
    // liquidglass.frag with qsb into the cache, else fall back to the compiled copy next to this file.
    readonly property string glassSrc: decodeURIComponent(Qt.resolvedUrl("liquidglass.frag").toString().replace("file://", ""))
    Process {
        id: glassProc
        property string out: ""
        command: ["sh", "-c",
            "o=\"$HOME/.config/macdock/liquidglass.frag.qsb\"; if [ -s \"$o\" ]; then echo \"$o\"; exit 0; fi; "
            + "o=\"${XDG_CACHE_HOME:-$HOME/.cache}/macshell-installer/liquidglass.frag.qsb\"; mkdir -p \"$(dirname \"$o\")\"; "
            + "for q in qsb qsb6 qsb-qt6 /usr/lib/qt6/bin/qsb /usr/lib64/qt6/bin/qsb /usr/lib/qt/bin/qsb; do "
            + "  if command -v \"$q\" >/dev/null 2>&1; then \"$q\" --qt6 -o \"$o\" \"$1\" 2>&1 && { echo \"$o\"; exit 0; }; fi; "
            + "done; "
            + "if [ -f \"$1.qsb\" ]; then cp \"$1.qsb\" \"$o\" && echo \"$o\" && exit 0; fi; exit 1",
            "sh", root.glassSrc]
        stdout: SplitParser { onRead: d => { var l = d.trim(); if (l.indexOf("/") === 0) glassProc.out = l; } }
        onExited: (code, status) => {
            if (code === 0 && out !== "") { root.glassShaderUrl = "file://" + out; root.glassOk = true; console.log("[macinstaller] glass shader:", out); }
            else console.log("[macinstaller] glass shader could not be built: plain controls");
        }
    }
    readonly property real glassLiquid: 1.0
    readonly property real glassRim: 0.45
    readonly property real glassGrain: 0.03
    readonly property real glassOpacity: 0.42
    readonly property color glassBorder: "#8A9AB5"
    property color accent: "#0A84FF"
    property string fam: "Open Runde"
    FontLoader { source: Qt.resolvedUrl("assets/fonts/OpenRunde-Regular.otf") }
    FontLoader { source: Qt.resolvedUrl("assets/fonts/OpenRunde-Semibold.otf") }
    function applyTheme(t) {
        try {
            var o = JSON.parse(t);
            if (o.darkMode !== undefined) darkMode = !!o.darkMode;
            if (o.accent) accent = String(o.accent);
            if (o.fontFamily) fam = String(o.fontFamily);
        } catch (e) { }
    }
    FileView {
        path: root.home + "/.config/macbar/settings.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.applyTheme(text())
    }

    QtObject {
        id: palObj
        readonly property bool dark: root.darkMode
        readonly property color accent: root.accent
        readonly property string fam: root.fam
        readonly property color contentSolid: dark ? "#1E1E1E" : "#F5F5F7"
        readonly property color sidebarGlass: dark ? Qt.rgba(0.17, 0.17, 0.18, 0.55) : Qt.rgba(0.94, 0.94, 0.96, 0.60)
        readonly property color sidebar: dark ? "#292929" : "#E9E9EC"
        readonly property color card: dark ? "#2B2B2D" : "#FFFFFF"
        readonly property color cardBorder: dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.12)
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
        readonly property color lightOff: dark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.15)
        readonly property color logBg: dark ? Qt.rgba(0, 0, 0, 0.28) : Qt.rgba(0, 0, 0, 0.04)
        readonly property color good: "#30D158"
        readonly property color warn: "#FF9F0A"
        readonly property color danger: "#FF453A"
        function lightBorder(active, c) { return active ? Qt.darker(c, dark ? 1.12 : 1.22) : "transparent"; }
    }
    readonly property var pal: palObj
    function fw(weight) { return Fonts.forWeight(weight, root.fam); }

    // ───────────── state ─────────────
    property bool busy: false
    property string runKind: ""
    property string raw: ""
    property string notice: ""                 // a short result line under the Install button
    property bool confirmUninstall: false

    property string installedVer: ""
    property string latestVer: ""
    property string updateState: "unknown"     // unknown | current | available | offline
    property bool checking: false
    property var plan: null                    // install.sh --deps-plan
    property bool planBusy: false

    // install options
    property bool optMain: false
    property bool optLock: true
    property bool optRules: true
    property bool optAutostart: true
    property bool optLow: false

    ListModel { id: logModel }
    readonly property var logM: logModel

    // what each package is for (same groups as the shell's own Install Dependencies window)
    readonly property var groups: [
        { name: "The shell", about: "Quickshell, Hyprland, Qt and the tools the shell itself uses",
          pkgs: ["quickshell", "hyprland", "qt6-declarative", "qt6-wayland", "qt6-svg", "qt6-shadertools", "mesa", "curl", "tar", "xdg-utils", "jq", "rsync", "python"] },
        { name: "Pictures, video and wallpapers", about: "Wallpapers, animated wallpapers, thumbnails and pictures",
          pkgs: ["awww", "mpvpaper", "ffmpeg", "imagemagick", "inotify-tools"] },
        { name: "Screenshots and recording", about: "Screenshots, screen recording, the colour picker and clipboard history",
          pkgs: ["grim", "slurp", "wf-recorder", "hyprpicker", "wl-clipboard", "cliphist", "xdg-desktop-portal-hyprland"] },
        { name: "System controls", about: "Sound, brightness, Bluetooth, Wi-Fi, Internet Sharing, power, the lock screen and Night Shift",
          pkgs: ["pipewire", "wireplumber", "pipewire-pulse", "brightnessctl", "bluez-utils", "util-linux", "networkmanager", "iw", "power-profiles-daemon", "hypridle", "hyprlock", "hyprsunset", "libnotify", "zenity", "polkit"] },
        { name: "Look and apps", about: "Fonts, emoji, icons, the terminal and About This Linux",
          pkgs: ["inter-font", "noto-fonts", "noto-fonts-emoji", "papirus-icon-theme", "kitty", "fastfetch"] }
    ]
    function stateOf(p) {
        if (!plan) return "";
        if (!plan.pacman) return "manual";
        if (plan.have && plan.have.indexOf(p) >= 0) return "installed";
        var sk = plan.skipped || [];
        for (var i = 0; i < sk.length; i++) if (String(sk[i]).split("|")[0] === p) return "skipped";
        if (plan.repo && plan.repo.indexOf(p) >= 0) return "install";
        if (plan.aur && plan.aur.indexOf(p) >= 0) return "aur";
        return "installed";
    }
    function reasonOf(p) {
        var sk = plan ? (plan.skipped || []) : [];
        for (var i = 0; i < sk.length; i++) { var s = String(sk[i]).split("|"); if (s[0] === p) return s[1] || ""; }
        return "";
    }
    // packages the plan mentions that none of the groups list
    readonly property var otherPkgs: {
        if (!plan || !plan.pacman) return [];
        var known = {}, out = [], g, i, j;
        for (g = 0; g < groups.length; g++) for (j = 0; j < groups[g].pkgs.length; j++) known[groups[g].pkgs[j]] = true;
        var lists = [plan.have || [], plan.repo || [], plan.aur || []];
        for (i = 0; i < lists.length; i++) for (j = 0; j < lists[i].length; j++) if (!known[lists[i][j]]) { known[lists[i][j]] = true; out.push(lists[i][j]); }
        return out;
    }
    readonly property int toInstall: plan && plan.pacman && plan.repo ? plan.repo.length : 0
    readonly property int aurCount: plan && plan.pacman && plan.aur ? plan.aur.length : 0
    readonly property int missing: plan && plan.pacman ? toInstall + aurCount : 0
    readonly property bool needsUpdate: plan && plan.pacman && plan.upgrades ? plan.upgrades.length > 0 : false
    readonly property string depsText: planBusy ? "Checking what is installed…"
        : !plan ? "Could not read the dependency list"
        : !plan.pacman ? "Not an Arch-based system: the terminal installer handles your package manager"
        : needsUpdate ? "Installing would also upgrade " + plan.upgrades.join(", ") + ": update the system first"
        : missing > 0 ? missing + (missing === 1 ? " package is" : " packages are") + " missing"
        : "Everything MacShell needs is installed"

    readonly property string shortInst: installedVer !== "" ? installedVer.substring(0, 12) : ""
    readonly property string shortLatest: latestVer !== "" ? latestVer.substring(0, 12) : ""
    readonly property string updateText: updateState === "available" ? "An update is available"
        : updateState === "current" ? "You are up to date"
        : updateState === "offline" ? "Could not reach GitHub" : (checking ? "Checking…" : "Not checked yet")

    // ───────────── helpers ─────────────
    function clean(s) { return String(s).replace(/\x1b\[[0-9;]*[A-Za-z]/g, "").replace(/\r/g, ""); }
    function classify(l) {
        if (/^==>/.test(l)) return "step";
        if (/^\s*✓/.test(l) || /Everything looks good|is installed\./.test(l)) return "ok";
        if (/^\s*!/.test(l) || /^error:/.test(l) || /problem\(s\) found/.test(l)) return "warn";
        if (/^\s*-\s/.test(l)) return "dim";
        return "n";
    }
    function parseCheck(text, code) {
        var m;
        if ((m = /installed:\s*(\S*)/.exec(text))) installedVer = m[1];
        if ((m = /latest:\s*(\S*)/.exec(text))) latestVer = m[1];
        if (code === 0) { updateState = "current"; if ((m = /up to date \(([^)]*)\)/.exec(text))) { installedVer = m[1]; if (latestVer === "") latestVer = m[1]; } }
        else if (code === 10) updateState = "available";
        else updateState = "offline";
    }
    function onLine(d) {
        var l = clean(d);
        if (l.trim() === "") return;
        raw += l + "\n";
        logModel.append({ t: l, k: classify(l) });
    }
    function clearLog() { logModel.clear(); raw = ""; }
    function sh(args) { return ["bash", script].concat(args); }
    function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
    function runMain(kind, cmd) {
        if (busy) return;
        clearLog(); notice = "";
        runKind = kind; busy = true;
        runner.command = cmd;
        runner.running = true;
    }
    function installArgs() {
        var a = ["-y", "--no-start", "--no-services", "--no-deps", "--no-verify"];
        a.push("--channel", optMain ? "main" : "release");
        if (!optLock) a.push("--no-lock");
        if (!optRules) a.push("--no-rules");
        if (!optAutostart) a.push("--no-autostart");
        if (optLow) a.push("--low-power");
        return a;
    }
    // commands that need a password (or a terminal) open in a terminal emulator
    function openTerminal(cmd) {
        Quickshell.execDetached(["sh", "-c",
            "c=\"$1\"; for t in kitty foot alacritty wezterm konsole xterm; do " +
            "if command -v $t >/dev/null 2>&1; then exec $t -e bash -c \"$c\"; fi; done; " +
            "command -v gnome-terminal >/dev/null 2>&1 && exec gnome-terminal -- bash -c \"$c\"; " +
            "notify-send 'MacShell Installer' 'No terminal emulator found: run the command yourself' 2>/dev/null",
            "sh", cmd + "; echo; read -r -p 'Done. Press Enter to close ' _"]);
    }
    function openPath(p) { Quickshell.execDetached(["xdg-open", p]); }
    function shellDetached(cmd) { Quickshell.execDetached(["sh", "-c", cmd]); }
    function runPlan() {
        if (planBusy) return;
        planBusy = true; plan = null;
        planProc.buf = "";
        planProc.command = sh(["--deps-plan"]);
        planProc.running = true;
    }
    function runQuietCheck() {
        if (checkProc.running) return;
        checking = true;
        checkProc.buf = "";
        checkProc.command = sh(["--check"]);
        checkProc.running = true;
    }
    function startShell() { shellDetached("setsid sh " + q(binDir + "/macshell-start") + " >/dev/null 2>&1 &"); }
    function stopShell() { shellDetached("pkill -f 'macshell-start'; qs kill -c MacShell"); }
    function restartShell() { shellDetached("qs kill -c MacShell >/dev/null 2>&1; sleep 1; setsid sh " + q(binDir + "/macshell-start") + " >/dev/null 2>&1 &"); }

    // ───────────── processes ─────────────
    Process {
        id: runner
        stdout: SplitParser { onRead: d => root.onLine(d) }
        stderr: SplitParser { onRead: d => root.onLine(d) }
        onExited: (code, status) => {
            root.busy = false;
            var k = root.runKind;
            if (k === "check") { root.parseCheck(root.raw, code); root.checking = false; }
            if (k === "install" || k === "update" || k === "rollback" || k === "uninstall") {
                root.onLine(code === 0 ? "✓ Finished" : "! Finished with exit code " + code);
                root.notice = code === 0 ? (k === "uninstall" ? "MacShell was removed. Your settings were kept." : "Done. Use Tools → Start MacShell to run it.") : "Something went wrong: see the output above.";
                stateWatch.reload();
                root.runQuietCheck();
                if (k === "install" || k === "update") root.runPlan();
            }
        }
    }
    Process {
        id: planProc
        property string buf: ""
        stdout: SplitParser { onRead: d => planProc.buf += root.clean(d) + "\n" }
        stderr: SplitParser { onRead: d => planProc.buf += root.clean(d) + "\n" }
        onExited: (code, status) => {
            root.planBusy = false;
            var lines = buf.split("\n");
            for (var i = lines.length - 1; i >= 0; i--) {
                if (lines[i].charAt(0) === "{") {
                    try { root.plan = JSON.parse(lines[i]); } catch (e) { root.plan = null; }
                    break;
                }
            }
        }
    }
    Process {
        id: checkProc
        property string buf: ""
        stdout: SplitParser { onRead: d => checkProc.buf += root.clean(d) + "\n" }
        stderr: SplitParser { onRead: d => checkProc.buf += root.clean(d) + "\n" }
        onExited: (code, status) => {
            root.parseCheck(buf, code);
            root.checking = false;
        }
    }
    FileView {
        id: stateWatch
        path: root.dataDir + "/state.env"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            var m = /^installed_version=(.*)$/m.exec(text());
            if (m && m[1]) root.installedVer = m[1];
        }
    }
    Component.onCompleted: { console.log("[macinstaller] build", build); glassProc.running = true; runPlan(); runQuietCheck(); }

    // ───────────── reusable pieces (named like the ones in the shell's Settings) ─────────────
    component T: Text {
        property bool semi: false
        color: root.pal.text
        font.family: root.fw(semi ? Font.DemiBold : Font.Normal)
        font.pixelSize: 13
    }

    // rounded, inset group box
    component SCard: Rectangle {
        id: card
        default property alias content: col.data
        width: parent ? parent.width : 0
        height: col.implicitHeight
        radius: 10
        color: root.pal.card
        border.width: 1
        border.color: root.pal.cardBorder
        Column { id: col; width: parent.width }
    }

    // one row inside a card: title (+ subtitle) on the left, control on the right
    component SRow: Item {
        id: r
        property string title: ""
        property string subtitle: ""
        default property alias control: slot.data
        width: parent ? parent.width : 0
        height: Math.max(44, textCol.height + 22, slot.height + 20)
        Rectangle { visible: r.y > 0.5; x: 14; width: parent.width - 14; height: 1; color: root.pal.sep }
        Column {
            id: textCol
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, r.width - 14 - slot.width - 28)
            spacing: 2
            T { width: parent.width; text: r.title; elide: Text.ElideRight }
            T { visible: r.subtitle !== ""; width: parent.width; text: r.subtitle; wrapMode: Text.WordWrap; color: root.pal.text2; font.pixelSize: 12 }
        }
        Item {
            id: slot
            anchors.right: parent.right; anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width; height: childrenRect.height
        }
    }

    // section header / footnote
    component SLabel: Text {
        property bool header: false
        width: parent ? parent.width : 0
        leftPadding: 4
        topPadding: header ? 8 : 0
        wrapMode: Text.WordWrap
        color: root.pal.text2
        font.family: root.fw(header ? Font.DemiBold : Font.Normal)
        font.pixelSize: 12
        font.weight: header ? Font.DemiBold : Font.Normal
    }

    // the Settings toggle (capsule knob, draggable); glass off: no shader is needed here
    component SSwitch: GlassSwitch {
        accentColor: "#30D158"
        offColor: root.pal.switchOff
        knobColor: root.pal.dark ? "#DCDDDA" : "white"
        dark: root.pal.dark
        baseColor: root.pal.dark ? "#2B2B2D" : "#FFFFFF"
        glass: root.glassOk
        shaderUrl: root.glassShaderUrl
        glassLiquid: root.glassLiquid
        glassRim: root.glassRim
        glassGrain: root.glassGrain
        glassTint: root.glassOpacity
        borderTint: root.glassBorder
        onGlassFailed: root.glassOk = false
    }

    component SSegmented: GlassSegmented {
        segWidth: 88
        dark: root.pal.dark
        textColor: root.pal.text
        fontFamily: root.fam
        fontSize: 12
        trackColor: root.pal.ctrl
        pillColor: root.pal.ctrlSel
        baseColor: root.pal.dark ? "#2B2B2D" : "#FFFFFF"
        glass: root.glassOk
        shaderUrl: root.glassShaderUrl
        glassLiquid: root.glassLiquid
        glassRim: root.glassRim
        glassGrain: root.glassGrain
        glassTint: root.glassOpacity
        borderTint: root.glassBorder
        onGlassFailed: root.glassOk = false
    }

    // macOS push button; `main` is the blue default button
    component SButton: Rectangle {
        id: b
        property string text: ""
        property bool main: false
        property bool destructive: false
        signal clicked()
        width: lbl.implicitWidth + 26
        height: 24
        radius: 10
        opacity: enabled ? 1 : 0.45
        color: main ? (ma.pressed ? Qt.darker(root.accent, 1.18) : root.accent)
                    : (ma.pressed ? root.pal.buttonPressed : root.pal.button)
        border.width: main ? 0 : 1
        border.color: root.pal.buttonBorder
        Text {
            id: lbl
            anchors.centerIn: parent
            text: b.text
            color: b.main ? "white" : (b.destructive ? root.pal.danger : root.pal.text)
            font.family: root.fw(b.main ? Font.DemiBold : Font.Normal)
            font.pixelSize: 13
        }
        MouseArea { id: ma; anchors.fill: parent; enabled: b.enabled; onClicked: b.clicked() }
    }

    // coloured rounded-square sidebar icon
    component STile: Rectangle {
        id: tl
        property string glyph: ""
        property color c1: "#3D9BFF"
        property color c2: "#0A6CFF"
        width: 24; height: 24; radius: 6
        gradient: Gradient {
            GradientStop { position: 0.0; color: tl.c1 }
            GradientStop { position: 1.0; color: tl.c2 }
        }
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.14)
        Text { anchors.centerIn: parent; text: tl.glyph; color: "white"; font.pixelSize: 14; font.bold: true }
    }

    // the output of whatever is running: lines coloured the way the terminal installer prints them
    component LogCard: Rectangle {
        id: lc
        property int viewHeight: 230
        width: parent ? parent.width : 0
        height: viewHeight
        radius: 10
        color: root.pal.logBg
        border.width: 1
        border.color: root.pal.cardBorder
        clip: true
        T { visible: root.logM.count === 0; anchors.centerIn: parent; text: "Output appears here"; color: root.pal.text3; font.pixelSize: 12 }
        ListView {
            id: lv
            anchors.fill: parent; anchors.margins: 10
            model: root.logM
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            onCountChanged: positionViewAtEnd()
            delegate: Text {
                required property string t
                required property string k
                width: lv.width
                text: t
                wrapMode: Text.WrapAnywhere
                font.family: "monospace"
                font.pixelSize: 11
                font.weight: k === "step" ? Font.Bold : Font.Normal
                color: k === "ok" ? root.pal.good : k === "warn" ? root.pal.warn
                     : k === "step" ? root.pal.text : k === "dim" ? root.pal.text2 : root.pal.text2
            }
        }
    }

    // an indeterminate bar while something runs (the shell's Installer uses the same one)
    component ProgressBar: Rectangle {
        id: track
        property bool running: false
        width: parent ? parent.width : 0; height: 6; radius: 3
        color: root.pal.ctrl
        clip: true
        visible: running
        Rectangle {
            height: parent.height; radius: 3
            width: track.width * 0.3
            color: root.accent
            SequentialAnimation on x {
                running: track.running; loops: Animation.Infinite
                NumberAnimation { from: -track.width * 0.3; to: track.width; duration: 1300; easing.type: Easing.InOutQuad }
            }
        }
    }

    // ═════════════ THE WINDOW ═════════════
    Window {
        id: win
        title: root.windowTitle
        // fixed size: it cannot be resized
        width: 820; height: 660
        minimumWidth: 820; maximumWidth: 820
        minimumHeight: 660; maximumHeight: 660
        visible: true
        color: "transparent"
        flags: Qt.Window | Qt.FramelessWindowHint
        onClosing: Qt.quit()

        // sidebar sections: a gap is drawn between them
        readonly property var panes: [
            { id: "install",   sec: 1, name: "Install",      glyph: "↓", c1: "#3D9BFF", c2: "#0A6CFF", keys: "install shell maclock options channel release main autostart keybinds glass low power" },
            { id: "deps",      sec: 1, name: "Dependencies", glyph: "≡", c1: "#FFB340", c2: "#FF9500", keys: "packages pacman aur missing libraries fonts quickshell hyprland terminal" },
            { id: "updates",   sec: 2, name: "Updates",      glyph: "↻", c1: "#8E8E93", c2: "#636366", keys: "update check version latest rollback roll back" },
            { id: "doctor",    sec: 2, name: "Doctor",       glyph: "+", c1: "#4CD964", c2: "#28A745", keys: "diagnose problems fix check log environment services shaders" },
            { id: "tools",     sec: 3, name: "Tools",        glyph: "⚙", c1: "#8E8E93", c2: "#636366", keys: "start stop restart lock screen test bind help environment env config backups folder low power" },
            { id: "uninstall", sec: 4, name: "Uninstall",    glyph: "✕", c1: "#FF5E57", c2: "#E8342A", keys: "remove delete uninstall" },
            { id: "about",     sec: 4, name: "About",        glyph: "i", c1: "#A7A7AD", c2: "#7C7C82", keys: "version project website github" }
        ]
        property int cur: 0
        property var backStack: []
        property var fwdStack: []
        property string query: ""
        readonly property var filtered: {
            var qy = query.trim().toLowerCase(), out = [];
            for (var i = 0; i < panes.length; i++) {
                var hay = (panes[i].name + " " + panes[i].keys).toLowerCase();
                if (qy === "" || hay.indexOf(qy) >= 0) out.push(i);
            }
            return out;
        }
        function go(i) { if (i === cur) return; backStack = backStack.concat([cur]); fwdStack = []; cur = i; root.confirmUninstall = false; }
        function back() { if (backStack.length === 0) return; var b = backStack.slice(); var p = b.pop(); fwdStack = fwdStack.concat([cur]); backStack = b; cur = p; }
        function forward() { if (fwdStack.length === 0) return; var f = fwdStack.slice(); var p = f.pop(); backStack = backStack.concat([cur]); fwdStack = f; cur = p; }
        onCurChanged: flick.contentY = 0

        Shortcut { sequences: ["Escape", "Ctrl+W"]; onActivated: { if (root.confirmUninstall) root.confirmUninstall = false; else Qt.quit(); } }

        // floats and centres itself, with no Hyprland border (the window draws its own edge)
        property int floatTries: 0
        onVisibleChanged: if (visible) { floatTries = 0; floatTimer.restart(); }
        Timer {
            id: floatTimer
            interval: 60
            repeat: true
            onTriggered: {
                var sel = 'window = "title:^(' + win.title + ')$"';
                Hyprland.dispatch('hl.dsp.window.float({ action = "enable", ' + sel + ' })');
                Hyprland.dispatch('hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", ' + sel + ' })');
                Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "border_size", value = "0", ' + sel + ' })');
                Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "rounding", value = "' + frame.radius + '", ' + sel + ' })');
                if (win.floatTries >= 2) {
                    Hyprland.dispatch('hl.dsp.window.resize({ x = ' + win.width + ', y = ' + win.height + ', "exact", ' + sel + ' })');
                    Hyprland.dispatch('hl.dsp.window.center({ ' + sel + ' })');
                }
                if (++win.floatTries >= 12) stop();
            }
        }

        // ── frame ──
        Rectangle {
            id: frame
            anchors.fill: parent
            radius: 12
            color: "transparent"
            border.width: 1
            border.color: root.pal.edgeOuter

            // inner highlight: with the outer line this is the two-tone edge macOS windows have
            Rectangle {
                anchors.fill: parent; anchors.margins: 1
                radius: frame.radius - 1
                color: "transparent"
                border.width: 1; border.color: root.pal.edgeInner
                z: 900
            }

            // Backdrop for the < > pill: the installer window itself (page colour, the sidebar edge and the page scrolling under the
            // toolbar), grabbed as one picture. The pill refracts this, never the wallpaper.
            Item {
                id: pillBack
                z: -100
                readonly property real m: 64
                x: header.x + navPill.x - m; y: header.y + navPill.y - m
                width: navPill.width + 2 * m; height: navPill.height + 2 * m
                Rectangle { anchors.fill: parent; color: root.pal.contentSolid }
                Rectangle { x: 0; y: 0; width: Math.max(0, sidebar.x + sidebar.width - pillBack.x); height: parent.height; color: root.pal.sidebar }
                Rectangle { x: Math.max(0, sidebar.x + sidebar.width - pillBack.x); y: 0; width: 1; height: parent.height; color: root.pal.sep }
                ShaderEffectSource {
                    x: flick.x - pillBack.x; y: flick.y - pillBack.y
                    width: Math.max(1, parent.width - x); height: Math.max(1, parent.height - y)
                    sourceItem: flick
                    sourceRect: Qt.rect(0, 0, width, height)
                    live: true
                }
            }
            ShaderEffectSource { id: pillSes; sourceItem: pillBack; hideSource: true; live: true; mipmap: true; visible: false }

            // the uninstall confirmation: modal, like the "New update" sheet in Settings
            Item {
                anchors.fill: parent
                z: 1000
                visible: root.confirmUninstall
                MouseArea { anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.AllButtons }
                Rectangle { anchors.fill: parent; radius: frame.radius; color: Qt.rgba(0, 0, 0, root.pal.dark ? 0.45 : 0.25) }
                Rectangle {
                    anchors.centerIn: parent
                    width: 320; height: 176
                    radius: 14
                    color: root.pal.contentSolid
                    border.width: 1; border.color: root.pal.buttonBorder
                    T { x: 0; y: 26; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "Uninstall MacShell?"; semi: true; font.pixelSize: 17 }
                    T {
                        x: 22; y: 60; width: parent.width - 44
                        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                        text: "MacShell and MacLock move to the backups folder. Your settings are kept."
                        color: root.pal.text2; font.pixelSize: 13
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 20
                        spacing: 10
                        SButton { text: "Cancel"; onClicked: root.confirmUninstall = false }
                        SButton { text: "Uninstall"; destructive: true; onClicked: { root.confirmUninstall = false; root.runMain("uninstall", root.sh(["--uninstall", "-y"])); } }
                    }
                }
            }

            // opaque page area: from the sidebar's right edge to the window edge
            Rectangle {
                x: sidebar.x + sidebar.width; y: 1
                width: parent.width - x - 1; height: parent.height - 2
                radius: 11
                color: root.pal.contentSolid
                Rectangle { anchors.left: parent.left; width: 12; height: parent.height; color: parent.color }
            }

            // drag the window by its top strip
            Item {
                z: 3
                width: parent.width; height: 52
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
            }

            // ───────── sidebar ─────────
            Rectangle {
                id: sidebar
                z: 4
                x: 1; y: 1
                width: 232
                height: parent.height - 2
                radius: 11
                color: "transparent"
                // translucent fill drawn as ONE layer so the rounded body and the square right edge don't add up to a darker band
                Item {
                    anchors.fill: parent
                    z: -1
                    layer.enabled: true
                    opacity: root.pal.sidebarGlass.a
                    Rectangle { anchors.fill: parent; radius: sidebar.radius; color: Qt.rgba(root.pal.sidebarGlass.r, root.pal.sidebarGlass.g, root.pal.sidebarGlass.b, 1) }
                    Rectangle { anchors.right: parent.right; width: 14; height: parent.height; color: Qt.rgba(root.pal.sidebarGlass.r, root.pal.sidebarGlass.g, root.pal.sidebarGlass.b, 1) }
                }
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: root.pal.sep }

                // traffic lights: close · minimise · full screen, with the shell's own glyphs
                Item {
                    id: lights
                    x: 17; y: 14
                    width: 58; height: 14
                    Row {
                        scale: 0.93; transformOrigin: Item.TopLeft
                        spacing: 8
                        Repeater {
                            model: [{ c: "#FF5F57", g: "×", on: true }, { c: "#FEBC2E", g: "−", on: true }, { c: "#28C840", g: "↗", on: false }]
                            delegate: Rectangle {
                                required property var modelData
                                width: 14; height: 14; radius: 7
                                readonly property bool lit: modelData.on && (win.active || lightsMa.containsMouse)
                                color: lit ? modelData.c : root.pal.lightOff
                                Behavior on color { ColorAnimation { duration: 220 } }
                                border.width: 1
                                border.color: lit ? root.pal.lightBorder(true, modelData.c) : "transparent"
                                TLGlyph { anchors.fill: parent; kind: parent.modelData.g; opacity: (lightsMa.containsMouse && parent.modelData.on) ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 140 } } }
                            }
                        }
                    }
                    MouseArea {
                        id: lightsMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: mouse => {
                            if (mouse.x < 22) Qt.quit();
                            else if (mouse.x < 44) root.shellDetached("hyprctl dispatch movetoworkspacesilent special:installer >/dev/null 2>&1");
                            // full screen is greyed out: the window has a fixed size
                        }
                    }
                }

                // search field
                Rectangle {
                    id: search
                    x: 12; y: 50
                    width: parent.width - 24; height: 28; radius: 7
                    color: root.pal.field
                    Rectangle {
                        anchors.fill: parent; anchors.margins: -2; radius: 9
                        color: "transparent"
                        border.width: 3
                        border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.5)
                        visible: searchInput.activeFocus
                    }
                    Item {
                        x: 9; anchors.verticalCenter: parent.verticalCenter
                        width: 14; height: 14
                        Rectangle { width: 9; height: 9; radius: 4.5; color: "transparent"; border.width: 2; border.color: root.pal.text3 }
                        Rectangle { x: 8; y: 9; width: 5; height: 1.6; radius: 0.8; color: root.pal.text3; rotation: 45; transformOrigin: Item.Left }
                    }
                    TextInput {
                        id: searchInput
                        x: 30; width: parent.width - 54
                        anchors.verticalCenter: parent.verticalCenter
                        clip: true; selectByMouse: true
                        color: root.pal.text; selectionColor: root.accent
                        font.family: root.fw(Font.Normal); font.pixelSize: 13
                        onTextChanged: win.query = text
                    }
                    T { x: 30; anchors.verticalCenter: parent.verticalCenter; visible: searchInput.text === ""; text: I18n.tr("Search"); color: root.pal.text3 }
                    Rectangle {
                        visible: searchInput.text !== ""
                        anchors.right: parent.right; anchors.rightMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14; height: 14; radius: 7
                        color: root.pal.text3
                        Text { anchors.centerIn: parent; anchors.verticalCenterOffset: -0.5; text: "×"; color: root.pal.sidebar; font.pixelSize: 12; font.bold: true }
                        MouseArea { anchors.fill: parent; onClicked: searchInput.text = "" }
                    }
                }

                // the app card (macOS: your name and picture) → Install
                Rectangle {
                    id: acct
                    x: 10; y: 90; width: parent.width - 20; height: 52; radius: 10
                    visible: win.query === ""
                    readonly property bool sel: win.cur === 0
                    color: sel ? (win.active ? root.accent : root.pal.selInactive) : (acctMa.containsMouse ? root.pal.hover : "transparent")
                    Image {
                        x: 6; anchors.verticalCenter: parent.verticalCenter
                        width: 38; height: 38
                        source: Qt.resolvedUrl("assets/macshell-logo.png")
                        sourceSize: Qt.size(96, 96)
                        fillMode: Image.PreserveAspectFit
                        smooth: true; mipmap: true
                    }
                    Column {
                        x: 52; anchors.verticalCenter: parent.verticalCenter
                        T { text: "MacShell"; semi: true; color: acct.sel && win.active ? "white" : root.pal.text }
                        T {
                            text: root.shortInst !== "" ? "Installed · " + root.shortInst : "Not installed"
                            color: acct.sel && win.active ? Qt.rgba(1, 1, 1, 0.8) : root.pal.text2
                            font.pixelSize: 11
                        }
                    }
                    MouseArea { id: acctMa; anchors.fill: parent; hoverEnabled: true; onClicked: win.go(0) }
                }

                // pane list
                Flickable {
                    id: navFlick
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
                            model: win.filtered
                            delegate: Item {
                                id: navItem
                                required property int modelData
                                required property int index
                                readonly property var p: win.panes[modelData]
                                readonly property bool gap: index > 0 && win.panes[win.filtered[index - 1]].sec !== win.panes[modelData].sec
                                readonly property bool sel: win.cur === modelData
                                width: parent.width
                                height: 34 + (gap ? 12 : 0)
                                Rectangle {
                                    y: navItem.gap ? 12 : 0
                                    width: parent.width; height: 34; radius: 8
                                    color: navItem.sel ? (win.active ? root.accent : root.pal.selInactive)
                                                       : (navMa.containsMouse ? root.pal.hover : "transparent")
                                    STile { x: 8; anchors.verticalCenter: parent.verticalCenter; glyph: navItem.p.glyph; c1: navItem.p.c1; c2: navItem.p.c2 }
                                    T {
                                        x: 42; anchors.verticalCenter: parent.verticalCenter
                                        text: I18n.tr(navItem.p.name)
                                        color: (navItem.sel && win.active) ? "white" : root.pal.text
                                        font.pixelSize: 14
                                    }
                                    // badges: an update is waiting / packages are missing
                                    Rectangle {
                                        readonly property string txt: navItem.p.id === "updates" && root.updateState === "available" ? "1"
                                                                    : navItem.p.id === "deps" && root.missing > 0 ? String(root.missing) : ""
                                        visible: txt !== ""
                                        anchors.right: parent.right; anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.max(18, bdg.implicitWidth + 10); height: 18; radius: 9
                                        color: "#FF3B30"
                                        Text { id: bdg; anchors.centerIn: parent; text: parent.txt; color: "white"; font.pixelSize: 11; font.bold: true }
                                    }
                                    MouseArea { id: navMa; anchors.fill: parent; hoverEnabled: true; onClicked: win.go(navItem.modelData) }
                                }
                            }
                        }
                        T { visible: win.filtered.length === 0; width: parent.width; topPadding: 14; horizontalAlignment: Text.AlignHCenter; text: I18n.tr("No Results"); color: root.pal.text2; font.pixelSize: 12 }
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
                GlassSlab {          // Liquid Glass pill behind the back / forward buttons (same glass as Settings)
                    id: navPill
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 66; height: 36
                    cornerR: 18
                    glass: root.glassOk
                    shaderUrl: root.glassShaderUrl
                    dark: root.pal.dark
                    // refracts the installer window itself (pillBack below), never the wallpaper
                    src: pillSes
                    srcSize: Qt.size(pillBack.width, pillBack.height)
                    origin: Qt.point(pillBack.m, pillBack.m)
                    baseColor: root.pal.dark ? "#3C3C40" : "#FBFBFD"
                    blurPx: 6
                    thickness: 14; strengthMul: 0.6
                    liquid: root.glassLiquid
                    rim: root.glassRim * 0.25
                    grain: root.glassGrain
                    tint: root.glassOpacity
                    shadowAmt: 0; flatInner: 1
                    onFailed: root.glassOk = false
                    CornerBorder {
                        z: 2; anchors.fill: parent
                        cornerR: 18; dark: root.pal.dark
                        tint: root.glassBorder
                        amount: 1; lineW: 0.8
                    }
                }
                Row {
                    x: 14; anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Repeater {
                        model: [{ g: "‹", dir: -1 }, { g: "›", dir: 1 }]
                        delegate: Item {
                            id: navBtn
                            required property var modelData
                            readonly property bool ok: modelData.dir < 0 ? win.backStack.length > 0 : win.fwdStack.length > 0
                            width: 26; height: 28
                            Text {
                                anchors.centerIn: parent; anchors.verticalCenterOffset: -2
                                text: navBtn.modelData.g
                                font.family: root.fw(Font.Normal); font.pixelSize: 28
                                color: navBtn.ok ? root.pal.text : root.pal.text3
                                opacity: navBtn.ok ? 1 : 0.5
                                scale: (navBtn.ok && nbMa.pressed) ? 0.86 : 1
                                Behavior on scale { NumberAnimation { duration: 230; easing.type: Easing.OutBack; easing.overshoot: 3.2 } }
                            }
                            MouseArea {
                                id: nbMa
                                anchors.fill: parent; hoverEnabled: true
                                enabled: navBtn.ok
                                onClicked: { if (navBtn.modelData.dir < 0) win.back(); else win.forward(); }
                            }
                        }
                    }
                }
                T { x: 90; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr(win.panes[win.cur].name); semi: true; font.pixelSize: 15 }
            }

            // ───────── scrolling content ─────────
            Flickable {
                id: flick
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
                    x: 22; y: 58
                    width: flick.width - 44
                    sourceComponent: ({
                        install: paneInstall, deps: paneDeps, updates: paneUpdates, doctor: paneDoctor,
                        tools: paneTools, uninstall: paneUninstall, about: paneAbout
                    })[win.panes[win.cur].id]
                    onLoaded: fadeIn.restart()
                }
            }
            // Tahoe-style scroll-under blur: what slides up under the toolbar is blurred, and the blur melts away below it
            // (the shell's own FeatherBlur). It re-draws the page; the page itself keeps scrolling and clicking as before.
            FeatherBlur {
                z: 1
                x: flick.x; y: flick.y; width: flick.width; height: flick.height
                target: root.featherBlur ? flick : null
                topHold: 36                  // height of the fully blurred band (was 52)
                topDepth: 22                 // short, soft fade-out (was 64)
                radiusScale: 1.4             // a bit more blur
                blurMax: 32
                topAmount: Math.max(0, Math.min(1, flick.contentY / 18))
            }
            NumberAnimation { id: fadeIn; target: paneLoader; property: "opacity"; from: 0; to: 1; duration: 160 }
            Rectangle {   // thin overlay scrollbar
                visible: flick.contentHeight > flick.height + 1
                x: frame.width - 8
                y: 52 + flick.visibleArea.yPosition * (flick.height - 52)
                width: 4
                height: Math.max(28, flick.visibleArea.heightRatio * (flick.height - 52))
                radius: 2
                color: root.pal.text3
                opacity: flick.moving ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 300 } }
            }
        }

        // ═════════════ PAGES ═════════════

        // ── Install ──
        Component {
            id: paneInstall
            Column {
                spacing: 10
                SLabel { header: true; text: "Status" }
                SCard {
                    SRow {
                        title: "Dependencies"
                        subtitle: root.depsText
                        Row {
                            spacing: 8
                            SButton { visible: root.missing > 0 || root.needsUpdate; text: root.needsUpdate ? "Update system…" : "Install…"; onClicked: root.needsUpdate ? root.openTerminal("sudo pacman -Syu") : root.openTerminal("bash " + root.q(root.script) + " --deps-only") }
                            SButton { text: "Re-check"; enabled: !root.planBusy; onClicked: root.runPlan() }
                        }
                    }
                    SRow {
                        title: "MacShell"
                        subtitle: root.shortInst !== "" ? "Installed · " + root.shortInst : "Not installed yet"
                        SButton { text: "Check for Updates"; enabled: !root.busy && !root.checking; onClicked: root.runQuietCheck() }
                    }
                }

                SLabel { header: true; text: "Options" }
                SCard {
                    SRow {
                        title: "Version"
                        subtitle: root.optMain ? "Always the newest commit" : "The latest release"
                        SSegmented {
                            model: ["Release", "Main"]
                            current: root.optMain ? 1 : 0
                            onPicked: i => root.optMain = (i === 1)
                        }
                    }
                    SRow {
                        title: "MacLock"
                        subtitle: "The lock screen"
                        SSwitch { checked: root.optLock; onToggled: v => root.optLock = v }
                    }
                    SRow {
                        title: "Hyprland autostart and keybinds"
                        subtitle: "Adds the MacShell block to your Hyprland config"
                        SSwitch { checked: root.optAutostart; onToggled: v => root.optAutostart = v }
                    }
                    SRow {
                        title: "Liquid Glass layer rules"
                        subtitle: "Blur behind the Dock and menus"
                        SSwitch { checked: root.optRules; onToggled: v => root.optRules = v }
                    }
                    SRow {
                        title: "Low-power mode"
                        subtitle: "For older computers: no live window capture or magnification"
                        SSwitch { checked: root.optLow; onToggled: v => root.optLow = v }
                    }
                }
                SLabel { text: "Installing stops conflicting bars and notification daemons (waybar, dunst, mako…). Your settings are never touched." }

                Row {
                    spacing: 12
                    SButton {
                        main: true
                        text: root.busy && root.runKind === "install" ? "Installing…" : (root.shortInst !== "" ? "Reinstall MacShell" : "Install MacShell")
                        enabled: !root.busy
                        onClicked: root.runMain("install", root.sh(root.installArgs()))
                    }
                    T { anchors.verticalCenter: parent.verticalCenter; text: root.notice; color: root.pal.text2; font.pixelSize: 12 }
                }
                ProgressBar { running: root.busy && root.runKind === "install" }
                LogCard { viewHeight: 220 }
            }
        }

        // ── Dependencies ──
        Component {
            id: paneDeps
            Column {
                spacing: 10
                SCard {
                    SRow {
                        title: "Status"
                        subtitle: root.depsText
                        Row {
                            spacing: 8
                            SButton { text: "Re-check"; enabled: !root.planBusy; onClicked: root.runPlan() }
                            SButton {
                                main: true
                                text: root.needsUpdate ? "Update system…" : "Install in Terminal…"
                                onClicked: root.needsUpdate ? root.openTerminal("sudo pacman -Syu") : root.openTerminal("bash " + root.q(root.script) + " --deps-only")
                            }
                        }
                    }
                }
                SLabel { text: "Nothing you already have is replaced and nothing is upgraded on its own. Installing asks for your password in a terminal window; press Re-check afterwards." }
                Repeater {
                    model: root.groups.concat(root.otherPkgs.length > 0 ? [{ name: "Other", about: "Other packages in the plan", pkgs: root.otherPkgs }] : [])
                    delegate: SCard {
                        id: gcard
                        required property var modelData
                        Item {
                            width: parent.width
                            height: gcol.implicitHeight + 24
                            Column {
                                id: gcol
                                x: 14; y: 12; width: parent.width - 28
                                spacing: 6
                                T { text: I18n.tr(gcard.modelData.name); semi: true }
                                T { width: parent.width; wrapMode: Text.WordWrap; text: gcard.modelData.about; color: root.pal.text3; font.pixelSize: 11 }
                                Flow {
                                    width: parent.width
                                    spacing: 6
                                    Repeater {
                                        model: gcard.modelData.pkgs
                                        delegate: Rectangle {
                                            required property string modelData
                                            readonly property string st: root.stateOf(modelData)
                                            height: 22; width: pkgT.implicitWidth + 26; radius: 11
                                            color: st === "installed" ? Qt.rgba(0.19, 0.82, 0.35, 0.16)
                                                 : st === "install" ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                                                 : (st === "skipped" || st === "aur") ? Qt.rgba(1, 0.62, 0.04, 0.18) : root.pal.ctrl
                                            T {
                                                id: pkgT
                                                anchors.centerIn: parent
                                                font.pixelSize: 11
                                                text: (parent.st === "installed" ? "✓ " : parent.st === "install" ? "+ " : parent.st === "skipped" ? "– " : parent.st === "aur" ? "AUR " : "") + parent.modelData
                                            }
                                            MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true }
                                            Rectangle {
                                                readonly property string tip: parent.st === "skipped" ? "Left alone: " + root.reasonOf(parent.modelData)
                                                                            : parent.st === "aur" ? "From the AUR: install it with paru or yay" : ""
                                                visible: pma.containsMouse && tip !== ""
                                                y: -height - 6; x: (parent.width - width) / 2; z: 10
                                                width: ttT.implicitWidth + 16; height: 22; radius: 6
                                                color: root.pal.dark ? "#3A3A3C" : "#1D1D1F"
                                                Text { id: ttT; anchors.centerIn: parent; text: parent.tip; color: "white"; font.pixelSize: 11 }
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

        // ── Updates ──
        Component {
            id: paneUpdates
            Column {
                spacing: 10
                SCard {
                    SRow { title: "Installed"; subtitle: root.shortInst !== "" ? root.shortInst : "MacShell is not installed" }
                    SRow { title: "Latest"; subtitle: root.shortLatest !== "" ? root.shortLatest : "Not checked yet" }
                    SRow {
                        title: root.updateText
                        subtitle: "Updates MacShell and MacLock together and keeps your settings. The old version is backed up first (the last 3 are kept)."
                        Row {
                            spacing: 8
                            SButton { text: "Check Now"; enabled: !root.busy && !root.checking; onClicked: root.runMain("check", root.sh(["--check"])) }
                            SButton { main: true; text: "Update"; enabled: !root.busy && root.shortInst !== ""; onClicked: root.runMain("update", root.sh(["--update"])) }
                        }
                    }
                }
                SCard {
                    SRow {
                        title: "Roll Back"
                        subtitle: "Go back to the version that was installed before the last update"
                        SButton { text: "Roll Back"; destructive: true; enabled: !root.busy; onClicked: root.runMain("rollback", ["sh", root.binDir + "/macshell-update", "rollback"]) }
                    }
                }
                ProgressBar { running: root.busy && (root.runKind === "update" || root.runKind === "rollback" || root.runKind === "check") }
                T { visible: root.notice !== "" && (root.runKind === "update" || root.runKind === "rollback"); leftPadding: 4; text: root.notice; color: root.pal.text2; font.pixelSize: 12 }
                LogCard { viewHeight: 200 }
            }
        }

        // ── Doctor ──
        Component {
            id: paneDoctor
            Column {
                spacing: 10
                SCard {
                    SRow {
                        title: "Check the setup"
                        subtitle: "Looks at the environment, QML modules, services, wallpaper, shaders, Hyprland and the last start log, and explains what is wrong."
                        Row {
                            spacing: 8
                            SButton { text: "Open Start Log"; onClicked: root.openPath(root.stateDir + "/MacShell.log") }
                            SButton { main: true; text: root.busy && root.runKind === "doctor" ? "Checking…" : "Run Doctor"; enabled: !root.busy; onClicked: root.runMain("doctor", root.sh(["--doctor"])) }
                        }
                    }
                }
                ProgressBar { running: root.busy && root.runKind === "doctor" }
                LogCard { viewHeight: 380 }
            }
        }

        // ── Tools ──
        Component {
            id: paneTools
            Column {
                spacing: 10
                SLabel { header: true; text: "MacShell" }
                SCard {
                    SRow { title: "Start"; subtitle: "Runs the shell in your Hyprland session"; SButton { main: true; text: "Start"; onClicked: root.startShell() } }
                    SRow { title: "Restart"; subtitle: "Stops the shell and starts it again"; SButton { text: "Restart"; onClicked: root.restartShell() } }
                    SRow { title: "Stop"; subtitle: "Quits the running shell"; SButton { text: "Stop"; destructive: true; onClicked: root.stopShell() } }
                    SRow { title: "Lock Screen"; subtitle: "Try MacLock"; SButton { text: "Lock Now"; onClicked: root.shellDetached("sh " + root.q(root.home + "/.config/quickshell/MacLock/lock-via-ipc.sh")) } }
                }
                SLabel { header: true; text: "Inside the shell" }
                SCard {
                    SRow { title: "System Settings"; SButton { text: "Open"; onClicked: root.shellDetached("qs -c MacShell ipc call settings toggle") } }
                    SRow { title: "About This Linux"; SButton { text: "Open"; onClicked: root.shellDetached("qs -c MacShell ipc call about open") } }
                    SRow { title: "Install Dependencies"; subtitle: "The shell's own Installer window"; SButton { text: "Open"; onClicked: root.shellDetached("qs -c MacShell ipc call deps open") } }
                }
                SLabel { header: true; text: "Configuration" }
                SCard {
                    SRow { title: "Bind Help"; subtitle: "How the keybinds are written in the Hyprland config"; SButton { text: "Open"; onClicked: root.openPath(root.bindHelpUrl) } }
                    SRow { title: "Environment File"; subtitle: "~/.config/macshell/env"; SButton { text: "Edit"; onClicked: root.shellDetached("mkdir -p ~/.config/macshell; touch ~/.config/macshell/env; xdg-open ~/.config/macshell/env") } }
                    SRow { title: "Hyprland Config Folder"; SButton { text: "Open"; onClicked: root.openPath(root.home + "/.config/hypr") } }
                    SRow { title: "Backups"; subtitle: "Where updates and uninstall keep older versions"; SButton { text: "Open"; onClicked: root.openPath(root.dataDir + "/backups") } }
                    SRow {
                        title: "Low-Power Settings"
                        subtitle: "Reinstalls this copy with the settings for older computers"
                        SButton { text: "Apply"; enabled: !root.busy; onClicked: root.runMain("install", root.sh(["-y", "--no-deps", "--no-start", "--no-services", "--low-power", "--local"])) }
                    }
                }
                ProgressBar { running: root.busy && root.runKind === "install" }
                LogCard { visible: root.logM.count > 0; viewHeight: 180 }
            }
        }

        // ── Uninstall ──
        Component {
            id: paneUninstall
            Column {
                spacing: 10
                SCard {
                    SRow {
                        title: "Uninstall MacShell"
                        subtitle: "Moves MacShell and MacLock to the backups folder and removes the update and start tools, the autostart block and the update timer."
                        SButton { text: "Uninstall…"; destructive: true; enabled: !root.busy; onClicked: root.confirmUninstall = true }
                    }
                }
                SLabel { text: "Your settings (~/.config/macbar, macdock, macshell, macwidgets) are kept, so installing again brings everything back." }
                ProgressBar { running: root.busy && root.runKind === "uninstall" }
                T { visible: root.notice !== "" && root.runKind === "uninstall"; leftPadding: 4; text: root.notice; color: root.pal.text2; font.pixelSize: 12 }
                LogCard { viewHeight: 240 }
            }
        }

        // ── About ──
        Component {
            id: paneAbout
            Column {
                spacing: 10
                SCard {
                    Item {
                        width: parent.width; height: 150
                        Image {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 16; width: 84; height: 84
                            source: Qt.resolvedUrl("assets/macshell-logo.png")
                            sourceSize: Qt.size(168, 168)
                            fillMode: Image.PreserveAspectFit
                            smooth: true; mipmap: true
                        }
                        T { y: 106; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "MacShell Installer"; semi: true; font.pixelSize: 18 }
                        T { y: 130; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: root.shortInst !== "" ? "Installed · " + root.shortInst : "Not installed"; color: root.pal.text2; font.pixelSize: 12 }
                    }
                }
                SCard {
                    SRow { title: "Build"; subtitle: root.build + " · Liquid Glass: " + (root.glassOk ? "on" : "failed, plain controls") + " · window " + win.width + "×" + win.height + " (fixed)" }
                    SRow { title: "Installer script"; subtitle: root.script }
                    SRow { title: "Project"; subtitle: root.projectUrl; SButton { text: "Open"; onClicked: root.openPath(root.projectUrl) } }
                    SRow { title: "Backups"; subtitle: root.dataDir + "/backups"; SButton { text: "Open"; onClicked: root.openPath(root.dataDir + "/backups") } }
                }
                SLabel { text: "This window drives install.sh: install, update, doctor and uninstall run the same code as the terminal installer." }
            }
        }
    }
}
