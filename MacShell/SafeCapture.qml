// SafeCapture — a ScreencopyView that never lets go of a capture while a frame may still be in flight.
//
// Why: Hyprland answers every capture with a frame object. If the shell destroys that frame before Hyprland has replied
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
// Callers must not set captureSource / live themselves. Use `armed` to ask "may I request a frame now?".
import QtQuick
import Quickshell.Wayland

ScreencopyView {
    id: sc

    property var want: null              // the window (toplevel) the owner wants captured, or null
    property bool wantLive: false        // the owner wants a continuous stream
    property int graceMs: 250            // how long the source outlives `want` (>> one compositor frame)

    property var held: null              // what is actually attached
    readonly property bool armed: want !== null && held !== null   // safe to request a single frame (captureFrame)

    captureSource: held
    live: wantLive && want !== null && held !== null

    onWantChanged: {
        if (want !== null) { releaseT.stop(); held = want; }
        else if (held !== null) releaseT.restart();
    }
    Component.onCompleted: { if (want !== null) held = want; }

    Timer {
        id: releaseT
        interval: sc.graceMs
        onTriggered: { if (sc.want === null) sc.held = null; }
    }

    // one frame, only when it is safe
    function snap() { if (armed && typeof sc.captureFrame === "function") sc.captureFrame(); }
}
