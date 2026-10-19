// WIcon — the little white symbols on the Mac Hello tour cards.
import QtQuick

Canvas {
    id: wi
    property string kind: ""
    property color color: "white"
    antialiasing: true
    onKindChanged: requestPaint()
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onPaint: {
        var c = getContext("2d");
        c.reset();
        var s = width / 16;
        c.scale(s, s);
        c.strokeStyle = wi.color;
        c.fillStyle = wi.color;
        c.lineWidth = 1.5;
        c.lineCap = "round";
        c.lineJoin = "round";
        var PI = Math.PI;
        if (kind === "search") {
            c.beginPath(); c.arc(7, 7, 4.6, 0, PI * 2); c.stroke();
            c.beginPath(); c.moveTo(10.4, 10.4); c.lineTo(14, 14); c.stroke();
        } else if (kind === "sliders") {
            for (var i = 0; i < 3; i++) {
                var y = 4 + i * 4;
                c.beginPath(); c.moveTo(2, y); c.lineTo(14, y); c.stroke();
                c.beginPath(); c.arc(i === 1 ? 10.5 : 5.5, y, 1.9, 0, PI * 2); c.fill();
            }
        } else if (kind === "dock") {
            c.beginPath(); c.roundedRect(1.4, 9, 13.2, 5, 1.8, 1.8); c.stroke();
            for (var d = 0; d < 3; d++) {
                c.beginPath(); c.roundedRect(3 + d * 3.6, 10.4, 2.6, 2.6, 0.8, 0.8); c.fill();
            }
            c.beginPath(); c.roundedRect(5.6, 2.2, 4.8, 4.8, 1.3, 1.3); c.stroke();
        } else if (kind === "widget") {
            c.beginPath(); c.roundedRect(1.8, 1.8, 5.6, 5.6, 1.4, 1.4); c.stroke();
            c.beginPath(); c.roundedRect(8.8, 1.8, 5.4, 5.4, 1.4, 1.4); c.fill();
            c.beginPath(); c.roundedRect(1.8, 8.8, 12.4, 5.4, 1.4, 1.4); c.stroke();
        } else if (kind === "share") {
            c.beginPath(); c.moveTo(8, 2.2); c.lineTo(8, 10); c.stroke();
            c.beginPath(); c.moveTo(5.2, 5); c.lineTo(8, 2.2); c.lineTo(10.8, 5); c.stroke();
            c.beginPath(); c.moveTo(3.4, 8.6); c.lineTo(3.4, 13.6); c.lineTo(12.6, 13.6); c.lineTo(12.6, 8.6); c.stroke();
        } else if (kind === "folder") {
            c.beginPath();
            c.moveTo(1.6, 12.8); c.lineTo(1.6, 4.2); c.lineTo(6.2, 4.2); c.lineTo(7.4, 5.6);
            c.lineTo(14.4, 5.6); c.lineTo(14.4, 12.8); c.closePath();
            c.fill();
        }
    }
}
