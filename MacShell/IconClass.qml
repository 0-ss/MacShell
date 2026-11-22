import QtQuick
Canvas {
    id: ic
    property Image icon: null
    readonly property bool ready: icon !== null && icon.status === Image.Ready
    property real art: 1
    property color dom: Qt.rgba(0.22, 0.22, 0.24, 1)
    property bool proper: false
    property bool square: false
    property real aspect: 1
    property real corner: 0.245
    property real power: 2.0
    readonly property real fit: {
        if (proper || square) return 1;
        var h = 0.47;
        var px = 0.407;
        var py = 0.407 * aspect;
        var s = 1;
        if (power > 2.01) {
            s = h / Math.pow(Math.pow(px, power) + Math.pow(py, power), 1 / power);
        } else {
            var r = Math.max(Math.min(corner, 0.5) - 0.03, 0);
            var c = h - r;
            if (px > c && py > c) {
                var a = px * px + py * py;
                var b = -2 * c * (px + py);
                var k = 2 * c * c - r * r;
                s = (-b + Math.sqrt(Math.max(b * b - 4 * a * k, 0))) / (2 * a);
            }
        }
        return Math.min(1, s);
    }
    width: 32
    height: 32
    opacity: 0
    renderTarget: Canvas.Image
    onReadyChanged: {
        if (ready) {
            requestPaint();
        } else {
            art = 1;
            dom = Qt.rgba(0.22, 0.22, 0.24, 1);
            proper = false;
            square = false;
            aspect = 1;
        }
    }
    onAvailableChanged: if (available && ready) requestPaint()
    onPaint: {
        if (!ready) return;
        var N = 32;
        var ctx = getContext("2d");
        ctx.clearRect(0, 0, N, N);
        ctx.drawImage(icon, 0, 0, N, N);
        var d = ctx.getImageData(0, 0, N, N).data;
        var opaque = 0, x0 = N, x1 = -1, y0 = N, y1 = -1;
        for (var y = 0; y < N; y++) {
            for (var x = 0; x < N; x++) {
                if (d[(y * N + x) * 4 + 3] >= 64) {
                    opaque++;
                    if (x < x0) x0 = x;
                    if (x > x1) x1 = x;
                    if (y < y0) y0 = y;
                    if (y > y1) y1 = y;
                }
            }
        }
        if (opaque === 0) return;
        var bw = x1 - x0 + 1, bh = y1 - y0 + 1;
        var fill = opaque / (bw * bh);
        var corner = Math.max(d[(y0 * N + x0) * 4 + 3], d[(y0 * N + x1) * 4 + 3], d[(y1 * N + x0) * 4 + 3], d[(y1 * N + x1) * 4 + 3]);
        var squareish = Math.abs(bw - bh) <= 2;
        art = Math.max(bw, bh) / N;
        aspect = Math.min(bw, bh) / Math.max(bw, bh);
        proper = squareish && fill >= 0.90 && fill <= 0.985 && corner < 100;
        square = squareish && fill > 0.985 && corner >= 100 && bw >= 0.9 * N;
        var useEdge = fill >= 0.7;
        var cnt = {};
        var best = 0;
        var bestKey = "";
        for (var j = 0; j < N; j++) {
            for (var i = 0; i < N; i++) {
                var p = (j * N + i) * 4;
                if (d[p + 3] < 200) continue;
                if (useEdge) {
                    var edge = i === 0 || j === 0 || i === N - 1 || j === N - 1
                        || d[p - 4 + 3] < 128 || d[p + 4 + 3] < 128 || d[p - N * 4 + 3] < 128 || d[p + N * 4 + 3] < 128;
                    if (!edge) continue;
                }
                var key = "" + (d[p] >> 4) + "," + (d[p + 1] >> 4) + "," + (d[p + 2] >> 4);
                var e = cnt[key];
                if (!e) { e = { n: 0, r: 0, g: 0, b: 0 }; cnt[key] = e; }
                e.n++; e.r += d[p]; e.g += d[p + 1]; e.b += d[p + 2];
                if (e.n > best) { best = e.n; bestKey = key; }
            }
        }
        if (best > 0) {
            var m = cnt[bestKey];
            dom = Qt.rgba(m.r / m.n / 255, m.g / m.n / 255, m.b / m.n / 255, 1);
        }
    }
}
