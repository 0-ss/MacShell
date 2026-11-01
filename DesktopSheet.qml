// DesktopSheet — a small glass popup for the desktop (Rename, Quick Preview, Add Folder).
//
// Same glass as the Dock's right-click menu (DockGlassPanel) but without the pointer tail, with a title and a grey round "x" button.
// It grows out of a point (the icon it belongs to) when it opens and shrinks back into it when it closes.
//
//   sheet.open = true / false      show / hide (animated)
//   sheet.ox / sheet.oy            the point (in the sheet's own coordinates) it grows from
//   closeRequested()               the x button was pressed
// Children go into the body area below the title: contentW x contentH (both in "design pixels", scaled by k).
import QtQuick

Item {
    id: sh
    property bool open: false
    property bool warm: false               // set briefly after start-up: builds the glass once, invisibly, so the first real open is not a hitch
    property string title: ""
    property var backdrop: null
    property bool dark: true
    property string fam: "Open Runde"
    property real k: 1
    property real contentW: 320
    property real contentH: 60
    property real ox: width / 2
    property real oy: height / 2
    signal closeRequested()

    default property alias content: body.data
    readonly property real headH: Math.round(46 * k)
    readonly property color fg: dark ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(0, 0, 0, 0.86)
    readonly property color fg2: dark ? Qt.rgba(1, 1, 1, 0.58) : Qt.rgba(0, 0, 0, 0.52)

    width: Math.round(contentW * k)
    height: panel.height

    // Two phases so the animation itself never stutters:
    //   1. on open the sheet is built and its glass captured while practically invisible (opacity 0.01: it must still render, or the
    //      capture would stay empty). That is where the heavy work (blur, masks, canvases) happens, and nobody sees a frame drop.
    //   2. once the glass is frozen (panel.hold) it fades in. Fade only: scaling / moving makes the glass re-capture every frame.
    property real prog: (open && panel.hold) ? 1 : 0
    Behavior on prog {
        NumberAnimation { duration: sh.open ? 180 : 120; easing.type: Easing.OutCubic }
    }
    visible: open || warm || prog > 0.01
    opacity: Math.max((open || warm) ? 0.01 : 0, prog)

    DockGlassPanel {
        id: panel
        backdrop: sh.backdrop
        live: true              // the blur objects stay built (shaders compiled, textures allocated); the capture itself only runs while visible
        frozen: sh.visible      // one blur snapshot when it opens, then no re-capture: not real-time
        dark: sh.dark
        k: sh.k
        radius: 24 * sh.k
        tailW: 0; tailH: 0; tailTipR: 0
        width: sh.width
        bodyH: sh.headH + Math.round(sh.contentH * sh.k)

        Text {
            x: Math.round(18 * sh.k)
            y: Math.round((sh.headH - height) / 2) + 1
            width: closeBtn.x - x - Math.round(10 * sh.k)
            elide: Text.ElideMiddle
            text: sh.title
            color: sh.fg
            font.family: sh.fam
            font.pixelSize: Math.max(10, Math.round(14 * sh.k))
            font.weight: Font.DemiBold
        }
        // grey round close button
        Rectangle {
            id: closeBtn
            width: Math.round(24 * sh.k); height: width; radius: width / 2
            x: panel.width - width - Math.round(12 * sh.k)
            y: Math.round((sh.headH - height) / 2)
            color: closeMa.containsMouse ? (sh.dark ? Qt.rgba(1, 1, 1, 0.32) : Qt.rgba(0, 0, 0, 0.22))
                                         : (sh.dark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.13))
            Rectangle {
                anchors.centerIn: parent
                width: Math.round(10 * sh.k); height: Math.max(1.5, 1.7 * sh.k); radius: height / 2
                rotation: 45
                color: sh.dark ? Qt.rgba(1, 1, 1, 0.88) : Qt.rgba(0, 0, 0, 0.62)
            }
            Rectangle {
                anchors.centerIn: parent
                width: Math.round(10 * sh.k); height: Math.max(1.5, 1.7 * sh.k); radius: height / 2
                rotation: -45
                color: sh.dark ? Qt.rgba(1, 1, 1, 0.88) : Qt.rgba(0, 0, 0, 0.62)
            }
            MouseArea {
                id: closeMa
                anchors.fill: parent
                hoverEnabled: true
                onClicked: sh.closeRequested()
            }
        }
        // content area
        Item {
            id: body
            x: 0; y: sh.headH
            width: panel.width
            height: Math.round(sh.contentH * sh.k)
        }
    }
}
