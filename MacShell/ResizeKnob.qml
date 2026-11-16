// ResizeKnob — the little corner handle shown while editing widgets / Control Center tiles (iPadOS / macOS Tahoe style):
// a thick white arc that hugs the bottom-right corner of the thing it resizes. Drag it to change the size.
//
// Put it as a child of the item to resize; it anchors itself to that item's bottom-right corner. It only reports the pointer
// (in `ref` coordinates) and the owner decides what size that means:
//   dragStarted()        the knob was grabbed
//   dragMoved(x, y)      pointer position in `ref` (default: the parent's parent chain root via mapToItem(ref, ...))
//   dragEnded()          released (or cancelled)
import QtQuick

Item {
    id: k
    property real cornerR: 28              // corner radius of the thing being resized: the arc runs concentric with it
    property real inset: 1                 // distance of the arc's centre line from the edge (small = sits right on the edge, 0 = centred on it)
    property real pad: 6                   // extra room past the corner so an arc that sits on / over the edge isn't clipped
    property real lineW: 6.5
    property real sweep: 0.7               // fraction of the quarter-circle that is drawn, centred on the diagonal (1 = the whole corner, 0.5 = half as long)
    property real reach: 0                 // how far the arc continues in a straight line past the curve, on both sides
    property color color: Qt.rgba(1, 1, 1, 0.65)     // translucent white, the same as the Control Center remove (x) badge
    property Item ref: null                // coordinate space for dragMoved (usually the layer that holds the item)
    property bool active: true             // false: hidden, takes no clicks
    property real hitInset: 0              // with tightHit: shrinks the clickable box by this many px on every side
    property bool tightHit: false          // true: the clickable area is exactly the drawn arc (its bounding box), not the whole corner square
    readonly property bool pressed: ma.pressed
    readonly property bool hovered: ma.containsMouse

    signal dragStarted()
    signal dragMoved(real x, real y)
    signal dragEnded()

    visible: active
    anchors.right: parent ? parent.right : undefined
    anchors.bottom: parent ? parent.bottom : undefined
    anchors.rightMargin: -pad
    anchors.bottomMargin: -pad
    // room for the curve + the two straight ends + the stroke
    width: Math.ceil(cornerR + reach + lineW + pad)
    height: width
    z: 70
    transformOrigin: Item.BottomRight
    opacity: active ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 140 } }

    // bounding box of the drawn arc (canvas coordinates), used as the hit box when tightHit is on
    readonly property real _sw: Math.max(0.05, Math.min(1, sweep))
    readonly property real _a0: Math.PI / 4 - (Math.PI / 2) * _sw / 2
    readonly property real _a1: Math.PI / 4 + (Math.PI / 2) * _sw / 2
    readonly property real _R: Math.max(2, cornerR)
    readonly property real _r: Math.max(1, _R - inset)
    readonly property real _rr: Math.min(reach, _R)
    readonly property bool _full: _sw >= 0.999 && reach > 0
    readonly property real _cx: width - pad - _R
    readonly property real _cy: height - pad - _R
    readonly property real hitX: (_full ? _cx - _rr : _cx + _r * Math.cos(_a1)) - lineW / 2
    readonly property real hitY: (_full ? _cy - _rr : _cy + _r * Math.sin(_a0)) - lineW / 2
    readonly property real hitR: (_full ? width - pad - inset : _cx + _r * Math.cos(_a0)) + lineW / 2
    readonly property real hitB: (_full ? height - pad - inset : _cy + _r * Math.sin(_a1)) + lineW / 2

    onCornerRChanged: cv.requestPaint()
    onInsetChanged: cv.requestPaint()
    onLineWChanged: cv.requestPaint()
    onReachChanged: cv.requestPaint()
    onSweepChanged: cv.requestPaint()
    onPadChanged: cv.requestPaint()
    onColorChanged: cv.requestPaint()

    Canvas {
        id: cv
        anchors.fill: parent
        antialiasing: true
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            var w = width - k.pad, h = height - k.pad;     // (w, h) is the widget's corner; the canvas reaches `pad` px past it
            var R = Math.max(2, k.cornerR);
            var line = k.inset;                                // centre line of the stroke, from the widget edge
            var r = Math.max(1, R - line);                     // radius of the arc (concentric with the corner)
            var cx = w - R, cy = h - R;                        // centre of the corner circle
            var x = w - line, y = h - line;                    // the two straight runs
            var reach = Math.min(k.reach, R);
            ctx.lineCap = "round";
            ctx.lineJoin = "round";
            // soft dark shadow first, so the white arc stays readable on a bright widget
            ctx.shadowColor = "rgba(0, 0, 0, 0.38)";
            ctx.shadowBlur = 4;
            ctx.shadowOffsetX = 0;
            ctx.shadowOffsetY = 1;
            ctx.strokeStyle = k.color;
            ctx.lineWidth = k.lineW;
            var sw = Math.max(0.05, Math.min(1, k.sweep));
            var a0 = Math.PI / 4 - (Math.PI / 2) * sw / 2;     // the arc is centred on the corner's diagonal
            var a1 = Math.PI / 4 + (Math.PI / 2) * sw / 2;
            ctx.beginPath();
            if (sw >= 0.999 && reach > 0) {
                ctx.moveTo(x, cy - reach);
                ctx.lineTo(x, cy);
                ctx.arc(cx, cy, r, 0, Math.PI / 2, false);
                ctx.lineTo(cx - reach, y);
            } else {
                ctx.arc(cx, cy, r, a0, a1, false);
            }
            ctx.stroke();
        }
    }

    MouseArea {
        id: ma
        x: k.tightHit ? k.hitX + k.hitInset : -7
        y: k.tightHit ? k.hitY + k.hitInset : -7
        width: k.tightHit ? Math.max(6, k.hitR - k.hitX - 2 * k.hitInset) : k.width + 14
        height: k.tightHit ? Math.max(6, k.hitB - k.hitY - 2 * k.hitInset) : k.height + 14
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.SizeFDiagCursor
        function report(mx, my) {
            var p = k.ref ? ma.mapToItem(k.ref, mx, my) : Qt.point(mx, my);
            k.dragMoved(p.x, p.y);
        }
        onPressed: mouse => { k.dragStarted(); report(mouse.x, mouse.y); }
        onPositionChanged: mouse => { if (pressed) report(mouse.x, mouse.y); }
        onReleased: k.dragEnded()
        onCanceled: k.dragEnded()
    }
}
