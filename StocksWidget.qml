// macOS Stocks & Crypto Widget (Apple Sonoma / Tahoe style)
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

    // Active selected index for small view
    property int selectedIndex: 0

    // Assets data
    property var stockList: [
        { "symbol": "BTC", "name": "Bitcoin", "price": 82038.0, "change24h": 0.60, "currency": "$", "sparkline": [81200, 81500, 81900, 81600, 82200, 82038] },
        { "symbol": "ETH", "name": "Ethereum", "price": 2416.7, "change24h": -0.82, "currency": "$", "sparkline": [2450, 2440, 2430, 2415, 2420, 2416.7] },
        { "symbol": "SOL", "name": "Solana", "price": 103.9, "change24h": -0.73, "currency": "$", "sparkline": [105, 104.5, 104, 103.5, 104.2, 103.9] },
        { "symbol": "AAPL", "name": "Apple", "price": 343.4, "change24h": 0.43, "currency": "$", "sparkline": [341, 342, 341.5, 342.8, 343.1, 343.4] },
        { "symbol": "NVDA", "name": "NVIDIA", "price": 214.1, "change24h": -1.43, "currency": "$", "sparkline": [217, 216, 215.5, 214.8, 214.5, 214.1] }
    ]

    readonly property var currentAsset: (stockList && stockList.length > selectedIndex)
        ? stockList[selectedIndex]
        : (stockList && stockList.length > 0 ? stockList[0] : { "symbol": "BTC", "name": "Bitcoin", "price": 0, "change24h": 0, "currency": "$", "sparkline": [] })

    readonly property string stocksScript: decodeURIComponent(Qt.resolvedUrl("stocks_fetcher.py").toString().replace(/^file:\/\//, ""))

    function formatPrice(val, curr) {
        if (val === undefined || val === null) return "$0.00";
        var n = Number(val);
        var parts = n.toFixed(2).split(".");
        parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",");
        return (curr || "$") + parts.join(".");
    }

    // Process for fetching live stock and crypto data
    Process {
        id: stockProc
        command: ["python3", w.stocksScript]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var s = text.trim();
                    if (s.indexOf("[") >= 0) {
                        var parsed = JSON.parse(s);
                        if (Array.isArray(parsed) && parsed.length > 0) {
                            w.stockList = parsed;
                        }
                    }
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 180000 // Refresh every 3 minutes to save bandwidth and CPU
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!stockProc.running) stockProc.running = true;
        }
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
                blurEnabled: gl.bn > 0.001
                blur: gl.bn
                blurMax: 64
                saturation: 0.15
                contrast: 0.05
                visible: false
            }

            ShaderEffectSource {
                id: frosted
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

                property variant src: frosted
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
                property real ringW: 1
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: !w.glassOn
        radius: w.radiusPx
        color: "transparent"
        border.width: 1
        border.color: w.dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.70)
    }

    // ───────────── Content UI ─────────────
    // SMALL SIZE: Single asset highlight with Sparkline chart
    Item {
        id: smallContent
        anchors.fill: parent
        anchors.leftMargin: 18 * w.s
        anchors.rightMargin: 18 * w.s
        anchors.topMargin: 16 * w.s
        anchors.bottomMargin: 14 * w.s
        visible: w.isSmall

        // Top Row: Symbol, Name, and Next switcher button
        Item {
            id: sTopRow
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 28 * w.s

            Column {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    text: w.currentAsset.symbol
                    font.family: w.fam
                    font.pixelSize: 14 * w.u
                    font.weight: Font.Bold
                    color: w.dark ? "white" : "#1C1C1E"
                }
                Text {
                    text: w.currentAsset.name
                    font.family: w.fam
                    font.pixelSize: 9.5 * w.u
                    color: w.dark ? Qt.rgba(1, 1, 1, 0.5) : Qt.rgba(0, 0, 0, 0.5)
                    elide: Text.ElideRight
                }
            }

            // Switcher pill button
            Rectangle {
                width: 22 * w.u
                height: 22 * w.u
                radius: 11 * w.u
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                color: w.dark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.06)

                Text {
                    anchors.centerIn: parent
                    text: "⇄"
                    font.pixelSize: 11 * w.u
                    color: w.dark ? "white" : "#1C1C1E"
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        w.selectedIndex = (w.selectedIndex + 1) % w.stockList.length;
                        sCanvas.requestPaint();
                    }
                }
            }
        }

        // Middle: Price & Percentage Change Pill
        Row {
            id: sPriceRow
            anchors.top: sTopRow.bottom
            anchors.topMargin: 4 * w.u
            anchors.left: parent.left
            anchors.right: parent.right
            height: 28 * w.u
            spacing: 6 * w.u

            Text {
                id: sPriceTxt
                anchors.verticalCenter: parent.verticalCenter
                text: w.formatPrice(w.currentAsset.price, w.currentAsset.currency)
                font.family: w.fam
                font.pixelSize: 15 * w.u
                font.weight: Font.Bold
                color: w.dark ? "white" : "#1C1C1E"
            }

            Rectangle {
                id: sPill
                anchors.verticalCenter: parent.verticalCenter
                height: 18 * w.u
                width: sPillTxt.implicitWidth + 8 * w.u
                radius: 5 * w.u
                color: (w.currentAsset.change24h >= 0) ? "#34C759" : "#FF3B30"

                Text {
                    id: sPillTxt
                    anchors.centerIn: parent
                    text: (w.currentAsset.change24h >= 0 ? "+" : "") + w.currentAsset.change24h + "%"
                    font.family: w.fam
                    font.pixelSize: 9.5 * w.u
                    font.weight: Font.Bold
                    color: "white"
                }
            }
        }

        // Bottom Sparkline Chart (Canvas)
        Canvas {
            id: sCanvas
            anchors.top: sPriceRow.bottom
            anchors.topMargin: 4 * w.u
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            antialiasing: true

            readonly property var pts: w.currentAsset.sparkline || []
            readonly property bool isUp: w.currentAsset.change24h >= 0

            onPtsChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                var W = width, H = height;
                if (!pts || pts.length < 2) return;

                var min = Math.min.apply(null, pts);
                var max = Math.max.apply(null, pts);
                var range = (max - min) || 1;

                var strokeCol = isUp ? "#34C759" : "#FF3B30";
                var fillCol = isUp ? "rgba(52, 199, 89, 0.18)" : "rgba(255, 59, 48, 0.18)";

                ctx.beginPath();
                for (var i = 0; i < pts.length; i++) {
                    var x = (i / (pts.length - 1)) * W;
                    var y = H - ((pts[i] - min) / range) * (H - 8) - 4;
                    if (i === 0) ctx.moveTo(x, y);
                    else ctx.lineTo(x, y);
                }

                // Line stroke
                ctx.lineWidth = 2.2;
                ctx.strokeStyle = strokeCol;
                ctx.stroke();

                // Fill gradient under curve
                ctx.lineTo(W, H);
                ctx.lineTo(0, H);
                ctx.closePath();
                ctx.fillStyle = fillCol;
                ctx.fill();
            }
        }
    }

    // MEDIUM SIZE: Watchlist of 4-5 Assets with mini sparklines
    Item {
        id: medContent
        anchors.fill: parent
        anchors.leftMargin: 20 * w.s
        anchors.rightMargin: 20 * w.s
        anchors.topMargin: 16 * w.s
        anchors.bottomMargin: 14 * w.s
        visible: w.isMedium

        Column {
            anchors.fill: parent
            spacing: 2 * w.s

            // Header row
            Item {
                width: parent.width
                height: 20 * w.s

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Watchlist"
                    font.family: w.fam
                    font.pixelSize: 12 * w.s
                    font.weight: Font.Bold
                    color: w.dark ? "white" : "#1C1C1E"
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Today's Markets"
                    font.family: w.fam
                    font.pixelSize: 10 * w.s
                    color: w.dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.45)
                }
            }

            // Asset Rows (up to 4)
            Column {
                width: parent.width
                spacing: 4 * w.s

                Repeater {
                    model: Math.min(4, w.stockList.length)
                    delegate: Item {
                        id: rowItem
                        required property int index
                        readonly property var ast: w.stockList[index]
                        width: parent.width
                        height: 27 * w.s

                        // Click to cycle
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                        }

                        // Symbol & Name (Apple Stocks style Column)
                        Column {
                            id: astCol
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 68 * w.s
                            spacing: 1 * w.s

                            Text {
                                text: rowItem.ast.symbol
                                font.family: w.fam
                                font.pixelSize: 12 * w.s
                                font.weight: Font.Bold
                                color: w.dark ? "white" : "#1C1C1E"
                            }

                            Text {
                                text: rowItem.ast.name
                                font.family: w.fam
                                font.pixelSize: 9 * w.s
                                color: w.dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.45)
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }

                        // Mini Sparkline Canvas in center (responsive width)
                        Canvas {
                            id: mSpark
                            anchors.left: astCol.right
                            anchors.leftMargin: 8 * w.s
                            anchors.right: priceRow.left
                            anchors.rightMargin: 12 * w.s
                            anchors.verticalCenter: parent.verticalCenter
                            height: 18 * w.s
                            antialiasing: true

                            readonly property var pts: rowItem.ast.sparkline || []
                            readonly property bool isUp: rowItem.ast.change24h >= 0

                            onPtsChanged: requestPaint()

                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.reset();
                                if (!pts || pts.length < 2) return;
                                var W = width, H = height;
                                var min = Math.min.apply(null, pts);
                                var max = Math.max.apply(null, pts);
                                var range = (max - min) || 1;

                                ctx.beginPath();
                                for (var i = 0; i < pts.length; i++) {
                                    var x = (i / (pts.length - 1)) * W;
                                    var y = H - ((pts[i] - min) / range) * (H - 4) - 2;
                                    if (i === 0) ctx.moveTo(x, y);
                                    else ctx.lineTo(x, y);
                                }
                                ctx.lineWidth = 1.6;
                                ctx.strokeStyle = isUp ? "#34C759" : "#FF3B30";
                                ctx.stroke();
                            }
                        }

                        // Right: Price & % pill
                        Row {
                            id: priceRow
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8 * w.s

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: w.formatPrice(rowItem.ast.price, rowItem.ast.currency)
                                font.family: w.fam
                                font.pixelSize: 11.5 * w.s
                                font.weight: Font.DemiBold
                                color: w.dark ? "white" : "#1C1C1E"
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                height: 18 * w.s
                                width: 52 * w.s
                                radius: 4.5 * w.s
                                color: (rowItem.ast.change24h >= 0) ? "#34C759" : "#FF3B30"

                                Text {
                                    anchors.centerIn: parent
                                    text: (rowItem.ast.change24h >= 0 ? "+" : "") + rowItem.ast.change24h + "%"
                                    font.family: w.fam
                                    font.pixelSize: 9.5 * w.s
                                    font.weight: Font.Bold
                                    color: "white"
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // LARGE SIZE: Featured Hero Asset + Watchlist
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

            // Top Hero Card
            Rectangle {
                width: parent.width
                height: 150 * w.s
                radius: 14 * w.s
                color: w.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04)

                Column {
                    anchors.fill: parent
                    anchors.margins: 12 * w.s
                    spacing: 6 * w.s

                    // Symbol, Name & Change Pill
                    Item {
                        width: parent.width
                        height: 28 * w.s

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8 * w.s

                            Text {
                                text: w.currentAsset.symbol
                                font.family: w.fam
                                font.pixelSize: 16 * w.s
                                font.weight: Font.Bold
                                color: w.dark ? "white" : "#1C1C1E"
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: w.currentAsset.name
                                font.family: w.fam
                                font.pixelSize: 12 * w.s
                                color: w.dark ? Qt.rgba(1, 1, 1, 0.5) : Qt.rgba(0, 0, 0, 0.5)
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8 * w.s

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: w.formatPrice(w.currentAsset.price, w.currentAsset.currency)
                                font.family: w.fam
                                font.pixelSize: 15 * w.s
                                font.weight: Font.Bold
                                color: w.dark ? "white" : "#1C1C1E"
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                height: 20 * w.s
                                width: lHeroPillTxt.implicitWidth + 10 * w.s
                                radius: 5 * w.s
                                color: (w.currentAsset.change24h >= 0) ? "#34C759" : "#FF3B30"

                                Text {
                                    id: lHeroPillTxt
                                    anchors.centerIn: parent
                                    text: (w.currentAsset.change24h >= 0 ? "+" : "") + w.currentAsset.change24h + "%"
                                    font.family: w.fam
                                    font.pixelSize: 10 * w.s
                                    font.weight: Font.Bold
                                    color: "white"
                                }
                            }
                        }
                    }

                    // Large Sparkline
                    Canvas {
                        width: parent.width
                        height: 84 * w.s
                        antialiasing: true

                        readonly property var pts: w.currentAsset.sparkline || []
                        readonly property bool isUp: w.currentAsset.change24h >= 0

                        onPtsChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.reset();
                            var W = width, H = height;
                            if (!pts || pts.length < 2) return;

                            var min = Math.min.apply(null, pts);
                            var max = Math.max.apply(null, pts);
                            var range = (max - min) || 1;

                            var strokeCol = isUp ? "#34C759" : "#FF3B30";
                            var fillCol = isUp ? "rgba(52, 199, 89, 0.15)" : "rgba(255, 59, 48, 0.15)";

                            ctx.beginPath();
                            for (var i = 0; i < pts.length; i++) {
                                var x = (i / (pts.length - 1)) * W;
                                var y = H - ((pts[i] - min) / range) * (H - 10) - 5;
                                if (i === 0) ctx.moveTo(x, y);
                                else ctx.lineTo(x, y);
                            }

                            ctx.lineWidth = 2.4;
                            ctx.strokeStyle = strokeCol;
                            ctx.stroke();

                            ctx.lineTo(W, H);
                            ctx.lineTo(0, H);
                            ctx.closePath();
                            ctx.fillStyle = fillCol;
                            ctx.fill();
                        }
                    }
                }
            }

            // Watchlist Section Header
            Item {
                width: parent.width
                height: 18 * w.s

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Markets Watchlist"
                    font.family: w.fam
                    font.pixelSize: 12 * w.s
                    font.weight: Font.Bold
                    color: w.dark ? "white" : "#1C1C1E"
                }
            }

            // Watchlist Rows
            Column {
                width: parent.width
                spacing: 5 * w.s

                Repeater {
                    model: Math.min(4, w.stockList.length)
                    delegate: Item {
                        id: lRowItem
                        required property int index
                        readonly property var ast: w.stockList[index]
                        width: parent.width
                        height: 28 * w.s

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: w.selectedIndex = lRowItem.index
                        }

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8 * w.s

                            Text {
                                text: lRowItem.ast.symbol
                                font.family: w.fam
                                font.pixelSize: 12 * w.s
                                font.weight: Font.Bold
                                color: w.dark ? "white" : "#1C1C1E"
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: lRowItem.ast.name
                                font.family: w.fam
                                font.pixelSize: 10 * w.s
                                color: w.dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.45)
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8 * w.s

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: w.formatPrice(lRowItem.ast.price, lRowItem.ast.currency)
                                font.family: w.fam
                                font.pixelSize: 12 * w.s
                                font.weight: Font.DemiBold
                                color: w.dark ? "white" : "#1C1C1E"
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                height: 18 * w.s
                                width: 52 * w.s
                                radius: 4.5 * w.s
                                color: (lRowItem.ast.change24h >= 0) ? "#34C759" : "#FF3B30"

                                Text {
                                    anchors.centerIn: parent
                                    text: (lRowItem.ast.change24h >= 0 ? "+" : "") + lRowItem.ast.change24h + "%"
                                    font.family: w.fam
                                    font.pixelSize: 9.5 * w.s
                                    font.weight: Font.Bold
                                    color: "white"
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

