// LiquidSwitch — the on/off switch used everywhere in the shell, after the iOS 26 / macOS Tahoe switch:
//   one tap is one motion: the knob swells into a clear glass lens as it leaves, crosses as glass (stretching a
//   little, the track colour following it) and is the solid white knob again as it lands
//   holding it keeps it glass, and it can be dragged across
// The knob can also be dragged across. Frosted / Blur turn the lens frosted, Opaque keeps it solid (it still moves).
import QtQuick
import QtQuick.Effects

Item {
    id: sw
    property bool checked: false
    property color accent: "#0A84FF"
    property color offColor: Qt.rgba(0.47, 0.47, 0.5, 0.32)
    property string material: "liquid"
    property bool dark: true
    signal toggled(bool value)
    width: 38; height: 22
    opacity: enabled ? 1 : 0.4

    // ONE motion, like the iOS 26 switch: a single value (along) moves the knob, and everything else follows it —
    // the knob turns to glass and swells as it leaves, is most glassy half way, and is solid again as it lands;
    // the stretch and the track colour ride on the same curve. Holding it (press / drag) keeps it glass.
    property real along: checked ? 1 : 0
    Behavior on along { enabled: !ma.dragging; NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }
    readonly property real travel: Math.sin(Math.PI * Math.max(0, Math.min(1, along)))
    property real held: 0
    Behavior on held { NumberAnimation { duration: ma.pressed ? 180 : 260; easing.type: Easing.OutCubic } }
    readonly property real glass: Math.max(held, travel)

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        // the colour follows the knob across rather than switching at once
        color: Qt.rgba(sw.offColor.r + (sw.accent.r - sw.offColor.r) * sw.along,
                       sw.offColor.g + (sw.accent.g - sw.offColor.g) * sw.along,
                       sw.offColor.b + (sw.accent.b - sw.offColor.b) * sw.along,
                       sw.offColor.a + (sw.accent.a - sw.offColor.a) * sw.along)
    }
    LiquidKnob {
        id: knob
        z: 2
        restW: sw.height - 4; restH: sw.height - 4
        grow: 1.5
        growH: 0.34                      // it swells past the track's edges, like on iOS
        glass: sw.glass
        material: sw.material
        dark: sw.dark
        fillColor: sw.accent; restColor: sw.offColor
        trackH: sw.height - 4
        leftRoom: sw.along * (sw.width - sw.height)
        rightRoom: (1 - sw.along) * (sw.width - sw.height)
        // the centre runs along the track; growing never shifts it, so the lens bulges evenly
        readonly property real cx: ma.dragging ? Math.max(sw.height / 2, Math.min(sw.width - sw.height / 2, ma.dragX))
                                               : sw.height / 2 + Math.max(0, Math.min(1, sw.along)) * (sw.width - sw.height)
        x: cx - width / 2
        y: (sw.height - height) / 2
        transform: Scale {
            origin.x: knob.width / 2; origin.y: knob.height / 2
            xScale: 1 + 0.16 * sw.travel
            yScale: 1 - 0.08 * sw.travel
        }
        layer.enabled: sw.travel > 0.08 && sw.material !== "opaque"
        layer.effect: MultiEffect { blurEnabled: true; blurMax: 6; blur: 0.35 * sw.travel; autoPaddingEnabled: true }
    }
    MouseArea {
        id: ma
        anchors.fill: parent; anchors.margins: -4
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        property bool dragging: false
        property real pressX: 0
        property real dragX: 0
        onPressed: mouse => { pressX = mouse.x; dragging = false; sw.held = 1; }
        onPositionChanged: mouse => {
            if (!dragging && Math.abs(mouse.x - pressX) > 4) dragging = true;
            dragX = mouse.x - 4;
        }
        onReleased: mouse => {
            var v = dragging ? (dragX > sw.width / 2) : !sw.checked;
            if (dragging) sw.along = Math.max(0, Math.min(1, (dragX - sw.height / 2) / (sw.width - sw.height)));
            dragging = false;
            if (v !== sw.checked) sw.toggled(v);
            sw.along = Qt.binding(function () { return sw.checked ? 1 : 0; });
            sw.held = 0;
        }
        onCanceled: { dragging = false; sw.held = 0; }
    }
}
