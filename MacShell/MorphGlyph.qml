// Blur + morph for icons: changing `kind` blurs the old glyph out while the new one sharpens in.
import QtQuick
import QtQuick.Effects

Item {
    id: mg
    property string kind: ""
    property color color: "white"
    property int duration: 360
    property bool flip: false
    property bool ready: false
    Component.onCompleted: { ga.kind = kind; ready = true; }
    onKindChanged: {
        if (!ready) return;
        var incoming = flip ? ga : gb, outgoing = flip ? gb : ga;
        if (outgoing.kind === kind) return;
        incoming.kind = kind;
        flip = !flip;
        morph.stop(); morph.inG = incoming; morph.outG = outgoing; morph.start();
    }
    component G: Item {
        id: gItem
        property alias kind: gl.kind
        property real bl: 0
        anchors.fill: parent
        WGlyph { id: gl; anchors.fill: parent; color: mg.color }
        layer.enabled: bl > 0.001
        layer.effect: MultiEffect { blurEnabled: true; blurMax: 16; blur: gItem.bl; autoPaddingEnabled: true }
    }
    G { id: ga; opacity: 1 }
    G { id: gb; opacity: 0 }
    ParallelAnimation {
        id: morph
        property Item inG: null
        property Item outG: null
        NumberAnimation { target: morph.outG; property: "opacity"; to: 0; duration: mg.duration * 0.7; easing.type: Easing.OutCubic }
        NumberAnimation { target: morph.outG; property: "bl"; to: 1; duration: mg.duration * 0.7; easing.type: Easing.OutCubic }
        NumberAnimation { target: morph.outG; property: "scale"; to: 0.7; duration: mg.duration; easing.type: Easing.OutQuint }
        NumberAnimation { target: morph.inG; property: "opacity"; from: 0; to: 1; duration: mg.duration; easing.type: Easing.OutQuint }
        NumberAnimation { target: morph.inG; property: "bl"; from: 1; to: 0; duration: mg.duration; easing.type: Easing.OutQuint }
        NumberAnimation { target: morph.inG; property: "scale"; from: 1.3; to: 1; duration: mg.duration; easing.type: Easing.OutQuint }
    }
}
