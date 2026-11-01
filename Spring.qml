import QtQuick

// A spring that follows `target`, parameterised the way Apple describes springs (damping ratio + response) instead of
// mass / stiffness / damping:
//
//   damping   1.0 = critically damped (no overshoot, the default for UI), < 1.0 = bouncy. Add bounce only when the gesture
//             that caused the motion carried momentum (a flick / throw), never for something that just appeared.
//   response  seconds for the value to travel most of the way to the target; lower = snappier. Not a duration - the settle
//             time emerges from the two numbers.
//
// Unlike a NumberAnimation behind a Behavior, retargeting never restarts anything: the new target just changes the force, so
// the value keeps its current position AND velocity (no jump, no "brick wall" when a motion is reversed mid-flight).
//
// Use `value` wherever you would have animated a property. `snap()` jumps to the current target with no motion (use it when the
// thing was hidden). It deliberately takes no argument: assigning `target` from script would remove a binding on it.
// `animated: false` makes `value` follow `target` instantly (reduced motion).
Item {
    id: sp
    width: 0; height: 0; visible: false

    property real target: 0
    property real value: 0
    property real velocity: 0
    property real response: 0.30
    property real damping: 1.0
    property real epsilon: 0.001            // stop once closer than this to the target ...
    property bool animated: true
    readonly property bool running: fa.running

    // start at rest on the initial target (like a Behavior, which does not animate the first value)
    Component.onCompleted: { value = target; velocity = 0; }

    function snap() {
        fa.stop();
        value = target; velocity = 0;
    }

    onTargetChanged: {
        if (!animated) { fa.stop(); value = target; velocity = 0; return; }
        if (Math.abs(target - value) > epsilon || Math.abs(velocity) > epsilon * 10) fa.start();
    }
    onAnimatedChanged: if (!animated) { fa.stop(); value = target; velocity = 0; }

    function step(dt) {
        dt = Math.min(Math.max(dt, 0), 0.05);                // a stalled frame must not blow the integrator up
        var w = 2 * Math.PI / Math.max(response, 0.02);      // natural frequency from response
        var k = w * w;                                       // stiffness (unit mass)
        var c = 2 * damping * w;                             // damping coefficient
        var n = Math.max(1, Math.ceil(dt / 0.004));          // sub-steps keep stiff springs stable
        var h = dt / n;
        var v = velocity, x = value;
        for (var i = 0; i < n; i++) {
            v += (k * (target - x) - c * v) * h;
            x += v * h;
        }
        velocity = v;
        value = x;
        if (Math.abs(target - x) < epsilon && Math.abs(v) < epsilon * 10) {
            value = target; velocity = 0; fa.stop();
        }
    }

    FrameAnimation {
        id: fa
        onTriggered: sp.step(frameTime)
    }
}
