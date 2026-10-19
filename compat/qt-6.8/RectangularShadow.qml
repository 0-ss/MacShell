import QtQuick

// Compat para Qt < 6.9 (Debian 13 trae Qt 6.8): sustituye a QtQuick.Effects.RectangularShadow.
// Sombra de rectangulo redondeado hecha con capas concentricas translucidas (sin shaders).
// API compatible: radius, blur, spread, color, offset (vector2d, admite offset.y: ...).
Item {
    id: root

    property real radius: 0
    property real blur: 0
    property real spread: 0
    property color color: "black"
    property vector2d offset: Qt.vector2d(0, 0)

    readonly property int _layers: 14
    readonly property real _layerAlpha: 1 - Math.pow(1 - root.color.a, 1 / _layers)

    Item {
        x: root.offset.x
        y: root.offset.y
        width: root.width
        height: root.height

        Repeater {
            model: root._layers
            Rectangle {
                required property int index
                // distancia (px) que sobresale esta capa: mas densas cerca del borde
                readonly property real grow: root.spread + root.blur * Math.pow((index + 1) / root._layers, 0.65)
                x: -grow
                y: -grow
                width: root.width + 2 * grow
                height: root.height + 2 * grow
                radius: Math.max(0, root.radius + grow)
                color: Qt.rgba(root.color.r, root.color.g, root.color.b, root._layerAlpha)
                antialiasing: true
            }
        }
    }
}
