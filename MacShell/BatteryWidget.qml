// macOS Battery Widget (Apple Sonoma / Tahoe style)
// sizes: Small (168x168), Medium (358x168)
// styles: "liquid" | "normal"

import QtQuick
import QtQuick.Effects
import Quickshell.Io

Item {
    id: w

    property string style: "liquid"
    property string size: "small"
    property real scaleF: 1.0
    property string fam: "Inter"
    property real screenX: x
    property real screenY: y
    property bool editing: false

    // Liquid Glass properties
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
    readonly property real u: Math.min(width, height) / 158
    readonly property real radiusPx: 28 * scaleF * (isSmall ? 168 / 158 : (isMedium ? 358 / 338 : 1))

    readonly property bool dark: style === "dark" || (style === "liquid" && darkGlass)
    readonly property bool glassOn: style === "liquid" && glassReady && wallUrl != ""

    width: (isSmall ? 158 : 358) * scaleF * (isSmall ? 168 / 158 : (isMedium ? 358 / 338 : 1.0))
    height: 168 * scaleF

    // Battery devices data
    property var devList: [
        { id: "BAT0", name: "MacBook", type: "laptop", percentage: 58, charging: false, status: "discharging", time: "" }
    ]
    readonly property var firstDev: (devList && devList.length > 0) ? devList[0] : ({ percentage: 100, charging: false, name: "Battery", time: "" })

    readonly property string readerScript: decodeURIComponent(Qt.resolvedUrl("battery_reader.py").toString().replace(/^file:\/\//, ""))

    Process {
        id: batProc
        command: ["python3", w.readerScript]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var s = text.trim();
                    if (s.indexOf("[") >= 0) {
                        var parsed = JSON.parse(s);
                        if (Array.isArray(parsed) && parsed.length > 0) {
                            w.devList = parsed;
                        }
                    }
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 8000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!batProc.running) batProc.running = true;
        }
    }

    function ringColor(pct, charging) {
        if (charging) return "#34C759";
        if (pct <= 10) return "#FF3B30";
        if (pct <= 20) return "#FFCC00";
        return "#34C759";
    }

    // ───────────── Backdrop ─────────────
    // Normal / Solid style
    Rectangle {
        anchors.fill: parent
        visible: !w.glassOn
        radius: w.radiusPx
        gradient: Gradient {
            GradientStop { position: 0.0; color: w.dark ? Qt.rgba(0.18, 0.18, 0.22, 0.92) : Qt.rgba(1.0, 1.0, 1.0, 0.92) }
            GradientStop { position: 1.0; color: w.dark ? Qt.rgba(0.11, 0.11, 0.14, 0.92) : Qt.rgba(0.93, 0.93, 0.96, 0.92) }
        }
        border.color: w.dark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.08)
        border.width: 1
    }

    readonly property real tint: Math.min(0.92, dark ? 0.25 + glassOpacity * 0.8 : 0.45 + glassOpacity * 0.9)

    // Liquid Glass backdrop
    Loader {
        anchors.fill: parent
        active: w.glassOn
        sourceComponent: Item {
            id: gl
            readonly property real margin: 72
            readonly property real padPx: 10
            readonly property real ds: w.glassBlur >= 8 ? 0.5 : 1.0
            readonly property real bn: Math.min(1.0, w.glassBlur * 1.4 * ds / 64.0)

            property bool updating: true
            Timer {
                id: settleTimer
                interval: 350
                onTriggered: gl.updating = false
            }
            function triggerUpdate() {
                gl.updating = true;
                settleTimer.restart();
            }
            Connections {
                target: w
                function onScreenXChanged() { gl.triggerUpdate(); }
                function onScreenYChanged() { gl.triggerUpdate(); }
                function onWallUrlChanged() { gl.triggerUpdate(); }
                function onGlassBlurChanged() { gl.triggerUpdate(); }
                function onGlassLiquidChanged() { gl.triggerUpdate(); }
                function onWidthChanged() { gl.triggerUpdate(); }
                function onHeightChanged() { gl.triggerUpdate(); }
                function onEditingChanged() { if (!w.editing) gl.triggerUpdate(); }
            }
            Component.onCompleted: gl.triggerUpdate()

            Item {
                id: backdrop
                width: w.width + 2 * (gl.padPx + gl.margin)
                height: w.height + 2 * (gl.padPx + gl.margin)
                Image {
                    id: bgImg
                    x: -(w.screenX - gl.padPx - gl.margin)
                    y: -(w.screenY - gl.padPx - gl.margin)
                    width: w.screenW; height: w.screenH
                    source: w.wallUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: w.screenW
                    smooth: true
                    onStatusChanged: if (status === Image.Ready) gl.triggerUpdate()
                }
            }

            ShaderEffectSource {
                id: bsrc
                sourceItem: backdrop
                hideSource: true
                live: w.editing || gl.updating
                visible: false
                textureSize: Qt.size(Math.max(1, Math.round(backdrop.width * gl.ds)), Math.max(1, Math.round(backdrop.height * gl.ds)))
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
                live: w.editing || gl.updating
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
                property real grain: w.glassGrain * 0.15
                property real blurPx: 1.0
                property real tintMix: w.tint
                property real saturation: 1.25
                property real dark: w.dark ? 1 : 0
                property real debug: 0
                property real shadowAmt: 1
                property real rimTint: 1
            }
        }
    }

    // Subtle edge highlight
    Rectangle {
        anchors.fill: parent
        radius: w.radiusPx
        color: "transparent"
        border.color: w.dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.45)
        border.width: 1
    }

    // ───────────── Content: Small (1 large ring OR 2x2 grid) ─────────────
    Item {
        id: smallContent
        anchors.fill: parent
        visible: w.isSmall

        // Single device prominent view (if 1 device)
        Item {
            anchors.fill: parent
            visible: w.devList.length <= 1

            Canvas {
                id: bigRing
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -10 * w.u
                width: 90 * w.u; height: 90 * w.u
                readonly property real pct: Math.max(0, Math.min(100, w.firstDev.percentage)) / 100.0
                readonly property color col: w.ringColor(w.firstDev.percentage, w.firstDev.charging)

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var cx = width / 2, cy = height / 2;
                    var r = (width - 10 * w.u) / 2;
                    // track
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, 0, Math.PI * 2);
                    ctx.strokeStyle = Qt.rgba(1, 1, 1, w.dark ? 0.12 : 0.20);
                    ctx.lineWidth = 9 * w.u;
                    ctx.lineCap = "round";
                    ctx.stroke();

                    // arc
                    if (pct > 0) {
                        ctx.beginPath();
                        var start = -Math.PI / 2;
                        ctx.arc(cx, cy, r, start, start + pct * Math.PI * 2);
                        ctx.strokeStyle = col;
                        ctx.lineWidth = 9 * w.u;
                        ctx.lineCap = "round";
                        ctx.stroke();
                    }
                }
                Connections {
                    target: w
                    function onDevListChanged() { bigRing.requestPaint(); }
                }
            }

            // Percentage in ring center
            Row {
                anchors.centerIn: bigRing
                spacing: 1 * w.u
                Text {
                    text: w.firstDev.percentage
                    font.family: w.fam
                    font.pixelSize: 26 * w.u
                    font.weight: Font.Bold
                    color: w.dark ? "#FFFFFF" : "#1D1D1F"
                }
                Text {
                    text: "%"
                    font.family: w.fam
                    font.pixelSize: 14 * w.u
                    font.weight: Font.DemiBold
                    color: w.dark ? Qt.rgba(1, 1, 1, 0.6) : Qt.rgba(0, 0, 0, 0.5)
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4 * w.u
                }
                WGlyph {
                    visible: w.firstDev.charging
                    width: 14 * w.u; height: 14 * w.u
                    kind: "bolt"
                    color: "#34C759"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Label at bottom
            Column {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14 * w.u
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 2 * w.u
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: w.firstDev.name
                    font.family: w.fam
                    font.pixelSize: 12 * w.u
                    font.weight: Font.Medium
                    color: w.dark ? Qt.rgba(1, 1, 1, 0.75) : Qt.rgba(0, 0, 0, 0.70)
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: w.firstDev.charging ? "Charging" : (w.firstDev.time !== "" ? w.firstDev.time : "On Battery")
                    font.family: w.fam
                    font.pixelSize: 10 * w.u
                    color: w.dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.40)
                }
            }
        }

        // Multi-device 2x2 Grid (if > 1 device)
        Grid {
            anchors.centerIn: parent
            visible: w.devList.length > 1
            columns: 2
            spacing: 12 * w.u

            Repeater {
                model: w.devList.slice(0, 4)
                delegate: Item {
                    id: miniCell
                    required property var modelData
                    width: 64 * w.u; height: 64 * w.u
                    readonly property var d: modelData

                    Canvas {
                        id: miniRing
                        anchors.centerIn: parent
                        width: 50 * w.u; height: 50 * w.u
                        readonly property real pct: Math.max(0, Math.min(100, d.percentage)) / 100.0
                        readonly property color col: w.ringColor(d.percentage, d.charging)
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.reset();
                            var cx = width / 2, cy = height / 2;
                            var r = (width - 6 * w.u) / 2;
                            ctx.beginPath();
                            ctx.arc(cx, cy, r, 0, Math.PI * 2);
                            ctx.strokeStyle = Qt.rgba(1, 1, 1, w.dark ? 0.12 : 0.20);
                            ctx.lineWidth = 5 * w.u;
                            ctx.lineCap = "round";
                            ctx.stroke();

                            if (pct > 0) {
                                ctx.beginPath();
                                var start = -Math.PI / 2;
                                ctx.arc(cx, cy, r, start, start + pct * Math.PI * 2);
                                ctx.strokeStyle = col;
                                ctx.lineWidth = 5 * w.u;
                                ctx.lineCap = "round";
                                ctx.stroke();
                            }
                        }
                    }

                    // Icon in center of ring
                    WGlyph {
                        anchors.centerIn: miniRing
                        width: 18 * w.u; height: 18 * w.u
                        kind: d.type === "headphones" ? "headphones"
                            : (d.type === "mouse" ? "mouse"
                            : (d.type === "keyboard" ? "keyboard" : "monitor"))
                        color: w.dark ? "white" : "#1D1D1F"
                    }

                    // Percentage badge below
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: miniRing.bottom
                        anchors.topMargin: 2 * w.u
                        spacing: 2 * w.u
                        Text {
                            text: d.percentage + "%"
                            font.family: w.fam
                            font.pixelSize: 10 * w.u
                            font.weight: Font.DemiBold
                            color: w.dark ? Qt.rgba(1, 1, 1, 0.8) : Qt.rgba(0, 0, 0, 0.75)
                        }
                        WGlyph {
                            visible: d.charging
                            width: 9 * w.u; height: 9 * w.u
                            kind: "bolt"
                            color: "#34C759"
                        }
                    }
                }
            }
        }
    }

    // ───────────── Content: Medium (Horizontal 4-device card or Detailed) ─────────────
    Item {
        id: medContent
        anchors.fill: parent
        visible: w.isMedium

        // Detailed layout when 1 device
        Row {
            anchors.fill: parent
            anchors.margins: 22 * w.u
            spacing: 24 * w.u
            visible: w.devList.length <= 1

            Canvas {
                id: medBigRing
                width: 100 * w.u; height: 100 * w.u
                anchors.verticalCenter: parent.verticalCenter
                readonly property real pct: Math.max(0, Math.min(100, w.firstDev.percentage)) / 100.0
                readonly property color col: w.ringColor(w.firstDev.percentage, w.firstDev.charging)

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var cx = width / 2, cy = height / 2;
                    var r = (width - 12 * w.u) / 2;
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, 0, Math.PI * 2);
                    ctx.strokeStyle = Qt.rgba(1, 1, 1, w.dark ? 0.12 : 0.20);
                    ctx.lineWidth = 10 * w.u;
                    ctx.lineCap = "round";
                    ctx.stroke();

                    if (pct > 0) {
                        ctx.beginPath();
                        var start = -Math.PI / 2;
                        ctx.arc(cx, cy, r, start, start + pct * Math.PI * 2);
                        ctx.strokeStyle = col;
                        ctx.lineWidth = 10 * w.u;
                        ctx.lineCap = "round";
                        ctx.stroke();
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 1 * w.u
                    Text {
                        text: w.firstDev.percentage
                        font.family: w.fam
                        font.pixelSize: 28 * w.u
                        font.weight: Font.Bold
                        color: w.dark ? "#FFFFFF" : "#1D1D1F"
                    }
                    Text {
                        text: "%"
                        font.family: w.fam
                        font.pixelSize: 15 * w.u
                        font.weight: Font.DemiBold
                        color: w.dark ? Qt.rgba(1, 1, 1, 0.6) : Qt.rgba(0, 0, 0, 0.5)
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4 * w.u
                    }
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6 * w.u
                Row {
                    spacing: 8 * w.u
                    WGlyph {
                        width: 18 * w.u; height: 18 * w.u
                        kind: "monitor"
                        color: w.dark ? "white" : "#1D1D1F"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: w.firstDev.name
                        font.family: w.fam
                        font.pixelSize: 16 * w.u
                        font.weight: Font.Bold
                        color: w.dark ? "#FFFFFF" : "#1D1D1F"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Row {
                    spacing: 6 * w.u
                    WGlyph {
                        visible: w.firstDev.charging
                        width: 14 * w.u; height: 14 * w.u
                        kind: "bolt"
                        color: "#34C759"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: w.firstDev.charging ? "Power Adapter Connected" : "Running on Battery"
                        font.family: w.fam
                        font.pixelSize: 13 * w.u
                        font.weight: Font.Medium
                        color: w.firstDev.charging ? "#34C759" : (w.dark ? Qt.rgba(1, 1, 1, 0.75) : Qt.rgba(0, 0, 0, 0.70))
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Text {
                    text: w.firstDev.time !== "" ? (w.firstDev.charging ? "Time until full: " + w.firstDev.time : "Remaining: " + w.firstDev.time) : (w.firstDev.charging ? "Charging" : "Normal Health")
                    font.family: w.fam
                    font.pixelSize: 12 * w.u
                    color: w.dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.45)
                }
            }
        }

        // Multi-device row (if > 1 device)
        Row {
            anchors.centerIn: parent
            spacing: 22 * w.u
            visible: w.devList.length > 1

            Repeater {
                model: w.devList.slice(0, 4)
                delegate: Column {
                    id: medCell
                    required property var modelData
                    spacing: 8 * w.u
                    width: 66 * w.u
                    readonly property var d: modelData

                    Canvas {
                        id: medColRing
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 60 * w.u; height: 60 * w.u
                        readonly property real pct: Math.max(0, Math.min(100, d.percentage)) / 100.0
                        readonly property color col: w.ringColor(d.percentage, d.charging)

                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.reset();
                            var cx = width / 2, cy = height / 2;
                            var r = (width - 7 * w.u) / 2;
                            ctx.beginPath();
                            ctx.arc(cx, cy, r, 0, Math.PI * 2);
                            ctx.strokeStyle = Qt.rgba(1, 1, 1, w.dark ? 0.12 : 0.20);
                            ctx.lineWidth = 6 * w.u;
                            ctx.lineCap = "round";
                            ctx.stroke();

                            if (pct > 0) {
                                ctx.beginPath();
                                var start = -Math.PI / 2;
                                ctx.arc(cx, cy, r, start, start + pct * Math.PI * 2);
                                ctx.strokeStyle = col;
                                ctx.lineWidth = 6 * w.u;
                                ctx.lineCap = "round";
                                ctx.stroke();
                            }
                        }

                        WGlyph {
                            anchors.centerIn: parent
                            width: 22 * w.u; height: 22 * w.u
                            kind: d.type === "headphones" ? "headphones"
                                : (d.type === "mouse" ? "mouse"
                                : (d.type === "keyboard" ? "keyboard" : "monitor"))
                            color: w.dark ? "white" : "#1D1D1F"
                        }
                    }

                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 2 * w.u
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 3 * w.u
                            Text {
                                text: d.percentage + "%"
                                font.family: w.fam
                                font.pixelSize: 13 * w.u
                                font.weight: Font.Bold
                                color: w.dark ? "#FFFFFF" : "#1D1D1F"
                            }
                            WGlyph {
                                visible: d.charging
                                width: 11 * w.u; height: 11 * w.u
                                kind: "bolt"
                                color: "#34C759"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: d.name
                            font.family: w.fam
                            font.pixelSize: 10 * w.u
                            font.weight: Font.Medium
                            color: w.dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.50)
                            elide: Text.ElideRight
                            width: 66 * w.u
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }
        }
    }
}

