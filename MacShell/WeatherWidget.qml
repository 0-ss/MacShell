// macOS Tahoe style Weather widget.
//   size:  "small" 158x158 · "medium" 338x158 · "large" 338x354   (macOS point sizes, times scaleF)
//   style: "liquid" – Liquid Glass: the wallpaper behind the widget is blurred + refracted by liquidglass.frag, using the
//                     Appearance sliders (Translucency / Blur / Liquid strength)
//          "normal" – solid card (same as the Calendar widget)
//   The look (glass, tint, text colours, border) is the same as the Clock and Calendar widgets: it follows the shell's
//   Dark / Light setting.
//
// The item's own x / y are its position on the screen, which is how the glass knows which part of the wallpaper
// sits behind it (it follows the widget while it is dragged).
import QtQuick
import QtQuick.Effects
import "Fonts.js" as Fonts

Item {
    id: w

    // ── look ──
    property string style: "liquid"
    property string size: "small"
    property real scaleF: 1.0
    property string fam: "Open Runde"
    property real screenX: x
    property real screenY: y

    // ── data (from MacWidgets) ──
    property string city: "—"
    property bool located: true         // show the little location arrow (automatic location)
    property bool hasData: false
    property int temp: 0
    property int hi: 0
    property int lo: 0
    property string cond: "Loading…"
    property string kind: "sun"         // WeatherIcon kind
    property bool isDay: true
    property string unitSuffix: "°"
    property var hourly: []             // [{ h: "Now", t: 58, k: "sun" }, ...]
    property var daily: []              // [{ d: "Today", lo: 56, hi: 79, k: "sun" }, ...]

    // ── liquid glass inputs (the Appearance sliders) ──
    property bool glassReady: false     // liquidglass.frag.qsb compiled
    property url shaderUrl: ""
    property url wallUrl: ""
    property string wallVideo: ""        // animated wallpaper to play behind the glass ("" = none / real-time glass off)
    property bool wallPaused: false      // desktop covered / Game Mode: keep the decoder idle
    property real screenW: 1920
    property real screenH: 1080
    property real glassOpacity: 0.42    // Translucency
    property real glassBlur: 5          // Blur
    property real glassLiquid: 1.0      // Liquid strength
    property real glassRim: 0.45
    property color borderTint: "#8A9AB5"      // Control Center border colour
    property real glassGrain: 0.03
    property bool darkGlass: true
    property bool preview: false        // inside the Settings gallery: no wallpaper, simplified glass

    // ── desktop edit mode ──
    property bool editing: false

    signal glassFailed()                // the shader did not compile / load → MacWidgets falls back to the frosted card

    readonly property bool isSmall: size === "small"
    readonly property bool isMedium: size === "medium"
    readonly property bool isLarge: size === "large"
    // Small / Medium are slightly enlarged; Large shares the widened footprint without stretching its vertical content.
    readonly property real s: scaleF * (isSmall ? 168 / 158 : (isMedium ? 358 / 338 : 1.0))
    readonly property real radiusPx: 28 * s
    readonly property bool glassOn: style === "liquid" && glassReady && !preview && wallUrl != ""
    width: (isSmall ? 158 : (isLarge ? 358 : 338)) * s
    height: (isLarge ? 354 : 168) * scaleF

    // The cloud glyphs are not shown: only the sun / moon get an icon.
    function showIcon(k) { return k === "sun" || k === "moon"; }

    // ── light / dark (same rules as the Clock and Calendar widgets) ──
    readonly property bool dark: darkGlass
    readonly property color fg: dark ? Qt.rgba(1, 1, 1, 0.96) : Qt.rgba(0, 0, 0, 0.86)
    readonly property color fgSub: dark ? Qt.rgba(1, 1, 1, 0.62) : Qt.rgba(0, 0, 0, 0.52)
    readonly property color fgHour: dark ? Qt.rgba(1, 1, 1, 0.85) : Qt.rgba(0, 0, 0, 0.70)
    readonly property color line: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12)
    readonly property color barTrack: dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.14)
    readonly property color barFill: dark ? Qt.rgba(1, 1, 1, 0.85) : Qt.rgba(0, 0, 0, 0.62)
    // glass tint: the same as Clock / Calendar, so dark (light mode) / white (dark mode) text stays readable on any wallpaper
    readonly property real tint: Math.min(0.92, dark ? 0.06 + glassOpacity * 0.5 : 0.45 + glassOpacity * 0.9)

    // ───────────────────────── background ─────────────────────────
    // Normal: solid card
    Rectangle {
        anchors.fill: parent
        visible: w.style === "normal"
        radius: w.radiusPx
        gradient: Gradient {
            GradientStop { position: 0.0; color: w.dark ? "#3A3A3D" : "#FFFFFF" }
            GradientStop { position: 1.0; color: w.dark ? "#2A2A2D" : "#EFEFF3" }
        }
    }

    // Liquid fallback / gallery preview: frosted card (while the shader builds, if it fails, and in Settings)
    Rectangle {
        anchors.fill: parent
        visible: w.style === "liquid" && !w.glassOn
        radius: w.radiusPx
        gradient: Gradient {
            GradientStop { position: 0.0; color: w.dark ? Qt.rgba(0.22, 0.22, 0.25, 0.82) : Qt.rgba(1.0, 1.0, 1.0, 0.88) }
            GradientStop { position: 1.0; color: w.dark ? Qt.rgba(0.13, 0.13, 0.15, 0.82) : Qt.rgba(0.92, 0.92, 0.95, 0.88) }
        }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, w.dark ? 0.10 : 0.35) }
                GradientStop { position: 0.6; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }
    }

    // Liquid Glass: wallpaper crop → blur → refraction shader (the same maths as the Dock)
    Loader {
        id: glassLoader
        anchors.fill: parent
        active: w.glassOn
        sourceComponent: Item {
            id: gl
            // ── render once, then rest (saves GPU and RAM) ──
            // The wallpaper -> blur textures are captured when something changed (wallpaper, size, position, blur) and then left alone.
            // They only stream while an animated wallpaper plays inside the glass, or for a moment while the widget is moved / resized.
            property bool moving: false
            readonly property bool streaming: w.wallVideo !== "" || moving
            readonly property string capSig: [w.wallUrl, w.screenX, w.screenY, w.screenW, w.screenH, w.width, w.height, w.glassBlur, w.shaderUrl].join("|")
            onCapSigChanged: { moving = true; settle.restart(); }
            property int capStep: 0
            function recap() { capStep = 0; capTimer.restart(); }
            Timer { id: settle; interval: 450; onTriggered: { gl.moving = false; gl.recap(); } }
            Timer {
                id: capTimer
                interval: 60
                onTriggered: {
                    // two stages, in order: the wallpaper capture first, then the blur that reads it
                    if (gl.capStep === 0) bsrc.scheduleUpdate(); else blurred.scheduleUpdate();
                    gl.capStep++;
                    if (gl.capStep < 2) capTimer.restart();
                }
            }
            Component.onCompleted: recap()
            readonly property real margin: 72           // backdrop captured around the widget (blur + refraction reach)
            readonly property real padPx: 10            // shader item padding (soft shadow)
            readonly property real ds: w.glassBlur >= 8 ? 0.5 : 1.0
            readonly property real bn: Math.min(1.0, w.glassBlur * 1.4 * ds / 64.0)

            // the part of the wallpaper behind the widget, laid out exactly like the screen
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
                    onStatusChanged: if (status === Image.Ready) { gl.moving = true; settle.restart(); }
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: w.screenW
                    smooth: true
                }
                LiveWall {
                    x: -(w.screenX - gl.padPx - gl.margin)
                    y: -(w.screenY - gl.padPx - gl.margin)
                    width: w.screenW
                    height: w.screenH
                    video: w.wallVideo
                    live: w.wallVideo !== ""
                    paused: w.wallPaused
                }
            }
            ShaderEffectSource {
                id: bsrc
                sourceItem: backdrop
                hideSource: true
                live: gl.streaming
                visible: false
                textureSize: Qt.size(Math.max(1, Math.round(backdrop.width * gl.ds)),
                                     Math.max(1, Math.round(backdrop.height * gl.ds)))
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
                live: gl.streaming
                visible: false
            }
            ShaderEffect {
                x: -gl.padPx
                y: -gl.padPx
                width: w.width + 2 * gl.padPx
                height: w.height + 2 * gl.padPx
                fragmentShader: w.shaderUrl
                onStatusChanged: if (status === ShaderEffect.Error) w.glassFailed()

                property variant src: blurred
                property vector2d itemSize: Qt.vector2d(width, height)
                property vector2d glassSize: Qt.vector2d(w.width, w.height)
                property vector2d srcSize: Qt.vector2d(backdrop.width, backdrop.height)
                property vector2d srcOffset: Qt.vector2d(gl.margin, gl.margin)
                property real pad: gl.padPx
                property real radius: w.radiusPx
                property real bezel: Math.min(Math.min(w.width, w.height) * 0.36, 26)
                property real thickness: 30 * w.glassLiquid
                property real dispersion: 0.06 * w.glassLiquid
                property real magnify: 0.08 * w.glassLiquid * Math.min(1, 90 / w.height)
                property real rim: w.glassRim
                property real grain: w.glassGrain * 0.15   // much finer / quieter than the Dock's noise
                property real blurPx: 1.0            // tiny residual smoothing; the real blur is the MultiEffect pre-pass
                property real tintMix: w.tint
                property real saturation: 1.25
                property real dark: w.dark ? 1 : 0
                property real debug: 0
                property real shadowAmt: 0           // no drop shadow
                property real flatInner: 1           // no darker inner edge (needs the rebuilt liquidglass shader)
                property real rimTint: 1             // rim + border follow the glass's own colour
                property real ringW: 0               // the border is the Control Center CornerBorder below
            }
        }
    }

    // Control Center border (all styles): thin, fades out at the top-right / bottom-left corners, in the wallpaper's colour
    CornerBorder {
        z: 2
        anchors.fill: parent
        cornerR: w.radiusPx
        dark: w.dark
        tint: w.borderTint
        lineW: 0.8
    }

    // ───────────────────────── content ─────────────────────────
    readonly property real pad: 15 * s

    // city (+ location arrow)
    Row {
        x: w.pad
        y: w.pad - 1 * w.s
        spacing: 4 * w.s
        Text {
            id: cityText
            text: w.city
            width: Math.min(implicitWidth, 158 * w.s - 2 * w.pad - (w.located ? 14 * w.s : 0))
            elide: Text.ElideRight
            color: w.fg
            font.family: Fonts.forWeight(font.weight, w.fam)
            font.pixelSize: 15 * w.s
            font.weight: Font.DemiBold
        }
        Canvas {
            visible: w.located
            anchors.verticalCenter: cityText.verticalCenter
            anchors.verticalCenterOffset: 1 * w.s
            width: 9 * w.s
            height: 9 * w.s
            onWidthChanged: requestPaint()
            Connections { target: w; function onDarkChanged() { loc.requestPaint(); } }
            id: loc
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                ctx.clearRect(0, 0, width, height);
                ctx.fillStyle = w.dark ? "white" : "#1c1c1e";
                ctx.beginPath();            // location arrow, pointing up-right
                ctx.moveTo(width, 0);
                ctx.lineTo(0.05 * width, 0.42 * height);
                ctx.lineTo(0.58 * width, 0.46 * height);
                ctx.lineTo(0.62 * width, 1.0 * height);
                ctx.closePath();
                ctx.fill();
            }
        }
    }

    // big temperature
    Text {
        x: w.pad - 1 * w.s
        y: 30 * w.s
        text: w.hasData ? (w.temp + w.unitSuffix) : "–°"
        color: w.fg
        font.family: w.fam
        font.pixelSize: 46 * w.s
        font.weight: Font.Light
    }

    // condition + high / low (bottom-left; top-right in the large widget)
    Column {
        id: condCol
        width: w.isLarge ? 150 * w.s : 158 * w.s - 2 * w.pad
        x: w.isLarge ? w.width - w.pad - width : w.pad
        y: w.isLarge ? 36 * w.s : 158 * w.s - w.pad + 1 * w.s - implicitHeight
        spacing: 1 * w.s

        Item {
            visible: w.showIcon(w.kind)
            width: parent.width
            height: visible ? 23 * w.s : 0
            WeatherIcon {
                x: w.isLarge ? parent.width - width : 0
                kind: w.kind
                size: 20 * w.s
            }
        }
        Text {
            width: parent.width
            horizontalAlignment: w.isLarge ? Text.AlignRight : Text.AlignLeft
            text: w.cond
            elide: Text.ElideRight
            color: w.fg
            font.family: Fonts.forWeight(font.weight, w.fam)
            font.pixelSize: 14 * w.s
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            horizontalAlignment: w.isLarge ? Text.AlignRight : Text.AlignLeft
            text: w.hasData ? ("H:" + w.hi + w.unitSuffix + " L:" + w.lo + w.unitSuffix) : " "
            color: w.fg
            font.family: Fonts.forWeight(font.weight, w.fam)
            font.pixelSize: 14 * w.s
            font.weight: Font.DemiBold
        }
    }


    // ── medium: hourly forecast on the right ──
    Rectangle {   // divider
        visible: w.isMedium
        x: 164 * w.s; y: 16 * w.s
        width: 1; height: w.height - 32 * w.s
        color: w.line
    }
    Row {
        visible: w.isMedium
        x: 172 * w.s
        anchors.verticalCenter: parent.verticalCenter
        Repeater {
            model: w.isMedium ? w.hourly.slice(0, 4) : []
            delegate: WeatherHourCol {
                required property var modelData
                info: modelData
                wd: w
                colW: (w.width - 172 * w.s - w.pad + 4 * w.s) / 4
            }
        }
    }

    // ── large: hourly strip + 5-day list ──
    Rectangle { visible: w.isLarge; x: w.pad; y: 134 * w.s; width: w.width - 2 * w.pad; height: 1; color: w.line }
    Row {
        visible: w.isLarge
        x: w.pad
        y: 142 * w.s
        Repeater {
            model: w.isLarge ? w.hourly.slice(0, 6) : []
            delegate: WeatherHourCol {
                required property var modelData
                info: modelData
                wd: w
                colW: (w.width - 2 * w.pad) / 6
            }
        }
    }
    Rectangle { visible: w.isLarge; x: w.pad; y: 206 * w.s; width: w.width - 2 * w.pad; height: 1; color: w.line }
    Column {
        id: dailyCol
        visible: w.isLarge
        x: w.pad
        y: 210 * w.s
        width: w.width - 2 * w.pad
        readonly property var days: w.daily.slice(0, 5)
        readonly property real minT: { var m = 1e9; for (var i = 0; i < days.length; i++) m = Math.min(m, days[i].lo); return m; }
        readonly property real maxT: { var m = -1e9; for (var i = 0; i < days.length; i++) m = Math.max(m, days[i].hi); return m; }
        Repeater {
            model: dailyCol.days
            delegate: Item {
                id: dr
                required property var modelData
                width: dailyCol.width
                height: 27 * w.s
                readonly property real span: Math.max(1, dailyCol.maxT - dailyCol.minT)
                Text {
                    x: 0
                    width: 66 * w.s
                    anchors.verticalCenter: parent.verticalCenter
                    text: dr.modelData.d
                    color: w.fg
                    font.family: Fonts.forWeight(font.weight, w.fam)
                    font.pixelSize: 14 * w.s
                    font.weight: Font.DemiBold
                }
                WeatherIcon {
                    x: 72 * w.s
                    anchors.verticalCenter: parent.verticalCenter
                    visible: w.showIcon(dr.modelData.k)
                    kind: dr.modelData.k
                    size: 18 * w.s
                }
                Text {
                    x: 104 * w.s
                    width: 32 * w.s
                    horizontalAlignment: Text.AlignRight
                    anchors.verticalCenter: parent.verticalCenter
                    text: dr.modelData.lo + w.unitSuffix
                    color: w.fgSub
                    font.family: Fonts.forWeight(font.weight, w.fam)
                    font.pixelSize: 14 * w.s
                    font.weight: Font.DemiBold
                }
                Rectangle {   // temperature range bar
                    id: track
                    x: 144 * w.s
                    width: dr.width - 144 * w.s - 38 * w.s
                    height: 4 * w.s
                    radius: height / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: w.barTrack
                    Rectangle {
                        x: track.width * (dr.modelData.lo - dailyCol.minT) / dr.span
                        width: Math.max(track.height, track.width * (dr.modelData.hi - dr.modelData.lo) / dr.span)
                        height: parent.height
                        radius: height / 2
                        color: w.barFill
                    }
                }
                Text {
                    x: dr.width - 32 * w.s
                    width: 32 * w.s
                    horizontalAlignment: Text.AlignRight
                    anchors.verticalCenter: parent.verticalCenter
                    text: dr.modelData.hi + w.unitSuffix
                    color: w.fg
                    font.family: Fonts.forWeight(font.weight, w.fam)
                    font.pixelSize: 14 * w.s
                    font.weight: Font.DemiBold
                }
            }
        }
    }
}
