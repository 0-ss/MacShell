import QtQuick

// Control Center border: a thin, slightly translucent line that fades out at the top-right and bottom-left corners, in a
// brighter shade of the background colour (root.menuBorderColor follows the wallpaper, so it is dynamic). Drawn in QML, so
// it doesn't depend on the glass shader being recompiled.
Item {
    id: cb
    property color tint: "#8A9AB5"
    property bool dark: true
    property real cornerR: 14
    property real lineW: 0.8
    property real amount: 1
    property bool fade: true            // true = Control Center look (fades out at top-right / bottom-left); false = even all the way round
    Behavior on tint { ColorAnimation { duration: 450; easing.type: Easing.OutCubic } }
    onTintChanged: cv.requestPaint()
    onDarkChanged: cv.requestPaint()
    onCornerRChanged: cv.requestPaint()
    onLineWChanged: cv.requestPaint()
    onAmountChanged: cv.requestPaint()
    onFadeChanged: cv.requestPaint()
    Canvas {
        id: cv
        anchors.fill: parent
        antialiasing: true
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            var w = width, h = height, lw = cb.lineW;
            if (w < 2 * lw || h < 2 * lw || cb.amount <= 0) return;
            // same colour as the background, but brighter (white mixed in, a bit more on light panels)
            var k = cb.dark ? 0.42 : 0.55;
            var r0 = cb.tint.r + (1 - cb.tint.r) * k, g0 = cb.tint.g + (1 - cb.tint.g) * k, b0 = cb.tint.b + (1 - cb.tint.b) * k;
            var a = Math.min(1, 0.72 * cb.amount);      // a bit translucent
            var cx = w / 2, cy = h / 2, d = (w + h) / 4;
            var g = ctx.createLinearGradient(cx + d, cy - d, cx - d, cy + d);      // top-right end -> bottom-left end
            if (cb.fade) {
                g.addColorStop(0.00, Qt.rgba(r0, g0, b0, 0));
                g.addColorStop(0.12, Qt.rgba(r0, g0, b0, a * 0.25));
                g.addColorStop(0.32, Qt.rgba(r0, g0, b0, a));
                g.addColorStop(0.68, Qt.rgba(r0, g0, b0, a));
                g.addColorStop(0.88, Qt.rgba(r0, g0, b0, a * 0.25));
                g.addColorStop(1.00, Qt.rgba(r0, g0, b0, 0));
            } else {                                                           // same colour on every corner
                g.addColorStop(0.0, Qt.rgba(r0, g0, b0, a));
                g.addColorStop(1.0, Qt.rgba(r0, g0, b0, a));
            }
            var x = lw / 2, y = lw / 2, ww = w - lw, hh = h - lw;
            var r = Math.max(0, Math.min(cb.cornerR - lw / 2, ww / 2, hh / 2));
            ctx.beginPath();
            ctx.moveTo(x + r, y);
            ctx.lineTo(x + ww - r, y);
            ctx.arcTo(x + ww, y, x + ww, y + r, r);
            ctx.lineTo(x + ww, y + hh - r);
            ctx.arcTo(x + ww, y + hh, x + ww - r, y + hh, r);
            ctx.lineTo(x + r, y + hh);
            ctx.arcTo(x, y + hh, x, y + hh - r, r);
            ctx.lineTo(x, y + r);
            ctx.arcTo(x, y, x + r, y, r);
            ctx.closePath();
            ctx.strokeStyle = g;
            ctx.lineWidth = lw;
            ctx.stroke();
        }
    }
}
