// DesktopIcon — one file / folder / app on the desktop. Purely visual: all mouse handling lives in Desktop.qml.
//
// Selected look: a frosted, translucent grey rounded square behind the icon with a light rim (no accent colour).
import QtQuick

Item {
    id: ic

    property var item: null              // { name, path, isDir, isApp, kind }
    property string source: ""           // resolved icon image
    property string fam: "Open Runde"
    property int iconSize: 48
    property bool selected: false
    property bool dropTarget: false      // another icon is being dragged over this one
    property bool dragging: false

    readonly property int pad: 10
    readonly property int boxSize: iconSize + 2 * pad
    // pictures (screenshots) are shown as a short landscape thumbnail instead of a square one
    readonly property bool isPicture: item !== null && item.kind === "Image"
    readonly property int iconH: isPicture ? Math.round(iconSize * 0.6) : iconSize
    readonly property int boxH: iconH + 2 * pad

    opacity: dragging ? 0.82 : 1.0

    // ── selection / drop highlight ──
    Item {
        id: box
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        width: ic.boxSize; height: ic.boxH
        opacity: (ic.selected || ic.dropTarget) ? 1 : 0

        // soft dark hairline just outside the rim, so the highlight stays readable on bright wallpapers
        Rectangle {
            anchors.fill: parent; anchors.margins: -1
            radius: 19
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.16)
        }
        // frosted grey body
        Rectangle {
            anchors.fill: parent
            radius: 18
            color: ic.selected ? Qt.rgba(0.80, 0.82, 0.82, 0.32) : Qt.rgba(0.80, 0.82, 0.82, 0.22)
            border.width: 1.5
            border.color: Qt.rgba(1, 1, 1, ic.selected ? 0.42 : 0.30)
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.07) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.00) }
            }
        }
    }

    // ── the icon itself: app icon, folder, image thumbnail or a plain document ──
    Image {
        id: img
        anchors.horizontalCenter: parent.horizontalCenter
        y: ic.pad
        width: ic.iconSize; height: ic.iconH
        asynchronous: true; cache: true; smooth: true; mipmap: true
        fillMode: ic.item && ic.item.kind === "Image" ? Image.PreserveAspectCrop : Image.PreserveAspectFit
        sourceSize: Qt.size(ic.iconSize * 2, ic.iconSize * 2)
        source: ic.source
    }

    // ── name ──
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: ic.boxH + 3
        width: parent.width - 8
        horizontalAlignment: Text.AlignHCenter
        maximumLineCount: 2; wrapMode: Text.Wrap; elide: Text.ElideMiddle
        text: ic.item ? (ic.item.isApp ? ic.item.name.replace(/\.desktop$/i, "") : ic.item.name) : ""
        color: "white"; font.family: ic.fam; font.pixelSize: 11
        style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.55)
    }
}
