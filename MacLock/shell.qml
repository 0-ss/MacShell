// MacLock: a macOS 26/27-style lock screen for Quickshell, matching MacShell's Liquid Glass.
//
//   qs -c MacLock                         lock now (one-shot; started by hypridle via maclock.sh)
//   MACLOCK_DAEMON=1 qs -c MacLock        start unlocked for an IPC-triggered lock
//   MACLOCK_PREVIEW=1 qs -c MacLock       draw it as an overlay window instead of a real lock (for tweaking)
//
// Runs as its own process on purpose: a MacShell crash can never take the lock with it, and maclock.sh
// relaunches this one if it dies (Hyprland's misc:allow_session_lock_restore lets the new instance take over).
// Password check: PAM, /etc/pam.d/hyprlock (same stack hyprlock uses).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pam

ShellRoot {
    // the UI font ("Open Runde") ships with MacLock: registered first, so every Text below can use it
    FontLoader { id: uiFontLoader; source: Qt.resolvedUrl("fonts/OpenRunde-Regular.otf") }
    FontLoader { id: uiBoldFontLoader; source: Qt.resolvedUrl("fonts/OpenRunde-Semibold.otf") }

    // never hot-reload while holding the session lock: a half-edited config must not touch a live lock
    settings.watchFiles: false
    id: root
    readonly property bool preview: Quickshell.env("MACLOCK_PREVIEW") === "1"
    readonly property bool daemonMode: Quickshell.env("MACLOCK_DAEMON") === "1"
    // Default launch keeps the original behavior and locks immediately. In daemon mode, wait for IPC.
    property bool lockRequested: !daemonMode
    function requestLock() {
        if (!preview) lockRequested = true;
    }
    IpcHandler {
        target: "lockscreen"
        function state(): string {
            if (lock.wasSecure) return lock.secure ? "busy" : "stopping";
            return root.lockRequested ? "busy" : "ready";
        }
        function lock(): void { root.requestLock(); }
    }

    // the monitor that was focused when the lock started gets the full layout
    property string primary: ""
    function pickPrimary() {
        if (primary === "" && Hyprland.focusedMonitor) primary = Hyprland.focusedMonitor.name;
    }
    Component.onCompleted: pickPrimary()
    // Hyprland's state arrives a moment after startup; only fall back to the first screen if it never does
    Timer {
        interval: 400; running: true
        onTriggered: if (root.primary === "" && Quickshell.screens.length > 0) root.primary = Quickshell.screens[0].name
    }
    Connections { target: Hyprland; function onFocusedMonitorChanged() { root.pickPrimary(); } }

    QtObject {
        id: lockState
        property var now: new Date()
        property string wallpaper: ""
        property string wallpaperVideo: ""      // animated wallpaper set in MacShell (~/.config/macshell/wallpaper-video)
        property string userName: Quickshell.env("USER") || ""
        property string avatar: ""
        property int wifiLevel: -1          // -1 unknown/hidden, 0 off, 1..3 bars
        property bool ethernet: false       // wired connection up
        property string pass: ""
        property bool busy: false
        property int fails: 0
        property string message: ""
        property bool engaged: false
        property bool unlocking: false
        property string mediaSlot: "top"    // "top" (under the clock) | "bottom" (above the password field)
        property bool capsLock: false
        property bool use24h: true          // MacShell → Menu Bar → "24-hour clock"
        // Settings → Lock Screen → Clock (MACLOCK_CLOCK='{"f":"serif",...}' overrides it, for previews)
        property var clockCfg: { try { return JSON.parse(Quickshell.env("MACLOCK_CLOCK") || "{}"); } catch (e) { return {}; } }
        property bool artBg: true           // blurred album art behind everything while the cover is enlarged (MacShell setting)
        property bool sounds: false         // MacShell's "Play user interface sound effects" (and not in Game Mode)
        function sound(name) {
            if (sounds) Quickshell.execDetached(["pw-play", "--volume=0.7", Quickshell.env("HOME") + "/.local/share/sounds/macshell/" + name + ".wav"]);
        }
        // Now Playing presentation: "" (bubble), "art" (cover floats out, tap the cover) or "lyrics" (lyrics button)
        property string npMode: Quickshell.env("MACLOCK_NP") || (Quickshell.env("MACLOCK_ART") === "1" ? "art" : "")

        function setMediaSlot(v) {
            if (v === mediaSlot) return;
            mediaSlot = v;
            saveProc.command = ["sh", "-c", "mkdir -p \"$HOME/.config/maclock\" && printf '{\\n  \"mediaSlot\": \"%s\"\\n}\\n' \"$1\" > \"$HOME/.config/maclock/settings.json\"", "sh", v];
            saveProc.running = true;
        }
        function checkCaps() { if (!capsProc.running) capsProc.running = true; }

        function poke() {
            engaged = true;
            idleTimer.restart();
        }
        function submit() {
            if (busy || unlocking || pass.length === 0) return;
            busy = true;
            message = "";
            if (!pam.start()) { busy = false; fail("Couldn't start authentication"); }
        }
        function fail(msg) {
            pass = "";
            message = msg;
            fails++;
            msgTimer.restart();
        }
        function unlock() {
            unlocking = true;
            sound("unlock");
            unlockTimer.start();
        }
    }

    Process { id: saveProc }
    // Caps Lock indicator
    Process {
        id: capsProc
        // Hyprland's own state, not the LEDs (a virtual keyboard such as GPU Screen Recorder's can leave the LEDs lit).
        // Caps Lock lives per keyboard in Hyprland; the one you typed on last is "main" and its state is what applies
        command: ["sh", "-c", "hyprctl devices -j 2>/dev/null | jq -r '[.keyboards[] | select(.main) | .capsLock] | any'"]
        stdout: StdioCollector {
            onStreamFinished: lockState.capsLock = text.trim() === "true"
        }
    }
    Timer { interval: 700; repeat: true; running: true; triggeredOnStart: true; onTriggered: lockState.checkCaps() }

    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: lockState.now = new Date() }
    // preview-only test hook: MACLOCK_TEST_MORPH=1 flips 12/24-hour every 1.5 s so the clock morph can be checked
    Timer { interval: 1500; repeat: true; running: root.preview && Quickshell.env("MACLOCK_TEST_MORPH") === "1"; onTriggered: lockState.use24h = !lockState.use24h }
    Timer { id: idleTimer; interval: 9000; onTriggered: if (lockState.pass.length === 0 && !lockState.busy) lockState.engaged = false }
    Timer { id: msgTimer; interval: 3500; onTriggered: lockState.message = "" }
    // let the exit animation play, then drop the lock and quit
    Timer {
        id: unlockTimer
        interval: 430
        onTriggered: {
            if (root.preview) Qt.quit();
            else {
                root.lockRequested = false;
                // A WlSessionLock is single-use in practice: retire this process after unlock so
                // the next IPC launch creates a fresh session-lock object.
                quitTimer.start();
            }
        }
    }
    Timer { id: quitTimer; interval: 150; onTriggered: Qt.quit() }

    PamContext {
        id: pam
        configDirectory: "/etc/pam.d"
        config: "hyprlock"
        onPamMessage: {
            if (this.responseRequired) this.respond(lockState.pass);
        }
        onCompleted: result => {
            lockState.busy = false;
            if (result === PamResult.Success) lockState.unlock();
            else lockState.fail(result === PamResult.MaxTries ? "Too many attempts, try again shortly" : "Incorrect password");
        }
        onError: err => {
            lockState.busy = false;
            lockState.fail("Authentication error");
        }
    }

    // Resolve wallpaper paths independently of slower network/profile probes so the lock scene can decode them immediately.
    Process {
        running: true
        command: ["sh", "-c",
            "p=$(jq -r '.wallpaperPath // empty' \"$HOME/.config/macbar/settings.json\" 2>/dev/null); "
            + "[ -f \"$p\" ] || p=$(jq -r '.wallpaperPath // empty' \"$HOME/.config/macdock/settings.json\" 2>/dev/null); "
            + "[ -f \"$p\" ] || p=$(awww query 2>/dev/null | sed -n 's/.*image: //p' | head -n1); "
            + "printf '%s\\n' \"$p\"; "
            + "v=$(cat \"$HOME/.config/macshell/wallpaper-video-play\" 2>/dev/null); [ -f \"$v\" ] || v=$(cat \"$HOME/.config/macshell/wallpaper-video\" 2>/dev/null); "
            + "[ -f \"$HOME/.config/macshell/wallpaper-video\" ] && [ -f \"$v\" ] && printf '%s' \"$v\"; echo"]
        stdout: StdioCollector {
            onStreamFinished: {
                var l = text.split("\n");
                lockState.wallpaper = (l[0] || "").trim();
                lockState.wallpaperVideo = (l[1] || "").trim();
            }
        }
    }

    // ── one-shot lookups: real name, avatar, wifi, and other settings
    Process {
        running: true
        command: ["sh", "-c",
            "n=$(getent passwd \"$USER\" | cut -d: -f5 | cut -d, -f1); printf '%s\\n' \"${n:-$USER}\"; "
            + "for a in \"$HOME/.face\" \"$HOME/.face.icon\" \"/var/lib/AccountsService/icons/$USER\"; do [ -f \"$a\" ] && { printf '%s' \"$a\"; break; }; done; echo; "
            + "if [ \"$(nmcli radio wifi 2>/dev/null)\" = enabled ]; then s=$(nmcli -t -f ACTIVE,SIGNAL dev wifi 2>/dev/null | grep '^yes' | head -n1 | cut -d: -f2); "
            + "[ -n \"$s\" ] && printf '%s' \"$s\" || printf 0; else printf -- -1; fi; echo; "
            + "nmcli -t -f TYPE,STATE dev 2>/dev/null | grep -q '^ethernet:connected$' && echo eth || echo -; "
            + "jq -r '.mediaSlot // \"top\"' \"$HOME/.config/maclock/settings.json\" 2>/dev/null || echo top; "
            + "[ \"$(jq -r '.uiSounds' \"$HOME/.config/macbar/settings.json\" 2>/dev/null)\" != false ] && [ ! -f \"${XDG_RUNTIME_DIR:-/tmp}/macshell-gaming.state\" ] && echo snd || echo -; "
            + "jq -r '.lockArtBackground' \"$HOME/.config/macbar/settings.json\" 2>/dev/null || echo true; "
            + "jq -r '.use24h' \"$HOME/.config/macbar/settings.json\" 2>/dev/null || echo true; "
            + "jq -r '.language // \"auto\"' \"$HOME/.config/macbar/settings.json\" 2>/dev/null || echo auto; "
            + "jq -c '{f: .lockClockFont, w: .lockClockWeight, m: .lockClockMaterial, d: .lockClockDate, i: .lockClockIntensity, c: .lockClockTint}' \"$HOME/.config/macbar/settings.json\" 2>/dev/null || echo '{}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var l = text.split("\n");
                if ((l[0] || "").trim() !== "") lockState.userName = l[0].trim();
                lockState.avatar = (l[1] || "").trim();
                var s = parseInt((l[2] || "-1").trim());
                lockState.wifiLevel = isNaN(s) || s < 0 ? -1 : (s === 0 ? 0 : (s > 66 ? 3 : (s > 33 ? 2 : 1)));
                lockState.ethernet = (l[3] || "").trim() === "eth";
                lockState.mediaSlot = (l[4] || "top").trim() === "bottom" ? "bottom" : "top";
                lockState.sounds = (l[5] || "").trim() === "snd";
                lockState.artBg = (l[6] || "true").trim() !== "false";
                lockState.use24h = (l[7] || "true").trim() !== "false";
                var lang = (l[8] || "auto").trim();
                Qt.uiLanguage = (lang === "auto" || lang === "null") ? "" : lang;
                if (!Quickshell.env("MACLOCK_CLOCK")) { try { lockState.clockCfg = JSON.parse((l[9] || "{}").trim() || "{}"); } catch (e) { } }
                if (!root.preview) lockState.sound("lock");
            }
        }
    }

    // ═════════════ the real lock ═════════════
    WlSessionLock {
        id: lock
        locked: root.lockRequested && !root.preview
        // If this instance ever stops holding the lock without unlocking itself (another locker took over, the
        // compositor ended it, …), quit: a leftover instance keeps maclock.sh's one-locker guard and every later
        // lock attempt would silently do nothing.
        property bool wasSecure: false
        onSecureChanged: {
            if (secure) { wasSecure = true; return; }
            if (wasSecure && !root.preview && root.lockRequested) { console.log("[maclock] lost the session lock: quitting"); quitTimer.start(); }
        }

        WlSessionLockSurface {
            id: surf
            // transparent + Hyprland's session_lock_xray: the lock fades in over the desktop and fades out to it
            color: "transparent"
            LockScreen {
                anchors.fill: parent
                st: lockState
                isPrimary: root.primary === "" || surf.screen === null || surf.screen.name === root.primary
            }
        }
    }

    // ═════════════ preview window ═════════════
    Variants {
        model: root.preview ? Quickshell.screens : []
        PanelWindow {
            id: pw
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "maclock-preview"
            WlrLayershell.keyboardFocus: Quickshell.env("MACLOCK_PREVIEW_KB") === "1" && modelData.name === root.primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            LockScreen {
                anchors.fill: parent
                st: lockState
                isPrimary: root.primary === "" || pw.modelData.name === root.primary
            }
        }
    }
}
