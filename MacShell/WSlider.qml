// WSlider — the System Settings slider: a thin track, a round knob and a glyph at each end.
import QtQuick

Item {
    id: ws
    property real value: 0.5
    property real minimum: 0
    property color accent: "#0A84FF"
    signal moved(real v)
    height: 30
    readonly property real trackX: 34
    readonly property real trackW: Math.max(1, width - 34 - 34)
    readonly property real pos: Math.max(0, Math.min(1, ws.value))

    Canvas {
        x: 2; anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22
        antialiasing: true
        onPaint: {
            var c = getContext("2d"); c.reset();
            c.scale(width / 22, width / 22);
            c.lineWidth = 1.4;
            c.strokeStyle = Qt.rgba(1, 1, 1, 0.55);
            c.beginPath(); c.roundedRect(3, 6, 11, 11, 3.2, 3.2); c.stroke();
            c.strokeStyle = Qt.rgba(1, 1, 1, 0.85);
            c.beginPath(); c.roundedRect(8, 3, 11, 11, 3.2, 3.2); c.stroke();
        }
    }
    Canvas {
        x: ws.width - 24; anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22
        antialiasing: true
        onPaint: {
            var c = getContext("2d"); c.reset();
            c.scale(width / 22, width / 22);
            c.fillStyle = Qt.rgba(1, 1, 1, 0.55);
            c.beginPath(); c.roundedRect(3, 6, 11, 11, 3.2, 3.2); c.fill();
            c.fillStyle = Qt.rgba(1, 1, 1, 0.9);
            c.beginPath(); c.roundedRect(8, 3, 11, 11, 3.2, 3.2); c.fill();
        }
    }

    Rectangle {
        x: ws.trackX; width: ws.trackW; height: 5; radius: 2.5
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.rgba(1, 1, 1, 0.18)
    }
    Rectangle {
        x: ws.trackX; width: ws.pos * ws.trackW; height: 5; radius: 2.5
        anchors.verticalCenter: parent.verticalCenter
        color: ws.accent
        Behavior on width { enabled: !wsMa.pressed; NumberAnimation { duration: 160; easing.type: Easing.OutQuint } }
    }
    Rectangle {
        x: ws.trackX + ws.pos * ws.trackW - 11 + 1; y: (ws.height - 22) / 2 + 1
        width: 22; height: 22; radius: 11
        color: Qt.rgba(0, 0, 0, 0.2)
        Behavior on x { enabled: !wsMa.pressed; NumberAnimation { duration: 160; easing.type: Easing.OutQuint } }
    }
    Rectangle {
        id: wsKnob
        x: ws.trackX + ws.pos * ws.trackW - 11; y: (ws.height - 22) / 2
        width: 22; height: 22; radius: 11
        color: "white"
        border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.14)
        scale: wsMa.pressed ? 1.12 : 1
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }
        Behavior on x { enabled: !wsMa.pressed; NumberAnimation { duration: 160; easing.type: Easing.OutQuint } }
    }
    MouseArea {
        id: wsMa
        anchors.fill: parent
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        function setFrom(mx) { ws.moved(Math.max(ws.minimum, Math.min(1, (mx - ws.trackX) / ws.trackW))); }
        onPressed: mouse => setFrom(mouse.x)
        onPositionChanged: mouse => { if (pressed) setFrom(mouse.x); }
    }
}
