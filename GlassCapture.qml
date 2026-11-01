// GlassCapture — a SafeCapture for the glass backdrops (bar menus, Control Center, Dock) that never lets the wallpaper show where a
// window is.
//
// Why: when Hyprland re-lays out tiled windows (an app opens, one closes, a resize) it fails the running capture of every window that
// moved. Quickshell then drops the picture (`hasContent` false) until SafeCapture has rebuilt the capture and the first new frame
// arrives. During that gap the window was missing from the glass backdrop, and the glass showed the bare wallpaper (the glitch on the
// Control Center, every bar menu and the Dock).
//
// How (on by default, see `keep` below): a ShaderEffectSource copy of the capture refreshes only while the capture HAS a picture. When the
// picture goes away the last good frame stays on screen under the capture until the new capture has a frame.
//
// Same interface as SafeCapture (want, wantLive, graceMs, armed, held, hasContent, snap(), heal(), nudge(), kick()).
import QtQuick
import Quickshell

Item {
    id: glassCap

    // The tiling-safe behaviour below (pause while a window is re-tiled, crossfade, no-wallpaper surface, kept last frame) is ON by default
    // and costs next to nothing: the kept-frame copy runs twice a second and only while glass is on screen (`glassOn`).
    // MACSHELL_GLASSFX=0 (environment) switches all of it off (the plain capture); MACSHELL_KEEP=0 only the last-frame layer.
    property bool glassOn: true        // the owner sets it false while no glass is drawn (nothing to keep warm then)
    readonly property bool fx: Quickshell.env("MACSHELL_GLASSFX") !== "0"

    property alias want: cap.want
    property bool wantLive: false
    property alias graceMs: cap.graceMs
    // `settling`: the window's SIZE is changing right now (a tiled window being re-laid out, a resize). Hyprland fails the capture frame that
    // is in flight when the size changes, and Quickshell then destroys the whole capture; the glass lost the window until it was rebuilt.
    // So while the size is moving no new frame is requested (the last good frame stays on screen, see `keep`), and the moment it has been
    // still for settleMs the stream simply carries on from a capture that is still alive. Position-only changes (dragging) never pause.
    property int settleMs: 45
    readonly property bool settling: settleT.running
    readonly property bool armed: cap.armed && !settling
    readonly property bool hasContent: cap.hasContent === true
    readonly property var held: cap.held
    readonly property bool dead: cap.dead
    readonly property int tries: cap.tries
    readonly property bool reviving: cap.reviving
    readonly property bool keeping: keep.on && !(cap.hasContent === true && !fading)     // the kept frame is what is on screen

    function snap() { if (!settling) cap.snap(); }
    function heal() { cap.heal(); }
    function nudge() { if (!settling) cap.nudge(); }
    function kick() { if (!settling) cap.kick(); }

    property real lastW: 0
    property real lastH: 0
    function sizeMoved() {
        var first = lastW <= 0 || lastH <= 0;          // the first real size is not a change
        var changed = Math.abs(width - lastW) >= 1 || Math.abs(height - lastH) >= 1;
        if (width > 0 && height > 0) { lastW = width; lastH = height; }
        if (fx && !first && changed && cap.want !== null) {
            if (!settleT.running && keep.on && cap.hasContent === true && !fading) keep.scheduleUpdate();     // the last good frame, before it is stretched
            settleT.restart();
        }
    }
    onWidthChanged: sizeMoved()
    onHeightChanged: sizeMoved()
    Timer {
        id: settleT
        interval: glassCap.settleMs
        // still again: whatever went wrong while it moved gets a fresh start (a capture that did die is rebuilt now, not on the watchdog)
        onTriggered: { cap.heal(); if (cap.hasContent !== true) cap.kick(); else glassCap.beginFade(); }
    }

    // ── smoothness: crossfade instead of a hard swap ──
    // Every time the picture changes under the glass in one jump (a capture that was rebuilt, a window that finished re-tiling and now has a
    // crisp frame instead of the stretched old one) the new frame fades in over the frozen old one. The capture is never hidden: it keeps
    // 2 % opacity at the least, so Quickshell keeps drawing (and consuming) its frames exactly as before.
    // Where a window has NEVER had a picture yet (a window that just opened, or one that was never handed a capture) the glass must not
    // show the bare wallpaper: a plain window-coloured surface sits there until the first real frame has faded in. After that the kept
    // last frame (`keep`) covers every gap, so the placeholder never shows again for that window.
    property color placeholder: "#1e1e20"
    property bool keepValid: false
    function updKeep() { if (cap.hasContent === true && !fading) { keepValid = true; if (keep.on) keep.scheduleUpdate(); } }
    onFadingChanged: updKeep()
    Rectangle {
        anchors.fill: parent
        z: -2
        color: glassCap.placeholder
        visible: glassCap.fx && !glassCap.keepValid && !(cap.hasContent === true && !glassCap.fading)
    }
    property int fadeMs: 100
    property real fadeIn: 1
    readonly property bool fading: fadeIn < 0.999
    function beginFade() { fadeAnim.stop(); fadeIn = 0.02; fadeAnim.start(); }
    NumberAnimation { id: fadeAnim; target: glassCap; property: "fadeIn"; from: 0.02; to: 1; duration: glassCap.fadeMs; easing.type: Easing.OutCubic }
    // a picture that is gone for only a blink (the capture failed and came straight back) does not restart the fade
    Timer { id: lostT; interval: 50; onTriggered: { fadeAnim.stop(); glassCap.fadeIn = 0.02; } }
    Connections {
        target: cap
        function onHasContentChanged() {
            if (!glassCap.fx) return;
            glassCap.updKeep();
            if (cap.hasContent === true) { lostT.stop(); if (glassCap.fadeIn < 0.999 && !fadeAnim.running) fadeAnim.start(); }
            else lostT.restart();
        }
    }
    Component.onCompleted: if (fx) fadeIn = 0.02

    Timer {
        id: keepT
        interval: 1000; repeat: true; triggeredOnStart: true
        running: keep.on && glassCap.glassOn && cap.hasContent === true && !glassCap.fading && cap.want !== null && glassCap.visible
        onTriggered: keep.scheduleUpdate()
    }

    SafeCapture {
        id: cap
        anchors.fill: parent
        wantLive: glassCap.wantLive && !glassCap.settling
        hold: glassCap.settling
        opacity: glassCap.fadeIn
    }

    // The last good frame of the window, drawn UNDER the live capture. It refreshes only while the capture has a picture; when the picture
    // goes away (Hyprland ended the capture while a tiled window was re-laid out) it keeps the last frame, and shows it until the new
    // capture has one. It is a plain sibling of the capture (the capture is still drawn normally: no hideSource, nothing is frozen), and
    // it is faded out (not hidden: a hidden source frees its texture) while the capture has a picture, so translucent windows (a terminal
    // with background opacity) are not blended twice.
    // ON by default (this is the fix for the glass flashing to the bare wallpaper when a tiled window opens / re-tiles while a menu or the
    // Control Center is open). An earlier version of this idea (capture hidden, drawn only through the source) crashed the shell on Hyprland
    // ("wl_display#1: error 0: invalid object NN"); this one never hides the capture and never touches its source, it only copies what the
    // capture draws. MACSHELL_KEEP=0 (environment) switches it off again if it ever misbehaves.
    ShaderEffectSource {
        id: keep
        readonly property bool on: glassCap.fx ? Quickshell.env("MACSHELL_KEEP") !== "0" : Quickshell.env("MACSHELL_KEEP") === "1"
        anchors.fill: parent
        z: -1
        sourceItem: on ? cap : null
        hideSource: false
        visible: on
        // NOT live: copying every window's capture into a second texture on every frame doubled the GPU work of the glass (the lag when a
        // menu / Control Center opens over several windows). The copy is refreshed twice a second, and right before the window is resized
        // or a fade ends (when it matters), so after a loss the kept frame is at most half a second old.
        live: false
        opacity: (cap.hasContent === true && !glassCap.fading) ? 0.001 : 1
        recursive: false
    }
}
