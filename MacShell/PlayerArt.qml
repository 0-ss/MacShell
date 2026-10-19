import QtQuick
import QtQuick.Effects
import QtMultimedia

Item {
    id: art
    required property var wd
    property real r: 7

    // ── animated video canvas (Spotify Canvas / Apple Music Motion) ──
    Loader {
        id: canvasLoader
        anchors.fill: parent
        active: art.wd && (art.wd.canvasVideo || "") !== "" && (art.wd.desktopCanvas !== false)
        visible: active && opacity > 0
        opacity: (art.wd && (art.wd.canvasVideo || "") !== "" && art.wd.playing && !art.wd.occluded) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        z: 3
        sourceComponent: Item {
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: Rectangle { width: art.width; height: art.height; radius: art.r; color: "black" }
            }
            readonly property bool shouldPlay: art.wd && art.wd.playing && !art.wd.occluded
            function syncAndPlay() {
                if (cMp.duration > 0 && art.wd && (art.wd.evalPos || 0) > 0) {
                    var songMs = Math.round(art.wd.evalPos * 1000);
                    cMp.position = songMs % cMp.duration;
                }
                cMp.play();
            }
            onShouldPlayChanged: {
                if (shouldPlay) syncAndPlay();
                else cMp.pause();
            }
            MediaPlayer {
                id: cMp
                source: art.wd && art.wd.canvasVideo ? ("file://" + art.wd.canvasVideo) : ""
                loops: MediaPlayer.Infinite
                videoOutput: cVo
                audioOutput: null
                onDurationChanged: {
                    if (duration > 0 && shouldPlay) syncAndPlay();
                }
                Component.onCompleted: {
                    if (shouldPlay) syncAndPlay();
                    else pause();
                }
                onSourceChanged: {
                    if (source !== "") {
                        if (shouldPlay) syncAndPlay();
                        else pause();
                    }
                }
            }
            VideoOutput {
                id: cVo
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectCrop
            }
        }
    }

    property int curIdx: 0
    property real prog: 1.0
    property real seed: 0
    property bool pending: false

    readonly property string currentUrl: String(art.wd.artSrc || "")

    onCurrentUrlChanged: {
        if (currentUrl === "") return;
        var cur = curIdx === 0 ? imgA : imgB;
        if (cur.source.toString() === currentUrl) return;
        var next = curIdx === 0 ? imgB : imgA;
        next.source = currentUrl;
        pending = true;
        burnWait.restart();
        tryStart();
    }

    function tryStart() {
        if (!pending) return;
        var next = curIdx === 0 ? imgB : imgA;
        if (next.status === Image.Loading && burnWait.running) return;
        pending = false;
        burnWait.stop();
        curIdx = 1 - curIdx;
        seed = Math.random();
        burnAnim.restart();
        if (art.wd && typeof art.wd.triggerSpread === "function") {
            art.wd.triggerSpread();
        }
    }

    Timer {
        id: burnWait
        interval: 1200
        onTriggered: art.tryStart()
    }

    NumberAnimation {
        id: burnAnim
        target: art
        property: "prog"
        from: 0
        to: 1
        duration: 950
        easing.type: Easing.OutCubic
    }

    Component.onCompleted: {
        if (currentUrl !== "") {
            imgA.source = currentUrl;
            curIdx = 0;
            prog = 1.0;
        }
    }

    // ── placeholder when no art ──
    Rectangle {
        anchors.fill: parent
        radius: art.r
        visible: art.currentUrl === "" || ((art.curIdx === 0 ? imgA : imgB).status !== Image.Ready && art.prog >= 1.0)
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.lighter(art.wd.ac, 1.25) }
            GradientStop { position: 1.0; color: Qt.darker(art.wd.ac, 1.25) }
        }
        Text {
            anchors.centerIn: parent
            text: "\u266B"
            color: Qt.rgba(1, 1, 1, 0.85)
            font.pixelSize: parent.height * 0.5
        }
    }

    // ── images & shader sources ──
    Image {
        id: imgA
        anchors.fill: parent
        visible: false
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        mipmap: true
        sourceSize.width: 400
        sourceSize.height: 400
        onStatusChanged: art.tryStart()
    }

    Image {
        id: imgB
        anchors.fill: parent
        visible: false
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        mipmap: true
        sourceSize.width: 400
        sourceSize.height: 400
        onStatusChanged: art.tryStart()
    }

    ShaderEffectSource {
        id: srcA
        sourceItem: imgA
        hideSource: true
        visible: false
        smooth: true
    }

    ShaderEffectSource {
        id: srcB
        sourceItem: imgB
        hideSource: true
        visible: false
        smooth: true
    }

    // ── burning paper cover transition shader ──
    ShaderEffect {
        anchors.fill: parent
        visible: art.currentUrl !== ""
        opacity: (art.curIdx === 0 ? imgA : imgB).status === Image.Ready || art.prog < 1.0 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 300 } }

        fragmentShader: Qt.resolvedUrl("burn.frag.qsb")
        property variant oldTex: art.curIdx === 0 ? srcB : srcA
        property variant newTex: art.curIdx === 0 ? srcA : srcB
        property real progress: art.prog
        property vector2d itemSize: Qt.vector2d(width, height)
        property real radius: art.r
        property real seed: art.seed
    }

    // hairline around the art
    Rectangle {
        anchors.fill: parent
        radius: art.r
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)
    }
}
