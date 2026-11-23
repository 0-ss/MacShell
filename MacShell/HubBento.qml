import QtQuick

// Staggered Bento slot for the Left Hub: ColorOS 17 / Tahoe row-by-row spring entrance + ContourGlow cursor rim halo
Item {
    id: hb
    property int seq: 0
    property int row: 0
    property int col: 0
    property real cornerR: 28
    property bool glow: true
    property real ap: 1
    onSeqChanged: if (seq > 0) { ap = 0; hbIn.restart(); }
    SequentialAnimation {
        id: hbIn
        PauseAnimation { duration: Math.min(140, hb.row * 24 + hb.col * 12) }
        NumberAnimation { target: hb; property: "ap"; from: 0; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.5 }
    }
    transform: Translate { y: (1 - hb.ap) * 16 }
    opacity: Math.max(0, Math.min(1, hb.ap * 1.8))
    HoverHandler { id: hbHov }
    ContourGlow {
        z: 5
        visible: hb.glow && amount > 0.005
        cornerR: hb.cornerR
        hovered: hbHov.hovered
        at: hbHov.point.position
    }
}
