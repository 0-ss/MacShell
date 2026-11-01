// Disintegrate a card (cleared notifications): put the card inside, call dissolve(delayMs); `done` fires when it is gone.
import QtQuick

Item {
    id: dz
    default property alias content: inner.data
    property real progress: 0
    property int duration: 900
    property real pad: 70
    property real cardH: height          // the card's real height (the slot itself may shrink while it dissolves)
    signal done()
    function dissolve(delay) { dzDelay.interval = Math.max(1, delay || 1); dzDelay.restart(); }
    Timer { id: dzDelay; onTriggered: { snap.scheduleUpdate(); dzAnim.restart(); } }
    NumberAnimation { id: dzAnim; target: dz; property: "progress"; from: 0; to: 1; duration: dz.duration; easing.type: Easing.InOutSine
                      onFinished: dz.done() }
    Item { id: inner; anchors.fill: parent; visible: dz.progress <= 0 }
    ShaderEffectSource { id: snap; sourceItem: inner; live: dz.progress <= 0; hideSource: false; visible: false
                         width: dz.width; height: dz.cardH; sourceRect: Qt.rect(0, 0, dz.width, dz.cardH) }
    ShaderEffect {
        visible: dz.progress > 0
        x: 0; y: -dz.pad
        width: dz.width + dz.pad; height: dz.cardH + dz.pad
        fragmentShader: Qt.resolvedUrl("dust.frag.qsb")
        property variant source: snap
        property real progress: dz.progress
        property vector2d itemSize: Qt.vector2d(width, height)
        property vector2d cardSize: Qt.vector2d(dz.width, dz.cardH)
        property real pad: dz.pad
        property real seed: Math.random()
    }
}
