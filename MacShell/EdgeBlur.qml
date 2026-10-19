import QtQuick
import QtQuick.Effects

// Progressive blur feather: a blurred copy of a Flickable's content along one edge, strongest at the very edge and
// dissolving inwards (the sharp content underneath fades out with it, see the masks of the Flickables in MacDock.qml).
Item {
    id: eb
    property var target: null           // the Flickable
    property bool atTop: true
    property real depth: 34
    property real amount: 1
    height: depth
    opacity: amount
    visible: target !== null && opacity > 0.01
    ShaderEffectSource {
        id: ebSrc
        width: eb.width; height: eb.height
        sourceItem: eb.target ? eb.target.contentItem : null
        sourceRect: eb.target ? Qt.rect(0, eb.atTop ? eb.target.contentY : eb.target.contentY + eb.target.height - eb.depth,
                                        eb.target.width, eb.depth) : Qt.rect(0, 0, 1, 1)
        live: true
        visible: false
    }
    Item {
        id: ebMask
        width: eb.width; height: eb.height
        visible: false
        layer.enabled: true
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: eb.atTop ? "black" : "transparent" }
                GradientStop { position: 1.0; color: eb.atTop ? "transparent" : "black" }
            }
        }
    }
    MultiEffect {
        anchors.fill: parent
        source: ebSrc
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: 32
        blur: 1.0
        maskEnabled: true
        maskSource: ebMask
    }
}
