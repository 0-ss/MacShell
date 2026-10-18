// SF Symbols-style clock glyphs (original vector drawings in Apple's style): "alarm" = alarm.fill, "stopwatch" = stopwatch.fill,
// "timer" = timer. Filled shapes with the hands cut out, so they read at 12-14 px like Apple's widget headers.
import QtQuick

Canvas {
    id: g
    property string kind: "alarm"
    property color color: "#FF9F0A"
    width: 16; height: 16
    antialiasing: true
    onKindChanged: requestPaint()
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        var c = getContext("2d");
        c.reset();
        var s = Math.min(width, height) / 20;
        c.scale(s, s);
        c.fillStyle = color; c.strokeStyle = color;
        c.lineCap = "round"; c.lineJoin = "round";
        var PI = Math.PI;
        function cut(fn) { c.save(); c.globalCompositeOperation = "destination-out"; c.strokeStyle = "black"; c.fillStyle = "black"; fn(); c.restore(); }
        if (kind === "alarm") {
            // bells: two rounded caps leaning out at the top
            c.save(); c.translate(4.1, 4.3); c.rotate(-PI / 4);
            c.beginPath(); c.arc(0, 0.9, 3.0, PI, 0); c.closePath(); c.fill(); c.restore();
            c.save(); c.translate(15.9, 4.3); c.rotate(PI / 4);
            c.beginPath(); c.arc(0, 0.9, 3.0, PI, 0); c.closePath(); c.fill(); c.restore();
            // feet
            c.lineWidth = 1.8;
            c.beginPath(); c.moveTo(5.3, 16.2); c.lineTo(3.8, 18.0); c.stroke();
            c.beginPath(); c.moveTo(14.7, 16.2); c.lineTo(16.2, 18.0); c.stroke();
            // body, with a ring gap to separate it from the bells
            cut(function () { c.beginPath(); c.arc(10, 11, 8.4, 0, PI * 2); c.fill(); });
            c.beginPath(); c.arc(10, 11, 7.1, 0, PI * 2); c.fill();
            // hands
            cut(function () { c.lineWidth = 1.7; c.beginPath(); c.moveTo(10, 7.0); c.lineTo(10, 11.2); c.lineTo(12.8, 12.9); c.stroke(); });
        } else if (kind === "stopwatch") {
            // crown + button
            c.beginPath(); c.roundedRect(7.6, 0.8, 4.8, 2.2, 0.9, 0.9); c.fill();
            c.lineWidth = 1.9; c.beginPath(); c.moveTo(10, 2.6); c.lineTo(10, 4.4); c.stroke();
            c.save(); c.translate(16.4, 5.4); c.rotate(PI / 4); c.beginPath(); c.roundedRect(-1.2, -0.9, 2.4, 1.8, 0.6, 0.6); c.fill(); c.restore();
            c.beginPath(); c.arc(10, 11.6, 7.6, 0, PI * 2); c.fill();
            cut(function () { c.lineWidth = 1.7; c.beginPath(); c.moveTo(10, 11.6); c.lineTo(10, 6.6); c.stroke(); c.beginPath(); c.arc(10, 11.6, 1.3, 0, PI * 2); c.fill(); });
        } else if (kind === "timer") {
            // timer: open ring with a gap at the top and a hand pointing into it
            c.lineWidth = 1.9;
            c.beginPath(); c.arc(10, 10.5, 7.6, -PI / 2 + 0.38, -PI / 2 + PI * 2 - 0.02); c.stroke();
            c.beginPath(); c.moveTo(10, 2.9); c.lineTo(10, 5.6); c.stroke();
            c.beginPath(); c.moveTo(10, 10.5); c.lineTo(6.6, 6.9); c.stroke();
            c.beginPath(); c.arc(10, 10.5, 1.3, 0, PI * 2); c.fill();
        }
    }
}
