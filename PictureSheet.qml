// PictureSheet — Quick Preview for pictures (screenshots, photos).
//
// Looks like the other desktop sheets (title + the grey round "x" button) but is built to stay cheap at any size: a solid panel,
// a layered shadow made of plain rounded rectangles and a picture decoded at the size it is shown. It deliberately does NOT use
// (live) DockGlassPanel: that one paints its shadow / outline on CPU canvases and runs a live blurred backdrop, which is fine for a
// 400 px menu but made a screenshot-sized sheet stutter badly.
//
//   sheet.source           file:// url of the picture (set it, wait for pictureReady, then open)
//   sheet.open = true / false
//   sheet.maxW / maxH      the most the picture may take on screen, in pixels (the decoder never produces more than this)
//   pictureReady() / pictureFailed()
//   closeRequested()       the x button was pressed
import QtQuick

Item {
    id: ps
    property bool open: false
    property bool warm: false               // set briefly after start-up: builds the glass once, invisibly, so the first real open is not a hitch
    property var item: null                 // { name, path, ... }
    property string source: ""
    property bool dark: true
    property var backdrop: null             // desktop glass backdrop (frozen snapshot, not live)
    property string fam: "Open Runde"
    property real k: 1
    property real maxW: 900
    property real maxH: 600
    signal closeRequested()
    signal pictureReady()
    signal pictureFailed()

    readonly property int status: img.status
    readonly property bool loaded: img.status === Image.Ready
    readonly property string title: item ? item.name : ""
    readonly property real pad: Math.round(14 * k)
    readonly property real headH: Math.round(46 * k)
    readonly property color fg: dark ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(0, 0, 0, 0.86)

    // implicitWidth / implicitHeight are the picture's ORIGINAL size (sourceSize only limits the decoding), so the shown size is
    // worked out here: shrink to fit maxW x maxH, never enlarge, keep the aspect ratio. (Using the implicit size directly made a
    // wide screenshot open as a sheet wider than the screen.)
    readonly property real fit: (img.implicitWidth > 0 && img.implicitHeight > 0)
        ? Math.min(1, Math.max(1, maxW) / img.implicitWidth, Math.max(1, maxH) / img.implicitHeight) : 1
    readonly property real picW: Math.round(img.implicitWidth * fit)
    readonly property real picH: Math.round(img.implicitHeight * fit)
    width: Math.max(Math.round(300 * k), picW + 2 * pad)
    height: headH + picH + pad + Math.round(2 * k)

    // Opens in two phases (see DesktopSheet): built + glass captured while nearly invisible, then a plain fade.
    property real prog: (open && panel.hold) ? 1 : 0
    Behavior on prog {
        NumberAnimation { duration: ps.open ? 180 : 120; easing.type: Easing.OutCubic }
    }
    visible: open || warm || prog > 0.01
    opacity: Math.max((open || warm) ? 0.01 : 0, prog)

    // Liquid glass, but frozen: one blur snapshot when the sheet opens, never re-captured afterwards. No scale animation (a scaled
    // glass re-captures every frame), the sheet only fades.
    DockGlassPanel {
        id: panel
        backdrop: ps.backdrop
        live: true              // the blur objects stay built (shaders compiled, textures allocated); the capture itself only runs while visible
        frozen: ps.visible
        dark: ps.dark
        k: ps.k
        radius: 24 * ps.k
        tailW: 0; tailH: 0; tailTipR: 0
        width: ps.width
        bodyH: ps.height
    }
    // clicks on the sheet itself do not fall through to the "click outside closes" layer
    MouseArea { anchors.fill: parent }

    Text {
        x: Math.round(18 * ps.k)
        y: Math.round((ps.headH - height) / 2) + 1
        width: closeBtn.x - x - Math.round(10 * ps.k)
        elide: Text.ElideMiddle
        text: ps.title
        color: ps.fg
        font.family: ps.fam
        font.pixelSize: Math.max(10, Math.round(14 * ps.k))
        font.weight: Font.DemiBold
    }

    // grey round close button (same as DesktopSheet's)
    Rectangle {
        id: closeBtn
        width: Math.round(24 * ps.k); height: width; radius: width / 2
        x: ps.width - width - Math.round(12 * ps.k)
        y: Math.round((ps.headH - height) / 2)
        color: closeMa.containsMouse ? (ps.dark ? Qt.rgba(1, 1, 1, 0.32) : Qt.rgba(0, 0, 0, 0.22))
                                     : (ps.dark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.13))
        Rectangle {
            anchors.centerIn: parent
            width: Math.round(10 * ps.k); height: Math.max(1.5, 1.7 * ps.k); radius: height / 2
            rotation: 45
            color: ps.dark ? Qt.rgba(1, 1, 1, 0.88) : Qt.rgba(0, 0, 0, 0.62)
        }
        Rectangle {
            anchors.centerIn: parent
            width: Math.round(10 * ps.k); height: Math.max(1.5, 1.7 * ps.k); radius: height / 2
            rotation: -45
            color: ps.dark ? Qt.rgba(1, 1, 1, 0.88) : Qt.rgba(0, 0, 0, 0.62)
        }
        MouseArea {
            id: closeMa
            anchors.fill: parent
            hoverEnabled: true
            onClicked: ps.closeRequested()
        }
    }

    // the picture: decoded at (at most) the size it is shown, so the texture is as small as it can be and needs no mipmaps
    Image {
        id: img
        x: Math.round((ps.width - width) / 2)
        y: ps.headH + Math.round(2 * ps.k)
        width: ps.picW; height: ps.picH
        asynchronous: true
        cache: false
        smooth: true
        mipmap: false
        fillMode: Image.PreserveAspectFit
        sourceSize: Qt.size(Math.max(1, Math.round(ps.maxW)), Math.max(1, Math.round(ps.maxH)))
        source: ps.source
        onStatusChanged: {
            if (status === Image.Ready) ps.pictureReady();
            else if (status === Image.Error) ps.pictureFailed();
        }
    }
    // hairline rim so the picture's edge reads against the panel
    Rectangle {
        x: img.x; y: img.y; width: img.width; height: img.height
        color: "transparent"
        border.width: 1
        border.color: ps.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)
    }
}
