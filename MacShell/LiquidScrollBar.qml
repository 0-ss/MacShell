// LiquidScrollBar — macOS-style overlay scroller for any Flickable / ListView / GridView.
// It fades in while the view scrolls or the pointer is near, and fades out a moment after. Hovering widens it into
// a glass capsule (clear with a bright rim for Liquid Glass, frosted for Frosted / Blur, solid for Opaque); drag it to scroll.
//   LiquidScrollBar { flick: myList; anchors { right: myList.right; top: myList.top; bottom: myList.bottom } }
import QtQuick

Item {
    id: sb
    property Flickable flick: null
    property string material: "liquid"
    property bool dark: true
    width: 16
    readonly property real contentH: flick ? Math.max(flick.contentHeight, 1) : 1
    readonly property real ratio: flick ? Math.min(1, flick.height / contentH) : 1
    readonly property real thumbH: Math.max(32, ratio * height)
    readonly property real travel: Math.max(1, contentH - (flick ? flick.height : 0))
    readonly property real frac: flick ? Math.max(0, Math.min(1, (flick.contentY - flick.originY) / travel)) : 0
    // stays hoverable while faded out, so moving the pointer to the edge brings it back
    visible: flick !== null && flick.visible && ratio < 0.999

    readonly property bool hot: ma.containsMouse || ma.pressed
    property bool awake: false
    opacity: awake || hot ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: sb.opacity < 0.5 ? 160 : 420; easing.type: Easing.OutCubic } }
    Timer { id: sleep; interval: 900; onTriggered: sb.awake = false }
    Connections {
        target: sb.flick
        function onContentYChanged() { sb.awake = true; sleep.restart(); }
    }

    property real glass: hot ? 1 : 0
    Behavior on glass { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    readonly property bool liquid: material === "liquid" || material === "custom"
    readonly property real lens: material === "opaque" ? 0 : glass

    Rectangle {
        id: thumb
        width: 6 + 5 * sb.glass
        x: sb.width - width - 3
        y: sb.frac * (sb.height - sb.thumbH)
        height: sb.thumbH
        radius: width / 2
        readonly property real ink: sb.dark ? 1 : 0
        color: sb.liquid ? Qt.rgba(ink, ink, ink, 0.42 - 0.3 * sb.lens)
                         : Qt.rgba(ink, ink, ink, 0.42 + (sb.material === "opaque" ? 0.15 : 0) * sb.glass)
        border.width: sb.lens > 0.01 ? 1 : 0
        border.color: Qt.rgba(1, 1, 1, (sb.liquid ? 0.8 : 0.45) * sb.lens)
        // specular strip down the left edge, like light catching a glass rod
        Rectangle {
            visible: sb.lens > 0.01
            opacity: sb.lens
            x: 1.5; y: 4; width: parent.width * 0.42; height: parent.height - 8; radius: width / 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.55) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
            }
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        property real grab: 0
        function scrollTo(y) {
            if (!sb.flick) return;
            var f = Math.max(0, Math.min(1, (y - grab) / Math.max(1, sb.height - sb.thumbH)));
            sb.flick.contentY = sb.flick.originY + f * sb.travel;
        }
        onPressed: mouse => {
            // on the thumb: keep the grab point; on the track: jump so the thumb centres on the pointer
            grab = (mouse.y >= thumb.y && mouse.y <= thumb.y + thumb.height) ? mouse.y - thumb.y : sb.thumbH / 2;
            scrollTo(mouse.y);
        }
        onPositionChanged: mouse => { if (pressed) scrollTo(mouse.y); }
        onWheel: wheel => { wheel.accepted = false; }
    }
}
