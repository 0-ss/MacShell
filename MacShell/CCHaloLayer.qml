import QtQuick
import QtQuick.Effects

// One layer of the Control Center halo (see `ccHalo` in MacBar.qml): a blurred copy of the backdrop that is faded out toward the
// left and the bottom (and a hair at the top, under the bar) with smooth (smootherstep) ramps. Two masks (horizontal x vertical) are applied one
// after the other, so the soft edge is a real 2-D feather with a rounded falloff at the corner instead of a hard rectangle.
// All distances are px from this item's own top-left corner.
Item {
    id: hl
    property var src: null              // the ShaderEffectSource holding the backdrop, same size as this item
    property real blurPx: 10
    property real leftStart: 0          // left ramp: alpha 0 up to leftStart ...
    property real leftEnd: 90           // ... alpha 1 from leftEnd on
    property real bottomStart: 100      // bottom ramp: alpha 1 down to bottomStart ...
    property real bottomEnd: 200        // ... alpha 0 from bottomEnd on
    property real topEnd: 12            // top ramp: alpha 0 at the very top, 1 at topEnd
    property real strength: 1.0         // overall opacity of this layer (layers stack, so each one only adds a part)
    opacity: strength

    readonly property real lw: Math.max(1, width)
    readonly property real lh: Math.max(1, height)
    readonly property real hp0: Math.min(0.97, Math.max(0, leftStart / lw))
    readonly property real hp1: Math.min(0.99, Math.max(hp0 + 0.01, leftEnd / lw))
    readonly property real vp0: Math.min(0.90, Math.max(0.0, topEnd / lh))
    readonly property real vp1: Math.min(0.98, Math.max(vp0 + 0.01, bottomStart / lh))
    readonly property real vp2: Math.min(1.0, Math.max(vp1 + 0.01, bottomEnd / lh))

    Item {
        id: hMask
        visible: false; layer.enabled: true
        width: hl.width; height: hl.height
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
                GradientStop { position: hl.hp0; color: Qt.rgba(0, 0, 0, 0) }
                GradientStop { position: hl.hp0 + (hl.hp1 - hl.hp0) * 0.125; color: Qt.rgba(0, 0, 0, 0.0161) }
                GradientStop { position: hl.hp0 + (hl.hp1 - hl.hp0) * 0.250; color: Qt.rgba(0, 0, 0, 0.1035) }
                GradientStop { position: hl.hp0 + (hl.hp1 - hl.hp0) * 0.375; color: Qt.rgba(0, 0, 0, 0.2752) }
                GradientStop { position: hl.hp0 + (hl.hp1 - hl.hp0) * 0.500; color: Qt.rgba(0, 0, 0, 0.5000) }
                GradientStop { position: hl.hp0 + (hl.hp1 - hl.hp0) * 0.625; color: Qt.rgba(0, 0, 0, 0.7248) }
                GradientStop { position: hl.hp0 + (hl.hp1 - hl.hp0) * 0.750; color: Qt.rgba(0, 0, 0, 0.8965) }
                GradientStop { position: hl.hp0 + (hl.hp1 - hl.hp0) * 0.875; color: Qt.rgba(0, 0, 0, 0.9839) }
                GradientStop { position: hl.hp1; color: Qt.rgba(0, 0, 0, 1) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 1) }
            }
        }
    }
    Item {
        id: vMask
        visible: false; layer.enabled: true
        width: hl.width; height: hl.height
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
                GradientStop { position: hl.vp0; color: Qt.rgba(0, 0, 0, 1) }
                GradientStop { position: hl.vp1; color: Qt.rgba(0, 0, 0, 1) }
                GradientStop { position: hl.vp1 + (hl.vp2 - hl.vp1) * 0.125; color: Qt.rgba(0, 0, 0, 0.9839) }
                GradientStop { position: hl.vp1 + (hl.vp2 - hl.vp1) * 0.250; color: Qt.rgba(0, 0, 0, 0.8965) }
                GradientStop { position: hl.vp1 + (hl.vp2 - hl.vp1) * 0.375; color: Qt.rgba(0, 0, 0, 0.7248) }
                GradientStop { position: hl.vp1 + (hl.vp2 - hl.vp1) * 0.500; color: Qt.rgba(0, 0, 0, 0.5000) }
                GradientStop { position: hl.vp1 + (hl.vp2 - hl.vp1) * 0.625; color: Qt.rgba(0, 0, 0, 0.2752) }
                GradientStop { position: hl.vp1 + (hl.vp2 - hl.vp1) * 0.750; color: Qt.rgba(0, 0, 0, 0.1035) }
                GradientStop { position: hl.vp1 + (hl.vp2 - hl.vp1) * 0.875; color: Qt.rgba(0, 0, 0, 0.0161) }
                GradientStop { position: hl.vp2; color: Qt.rgba(0, 0, 0, 0) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0) }
            }
        }
    }
    MultiEffect {
        id: hFx
        width: hl.width; height: hl.height
        source: hl.src
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: 32
        blur: Math.min(1.0, hl.blurPx / 32)
        maskEnabled: true
        maskSource: hMask
        visible: false
    }
    ShaderEffectSource {
        id: hSes
        sourceItem: hFx
        live: hl.visible
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: hSes
        autoPaddingEnabled: false
        maskEnabled: true
        maskSource: vMask
    }
}
