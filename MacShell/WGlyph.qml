// Monochrome glyphs, extracted unchanged from MacShell/MacBar.qml (component Glyph)
import QtQuick

Canvas {
    id: gl
    property string kind: ""
    property color color: "white"
    property real level: 3          // speaker / sun intensity 0..3, wifi bars 0..3, battery 0..100
    property bool flag: false       // "disabled" slash for wifi / bluetooth
    width: 18; height: 18
    antialiasing: true
    onKindChanged: requestPaint()
    onColorChanged: requestPaint()
    onLevelChanged: requestPaint()
    onFlagChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        var s = Math.min(width, height) / 18;
        ctx.scale(s, s);
        ctx.strokeStyle = color;
        ctx.fillStyle = color;
        ctx.lineWidth = 1.5;
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        var PI = Math.PI;
        function circ(x, y, r) { ctx.beginPath(); ctx.arc(x, y, r, 0, PI * 2); }
        function line(x1, y1, x2, y2) { ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke(); }
        function poly(p, fill) {
            ctx.beginPath(); ctx.moveTo(p[0], p[1]);
            for (var i = 2; i < p.length; i += 2) ctx.lineTo(p[i], p[i + 1]);
            if (fill) { ctx.closePath(); ctx.fill(); } else ctx.stroke();
        }
        // filled polygon with rounded corners (radius r), used by the media icons
        function rpoly(p, r) {
            var n = p.length / 2;
            ctx.beginPath();
            ctx.moveTo((p[0] + p[2 * (n - 1)]) / 2, (p[1] + p[2 * (n - 1) + 1]) / 2);
            for (var q = 0; q < n; q++) {
                var x = p[2 * q], y = p[2 * q + 1];
                var nx = p[2 * ((q + 1) % n)], ny = p[2 * ((q + 1) % n) + 1];
                ctx.arcTo(x, y, (x + nx) / 2, (y + ny) / 2, r);
            }
            ctx.closePath(); ctx.fill();
        }
        function rrect(x, y, w, h, r) {
            ctx.beginPath(); ctx.moveTo(x + r, y); ctx.lineTo(x + w - r, y); ctx.arcTo(x + w, y, x + w, y + r, r);
            ctx.lineTo(x + w, y + h - r); ctx.arcTo(x + w, y + h, x + w - r, y + h, r);
            ctx.lineTo(x + r, y + h); ctx.arcTo(x, y + h, x, y + h - r, r);
            ctx.lineTo(x, y + r); ctx.arcTo(x, y, x + r, y, r); ctx.closePath();
        }
        var k = kind, i2;

        if (k === "arch") {
            ctx.translate(0.43, 0);
            ctx.beginPath();
            ctx.moveTo(8.54, 0.45);
            ctx.bezierCurveTo(7.78, 2.32, 7.32, 3.54, 6.48, 5.35);
            ctx.bezierCurveTo(7, 5.9, 7.63, 6.54, 8.67, 7.26);
            ctx.bezierCurveTo(7.56, 6.81, 6.8, 6.35, 6.23, 5.87);
            ctx.bezierCurveTo(5.15, 8.13, 3.45, 11.35, 0, 17.55);
            ctx.bezierCurveTo(2.71, 15.98, 4.81, 15.02, 6.77, 14.65);
            ctx.lineTo(6.64, 13.49);
            ctx.lineTo(6.64, 13.4);
            ctx.bezierCurveTo(6.68, 11.67, 7.59, 10.33, 8.66, 10.42);
            ctx.bezierCurveTo(9.72, 10.51, 10.56, 12, 10.51, 13.73);
            ctx.lineTo(10.4, 14.66);
            ctx.bezierCurveTo(12.34, 15.04, 14.44, 16, 17.13, 17.55);
            ctx.bezierCurveTo(16.6, 16.58, 16.12, 15.71, 15.67, 14.88);
            ctx.bezierCurveTo(14.96, 14.33, 14.22, 13.61, 12.75, 12.86);
            ctx.bezierCurveTo(13.77, 13.13, 14.51, 13.44, 15.08, 13.78);
            ctx.bezierCurveTo(10.24, 6.35, 9.4, 3.82, 8.54, 0.45);
            ctx.closePath();
            ctx.fill();
        } else if (k === "wifi") {
            var radii = [3.8, 7.2, 10.6];
            for (i2 = 0; i2 < 3; i2++) {
                if (i2 >= level) ctx.globalAlpha = 0.3; else ctx.globalAlpha = 1;
                ctx.beginPath(); ctx.arc(9, 14.6, radii[i2], -PI * 0.75, -PI * 0.25); ctx.stroke();
            }
            ctx.globalAlpha = 1;
            circ(9, 14.6, 1.3); ctx.fill();
            if (flag) line(2.5, 2.5, 15.5, 15.5);
        } else if (k === "bluetooth") {
            poly([5, 5.5, 13, 12.5, 9, 16, 9, 2, 13, 5.5, 5, 12.5], false);
            if (flag) line(2.5, 2.5, 15.5, 15.5);
        } else if (k === "airplane") {
            line(9, 1.8, 9, 16.2);
            poly([2, 10.5, 9, 7, 16, 10.5], false);
            poly([6, 15.5, 9, 13.5, 12, 15.5], false);
        } else if (k === "moon") {
            circ(9, 9, 6.8); ctx.fill();
            ctx.globalCompositeOperation = "destination-out";
            circ(12.2, 6.4, 5.6); ctx.fill();
            ctx.globalCompositeOperation = "source-over";
        } else if (k === "sun") {
            var r = 2.2 + level * 0.5, a = r + 2.2, b = a + 1.2 + level * 0.4;
            circ(9, 9, r); ctx.stroke();
            for (i2 = 0; i2 < 8; i2++) {
                var ang = i2 * PI / 4;
                line(9 + Math.cos(ang) * a, 9 + Math.sin(ang) * a, 9 + Math.cos(ang) * b, 9 + Math.sin(ang) * b);
            }
        } else if (k === "nightshift") {
            ctx.beginPath(); ctx.arc(9, 11, 4, PI, PI * 2); ctx.stroke();
            line(2, 11, 16, 11);
            line(5.5, 14.5, 12.5, 14.5);
            line(9, 3.2, 9, 5);
            line(3.6, 5.6, 4.9, 6.9);
            line(14.4, 5.6, 13.1, 6.9);
        } else if (k === "coffee") {
            ctx.beginPath(); ctx.moveTo(3.5, 7.5); ctx.lineTo(12, 7.5); ctx.lineTo(12, 11.5);
            ctx.quadraticCurveTo(12, 15, 7.75, 15); ctx.quadraticCurveTo(3.5, 15, 3.5, 11.5); ctx.closePath(); ctx.stroke();
            ctx.beginPath(); ctx.arc(12.4, 10, 2.2, -PI * 0.5, PI * 0.5); ctx.stroke();
            ctx.beginPath(); ctx.moveTo(6, 2.6); ctx.quadraticCurveTo(7.2, 4, 6, 5.4); ctx.stroke();
            ctx.beginPath(); ctx.moveTo(9.4, 2.6); ctx.quadraticCurveTo(10.6, 4, 9.4, 5.4); ctx.stroke();
        } else if (k === "speaker") {
            poly([2.2, 7, 5.4, 7, 9.2, 3.6, 9.2, 14.4, 5.4, 11, 2.2, 11], true);
            if (level <= 0) {
                line(12, 6.8, 16, 11.2); line(16, 6.8, 12, 11.2);
            } else {
                for (i2 = 1; i2 <= Math.min(2, Math.ceil(level / 1.5)); i2++) {
                    ctx.beginPath(); ctx.arc(9.2, 9, 2.4 + i2 * 3.0, -0.62, 0.62); ctx.stroke();
                }
            }
        } else if (k === "record") {
            circ(9, 9, 7); ctx.stroke();
            circ(9, 9, 3.7); ctx.fill();
        } else if (k === "stoprec") {
            circ(9, 9, 7); ctx.stroke();
            rrect(5.9, 5.9, 6.2, 6.2, 1.6); ctx.fill();
        } else if (k === "mic") {
            rrect(6.5, 1.8, 5, 8.6, 2.5); ctx.stroke();
            ctx.beginPath(); ctx.arc(9, 8.4, 5, 0.12, PI - 0.12, false); ctx.stroke();
            line(9, 13.4, 9, 16); line(6.2, 16, 11.8, 16);
            if (flag) line(2.5, 2.5, 15.5, 15.5);
        } else if (k === "headphones") {
            ctx.beginPath(); ctx.arc(9, 9.8, 5.9, PI, 0, false); ctx.stroke();
            rrect(2.5, 9.4, 3.3, 5.8, 1.5); ctx.fill();
            rrect(12.2, 9.4, 3.3, 5.8, 1.5); ctx.fill();
        } else if (k === "monitor") {
            rrect(2, 3, 14, 9.4, 1.8); ctx.stroke();
            line(6.4, 15.4, 11.6, 15.4); line(9, 12.4, 9, 15.4);
        } else if (k === "camera") {
            rrect(2, 4.6, 14, 9.6, 2.2); ctx.stroke();
            circ(9, 9.4, 2.7); ctx.stroke();
            line(6.8, 3, 11.2, 3);
        } else if (k === "ethernet") {
        // Apple's Ethernet symbol: <···>
        poly([5.2, 4.6, 1.6, 9, 5.2, 13.4], false);
        poly([12.8, 4.6, 16.4, 9, 12.8, 13.4], false);
        circ(6.5, 9, 1.1); ctx.fill();
        circ(9, 9, 1.1); ctx.fill();
        circ(11.5, 9, 1.1); ctx.fill();
        } else if (k === "keyboard") {
            rrect(1.5, 4.5, 15, 9.5, 2); ctx.stroke();
            for (var kx = 0; kx < 4; kx++) { circ(4.6 + kx * 2.9, 7.6, 0.75); ctx.fill(); }
            line(5.5, 11, 12.5, 11);
        } else if (k === "mouse") {
            rrect(5, 2, 8, 14, 4); ctx.stroke();
            line(9, 3.5, 9, 7);
        } else if (k === "trackpad") {
            rrect(2, 3.5, 14, 11, 2.2); ctx.stroke();
            line(2.6, 11.6, 15.4, 11.6); line(9, 11.6, 9, 14);
        } else if (k === "shuffle") {
            // two crossing arrows
            ctx.beginPath(); ctx.moveTo(2, 5.5); ctx.lineTo(5, 5.5); ctx.bezierCurveTo(8.5, 5.5, 9.5, 12.5, 13, 12.5); ctx.lineTo(15.5, 12.5); ctx.stroke();
            ctx.beginPath(); ctx.moveTo(2, 12.5); ctx.lineTo(5, 12.5); ctx.bezierCurveTo(8.5, 12.5, 9.5, 5.5, 13, 5.5); ctx.lineTo(15.5, 5.5); ctx.stroke();
            poly([13.6, 3.4, 16, 5.5, 13.6, 7.6], false);
            poly([13.6, 10.4, 16, 12.5, 13.6, 14.6], false);
        } else if (k === "repeat" || k === "repeat1") {
            // loop: rounded path with an arrow head on each run
            ctx.beginPath(); ctx.moveTo(3, 9); ctx.lineTo(3, 7.5); ctx.arcTo(3, 5, 5.5, 5, 2.5); ctx.lineTo(15, 5); ctx.stroke();
            poly([12.8, 2.9, 15, 5, 12.8, 7.1], false);
            ctx.beginPath(); ctx.moveTo(15, 9); ctx.lineTo(15, 10.5); ctx.arcTo(15, 13, 12.5, 13, 2.5); ctx.lineTo(3, 13); ctx.stroke();
            poly([5.2, 10.9, 3, 13, 5.2, 15.1], false);
            if (k === "repeat1") { ctx.font = "bold 5px sans-serif"; ctx.textAlign = "center"; ctx.fillText("1", 9, 10.8); }
        } else if (k === "play") {
            rpoly([5, 3.2, 15, 9, 5, 14.8], 0.8);
        } else if (k === "pause") {
            rrect(4.2, 3.4, 3.4, 11.2, 0.7); ctx.fill();
            rrect(10.4, 3.4, 3.4, 11.2, 0.7); ctx.fill();
        } else if (k === "next") {
            rpoly([1.8, 4, 8.6, 9, 1.8, 14], 0.6);
            rpoly([9.4, 4, 16.2, 9, 9.4, 14], 0.6);
        } else if (k === "prev") {
            rpoly([16.2, 4, 9.4, 9, 16.2, 14], 0.6);
            rpoly([8.6, 4, 1.8, 9, 8.6, 14], 0.6);
        } else if (k === "note") {
            line(7, 12.5, 7, 3.5); line(7, 3.5, 14, 2.2); line(14, 2.2, 14, 11);
            circ(5.2, 13, 2); ctx.fill();
            circ(12.2, 11.6, 2); ctx.fill();
        } else if (k === "search") {
            circ(7.6, 7.6, 4.8); ctx.stroke();
            line(11.2, 11.2, 15.4, 15.4);
        } else if (k === "cc") {
            rrect(2, 3, 14, 5.2, 2.6); ctx.stroke();
            circ(12.4, 5.6, 1.5); ctx.fill();
            rrect(2, 9.8, 14, 5.2, 2.6); ctx.stroke();
            circ(5.6, 12.4, 1.5); ctx.fill();
        } else if (k === "volume") {
            poly([2.2, 7, 5.4, 7, 9.2, 3.6, 9.2, 14.4, 5.4, 11, 2.2, 11], true);
            ctx.beginPath(); ctx.arc(9.2, 9, 4.4, -0.62, 0.62); ctx.stroke();
            ctx.beginPath(); ctx.arc(9.2, 9, 7.4, -0.62, 0.62); ctx.stroke();
        } else if (k === "bolt") {
            poly([10, 1.5, 4.5, 10, 8.4, 10, 7.6, 16.5, 13.5, 7.6, 9.6, 7.6], true);
        } else if (k === "appstore") {
            line(9, 2.8, 3.8, 14.6);
            line(9, 2.8, 14.2, 14.6);
            line(5.4, 11.2, 12.6, 11.2);
        } else if (k === "folder") {
            ctx.beginPath();
            ctx.moveTo(2.2, 13);
            ctx.lineTo(2.2, 5.6);
            ctx.arcTo(2.2, 3.8, 4, 3.8, 1.8);
            ctx.lineTo(6.6, 3.8);
            ctx.lineTo(8.2, 5.8);
            ctx.lineTo(14, 5.8);
            ctx.arcTo(15.8, 5.8, 15.8, 7.6, 1.8);
            ctx.lineTo(15.8, 13);
            ctx.arcTo(15.8, 15.2, 13.6, 15.2, 2.2);
            ctx.lineTo(4.4, 15.2);
            ctx.arcTo(2.2, 15.2, 2.2, 13, 2.2);
            ctx.closePath(); ctx.stroke();
        } else if (k === "layers") {
            ctx.beginPath(); ctx.moveTo(9, 2.4); ctx.lineTo(15.6, 5.8); ctx.lineTo(9, 9.2); ctx.lineTo(2.4, 5.8); ctx.closePath(); ctx.stroke();
            poly([2.4, 9.2, 9, 12.6, 15.6, 9.2], false);
            poly([2.4, 12.4, 9, 15.8, 15.6, 12.4], false);
        } else if (k === "clipboard") {
            rrect(3.6, 3.4, 10.8, 12.6, 2); ctx.stroke();
            rrect(6.4, 1.9, 5.2, 3.4, 1.2); ctx.stroke();
            line(6.4, 9, 11.6, 9);
            line(6.4, 12, 10, 12);
        } else if (k === "smile") {
            circ(9, 9, 6.6); ctx.stroke();
            circ(6.7, 7.5, 0.95); ctx.fill();
            circ(11.3, 7.5, 0.95); ctx.fill();
            ctx.beginPath(); ctx.arc(9, 9.2, 3.7, 0.25, PI - 0.25, false); ctx.stroke();
        } else if (k === "doc") {
            ctx.beginPath(); ctx.moveTo(4.6, 2.2); ctx.lineTo(10.2, 2.2); ctx.lineTo(13.8, 5.8); ctx.lineTo(13.8, 15.8); ctx.lineTo(4.6, 15.8); ctx.closePath(); ctx.stroke();
            poly([10.2, 2.2, 10.2, 5.8, 13.8, 5.8], false);
            line(6.8, 9.6, 11.6, 9.6);
            line(6.8, 12.4, 11.6, 12.4);
        } else if (k === "link") {
            ctx.save(); ctx.translate(9, 9); ctx.rotate(-PI / 4);
            rrect(-7.2, -2.7, 8.2, 5.4, 2.7); ctx.stroke();
            rrect(-1, -2.7, 8.2, 5.4, 2.7); ctx.stroke();
            ctx.restore();
        } else if (k === "photo") {
            rrect(2.4, 3.4, 13.2, 11.2, 2.2); ctx.stroke();
            circ(6.4, 7.4, 1.3); ctx.fill();
            poly([3.2, 13.4, 7.6, 9.4, 10.4, 12, 12.4, 10.2, 14.8, 13.4], false);
        } else if (k === "return") {
            poly([14.5, 4, 14.5, 10, 4.5, 10], false);
            poly([7.5, 7, 4.5, 10, 7.5, 13], false);
        } else if (k === "dots") {
            circ(3.6, 9, 1.35); ctx.fill();
            circ(9, 9, 1.35); ctx.fill();
            circ(14.4, 9, 1.35); ctx.fill();
        } else if (k === "lock") {
            rrect(3.6, 8, 10.8, 7.8, 2); ctx.stroke();
            ctx.beginPath(); ctx.moveTo(6, 8); ctx.lineTo(6, 6); ctx.arc(9, 6, 3, PI, 0, false); ctx.lineTo(12, 8); ctx.stroke();
        } else if (k === "power") {
            ctx.beginPath(); ctx.arc(9, 9.6, 6, -PI / 2 + 0.65, -PI / 2 - 0.65 + PI * 2, false); ctx.stroke();
            line(9, 2.2, 9, 8.4);
        } else if (k === "restart") {
            ctx.beginPath(); ctx.arc(9, 9, 5.8, -1.0, 4.4, false); ctx.stroke();
            poly([9.7, 2.7, 6.6, 1.6, 7.8, 5.4], true);
        } else if (k === "logout") {
            poly([9, 3, 3.5, 3, 3.5, 15, 9, 15], false);
            line(7.5, 9, 15.5, 9);
            poly([12.5, 6, 15.5, 9, 12.5, 12], false);
        } else if (k === "contrast") {
            circ(9, 9, 6.5); ctx.stroke();
            ctx.beginPath(); ctx.arc(9, 9, 6.5, -PI / 2, PI / 2, false); ctx.closePath(); ctx.fill();
        } else if (k === "check") {
            poly([3.5, 9.5, 7.5, 13.5, 14.5, 4.5], false);
        } else if (k === "chevL") {
            poly([11, 3.5, 5.5, 9, 11, 14.5], false);
        } else if (k === "chevR") {
            poly([7, 3.5, 12.5, 9, 7, 14.5], false);
        } else if (k === "bell") {
            ctx.beginPath(); ctx.moveTo(3.4, 12.9);
            ctx.bezierCurveTo(4.6, 11.8, 5.0, 10.6, 5.0, 8.2);
            ctx.bezierCurveTo(5.0, 5.6, 6.8, 3.9, 9.0, 3.9);
            ctx.bezierCurveTo(11.2, 3.9, 13.0, 5.6, 13.0, 8.2);
            ctx.bezierCurveTo(13.0, 10.6, 13.4, 11.8, 14.6, 12.9);
            ctx.closePath(); ctx.stroke();
            line(9, 2.2, 9, 3.9);
            ctx.beginPath(); ctx.arc(9, 14.3, 1.7, 0.25, PI - 0.25); ctx.stroke();
        } else if (k === "close") {
            line(5, 5, 13, 13); line(13, 5, 5, 13);
        } else if (k === "command") {
            // ⌘ — a square with a three-quarter loop at each corner
            var sr = 2.2, lr = 1.85;
            var sgn = [[-1, -1], [1, -1], [-1, 1], [1, 1]];
            ctx.beginPath();
            ctx.rect(9 - sr, 9 - sr, sr * 2, sr * 2);
            ctx.stroke();
            for (i2 = 0; i2 < 4; i2++) {
                var sx = sgn[i2][0], sy = sgn[i2][1];
                var cx2 = 9 + sx * (sr + lr), cy2 = 9 + sy * (sr + lr);
                var a1 = sx > 0 ? PI : 0, a2 = -sy * PI / 2;
                ctx.beginPath(); ctx.arc(cx2, cy2, lr, a1, a2, sx * sy > 0); ctx.stroke();
                line(9 + sx * sr, 9 + sy * (sr + lr), 9 + sx * sr, 9 + sy * sr);
                line(9 + sx * (sr + lr), 9 + sy * sr, 9 + sx * sr, 9 + sy * sr);
            }
        } else if (k === "gear") {
            circ(9, 9, 2.6); ctx.stroke();
            for (i2 = 0; i2 < 8; i2++) {
                var g2 = i2 * PI / 4;
                line(9 + Math.cos(g2) * 5.6, 9 + Math.sin(g2) * 5.6, 9 + Math.cos(g2) * 7.6, 9 + Math.sin(g2) * 7.6);
            }
            circ(9, 9, 5.6); ctx.stroke();
        }
    }
}
