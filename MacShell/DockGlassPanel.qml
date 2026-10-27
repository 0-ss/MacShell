import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "GlassShape.js" as GS

// The Dock's hover label and right-click menu: a macOS Tahoe style bubble made of heavily blurred Liquid Glass, with a pointer tail
// under it. One component for both, so they always look the same.
//
//   * live (Apple Liquid Glass Dock style): the wallpaper and windows behind the bubble (the same backdrop the Dock glass uses) are
//     captured, Gaussian-blurred very hard, saturated a little and cut to the bubble's outline; a light / dark tint, a specular rim
//     and a dark hairline go on top, and a soft shadow underneath.
//   * not live (Normal Blur Dock style, or the glass shader is unavailable): the same outline and rim with a firmer tint; the
//     compositor's own blur (which the Dock window already relies on) frosts what is behind it.
//
// Everything is sized from `k` (the Dock's size / 52), so the bubble grows and shrinks with the Dock.
//
// Put the content in the bubble as children: they are placed in a `width` x `bodyH` area (the tail hangs below it).
Item {
    id: gp

    property var backdrop: null          // the Dock's glass backdrop item (wallpaper + live windows, screen coordinates), or null
    property bool live: false            // true: blur the backdrop; false: plain tinted fill
    property bool dark: false            // appearance: dark or light glass
    property real k: 1                   // scale (Dock size / 52)
    property real radius: 16
    property real bodyH: 28              // body height; the whole item is bodyH + tailH tall
    property real tailW: 0               // tail width at the body edge, 0 = no tail
    property real tailH: 0
    property real tailTipR: 3
    property real tailX: width / 2       // centre of the tail along the body (clamped inside the corners by the outline itself)
    property real blurAmount: 0.85       // 0..1 of the 64 px blur kernel: "very blurred"

    default property alias content: body.data

    height: bodyH + tailH

    readonly property real m: 64         // backdrop captured around the bubble (blur reach)
    readonly property real sp: 48        // room around the bubble for the shadow
    readonly property real hp: 2         // room around the bubble for the hairline
    // where the bubble's top-left corner lies in the backdrop (kept up to date every frame while it can be seen: the hover label moves
    // with the magnified icon it belongs to)
    property real bx: 0
    property real by: 0
    // everything that changes the picture: any of these repaints the canvases
    readonly property string shapeKey: [width, bodyH, tailW, tailH, tailTipR, tailX, radius, dark, live, k].join("|")

    function syncPos() {
        if (!gp.backdrop) return;
        var p = gp.backdrop.mapFromItem(gp, 0, 0);
        if (Math.abs(p.x - gp.bx) > 0.01) gp.bx = p.x;
        if (Math.abs(p.y - gp.by) > 0.01) gp.by = p.y;
    }
    FrameAnimation {
        running: gp.live && gp.visible && gp.backdrop !== null
        onTriggered: gp.syncPos()
    }
    onVisibleChanged: if (visible) syncPos()
    Component.onCompleted: syncPos()

    // ── soft shadow: drawn once (only the part outside the bubble is kept) ──
    Canvas {
        id: shadowCv
        x: -gp.sp; y: -gp.sp
        width: gp.width + 2 * gp.sp
        height: gp.height + 2 * gp.sp
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            if (gp.width < 2 || gp.bodyH < 2) return;
            ctx.shadowColor = gp.dark ? "rgba(0,0,0,0.50)" : "rgba(0,0,0,0.26)";
            ctx.shadowBlur = 20 * gp.k;
            ctx.shadowOffsetX = 0;
            ctx.shadowOffsetY = 6 * gp.k;
            ctx.fillStyle = "#000000";
            GS.build(ctx, gp.sp, gp.sp, gp.width, gp.bodyH, gp.radius, gp.tailX, gp.tailW, gp.tailH, gp.tailTipR);
            ctx.fill();
            ctx.shadowColor = "rgba(0,0,0,0)";
            ctx.shadowBlur = 0;
            ctx.shadowOffsetY = 0;
            ctx.globalCompositeOperation = "destination-out";
            GS.build(ctx, gp.sp, gp.sp, gp.width, gp.bodyH, gp.radius, gp.tailX, gp.tailW, gp.tailH, gp.tailTipR);
            ctx.fill();
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections { target: gp; function onShapeKeyChanged() { shadowCv.requestPaint(); } }
        Component.onCompleted: requestPaint()
    }

    // ── the blurred backdrop, cut to the bubble's outline (only while live) ──
    Loader {
        id: blurLoader
        active: gp.live && gp.backdrop !== null
        x: -gp.m; y: -gp.m
        width: gp.width + 2 * gp.m
        height: gp.height + 2 * gp.m
        sourceComponent: Item {
            ShaderEffectSource {
                id: ses
                sourceItem: gp.backdrop
                sourceRect: Qt.rect(gp.bx - gp.m, gp.by - gp.m, gp.width + 2 * gp.m, gp.height + 2 * gp.m)
                live: gp.visible
                visible: false
            }
            // alpha mask in the bubble's shape (same idiom as the other masks in this shell: a hidden item with a layer)
            Shape {
                id: maskShape
                width: parent.width
                height: parent.height
                layer.enabled: true
                layer.samples: 4
                visible: false
                ShapePath {
                    fillColor: "#000000"
                    strokeColor: "transparent"
                    strokeWidth: -1
                    PathSvg { path: GS.svg(gp.m, gp.m, gp.width, gp.bodyH, gp.radius, gp.tailX, gp.tailW, gp.tailH, gp.tailTipR) }
                }
            }
            MultiEffect {
                anchors.fill: parent
                source: ses
                autoPaddingEnabled: false
                blurEnabled: true
                blurMax: 64
                blur: gp.blurAmount
                saturation: 0.30
                brightness: gp.dark ? -0.03 : 0.03
                maskEnabled: true
                maskSource: maskShape
            }
        }
    }

    // ── tint, specular rim, dark hairline ──
    Canvas {
        id: skin
        x: -gp.hp; y: -gp.hp
        width: gp.width + 2 * gp.hp
        height: gp.height + 2 * gp.hp
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var W = gp.width, H = gp.bodyH, pd = gp.hp, TH = gp.tailH;
            if (W < 2 || H < 2) return;
            function outline() { GS.build(ctx, pd, pd, W, H, gp.radius, gp.tailX, gp.tailW, TH, gp.tailTipR); }

            // 1 px dark line just outside the edge (the inside half is wiped again), so the bubble keeps its edge over a bright window
            outline();
            ctx.lineWidth = 2;
            ctx.strokeStyle = gp.dark ? "rgba(0,0,0,0.40)" : "rgba(0,0,0,0.13)";
            ctx.stroke();
            ctx.globalCompositeOperation = "destination-out";
            outline();
            ctx.fillStyle = "#000000";
            ctx.fill();
            ctx.globalCompositeOperation = "source-over";

            // tint over the blurred backdrop (a firmer one when there is no backdrop of our own to blur)
            var g = ctx.createLinearGradient(0, pd, 0, pd + H + TH);
            if (gp.dark) {
                g.addColorStop(0, gp.live ? "rgba(56,56,62,0.50)" : "rgba(54,54,59,0.78)");
                g.addColorStop(1, gp.live ? "rgba(30,30,34,0.58)" : "rgba(34,34,38,0.82)");
            } else {
                g.addColorStop(0, gp.live ? "rgba(255,255,255,0.44)" : "rgba(246,246,249,0.80)");
                g.addColorStop(1, gp.live ? "rgba(255,255,255,0.36)" : "rgba(236,236,241,0.84)");
            }
            outline();
            ctx.fillStyle = g;
            ctx.fill();

            // specular rim, inside the edge: bright along the top and bottom, only a whisper down the sides
            ctx.save();
            outline();
            ctx.clip();
            var rg = ctx.createLinearGradient(0, pd, 0, pd + H);
            if (gp.dark) {
                rg.addColorStop(0.00, "rgba(255,255,255,0.30)");
                rg.addColorStop(0.30, "rgba(255,255,255,0.10)");
                rg.addColorStop(0.70, "rgba(255,255,255,0.08)");
                rg.addColorStop(1.00, "rgba(255,255,255,0.18)");
            } else {
                rg.addColorStop(0.00, "rgba(255,255,255,0.55)");     // measured on a real Tahoe label: the top row is ~40% whiter than the fill
                rg.addColorStop(0.30, "rgba(255,255,255,0.18)");
                rg.addColorStop(0.70, "rgba(255,255,255,0.12)");
                rg.addColorStop(1.00, "rgba(255,255,255,0.22)");
            }
            outline();
            ctx.lineWidth = 2;
            ctx.strokeStyle = rg;
            ctx.stroke();
            ctx.restore();
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections { target: gp; function onShapeKeyChanged() { skin.requestPaint(); } }
        Component.onCompleted: requestPaint()
    }

    // ── content ──
    Item {
        id: body
        width: gp.width
        height: gp.bodyH
    }
}
