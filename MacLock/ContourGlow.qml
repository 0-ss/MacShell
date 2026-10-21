// Hover contour glow (same shader as MacShell's Spotlight): a thin light line along the rounded outline + a soft
// halo, brightest near the cursor. Put it inside the shape it outlines.
import QtQuick

ShaderEffect {
    id: cgl
    property real cornerR: 18
    property bool hovered: false
    property real boost: 1.0                                  // > 1 while pressed
    property point at: Qt.point(width / 2, height / 2)      // cursor, in the shape's coordinates
    property real pad: 14
    property color glowColor: "white"
    anchors.fill: parent
    anchors.margins: -pad
    fragmentShader: Qt.resolvedUrl("contourglow.frag.qsb")
    property vector2d itemSize: Qt.vector2d(width, height)
    property vector2d mouse: Qt.vector2d(at.x, at.y)
    property real amount: hovered ? boost : 0
    Behavior on amount { NumberAnimation { duration: 320; easing.type: Easing.OutQuint } }
    property real spread: Math.max(40, Math.min(width, height) * 0.9)
    property vector4d tint: Qt.vector4d(glowColor.r, glowColor.g, glowColor.b, 1)
    visible: amount > 0.005
}
