// macOS System Monitor Widget (Apple Activity Monitor / iStat Menus style)
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
    readonly property bool isLarge: size === "large"
    readonly property real s: scaleF * (isSmall ? 168 / 158 : (isMedium ? 358 / 338 : 1.0))
    readonly property real u: s
    readonly property real radiusPx: 28 * s

    readonly property bool dark: style === "dark" || (style === "liquid" && darkGlass)
    readonly property bool glassOn: style === "liquid" && glassReady && wallUrl != ""

    width: (isSmall ? 158 : (isLarge ? 358 : 338)) * s
    height: (isLarge ? 354 : 168) * scaleF

    // System metrics data
    property int cpuPct: 15
    property int gpuPct: 20
    property int ramPct: 45
    property string ramUsed: "6.8G"
    property string ramTotal: "16.0G"
    property int diskPct: 65
    property string diskFree: "24G"
    property string diskTotal: "128G"
    property int tempVal: 52
    property string netSpeed: "120 KB/s"

    readonly property string readerScript: decodeURIComponent(Qt.resolvedUrl("sysmon_reader.py").toString().replace(/^file:\/\//, ""))

    Process {
        id: sysProc
        command: ["python3", w.readerScript]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var s = text.trim();
                    if (s.indexOf("{") >= 0) {
                        var o = JSON.parse(s);
                        w.cpuPct = o.cpu !== undefined ? o.cpu : w.cpuPct;
                        w.gpuPct = o.gpu !== undefined ? o.gpu : w.gpuPct;
                        w.ramPct = o.ram !== undefined ? o.ram : (o.ram_pct !== undefined ? o.ram_pct : w.ramPct);
                        w.ramUsed = o.ram_used !== undefined ? (o.ram_used + "G") : (o.ram_used || w.ramUsed);
                        w.ramTotal = o.ram_total !== undefined ? (o.ram_total + "G") : (o.ram_total || w.ramTotal);
                        w.diskPct = o.disk !== undefined ? o.disk : (o.disk_pct !== undefined ? o.disk_pct : w.diskPct);
                        w.diskFree = o.disk_free !== undefined ? (o.disk_free + " GB") : (w.diskFree);
                        w.diskTotal = o.disk_total !== undefined ? (o.disk_total + " GB") : (o.disk_total || w.diskTotal);
                        w.tempVal = o.temp !== undefined ? o.temp : w.tempVal;
                        w.netSpeed = o.net || o.net_speed || w.netSpeed;
                    }
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!sysProc.running) sysProc.running = true;
        }
    }

    // ───────────── Backdrop ─────────────
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

    Rectangle {
        anchors.fill: parent
        radius: w.radiusPx
        color: "transparent"
        border.color: w.dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.45)
        border.width: 1
    }

    // ───────────── Content: Small (2x2 Quad Gauge Grid) ─────────────
    Item {
        id: smallContent
        anchors.fill: parent
        visible: w.isSmall

        Grid {
            anchors.centerIn: parent
            columns: 2
            spacing: 8 * w.s

            // 1. CPU Gauge
            Item {
                width: 62 * w.s; height: 62 * w.s
                Canvas {
                    id: cpuRing
                    anchors.centerIn: parent
                    width: 48 * w.s; height: 48 * w.s
                    readonly property real pct: Math.max(0, Math.min(100, w.cpuPct)) / 100.0
                    onPaint: {
                        var ctx = getContext("2d"); ctx.reset();
                        var cx = width / 2, cy = height / 2, r = (width - 6 * w.s) / 2;
                        ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2);
                        ctx.strokeStyle = Qt.rgba(1, 1, 1, w.dark ? 0.12 : 0.20);
                        ctx.lineWidth = 4.5 * w.s; ctx.stroke();
                        if (pct > 0) {
                            ctx.beginPath(); ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + pct * Math.PI * 2);
                            ctx.strokeStyle = "#007AFF"; ctx.lineWidth = 4.5 * w.s; ctx.lineCap = "round"; ctx.stroke();
                        }
                    }
                    Connections { target: w; function onCpuPctChanged() { cpuRing.requestPaint(); } }
                }
                Column {
                    anchors.centerIn: cpuRing
                    spacing: 0
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: w.cpuPct + "%"
                        font.family: w.fam; font.pixelSize: 10.5 * w.s; font.weight: Font.Bold
                        color: w.dark ? "#FFFFFF" : "#1D1D1F"
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "CPU"
                        font.family: w.fam; font.pixelSize: 7.5 * w.s; font.weight: Font.DemiBold
                        color: "#007AFF"
                    }
                }
            }

            // 2. GPU Gauge
            Item {
                width: 62 * w.s; height: 62 * w.s
                Canvas {
                    id: gpuRing
                    anchors.centerIn: parent
                    width: 48 * w.s; height: 48 * w.s
                    readonly property real pct: Math.max(0, Math.min(100, w.gpuPct)) / 100.0
                    onPaint: {
                        var ctx = getContext("2d"); ctx.reset();
                        var cx = width / 2, cy = height / 2, r = (width - 6 * w.s) / 2;
                        ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2);
                        ctx.strokeStyle = Qt.rgba(1, 1, 1, w.dark ? 0.12 : 0.20);
                        ctx.lineWidth = 4.5 * w.s; ctx.stroke();
                        if (pct > 0) {
                            ctx.beginPath(); ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + pct * Math.PI * 2);
                            ctx.strokeStyle = "#30B0C7"; ctx.lineWidth = 4.5 * w.s; ctx.lineCap = "round"; ctx.stroke();
                        }
                    }
                    Connections { target: w; function onGpuPctChanged() { gpuRing.requestPaint(); } }
                }
                Column {
                    anchors.centerIn: gpuRing
                    spacing: 0
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: w.gpuPct + "%"
                        font.family: w.fam; font.pixelSize: 10.5 * w.s; font.weight: Font.Bold
                        color: w.dark ? "#FFFFFF" : "#1D1D1F"
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "GPU"
                        font.family: w.fam; font.pixelSize: 7.5 * w.s; font.weight: Font.DemiBold
                        color: "#30B0C7"
                    }
                }
            }

            // 3. RAM Gauge
            Item {
                width: 62 * w.s; height: 62 * w.s
                Canvas {
                    id: ramRing
                    anchors.centerIn: parent
                    width: 48 * w.s; height: 48 * w.s
                    readonly property real pct: Math.max(0, Math.min(100, w.ramPct)) / 100.0
                    onPaint: {
                        var ctx = getContext("2d"); ctx.reset();
                        var cx = width / 2, cy = height / 2, r = (width - 6 * w.s) / 2;
                        ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2);
                        ctx.strokeStyle = Qt.rgba(1, 1, 1, w.dark ? 0.12 : 0.20);
                        ctx.lineWidth = 4.5 * w.s; ctx.stroke();
                        if (pct > 0) {
                            ctx.beginPath(); ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + pct * Math.PI * 2);
                            ctx.strokeStyle = "#BF5AF2"; ctx.lineWidth = 4.5 * w.s; ctx.lineCap = "round"; ctx.stroke();
                        }
                    }
                    Connections { target: w; function onRamPctChanged() { ramRing.requestPaint(); } }
                }
                Column {
                    anchors.centerIn: ramRing
                    spacing: 0
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: w.ramPct + "%"
                        font.family: w.fam; font.pixelSize: 10.5 * w.s; font.weight: Font.Bold
                        color: w.dark ? "#FFFFFF" : "#1D1D1F"
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "RAM"
                        font.family: w.fam; font.pixelSize: 7.5 * w.s; font.weight: Font.DemiBold
                        color: "#BF5AF2"
                    }
                }
            }

            // 4. Disk Gauge
            Item {
                width: 62 * w.s; height: 62 * w.s
                Canvas {
                    id: diskRing
                    anchors.centerIn: parent
                    width: 48 * w.s; height: 48 * w.s
                    readonly property real pct: Math.max(0, Math.min(100, w.diskPct)) / 100.0
                    onPaint: {
                        var ctx = getContext("2d"); ctx.reset();
                        var cx = width / 2, cy = height / 2, r = (width - 6 * w.s) / 2;
                        ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2);
                        ctx.strokeStyle = Qt.rgba(1, 1, 1, w.dark ? 0.12 : 0.20);
                        ctx.lineWidth = 4.5 * w.s; ctx.stroke();
                        if (pct > 0) {
                            ctx.beginPath(); ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + pct * Math.PI * 2);
                            ctx.strokeStyle = "#FF9500"; ctx.lineWidth = 4.5 * w.s; ctx.lineCap = "round"; ctx.stroke();
                        }
                    }
                    Connections { target: w; function onDiskPctChanged() { diskRing.requestPaint(); } }
                }
                Column {
                    anchors.centerIn: diskRing
                    spacing: 0
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: w.diskPct + "%"
                        font.family: w.fam; font.pixelSize: 10.5 * w.s; font.weight: Font.Bold
                        color: w.dark ? "#FFFFFF" : "#1D1D1F"
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "DISK"
                        font.family: w.fam; font.pixelSize: 7.5 * w.s; font.weight: Font.DemiBold
                        color: "#FF9500"
                    }
                }
            }
        }
    }

    // ───────────── Content: Medium (Dual Gauges + Detailed Stat Rows) ─────────────
    Item {
        id: medContent
        anchors.fill: parent
        anchors.leftMargin: 20 * w.s
        anchors.rightMargin: 20 * w.s
        anchors.topMargin: 16 * w.s
        anchors.bottomMargin: 16 * w.s
        visible: w.isMedium

        Row {
            anchors.fill: parent
            spacing: 14 * w.s

            // Left: Dual Circular Gauges (CPU & RAM)
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8 * w.s

                // CPU
                Column {
                    spacing: 4 * w.s
                    Canvas {
                        id: medCpuRing
                        width: 52 * w.s; height: 52 * w.s
                        readonly property real pct: Math.max(0, Math.min(100, w.cpuPct)) / 100.0
                        onPaint: {
                            var ctx = getContext("2d"); ctx.reset();
                            var cx = width / 2, cy = height / 2, r = (width - 6 * w.s) / 2;
                            ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2);
                            ctx.strokeStyle = Qt.rgba(1, 1, 1, w.dark ? 0.12 : 0.20);
                            ctx.lineWidth = 5 * w.s; ctx.stroke();
                            if (pct > 0) {
                                ctx.beginPath(); ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + pct * Math.PI * 2);
                                ctx.strokeStyle = "#007AFF"; ctx.lineWidth = 5 * w.s; ctx.lineCap = "round"; ctx.stroke();
                            }
                        }
                        Connections { target: w; function onCpuPctChanged() { medCpuRing.requestPaint(); } }
                        Column {
                            anchors.centerIn: parent
                            spacing: 0
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: w.cpuPct + "%"
                                font.family: w.fam; font.pixelSize: 11.5 * w.s; font.weight: Font.Bold
                                color: w.dark ? "#FFFFFF" : "#1D1D1F"
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "CPU"
                                font.family: w.fam; font.pixelSize: 7.5 * w.s; font.weight: Font.DemiBold
                                color: "#007AFF"
                            }
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Usage"
                        font.family: w.fam; font.pixelSize: 9 * w.s
                        color: w.dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.45)
                    }
                }

                // RAM
                Column {
                    spacing: 4 * w.s
                    Canvas {
                        id: medRamRing
                        width: 52 * w.s; height: 52 * w.s
                        readonly property real pct: Math.max(0, Math.min(100, w.ramPct)) / 100.0
                        onPaint: {
                            var ctx = getContext("2d"); ctx.reset();
                            var cx = width / 2, cy = height / 2, r = (width - 6 * w.s) / 2;
                            ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2);
                            ctx.strokeStyle = Qt.rgba(1, 1, 1, w.dark ? 0.12 : 0.20);
                            ctx.lineWidth = 5 * w.s; ctx.stroke();
                            if (pct > 0) {
                                ctx.beginPath(); ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + pct * Math.PI * 2);
                                ctx.strokeStyle = "#BF5AF2"; ctx.lineWidth = 5 * w.s; ctx.lineCap = "round"; ctx.stroke();
                            }
                        }
                        Connections { target: w; function onRamPctChanged() { medRamRing.requestPaint(); } }
                        Column {
                            anchors.centerIn: parent
                            spacing: 0
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: w.ramPct + "%"
                                font.family: w.fam; font.pixelSize: 11.5 * w.s; font.weight: Font.Bold
                                color: w.dark ? "#FFFFFF" : "#1D1D1F"
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "RAM"
                                font.family: w.fam; font.pixelSize: 7.5 * w.s; font.weight: Font.DemiBold
                                color: "#BF5AF2"
                            }
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: w.ramUsed
                        font.family: w.fam; font.pixelSize: 9 * w.s
                        color: w.dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.45)
                    }
                }
            }

            // Divider line
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 72 * w.s
                color: w.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
            }

            // Right: Detailed Metric Cards (Disk, GPU, Temp, Network)
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 9 * w.s
                width: parent.width - (52 * 2 + 8) * w.s - 28 * w.s - 1

                // Disk Bar
                Column {
                    width: parent.width
                    spacing: 4 * w.s
                    Item {
                        width: parent.width
                        height: 14 * w.s
                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Storage " + w.diskPct + "%"
                            font.family: w.fam; font.pixelSize: 10.5 * w.s; font.weight: Font.Medium
                            color: w.dark ? Qt.rgba(1, 1, 1, 0.85) : Qt.rgba(0, 0, 0, 0.85)
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: w.diskFree + " free"
                            font.family: w.fam; font.pixelSize: 9.5 * w.s
                            color: w.dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.45)
                        }
                    }
                    Rectangle {
                        width: parent.width; height: 5 * w.s; radius: 2.5 * w.s
                        color: w.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
                        Rectangle {
                            width: parent.width * (Math.max(0, Math.min(100, w.diskPct)) / 100.0)
                            height: parent.height; radius: parent.radius
                            color: "#FF9500"
                        }
                    }
                }

                // GPU, Temp & Network Row
                Row {
                    width: parent.width
                    spacing: 6 * w.s

                    // GPU
                    Rectangle {
                        width: (parent.width - 12 * w.s) / 3
                        height: 44 * w.s
                        radius: 8 * w.s
                        color: w.dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.04)
                        Column {
                            anchors.centerIn: parent
                            spacing: 2 * w.s
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: w.gpuPct + "%"
                                font.family: w.fam; font.pixelSize: 11.5 * w.s; font.weight: Font.Bold
                                color: "#30B0C7"
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "GPU"
                                font.family: w.fam; font.pixelSize: 8 * w.s; font.weight: Font.Medium
                                color: w.dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.45)
                            }
                        }
                    }

                    // Temp
                    Rectangle {
                        width: (parent.width - 12 * w.s) / 3
                        height: 44 * w.s
                        radius: 8 * w.s
                        color: w.dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.04)
                        Column {
                            anchors.centerIn: parent
                            spacing: 2 * w.s
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: w.tempVal + "°C"
                                font.family: w.fam; font.pixelSize: 11.5 * w.s; font.weight: Font.Bold
                                color: w.tempVal >= 75 ? "#FF3B30" : (w.dark ? "#FFFFFF" : "#1D1D1F")
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Thermal"
                                font.family: w.fam; font.pixelSize: 8 * w.s; font.weight: Font.Medium
                                color: w.dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.45)
                            }
                        }
                    }

                    // Network
                    Rectangle {
                        width: (parent.width - 12 * w.s) / 3
                        height: 44 * w.s
                        radius: 8 * w.s
                        color: w.dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.04)
                        clip: true
                        Column {
                            anchors.centerIn: parent
                            spacing: 2 * w.s
                            width: parent.width - 4 * w.s
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: w.netSpeed
                                font.family: w.fam; font.pixelSize: 8.5 * w.s; font.weight: Font.Bold
                                color: "#34C759"
                                elide: Text.ElideRight
                                width: Math.min(parent.width, implicitWidth)
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Net"
                                font.family: w.fam; font.pixelSize: 8 * w.s; font.weight: Font.Medium
                                color: w.dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.45)
                            }
                        }
                    }
                }
            }
        }
    }

    // ───────────── Content: Large (Apple Activity Monitor Dashboard) ─────────────
    Item {
        id: largeContent
        anchors.fill: parent
        anchors.leftMargin: 20 * w.s
        anchors.rightMargin: 20 * w.s
        anchors.topMargin: 18 * w.s
        anchors.bottomMargin: 18 * w.s
        visible: w.isLarge

        Column {
            anchors.fill: parent
            spacing: 12 * w.s

            // Header
            Item {
                width: parent.width
                height: 22 * w.s
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Activity Monitor"
                    font.family: w.fam
                    font.pixelSize: 13.5 * w.s
                    font.weight: Font.Bold
                    color: w.dark ? "white" : "#1C1C1E"
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "System Overview"
                    font.family: w.fam
                    font.pixelSize: 10.5 * w.s
                    color: w.dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.45)
                }
            }

            // Quad gauges row
            Row {
                width: parent.width
                spacing: (parent.width - 4 * 60 * w.s) / 3

                // CPU
                Column {
                    width: 60 * w.s
                    spacing: 4 * w.s
                    Canvas {
                        id: lCpuRing
                        width: 52 * w.s; height: 52 * w.s
                        anchors.horizontalCenter: parent.horizontalCenter
                        readonly property real pct: Math.max(0, Math.min(100, w.cpuPct)) / 100.0
                        onPaint: {
                            var ctx = getContext("2d"); ctx.reset();
                            var cx = width / 2, cy = height / 2, r = (width - 6 * w.s) / 2;
                            ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2);
                            ctx.strokeStyle = Qt.rgba(1, 1, 1, w.dark ? 0.12 : 0.20);
                            ctx.lineWidth = 5 * w.s; ctx.stroke();
                            if (pct > 0) {
                                ctx.beginPath(); ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + pct * Math.PI * 2);
                                ctx.strokeStyle = "#007AFF"; ctx.lineWidth = 5 * w.s; ctx.lineCap = "round"; ctx.stroke();
                            }
                        }
                        Connections { target: w; function onCpuPctChanged() { lCpuRing.requestPaint(); } }
                        Column {
                            anchors.centerIn: parent
                            spacing: 0
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: w.cpuPct + "%"
                                font.family: w.fam; font.pixelSize: 11.5 * w.s; font.weight: Font.Bold
                                color: w.dark ? "#FFFFFF" : "#1D1D1F"
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "CPU"
                                font.family: w.fam; font.pixelSize: 7.5 * w.s; font.weight: Font.DemiBold
                                color: "#007AFF"
                            }
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Processor"
                        font.family: w.fam; font.pixelSize: 9 * w.s
                        color: w.dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.45)
                    }
                }

                // GPU
                Column {
                    width: 60 * w.s
                    spacing: 4 * w.s
                    Canvas {
                        id: lGpuRing
                        width: 52 * w.s; height: 52 * w.s
                        anchors.horizontalCenter: parent.horizontalCenter
                        readonly property real pct: Math.max(0, Math.min(100, w.gpuPct)) / 100.0
                        onPaint: {
                            var ctx = getContext("2d"); ctx.reset();
                            var cx = width / 2, cy = height / 2, r = (width - 6 * w.s) / 2;
                            ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2);
                            ctx.strokeStyle = Qt.rgba(1, 1, 1, w.dark ? 0.12 : 0.20);
                            ctx.lineWidth = 5 * w.s; ctx.stroke();
                            if (pct > 0) {
                                ctx.beginPath(); ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + pct * Math.PI * 2);
                                ctx.strokeStyle = "#30B0C7"; ctx.lineWidth = 5 * w.s; ctx.lineCap = "round"; ctx.stroke();
                            }
                        }
                        Connections { target: w; function onGpuPctChanged() { lGpuRing.requestPaint(); } }
                        Column {
                            anchors.centerIn: parent
                            spacing: 0
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: w.gpuPct + "%"
                                font.family: w.fam; font.pixelSize: 11.5 * w.s; font.weight: Font.Bold
                                color: w.dark ? "#FFFFFF" : "#1D1D1F"
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "GPU"
                                font.family: w.fam; font.pixelSize: 7.5 * w.s; font.weight: Font.DemiBold
                                color: "#30B0C7"
                            }
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Graphics"
                        font.family: w.fam; font.pixelSize: 9 * w.s
                        color: w.dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.45)
                    }
                }

                // RAM
                Column {
                    width: 60 * w.s
                    spacing: 4 * w.s
                    Canvas {
                        id: lRamRing
                        width: 52 * w.s; height: 52 * w.s
                        anchors.horizontalCenter: parent.horizontalCenter
                        readonly property real pct: Math.max(0, Math.min(100, w.ramPct)) / 100.0
                        onPaint: {
                            var ctx = getContext("2d"); ctx.reset();
                            var cx = width / 2, cy = height / 2, r = (width - 6 * w.s) / 2;
                            ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2);
                            ctx.strokeStyle = Qt.rgba(1, 1, 1, w.dark ? 0.12 : 0.20);
                            ctx.lineWidth = 5 * w.s; ctx.stroke();
                            if (pct > 0) {
                                ctx.beginPath(); ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + pct * Math.PI * 2);
                                ctx.strokeStyle = "#BF5AF2"; ctx.lineWidth = 5 * w.s; ctx.lineCap = "round"; ctx.stroke();
                            }
                        }
                        Connections { target: w; function onRamPctChanged() { lRamRing.requestPaint(); } }
                        Column {
                            anchors.centerIn: parent
                            spacing: 0
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: w.ramPct + "%"
                                font.family: w.fam; font.pixelSize: 11.5 * w.s; font.weight: Font.Bold
                                color: w.dark ? "#FFFFFF" : "#1D1D1F"
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "RAM"
                                font.family: w.fam; font.pixelSize: 7.5 * w.s; font.weight: Font.DemiBold
                                color: "#BF5AF2"
                            }
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: w.ramUsed
                        font.family: w.fam; font.pixelSize: 9 * w.s
                        color: w.dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.45)
                    }
                }

                // Disk
                Column {
                    width: 60 * w.s
                    spacing: 4 * w.s
                    Canvas {
                        id: lDiskRing
                        width: 52 * w.s; height: 52 * w.s
                        anchors.horizontalCenter: parent.horizontalCenter
                        readonly property real pct: Math.max(0, Math.min(100, w.diskPct)) / 100.0
                        onPaint: {
                            var ctx = getContext("2d"); ctx.reset();
                            var cx = width / 2, cy = height / 2, r = (width - 6 * w.s) / 2;
                            ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2);
                            ctx.strokeStyle = Qt.rgba(1, 1, 1, w.dark ? 0.12 : 0.20);
                            ctx.lineWidth = 5 * w.s; ctx.stroke();
                            if (pct > 0) {
                                ctx.beginPath(); ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + pct * Math.PI * 2);
                                ctx.strokeStyle = "#FF9500"; ctx.lineWidth = 5 * w.s; ctx.lineCap = "round"; ctx.stroke();
                            }
                        }
                        Connections { target: w; function onDiskPctChanged() { lDiskRing.requestPaint(); } }
                        Column {
                            anchors.centerIn: parent
                            spacing: 0
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: w.diskPct + "%"
                                font.family: w.fam; font.pixelSize: 11.5 * w.s; font.weight: Font.Bold
                                color: w.dark ? "#FFFFFF" : "#1D1D1F"
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "DISK"
                                font.family: w.fam; font.pixelSize: 7.5 * w.s; font.weight: Font.DemiBold
                                color: "#FF9500"
                            }
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: w.diskFree
                        font.family: w.fam; font.pixelSize: 9 * w.s
                        color: w.dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.45)
                    }
                }
            }

            // Detailed Progress Bars Card
            Rectangle {
                width: parent.width
                height: 94 * w.s
                radius: 12 * w.s
                color: w.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04)

                Column {
                    anchors.fill: parent
                    anchors.margins: 12 * w.s
                    spacing: 10 * w.s

                    // RAM Bar
                    Column {
                        width: parent.width
                        spacing: 4 * w.s
                        Item {
                            width: parent.width
                            height: 14 * w.s
                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Memory (RAM)"
                                font.family: w.fam; font.pixelSize: 11 * w.s; font.weight: Font.DemiBold
                                color: w.dark ? Qt.rgba(1, 1, 1, 0.85) : Qt.rgba(0, 0, 0, 0.85)
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: w.ramUsed + " / " + w.ramTotal
                                font.family: w.fam; font.pixelSize: 10 * w.s
                                color: w.dark ? Qt.rgba(1, 1, 1, 0.5) : Qt.rgba(0, 0, 0, 0.5)
                            }
                        }
                        Rectangle {
                            width: parent.width; height: 6 * w.s; radius: 3 * w.s
                            color: w.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
                            Rectangle {
                                width: parent.width * (Math.max(0, Math.min(100, w.ramPct)) / 100.0)
                                height: parent.height; radius: parent.radius
                                color: "#BF5AF2"
                            }
                        }
                    }

                    // Storage Bar
                    Column {
                        width: parent.width
                        spacing: 4 * w.s
                        Item {
                            width: parent.width
                            height: 14 * w.s
                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Storage"
                                font.family: w.fam; font.pixelSize: 11 * w.s; font.weight: Font.DemiBold
                                color: w.dark ? Qt.rgba(1, 1, 1, 0.85) : Qt.rgba(0, 0, 0, 0.85)
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: w.diskFree + " free / " + w.diskTotal + " total"
                                font.family: w.fam; font.pixelSize: 10 * w.s
                                color: w.dark ? Qt.rgba(1, 1, 1, 0.5) : Qt.rgba(0, 0, 0, 0.5)
                            }
                        }
                        Rectangle {
                            width: parent.width; height: 6 * w.s; radius: 3 * w.s
                            color: w.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
                            Rectangle {
                                width: parent.width * (Math.max(0, Math.min(100, w.diskPct)) / 100.0)
                                height: parent.height; radius: parent.radius
                                color: "#FF9500"
                            }
                        }
                    }
                }
            }

            // Bottom 3 Cards: Thermal, Network, Load
            Row {
                width: parent.width
                spacing: 8 * w.s

                // Thermal
                Rectangle {
                    width: (parent.width - 16 * w.s) / 3
                    height: 52 * w.s
                    radius: 10 * w.s
                    color: w.dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.04)
                    Column {
                        anchors.centerIn: parent
                        spacing: 3 * w.s
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: w.tempVal + "°C"
                            font.family: w.fam; font.pixelSize: 13 * w.s; font.weight: Font.Bold
                            color: w.tempVal >= 75 ? "#FF3B30" : (w.dark ? "#FFFFFF" : "#1D1D1F")
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Thermal"
                            font.family: w.fam; font.pixelSize: 9 * w.s; font.weight: Font.Medium
                            color: w.dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.45)
                        }
                    }
                }

                // Network
                Rectangle {
                    width: (parent.width - 16 * w.s) / 3
                    height: 52 * w.s
                    radius: 10 * w.s
                    color: w.dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.04)
                    clip: true
                    Column {
                        anchors.centerIn: parent
                        spacing: 3 * w.s
                        width: parent.width - 6 * w.s
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: w.netSpeed
                            font.family: w.fam; font.pixelSize: 10.5 * w.s; font.weight: Font.Bold
                            color: "#34C759"
                            elide: Text.ElideRight
                            width: Math.min(parent.width, implicitWidth)
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Network Speed"
                            font.family: w.fam; font.pixelSize: 9 * w.s; font.weight: Font.Medium
                            color: w.dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.45)
                        }
                    }
                }

                // Load
                Rectangle {
                    width: (parent.width - 16 * w.s) / 3
                    height: 52 * w.s
                    radius: 10 * w.s
                    color: w.dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.04)
                    Column {
                        anchors.centerIn: parent
                        spacing: 3 * w.s
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: w.cpuPct < 30 ? "Light" : (w.cpuPct < 70 ? "Moderate" : "Heavy")
                            font.family: w.fam; font.pixelSize: 12 * w.s; font.weight: Font.Bold
                            color: w.cpuPct < 70 ? "#007AFF" : "#FF9500"
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "System Load"
                            font.family: w.fam; font.pixelSize: 9 * w.s; font.weight: Font.Medium
                            color: w.dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.45)
                        }
                    }
                }
            }
        }
    }
}

