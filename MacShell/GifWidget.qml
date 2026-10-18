// Desktop "GIF" widget: plays animated GIFs or WebPs chosen by the user,
// cropped to fill the card with the same rounded corners as the other macOS widgets.
// sizes: Small 168x168 · Medium 358x168 · Large 358x354 (times scaleF)

import QtQuick
import QtQuick.Effects

Item {
    id: w

    property string style: "normal"
    property string size: "small"
    property real scaleF: 1.0
    property string fam: "Inter"
    property real screenX: x
    property real screenY: y
    property url source: ""
    property bool editing: false
    property bool darkGlass: true
    property bool paused: false
    property string screenName: ""
    property bool desktopCovered: false
    readonly property bool isHovered: hoverArea.hovered
    readonly property bool isCovered: desktopCovered && !isHovered

    readonly property bool isSmall: size === "small"
    readonly property bool isMedium: size === "medium"
    readonly property bool isLarge: size === "large"
    readonly property real s: scaleF * (isSmall ? 168 / 158 : (isMedium ? 358 / 338 : 1.0))
    readonly property real radiusPx: 28 * s

    width: (isSmall ? 158 : (isLarge ? 358 : 338)) * s
    height: (isLarge ? 354 : 168) * scaleF

    // Rounded-corner mask
    Item {
        id: maskItem
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle {
            anchors.fill: parent
            radius: w.radiusPx
            color: "black"
        }
    }

    // Placeholder while no file is chosen or loading
    Rectangle {
        anchors.fill: parent
        radius: w.radiusPx
        visible: gif.status !== AnimatedImage.Ready
        color: w.darkGlass ? Qt.rgba(0.16, 0.16, 0.18, 0.92) : Qt.rgba(0.92, 0.92, 0.94, 0.95)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)

        Column {
            anchors.centerIn: parent
            spacing: 6 * w.s
            width: parent.width - 24

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "🎞️"
                font.pixelSize: 24 * w.s
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: w.source.toString() === "" ? "No GIF selected" : (gif.status === AnimatedImage.Loading ? "Loading GIF…" : "GIF not found")
                color: w.darkGlass ? Qt.rgba(1, 1, 1, 0.6) : Qt.rgba(0, 0, 0, 0.55)
                font.family: w.fam
                font.pixelSize: 12.5 * w.s
                font.weight: Font.DemiBold
            }
        }
    }

    // Animated GIF Player
    AnimatedImage {
        id: gif
        anchors.fill: parent
        source: w.source
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        mipmap: false // Avoid regenerating mipmaps on GPU every frame
        cache: true   // Cache frames to reduce disk and CPU thrashing
        // Downscale decoding size to match widget dimensions instead of huge original frame dimensions
        sourceSize.width: Math.min(1024, Math.ceil(Math.max(w.width, 168) * 1.5))
        sourceSize.height: Math.min(1024, Math.ceil(Math.max(w.height, 168) * 1.5))
        playing: !w.paused && w.visible && !w.isCovered
        visible: status === AnimatedImage.Ready
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: maskItem
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }

    HoverHandler {
        id: hoverArea
    }

    // Click to pause / resume toggle
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        enabled: !w.editing && gif.status === AnimatedImage.Ready
        onClicked: {
            w.paused = !w.paused;
            pausePillAnim.restart();
        }
    }

    // Subtle Pause / Play indicator badge that pops up on click
    Rectangle {
        id: pausePill
        anchors.centerIn: parent
        width: 44 * w.s
        height: 44 * w.s
        radius: 22 * w.s
        color: Qt.rgba(0, 0, 0, 0.65)
        opacity: 0.0
        visible: opacity > 0.01

        Text {
            anchors.centerIn: parent
            text: w.paused ? "⏸" : "▶"
            font.pixelSize: 18 * w.s
            color: "white"
        }

        SequentialAnimation {
            id: pausePillAnim
            NumberAnimation { target: pausePill; property: "opacity"; to: 1.0; duration: 150 }
            PauseAnimation { duration: 500 }
            NumberAnimation { target: pausePill; property: "opacity"; to: 0.0; duration: 300 }
        }
    }

    // Thin card border rim
    Rectangle {
        anchors.fill: parent
        radius: w.radiusPx
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)
    }
}

