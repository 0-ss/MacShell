// Picker wheel for the Clock app (macOS / iOS time picker): snaps to rows; rows fade and shrink away from the middle.
import QtQuick

ListView {
    id: wh
    property int start: 0
    property var labels: []            // shown text per row
    property int fontPx: 24
    property int align: Text.AlignHCenter
    property color ink: "white"
    property string fam: "Open Runde"
    readonly property int value: currentIndex
    readonly property real rowH: 36
    width: 70; height: rowH * 5
    clip: true
    model: labels.length
    preferredHighlightBegin: height / 2 - rowH / 2
    preferredHighlightEnd: height / 2 + rowH / 2
    highlightRangeMode: ListView.StrictlyEnforceRange
    snapMode: ListView.SnapToItem
    highlightMoveDuration: 260
    boundsBehavior: Flickable.StopAtBounds
    Component.onCompleted: { currentIndex = Math.max(0, Math.min(labels.length - 1, start)); positionViewAtIndex(currentIndex, ListView.Center); }
    delegate: Text {
        required property int index
        width: wh.width; height: wh.rowH
        readonly property real d: Math.abs(y - wh.contentY + height / 2 - wh.height / 2) / wh.rowH
        text: wh.labels[index]
        horizontalAlignment: wh.align; verticalAlignment: Text.AlignVCenter
        color: wh.ink
        opacity: Math.max(0.12, 1 - d * 0.36)
        scale: Math.max(0.8, 1 - d * 0.06)
        font.family: wh.fam; font.pixelSize: wh.fontPx
        font.features: { "tnum": 1 }
        MouseArea { anchors.fill: parent; onClicked: wh.currentIndex = parent.index }
    }
    WheelHandler { onWheel: e => { wh.currentIndex = Math.max(0, Math.min(wh.count - 1, wh.currentIndex + (e.angleDelta.y < 0 ? 1 : -1))); } }
}
