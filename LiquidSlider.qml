// LiquidSlider — the slider used everywhere in the shell: a slim track, an accent fill and a knob that becomes a
// glass lens while you drag it (see LiquidKnob). Put glyphs or labels around it from outside.
import QtQuick

Item {
    id: s
    property real value: 0                  // 0 … 1
    property real minimum: 0
    property color accent: "#0A84FF"
    property color trackColor: Qt.rgba(0.47, 0.47, 0.5, 0.3)
    property string material: "liquid"
    property bool dark: true
    property real trackH: 4
    property real knobSize: 20
    property bool knobAtRest: true          // false: no knob until you touch it (the Control Center look)
    property real stepSize: 0               // in 0 … 1 units
    readonly property bool pressed: ma.pressed
    signal moved(real v)
    height: Math.max(knobSize + 6, 24)
    opacity: enabled ? 1 : 0.4

    readonly property real pos: Math.max(0, Math.min(1, value))
    readonly property real span: Math.max(1, width - knobSize)
    // the same motion as the Control Center slider (upstream CCSlider): holding springs the knob bigger, and it stretches
    // and leans along the movement, then rings out
    property real glass: 0
    Behavior on glass { NumberAnimation { duration: ma.pressed ? 420 : 300; easing.type: Easing.OutBack; easing.overshoot: 3.0 } }
    property real vel: 0
    property real jig: 0
    property real lastV: value
    property real lastT: 0
    Behavior on jig { SpringAnimation { spring: 3.4; damping: 0.2; epsilon: 0.004 } }
    onValueChanged: {
        var now = Date.now();
        if (lastT > 0) {
            var dt = Math.max(1, now - lastT);
            vel = vel * 0.45 + ((value - lastV) * span / dt) * 0.55;
            jig = Math.max(-1.5, Math.min(1.5, vel * 0.6));
        }
        lastV = value; lastT = now;
        jigIdle.restart();
    }
    Timer { id: jigIdle; interval: 70; onTriggered: { s.vel = 0; s.jig = 0; } }
    property real shown: knobAtRest ? 1 : 0
    Behavior on shown { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    Rectangle {
        x: s.knobSize / 2 - s.trackH / 2; width: s.span + s.trackH; height: s.trackH; radius: height / 2
        anchors.verticalCenter: parent.verticalCenter
        color: s.trackColor
    }
    Rectangle {
        x: s.knobSize / 2 - s.trackH / 2; width: s.pos * s.span + s.trackH; height: s.trackH; radius: height / 2
        anchors.verticalCenter: parent.verticalCenter
        color: s.accent
    }
    LiquidKnob {
        id: knob
        restW: s.knobSize; restH: s.knobSize
        grow: 1.9
        glass: s.glass
        material: s.material
        dark: s.dark
        fillColor: s.accent; restColor: s.trackColor
        trackH: s.trackH
        leftRoom: s.pos * s.span; rightRoom: (1 - s.pos) * s.span
        x: s.knobSize / 2 + s.pos * s.span - width / 2 - s.jig * 3
        anchors.verticalCenter: parent.verticalCenter
        opacity: Math.min(1, Math.max(s.shown, s.glass))
        scale: 0.6 + 0.4 * Math.min(1, Math.max(s.shown, s.glass))
        rotation: s.jig * 7
        transform: Scale {
            origin.x: knob.width / 2; origin.y: knob.height / 2
            xScale: 1 + 0.32 * Math.min(1.5, Math.abs(s.jig))
            yScale: 1 - 0.16 * Math.min(1.5, Math.abs(s.jig))
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        function setFrom(mx) {
            var v = Math.max(s.minimum, Math.min(1, (mx - s.knobSize / 2) / s.span));
            if (s.stepSize > 0) v = Math.round(v / s.stepSize) * s.stepSize;
            s.moved(v);
        }
        onPressed: mouse => { s.glass = 1; setFrom(mouse.x); }
        onPositionChanged: mouse => { if (pressed) setFrom(mouse.x); }
        onReleased: s.glass = 0
        onCanceled: s.glass = 0
    }
}
