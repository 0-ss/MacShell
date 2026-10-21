// MinimizeFx — what you see when a window is minimised or brought back: the macOS genie (the window pours into
// its place in the Dock), a quick 0.35 s fade, or nothing at all (Settings → Desktop & Dock).
//
// A full-screen, click-through overlay holds a still capture of the window and plays the effect on it; the real
// window is moved away (or brought back) at the moment that hides the hand-over.
import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: fx
    property var hub: null
    property string effect: "genie"            // genie | fade | instant

    // the one running animation: { screen, tl, win: {x,y,width,height}, target: {...}, reverse, before, after }
    property var job: null
    property real progress: 0
    readonly property bool busy: job !== null
    property real speed: 0.42                  // Magic Lamp duration, seconds (Settings → Desktop & Dock)
    readonly property int genieMs: Math.round(Math.max(0.2, Math.min(1.2, speed)) * 1000)
    readonly property int fadeMs: 350

    // play(job): job.before() runs once the window has been captured, job.after() once the effect is over
    property bool captured: false
    // the rectangles in play (global layout coordinates); read from the job when the effect starts, because a
    // window's position is only known for certain a moment after the shell asks Hyprland for it
    property var winRect: ({ x: 0, y: 0, width: 1, height: 1 })
    property var targetRect: ({ x: 0, y: 0, width: 1, height: 1 })
    function rectsFrom(j) {
        winRect = j.winFn ? j.winFn() : j.win;
        targetRect = j.targetFn ? j.targetFn() : j.target;
    }
    function play(j) {
        if (busy) { finish(); }
        if (effect === "instant" || !j.tl) {
            if (j.before) j.before();
            if (j.after) j.after();
            return;
        }
        rectsFrom(j);
        progress = j.reverse ? 1 : 0;
        captured = false;
        job = j;
        captureWait.restart();
    }
    // the window's picture never came: don't animate an empty frame, just do it
    function giveUp() {
        console.log("[minimize] no capture in time, doing it without the effect");
        var j = job;
        job = null;
        if (j && j.before) j.before();
        if (j && j.after) j.after();
    }
    // the overlay's own fade, used to hand a restored window over to the real one without a double image
    property real handover: 1
    function finish() {
        anim.stop();
        captureWait.stop();
        var j = job;
        if (j && j.reverse && effect !== "instant") {
            // put the real window back first, then let the copy fade off it
            if (j.after) j.after();
            j.after = null;
            handoverAnim.restart();
            return;
        }
        job = null;
        handover = 1;
        if (j && j.after) j.after();
    }
    NumberAnimation {
        id: handoverAnim
        target: fx; property: "handover"; from: 1; to: 0; duration: 180; easing.type: Easing.OutCubic
        onFinished: { fx.job = null; fx.handover = 1; }
    }
    function start() {
        if (!job) return;
        rectsFrom(job);
        if (job.before) job.before();
        anim.from = job.reverse ? 1 : 0;
        anim.to = job.reverse ? 0 : 1;
        anim.duration = effect === "fade" ? fadeMs : genieMs;
        anim.restart();
    }
    // The real window only moves once its picture is in hand (a first capture of a window is paced by the shell
    // and can take a few hundred ms). If it never arrives, the effect is skipped rather than played on nothing.
    Timer { id: captureWait; interval: 900; onTriggered: if (!fx.captured) fx.giveUp() }
    NumberAnimation {
        id: anim
        target: fx; property: "progress"
        // a fast ease: it leaves at once and glides into place (the old in-out curve lingered at both ends)
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.22, 0.8, 0.28, 1.0, 1.0, 1.0]
        onFinished: fx.finish()
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: ow
            required property var modelData
            screen: modelData
            readonly property bool mine: fx.job !== null && fx.job.screen === modelData.name
            visible: mine
            contentItem.opacity: fx.handover
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {}
            WlrLayershell.namespace: "macshell-minimize"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // the job's rectangles, moved from global layout coordinates into this screen's
            readonly property var w: fx.winRect
            readonly property var t: fx.targetRect
            readonly property real ox: modelData.x
            readonly property real oy: modelData.y

            ScreencopyView {
                id: cap
                width: Math.max(1, ow.w.width)
                height: Math.max(1, ow.w.height)
                captureSource: ow.mine ? fx.job.tl : null
                live: false
                visible: false
                onHasContentChanged: {
                    if (hasContent && ow.mine && fx.job && !fx.captured) {
                        fx.captured = true;
                        captureWait.stop();
                        fx.start();
                    }
                }
            }
            ShaderEffectSource { id: capTex; sourceItem: cap; hideSource: true; visible: false; live: true; smooth: true }

            // Genie
            ShaderEffect {
                anchors.fill: parent
                visible: ow.mine && fx.effect === "genie" && fx.captured
                mesh: GridMesh { resolution: Qt.size(6, 64) }
                vertexShader: Qt.resolvedUrl("genie.vert.qsb")
                fragmentShader: Qt.resolvedUrl("genie.frag.qsb")
                property variant source: capTex
                property real progress: fx.progress
                property vector4d win: Qt.vector4d(ow.w.x - ow.ox, ow.w.y - ow.oy, ow.w.width, ow.w.height)
                property vector4d target: Qt.vector4d(ow.t.x - ow.ox, ow.t.y - ow.oy, ow.t.width, ow.t.height)
                onStatusChanged: if (status === ShaderEffect.Error) console.log("[minimize] genie shader:", log)
            }

            // Fade: the window fades and settles a little toward the Dock
            Item {
                visible: ow.mine && fx.effect === "fade" && fx.captured
                x: ow.w.x - ow.ox + (ow.t.x + ow.t.width / 2 - ow.w.x - ow.w.width / 2) * fx.progress * 0.12
                y: ow.w.y - ow.oy + (ow.t.y - ow.w.y) * fx.progress * 0.12
                width: ow.w.width
                height: ow.w.height
                opacity: 1 - fx.progress
                scale: 1 - 0.08 * fx.progress
                ShaderEffectSource { anchors.fill: parent; sourceItem: cap; live: true }
            }
        }
    }
}
