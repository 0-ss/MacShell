import QtQuick
import QtQuick.Effects

Item {
    id: it
    property string source: ""
    property real iconScale: 1.0
    property real corner: 0.245
    property real power: 2.0
    property real edge: 2.0
    property real rim: 1.0
    property bool tint: false
    property real tintStrength: 0.0
    property color tintColor: "white"

    readonly property real artSize: Math.max(1, Math.round(width * iconScale))
    readonly property real tile: artSize - 2 * Math.round(artSize * 0.0975) + 2
    readonly property vector4d radii: Qt.vector4d(corner, corner, corner, corner)

    Image {
        id: img
        anchors.centerIn: parent
        width: it.artSize
        height: it.artSize
        visible: false
        source: it.source
        sourceSize: Qt.size(96, 96)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
    }
    IconClass {
        id: cls
        source: img.source.toString()
        corner: it.corner
        power: it.power
    }
    MultiEffect {
        id: artFx
        source: img
        anchors.fill: img
        saturation: it.tint ? -0.75 * it.tintStrength : 0.0
        colorization: it.tint ? it.tintStrength : 0.0
        brightness: it.tint ? 0.14 * it.tintStrength : 0.0
        contrast: it.tint ? 0.04 * it.tintStrength : 0.0
        colorizationColor: it.tintColor
    }
    Rectangle {
        id: tileFill
        width: it.tile
        height: width
        color: cls.dom
        visible: false
        layer.enabled: true
    }
    MultiEffect {
        id: fillFx
        source: tileFill
        width: tileFill.width
        height: width
        saturation: it.tint ? -0.75 * it.tintStrength : 0.0
        colorization: it.tint ? it.tintStrength : 0.0
        brightness: it.tint ? 0.14 * it.tintStrength : 0.0
        contrast: it.tint ? 0.04 * it.tintStrength : 0.0
        colorizationColor: it.tintColor
    }
    ShaderEffectSource {
        id: fillTex
        sourceItem: fillFx
        hideSource: true
        live: true
        visible: false
    }
    ShaderEffectSource {
        id: artTex
        sourceItem: artFx
        hideSource: true
        live: true
        smooth: true
        mipmap: true
        visible: false
    }
    ShaderEffect {
        anchors.centerIn: img
        width: it.tile
        height: width
        z: 0
        property variant source: fillTex
        property vector2d itemSize: Qt.vector2d(width, height)
        property real power: it.power
        property real box: 1.0
        property real soft: it.edge
        property real fillCorner: 0.0
        property vector4d radii: it.radii
        fragmentShader: Qt.resolvedUrl("iconclip.frag.qsb")
    }
    ShaderEffect {
        anchors.fill: img
        z: 1
        scale: ((cls.proper || cls.square) ? it.tile / img.width : 0.66 * cls.fit) / norm
        property variant source: artTex
        property vector2d itemSize: Qt.vector2d(width, height)
        property real power: it.power
        property real norm: cls.art >= 0.8 ? cls.art : (cls.proper ? 0.88 : 1.0)
        property real box: (cls.proper || cls.square) ? norm : 2.0
        property real soft: it.edge
        property real fillCorner: cls.proper ? 1.0 : 0.0
        property vector4d radii: it.radii
        fragmentShader: Qt.resolvedUrl("iconclip.frag.qsb")
    }
    ShaderEffect {
        anchors.centerIn: img
        width: it.tile
        height: width
        z: 2
        property vector2d itemSize: Qt.vector2d(width, height)
        property real power: it.power
        property vector4d radii: it.radii
        property real strength: it.rim
        property real soft: it.edge
        fragmentShader: Qt.resolvedUrl("iconrim.frag.qsb")
    }
}
