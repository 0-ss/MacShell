// Small hand-drawn weather glyphs (no icon font / image files needed).
//   kind: sun | moon | partly | partlyNight | cloud | fog | rain | snow | storm
import QtQuick

Canvas {
    id: ic
    property string kind: "sun"
    property real size: 18
    width: size
    height: size
    antialiasing: true

    onKindChanged: requestPaint()
    onSizeChanged: requestPaint()
    onWidthChanged: requestPaint()

    function cloud(ctx, cx, cy, w, c1, c2) {
        var g = ctx.createLinearGradient(0, cy - 0.3 * w, 0, cy + 0.22 * w);
        g.addColorStop(0, c1);
        g.addColorStop(1, c2);
        ctx.fillStyle = g;
        ctx.beginPath();
        ctx.arc(cx - 0.22 * w, cy + 0.02 * w, 0.20 * w, 0, 2 * Math.PI);
        ctx.arc(cx - 0.02 * w, cy - 0.10 * w, 0.26 * w, 0, 2 * Math.PI);
        ctx.arc(cx + 0.26 * w, cy + 0.03 * w, 0.18 * w, 0, 2 * Math.PI);
        ctx.fill();
        // pill-shaped base
        var l = cx - 0.42 * w, r = cx + 0.44 * w, t = cy - 0.02 * w, b = cy + 0.20 * w, rad = (b - t) / 2;
        ctx.beginPath();
        ctx.moveTo(l + rad, t);
        ctx.lineTo(r - rad, t);
        ctx.arc(r - rad, t + rad, rad, -Math.PI / 2, Math.PI / 2, false);
        ctx.lineTo(l + rad, b);
        ctx.arc(l + rad, t + rad, rad, Math.PI / 2, 3 * Math.PI / 2, false);
        ctx.closePath();
        ctx.fill();
    }

    function sun(ctx, cx, cy, s, withRays) {
        var r = 0.26 * s;
        if (withRays) {
            ctx.strokeStyle = "#FFD23F";
            ctx.lineWidth = Math.max(1, 0.075 * s);
            ctx.lineCap = "round";
            for (var i = 0; i < 8; i++) {
                var a = i * Math.PI / 4;
                ctx.beginPath();
                ctx.moveTo(cx + Math.cos(a) * (r + 0.09 * s), cy + Math.sin(a) * (r + 0.09 * s));
                ctx.lineTo(cx + Math.cos(a) * (r + 0.20 * s), cy + Math.sin(a) * (r + 0.20 * s));
                ctx.stroke();
            }
        }
        var g = ctx.createLinearGradient(cx, cy - r, cx, cy + r);
        g.addColorStop(0, "#FFE066");
        g.addColorStop(1, "#FFB800");
        ctx.fillStyle = g;
        ctx.beginPath();
        ctx.arc(cx, cy, r, 0, 2 * Math.PI);
        ctx.fill();
    }

    function moon(ctx, cx, cy, s) {
        var r = 0.34 * s;
        var g = ctx.createLinearGradient(cx - r, cy - r, cx + r, cy + r);
        g.addColorStop(0, "#F4F1DE");
        g.addColorStop(1, "#C9C6B0");
        ctx.fillStyle = g;
        ctx.beginPath();
        ctx.arc(cx, cy, r, 0, 2 * Math.PI);
        ctx.fill();
        // bite out of the disc → crescent
        ctx.globalCompositeOperation = "destination-out";
        ctx.beginPath();
        ctx.arc(cx + 0.55 * r, cy - 0.35 * r, 0.82 * r, 0, 2 * Math.PI);
        ctx.fill();
        ctx.globalCompositeOperation = "source-over";
    }

    onPaint: {
        var ctx = getContext("2d");
        var s = Math.min(width, height);
        ctx.reset();
        ctx.clearRect(0, 0, width, height);
        var c = s / 2;
        switch (ic.kind) {
        case "sun":
            sun(ctx, c, c, s, true);
            break;
        case "moon":
            moon(ctx, c, c, s);
            break;
        case "partly":
            sun(ctx, 0.38 * s, 0.36 * s, s * 0.9, true);
            cloud(ctx, 0.56 * s, 0.66 * s, 0.82 * s, "#FFFFFF", "#D5DCE8");
            break;
        case "partlyNight":
            moon(ctx, 0.36 * s, 0.34 * s, s * 0.9);
            cloud(ctx, 0.56 * s, 0.66 * s, 0.82 * s, "#F2F5FA", "#B9C3D3");
            break;
        case "cloud":
            cloud(ctx, c, 0.55 * s, 0.94 * s, "#FFFFFF", "#CBD3E0");
            break;
        case "fog":
            cloud(ctx, c, 0.40 * s, 0.84 * s, "#F2F5FA", "#C4CCDA");
            ctx.strokeStyle = "rgba(255,255,255,0.85)";
            ctx.lineWidth = Math.max(1, 0.075 * s);
            ctx.lineCap = "round";
            for (var f = 0; f < 2; f++) {
                ctx.beginPath();
                ctx.moveTo(0.18 * s, (0.72 + f * 0.16) * s);
                ctx.lineTo(0.82 * s, (0.72 + f * 0.16) * s);
                ctx.stroke();
            }
            break;
        case "rain":
            cloud(ctx, c, 0.38 * s, 0.88 * s, "#E6EBF3", "#A9B4C6");
            ctx.strokeStyle = "#6EC1FF";
            ctx.lineWidth = Math.max(1, 0.08 * s);
            ctx.lineCap = "round";
            for (var d = 0; d < 3; d++) {
                ctx.beginPath();
                ctx.moveTo((0.30 + d * 0.20) * s, 0.68 * s);
                ctx.lineTo((0.25 + d * 0.20) * s, 0.90 * s);
                ctx.stroke();
            }
            break;
        case "snow":
            cloud(ctx, c, 0.38 * s, 0.88 * s, "#E6EBF3", "#A9B4C6");
            ctx.fillStyle = "#FFFFFF";
            for (var n = 0; n < 3; n++) {
                ctx.beginPath();
                ctx.arc((0.30 + n * 0.20) * s, (0.76 + (n % 2) * 0.10) * s, 0.055 * s, 0, 2 * Math.PI);
                ctx.fill();
            }
            break;
        case "storm":
            cloud(ctx, c, 0.36 * s, 0.88 * s, "#C9D0DC", "#8A94A6");
            ctx.fillStyle = "#FFD23F";
            ctx.beginPath();
            ctx.moveTo(0.54 * s, 0.56 * s);
            ctx.lineTo(0.38 * s, 0.80 * s);
            ctx.lineTo(0.50 * s, 0.80 * s);
            ctx.lineTo(0.44 * s, 0.98 * s);
            ctx.lineTo(0.66 * s, 0.70 * s);
            ctx.lineTo(0.54 * s, 0.70 * s);
            ctx.closePath();
            ctx.fill();
            break;
        }
    }
}
