import QtQuick
import QtQuick.Effects

Item {
    id: b
    required property var wd
    property string kind: "play"
    property color col: "white"
    property real gw: 30                 // glyph size in px
    property real gh: 30
    property bool on: false              // shuffle / repeat engaged: round highlight behind the glyph
    property bool enabledBtn: true
    property string badge: ""            // "1" for repeat-one
    property bool idleFill: false        // faint round background even when switched off
    signal clicked()
    // morph state
    property bool useA: true
    property string kindA: kind
    property string kindB: kind
    property real morphT: 1
    property real pulse: 0
    property real nudgeDir: 0
    readonly property real visA: useA ? morphT : 1 - morphT
    readonly property real visB: 1 - visA
    onKindChanged: {
        if (useA) kindB = kind; else kindA = kind;
        useA = !useA;
        morphAnim.restart();
    }
    NumberAnimation { id: morphAnim; target: b; property: "morphT"; from: 0; to: 1; duration: 340; easing.type: Easing.OutCubic }
    SequentialAnimation {
        id: nudgeAnim
        NumberAnimation { target: b; property: "pulse"; to: 1; duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: b; property: "pulse"; to: 0; duration: 300; easing.type: Easing.OutCubic }
    }
    scale: ma.pressed ? 0.86 : 1.0
    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
    opacity: b.wd.hasPlayer && b.enabledBtn ? (ma.pressed ? 0.6 : 1) : 0.4
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(b.width, b.height)
        height: width
        radius: width / 2
        color: b.on ? (b.wd.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10))
                    : (b.wd.dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.05))
        visible: b.on || b.idleFill
        Behavior on color { ColorAnimation { duration: 200 } }
    }
    // icon: morphs into the next one (old glyph blurs + shrinks away, new one comes into focus);
    // back / forward also give a motion-blur nudge when clicked
    Item {
        id: icon
        anchors.centerIn: parent
        width: b.gw
        height: b.gh
        PlayerGlyph {
            width: icon.width; height: icon.height
            x: b.nudgeDir * b.pulse * icon.width * 0.14
            kind: b.kindA
            col: b.col
            opacity: b.visA
            scale: 0.7 + 0.3 * b.visA
            visible: opacity > 0.01
            layer.enabled: true
            layer.effect: MultiEffect { blurEnabled: true; blurMax: 24; blur: Math.min(1, (1 - b.visA) * 0.9 + b.pulse * 0.45) }
        }
        PlayerGlyph {
            width: icon.width; height: icon.height
            x: b.nudgeDir * b.pulse * icon.width * 0.14
            kind: b.kindB
            col: b.col
            opacity: b.visB
            scale: 0.7 + 0.3 * b.visB
            visible: opacity > 0.01
            layer.enabled: true
            layer.effect: MultiEffect { blurEnabled: true; blurMax: 24; blur: Math.min(1, (1 - b.visB) * 0.9 + b.pulse * 0.45) }
        }
    }
    Text {
        visible: b.badge !== ""
        anchors.centerIn: parent
        text: b.badge
        color: b.col
        font.family: b.wd.fam
        font.pixelSize: b.gh * 0.42
        font.weight: Font.Bold
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        enabled: !b.wd.preview && !b.wd.editing && b.wd.hasPlayer && b.enabledBtn
        onClicked: {
            if (b.kind === "next" || b.kind === "prev") { b.nudgeDir = b.kind === "next" ? 1 : -1; nudgeAnim.restart(); }
            b.clicked();
        }
    }
}
