import QtQuick
import QtQuick.Effects

Canvas {
    id: g
    property string kind: "play"
    property color col: "white"
    onKindChanged: requestPaint()
    onColChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        var c = getContext("2d"), W = width, H = height;
        c.reset();
        c.clearRect(0, 0, W, H);
        c.fillStyle = col;
        c.strokeStyle = col;
        c.lineJoin = "round";
        c.lineCap = "round";
        // rounded triangle pointing right (base at x0, tip at x1)
        function tri(x0, x1, y0, y1, lw) {
            c.lineWidth = lw;
            c.beginPath(); c.moveTo(x0, y0); c.lineTo(x1, (y0 + y1) / 2); c.lineTo(x0, y1); c.closePath();
            c.fill(); c.stroke();
        }
        function arrowHead(x, y, dir, sz) {     // small filled head pointing left / right
            c.beginPath(); c.moveTo(x, y); c.lineTo(x - dir * sz, y - sz * 0.8); c.lineTo(x - dir * sz, y + sz * 0.8); c.closePath();
            c.fill(); c.stroke();
        }
        if (kind === "play") {
            tri(0.16 * W, 0.90 * W, 0.12 * H, 0.88 * H, 0.10 * W);
        } else if (kind === "pause") {
            c.lineWidth = 0.08 * W;
            c.beginPath(); c.rect(0.20 * W, 0.12 * H, 0.22 * W, 0.76 * H); c.fill(); c.stroke();
            c.beginPath(); c.rect(0.58 * W, 0.12 * H, 0.22 * W, 0.76 * H); c.fill(); c.stroke();
        } else if (kind === "next") {                    // two triangles pointing right
            tri(0.04 * W, 0.50 * W, 0.08 * H, 0.92 * H, 0.07 * H);
            tri(0.50 * W, 0.96 * W, 0.08 * H, 0.92 * H, 0.07 * H);
        } else if (kind === "prev") {                    // two triangles pointing left
            c.save(); c.translate(W, 0); c.scale(-1, 1);
            tri(0.04 * W, 0.50 * W, 0.08 * H, 0.92 * H, 0.07 * H);
            tri(0.50 * W, 0.96 * W, 0.08 * H, 0.92 * H, 0.07 * H);
            c.restore();
        } else if (kind === "shuffle") {
            c.lineWidth = 0.11 * H;
            c.beginPath();
            c.moveTo(0.03 * W, 0.26 * H); c.lineTo(0.22 * W, 0.26 * H);
            c.bezierCurveTo(0.46 * W, 0.26 * H, 0.50 * W, 0.74 * H, 0.74 * W, 0.74 * H); c.lineTo(0.80 * W, 0.74 * H);
            c.stroke();
            c.beginPath();
            c.moveTo(0.03 * W, 0.74 * H); c.lineTo(0.22 * W, 0.74 * H);
            c.bezierCurveTo(0.46 * W, 0.74 * H, 0.50 * W, 0.26 * H, 0.74 * W, 0.26 * H); c.lineTo(0.80 * W, 0.26 * H);
            c.stroke();
            c.lineWidth = 0.05 * H;
            arrowHead(0.99 * W, 0.26 * H, 1, 0.22 * W);
            arrowHead(0.99 * W, 0.74 * H, 1, 0.22 * W);
        } else if (kind === "repeat") {
            c.lineWidth = 0.11 * H;
            c.beginPath();                                   // top run, heading right
            c.moveTo(0.14 * W, 0.58 * H); c.lineTo(0.14 * W, 0.44 * H);
            c.quadraticCurveTo(0.14 * W, 0.20 * H, 0.36 * W, 0.20 * H); c.lineTo(0.70 * W, 0.20 * H);
            c.stroke();
            c.beginPath();                                   // bottom run, heading left
            c.moveTo(0.86 * W, 0.42 * H); c.lineTo(0.86 * W, 0.56 * H);
            c.quadraticCurveTo(0.86 * W, 0.80 * H, 0.64 * W, 0.80 * H); c.lineTo(0.30 * W, 0.80 * H);
            c.stroke();
            c.lineWidth = 0.05 * H;
            arrowHead(0.90 * W, 0.20 * H, 1, 0.20 * W);
            arrowHead(0.10 * W, 0.80 * H, -1, 0.20 * W);
        } else if (kind === "lyrics") {                      // speech bubble with two lines of text
            c.lineWidth = 0.085 * H;
            var bx = 0.06 * W, by = 0.10 * H, bw = 0.88 * W, bh = 0.66 * H, br = 0.18 * H;
            c.beginPath();
            c.moveTo(bx + br, by); c.lineTo(bx + bw - br, by);
            c.quadraticCurveTo(bx + bw, by, bx + bw, by + br); c.lineTo(bx + bw, by + bh - br);
            c.quadraticCurveTo(bx + bw, by + bh, bx + bw - br, by + bh); c.lineTo(0.42 * W, by + bh);
            c.lineTo(0.20 * W, 0.94 * H); c.lineTo(0.24 * W, by + bh);
            c.lineTo(bx + br, by + bh);
            c.quadraticCurveTo(bx, by + bh, bx, by + bh - br); c.lineTo(bx, by + br);
            c.quadraticCurveTo(bx, by, bx + br, by);
            c.closePath();
            c.stroke();
            c.beginPath(); c.moveTo(0.24 * W, 0.34 * H); c.lineTo(0.76 * W, 0.34 * H); c.stroke();
            c.beginPath(); c.moveTo(0.24 * W, 0.54 * H); c.lineTo(0.56 * W, 0.54 * H); c.stroke();
        } else if (kind === "waves") {                       // the sound-wave mark at the top right
            c.lineWidth = 0.13 * H;
            for (var n = 0; n < 3; n++) {
                c.beginPath();
                var amp = (0.34 - n * 0.06) * H, ph = n * 0.9, x0 = (0.02 + n * 0.12) * W;
                for (var x = x0; x <= W * 0.98; x += 1) {
                    var t = (x - x0) / (W * 0.98 - x0) * Math.PI * 2.2 + ph;
                    var y = 0.5 * H + amp * Math.sin(t) * Math.sin(Math.min(1, (x - x0) / (0.25 * W)) * Math.PI / 2);
                    if (x === x0) c.moveTo(x, y); else c.lineTo(x, y);
                }
                c.stroke();
            }
        }
    }
}
