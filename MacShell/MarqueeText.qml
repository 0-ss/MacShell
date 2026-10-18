// One line of text that scrolls when it is too long (like the Now Playing subtitle on macOS):
// it rests for a moment, scrolls left in a loop, and fades out at both ends. Text that fits just sits still.
import QtQuick
import QtQuick.Effects

Item {
    id: m

    property string text: ""
    property color color: "white"
    property string fam: "Open Runde"
    property real pixelSize: 16
    property int weight: Font.Medium
    property real fade: 18            // px of fade at each end while scrolling
    property real startPad: 0         // where the text starts when it fits (the region itself may begin further left)
    property real speed: 34           // px / s
    property bool animate: true

    height: Math.ceil(pixelSize * 1.3)
    readonly property real gap: pixelSize * 3
    readonly property bool overflow: probe.implicitWidth > width - startPad
    property real scrollX: 0

    Text {
        id: probe
        visible: false
        text: m.text
        font.family: m.fam
        font.pixelSize: m.pixelSize
        font.weight: m.weight
    }

    Item {
        id: strip
        anchors.fill: parent
        visible: false
        clip: true
        Row {
            x: m.startPad + m.scrollX
            spacing: m.gap
            Text {
                text: m.text
                color: m.color
                height: strip.height
                verticalAlignment: Text.AlignVCenter
                font.family: m.fam
                font.pixelSize: m.pixelSize
                font.weight: m.weight
            }
            Text {
                visible: m.overflow
                text: m.text
                color: m.color
                height: strip.height
                verticalAlignment: Text.AlignVCenter
                font.family: m.fam
                font.pixelSize: m.pixelSize
                font.weight: m.weight
            }
        }
    }

    Rectangle {   // soft left / right edges
        id: edgeMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: Math.min(0.45, m.fade / Math.max(1, m.width)); color: "black" }
            GradientStop { position: Math.max(0.55, 1 - m.fade / Math.max(1, m.width)); color: "black" }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }
    MultiEffect {
        anchors.fill: parent
        source: strip
        maskEnabled: m.overflow
        maskSource: edgeMask
    }

    onTextChanged: scrollX = 0
    SequentialAnimation {
        running: m.overflow && m.animate && m.visible
        loops: Animation.Infinite
        onRunningChanged: if (!running) m.scrollX = 0
        PauseAnimation { duration: 2400 }
        NumberAnimation {
            target: m
            property: "scrollX"
            from: 0
            to: -(probe.implicitWidth + m.gap)
            duration: Math.max(1, (probe.implicitWidth + m.gap) / m.speed * 1000)
            easing.type: Easing.Linear
        }
    }
}
