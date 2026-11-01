// SafeCapture — a ScreencopyView that never lets go of a capture while a frame may still be in flight, and that rebuilds itself
// when Hyprland ends the capture.
//
// Why (crash): Hyprland answers every capture with a frame object. If the shell destroys that frame before Hyprland has replied
// (ready / failed), Hyprland's reply lands on an object that no longer exists and the whole Wayland connection dies
// ("wl_display#1: error 0: invalid object NN") — the shell crashes. That is exactly what happened when a window was
// closed right after it was opened: the capture's source was set to null in the same instant its live stream stopped.
//
// How: bind `want` / `wantLive` instead of `captureSource` / `live`.
//   * `wantLive` false (or `want` null) stops the stream at once — no NEW frame is requested.
//   * `want` going null does NOT drop the source yet: it is kept for `graceMs`, so the frame that is already in
//     flight can finish. Only then is the capture source released (nothing in flight any more).
//   * a source that arrives again within the grace period just cancels the release.
//
// Why (dead captures): when a frame request FAILS (a tiled window is being re-laid out and its size changes on every frame of the
// animation, a window moves workspace, ...) Quickshell logs "Ending recording due to screencopy failure", destroys the capture
// context, and `hasContent` turns false. Nothing ever creates a new context for the same source, so the window stays out of the
// glass for good (the Control Center / menus / Dock then showed only the wallpaper), and every captureFrame() after that logs
// "Cannot capture frame, as no recording context is ready" (hundreds of lines a second from a 33 ms timer).
//   * snap() only asks for a frame while the view HAS a picture (`hasContent`): the first frame of a new context is requested by
//     Quickshell itself, so asking while there is none can only produce that warning.
//   * the moment `hasContent` drops after it was true (the context died) the source is rebuilt: detached and attached again,
//     which creates a fresh context. A window that is still animating may fail again, so retries back off (150 ms, 300 ms, ...).
//   * a capture that never gets a picture (1.5 s) is rebuilt the same way; after 8 rebuilds it is marked `dead` and asks for
//     nothing until its window changes size (heal()) or the owner hands it another window.
//
// Callers must not set captureSource / live themselves. Use `armed` to ask "may I request a frame now?".
import QtQuick
import Quickshell
import Quickshell.Wayland
import "CaptureGate.js" as Gate

ScreencopyView {
    id: sc

    property var want: null              // the window (toplevel) the owner wants captured, or null
    property bool wantLive: false        // the owner wants a continuous stream
    property int graceMs: 250            // how long the source outlives `want` (>> one compositor frame)

    property var held: null              // what is actually attached
    property bool dead: false            // rebuilt too often without ever getting a picture: stop asking (see above)
    property bool reviving: false        // the source is being rebuilt right now
    readonly property bool armed: want !== null && held !== null && !dead && !reviving && hasContent === true   // safe to request a single frame

    // `pulse` is how a single frame is requested (see snap()): switching `live` on makes Quickshell request one frame ONLY when a
    // capture context exists, and silently does nothing when it does not. captureFrame() itself logs "Cannot capture frame, as no
    // recording context is ready" every time it is called without a context, which is what spammed the log.
    property bool pulse: false

    // `hold`: the owner says the window's size is changing right now (a tiled window being re-laid out). Every rebuild destroys and creates a
    // capture context, and during a tiling animation that used to happen again and again (each size change reset the retries and the watchdog
    // fired mid-animation). While `hold` is set nothing is rebuilt; the owner calls heal() / kick() once the size has settled.
    property bool hold: false

    // MACSHELL_CAPLOG=1 (environment): one line per capture event, to see what the compositor does while windows are re-tiled
    readonly property bool dbg: Quickshell.env("MACSHELL_CAPLOG") === "1"
    function log(m) { if (dbg) console.log("[capture " + (held ? "held" : "free") + " " + Math.round(width) + "x" + Math.round(height) + "] " + m); }

    captureSource: held
    live: (wantLive || pulse) && !reviving && !dead && want !== null && held !== null

    // one frame, only when it is safe. Never calls captureFrame() directly, so it can never warn.
    function snap() {
        if (!armed) return;
        pulse = true;
        pulse = false;
    }

    // ── rebuild ──
    property int tries: 0
    readonly property int maxTries: 3     // every rebuild is another capture context created and destroyed: few, and spread out
    property bool hadContent: false
    property real lastRebuild: 0
    property real heldAt: 0              // when the current source was attached
    property bool ended: false           // Hyprland ended the capture (it HAD a picture and lost it): no frame is in flight any more
    function recover(fast) {
        if (want === null || held === null || reviving || dead || hold) return;
        if (++tries > maxTries) { log("gave up after " + maxTries + " rebuilds"); dead = true; wakeT.restart(); return; }
        Gate.noteFail();
        log("rebuild " + tries + (ended ? " (compositor ended it)" : " (no picture)"));
        reviving = true;                       // live off: a frame still in flight gets a moment to finish
        lastRebuild = Date.now();
        // CRASH RULE: a capture is only dropped quickly when it is KNOWN to be over (`ended`). A capture that merely has no picture yet may
        // have a frame request in flight; destroying it then makes Hyprland answer a dead object ("wl_display#1: error 0: invalid
        // object NN", the Wayland connection dies, the shell crashes). Those get a long grace period.
        reviveA.interval = (fast && ended) ? 60 : 150;     // the original timings: this is the part that is known not to upset Hyprland
        reviveA.restart();
    }
    // rebuild a capture that has no picture (used when the layout changed under it): no waiting for the watchdog.
    // Rebuilding while the window is still sliding into place only fails again (and Quickshell logs every failure), so a capture
    // that was rebuilt in the last 350 ms is left alone.
    function kick() {
        if (held === null || want === null || reviving || dead) return;     // a capture that gave up is retried by wakeT, not from here
        if (hasContent === true) return;
        if (Date.now() - lastRebuild < 350) return;
        // no picture yet and not known to be over: a first frame normally arrives within ~100 ms and a failed capture is over just as fast, so 0.5 s
        // without a picture means it is dead (a window that opened while the layout changed fails its very first frame). The old 2 s here was the
        // 2-3 second wait for the glass to show what is behind it.
        if (!ended && Date.now() - heldAt < 500) return;
        recover(true);
    }
    // a capture that gave up is not abandoned for good: one more attempt now and then (the window may be capturable by then)
    Timer { id: wakeT; interval: 20000; onTriggered: { if (sc.dead && sc.want !== null) { sc.dead = false; sc.tries = sc.maxTries - 1; if (sc.held !== null && sc.hasContent === false) sc.recover(); } } }
    // the window changed size: whatever went wrong before gets another chance
    function heal() {
        if (held === null) return;
        dead = false; tries = 0; missTicks = 0;
        if (hasContent === false && !reviving) missTicks = 2;     // no picture: the watchdog rebuilds on its next tick (250 ms)
    }
    function nudge() { kick(); }     // only acts on a capture without a picture
    Timer { id: reviveA; onTriggered: { if (sc.want !== null) sc.held = null; reviveB.interval = Math.min(2000, 150 * Math.pow(2, Math.max(0, sc.tries - 1))); reviveB.restart(); } }
    Timer { id: reviveB; onTriggered: { sc.reviving = false; if (sc.want !== null) sc.attach(); } }

    onHasContentChanged: {
        log(hasContent === true ? "picture" : "picture lost");
        if (hasContent === true) { hadContent = true; ended = false; tries = 0; missTicks = 0; dead = false; }
        else lostPicture();
    }
    // Quickshell clears the picture size together with `hasContent` when it ends a capture: either one going away counts
    onImplicitWidthChanged: { if (implicitWidth <= 0 && hadContent) lostPicture(); }
    function lostPicture() {
        if (!hadContent) return;
        // it HAD a picture and lost it: Hyprland ended the capture. Rebuild right away (no frame is in flight any more)
        hadContent = false;
        ended = true;
        Gate.noteFail();
        if (held !== null && want !== null) recover(true);
    }
    onHeldChanged: { hadContent = false; ended = false; missTicks = 0; heldAt = Date.now(); }

    // a capture that stays without a picture is rebuilt (0.5 s)
    property int missTicks: 0
    Timer {
        interval: 250; repeat: true
        running: sc.want !== null && sc.held !== null && !sc.dead && !sc.reviving && !sc.hold && sc.hasContent === false
        onTriggered: { if (++sc.missTicks >= 2) { sc.missTicks = 0; sc.recover(); } }
        onRunningChanged: if (!running) sc.missTicks = 0
    }
    // a size change (tiling re-layout, resize): the old retries no longer count
    onWidthChanged: heal()
    onHeightChanged: heal()

    // A capture context is created through attach(): globally at most one every few ms (CaptureGate.slotDelay), so a workspace switch,
    // a batch of new windows or the shell's own start never creates dozens of contexts in the same instant.
    function attach() {
        if (want === null) return;
        var d = Gate.slotDelay();
        if (d <= 0) { held = want; return; }
        attachT.interval = d;
        attachT.restart();
    }
    Timer { id: attachT; onTriggered: { if (sc.want !== null) sc.held = sc.want; } }

    onWantChanged: {
        tries = 0; missTicks = 0; dead = false;
        if (want !== null) { releaseT.stop(); if (held !== want) attach(); else attachT.stop(); }
        else { attachT.stop(); if (held !== null) releaseT.restart(); }
    }
    Component.onCompleted: { if (want !== null) attach(); }

    Timer {
        id: releaseT
        interval: sc.graceMs
        onTriggered: { if (sc.want === null) sc.held = null; }
    }
}
