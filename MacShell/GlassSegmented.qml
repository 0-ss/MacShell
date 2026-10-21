import QtQuick
import "I18n.js" as I18n

// Segmented control (macOS Tahoe look): a capsule track, thin dividers between the options that are not selected, and a
// capsule that marks the chosen option.
//
//  * choosing another option makes the marker turn into Liquid Glass (the same shader, the same Control Center border and
//    the same grow-and-settle motion as the knob of GlassSwitch) while it slides to the new option; it then settles back
//    into a plain capsule
//  * the slide is fluid: the leading edge runs ahead with a little overshoot while the trailing edge lags behind, so the
//    marker stretches while it moves
//  * click an option, or press the marker and drag it across the options (it follows the pointer and snaps to the
//    nearest option on release)
//  * the glass lens refracts the option labels, so the chosen word is seen through it
//
// `current` is only ever set by the owner (the usual  current: x   +   onPicked: i => x = i  pattern).
Item {
    id: g

    property var model: []
    property int current: 0
    property real segWidth: 0                 // 0: every option is as wide as its label; > 0: fixed width per option
    property real labelPad: 14
    property string fontFamily: "Open Runde"
    property real fontSize: 12
    signal picked(int index)
    signal glassFailed()

    // look
    property bool dark: true
    property color textColor: dark ? "#F5F5F7" : "#1D1D1F"
    property color trackColor: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06)
    property color trackBorder: dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.07)
    property color dividerColor: dark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.14)
    property color pillColor: dark ? "#636366" : "#FFFFFF"
    property color baseColor: dark ? "#2B2B2D" : "#FFFFFF"       // what lies under the control (the lens refracts it)
    // glass
    property bool glass: false                // false: the marker stays a plain capsule
    property url shaderUrl: ""
    property real glassLiquid: 1.0
    property real glassRim: 0.45
    property real glassGrain: 0.03
    property real glassTint: 0.42
    property color borderTint: "#8A9AB5"
    property real lensStrength: 0.2           // how strongly the glass bends what is behind it (the switch knob uses 0.85)

    height: 28
    width: segRow.width + 2 * inset
    opacity: enabled ? 1 : 0.45

    readonly property real inset: 2
    readonly property real kh0: height - 2 * inset
    readonly property int count: model ? model.length : 0

    // ── layout of the options (positions are read back from the row, so every width, fixed or from the text, works) ──
    property int geoTick: 0
    function segX(i) { var it = rep.itemAt(i); return it ? segRow.x + it.x : inset; }
    function segW(i) { var it = rep.itemAt(i); return it ? it.width : 0; }

    // ── the marker: its two edges run on their own (pixels inside this item) ──
    property real pL: inset
    property real pR: inset
    property int tgtIdx: -1
    property bool ready: false
    property bool dragging: false
    property int want: -1

    // glass state: pressed, or just released / just changed (keeps the glass through the slide)
    property bool hold: false
    readonly property bool glassOn: ma.pressed || hold
    property real pressT: glassOn ? 1 : 0
    Behavior on pressT { NumberAnimation { duration: g.glassOn ? 420 : 320; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }
    onGlassOnChanged: if (glassOn) ses.scheduleUpdate()
    Timer { id: holdT; interval: 480; onTriggered: g.hold = false }

    readonly property real gw: height * 0.14          // the marker grows a little while it is glass
    readonly property real gh: height * 0.07

    NumberAnimation { id: animL; target: g; property: "pL" }
    NumberAnimation { id: animR; target: g; property: "pR" }
    function snap() {
        var i = Math.max(0, Math.min(count - 1, current));
        tgtIdx = current >= 0 ? i : -1;
        pL = segX(i); pR = segX(i) + segW(i);
    }
    function settleTo(i) {
        if (i < 0 || i >= count) return;
        var tl = segX(i), tr = segX(i) + segW(i);
        if (!ready) { tgtIdx = i; pL = tl; pR = tr; return; }
        if (i === tgtIdx && (animL.running || animR.running)) return;
        tgtIdx = i;
        var up = tr >= pR;
        animL.stop(); animR.stop();
        var lead = up ? animR : animL, trail = up ? animL : animR;
        lead.duration = 300;  lead.easing.type = Easing.OutBack;  lead.easing.overshoot = 1.7;
        trail.duration = 440; trail.easing.type = Easing.OutBack; trail.easing.overshoot = 0.9;
        animL.to = tl; animR.to = tr;
        animL.start(); animR.start();
    }
    function commit(i) {
        hold = true; holdT.restart();                                  // glass through the slide
        settleTo(i);
        if (i !== current) { want = i; picked(i); refuse.restart(); }
    }
    // the owner may refuse (or be slow to apply) the change: follow `current` again if it did not come
    Timer { id: refuse; interval: 1200; onTriggered: if (g.current !== g.want) g.settleTo(g.current) }
    onCurrentChanged: {
        if (!ready || dragging || ma.pressed) return;
        if (current >= 0) { hold = true; holdT.restart(); settleTo(current); }
        else tgtIdx = -1;
    }
    onGeoTickChanged: if (ready && !animL.running && !animR.running && !dragging && !ma.pressed) snap()
    onCountChanged: if (ready) snap()
    Component.onCompleted: Qt.callLater(function () { geoTick++; snap(); ready = true; })

    // ── track ──
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: g.trackColor
        border.width: 1; border.color: g.trackBorder
    }

    // ── thin dividers between the options (hidden next to the marker) ──
    Repeater {
        model: Math.max(0, g.count - 1)
        delegate: Rectangle {
            required property int index
            width: 1
            height: Math.round(g.height * 0.5)
            y: Math.round((g.height - height) / 2)
            x: { g.geoTick; return Math.round(g.segX(index) + g.segW(index)); }
            color: g.dividerColor
            opacity: (index === g.tgtIdx || index + 1 === g.tgtIdx) ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }
    }

    // ── the marker, plain (the glass one fades in over it while it moves) ──
    Item {
        id: pill
        visible: g.tgtIdx >= 0
        x: g.pL - g.gw * g.pressT / 2
        y: (g.height - height) / 2
        width: Math.max(height, g.pR - g.pL + g.gw * g.pressT)
        height: g.kh0 + g.gh * g.pressT
        readonly property real rad: height / 2
        readonly property real plainOp: g.glass ? Math.max(0, Math.min(1, 1 - g.pressT * 1.4)) : 1
        Rectangle {
            anchors.fill: parent
            radius: pill.rad
            color: g.pillColor
            border.width: 1; border.color: g.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.10)
            opacity: pill.plainOp
        }
    }

    // ── the labels ──
    Row {
        id: segRow
        x: g.inset; y: g.inset
        Repeater {
            id: rep
            model: g.model
            delegate: Item {
                id: seg
                required property var modelData
                required property int index
                width: g.segWidth > 0 ? g.segWidth : lbl.implicitWidth + 2 * g.labelPad
                height: g.kh0
                onWidthChanged: g.geoTick++
                onXChanged: g.geoTick++
                Component.onCompleted: g.geoTick++
                Text {
                    id: lbl
                    anchors.centerIn: parent
                    text: I18n.tr(seg.modelData)
                    color: g.textColor
                    font.family: g.fontFamily
                    font.pixelSize: g.fontSize
                    font.weight: Font.DemiBold
                }
            }
        }
    }

    // ── what the lens sees (hidden copy of the track and the labels, on a backdrop) ──
    readonly property real m: 22
    Item {
        id: lyr
        visible: g.glass
        x: -g.m; y: -g.m
        width: g.width + 2 * g.m; height: g.height + 2 * g.m
        Rectangle { anchors.fill: parent; color: g.baseColor }
        Rectangle { x: g.m; y: g.m; width: g.width; height: g.height; radius: height / 2; color: g.trackColor }
        Repeater {
            model: g.model
            delegate: Text {
                required property var modelData
                required property int index
                x: { g.geoTick; return g.m + g.segX(index) + (g.segW(index) - implicitWidth) / 2; }
                y: g.m + (g.height - implicitHeight) / 2
                text: I18n.tr(modelData)
                color: g.textColor
                font.family: g.fontFamily
                font.pixelSize: g.fontSize
                font.weight: Font.DemiBold
            }
        }
    }
    ShaderEffectSource {
        id: ses
        sourceItem: g.glass ? lyr : null
        hideSource: true
        live: g.glass && (g.glassOn || g.pressT > 0.02)
        mipmap: true
        visible: false
    }

    // ── the marker, glass ──
    Item {
        id: lens
        visible: g.tgtIdx >= 0
        x: pill.x; y: pill.y; width: pill.width; height: pill.height
        Loader {
            anchors.fill: parent
            active: g.glass && g.pressT > 0.02
            opacity: Math.max(0, Math.min(1, g.pressT * 1.6))
            sourceComponent: Item {
                GlassSlab {
                    anchors.fill: parent
                    src: ses
                    srcSize: Qt.size(lyr.width, lyr.height)
                    origin: Qt.point(g.m + lens.x, g.m + lens.y)
                    glass: g.glass
                    shaderUrl: g.shaderUrl
                    dark: g.dark
                    cornerR: lens.height / 2
                    thickness: Math.round(g.kh0 * 0.7)
                    strengthMul: g.lensStrength
                    liquid: g.glassLiquid
                    rim: g.glassRim * 0.25
                    grain: g.glassGrain
                    tint: g.glassTint
                    shadowAmt: 0.5
                    flatInner: 1
                    onFailed: g.glassFailed()
                }
                // same border as the Control Center buttons, sliders and switches
                CornerBorder { z: 2; anchors.fill: parent; cornerR: lens.height / 2; dark: g.dark; tint: g.borderTint; amount: 1; lineW: 0.9 }
                // soft specular sheen along the top
                Rectangle {
                    anchors.fill: parent
                    radius: lens.height / 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, g.dark ? 0.12 : 0.2) }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.02) }
                        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, g.dark ? 0.04 : 0.08) }
                    }
                }
            }
        }
    }

    // ── mouse: click an option, or press the marker and drag it across the options ──
    MouseArea {
        id: ma
        anchors.fill: parent
        anchors.margins: -3
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        property real pressX: 0
        property real lastX: 0
        property real grab: 0
        property real vx: 0
        function lx(m) { return ma.mapToItem(g, m.x, m.y).x; }
        function idxAt(x) {
            for (var i = 0; i < g.count; i++) if (x < g.segX(i) + g.segW(i)) return i;
            return Math.max(0, g.count - 1);
        }
        onPressed: mouse => {
            holdT.stop(); g.hold = false;
            animL.stop(); animR.stop();
            pressX = lx(mouse); lastX = pressX; vx = 0;
            grab = pressX - (g.pL + g.pR) / 2;
            g.dragging = false;
        }
        onPositionChanged: mouse => {
            if (!pressed) return;
            var x = lx(mouse);
            if (!g.dragging && Math.abs(x - pressX) > 3) g.dragging = true;
            if (!g.dragging) return;
            var w = g.pR - g.pL;
            var lo = g.segX(0) + w / 2, hi = g.segX(g.count - 1) + g.segW(g.count - 1) - w / 2;
            var c = Math.max(lo, Math.min(hi, x - grab));
            g.pL = c - w / 2; g.pR = c + w / 2;
            vx = vx * 0.5 + (x - lastX) * 0.5;
            lastX = x;
        }
        onReleased: mouse => {
            var i;
            if (g.dragging) {
                var c = (g.pL + g.pR) / 2 + (Math.abs(vx) > 4 ? vx * 3 : 0);       // a flick carries it a little further
                i = idxAt(c);
            } else {
                i = idxAt(lx(mouse));
            }
            g.dragging = false;
            g.commit(i);
        }
        onCanceled: {
            g.dragging = false;
            g.hold = true; holdT.restart();
            g.settleTo(g.tgtIdx >= 0 ? g.tgtIdx : g.current);
        }
    }
}
