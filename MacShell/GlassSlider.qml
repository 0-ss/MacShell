import QtQuick

// Slider that looks and behaves exactly like the Control Center sliders (CCSlider in MacBar.qml): a thin 4 px track with a
// coloured fill; the small rounded-square knob is always shown, holding it springs the knob bigger and turns it into Liquid
// Glass (you see the bar through the lens, with the Control Center border), and while the value moves the knob stretches,
// leans and wobbles with a little spring.
//
// Unlike the Control Center one it works on any range (from / to / stepSize) and can carry a caption under each end.
Item {
    id: s

    property real from: 0
    property real to: 1
    property real value: 0
    property real stepSize: 0
    property int decimals: 3
    property string leftLabel: ""
    property string rightLabel: ""
    signal moved(real v)
    signal glassFailed()

    // look
    property color fg: "white"                          // resting knob
    property color fillColor: fg                        // the filled part of the bar
    property color knobColor: fg
    property color trackColor: Qt.rgba(1, 1, 1, 0.20)
    property color labelColor: Qt.rgba(1, 1, 1, 0.56)
    property string fontFamily: ""
    property color baseColor: "#2B2B2D"                 // what lies under the slider (the lens refracts it)
    property bool dark: true
    property real knobSize: 1.0                         // knob size multiplier (the settings sliders use a bigger one)
    property real pressGrow: 1.0                        // how much the knob grows (and turns to glass) while held
    property bool tileHover: false                      // the pointer is anywhere over the row that holds this slider
    // glass
    property bool glass: false                          // false: the knob stays a plain rounded square
    property url shaderUrl: ""
    property real glassLiquid: 1.0
    property real glassRim: 0.45
    property real glassGrain: 0.03
    property real glassTint: 0.42
    property color borderTint: "#8A9AB5"

    width: 230
    height: (leftLabel !== "" || rightLabel !== "") ? 40 : 22
    opacity: enabled ? 1 : 0.4

    readonly property real cy: 11
    readonly property real trackX: 14
    readonly property real trackW: Math.max(1, width - 28)
    readonly property real pos: to > from ? Math.max(0, Math.min(1, (value - from) / (to - from))) : 0

    // knob animation state: hover pops a rounded square in, holding it springs it bigger and turns it to glass
    readonly property bool hovering: sma.containsMouse || sma.pressed || tileHover
    property real hoverT: hovering ? 1 : 0
    Behavior on hoverT { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
    property real pressT: sma.pressed ? 1 : 0
    Behavior on pressT { NumberAnimation { duration: sma.pressed ? 420 : 300; easing.type: Easing.OutBack; easing.overshoot: 3.0 } }
    onPressTChanged: if (pressT > 0.02 && !ses.live) ses.scheduleUpdate()

    // jiggle: the knob stretches, leans and wobbles when the value moves; how hard depends on how fast it moves
    property real vel: 0
    property real jig: 0
    property real lastP: pos
    property real lastT: 0
    Behavior on jig { SpringAnimation { spring: 3.4; damping: 0.2; epsilon: 0.004 } }
    onPosChanged: {
        var now = Date.now();
        if (lastT > 0) {
            var dt = Math.max(1, now - lastT);
            vel = vel * 0.45 + ((pos - lastP) * trackW / dt) * 0.55;
            jig = Math.max(-1.5, Math.min(1.5, vel * 0.6));
        }
        lastP = pos; lastT = now;
        jigIdle.restart();
    }
    Timer { id: jigIdle; interval: 70; onTriggered: { s.vel = 0; s.jig = 0; } }

    // ── track + fill ──
    Rectangle {
        x: s.trackX; y: s.cy - 2; width: s.trackW; height: 4; radius: 2
        color: s.trackColor
    }
    Rectangle {
        x: s.trackX; y: s.cy - 2
        width: s.pos * s.trackW
        height: 4; radius: 2
        color: s.fillColor
    }

    // ── captions ──
    Text {
        visible: s.leftLabel !== ""
        y: 25
        text: s.leftLabel
        color: s.labelColor
        font.family: s.fontFamily; font.pixelSize: 11
    }
    Text {
        visible: s.rightLabel !== ""
        y: 25
        x: s.width - implicitWidth
        text: s.rightLabel
        color: s.labelColor
        font.family: s.fontFamily; font.pixelSize: 11
    }

    // ── what the lens sees: a hidden duplicate of the bar on its backdrop ──
    readonly property real m: 24
    Item {
        id: lyr
        visible: s.glass
        x: -s.m; y: -s.m
        width: s.width + 2 * s.m; height: s.height + 2 * s.m
        Rectangle { anchors.fill: parent; color: s.baseColor }
        Rectangle {
            x: s.m + s.trackX; y: s.m + s.cy - 2; width: s.trackW; height: 4; radius: 2
            color: s.trackColor
        }
        Rectangle {
            x: s.m + s.trackX; y: s.m + s.cy - 2
            width: s.pos * s.trackW
            height: 4; radius: 2
            color: s.fillColor
        }
    }
    ShaderEffectSource {
        id: ses
        sourceItem: s.glass ? lyr : null
        hideSource: true
        live: s.glass && s.pressT > 0.02
        mipmap: true
        visible: false
    }

    // ── knob: a rounded square on hover; held, it grows with a little spring and becomes Liquid Glass ──
    Item {
        id: knob
        readonly property real kw: (21 + 6 * s.pressGrow * s.pressT) * s.knobSize
        readonly property real kh: (14 + 3 * s.pressGrow * s.pressT) * s.knobSize
        width: Math.max(1, kw); height: Math.max(1, kh)
        x: s.trackX + s.pos * s.trackW - width / 2 - s.jig * 3        // trails a little behind when moving
        y: s.cy - height / 2
        // always visible (no longer only on hover); hovering just pops it a touch bigger
        visible: true
        scale: 1 + 0.08 * Math.min(1.3, s.hoverT)
        rotation: s.jig * 7
        transform: Scale {                  // squash and stretch along the movement: longer and flatter the faster it goes
            origin.x: knob.width / 2; origin.y: knob.height / 2
            xScale: 1 + 0.32 * Math.min(1.5, Math.abs(s.jig))
            yScale: 1 - 0.16 * Math.min(1.5, Math.abs(s.jig))
        }
        readonly property real rad: Math.max(2, Math.min(height / 2, 8 + 3 * s.pressT))

        // solid square (fades out while the glass takes over)
        Rectangle {
            anchors.fill: parent
            radius: knob.rad
            color: s.knobColor
            border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.08)
            opacity: s.glass ? Math.max(0, 1 - s.pressT * 1.4) : 1
        }
        Loader {
            anchors.fill: parent
            active: s.glass && s.pressT > 0.02
            opacity: Math.min(1, s.pressT * 1.6)
            sourceComponent: Item {
                GlassSlab {
                    anchors.fill: parent
                    src: ses
                    srcSize: Qt.size(lyr.width, lyr.height)
                    origin: Qt.point(s.m + knob.x, s.m + knob.y)
                    glass: s.glass
                    shaderUrl: s.shaderUrl
                    dark: s.dark
                    cornerR: knob.rad
                    thickness: 16
                    strengthMul: 0.85
                    liquid: s.glassLiquid
                    rim: s.glassRim * 0.25
                    grain: s.glassGrain
                    tint: s.glassTint
                    shadowAmt: 0.5
                    flatInner: 1
                    onFailed: s.glassFailed()
                }
                // edge: the same border as the Control Center buttons
                CornerBorder { z: 2; anchors.fill: parent; cornerR: knob.rad; dark: s.dark; tint: s.borderTint; amount: 1; lineW: 0.8 }
                // glassy sheen: a soft specular highlight along the top, fading out towards the middle
                Rectangle {
                    anchors.fill: parent
                    radius: knob.rad
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, s.dark ? 0.12 : 0.2) }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.02) }
                        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, s.dark ? 0.04 : 0.08) }
                    }
                }
            }
        }
    }

    MouseArea {
        id: sma
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        function setFrom(mx) {
            var p = Math.max(0, Math.min(1, (mx - s.trackX) / s.trackW));
            var v = s.from + p * (s.to - s.from);
            if (s.stepSize > 0) v = Math.round(v / s.stepSize) * s.stepSize;
            var k = Math.pow(10, s.decimals);
            s.moved(Math.round(v * k) / k);
        }
        onPressed: mouse => setFrom(mouse.x)
        onPositionChanged: mouse => { if (pressed) setFrom(mouse.x); }
    }
}
