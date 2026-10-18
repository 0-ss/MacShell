// macOS pop-up button (System Settings style): right-aligned value + grey chevrons; opens a menu ON the button with
// the current item lined up on it, a check mark, accent hover, and a fade/scale animation
import QtQuick
import QtQuick.Controls
import QtQuick.Effects

Item {
    id: pu
    required property var t
    property var model: []
    property int current: 0
    signal picked(int index)
    width: 220; height: 26
    Rectangle {
        anchors.fill: parent; radius: 6
        color: puMa.containsMouse || menu.visible ? pu.t.hover : "transparent"
        Behavior on color { ColorAnimation { duration: 160 } }
    }
    Text {
        anchors.right: chev.left; anchors.rightMargin: 7; anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 30; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
        text: pu.model[pu.current] !== undefined ? pu.model[pu.current] : ""
        color: pu.t.text; font.family: pu.t.fam; font.pixelSize: 13
    }
    Canvas {
        id: chev
        anchors.right: parent.right; anchors.rightMargin: 7; anchors.verticalCenter: parent.verticalCenter
        width: 8; height: 12
        property color ink: pu.t.text2
        onInkChanged: requestPaint()
        onPaint: {
            var c = getContext("2d"); c.reset();
            c.strokeStyle = ink; c.lineWidth = 1.4; c.lineCap = "round"; c.lineJoin = "round";
            c.beginPath(); c.moveTo(1, 4.2); c.lineTo(4, 1.2); c.lineTo(7, 4.2); c.stroke();
            c.beginPath(); c.moveTo(1, 7.8); c.lineTo(4, 10.8); c.lineTo(7, 7.8); c.stroke();
        }
    }
    function openMenu() { menu.open(); }
    MouseArea { id: puMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: menu.open() }

    Popup {
        id: menu
        readonly property real rowH: 26
        width: Math.max(pu.width, 180)
        x: pu.width - width
        // macOS: the current item sits right on the button; if that would leave the window, the menu shifts to fit,
        // and a menu taller than the window scrolls (no separate popup window: those fought Hyprland's pointer grabs)
        // Qt keeps the popup inside the window (8 px margin): it shifts up and, if still too tall, shrinks — the list scrolls
        margins: 8
        height: pu.model.length * rowH + 12
        y: -(6 + pu.current * rowH)
        padding: 6
        modal: false; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: 320; easing.type: Easing.OutQuint }
            }
        }
        exit: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; to: 0; duration: 180; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; to: 0.97; duration: 180; easing.type: Easing.OutCubic }
            }
        }
        background: Item {
            RectangularShadow { anchors.fill: parent; radius: 10; blur: 22; offset.y: 6; color: Qt.rgba(0, 0, 0, 0.35) }
            Rectangle {
                anchors.fill: parent; radius: 10
                color: pu.t.dark ? Qt.rgba(0.16, 0.16, 0.18, 0.985) : Qt.rgba(0.98, 0.98, 0.99, 0.99)
                border.width: 1; border.color: pu.t.dark ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(0, 0, 0, 0.10)
            }
        }
        contentItem: Flickable {
            clip: true
            contentHeight: menuCol.height
            boundsBehavior: Flickable.StopAtBounds
            Component.onCompleted: contentY = Math.max(0, Math.min(contentHeight - height, (pu.current - 2) * menu.rowH))
        Column {
            id: menuCol
            Repeater {
                model: pu.model
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width: menu.width - 12; height: menu.rowH; radius: 6
                    color: rowMa.containsMouse ? pu.t.accent : "transparent"
                    Behavior on color { ColorAnimation { duration: 90 } }
                    Text {
                        x: 8; anchors.verticalCenter: parent.verticalCenter
                        text: "\u2713"; visible: row.index === pu.current
                        color: rowMa.containsMouse ? "white" : pu.t.text; font.pixelSize: 12; font.bold: true
                    }
                    Text {
                        x: 26; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 34; elide: Text.ElideRight
                        text: row.modelData
                        color: rowMa.containsMouse ? "white" : pu.t.text; font.family: pu.t.fam; font.pixelSize: 13
                    }
                    MouseArea {
                        id: rowMa; anchors.fill: parent; hoverEnabled: true
                        onClicked: { menu.close(); if (row.index !== pu.current) pu.picked(row.index); }
                    }
                }
            }
        }
        }
    }
}
