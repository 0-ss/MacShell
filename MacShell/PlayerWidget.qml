// macOS Tahoe "Now Playing" widget (MPRIS: Spotify, Firefox, mpv, VLC, ...).
//   size:  "small"  – art, play / pause, title + scrolling artist line
//          "medium" – the wide Now Playing card: art, title, scrolling subtitle, waves, progress + times, shuffle / back / play / forward / repeat
//          "large"  – the same card, taller, with big artwork
//   Everything is drawn in "reference units" (RU): the wide card scales to the shell's 358 x 168 Medium footprint.
//   style: "light"  – pastel card tinted with the artwork's colour, dark text
//          "dark"   – deep card tinted with the artwork's colour, white text
//          "liquid" – Liquid Glass (Appearance sliders) with the artwork's colour washed over it
//
// The card colour is taken from the album artwork (a 24x24 sample of it, see `sampler`), and fades to the next song's colour.
// Without artwork a stable colour is derived from the title instead.
//
// This file only draws. MacWidgets.qml owns the MPRIS player and feeds the data properties; the buttons emit
// togglePlaying() / nextTrack() / previousTrack().
import QtQuick
import QtQuick.Effects
import "I18n.js" as I18n

Item {
    id: w

    // ── look ──
    property string style: "dark"            // "light" | "dark" | "liquid"
    property string size: "small"
    property real scaleF: 1.0
    property real contentScale: 1.0          // scales art / text / buttons; the card itself keeps the widget's full size
    property string fam: "Open Runde"
    property real screenX: x
    property real screenY: y
    property bool preview: false             // inside the Settings gallery: sample data, no wallpaper, not clickable
    property bool editing: false
    property color tintOverride: "transparent"   // preview only: pretend the artwork has this colour

    // ── data (from MacWidgets) ──
    property bool hasPlayer: false
    property string title: ""
    property string artist: ""
    property string album: ""
    property string artUrl: ""
    property bool playing: false
    property real position: 0                // seconds
    property real length: 0                  // seconds (0 = unknown)

    property bool shuffle: false
    property int loop: 0                     // 0 = off, 1 = repeat song, 2 = repeat all
    property bool canShuffle: true
    property bool canLoop: true

    property bool canSeek: false

    // lyrics (fetched by MacWidgets): [{ t: seconds (-1 = not synced), text: "..." }]
    property var lyrics: []
    property string lyricsState: "idle"      // idle | loading | ok | none
    property bool lyricsSynced: false
    property bool lyricsOn: false            // the lyrics view is open
    signal lyricsToggled(bool on)

    signal seek(real seconds)
    signal togglePlaying()
    signal nextTrack()
    signal previousTrack()
    signal toggleShuffle()
    signal cycleLoop()

    // ── liquid glass inputs (the Appearance sliders), same as the other widgets ──
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

    // RU -> px. It follows the real size of the widget, so it still fits if the host stretches it.
    readonly property real k0: isSmall ? width / 202 : (isMedium ? height / 202 : width / 446)
    readonly property real k: contentScale * k0        // RU -> px for the contents
    readonly property real wr: width / k               // card size in RU: the layout stretches to fill the whole card
    readonly property real hr: height / k
    readonly property real radiusPx: 28 * scaleF * (isSmall ? 168 / 158 : (isMedium ? 358 / 338 : 1))

    width: (isSmall ? 158 : (isMedium ? 338 : 358)) * scaleF
           * (isSmall ? 168 / 158 : (isMedium ? 358 / 338 : 1.0))
    height: (isLarge ? 354 : 168) * scaleF

    readonly property bool glassOn: style === "liquid" && glassReady && !preview && wallUrl != ""
    readonly property bool dark: style === "dark" || (style === "liquid" && darkGlass)
    readonly property real tint: Math.min(0.92, dark ? 0.25 + glassOpacity * 0.8 : 0.45 + glassOpacity * 0.9)

    // ───────────────────────── colours from the artwork ─────────────────────────
    function mix(c, o, t) { return Qt.rgba(c.r * (1 - t) + o.r * t, c.g * (1 - t) + o.g * t, c.b * (1 - t) + o.b * t, 1); }
    function hashColor(str) {
        var h = 7;
        for (var i = 0; i < str.length; i++) h = (h * 31 + str.charCodeAt(i)) % 360;
        return Qt.hsva(h / 360, 0.55, 0.66, 1);
    }
    function fileUrl(p) {
        if (!p) return "";
        if (p.indexOf("/") === 0) return "file://" + encodeURI(p).replace(/#/g, "%23").replace(/\?/g, "%3F");
        return p;
    }
    readonly property url artSrc: fileUrl(artUrl)

    property color sampled: "transparent"     // the colour found in the artwork (alpha 0 = nothing yet)
    readonly property color artColor: {
        if (tintOverride.a > 0) return tintOverride;
        if (!hasPlayer) return Qt.rgba(0.36, 0.38, 0.44, 1);
        if (sampled.a > 0 && artSrc != "") return sampled;
        return hashColor(title + "|" + artist);
    }
    property color ac: artColor
    Behavior on ac { ColorAnimation { duration: 450 } }

    // 24x24 sample of the artwork: the average of its colourful pixels (grey / black / white ones count for little)
    Canvas {
        id: sampler
        width: 24; height: 24
        opacity: 0                           // painted, but never seen
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Immediate
        property string loaded: ""
        function load(u) {
            if (loaded !== "") { unloadImage(loaded); loaded = ""; }
            if (u === "") { w.sampled = "transparent"; return; }
            loaded = u;
            loadImage(u);
        }
        onImageLoaded: requestPaint()
        onPaint: {
            if (loaded === "" || !isImageLoaded(loaded)) return;
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, 24, 24);
            ctx.drawImage(loaded, 0, 0, 24, 24);
            var d = ctx.getImageData(0, 0, 24, 24).data, r = 0, g = 0, b = 0, wt = 0, ar = 0, ag = 0, ab = 0;
            for (var i = 0; i < d.length; i += 4) {
                var R = d[i] / 255, G = d[i + 1] / 255, B = d[i + 2] / 255;
                var mx = Math.max(R, G, B), mn = Math.min(R, G, B), sat = mx > 0 ? (mx - mn) / mx : 0;
                var k = sat * sat * (0.25 + mx) + 0.002;            // vivid, reasonably bright pixels win
                r += R * k; g += G * k; b += B * k; wt += k;
                ar += R; ag += G; ab += B;
            }
            if (wt <= 0) return;
            var c = Qt.rgba(r / wt, g / wt, b / wt, 1);
            // keep it a real colour, neither black nor white
            var s = c.hsvSaturation < 0.10 ? c.hsvSaturation : Math.max(c.hsvSaturation, 0.38);
            var v = Math.max(0.42, Math.min(0.88, c.hsvValue));
            w.sampled = Qt.hsva(c.hsvHue < 0 ? 0 : c.hsvHue, Math.min(1, s), v, 1);
        }
    }
    onArtSrcChanged: sampler.load(String(artSrc))
    Component.onCompleted: sampler.load(String(artSrc))

    // card colours
    readonly property color topCol: style === "light" ? mix(ac, Qt.rgba(1, 1, 1, 1), 0.70) : mix(ac, Qt.rgba(0, 0, 0, 1), 0.42)
    readonly property color botCol: style === "light" ? mix(ac, Qt.rgba(1, 1, 1, 1), 0.84) : mix(ac, Qt.rgba(0, 0, 0, 1), 0.66)
    readonly property color cardMid: mix(topCol, botCol, 0.5)
    function fa(a) { return dark ? Qt.rgba(1, 1, 1, a) : Qt.rgba(0, 0, 0, a); }
    readonly property color fg: fa(dark ? 0.90 : 0.86)          // title
    readonly property color fg2: fa(dark ? 0.52 : 0.50)         // subtitle, times
    readonly property color fgBtn: fa(dark ? 0.78 : 0.72)       // back / play / forward
    readonly property color fgDim: fa(dark ? 0.52 : 0.48)       // shuffle / repeat when off
    readonly property color trackCol: fa(dark ? 0.12 : 0.10)
    readonly property color fillCol: fa(dark ? 0.58 : 0.50)
    // thin border: the card's own colour, a bit brighter
    readonly property color borderCol: {
        var c = Qt.lighter(cardMid, 1.55);
        return Qt.rgba(c.r, c.g, c.b, 0.9);
    }

    // ───────────────────────── background ─────────────────────────
    // Light / Dark: card tinted with the artwork colour
    Rectangle {
        anchors.fill: parent
        visible: w.style !== "liquid"
        radius: w.radiusPx
        gradient: Gradient {
            GradientStop { position: 0.0; color: w.topCol }
            GradientStop { position: 1.0; color: w.botCol }
        }
        Rectangle {   // soft top sheen
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, w.dark ? 0.08 : 0.30) }
                GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }
    }

    // Liquid fallback / gallery preview: frosted card
    Rectangle {
        anchors.fill: parent
        visible: w.style === "liquid" && !w.glassOn
        radius: w.radiusPx
        gradient: Gradient {
            GradientStop { position: 0.0; color: w.dark ? Qt.rgba(0.22, 0.22, 0.25, 0.82) : Qt.rgba(1.0, 1.0, 1.0, 0.88) }
            GradientStop { position: 1.0; color: w.dark ? Qt.rgba(0.13, 0.13, 0.15, 0.82) : Qt.rgba(0.92, 0.92, 0.95, 0.88) }
        }
    }

    // Liquid Glass: wallpaper crop → blur → refraction shader (same maths as the Dock and the other widgets)
    Loader {
        anchors.fill: parent
        active: w.glassOn
        sourceComponent: Item {
            id: gl
            readonly property real margin: 72
            readonly property real padPx: 10
            readonly property real ds: w.glassBlur >= 8 ? 0.5 : 1.0
            readonly property real bn: Math.min(1.0, w.glassBlur * 1.4 * ds / 64.0)

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

    // the artwork's colour washed over the glass (Liquid style)
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        visible: w.style === "liquid"
        radius: Math.max(0, w.radiusPx - 1)
        color: Qt.rgba(w.ac.r, w.ac.g, w.ac.b, w.dark ? 0.46 : 0.34)
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
    function fmt(sec) {
        var s = Math.max(0, Math.floor(sec)), m = Math.floor(s / 60);
        return m + ":" + ("0" + (s % 60)).slice(-2);
    }
    readonly property real progress: length > 0 ? Math.max(0, Math.min(1, position / length)) : 0
    // lyrics view is only for the wide cards (the small one has no room)
    readonly property bool lyricsView: lyricsOn && !isSmall
    // index of the line being sung (-1 = before the first line / not synced)
    readonly property int lyricIdx: {
        var L = lyrics;
        if (!lyricsSynced || !L || L.length === 0) return -1;
        var p = position + 0.3, lo = 0, hi = L.length - 1, r = -1;
        while (lo <= hi) {
            var mid = (lo + hi) >> 1;
            if (L[mid].t <= p) { r = mid; lo = mid + 1; } else hi = mid - 1;
        }
        return r;
    }
    // while the bar is dragged (and a moment after, until the player reports the new position) show the dragged value
    property bool seeking: false
    property bool seekHold: false
    property real seekFrac: 0
    readonly property bool seekShown: seeking || seekHold
    readonly property real shownFrac: seekShown ? seekFrac : progress
    readonly property real shownPos: seekShown ? seekFrac * length : position
    Timer { id: seekHoldTimer; interval: 900; onTriggered: w.seekHold = false }
    readonly property string shownTitle: hasPlayer ? (title !== "" ? title : I18n.tr("Unknown Title")) : I18n.tr("Not Playing")
    readonly property string shownSub: hasPlayer ? (artist !== "" ? (album !== "" ? artist + " \u2014 " + album : artist) : album)
                                                 : "Open a music app"




    // ── layout numbers (RU), per size ──
    readonly property real mx: 23                                     // side margin
    readonly property real artX: isLarge ? (wr - artS) / 2 : w.mx
    readonly property real artY: 23
    readonly property real artS: isSmall ? 110 : (isMedium ? hr - 142 : hr - 218)
    readonly property real textX: isSmall ? w.mx : (isMedium ? w.mx + artS + 18 : w.mx)
    readonly property real titleCY: isSmall ? hr - 60 : (isMedium ? artY + artS / 2 - 16 : hr - 165)
    readonly property real subCY: isSmall ? hr - 31 : (isMedium ? artY + artS / 2 + 16 : hr - 137.5)
    readonly property real barCY: hr - 95.5
    readonly property real timeCY: hr - 75.2
    readonly property real ctlCY: hr - 44

    // the contents (artwork, title, controls) fill the card edge to edge
    Item {
        id: content
        anchors.fill: parent

        // ── artwork ──
        PlayerArt {
            id: artItem
            wd: w
            x: w.artX * w.k
            y: w.artY * w.k
            width: w.artS * w.k
            height: width
            r: (w.isLarge ? 11 : (w.isSmall ? 11 : 12)) * w.k
            opacity: w.lyricsView ? 0 : 1
            visible: opacity > 0
            scale: w.lyricsView ? 0.9 : 1
            transformOrigin: Item.TopLeft
            Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 480; easing.type: Easing.OutCubic } }
            layer.enabled: opacity > 0 && opacity < 0.999
            layer.sourceRect: Qt.rect(-16, -16, width + 32, height + 32)
            layer.effect: MultiEffect { blurEnabled: true; blurMax: 32; blur: Math.min(1, (1 - artItem.opacity) * 0.9) }
        }

        // ── title ──
        Text {
            id: titleItem
            x: w.textX * w.k
            y: w.titleCY * w.k - height / 2
            width: (w.wr - w.textX - w.mx - (w.isMedium ? 50 : 0)) * w.k
            height: 30 * w.k
            opacity: w.lyricsView ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
            layer.enabled: opacity > 0 && opacity < 0.999
            layer.sourceRect: Qt.rect(-12, -8, width + 24, height + 16)
            layer.effect: MultiEffect { blurEnabled: true; blurMax: 24; blur: Math.min(1, (1 - titleItem.opacity) * 0.9) }
            verticalAlignment: Text.AlignVCenter
            text: w.shownTitle
            elide: Text.ElideRight
            color: w.fg
            font.family: w.fam
            font.pixelSize: (w.isSmall ? 21 : 24) * w.k
            font.weight: Font.DemiBold
        }

        // ── subtitle: artist - album, scrolling when it does not fit ──
        MarqueeText {
            id: subItem
            x: (w.textX - 17) * w.k
            y: w.subCY * w.k - height / 2
            width: (w.wr - (w.textX - 17) - (w.mx - 17) - (w.isMedium ? 50 : 0)) * w.k
            opacity: w.lyricsView ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
            layer.enabled: opacity > 0 && opacity < 0.999
            layer.sourceRect: Qt.rect(-12, -8, width + 24, height + 16)
            layer.effect: MultiEffect { blurEnabled: true; blurMax: 24; blur: Math.min(1, (1 - subItem.opacity) * 0.9) }
            text: w.shownSub
            color: w.fg2
            fam: w.fam
            pixelSize: (w.isSmall ? 18 : 21) * w.k
            weight: Font.Medium
            fade: 20 * w.k
            startPad: 17 * w.k
            animate: !w.preview && w.playing
        }

        // ── small: play / pause at the top right ──
        PlayerBtn {
            visible: w.isSmall
            wd: w
            x: (w.wr - w.mx - 46) * w.k
            y: 23 * w.k
            width: 46 * w.k
            height: width
            kind: w.playing ? "pause" : "play"
            col: w.fgBtn
            gw: 22 * w.k
            gh: 26 * w.k
            on: true
            onClicked: w.togglePlaying()
        }

        // ── lyrics: plain text straight on the card (no panel, no glass); the current line is big and sharp,
        //    the others shrink, dim and blur with their distance, and everything glides when the song moves on ──
        Item {
            id: lyr
            x: w.mx * w.k
            y: 16 * w.k
            width: (w.wr - 2 * w.mx - 52) * w.k
            height: ((w.lyricsView ? w.ctlCY - 40 : w.barCY - 14) - 16) * w.k
            Behavior on height { NumberAnimation { duration: 480; easing.type: Easing.OutCubic } }
            opacity: w.lyricsView ? 1 : 0
            visible: opacity > 0
            scale: w.lyricsView ? 1 : 0.94
            transformOrigin: Item.Left
            Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 480; easing.type: Easing.OutCubic } }
            layer.enabled: opacity > 0 && opacity < 0.999
            layer.sourceRect: Qt.rect(-16, -16, width + 32, height + 32)
            layer.effect: MultiEffect { blurEnabled: true; blurMax: 32; blur: Math.min(1, (1 - lyr.opacity) * 0.9) }

            // feathered top and bottom edge: the lines melt away smoothly instead of being cut off
            Rectangle {
                id: lyrMask
                anchors.fill: lyrList
                visible: false
                layer.enabled: true
                readonly property real fp: Math.min(0.32, 46 * w.k / Math.max(1, height))      // feather depth: 46 reference px at each end (raise for a longer fade)
                gradient: Gradient {
                    GradientStop { position: 0.0;                  color: Qt.rgba(0, 0, 0, 0.0) }
                    GradientStop { position: lyrMask.fp * 0.25;    color: Qt.rgba(0, 0, 0, 0.04) }
                    GradientStop { position: lyrMask.fp * 0.50;    color: Qt.rgba(0, 0, 0, 0.30) }
                    GradientStop { position: lyrMask.fp * 0.75;    color: Qt.rgba(0, 0, 0, 0.72) }
                    GradientStop { position: lyrMask.fp;           color: Qt.rgba(0, 0, 0, 1.0) }
                    GradientStop { position: 1 - lyrMask.fp;       color: Qt.rgba(0, 0, 0, 1.0) }
                    GradientStop { position: 1 - lyrMask.fp * 0.75; color: Qt.rgba(0, 0, 0, 0.72) }
                    GradientStop { position: 1 - lyrMask.fp * 0.50; color: Qt.rgba(0, 0, 0, 0.30) }
                    GradientStop { position: 1 - lyrMask.fp * 0.25; color: Qt.rgba(0, 0, 0, 0.04) }
                    GradientStop { position: 1.0;                  color: Qt.rgba(0, 0, 0, 0.0) }
                }
            }
            ListView {
                id: lyrList
                anchors.fill: parent
                clip: true
                interactive: !w.lyricsSynced
                boundsBehavior: Flickable.StopAtBounds
                model: w.lyrics
                currentIndex: Math.max(0, w.lyricIdx)
                highlightRangeMode: w.lyricsSynced ? ListView.StrictlyEnforceRange : ListView.NoHighlightRange
                preferredHighlightBegin: height * 0.30
                preferredHighlightEnd: height * 0.30
                highlightMoveDuration: 650
                highlightMoveVelocity: -1
                layer.enabled: true
                layer.effect: MultiEffect { maskEnabled: true; maskSource: lyrMask }

                delegate: Item {
                    id: ln
                    required property var modelData
                    required property int index
                    readonly property real dist: w.lyricsSynced ? Math.abs(index - w.lyricIdx) : 0
                    readonly property bool cur: w.lyricsSynced && index === w.lyricIdx
                    property real bl: (!w.lyricsSynced || cur) ? 0 : Math.min(1, 0.22 + dist * 0.16)
                    Behavior on bl { NumberAnimation { duration: 480; easing.type: Easing.OutCubic } }
                    width: ListView.view.width
                    height: txt.implicitHeight + 12 * w.k
                    Text {
                        id: txt
                        width: parent.width
                        anchors.verticalCenter: parent.verticalCenter
                        text: ln.modelData.text !== "" ? ln.modelData.text : "\u266A"
                        wrapMode: Text.Wrap
                        color: w.fg
                        font.family: w.fam
                        font.pixelSize: 25 * w.k
                        font.weight: Font.Bold
                        opacity: !w.lyricsSynced ? 0.9 : (ln.cur ? 1 : Math.max(0.16, 0.46 - ln.dist * 0.08))
                        scale: (!w.lyricsSynced || ln.cur) ? 1 : 0.86
                        transformOrigin: Item.Left
                        Behavior on opacity { NumberAnimation { duration: 480; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 480; easing.type: Easing.OutCubic } }
                        layer.enabled: ln.bl > 0.01
                        layer.sourceRect: Qt.rect(-12, -8, width + 24, height + 16)
                        layer.effect: MultiEffect { blurEnabled: true; blurMax: 24; blur: ln.bl }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: w.lyricsSynced && w.canSeek && !w.preview && !w.editing
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: w.seek(ln.modelData.t)       // tap a line to jump to it
                    }
                }
            }
            Text {   // searching / nothing found
                anchors.centerIn: parent
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: w.lyrics.length === 0
                text: w.lyricsState === "none" ? I18n.tr("No lyrics found") : I18n.tr("Searching for lyrics\u2026")
                color: w.fg2
                font.family: w.fam
                font.pixelSize: 20 * w.k
                font.weight: Font.Medium
            }
        }

        // ── progress bar: click or drag to seek ──
        Rectangle {
            id: bar
            visible: !w.isSmall && opacity > 0
            opacity: w.lyricsView ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
            layer.enabled: opacity > 0 && opacity < 0.999
            layer.sourceRect: Qt.rect(-12, -16, width + 24, height + 32)
            layer.effect: MultiEffect { blurEnabled: true; blurMax: 24; blur: Math.min(1, (1 - bar.opacity) * 0.9) }
            x: w.mx * w.k
            y: w.barCY * w.k - height / 2
            width: (w.wr - 2 * w.mx) * w.k
            height: (seekMa.pressed || seekMa.containsMouse ? 11 : 7) * w.k
            Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            radius: height / 2
            color: w.trackCol
            Rectangle {
                width: w.hasPlayer && w.length > 0 ? Math.max(parent.height, parent.width * w.shownFrac) : 0
                height: parent.height
                radius: height / 2
                color: seekMa.pressed || seekMa.containsMouse ? w.fa(w.dark ? 0.78 : 0.66) : w.fillCol
                Behavior on color { ColorAnimation { duration: 140 } }
            }
            MouseArea {
                id: seekMa
                anchors.fill: parent
                anchors.topMargin: -14 * w.k          // taller touch area than the thin bar
                anchors.bottomMargin: -14 * w.k
                hoverEnabled: true
                preventStealing: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                enabled: !w.preview && !w.editing && w.hasPlayer && w.canSeek && w.length > 0
                function frac(mx) { return Math.max(0, Math.min(1, mapToItem(bar, mx, 0).x / bar.width)); }
                onPressed: mouse => { seekHoldTimer.stop(); w.seekHold = false; w.seekFrac = frac(mouse.x); w.seeking = true; }
                onPositionChanged: mouse => { if (pressed) w.seekFrac = frac(mouse.x); }
                onReleased: {
                    w.seeking = false;
                    w.seekHold = true;
                    seekHoldTimer.restart();
                    w.seek(w.seekFrac * w.length);
                }
                onCanceled: w.seeking = false
            }
        }
        Text {
            id: timeL
            visible: !w.isSmall && opacity > 0
            opacity: w.lyricsView ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
            layer.enabled: opacity > 0 && opacity < 0.999
            layer.sourceRect: Qt.rect(-8, -8, width + 16, height + 16)
            layer.effect: MultiEffect { blurEnabled: true; blurMax: 16; blur: Math.min(1, (1 - timeL.opacity) * 0.9) }
            x: w.mx * w.k
            y: w.timeCY * w.k - height / 2
            height: 18 * w.k
            verticalAlignment: Text.AlignVCenter
            text: w.hasPlayer ? w.fmt(w.shownPos) : ""
            color: w.fg2
            font.family: w.fam
            font.pixelSize: 13 * w.k
            font.weight: Font.Medium
        }
        Text {
            id: timeR
            visible: !w.isSmall && w.length > 0 && opacity > 0
            opacity: w.lyricsView ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
            layer.enabled: opacity > 0 && opacity < 0.999
            layer.sourceRect: Qt.rect(-8, -8, width + 16, height + 16)
            layer.effect: MultiEffect { blurEnabled: true; blurMax: 16; blur: Math.min(1, (1 - timeR.opacity) * 0.9) }
            x: (w.wr - w.mx) * w.k - width
            y: w.timeCY * w.k - height / 2
            height: 18 * w.k
            verticalAlignment: Text.AlignVCenter
            text: "\u2212" + w.fmt(Math.max(0, w.length - w.shownPos))
            color: w.fg2
            font.family: w.fam
            font.pixelSize: 13 * w.k
            font.weight: Font.Medium
        }

        // ── controls: shuffle · back · play · forward · repeat ──
        PlayerBtn {
            visible: !w.isSmall
            wd: w
            x: 25 * w.k
            y: w.ctlCY * w.k - height / 2
            width: 44 * w.k
            height: width
            kind: "shuffle"
            col: w.shuffle ? w.fgBtn : w.fgDim
            gw: 26 * w.k
            gh: 21 * w.k
            on: w.shuffle
            enabledBtn: w.canShuffle
            onClicked: w.toggleShuffle()
        }
        PlayerBtn {
            visible: !w.isSmall
            wd: w
            x: 0.30 * content.width - width / 2
            y: w.ctlCY * w.k - height / 2
            width: 56 * w.k
            height: 44 * w.k
            kind: "prev"
            col: w.fgBtn
            gw: 44 * w.k
            gh: 25 * w.k
            onClicked: w.previousTrack()
        }
        PlayerBtn {
            visible: !w.isSmall
            wd: w
            x: 0.50 * content.width - width / 2
            y: w.ctlCY * w.k - height / 2
            width: 56 * w.k
            height: 52 * w.k
            kind: w.playing ? "pause" : "play"
            col: w.fa(w.dark ? 0.84 : 0.78)
            gw: (w.playing ? 30 : 32) * w.k
            gh: 38 * w.k
            onClicked: w.togglePlaying()
        }
        PlayerBtn {
            visible: !w.isSmall
            wd: w
            x: 0.70 * content.width - width / 2
            y: w.ctlCY * w.k - height / 2
            width: 56 * w.k
            height: 44 * w.k
            kind: "next"
            col: w.fgBtn
            gw: 44 * w.k
            gh: 25 * w.k
            onClicked: w.nextTrack()
        }
        PlayerBtn {
            visible: !w.isSmall
            wd: w
            x: (w.wr - 25 - 44) * w.k
            y: w.ctlCY * w.k - height / 2
            width: 44 * w.k
            height: width
            kind: "repeat"
            col: w.loop > 0 ? w.fgBtn : w.fgDim
            gw: 26 * w.k
            gh: 22 * w.k
            on: w.loop > 0
            badge: w.loop === 1 ? "1" : ""
            enabledBtn: w.canLoop
            onClicked: w.cycleLoop()
        }

        // ── lyrics button (top right corner) ──
        PlayerBtn {
            visible: !w.isSmall
            wd: w
            x: (w.wr - w.mx - 40) * w.k
            y: 18 * w.k
            width: 40 * w.k
            height: width
            kind: "lyrics"
            col: w.lyricsOn ? w.fg : w.fgBtn
            gw: 22 * w.k
            gh: 20 * w.k
            on: w.lyricsOn
            idleFill: true
            onClicked: { w.lyricsOn = !w.lyricsOn; w.lyricsToggled(w.lyricsOn); }
        }
    }
}
