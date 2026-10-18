// Blur + morph text: when `text` changes the old text blurs out (fading, shrinking a touch) while the new one comes
// into focus out of a blur. Width changes and alignment changes animate, so re-aligned text glides instead of jumping.
// Drop-in for a Text: text, font, color, horizontalAlignment, elide, renderType.
//   useBlur: false → no blur effect inside (fade + scale only); read `morphBlur` (1 → 0 during a morph) to blur the
//                    result yourself — needed when this item is the hidden source of another effect (the glass clock).
import QtQuick
import QtQuick.Effects

Item {
    id: mt
    property string text: ""
    property font font
    property color color: "white"
    property int horizontalAlignment: Text.AlignLeft
    property int elide: Text.ElideNone
    property int renderType: Text.QtRendering
    property int duration: 420
    property int alignDuration: 650
    property real blurMax: 44
    property bool animateWidth: true
    property bool useBlur: true
    property real scaleIn: 1.06            // incoming text starts this big
    property real scaleOut: 0.94           // outgoing text ends this small
    property real morphBlur: 0             // 1 → 0 while a morph runs
    property bool stretch: true            // the old text stretches into the new one's width (and vice versa)

    // always the width of the text that is showing; animated so re-alignment glides
    property real wTarget: (flip ? b : a).textW
    Behavior on wTarget { enabled: mt.animateWidth && mt.ready; NumberAnimation { duration: mt.duration; easing.type: Easing.OutQuint } }
    implicitWidth: wTarget
    implicitHeight: (flip ? b : a).implicitHeight

    // 0 = left, 0.5 = centre, 1 = right — animated, so switching alignment slides the text over
    property real alignT: horizontalAlignment === Text.AlignHCenter ? 0.5 : (horizontalAlignment === Text.AlignRight ? 1 : 0)
    Behavior on alignT { enabled: mt.ready; NumberAnimation { duration: mt.alignDuration; easing.type: Easing.OutQuint } }

    property bool flip: false
    property bool ready: false
    Component.onCompleted: { a.text = text; ready = true; }
    onTextChanged: {
        if (!ready) return;
        var incoming = flip ? a : b, outgoing = flip ? b : a;
        if (outgoing.text === text) return;
        incoming.text = text;
        flip = !flip;
        morph.stop();
        morph.inT = incoming; morph.outT = outgoing;
        // stretch: each word squeezes / widens toward the other one's width, so one reads as turning into the other
        var wo = Math.max(1, outgoing.width * outgoing.sx), wi = Math.max(1, incoming.textW);
        morph.outSx = stretch ? Math.max(0.35, Math.min(2.5, wi / Math.max(1, outgoing.width))) : 1;
        morph.inSx = stretch ? Math.max(0.35, Math.min(2.5, wo / wi)) : 1;
        morph.start();
    }

    // one text layer: crisp Text when sharp; while blurred, a blur effect fed from a hidden copy takes over
    component Layer: Item {
        id: ly
        property string text: ""
        property real bl: 0
        readonly property real textW: crisp.implicitWidth
        implicitHeight: crisp.implicitHeight
        // as wide as the text itself (only clamped to the box when it elides), placed by the animated alignment —
        // never squeezed: a squeezed left-aligned Text overflows to the right (the clock drifted right and got cropped)
        readonly property real boxW: mt.width > 0 ? mt.width : textW
        width: mt.elide === Text.ElideNone ? textW : Math.min(textW, boxW)
        height: implicitHeight
        anchors.verticalCenter: parent.verticalCenter
        x: mt.alignT * (mt.width - width)
        transformOrigin: Item.Center
        property real sx: 1                // horizontal stretch while morphing
        transform: Scale { origin.x: mt.alignT * ly.width; origin.y: ly.height / 2; xScale: ly.sx }
        // sharp ↔ blurred hand-over: the two renderings cross-fade over the last stretch of the blur (a hard switch at
        // blur 0 made the text visibly snap at the end of every morph)
        readonly property real fx: mt.useBlur ? Math.min(1, ly.bl / 0.35) : 0
        Text {
            id: crisp
            anchors.fill: parent
            opacity: 1 - ly.fx
            visible: opacity > 0.001
            text: ly.text
            horizontalAlignment: Text.AlignLeft
            elide: mt.elide
            font: mt.font
            color: mt.color
            renderType: mt.renderType
        }
        // the blurred copy is laid out on exactly the same pixels as the crisp text, inside a padded box (no auto
        // padding shifting it), so the two line up while they cross-fade
        Item {
            id: pbox
            readonly property real pad: Math.ceil(mt.blurMax)
            x: -pad; y: -pad
            width: ly.width + 2 * pad; height: ly.height + 2 * pad
            visible: mt.useBlur && ly.fx > 0.001
            Item {
                id: srcBox
                anchors.fill: parent
                visible: false
                Text {
                    x: pbox.pad; y: pbox.pad
                    width: ly.width; height: ly.height
                    text: ly.text
                    elide: mt.elide
                    font: mt.font
                    color: mt.color
                    renderType: mt.renderType
                }
            }
            MultiEffect {
                anchors.fill: parent
                source: srcBox
                opacity: ly.fx
                blurEnabled: true
                blurMax: mt.blurMax
                blur: ly.bl
                autoPaddingEnabled: false
            }
        }
    }
    Layer { id: a; opacity: 1 }
    Layer { id: b; opacity: 0 }

    ParallelAnimation {
        id: morph
        property Item inT: null
        property Item outT: null
        property real outSx: 1
        property real inSx: 1
        NumberAnimation { target: morph.outT; property: "sx"; to: morph.outSx; duration: mt.duration; easing.type: Easing.OutQuint }
        NumberAnimation { target: morph.inT; property: "sx"; from: morph.inSx; to: 1; duration: mt.duration; easing.type: Easing.OutQuint }
        NumberAnimation { target: morph.outT; property: "opacity"; to: 0; duration: mt.duration * 0.75; easing.type: Easing.OutCubic }
        NumberAnimation { target: morph.outT; property: "bl"; to: 1; duration: mt.duration * 0.75; easing.type: Easing.OutCubic }
        NumberAnimation { target: morph.outT; property: "scale"; to: mt.scaleOut; duration: mt.duration; easing.type: Easing.OutQuint }
        NumberAnimation { target: morph.inT; property: "opacity"; from: 0; to: 1; duration: mt.duration; easing.type: Easing.OutQuint }
        NumberAnimation { target: morph.inT; property: "bl"; from: 1; to: 0; duration: mt.duration; easing.type: Easing.OutQuint }
        NumberAnimation { target: morph.inT; property: "scale"; from: mt.scaleIn; to: 1; duration: mt.duration; easing.type: Easing.OutQuint }
        NumberAnimation { target: mt; property: "morphBlur"; from: 1; to: 0; duration: mt.duration; easing.type: Easing.OutQuint }
    }
}
