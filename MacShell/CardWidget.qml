// One desktop widget card in the macOS Tahoe style, for widgets whose contents come from ExtraWidgets.qml
// (Batteries, Notes, Photos, Reminders, Alarms, Stocks). The card, sizes, styles and Liquid Glass are the
// Calendar widget's own; the contents get a `ctx` ({ size: "s" | "m" | "l", fg, fg2, mono, dark }) from their parent.
//   size:  "small" · "medium" · "large"     style: "liquid" | "normal"     mode: "auto" | "light" | "dark"
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
    property Component content: null    // ExtraWidgets.comp(type)

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
    readonly property color line: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12)
    // glass tint: stronger than the Weather widget's, so black (light mode) / white (dark mode) text stays readable on any wallpaper
    readonly property real tint: Math.min(0.92, dark ? 0.25 + glassOpacity * 0.8 : 0.45 + glassOpacity * 0.9)

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
    Loader {
        id: body
        // what the contents read: the size they are drawn at, and the text colours for this card
        readonly property var ctx: ({ size: w.isSmall ? "s" : (w.isMedium ? "m" : "l"), fg: w.fg, fg2: w.fgSub, mono: false, dark: w.dark })
        x: 16 * w.s; y: 14 * w.s
        width: (w.width / w.s - 32) ; height: (w.height / w.s - 28)
        scale: w.s; transformOrigin: Item.TopLeft
        z: 3
        sourceComponent: w.content
    }
}
