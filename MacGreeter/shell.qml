// MacGreeter: the MacShell login screen. It shows MacLock's lock screen (LockScreen.qml, the same file, copied here by
// `macshell-install --login-screen`) and logs in through greetd instead of unlocking a session.
//
//   greetd  ->  /usr/local/bin/macshell-greeter  ->  a tiny Hyprland  ->  qs -p <this folder>  ->  Greetd.launch(session)
//
//   MACGREETER_PREVIEW=1 qs -p <this folder>     try it as a window over your desktop (nothing is logged in; any password
//                                                 "works"; Ctrl+Shift+Q closes it, and it closes by itself after 90 s)
//   MACGREETER_STATE=<dir>                       where the data lives (default /var/lib/macshell-greeter)
//
// What it shows (name, picture, wallpaper, clock look, language) is copied for the greeter account by macshell-greeter-sync,
// because the greeter cannot read your home folder. Media, lyrics and notifications of the lock screen simply stay empty here.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Greetd

ShellRoot {
    id: root
    settings.watchFiles: false

    FontLoader { source: Qt.resolvedUrl("fonts/OpenRunde-Regular.otf") }
    FontLoader { source: Qt.resolvedUrl("fonts/OpenRunde-Semibold.otf") }

    readonly property bool preview: Quickshell.env("MACGREETER_PREVIEW") === "1"
    readonly property string stateRoot: Quickshell.env("MACGREETER_STATE") || "/var/lib/macshell-greeter"
    readonly property bool underGreetd: (Quickshell.env("GREETD_SOCK") || "") !== ""

    // ── what the greeter offers ──
    property var users: []                  // [{ user, name, avatar, wallpaper, use24h, language, clock }]
    property int userIdx: 0
    property var sessions: []               // [{ name, exec }]
    property int sessionIdx: 0
    readonly property var cu: users.length > 0 ? users[Math.min(userIdx, users.length - 1)] : null
    readonly property string loginUser: cu ? cu.user : ""

    function selectUser(i) {
        if (i === userIdx || gs.busy || gs.unlocking) return;
        if (root.underGreetd && !root.preview) Greetd.cancelSession();
        userIdx = i;
        gs.pass = ""; gs.message = ""; gs.engaged = false;
        applyLanguage();
    }
    function applyLanguage() {
        var lang = cu && cu.language ? String(cu.language) : "auto";
        Qt.uiLanguage = (lang === "auto" || lang === "null") ? "" : lang;
    }
    function cycleSession() {
        if (sessions.length > 1) sessionIdx = (sessionIdx + 1) % sessions.length;
    }
    function launchSession() {
        var s = sessions.length > 0 ? sessions[Math.min(sessionIdx, sessions.length - 1)] : { name: "Hyprland", exec: "Hyprland" };
        var cmd = String(s.exec).replace(/%[a-zA-Z%]/g, "").trim();
        // remember the choices for the next boot (detached: this process quits as the session starts)
        Quickshell.execDetached(["sh", "-c", "d=\"$1/state\"; printf %s \"$2\" > \"$d/last-user\"; printf %s \"$3\" > \"$d/last-session\"",
                                 "sh", stateRoot, loginUser, String(s.name)]);
        // greetd already runs this through "sh -c" (after sourcing the profile) with "exec" in front, so it must be a plain
        // command line, not wrapped in another sh -lc. Hyprland 0.53+ wants to be started through start-hyprland.
        cmd = cmd.replace(/^(\/usr\/bin\/)?Hyprland(\s|$)/, "start-hyprland$2");
        // the session's output goes to ~/.cache/macshell-session.log (the TTY is gone once the login screen quits)
        var inner = "mkdir -p \"$HOME/.cache\" 2>/dev/null; exec " + cmd + " >>\"$HOME/.cache/macshell-session.log\" 2>&1";
        Greetd.launch(["sh -c '" + inner.replace(/'/g, "'\\''") + "'"],
                      ["XDG_SESSION_TYPE=wayland", "XDG_CURRENT_DESKTOP=Hyprland", "XDG_SESSION_DESKTOP=Hyprland"], true);
    }

    // the monitor that has the pointer / focus gets the full layout, the others show the wallpaper and the clock
    property string primary: ""
    function pickPrimary() { if (primary === "" && Hyprland.focusedMonitor) primary = Hyprland.focusedMonitor.name; }
    Component.onCompleted: pickPrimary()
    Timer {
        interval: 500; running: true
        onTriggered: if (root.primary === "" && Quickshell.screens.length > 0) root.primary = Quickshell.screens[0].name
    }
    Connections { target: Hyprland; function onFocusedMonitorChanged() { root.pickPrimary(); } }

    // ── the state object LockScreen.qml expects (same names as MacLock's) ──
    QtObject {
        id: gs
        property var now: new Date()
        property string userName: root.cu ? (root.cu.name || root.cu.user) : ""
        property string avatar: root.cu && root.cu.avatar ? root.cu.avatar : ""
        property string wallpaper: root.cu && root.cu.wallpaper ? root.cu.wallpaper : ""
        property string wallpaperVideo: ""
        property bool use24h: !(root.cu && root.cu.use24h === false)
        property var clockCfg: root.cu && root.cu.clock ? root.cu.clock : ({})
        property int wifiLevel: -1
        property bool ethernet: false
        property string pass: ""
        property bool busy: false
        property int fails: 0
        property string message: ""
        property bool engaged: false
        property bool unlocking: false
        property string mediaSlot: "top"
        property bool capsLock: false
        property bool artBg: false
        property bool sounds: false
        property string npMode: ""
        function sound(name) { }
        function setMediaSlot(v) { }
        function checkCaps() { if (!capsProc.running) capsProc.running = true; }
        function poke() { engaged = true; idleTimer.restart(); }
        function submit() {
            if (busy || unlocking || pass.length === 0) return;
            message = "";
            if (root.preview) { busy = true; previewTimer.start(); return; }
            if (!root.underGreetd) { fail("Not started by greetd"); return; }
            if (root.loginUser === "") { fail("No user to log in"); return; }
            busy = true;
            Greetd.createSession(root.loginUser);
        }
        function fail(msg) { pass = ""; message = msg; fails++; msgTimer.restart(); }
        function unlock() { unlocking = true; unlockTimer.start(); }
    }
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: gs.now = new Date() }
    Timer { id: idleTimer; interval: 9000; onTriggered: if (gs.pass.length === 0 && !gs.busy) gs.engaged = false }
    Timer { id: msgTimer; interval: 3500; onTriggered: gs.message = "" }
    Timer { id: previewTimer; interval: 700; onTriggered: { gs.busy = false; gs.unlock(); } }
    // let the exit animation play, then start the session
    Timer {
        id: unlockTimer
        interval: 430
        onTriggered: { if (root.preview) Qt.quit(); else root.launchSession(); }
    }
    Timer { interval: (parseInt(Quickshell.env("MACGREETER_PREVIEW_SECONDS")) || 90) * 1000; running: root.preview; onTriggered: Qt.quit() }
    Timer { interval: 700; repeat: true; running: true; triggeredOnStart: true; onTriggered: gs.checkCaps() }

    // ── greetd ──
    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) Greetd.respond(gs.pass);
        }
        function onAuthFailure(message) {
            gs.busy = false;
            gs.fail("Incorrect password");
            Greetd.cancelSession();
        }
        function onReadyToLaunch() { gs.busy = false; gs.unlock(); }
    }

    // ── one-shot lookups ──
    Process {
        running: true
        command: ["sh", Quickshell.shellDir + "/list.sh", root.stateRoot]
        stdout: StdioCollector {
            onStreamFinished: {
                var o = {};
                try { o = JSON.parse(text.trim().split("\n").pop()); } catch (e) { o = {}; }
                var us = o.users || [], i;
                root.sessions = o.sessions || [];
                // the last user who logged in comes first
                for (i = 0; i < us.length; i++) if (us[i].user === o.lastUser) { us.unshift(us.splice(i, 1)[0]); break; }
                root.users = us;
                root.userIdx = 0;
                // the last session, else Hyprland, else the first one
                var pick = -1;
                for (i = 0; i < root.sessions.length; i++) if (root.sessions[i].name === o.lastSession) { pick = i; break; }
                if (pick < 0) for (i = 0; i < root.sessions.length; i++) if (/hyprland/i.test(root.sessions[i].exec + root.sessions[i].name)) { pick = i; break; }
                root.sessionIdx = Math.max(0, pick);
                root.applyLanguage();
            }
        }
    }
    Process {
        running: true
        command: ["sh", Quickshell.shellDir + "/net.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                var l = text.split("\n");
                var s = parseInt((l[0] || "-1").trim());
                gs.wifiLevel = isNaN(s) || s < 0 ? -1 : (s === 0 ? 0 : (s > 66 ? 3 : (s > 33 ? 2 : 1)));
                gs.ethernet = (l[1] || "").trim() === "eth";
            }
        }
    }
    Process {
        id: capsProc
        command: ["sh", "-c", "cat /sys/class/leds/*capslock/brightness 2>/dev/null | grep -q 1 && echo true || echo false"]
        stdout: StdioCollector { onStreamFinished: gs.capsLock = text.trim() === "true" }
    }

    // a small pill for the choices that sit along the bottom edge
    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool active: false
        property real u: 1
        signal clicked()
        implicitWidth: lbl.implicitWidth + 30 * u
        implicitHeight: 38 * u
        radius: height / 2
        color: cma.containsMouse ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(1, 1, 1, active ? 0.24 : 0.14)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, active ? 0.55 : 0.2)
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
            id: lbl
            anchors.centerIn: parent
            text: chip.label
            color: "white"; opacity: 0.94
            font.family: "Open Runde"; font.pixelSize: 15 * chip.u
        }
        MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            readonly property bool primary: root.primary === "" || modelData.name === root.primary
            readonly property real u: Math.max(0.6, height / 1200)
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: root.preview ? "transparent" : "#0b0b10"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "macshell-greeter"
            WlrLayershell.keyboardFocus: !primary ? WlrKeyboardFocus.None : (root.preview ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)

            Shortcut { sequence: "Ctrl+Shift+Q"; enabled: root.preview; onActivated: Qt.quit() }

            LockScreen {
                id: ls
                anchors.fill: parent
                st: gs
                isPrimary: win.primary
            }

            // users, session and power: along the bottom edge of the main screen
            Item {
                anchors.fill: parent
                z: 20
                visible: win.primary && !gs.unlocking
                opacity: ls.opacity

                Chip {
                    visible: root.sessions.length > 1
                    u: win.u
                    anchors { left: parent.left; bottom: parent.bottom; leftMargin: 32 * win.u; bottomMargin: 30 * win.u }
                    label: root.sessions.length > 0 ? root.sessions[Math.min(root.sessionIdx, root.sessions.length - 1)].name : ""
                    onClicked: { root.cycleSession(); ls.forceActiveFocus(); }
                }
                Row {
                    visible: root.users.length > 1
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 30 * win.u }
                    spacing: 10 * win.u
                    Repeater {
                        model: root.users
                        delegate: Chip {
                            required property var modelData
                            required property int index
                            u: win.u
                            label: modelData.name || modelData.user
                            active: index === root.userIdx
                            onClicked: { root.selectUser(index); ls.forceActiveFocus(); }
                        }
                    }
                }
                Row {
                    anchors { right: parent.right; bottom: parent.bottom; rightMargin: 32 * win.u; bottomMargin: 30 * win.u }
                    spacing: 10 * win.u
                    Chip { u: win.u; label: "Sleep";     onClicked: { if (!root.preview) Quickshell.execDetached(["systemctl", "suspend"]); } }
                    Chip { u: win.u; label: "Restart";   onClicked: { if (!root.preview) Quickshell.execDetached(["systemctl", "reboot"]); } }
                    Chip { u: win.u; label: "Shut Down"; onClicked: { if (!root.preview) Quickshell.execDetached(["systemctl", "poweroff"]); } }
                }
            }
        }
    }
}
