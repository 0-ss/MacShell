// One Liquid Glass slab (pill, card, button) that refracts the shared, pre-blurred lock screen backdrop.
// Same uniforms / tuning as MacShell's GGlass (MacBar.qml), so it looks like the bar's popovers.
import QtQuick

Item {
    id: gg
    property var src: null              // ShaderEffectSource with mipmaps: the blurred scene
    property Item frame: null           // coordinate space the backdrop texture covers (the whole screen)
    property url shaderUrl: Qt.resolvedUrl("liquidglass.frag.qsb")
    property real cornerR: 22
    property real thickness: 24
    property real strength: 1.0
    property real tint: 0.32
    property real rim: 0.5
    property real shadowAmt: 0.5
    property bool dark: true
    // The system material (Settings → Appearance) reaches the lock screen: Liquid Glass refracts, Frosted and Blur
    // are the same blurred backdrop without the refraction, Opaque is a solid card.
    property string material: "liquid"
    readonly property bool flat: material === "frosted" || material === "blur"
    readonly property bool solid: material === "opaque"
    readonly property real effThickness: flat ? 0 : thickness
    readonly property real effStrength: flat ? 0 : strength
    readonly property real effTint: solid ? 1 : (material === "frosted" ? Math.min(1, tint + 0.22) : (material === "blur" ? Math.min(1, tint + 0.08) : tint))
    readonly property real pad: 10
    readonly property bool failed: fx.status === ShaderEffect.Error

    // position inside `frame`; reads every ancestor's x/y so it follows animated parents
    function framePos() {
        var px = 0, py = 0, it = gg;
        while (it && it !== frame) { px += it.x; py += it.y; it = it.parent; }
        return Qt.point(px, py);
    }
    readonly property point fp: framePos()

    // flat fallback if the shader can't load
    Rectangle {
        visible: gg.solid
        anchors.fill: parent
        radius: gg.cornerR
        color: gg.dark ? Qt.rgba(0.11, 0.11, 0.12, 0.97) : Qt.rgba(0.98, 0.98, 0.99, 0.97)
        border.width: 1
        border.color: gg.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.1)
    }
    Rectangle {
        visible: (gg.failed || !gg.src) && !gg.solid
        anchors.fill: parent
        radius: gg.cornerR
        color: Qt.rgba(0.12, 0.12, 0.14, 0.45)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.18)
    }

    ShaderEffect {
        id: fx
        visible: gg.src !== null && gg.frame !== null && !gg.solid
        x: -gg.pad; y: -gg.pad
        width: gg.width + 2 * gg.pad
        height: gg.height + 2 * gg.pad
        fragmentShader: gg.shaderUrl
        onStatusChanged: if (status === ShaderEffect.Error) console.log("[maclock] glass shader:", log)
        property variant src: gg.src
        property vector2d itemSize: Qt.vector2d(width, height)
        property vector2d glassSize: Qt.vector2d(gg.width, gg.height)
        property vector2d srcSize: Qt.vector2d(gg.frame ? gg.frame.width : 1, gg.frame ? gg.frame.height : 1)
        property vector2d srcOffset: Qt.vector2d(gg.fp.x - gg.pad, gg.fp.y - gg.pad)
        property real pad: gg.pad
        property real radius: gg.cornerR
        property real bezel: Math.min(gg.height * 0.36, 26)
        property real thickness: gg.effThickness * gg.effStrength * 1.6
        property real dispersion: 0.06 * gg.effStrength * 1.3
        property real magnify: 0.05 * gg.effStrength * 1.6
        property real rim: gg.flat ? gg.rim * 0.4 : gg.rim
        property real grain: 0.006
        property real blurPx: 1.5
        property real tintMix: gg.effTint * 0.55
        property real saturation: 1.25
        property real dark: gg.dark ? 1 : 0
        property real debug: 0
        property real shadowAmt: gg.shadowAmt
    }
}
