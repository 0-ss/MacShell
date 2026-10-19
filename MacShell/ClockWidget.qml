 // macOS Clock widget for the desktop widget layer.
 // styles: "light" | "dark" | "liquid"
 // sizes: Small 168x168 · Medium 358x168 · Large 358x354

import QtQuick
import QtQuick.Effects

Item {
    id: w

    property string style: "light"       // "light" | "dark" | "liquid"
    property string size: "small"
    property real scaleF: 1.0
    property string fam: "Open Runde"
    property real screenX: x
    property real screenY: y
    property bool preview: false
    property string previewTime: "9:41"
    property bool editing: false

    // City label supplied by the widget host.
    // Riyadh = RIY, Dubai = DXB, London = LON, New York = NYC.
    property string cityCode: "RIY"

    // Liquid Glass inputs shared with Weather / Calendar.
    property bool glassReady: false
    property url shaderUrl: ""
    property url wallUrl: ""
    property real screenW: 1920
    property real screenH: 1080
    property real glassOpacity: 0.42
    property real glassBlur: 5
    property real glassLiquid: 1.0
    property real glassRim: 0.45
    property color borderTint: "#8A9AB5"      // Control Center border colour
    property real glassGrain: 0.03
    property bool darkGlass: true

    signal glassFailed()

    readonly property bool isSmall: size === "small"
    readonly property bool isMedium: size === "medium"
    readonly property bool isLarge: size === "large"

    // content scale: follows the real size of the widget, so it still fits if the host stretches it
    readonly property real u: Math.min(width, height) / 158
    readonly property real s: u
    // same corner radius as the Weather / Calendar widgets
    readonly property real radiusPx: 28 * scaleF * (isSmall ? 168 / 158 : (isMedium ? 358 / 338 : 1))

    readonly property bool dark:
        style === "dark" || (style === "liquid" && darkGlass)

    readonly property bool glassOn:
        style === "liquid" && glassReady && !preview && wallUrl != ""

    readonly property real tint:
        Math.min(0.92,
                 dark ? 0.25 + glassOpacity * 0.8
                      : 0.45 + glassOpacity * 0.9)

    width: (isSmall ? 158 : 358) * scaleF
           * (isSmall ? 168 / 158 : (isMedium ? 358 / 338 : 1.0))

    height: (isLarge ? 354 : 168) * scaleF

    property var now: new Date()

    // Update often enough that the second ticks glide smoothly.
    Timer {
        interval: 33
        repeat: true
        running: !w.preview
        onTriggered: w.now = new Date()
    }

    readonly property string liveTime: {
        var hour = w.now.getHours() % 12
        if (hour === 0)
            hour = 12

        return hour + ":" + ("0" + w.now.getMinutes()).slice(-2)
    }

    readonly property string displayTime:
        preview ? previewTime : liveTime

    // seconds into the minute (fractional); the Settings preview freezes the dial half way round, like the macOS picture
    readonly property real secs:
        preview ? 30.4 : w.now.getSeconds() + w.now.getMilliseconds() / 1000

    // Light face.
    Rectangle {
        anchors.fill: parent
        visible: w.style === "light"
        radius: w.radiusPx

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#E9EAEB" }
            GradientStop { position: 0.55; color: "#DFE0E2" }
            GradientStop { position: 1.0; color: "#D6D7DA" }
        }
    }

    // Dark face.
    Rectangle {
        anchors.fill: parent
        visible: w.style === "dark"
        radius: w.radiusPx

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#38393D" }
            GradientStop { position: 0.55; color: "#303135" }
            GradientStop { position: 1.0; color: "#242529" }
        }
    }

    // Liquid style fallback and Settings preview.
    Rectangle {
        anchors.fill: parent
        visible: w.style === "liquid" && !w.glassOn
        radius: w.radiusPx

        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: w.dark
                    ? Qt.rgba(0.22, 0.22, 0.25, 0.82)
                    : Qt.rgba(1.0, 1.0, 1.0, 0.88)
            }
            GradientStop {
                position: 1.0
                color: w.dark
                    ? Qt.rgba(0.13, 0.13, 0.15, 0.82)
                    : Qt.rgba(0.92, 0.92, 0.95, 0.88)
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius

            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: Qt.rgba(1, 1, 1, w.dark ? 0.10 : 0.35)
                }
                GradientStop {
                    position: 0.6
                    color: Qt.rgba(1, 1, 1, 0.0)
                }
            }
        }
    }

    // Live wallpaper backdrop and refraction shader.
    Loader {
        anchors.fill: parent
        active: w.glassOn

        sourceComponent: Item {
            id: gl

            readonly property real margin: 72
            readonly property real padPx: 10
            readonly property real ds: w.glassBlur >= 8 ? 0.5 : 1.0
            readonly property real bn:
                Math.min(1.0, w.glassBlur * 1.4 * ds / 64.0)

            Item {
                id: backdrop

                width: w.width + 2 * (gl.padPx + gl.margin)
                height: w.height + 2 * (gl.padPx + gl.margin)

                Rectangle {
                    anchors.fill: parent

                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#2f6bff" }
                        GradientStop { position: 0.5; color: "#b44cff" }
                        GradientStop { position: 1.0; color: "#ff8a3d" }
                    }
                }

                Image {
                    x: -(w.screenX - gl.padPx - gl.margin)
                    y: -(w.screenY - gl.padPx - gl.margin)
                    width: w.screenW
                    height: w.screenH
                    source: w.wallUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: w.screenW
                    smooth: true
                }
            }

            ShaderEffectSource {
                id: bsrc
                sourceItem: backdrop
                hideSource: true
                live: true
                visible: false

                textureSize: Qt.size(
                    Math.max(1, Math.round(backdrop.width * gl.ds)),
                    Math.max(1, Math.round(backdrop.height * gl.ds))
                )
            }

            MultiEffect {
                id: blurFx
                source: bsrc
                width: backdrop.width * gl.ds
                height: backdrop.height * gl.ds
                blurEnabled: true
                blurMax: 64
                blur: gl.bn
                autoPaddingEnabled: false
                visible: false
            }

            ShaderEffectSource {
                id: blurred
                sourceItem: blurFx
                live: true
                visible: false
            }

            ShaderEffect {
                x: -gl.padPx
                y: -gl.padPx
                width: w.width + 2 * gl.padPx
                height: w.height + 2 * gl.padPx

                fragmentShader: w.shaderUrl

                onStatusChanged: {
                    if (status === ShaderEffect.Error)
                        w.glassFailed()
                }

                property variant src: blurred
                property vector2d itemSize: Qt.vector2d(width, height)
                property vector2d glassSize: Qt.vector2d(w.width, w.height)
                property vector2d srcSize:
                    Qt.vector2d(backdrop.width, backdrop.height)
                property vector2d srcOffset:
                    Qt.vector2d(gl.margin, gl.margin)

                property real pad: gl.padPx
                property real radius: w.radiusPx
                property real bezel:
                    Math.min(Math.min(w.width, w.height) * 0.36, 26)
                property real thickness: 30 * w.glassLiquid
                property real dispersion: 0.06 * w.glassLiquid
                property real magnify:
                    0.08 * w.glassLiquid * Math.min(1, 90 / w.height)
                property real rim: w.glassRim
                property real grain: w.glassGrain * 0.15
                property real blurPx: 1.0
                property real tintMix: w.tint
                property real saturation: 1.25
                property real dark: w.dark ? 1 : 0
                property real debug: 0
                property real shadowAmt: 0           // no drop shadow
                property real flatInner: 1           // no darker inner edge (needs the rebuilt liquidglass shader)
                property real rimTint: 1
                property real ringW: 0
            }
        }
    }

    // Control Center border (all styles)
    CornerBorder {
        z: 2
        anchors.fill: parent
        cornerR: w.radiusPx
        dark: w.dark
        tint: w.borderTint
        lineW: 0.8
    }

    // ── dial ticks ──
    // 60 ticks, one every 6 degrees starting at 12 o'clock. Each sits where its ray from the centre meets a rounded rectangle
    // inset from the widget's edge, and points at the centre (that is how the macOS face looks, also in the corners).
    readonly property real tickLen: 5.6 * u
    readonly property var tickGeo: {
        var W = w.width, H = w.height, inset = 9 * w.u, L = w.tickLen;
        var hw = W / 2 - inset, hh = H / 2 - inset;
        var cr = Math.max(4 * w.u, w.radiusPx - inset);
        var cx = hw - cr, cy = hh - cr, out = [];
        for (var i = 0; i < 60; i++) {
            var th = i * Math.PI / 30, dx = Math.sin(th), dy = -Math.cos(th);
            var ax = Math.abs(dx), ay = Math.abs(dy);
            var t = Math.min(ax > 1e-9 ? hw / ax : 1e9, ay > 1e-9 ? hh / ay : 1e9);
            var px = ax * t, py = ay * t;
            if (px > cx && py > cy) {            // inside a rounded corner: meet the corner circle instead
                var b = ax * cx + ay * cy, c = cx * cx + cy * cy - cr * cr;
                t = b + Math.sqrt(Math.max(0, b * b - c));
                px = ax * t; py = ay * t;
            }
            var ex = dx < 0 ? -px : px, ey = dy < 0 ? -py : py;      // outer end of the tick, relative to the centre
            out.push({ x: W / 2 + ex - dx * L / 2, y: H / 2 + ey - dy * L / 2, a: Math.atan2(dx, -dy) * 180 / Math.PI });
        }
        return out;
    }

    Repeater {
        model: 60

        delegate: Rectangle {
            required property int index

            readonly property var tick: w.tickGeo[index]

            // The seconds that already passed this minute form a dark trail that gets stronger towards the current second;
            // the ticks still to come are faint. frac = how much of this tick's second has elapsed (smooth sweep).
            readonly property real frac: Math.max(0, Math.min(1, w.secs - index))
            readonly property real past: 0.40 + 0.58 * Math.min(1, index / Math.max(1, w.secs))
            readonly property real ahead: 0.12 + 0.28 * Math.max(0, Math.min(1, (index - w.secs) / Math.max(1, 60 - w.secs)))

            width: 1.7 * w.u
            height: w.tickLen
            x: tick.x - width / 2
            y: tick.y - height / 2
            radius: width / 2
            rotation: tick.a
            color: w.dark ? "white" : "#0C0D0F"
            opacity: (w.dark ? 0.9 : 1.0) * (ahead + (past - ahead) * frac)
        }
    }

    // City label (Cupertino is "CUP" on the Mac): small, bold, grey, a fifth of the way down.
    Text {
        id: cityLabel

        anchors.horizontalCenter: parent.horizontalCenter
        y: 0.20 * w.height - height / 2
        height: 17 * w.u

        text: w.cityCode

        color: w.dark
            ? Qt.rgba(1, 1, 1, 0.55)
            : Qt.rgba(0, 0, 0, 0.46)

        font.family: w.fam
        font.pixelSize: 11.5 * w.u
        font.weight: Font.Bold
        font.letterSpacing: 0.4 * w.u

        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    // The time: very heavy, tall and narrow numerals (Inter Black squeezed horizontally and stretched vertically),
    // 12-hour, no leading zero. Longer times like 12:45 shrink to stay inside the ticks.
    Text {
        id: clockText

        readonly property real xs: 0.75       // horizontal squeeze
        readonly property real ys: 1.30       // vertical stretch

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -1 * w.u

        width: (w.width - 50 * w.u) / xs      // layout width before the squeeze
        height: 62 * w.u * 1.25

        text: w.displayTime

        color: w.dark ? "#FFFFFF" : "#0C0D0F"

        font.family: w.fam
        font.pixelSize: 62 * w.u
        font.weight: Font.Black
        font.letterSpacing: -3.0 * w.u

        // same-colour outline: slightly heavier strokes
        style: Text.Outline
        styleColor: color

        transform: Scale {
            origin.x: clockText.width / 2
            origin.y: clockText.height / 2
            xScale: clockText.xs
            yScale: clockText.ys
        }

        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter

        fontSizeMode: Text.Fit
        minimumPixelSize: 10
    }
}
