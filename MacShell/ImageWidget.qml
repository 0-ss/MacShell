// Desktop "Image" widget: shows a picture the user chose, cropped to fill the card with the same rounded corners as the
// Weather / Calendar / Clock / Player widgets.
// sizes: Small 168x168 · Medium 358x168 · Large 358x354 (times scaleF, the widget size slider)
import QtQuick
import QtQuick.Effects
import "I18n.js" as I18n

Item {
    id: w

    property string style: "normal"
    property string size: "small"
    property real scaleF: 1.0
    property string fam: "Open Runde"
    property real screenX: x
    property real screenY: y
    property url source: ""
    property bool editing: false
    property bool darkGlass: true
    property color borderTint: "#8A9AB5"      // Control Center border colour

    readonly property bool isSmall: size === "small"
    readonly property bool isMedium: size === "medium"
    readonly property bool isLarge: size === "large"
    readonly property real s: scaleF * (isSmall ? 168 / 158 : (isMedium ? 358 / 338 : 1.0))
    readonly property real radiusPx: 28 * s

    width: (isSmall ? 158 : (isLarge ? 358 : 338)) * s
    height: (isLarge ? 354 : 168) * scaleF

    // rounded-corner mask for the picture
    Item {
        id: maskItem
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle { anchors.fill: parent; radius: w.radiusPx; color: "black" }
    }

    // placeholder while nothing is chosen / the file cannot be read
    Rectangle {
        anchors.fill: parent
        radius: w.radiusPx
        visible: img.status !== Image.Ready
        color: w.darkGlass ? Qt.rgba(0.16, 0.16, 0.18, 0.92) : Qt.rgba(0.92, 0.92, 0.94, 0.95)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)
        Text {
            anchors.centerIn: parent
            width: parent.width - 24
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: w.source.toString() === "" ? I18n.tr("No image") : (img.status === Image.Loading ? "" : I18n.tr("Image not found"))
            color: w.darkGlass ? Qt.rgba(1, 1, 1, 0.5) : Qt.rgba(0, 0, 0, 0.45)
            font.family: w.fam
            font.pixelSize: 14 * w.s
        }
    }

    Image {
        id: img
        anchors.fill: parent
        source: w.source
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        mipmap: true
        cache: false
        sourceSize.width: Math.ceil(Math.max(w.width, w.height) * 2)
        sourceSize.height: Math.ceil(Math.max(w.width, w.height) * 2)
        visible: status === Image.Ready
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: maskItem
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }

    // Control Center border, like the other cards
    CornerBorder {
        z: 2
        anchors.fill: parent
        cornerR: w.radiusPx
        dark: w.darkGlass
        tint: w.borderTint
        lineW: 0.8
    }
}
