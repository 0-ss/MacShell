// Text where only what you just typed animates: the letters already on screen never move, re-render or flicker.
// Typing blurs in the new tail, backspace blurs the removed tail out (and collapses its width).
import QtQuick
import QtQuick.Effects

Row {
    id: ct
    property string text: ""
    property color color: "white"
    property alias font: sizer.font
    spacing: 0

    // what is already settled, what just arrived, and what is on its way out
    property string settled: ""
    property string fresh: ""
    property string leaving: ""
    property real inT: 1
    property real outT: 1

    Text { id: sizer; visible: false }

    onTextChanged: apply()
    Component.onCompleted: { settled = text; fresh = ""; leaving = ""; }

    function apply() {
        var prev = settled + fresh;
        if (text === prev) return;
        var k = 0;
        while (k < prev.length && k < text.length && prev.charAt(k) === text.charAt(k)) k++;
        leaveTimer.stop();
        if (k === prev.length && text.length > prev.length) {
            settled = prev; fresh = text.substring(k); leaving = "";       // typed at the end
        } else if (k === text.length && text.length < prev.length) {
            settled = text; fresh = ""; leaving = prev.substring(k);       // deleted from the end
        } else {
            settled = text.substring(0, k); fresh = text.substring(k); leaving = prev.substring(k);
        }
        if (fresh !== "") { inT = 0; inAnim.restart(); }
        if (leaving !== "") { outT = 0; outAnim.restart(); leaveTimer.restart(); }
    }
    NumberAnimation { id: inAnim; target: ct; property: "inT"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
    NumberAnimation { id: outAnim; target: ct; property: "outT"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
    // once it has faded, the outgoing text is dropped and the new tail counts as settled
    Timer { id: leaveTimer; interval: 210; onTriggered: { ct.leaving = ""; ct.outT = 1; } }
    Timer { interval: 280; running: ct.fresh !== ""; repeat: true; onTriggered: { if (ct.inT >= 1) { ct.settled += ct.fresh; ct.fresh = ""; } } }

    // already on screen: never touched again
    Text {
        text: ct.settled
        font: sizer.font
        color: ct.color
    }
    // the character(s) you just typed: blur in, widening as they arrive
    Item {
        width: freshTxt.implicitWidth * ct.inT
        height: freshTxt.implicitHeight
        visible: ct.fresh !== ""
        Text {
            id: freshTxt
            text: ct.fresh
            font: sizer.font
            color: ct.color
            opacity: Math.min(1, ct.inT * 1.5)
            layer.enabled: ct.inT < 0.99
            layer.effect: MultiEffect { blurEnabled: true; blurMax: 20; blur: 1 - ct.inT; autoPaddingEnabled: true }
        }
    }
    // what you just deleted: blurs out while its space closes up
    Item {
        width: leaveTxt.implicitWidth * (1 - ct.outT)
        height: leaveTxt.implicitHeight
        visible: ct.leaving !== ""
        Text {
            id: leaveTxt
            text: ct.leaving
            font: sizer.font
            color: ct.color
            opacity: 1 - ct.outT
            layer.enabled: ct.outT > 0.01
            layer.effect: MultiEffect { blurEnabled: true; blurMax: 20; blur: ct.outT; autoPaddingEnabled: true }
        }
    }
}
