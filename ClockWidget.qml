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
    property string fam: "Inter"
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
    property real glassGrain: 0.03
    property bool darkGlass: true

    signal glassFailed()

    readonly property bool isSmall: size === "small"
    readonly property bool isMedium: size === "medium"
    readonly property bool isLarge: size === "large"

    readonly property real s:
        scaleF * (isLarge ? 354 / 158 : 168 / 158)

    readonly property real radiusPx: 28 * s

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

    // Update often enough that the active tick glides smoothly.
    Timer {
        interval: 33
        repeat: true
        running: true
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

    // Light face.
    Rectangle {
        anchors.fill: parent
        visible: w.style === "light"
        radius: w.radiusPx
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.14)

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#F4F5F3" }
            GradientStop { position: 0.55; color: "#F0F1EF" }
            GradientStop { position: 1.0; color: "#E7E9E6" }
        }
    }

    // Dark face.
    Rectangle {
        anchors.fill: parent
        visible: w.style === "dark"
        radius: w.radiusPx
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.20)

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
                property real shadowAmt: 1
                property real rimTint: 1
                property real ringW: 1
            }
        }
    }

    // Static/fallback edge.
    Rectangle {
        anchors.fill: parent
        visible: !w.glassOn
        radius: w.radiusPx
        color: "transparent"
        border.width: 1
        border.color:
            w.dark ? Qt.rgba(1, 1, 1, 0.20)
                   : Qt.rgba(0, 0, 0, 0.11)
    }

    // Perimeter ticks follow the rounded bezel.
    function tickAt(index) {
        var inset = 10.5 * w.s
        var cr = Math.max(2 * w.s, w.radiusPx - inset)

        var left = inset
        var top = inset
        var right = w.width - inset
        var bottom = w.height - inset

        var straightH = Math.max(0, right - left - 2 * cr)
        var straightV = Math.max(0, bottom - top - 2 * cr)
        var arc = Math.PI * cr / 2
        var perimeter = 2 * straightH + 2 * straightV + 4 * arc

        var d = ((index + 0.5) / 60) * perimeter
        var x = 0
        var y = 0
        var angle = 0

        // Start at the top edge and travel clockwise.
        if (d < straightH) {
            x = left + cr + d
            y = top
            angle = 0
        } else if ((d -= straightH) < arc) {
            var a1 = -Math.PI / 2 + d / cr
            x = right - cr + cr * Math.cos(a1)
            y = top + cr + cr * Math.sin(a1)
            angle = (a1 + Math.PI / 2) * 180 / Math.PI
        } else if ((d -= arc) < straightV) {
            x = right
            y = top + cr + d
            angle = 90
        } else if ((d -= straightV) < arc) {
            var a2 = d / cr
            x = right - cr + cr * Math.cos(a2)
            y = bottom - cr + cr * Math.sin(a2)
            angle = (a2 + Math.PI / 2) * 180 / Math.PI
        } else if ((d -= arc) < straightH) {
            x = right - cr - d
            y = bottom
            angle = 0
        } else if ((d -= straightH) < arc) {
            var a3 = Math.PI / 2 + d / cr
            x = left + cr + cr * Math.cos(a3)
            y = bottom - cr + cr * Math.sin(a3)
            angle = (a3 + Math.PI / 2) * 180 / Math.PI
        } else if ((d -= arc) < straightV) {
            x = left
            y = bottom - cr - d
            angle = 90
        } else {
            d -= straightV
            var a4 = Math.PI + d / cr
            x = left + cr + cr * Math.cos(a4)
            y = top + cr + cr * Math.sin(a4)
            angle = (a4 + Math.PI / 2) * 180 / Math.PI
        }

        return {
            x: x,
            y: y,
            angle: angle + 32
        }
    }

    Repeater {
        model: 60

        delegate: Rectangle {
            required property int index

            readonly property var tick: w.tickAt(index)
            readonly property bool major: index % 5 === 0

            readonly property real secondProgress:
                Math.max(0, Math.min(1,
                    w.now.getSeconds()
                    + w.now.getMilliseconds() / 1000
                    - index))

            readonly property real baseOpacity: w.dark
                ? (major ? 0.42 : 0.26)
                : (major ? 0.28 : 0.16)

            readonly property real peakOpacity: w.dark
                ? (major ? 0.78 : 0.62)
                : (major ? 0.68 : 0.50)

            width: 1.8 * w.s
            height: (major ? 7 : 5) * w.s

            x: tick.x - width / 2
            y: tick.y - height / 2

            radius: width / 2
            rotation: tick.angle
            color: w.dark ? "white" : "#101113"

            opacity: baseOpacity
                     + (peakOpacity - baseOpacity) * secondProgress

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on rotation {
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    // City label: RIY for Riyadh by default.
    Text {
        id: cityLabel

        anchors.horizontalCenter: parent.horizontalCenter
        y: 22 * w.s
        height: 17 * w.s

        text: w.cityCode

        color: w.dark
            ? Qt.rgba(1, 1, 1, 0.72)
            : Qt.rgba(0, 0, 0, 0.65)

        font.family: w.fam
        font.pixelSize: 11 * w.s
        font.weight: Font.Bold
        font.letterSpacing: 1.0 * w.s

        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    // Bolder clock numerals.
    Text {
        id: clockText

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -2 * w.s

        width: parent.width - 26 * w.s
        height: Math.min(parent.height - 38 * w.s, 92 * w.s)

        text: w.displayTime

        color: w.dark ? "#FFFFFF" : "#111214"

        font.family: w.fam
        font.pixelSize: 72 * w.s
        font.weight: Font.Black
        font.letterSpacing: -3.0 * w.s

        // Same-color outline makes the numerals appear thicker.
        style: Text.Outline
        styleColor: color

        // Preserve the compact proportions of the original design.
	transform: Scale {
	    origin.x: clockText.width / 2
	    origin.y: clockText.height / 2
	    xScale: 0.80
	    yScale: 1.30
	}
	
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter

        minimumPixelSize: 10
        fontSizeMode: Text.Fit
    }
}
