import QtQuick

// Sculpted 3D studio-lit Galaxy Buds 4 vector artwork on a 32×32 canvas:
//  * "budL" / "budR": Dual-faceted Samsung Blade-stem earbud + radial-lit acoustic bulb + glowing LED blade strip
//  * "case": Frosted glass dome clamshell charging case with 3D nested buds + satin ceramic body + jewel status LED
Canvas {
    id: bpa
    property string kind: "case"         // "budL" | "case" | "budR"
    property color color: "#F5F5F7"
    property color accentColor: "#38BDF8"
    width: 28; height: 28
    antialiasing: true
    onKindChanged: requestPaint()
    onColorChanged: requestPaint()
    onAccentColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        var s = Math.min(width, height) / 32;
        ctx.scale(s, s);
        ctx.lineCap = "round";
        ctx.lineJoin = "round";

        // Subtle ambient studio depth shadow behind hardware inside the glass sphere
        var bgSh = ctx.createRadialGradient(16, 17, 2, 16, 17.5, 13);
        bgSh.addColorStop(0.0, Qt.rgba(0, 0, 0, 0.28));
        bgSh.addColorStop(1.0, Qt.rgba(0, 0, 0, 0.0));
        ctx.fillStyle = bgSh;
        ctx.fillRect(0, 0, 32, 32);

        if (kind === "case") {
            // 1. Frosted translucent top clamshell dome lid with 3D studio sheen
            var lidGrad = ctx.createLinearGradient(6.5, 6.0, 25.5, 15.5);
            lidGrad.addColorStop(0.0, Qt.rgba(color.r, color.g, color.b, 0.34));
            lidGrad.addColorStop(0.5, Qt.rgba(color.r, color.g, color.b, 0.14));
            lidGrad.addColorStop(1.0, Qt.rgba(color.r, color.g, color.b, 0.22));
            ctx.beginPath();
            ctx.moveTo(6.3, 15.2);
            ctx.lineTo(6.3, 11.6);
            ctx.bezierCurveTo(6.3, 7.3, 10.1, 5.9, 16.0, 5.9);
            ctx.bezierCurveTo(21.9, 5.9, 25.7, 7.3, 25.7, 11.6);
            ctx.lineTo(25.7, 15.2);
            ctx.closePath();
            ctx.fillStyle = lidGrad;
            ctx.fill();
            ctx.lineWidth = 1.25;
            ctx.strokeStyle = Qt.rgba(color.r, color.g, color.b, 0.68);
            ctx.stroke();

            // Top dome specular glass reflection arc
            ctx.beginPath();
            ctx.moveTo(9.2, 8.6);
            ctx.bezierCurveTo(11.6, 7.0, 20.4, 7.0, 22.8, 8.6);
            ctx.lineWidth = 0.95;
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.55);
            ctx.stroke();

            // 2. Two 3D-shaded nested earbud heads visible beneath the clear dome lid
            var cradlePositions = [11.8, 20.2];
            for (var bi = 0; bi < 2; bi++) {
                var bx = cradlePositions[bi];
                var bGrad = ctx.createRadialGradient(bx - 0.8, 10.8, 0.4, bx, 11.5, 3.2);
                bGrad.addColorStop(0.0, Qt.rgba(1, 1, 1, 0.85));
                bGrad.addColorStop(1.0, Qt.rgba(color.r, color.g, color.b, 0.38));
                ctx.save();
                ctx.translate(bx, 11.5);
                ctx.scale(1.25, 0.95);
                ctx.beginPath();
                ctx.arc(0, 0, 2.2, 0, Math.PI * 2);
                ctx.restore();
                ctx.fillStyle = bGrad;
                ctx.fill();
            }

            // 3. Lower sculpted satin-ceramic squircle charging body
            var bodyGrad = ctx.createLinearGradient(16, 15.2, 16, 26.5);
            bodyGrad.addColorStop(0.0, Qt.rgba(1, 1, 1, 0.98));
            bodyGrad.addColorStop(0.55, Qt.rgba(color.r, color.g, color.b, 0.90));
            bodyGrad.addColorStop(1.0, Qt.rgba(color.r * 0.78, color.g * 0.80, color.b * 0.85, 0.88));
            ctx.beginPath();
            ctx.moveTo(5.9, 15.2);
            ctx.lineTo(26.1, 15.2);
            ctx.lineTo(26.1, 20.8);
            ctx.bezierCurveTo(26.1, 24.8, 23.0, 26.4, 16.0, 26.4);
            ctx.bezierCurveTo(9.0, 26.4, 5.9, 24.8, 5.9, 20.8);
            ctx.closePath();
            ctx.fillStyle = bodyGrad;
            ctx.fill();

            // Precision clamshell seam + subtle lip highlight
            ctx.beginPath();
            ctx.moveTo(6.4, 15.2);
            ctx.lineTo(25.6, 15.2);
            ctx.lineWidth = 1.05;
            ctx.strokeStyle = Qt.rgba(0, 0, 0, 0.34);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(7.0, 16.2);
            ctx.lineTo(25.0, 16.2);
            ctx.lineWidth = 0.7;
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.55);
            ctx.stroke();

            // 4. Front jewel-cut glowing status LED + soft caustic halo
            var ledHalo = ctx.createRadialGradient(16.0, 20.7, 0.4, 16.0, 20.7, 4.2);
            ledHalo.addColorStop(0.0, Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.55));
            ledHalo.addColorStop(1.0, Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.0));
            ctx.fillStyle = ledHalo;
            ctx.beginPath();
            ctx.arc(16.0, 20.7, 4.2, 0, Math.PI * 2);
            ctx.fill();

            ctx.beginPath();
            ctx.arc(16.0, 20.7, 1.55, 0, Math.PI * 2);
            ctx.fillStyle = accentColor;
            ctx.fill();
            ctx.beginPath();
            ctx.arc(15.5, 20.2, 0.55, 0, Math.PI * 2);
            ctx.fillStyle = Qt.rgba(1, 1, 1, 0.85);
            ctx.fill();
        } else {
            // "budL" or mirrored "budR"
            if (kind === "budR") {
                ctx.translate(32, 0);
                ctx.scale(-1, 1);
            }

            // 1. Translucent silicone ear-tip cushion (angled inward toward ear canal)
            var tipGrad = ctx.createRadialGradient(20.6, 9.2, 0.4, 20.4, 9.8, 3.6);
            tipGrad.addColorStop(0.0, Qt.rgba(color.r, color.g, color.b, 0.62));
            tipGrad.addColorStop(1.0, Qt.rgba(color.r, color.g, color.b, 0.26));
            ctx.save();
            ctx.translate(20.4, 9.8);
            ctx.rotate(0.28);
            ctx.scale(1.15, 0.92);
            ctx.beginPath();
            ctx.arc(0, 0, 2.5, 0, Math.PI * 2);
            ctx.restore();
            ctx.fillStyle = tipGrad;
            ctx.fill();

            // 2. Studio-lit 3D ergonomic acoustic bulb
            var bulbGrad = ctx.createRadialGradient(14.2, 8.2, 0.8, 15.6, 10.6, 6.8);
            bulbGrad.addColorStop(0.0, Qt.rgba(1, 1, 1, 0.99));
            bulbGrad.addColorStop(0.6, Qt.rgba(color.r, color.g, color.b, 0.92));
            bulbGrad.addColorStop(1.0, Qt.rgba(color.r * 0.72, color.g * 0.75, color.b * 0.82, 0.90));
            ctx.beginPath();
            ctx.moveTo(11.0, 8.8);
            ctx.bezierCurveTo(11.0, 5.5, 15.7, 5.1, 18.9, 7.4);
            ctx.bezierCurveTo(21.3, 9.2, 20.8, 13.0, 17.6, 14.4);
            ctx.bezierCurveTo(15.2, 15.4, 12.1, 14.2, 11.3, 12.0);
            ctx.closePath();
            ctx.fillStyle = bulbGrad;
            ctx.fill();

            // 3. Dual-faceted Samsung "Blade" stem (sunlit left bevel + sculpted satin right bevel)
            ctx.beginPath();
            ctx.moveTo(11.1, 10.5);
            ctx.lineTo(13.1, 11.4);
            ctx.lineTo(11.0, 25.8);
            ctx.bezierCurveTo(10.3, 26.3, 9.6, 25.9, 9.6, 24.9);
            ctx.closePath();
            ctx.fillStyle = Qt.rgba(1, 1, 1, 0.98);
            ctx.fill();

            ctx.beginPath();
            ctx.moveTo(13.1, 11.4);
            ctx.lineTo(14.9, 12.2);
            ctx.lineTo(12.3, 25.4);
            ctx.bezierCurveTo(12.0, 26.3, 11.4, 26.2, 11.0, 25.8);
            ctx.closePath();
            ctx.fillStyle = Qt.rgba(color.r * 0.76, color.g * 0.79, color.b * 0.86, 0.92);
            ctx.fill();

            // 4. Luminous mode-reactive Blade Light strip along the faceted ridge
            ctx.beginPath();
            ctx.moveTo(12.9, 12.2);
            ctx.lineTo(11.1, 24.6);
            ctx.lineWidth = 1.15;
            ctx.strokeStyle = Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.82);
            ctx.stroke();
        }
    }
}
