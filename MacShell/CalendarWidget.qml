// macOS  style Calendar widget (month grid, today in red).
//   size:  "small" 158x158 · "medium" 338x158 · "large" 338x354   (macOS point sizes, times scaleF) – same as the Weather widget
//   style: "liquid" – Liquid Glass: the wallpaper behind the widget is blurred + refracted by liquidglass.frag, using the
//                     Appearance sliders (Translucency / Blur / Liquid strength)
//          "normal" – solid card
//   mode:  "auto"  – follows the shell's Dark / Light setting (Settings → Appearance)
//          "light" – bright glass, dark text
//          "dark"  – dark glass, white text
//
//   small  : month name + month grid
//   medium : weekday + big day number + month on the left, month grid on the right
//   large  : big month / year header + large month grid
//
// The item's own x / y are its position on the screen, which is how the glass knows which part of the wallpaper
// sits behind it (it follows the widget while it is dragged).
import QtQuick
import QtQuick.Effects

Item {
    id: w

    // ── look ──
    property string style: "liquid"
    property string size: "small"
    property string mode: "auto"        // "auto" | "light" | "dark"
    property real scaleF: 1.0
    property string fam: "Open Runde"
    property real screenX: x
    property real screenY: y
    property int weekStart: 0           // 0 = Sunday, 1 = Monday

    // ── liquid glass inputs (the Appearance sliders) ──
    property bool glassReady: false     // liquidglass.frag.qsb compiled
    property url shaderUrl: ""
    property url wallUrl: ""
    property real screenW: 1920
    property real screenH: 1080
    property real glassOpacity: 0.42    // Translucency
    property real glassBlur: 5          // Blur
    property real glassLiquid: 1.0      // Liquid strength
    property real glassRim: 0.45
    property color borderTint: "#8A9AB5"      // Control Center border colour
    property real glassGrain: 0.03
    property bool darkGlass: true       // the shell's Dark / Light setting (used by mode "auto")
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

    // ── light / dark ──
    readonly property bool dark: mode === "dark" || (mode !== "light" && darkGlass)
    readonly property color fg: dark ? Qt.rgba(1, 1, 1, 0.96) : Qt.rgba(0, 0, 0, 0.86)
    readonly property color fgSub: dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.45)
    readonly property color red: dark ? "#FF453A" : "#FF3B30"
    readonly property color line: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12)
    // glass tint: stronger than the Weather widget's, so black (light mode) / white (dark mode) text stays readable on any wallpaper
    readonly property real tint: Math.min(0.92, dark ? 0.25 + glassOpacity * 0.8 : 0.45 + glassOpacity * 0.9)

    // ── date ──
    property var now: new Date()
    Timer {   // roll over at midnight (and pick up clock / time-zone changes)
        interval: 30000
        repeat: true
        running: true
        onTriggered: { var d = new Date(); if (d.toDateString() !== w.now.toDateString()) w.now = d; }
    }
    readonly property var monthNames: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    readonly property var dayNames: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    readonly property var letters: ["S", "M", "T", "W", "T", "F", "S"]
    readonly property var cal: {
        var d = w.now, y = d.getFullYear(), m = d.getMonth();
        var first = new Date(y, m, 1).getDay();
        return { year: y, month: m, today: d.getDate(), weekday: d.getDay(),
                 lead: (first - w.weekStart + 7) % 7, days: new Date(y, m + 1, 0).getDate() };
    }

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

    // Liquid Glass: wallpaper crop → blur → refraction shader (the same maths as the Dock and the Weather widget)
    Loader {
        id: glassLoader
        anchors.fill: parent
        active: w.glassOn
        sourceComponent: Item {
            id: gl
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
                live: true
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
                property real dark: w.dark ? 1 : 0   // this widget's own light / dark mode, not the shell's
                property real debug: 0
                property real shadowAmt: 0           // no drop shadow
                property real flatInner: 1           // no darker inner edge (needs the rebuilt liquidglass shader)
                property real rimTint: 1             // rim + border follow the glass's own colour
                property real ringW: 0               // the border is the Control Center CornerBorder below
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

    // ───────────────────────── content ─────────────────────────
    readonly property real pad: 15 * s

    // The month grid: weekday letters, then up to 6 rows of days. Today sits in a red circle.
    //
    // Every position and size below is a whole pixel, and the circle and the day number share one box. Fractional
    // positions made the circle (anti-aliased, can sit on a half pixel) and the digits (text is drawn on whole pixels)
    // land up to a pixel apart, which is what looked off-centre. (Open Runde's digits are exactly as tall as the gap
    // between its ascent and descent, so a text box centred on the circle also centres the digits.)
    readonly property var gridSpec: isSmall ? { x: 12, y: 32, w: 134, wdH: 16, rowH: 16.7, wdPx: 10.5, dayPx: 11.5, circ: 17 }
                                  : (isMedium ? { x: 172, y: 11, w: 152, wdH: 18, rowH: 19.5, wdPx: 11, dayPx: 12.5, circ: 18 }
                                              : { x: 15, y: 58, w: 308, wdH: 24, rowH: 44, wdPx: 13, dayPx: 19, circ: 33 })
    Item {
        id: grid
        x: Math.round(w.gridSpec.x * w.s)
        y: Math.round(w.gridSpec.y * w.s)
        width: Math.round(w.gridSpec.w * w.s)
        height: wdH + 6 * rowH
        readonly property real cw: width / 7
        readonly property int wdH: Math.round(w.gridSpec.wdH * w.s)
        readonly property int rowH: Math.round(w.gridSpec.rowH * w.s)
        readonly property real wdPx: w.gridSpec.wdPx * w.s
        readonly property real dayPx: w.gridSpec.dayPx * w.s
        readonly property int circ: 2 * Math.round(w.gridSpec.circ * w.s / 2)      // even, so the centre is a whole pixel

        Repeater {
            model: 7
            delegate: Text {
                required property int index
                x: Math.round((index + 0.5) * grid.cw - implicitWidth / 2)
                y: Math.round((grid.wdH - implicitHeight) / 2)
                text: w.letters[(index + w.weekStart) % 7]
                color: w.fgSub
                font.family: w.fam
                font.pixelSize: grid.wdPx
                font.weight: Font.DemiBold
            }
        }
        Repeater {
            model: 42
            delegate: Item {
                id: cell
                required property int index
                readonly property int day: index - w.cal.lead + 1
                readonly property bool valid: day >= 1 && day <= w.cal.days
                readonly property bool isToday: valid && day === w.cal.today
                visible: valid
                // the box that holds the circle and the number: a whole-pixel square centred in the cell
                x: Math.round((index % 7 + 0.5) * grid.cw) - grid.circ / 2
                y: grid.wdH + Math.floor(index / 7) * grid.rowH + Math.round((grid.rowH - grid.circ) / 2)
                width: grid.circ
                height: grid.circ
                Rectangle {
                    visible: cell.isToday
                    anchors.fill: parent
                    radius: width / 2
                    color: w.red
                }
                Text {
                    anchors.fill: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: cell.day
                    color: cell.isToday ? "white" : w.fg
                    font.family: w.fam
                    font.pixelSize: grid.dayPx
                    font.weight: cell.isToday ? Font.Bold : Font.DemiBold
                }
            }
        }
    }

    // ── small: month name above the grid ──
    Text {
        visible: w.isSmall
        x: 13 * w.s
        y: 10 * w.s
        text: w.monthNames[w.cal.month].toUpperCase()
        color: w.red
        font.family: w.fam
        font.pixelSize: 13 * w.s
        font.weight: Font.Bold
    }

    // ── medium: weekday, big day number and month on the left ──
    Rectangle {   // divider
        visible: w.isMedium
        x: 164 * w.s; y: 16 * w.s
        width: 1; height: w.height - 32 * w.s
        color: w.line
    }
    Text {
        visible: w.isMedium
        x: w.pad
        y: 14 * w.s
        width: 142 * w.s
        elide: Text.ElideRight
        text: w.dayNames[w.cal.weekday].toUpperCase()
        color: w.red
        font.family: w.fam
        font.pixelSize: 13 * w.s
        font.weight: Font.Bold
    }
    Text {
        visible: w.isMedium
        x: w.pad - 1 * w.s
        y: 30 * w.s
        text: w.cal.today
        color: w.fg
        font.family: w.fam
        font.pixelSize: 58 * w.s
        font.weight: Font.Light
    }
    Text {
        visible: w.isMedium
        x: w.pad
        y: w.height - w.pad + 1 * w.s - implicitHeight
        width: 142 * w.s
        elide: Text.ElideRight
        text: w.monthNames[w.cal.month] + " " + w.cal.year
        color: w.fgSub
        font.family: w.fam
        font.pixelSize: 14 * w.s
        font.weight: Font.DemiBold
    }

    // ── large: month + year header, hairline under the weekday row ──
    Row {
        visible: w.isLarge
        x: w.pad
        y: 13 * w.s
        spacing: 7 * w.s
        Text {
            text: w.monthNames[w.cal.month]
            color: w.red
            font.family: w.fam
            font.pixelSize: 26 * w.s
            font.weight: Font.DemiBold
        }
        Text {
            text: w.cal.year
            color: w.fgSub
            font.family: w.fam
            font.pixelSize: 26 * w.s
            font.weight: Font.DemiBold
        }
    }
    Rectangle {
        visible: w.isLarge
        x: w.pad
        y: grid.y + grid.wdH
        width: w.width - 2 * w.pad
        height: 1
        color: w.line
    }
}
