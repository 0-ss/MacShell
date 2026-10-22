// What one monitor shows while locked. The primary monitor gets the full macOS layout (clock, Now Playing,
// avatar + password); the others show the wallpaper and the clock only, but still forward typing.
import QtQuick
import QtQuick.Effects
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import "I18n.js" as I18n

Item {
    id: ls
    required property var st            // shared lock state (shell.qml)
    property bool isPrimary: true
    property bool shown: false          // entrance animation done / running
    readonly property real u: Math.max(0.6, height / 1200)   // layout unit, 1.0 on a 1200 px tall screen
    // UI font: Open Runde (bundled in fonts/, loaded by shell.qml)
    readonly property string fam: "Open Runde"
    readonly property string famDisplay: fam
    readonly property bool leaving: st.unlocking

    focus: true

    // ── entrance: start once the wallpaper is decoded (or after a short timeout), so it never fades in from black
    Timer { id: showTimer; interval: 450; running: true; onTriggered: ls.shown = true }
    Connections {
        target: wall
        function onStatusChanged() { if (wall.status === Image.Ready || wall.status === Image.Error) ls.shown = true; }
    }

    // whole screen fades in over the (xray) desktop and back out on unlock
    opacity: shown && !leaving ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: ls.leaving ? 420 : 650; easing.type: Easing.OutQuint } }

    // ═════════════ BACKDROP ═════════════
    Rectangle { anchors.fill: parent; color: "#0b0b10" }

    Item {
        id: scene
        anchors.fill: parent
        Image {
            id: wall
            anchors.fill: parent
            source: ls.st.wallpaper !== "" ? "file://" + ls.st.wallpaper : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            smooth: true
            // A 2.5K decode is plenty for a blurred full-screen background and avoids decoding huge 4K/8K originals.
            sourceSize.width: Math.max(1, Math.min(ls.width * 1.15, 2560))
            // slow settle-in zoom, and a gentle zoom-out as the lock lifts
            scale: ls.leaving ? 1.06 : (ls.shown ? 1.0 : 1.09)
            Behavior on scale { NumberAnimation { duration: ls.leaving ? 520 : 650; easing.type: Easing.OutQuint } }
        }
        // animated wallpaper: the same video MacShell plays on the desktop, muted and looping
        Loader {
            id: wallVideo
            anchors.fill: wall
            scale: wall.scale
            active: ls.st.wallpaperVideo !== ""
            sourceComponent: Item {
                MediaPlayer {
                    source: "file://" + ls.st.wallpaperVideo
                    loops: MediaPlayer.Infinite
                    videoOutput: vo
                    Component.onCompleted: play()
                }
                VideoOutput { id: vo; anchors.fill: parent; fillMode: VideoOutput.PreserveAspectCrop }
            }
        }
        // the wallpaper softens (no darkening) while you are entering the password
        MultiEffect {
            source: wallVideo.active ? wallVideo : wall
            anchors.fill: wall
            scale: wall.scale
            blurEnabled: true
            blurMax: 48
            blur: ls.st.engaged ? 0.55 : 0.0
            opacity: ls.st.engaged ? 1 : 0
            visible: opacity > 0.002
            Behavior on blur { NumberAnimation { duration: 650; easing.type: Easing.OutQuint } }
            Behavior on opacity { NumberAnimation { duration: 650; easing.type: Easing.OutQuint } }
        }
        // Album background: while the cover is enlarged the wallpaper gives way to a heavily blurred, slightly
        // darkened copy of the artwork (Apple Music full-screen player). Part of the scene, so the glass refracts it.
        Item {
            id: artBg
            anchors.fill: parent
            opacity: ls.st.artBg ? ls.clamp01(ls.artT) : 0
            visible: opacity > 0.003
            Rectangle { anchors.fill: parent; color: "#0c0c10" }

            // Animated Canvas Video (Spotify supported music)
            Loader {
                id: canvasLoader
                anchors.fill: parent
                active: ls.canvasVideo !== "" && ls.artT > 0.01
                sourceComponent: Item {
                    anchors.fill: parent
                    MediaPlayer {
                        id: canvasMp
                        source: "file://" + ls.canvasVideo
                        loops: MediaPlayer.Infinite
                        videoOutput: canvasVo
                        Component.onCompleted: play()
                    }
                    VideoOutput {
                        id: canvasVo
                        anchors.fill: parent
                        fillMode: VideoOutput.PreserveAspectCrop
                    }
                }
            }
            MultiEffect {
                anchors.fill: parent
                source: canvasLoader.active ? canvasLoader : null
                visible: canvasLoader.active
                scale: 1.15
                blurEnabled: true; blurMax: 48; blur: 0.55
                saturation: 0.35
                brightness: -0.15
            }

            // old and new album, each blurred; the new one fades in over the old one during a hand-over
            Repeater {
                model: canvasLoader.active ? 0 : 2
                delegate: MultiEffect {
                    required property int index
                    readonly property Item img: index === 0 ? ls.coverOld : ls.coverNew
                    anchors.fill: parent
                    scale: 1.25                            // pushes the blur's soft edges off-screen
                    source: img
                    autoPaddingEnabled: false
                    blurEnabled: true; blurMax: 64; blur: 1.0
                    saturation: 0.25
                    brightness: -0.16
                    // new: fades in with the hand-over; old: only there while it's being covered
                    opacity: index === 1 ? ls.bgProg : (ls.bgProg < 1 ? 1 : 0)
                    visible: img.status === Image.Ready && opacity > 0.003
                    z: index
                }
            }
        }
        // top/bottom vignette so white text always reads, like the macOS lock screen
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.22) }
                GradientStop { position: 0.35; color: Qt.rgba(0, 0, 0, 0.0) }
                GradientStop { position: 0.72; color: Qt.rgba(0, 0, 0, 0.0) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.30) }
            }
        }
    }

    // shared, pre-blurred copy of the scene that every glass slab (and the clock) refracts
    ShaderEffectSource {
        id: sceneTex
        sourceItem: scene
        // with a video wallpaper the scene changes every frame: the glass copy refreshes at 12 fps instead
        // (blur + every glass shader re-running 30-60x a second was the main GPU cost on the lock screen)
        live: !wallVideo.active && !canvasLoader.active
        visible: false
        textureSize: Qt.size(Math.max(1, Math.round(ls.width / 2)), Math.max(1, Math.round(ls.height / 2)))
    }
    Timer {
        interval: 83; repeat: true
        running: (wallVideo.active || canvasLoader.active) && ls.shown && !ls.leaving
        onTriggered: sceneTex.scheduleUpdate()
    }
    MultiEffect {
        id: sceneBlurFx
        source: sceneTex
        width: sceneTex.textureSize.width; height: sceneTex.textureSize.height
        blurEnabled: true
        blurMax: 32
        blur: 0.35
        autoPaddingEnabled: false
        visible: false
    }
    ShaderEffectSource {
        id: glassTex
        sourceItem: sceneBlurFx
        live: true
        mipmap: true
        visible: false
    }

    // ═════════════ STATUS (top right) ═════════════
    Row {
        visible: ls.isPrimary
        anchors.top: parent.top; anchors.right: parent.right
        anchors.topMargin: 14 * ls.u; anchors.rightMargin: 22 * ls.u
        spacing: 12 * ls.u
        opacity: ls.shown && !ls.leaving ? 0.95 : 0
        Behavior on opacity { NumberAnimation { duration: 650; easing.type: Easing.OutQuint } }

        Glyph {
            anchors.verticalCenter: parent.verticalCenter
            visible: ls.st.ethernet && ls.st.wifiLevel <= 0
            width: 18 * ls.u; height: 18 * ls.u
            kind: "ethernet"
            color: "white"
        }
        Glyph {
            anchors.verticalCenter: parent.verticalCenter
            visible: ls.st.wifiLevel > 0 || (ls.st.wifiLevel === 0 && !ls.st.ethernet)
            width: 18 * ls.u; height: 18 * ls.u
            kind: "wifi"; level: Math.max(0, ls.st.wifiLevel); flag: ls.st.wifiLevel === 0
            color: "white"
        }
        Row {
            visible: UPower.displayDevice && UPower.displayDevice.isPresent
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6 * ls.u
            readonly property real pct: {
                var d = UPower.displayDevice;
                if (!d) return 0;
                return Math.round(d.percentage <= 1.0 ? d.percentage * 100 : d.percentage);
            }
            readonly property bool charging: UPower.displayDevice
                && (UPower.displayDevice.state === UPowerDeviceState.Charging || UPower.displayDevice.state === UPowerDeviceState.FullyCharged)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: parent.pct + "%"
                color: "white"; font.family: ls.fam; font.pixelSize: 13 * ls.u; font.weight: Font.Medium
            }
            // macOS battery: rounded outline, fill, little cap
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 27 * ls.u; height: 13 * ls.u
                Rectangle {
                    id: batBody
                    width: parent.width - 3 * ls.u; height: parent.height
                    radius: 4 * ls.u
                    color: "transparent"
                    border.width: 1.2; border.color: Qt.rgba(1, 1, 1, 0.55)
                    Rectangle {
                        x: 2 * ls.u; y: 2 * ls.u
                        height: parent.height - 4 * ls.u
                        width: Math.max(2, (parent.width - 4 * ls.u) * parent.parent.parent.pct / 100)
                        radius: 2 * ls.u
                        color: parent.parent.parent.charging ? "#34c759" : (parent.parent.parent.pct <= 20 ? "#ff453a" : "white")
                    }
                }
                Rectangle {
                    x: batBody.width + 1 * ls.u; anchors.verticalCenter: batBody.verticalCenter
                    width: 1.6 * ls.u; height: 4.5 * ls.u; radius: 1
                    color: Qt.rgba(1, 1, 1, 0.55)
                }
            }
        }
    }

    // ═════════════ NOTIFICATIONS + LIVE ACTIVITY (top right, under the status) ═════════════
    // Notifications are hidden like macOS ("Show previews: When Unlocked"): app icon, app name, "Notification", time.
    // Clicking one asks for the password: the field glows and fades (1 s). MacShell writes the list.
    FileView {
        id: notifFile
        path: Quickshell.env("HOME") + "/.cache/macshell/lock-notifs.json"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
    }
    readonly property var lockNotifs: { try { return notifFile.loaded ? JSON.parse(notifFile.text()) : []; } catch (e) { return []; } }
    // the cards live in a keyed ListModel updated in place: clearing one doesn't rebuild (and re-fade) the others
    ListModel { id: lnModel }
    onLockNotifsChanged: {
        var want = lockNotifs.slice(0, 4), i, j, k;
        for (i = lnModel.count - 1; i >= 0; i--) {
            var keep = false;
            for (j = 0; j < want.length; j++) if (want[j].id === lnModel.get(i).nid) keep = true;
            if (!keep) lnModel.remove(i);
        }
        for (i = 0; i < want.length; i++) {
            var at = -1;
            for (k = 0; k < lnModel.count; k++) if (lnModel.get(k).nid === want[i].id) { at = k; break; }
            var row = { nid: want[i].id, app: want[i].app || "", icon: want[i].icon || "", time: want[i].time || 0 };
            if (at < 0) lnModel.insert(i, row);
            else if (at !== i) lnModel.move(at, i, 1);
        }
    }
    // Clock app state: a running timer / stopwatch, or an alarm ringing
    FileView {
        id: clockFile
        path: Quickshell.env("HOME") + "/.config/macshell/clock.json"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
    }
    readonly property var clockSt: { try { return clockFile.loaded ? JSON.parse(clockFile.text()) : null; } catch (e) { return null; } }
    property real nowMs: Date.now()
    Timer { interval: 250; repeat: true; running: ls.liveKind !== ""; onTriggered: ls.nowMs = Date.now() }
    readonly property string liveKind: !clockSt ? "" : (clockSt.ringing ? "ring" : ((clockSt.timer && clockSt.timer.state && clockSt.timer.state !== "idle") ? "timer"
                                       : ((clockSt.sw && (clockSt.sw.running || clockSt.sw.acc > 0)) ? "sw" : "")))
    function pad2(n) { return (n < 10 ? "0" : "") + n; }
    function fmtDur(ms) { var s = Math.ceil(ms / 1000), h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60); return (h > 0 ? h + ":" + pad2(m) : pad2(m)) + ":" + pad2(s % 60); }
    function notifAge(t) {
        var d = Math.floor((nowMs2 - t) / 60000);
        if (d < 1) return "now";
        if (d < 60) return d + "m ago";
        var dt = new Date(t);
        return ls.st.use24h ? pad2(dt.getHours()) + ":" + pad2(dt.getMinutes()) : Qt.formatTime(dt, "h:mm AP");
    }
    property real nowMs2: Date.now()
    Timer { interval: 30000; repeat: true; running: ls.lockNotifs.length > 0; onTriggered: ls.nowMs2 = Date.now() }
    function askPassword() { ls.forceActiveFocus(); ls.st.poke(); pwPulse.restart(); }

    Column {
        id: rightCol
        visible: ls.isPrimary
        anchors.right: parent.right; anchors.rightMargin: 18 * ls.u
        y: 48 * ls.u
        width: 340 * ls.u
        spacing: 8 * ls.u
        // cards below a cleared one glide up into its place
        move: Transition { NumberAnimation { properties: "y"; duration: 420; easing.type: Easing.OutQuint } }
        opacity: ls.shown && !ls.leaving ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 650; easing.type: Easing.OutQuint } }

        // live activity
        Item {
            id: liveCard
            width: parent.width
            readonly property bool on: ls.liveKind !== ""
            height: on ? (ls.liveKind === "ring" ? 110 : 76) * ls.u : 0
            opacity: on ? 1 : 0
            visible: opacity > 0.01
            Behavior on height { NumberAnimation { duration: 420; easing.type: Easing.OutQuint } }
            Behavior on opacity { NumberAnimation { duration: 320 } }
            clip: true
            Glass { anchors.fill: parent; src: glassTex; frame: ls; cornerR: 22 * ls.u; thickness: 20; tint: 0.42; shadowAmt: 0.35 }
            readonly property var tm: ls.clockSt ? ls.clockSt.timer : null
            readonly property real remain: !tm ? 0 : (tm.state === "running" ? Math.max(0, tm.endAt - ls.nowMs) : tm.left)
            readonly property real swMs: (ls.clockSt && ls.clockSt.sw) ? ls.clockSt.sw.acc + (ls.clockSt.sw.running ? ls.nowMs - ls.clockSt.sw.startAt : 0) : 0
            // timer ring / stopwatch glyph
            Canvas {
                id: liveRing
                x: 16 * ls.u; y: 14 * ls.u
                width: 48 * ls.u; height: width
                property real f: ls.liveKind === "timer" && liveCard.tm && liveCard.tm.total > 0 ? liveCard.remain / liveCard.tm.total : 1
                onFChanged: requestPaint()
                onPaint: {
                    var c = getContext("2d"); c.reset();
                    var lw = 4.5 * ls.u, r = width / 2 - lw / 2;
                    c.lineWidth = lw; c.lineCap = "round";
                    c.strokeStyle = Qt.rgba(1, 1, 1, 0.22); c.beginPath(); c.arc(width / 2, height / 2, r, 0, Math.PI * 2); c.stroke();
                    c.strokeStyle = "#FF9F0A"; c.beginPath(); c.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0.0001, f)); c.stroke();
                }
                ClockGlyph { anchors.centerIn: parent; visible: ls.liveKind === "sw" || ls.liveKind === "ring"; kind: ls.liveKind === "sw" ? "stopwatch" : "alarm"; color: "white"; width: 22 * ls.u; height: width }
            }
            Column {
                x: 78 * ls.u; y: 14 * ls.u
                width: parent.width - x - 16 * ls.u
                Text {
                    text: ls.liveKind === "timer" && liveCard.tm ? (liveCard.tm.label || I18n.tr("Timer")) + (liveCard.tm.state === "paused" ? I18n.tr(" · Paused") : "")
                        : (ls.liveKind === "sw" ? "Stopwatch" : (ls.liveKind === "ring" && ls.clockSt.ringing ? (ls.clockSt.ringing.kind === "timer" ? "Timer" : "Alarm") : ""))
                    color: "#FF9F0A"; font.family: ls.fam; font.pixelSize: 13 * ls.u; font.weight: Font.DemiBold
                }
                Text {
                    text: ls.liveKind === "timer" && liveCard.tm ? ls.fmtDur(liveCard.remain)
                        : (ls.liveKind === "sw" ? ls.fmtDur(liveCard.swMs).replace(/^(\d\d:\d\d)$/, "$1")
                        : (ls.liveKind === "ring" && ls.clockSt.ringing ? (ls.clockSt.ringing.kind === "timer" ? "Done" : ls.clockSt.ringing.time) : ""))
                    color: "white"; font.family: ls.fam; font.pixelSize: 30 * ls.u; font.weight: Font.Medium
                    font.features: { "tnum": 1 }
                }
            }
            // ringing: Stop / Snooze right here (MacShell does the stopping)
            Row {
                visible: ls.liveKind === "ring"
                x: 16 * ls.u; anchors.bottom: parent.bottom; anchors.bottomMargin: 12 * ls.u
                spacing: 8 * ls.u
                Repeater {
                    model: ls.liveKind === "ring" ? (ls.clockSt.ringing.kind === "timer" ? ["Stop"] : ["Snooze", "Stop"]) : []
                    delegate: Rectangle {
                        required property string modelData
                        width: (liveCard.width - 40 * ls.u) / (ls.clockSt.ringing.kind === "timer" ? 1 : 2); height: 30 * ls.u; radius: height / 2
                        color: modelData === "Stop" ? "#FF9F0A" : Qt.rgba(1, 1, 1, ringBtn.pressed ? 0.32 : 0.2)
                        Text { anchors.centerIn: parent; text: parent.modelData; color: parent.modelData === "Stop" ? "black" : "white"; font.family: ls.fam; font.pixelSize: 13 * ls.u; font.weight: Font.DemiBold }
                        MouseArea { id: ringBtn; anchors.fill: parent; onClicked: Quickshell.execDetached(["qs", "-c", "MacShell", "ipc", "call", "clock", parent.modelData === "Stop" ? "stop" : "snooze"]) }
                    }
                }
            }
        }

        // notifications (newest first; past four they stack, like macOS)
        Repeater {
            model: lnModel
            delegate: Item {
                id: nc
                required property int nid
                required property string app
                required property string icon
                required property real time
                required property int index
                width: rightCol.width
                // a swiped card folds its slot away so the ones below glide up
                height: (gone ? 0 : 62 * ls.u)
                Behavior on height { NumberAnimation { duration: 380; easing.type: Easing.OutQuint } }
                property real appear: 0
                Component.onCompleted: appearAnim.start()
                NumberAnimation { id: appearAnim; target: nc; property: "appear"; from: 0; to: 1; duration: 560; easing.type: Easing.OutQuint }
                // swipe sideways to clear: the card follows the pointer and fades with distance; past a third of its
                // width (or flicked) it flies off and MacShell dismisses it, otherwise it springs back
                property real dragX: 0
                property bool gone: false
                readonly property real far: Math.min(1, Math.abs(dragX) / (width * 0.75))
                opacity: appear * (1 - far)
                transform: Translate { x: (1 - nc.appear) * 40 * ls.u + nc.dragX }
                NumberAnimation { id: snapBack; target: nc; property: "dragX"; to: 0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                SequentialAnimation {
                    id: flyOff
                    property real to: 0
                    NumberAnimation { target: nc; property: "dragX"; to: flyOff.to; duration: 260; easing.type: Easing.OutCubic }
                    ScriptAction { script: { nc.gone = true; Quickshell.execDetached(["qs", "-c", "MacShell", "ipc", "call", "notifications", "dismiss", String(nc.nid)]); } }
                }

                Glass { anchors.fill: parent; src: glassTex; frame: ls; cornerR: 20 * ls.u; thickness: 20; tint: 0.40; shadowAmt: 0.3 }
                Rectangle { anchors.fill: parent; radius: 20 * ls.u; color: "white"; opacity: ncMa.pressed ? 0.12 : (ncMa.containsMouse ? 0.06 : 0); Behavior on opacity { NumberAnimation { duration: 140 } } }
                Image {
                    x: 14 * ls.u; anchors.verticalCenter: parent.verticalCenter
                    width: 34 * ls.u; height: width
                    // apps without an icon (MacShell's own, notify-send…) get the system notifications icon
                    source: nc.icon && status !== Image.Error ? nc.icon : "image://icon/preferences-system-notifications"
                    sourceSize: Qt.size(96, 96)
                    smooth: true; mipmap: true
                }
                Column {
                    x: 60 * ls.u; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - 70 * ls.u
                    Text { width: parent.width; elide: Text.ElideRight; text: nc.app; color: "white"; font.family: ls.fam; font.pixelSize: 14 * ls.u; font.weight: Font.DemiBold }
                    Text { text: I18n.tr("Notification"); color: Qt.rgba(1, 1, 1, 0.72); font.family: ls.fam; font.pixelSize: 13 * ls.u }
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 14 * ls.u; y: 13 * ls.u
                    text: ls.notifAge(nc.time); color: Qt.rgba(1, 1, 1, 0.6); font.family: ls.fam; font.pixelSize: 12 * ls.u
                }
                // one MouseArea for tap AND swipe: it keeps the pointer for the whole drag (preventStealing), and the card
                // is only cleared when the button is actually released — an interrupted drag springs back
                MouseArea {
                    id: ncMa
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                    // screen coordinates: the card itself moves under the pointer
                    property real pressSX: 0
                    property real startDX: 0
                    property real lastSX: 0
                    property real lastT: 0
                    property real vx: 0
                    property bool dragging: false
                    function sx(mouse) { return ncMa.mapToItem(ls, mouse.x, mouse.y).x; }
                    onPressed: mouse => { snapBack.stop(); pressSX = sx(mouse); lastSX = pressSX; startDX = nc.dragX; lastT = Date.now(); vx = 0; dragging = false; }
                    onPositionChanged: mouse => {
                        if (!pressed) return;
                        var x = sx(mouse);
                        if (!dragging && Math.abs(x - pressSX) > 6) { dragging = true; ls.st.poke(); }
                        if (!dragging) return;
                        nc.dragX = startDX + (x - pressSX);
                        var t = Date.now(), dt = Math.max(1, t - lastT);
                        vx = 0.7 * vx + 0.3 * ((x - lastSX) / dt * 1000);
                        lastSX = x; lastT = t;
                    }
                    onReleased: {
                        if (!dragging) return;
                        dragging = false;
                        if (Math.abs(nc.dragX) > nc.width / 3 || Math.abs(vx) > 900) {
                            var dir = (Math.abs(vx) > 900 ? vx : nc.dragX) > 0 ? 1 : -1;
                            flyOff.to = dir * (nc.width + 60 * ls.u); flyOff.restart();
                        } else snapBack.restart();
                    }
                    onCanceled: { dragging = false; snapBack.restart(); }
                    onClicked: if (Math.abs(nc.dragX) < 2) ls.askPassword()
                }
            }
        }
        // "+N more": the rest, stacked under the last card
        Item {
            visible: ls.lockNotifs.length > 4
            width: parent.width; height: 26 * ls.u
            Text {
                anchors.horizontalCenter: parent.horizontalCenter; anchors.verticalCenter: parent.verticalCenter
                text: (ls.lockNotifs.length - 4) + I18n.tr(" more notification") + (ls.lockNotifs.length - 4 === 1 ? "" : "s")
                color: Qt.rgba(1, 1, 1, 0.75); font.family: ls.fam; font.pixelSize: 12 * ls.u; font.weight: Font.Medium
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ls.askPassword() }
        }
    }

    // ═════════════ CLOCK ═════════════
    Item {
        id: clock
        anchors.horizontalCenter: parent.horizontalCenter
        y: (ls.shown && !ls.leaving ? 0.075 : 0.035) * ls.height
        width: Math.max(dateTxt.implicitWidth, timeItem.width)
        // repel: the bubble pressing up into the clock pushes it up and squashes it against the top
        transform: [
            Translate {
                y: -ls.pressTop * 0.45
                Behavior on y { enabled: !media.dragging; NumberAnimation { duration: 650; easing.type: Easing.OutQuint } }
            },
            Scale {
                origin.x: clock.width / 2; origin.y: 0
                xScale: 1 + 0.06 * ls.squishK(ls.pressTop)
                yScale: 1 - 0.14 * ls.squishK(ls.pressTop)
                Behavior on xScale { enabled: !media.dragging; NumberAnimation { duration: 650; easing.type: Easing.OutQuint } }
                Behavior on yScale { enabled: !media.dragging; NumberAnimation { duration: 650; easing.type: Easing.OutQuint } }
            }
        ]
        height: dateTxt.implicitHeight + timeItem.y - dateTxt.height + timeItem.height
        opacity: ls.shown && !ls.leaving ? 1 : 0
        Behavior on y { NumberAnimation { duration: ls.leaving ? 420 : 650; easing.type: Easing.OutQuint } }
        Behavior on opacity { NumberAnimation { duration: ls.leaving ? 300 : 650; easing.type: Easing.OutQuint } }

        MorphText {
            id: dateTxt
            horizontalAlignment: Text.AlignHCenter
            renderType: Text.NativeRendering
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.locale().toString(ls.st.now, ls.ckShortDate ? I18n.tr("ddd MMM d") : I18n.tr("dddd, MMMM d"))
            color: Qt.rgba(1, 1, 1, 0.92)
            font.family: ls.ckFont === "serif" && ls.ckFontOk ? "Noto Serif Display" : ls.fam
            font.pixelSize: (ls.ckShortDate ? 23 : 25) * ls.u; font.weight: Font.DemiBold
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.6; shadowOpacity: 0.25; shadowVerticalOffset: 1 }
        }

        // big translucent glass clock: the text is a mask, glasstext.frag refracts the wallpaper through it
        Item {
            id: timeItem
            anchors.top: dateTxt.bottom
            anchors.topMargin: -14 * ls.u
            anchors.horizontalCenter: parent.horizontalCenter
            width: timeTxt.implicitWidth + 40
            height: timeTxt.implicitHeight
            // room captured around the digits: the morph scales / realigns a little past the text box, and the glass
            // refracts past its edges — without it the clock got cropped mid-animation
            readonly property real mp: Math.max(48 * ls.u, ls.clockPx * 0.5)
            // the digits morph into each new minute (fade + slight scale) …
            MorphText {
                id: timeTxt
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                duration: 560
                useBlur: false              // no effect INSIDE the glass's hidden source (that made the clock vanish)
                animateWidth: false         // box snaps to the new width; the digits stay centred through the morph
                stretch: false
                scaleIn: 1.03; scaleOut: 0.97
                // 12- or 24-hour, as set in MacShell (no AM/PM, like the macOS / iOS lock screen)
                // (Qt's "h" only goes 12-hour together with AP, so the hour is computed here)
                text: ls.st.use24h ? Qt.formatTime(ls.st.now, I18n.tr("H:mm")) : ((ls.st.now.getHours() % 12) || 12) + Qt.formatTime(ls.st.now, ":mm")
                color: "white"
                font.family: ls.ckFamily; font.pixelSize: ls.clockPx; font.weight: Font.Bold
                font.variableAxes: ({ "wght": ls.clockWght })
                font.letterSpacing: (ls.ckWeight < 330 ? 0 : -1.5) * ls.u
                renderType: Text.QtRendering
                visible: false
            }
            ShaderEffectSource {
                id: timeMaskRaw
                sourceItem: timeTxt; hideSource: true; visible: false; smooth: true
                sourceRect: Qt.rect(-timeItem.mp, -timeItem.mp, timeTxt.width + 2 * timeItem.mp, timeTxt.height + 2 * timeItem.mp)
            }
            // … and the glass digits go soft and come back into focus while that happens (blur + morph)
            MultiEffect {
                id: timeMaskFx
                width: timeMaskRaw.sourceRect.width; height: timeMaskRaw.sourceRect.height
                source: timeMaskRaw
                blurEnabled: true; blurMax: 48; blur: timeTxt.morphBlur
                autoPaddingEnabled: false
                visible: false
            }
            ShaderEffectSource { id: timeMask; sourceItem: timeMaskFx; visible: false; smooth: true }
            // a LIGHTLY blurred copy of the digits: only used to find the thin glass rim along the edges
            MultiEffect {
                id: timeHeightFx
                width: timeMaskFx.width; height: timeMaskFx.height
                source: timeMask
                // the rim is a fixed share of the digit size (thin weights get a finer one)
                blurEnabled: true; blurMax: 16
                blur: Math.max(0.12, Math.min(0.6, ls.clockPx * (ls.ckWeight < 330 ? 0.02 : 0.04) / 16))
                autoPaddingEnabled: false
                visible: false
            }
            ShaderEffectSource { id: timeHeight; sourceItem: timeHeightFx; visible: false; smooth: true }
            // soft shadow under the glass digits so they lift off light wallpapers too
            MultiEffect {
                x: timeTxt.x - timeItem.mp; y: timeTxt.y - timeItem.mp + 8 * ls.u
                width: timeMaskFx.width; height: timeMaskFx.height
                source: timeMask
                blurEnabled: true; blurMax: 64; blur: 1.0
                colorization: 1.0; colorizationColor: "black"; brightness: -1.0
                opacity: ls.ckGlass ? 0.22 : 0.12
                Behavior on opacity { NumberAnimation { duration: 500 } }
            }
            ShaderEffect {
                id: timeGlass
                x: timeTxt.x - timeItem.mp; y: timeTxt.y - timeItem.mp
                width: timeMaskFx.width; height: timeMaskFx.height
                fragmentShader: Qt.resolvedUrl("glasstext.frag.qsb")
                // where the glass really is on screen (follows the clock's animations)
                readonly property point fp: { ls.clockPx; clock.y; clock.x; timeItem.x; timeTxt.x; timeTxt.width; return timeGlass.mapToItem(ls, 0, 0); }
                property variant src: glassTex
                property variant mask: timeMask
                property variant hmap: timeHeight
                property vector2d itemSize: Qt.vector2d(width, height)
                property vector2d srcSize: Qt.vector2d(ls.width, ls.height)
                property vector2d srcOffset: Qt.vector2d(fp.x, fp.y)
                // Apple's two clock materials (Settings → Lock Screen → Clock): Solid = vibrancy, Glass = Liquid Glass
                property real mode: ls.ckGlass ? 1 : 0
                property real intensity: ls.ckGlass ? ls.ckIntensity : 0.55 + 0.4 * ls.ckIntensity
                property real refract: (6 + 4 * (1 - ls.ckIntensity)) * ls.u
                property real bevel: 4.5
                property color tint: ls.ckTint
                property vector2d lightDir: Qt.vector2d(ls.lightX, ls.lightY)
                Behavior on mode { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                Behavior on intensity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                Behavior on tint { ColorAnimation { duration: 500 } }
                onStatusChanged: if (status === ShaderEffect.Error) console.log("[maclock] clock shader:", log)
            }
            // fallback when the shader is missing
            Text {
                visible: timeGlass.status === ShaderEffect.Error
                anchors.fill: timeTxt
                text: timeTxt.text; font: timeTxt.font
                horizontalAlignment: Text.AlignHCenter
                color: Qt.rgba(1, 1, 1, 0.85)
            }
        }
    }

    // ═════════════ COVER HAND-OVER ═════════════
    // Two picture slots. A new cover loads into the back slot; once it's there (or after 1.5 s) the bubble's cover
    // "burns" over to it (burn.frag) and the blurred album background cross-fades, both in step.
    readonly property string coverUrl: media.pl && media.pl.trackArtUrl ? media.pl.trackArtUrl : ""
    property int coverIdx: 0
    property real coverProg: 1
    property real coverSeed: 0
    property bool coverPending: false
    onCoverUrlChanged: {
        if (coverUrl === "" || !ls.isPrimary) return;
        var cur = coverIdx === 0 ? coverA : coverB;
        if (cur.source.toString() === coverUrl) return;
        if (cur.source.toString() === "") { cur.source = coverUrl; return; }     // first cover: just show it
        (coverIdx === 0 ? coverB : coverA).source = coverUrl;
        coverPending = true;
        coverWait.restart();
        coverTry();
    }
    function coverTry() {
        if (!coverPending) return;
        var t = coverIdx === 0 ? coverB : coverA;
        if (t.status === Image.Loading && coverWait.running) return;
        coverPending = false;
        coverWait.stop();
        coverIdx = 1 - coverIdx;
        coverSeed = Math.random();
        coverAnim.restart();
        bgAnim.restart();
    }
    Timer { id: coverWait; interval: 1500; onTriggered: ls.coverTry() }
    NumberAnimation { id: coverAnim; target: ls; property: "coverProg"; from: 0; to: 1; duration: 1100; easing.type: Easing.InOutCubic }
    // the blurred album background: its own, quicker hand-over (0.65 s ease-out)
    property real bgProg: 1
    NumberAnimation { id: bgAnim; target: ls; property: "bgProg"; from: 0; to: 1; duration: 650; easing.type: Easing.OutCubic }
    Image { id: coverA; visible: false; width: 600; height: 600; fillMode: Image.PreserveAspectCrop; asynchronous: true; mipmap: true; sourceSize: Qt.size(600, 600); onStatusChanged: ls.coverTry() }
    Image { id: coverB; visible: false; width: 600; height: 600; fillMode: Image.PreserveAspectCrop; asynchronous: true; mipmap: true; sourceSize: Qt.size(600, 600); onStatusChanged: ls.coverTry() }
    readonly property Item coverNew: coverIdx === 0 ? coverA : coverB
    readonly property Item coverOld: coverIdx === 0 ? coverB : coverA

    // ═════════════ NOW PLAYING ═════════════
    readonly property var player: {
        var ps = Mpris.players.values, best = null;
        for (var i = 0; i < ps.length; i++) {
            if (ps[i].isPlaying) return ps[i];
            if (!best && ps[i].trackTitle) best = ps[i];
        }
        return best;
    }
    readonly property bool hasMedia: player !== null && player !== undefined && (player.trackTitle || "") !== ""
    // Apple "artwork mode" (tap the cover: it leaves the bubble, as wide as the bubble) and Apple Music style lyrics
    // (lyrics button). Only one at a time.
    // npMode: "" | "art" | "lyrics" | "artlyrics" (big cover on the left, lyrics on the right — Apple Music full screen)
    readonly property bool artMode: (ls.st.npMode === "art" || ls.st.npMode === "artlyrics") && hasMedia && isPrimary && !leaving
    readonly property bool lyricsMode: (ls.st.npMode === "lyrics" || ls.st.npMode === "artlyrics") && hasMedia && isPrimary && !leaving
    readonly property bool sideMode: ls.st.npMode === "artlyrics" && hasMedia && isPrimary && !leaving
    // 0 → 1: cover + bubble slide left, the lyrics move beside them
    property real sideT: sideMode ? 1 : 0
    Behavior on sideT { NumberAnimation { id: sideAnim; duration: 650; easing.type: Easing.OutQuint } }
    readonly property real sideGap: 32 * u
    readonly property real sideLyrW: Math.min(560 * u, width - 372 * u - sideGap - 96 * u)
    // 0 → 1 springs; the cover, the bubble, the lyrics and the clock all follow them, so they move as one
    property real artT: artMode ? 1 : 0
    Behavior on artT { NumberAnimation { id: artAnim; duration: 650; easing.type: Easing.OutQuint } }
    property real lyrT: lyricsMode ? 1 : 0
    Behavior on lyrT { NumberAnimation { id: lyrAnim; duration: 650; easing.type: Easing.OutQuint } }
    readonly property bool npAnimating: artAnim.running || lyrAnim.running || sideAnim.running
    function clamp01(v) { return Math.max(0, Math.min(1, v)); }
    // how much the clock gives way (follows the cover / lyrics ease-out)
    readonly property real squash: Math.max(artT, lyrT)
    // ── clock style (Settings → Lock Screen → Clock) ──
    //   font: rounded (default; Nunito, falls back to the bundled Open Runde) | serif (Noto Serif Display) | inter (Open Runde)
    //   material: solid (vibrancy) | glass (Liquid Glass)
    readonly property var ckCfg: (ls.st.clockCfg && !ls.st.clockCfg.__ignore) ? ls.st.clockCfg : ({})
    // anything else (including the removed "condensed" font) falls back to rounded
    readonly property string ckFont: ["rounded", "serif", "inter"].indexOf(ckCfg.f) >= 0 ? ckCfg.f : "rounded"
    readonly property bool ckFontOk: {
        var want = ckFont === "serif" ? "Noto Serif Display" : (ckFont === "inter" ? "Open Runde" : "Nunito");
        return Qt.fontFamilies().indexOf(want) >= 0;
    }
    readonly property string ckFamily: !ckFontOk ? "Open Runde"
        : (ckFont === "serif" ? "Noto Serif Display" : (ckFont === "inter" ? "Open Runde" : "Nunito"))
    readonly property int ckWeight: (typeof ckCfg.w === "number" && ckCfg.w >= 100 && ckCfg.w <= 1000) ? ckCfg.w : 680
    // material: "solid" (vibrancy) | "glass" (Liquid Glass); older settings: liquid → clear glass, frosted → frosted glass
    readonly property bool ckGlass: ckCfg.m !== "solid"
    readonly property real ckIntensity: typeof ckCfg.i === "number" ? Math.max(0, Math.min(1, ckCfg.i))
                                       : (ckCfg.m === "liquid" ? 0.12 : (ckCfg.m === "solid" ? 0.8 : 0.6))
    readonly property color ckTint: (typeof ckCfg.c === "string" && ckCfg.c !== "") ? ckCfg.c : "#FFFFFF"
    readonly property bool ckLiquid: ckGlass && ckIntensity < 0.35
    // the light on the glass follows the pointer (tilting a phone); rests at the top-left
    HoverHandler { id: lightHover }
    property real lightX: -0.6
    property real lightY: -0.8
    Behavior on lightX { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
    Behavior on lightY { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
    Timer {
        interval: 80; repeat: true; running: lightHover.hovered && ls.ckGlass && ls.isPrimary
        onTriggered: {
            var c = clock.mapToItem(ls, clock.width / 2, clock.height / 2);
            var dx = c.x - lightHover.point.position.x, dy = c.y - lightHover.point.position.y;   // light comes from the pointer
            var l = Math.sqrt(dx * dx + dy * dy) || 1;
            // never straight from below: the glass reads best lit from above
            ls.lightX = -dx / l; ls.lightY = Math.min(-0.25, -dy / l);
        }
    }
    readonly property bool ckShortDate: ckCfg.d === "short"
    // size per font (all shrink together when the cover / lyrics need the room)
    readonly property real ckBase: (ckFont === "serif" ? 168 : (ckFont === "rounded" ? 176 : 172))
                                   * (ckWeight < 330 ? 1.12 : 1.0)
    readonly property real clockPx: ckBase * (1 - 0.46 * squash) * u
    readonly property real clockWght: Math.max(100, Math.min(1000, ckWeight - 80 * squash * (ckWeight / 680)))
    readonly property real lyricsH: Math.min(ls.height * 0.42, 440 * ls.u)
    // vertical room above the bubble: the cover, the lyrics, or (side by side) the taller of the two
    // lyrics go UNDER the bubble when it sits in the top spot (the bubble stays put), above it in the bottom spot
    readonly property bool lyricsBelow: ls.st.mediaSlot !== "bottom"
    readonly property real panelRoom: Math.max(Math.max(0, artT) * (media.width + 24 * ls.u), lyricsBelow ? 0 : Math.max(0, lyrT) * (1 - sideT) * (lyricsH + 24 * ls.u))
    readonly property int springMs: 650
    // how far the dragged bubble is pressed past its top / bottom spot (px), 0 when not dragging
    readonly property real pressTop: media.dragging ? Math.max(0, media.slotTop - (media.base + media.dragOff)) : 0
    readonly property real pressBottom: media.dragging ? Math.max(0, (media.base + media.dragOff) - media.slotBottom) : 0
    function squishK(px) { return Math.min(1, px / (70 * u)); }

    Item {
        id: media
        visible: ls.isPrimary && opacity > 0.002
        readonly property bool expanded: ls.artMode
        readonly property real bigArt: width
        width: 372 * ls.u
        height: (150 * ls.u) + ((138 * ls.u) - (150 * ls.u)) * ls.artT
        x: (ls.width - width) / 2 - ls.sideT * (ls.sideLyrW + ls.sideGap) / 2
        readonly property bool on: ls.shown && !ls.leaving && ls.hasMedia
        onOnChanged: if (!on) ls.st.npMode = ""
        // two fixed spots: under the clock, or just above the password field. Drag the card between them.
        // with the cover floating, the top spot leaves room for it between the clock and the bubble
        // computed from where the clock and the login column END UP, not where they are mid-animation
        readonly property real slotTop: 0.075 * ls.height + clock.height + 22 * ls.u + ls.panelRoom
        readonly property real slotBottom: ls.height - login.height - 78 * ls.u - height - 26 * ls.u
        readonly property real base: ls.st.mediaSlot === "bottom" ? slotBottom : slotTop
        property real dragOff: 0
        property bool settling: false
        readonly property bool dragging: mediaDrag.active
        y: base + dragOff
        // y only animates for real moves (cover / lyrics opening, slot changes), never while the lock appears
        property bool settled: false
        Timer { running: ls.shown; interval: 900; onTriggered: media.settled = true }
        opacity: on ? 1 : 0
        scale: !on ? 0.94 : (dragging ? 1.04 : 1)
        // the bubble squashes too where it presses into the clock / the login
        transform: Scale {
            origin.x: media.width / 2; origin.y: ls.pressTop > 0 ? 0 : media.height
            xScale: 1 + 0.05 * ls.squishK(Math.max(ls.pressTop, ls.pressBottom))
            yScale: 1 - 0.10 * ls.squishK(Math.max(ls.pressTop, ls.pressBottom))
            Behavior on xScale { enabled: !media.dragging; NumberAnimation { duration: 650; easing.type: Easing.OutQuint } }
            Behavior on yScale { enabled: !media.dragging; NumberAnimation { duration: 650; easing.type: Easing.OutQuint } }
        }
        z: dragging ? 10 : 0
        Behavior on y { enabled: media.settled && !media.dragging && !media.settling && !ls.npAnimating; NumberAnimation { duration: 650; easing.type: Easing.OutQuint } }

        DragHandler {
            id: mediaDrag
            target: null
            xAxis.enabled: false
            cursorShape: Qt.ClosedHandCursor
            onTranslationChanged: {
                if (!active) return;
                // follow the pointer, with rubber-banding past the two spots
                var lo = media.slotTop - media.base, hi = media.slotBottom - media.base, t = translation.y;
                if (t < lo) t = lo - Math.sqrt(lo - t) * 7;
                else if (t > hi) t = hi + Math.sqrt(t - hi) * 7;
                media.dragOff = t;
            }
            onActiveChanged: {
                ls.st.poke();
                if (active) { settleAnim.stop(); return; }
                // snap to the nearer spot and remember it
                var cur = media.base + media.dragOff;
                var slot = Math.abs(cur - media.slotBottom) < Math.abs(cur - media.slotTop) ? "bottom" : "top";
                media.settling = true;
                var newBase = slot === "bottom" ? media.slotBottom : media.slotTop;
                media.dragOff = cur - newBase;
                ls.st.setMediaSlot(slot);
                settleAnim.restart();
            }
        }
        NumberAnimation {
            id: settleAnim
            target: media; property: "dragOff"; to: 0
            duration: 650; easing.type: Easing.OutQuint
            onFinished: media.settling = false
        }
        Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
        Behavior on scale { NumberAnimation { duration: 650; easing.type: Easing.OutQuint } }

        // keep the latest track info while fading out, so the card doesn't go blank mid-animation
        property var pl: null
        Connections { target: ls; function onPlayerChanged() { if (ls.player) media.pl = ls.player; } }
        Component.onCompleted: pl = ls.player

        Glass {
            anchors.fill: parent
            src: glassTex; frame: ls
            cornerR: 28 * ls.u; thickness: 26; tint: 0.48; shadowAmt: 0.55
        }
        HoverHandler { id: mediaHover }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 6 * ls.u
            width: 34 * ls.u; height: 4 * ls.u; radius: height / 2
            color: "white"
            opacity: media.dragging ? 0.7 : (mediaHover.hovered ? 0.35 : 0)
            Behavior on opacity { NumberAnimation { duration: 220 } }
        }

        // cover art
        Item {
            id: art
            // the cover leaves the glass bubble: it is drawn on the screen itself, above the bubble
            parent: ls
            z: media.z + 1
            visible: media.visible
            opacity: media.opacity
            readonly property real r: (11 * ls.u) + ((28 * ls.u) - (11 * ls.u)) * ls.artT
            x: (media.x + 16 * ls.u) + ((media.x) - (media.x + 16 * ls.u)) * ls.artT
            y: (media.y + 16 * ls.u) + ((media.y - media.bigArt - 24 * ls.u) - (media.y + 16 * ls.u)) * ls.artT
            width: (58 * ls.u) + ((media.bigArt) - (58 * ls.u)) * ls.artT
            height: width
            RectangularShadow {
                anchors.fill: parent
                radius: art.r
                blur: 40 * ls.u; spread: 0
                offset.y: 14 * ls.u
                color: Qt.rgba(0, 0, 0, 0.55)
                opacity: Math.max(0, Math.min(1, ls.artT))
            }
            Rectangle { anchors.fill: parent; radius: art.r; color: Qt.rgba(1, 1, 1, 0.12) }
            TapHandler {
                // cover tap: bubble ↔ big cover; with lyrics open the cover joins them on the left (and leaves again)
                onTapped: {
                    var m = ls.st.npMode;
                    ls.st.npMode = m === "" ? "art" : m === "art" ? "" : m === "lyrics" ? "artlyrics" : "lyrics";
                    ls.st.poke();
                }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            Glyph {
                visible: artImg.status !== Image.Ready
                anchors.centerIn: parent; width: 24 * ls.u; height: 24 * ls.u
                kind: "note"; color: Qt.rgba(1, 1, 1, 0.6)
            }
            ShaderEffectSource { id: covOldSrc; sourceItem: ls.coverOld; visible: false; smooth: true; mipmap: true }
            ShaderEffectSource { id: covNewSrc; sourceItem: ls.coverNew; visible: false; smooth: true; mipmap: true }
            ShaderEffect {
                id: artImg
                anchors.fill: parent
                readonly property int status: ls.coverNew.status
                visible: ls.coverUrl !== ""
                opacity: ls.coverNew.status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }
                fragmentShader: Qt.resolvedUrl("burn.frag.qsb")
                property variant oldTex: covOldSrc
                property variant newTex: covNewSrc
                property real progress: ls.coverProg
                property vector2d itemSize: Qt.vector2d(width, height)
                property real radius: art.r
                property real seed: ls.coverSeed
            }
            Rectangle {
                anchors.fill: parent; radius: art.r; color: "transparent"
                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.14)
            }
        }

        Column {
            id: txtCol
            x: (87 * ls.u) + ((18 * ls.u) - (87 * ls.u)) * ls.artT
            y: (16 * ls.u + (58 * ls.u - height) / 2) + ((16 * ls.u) - (16 * ls.u + (58 * ls.u - height) / 2)) * ls.artT
            width: media.width - x - 18 * ls.u
            spacing: 2 * ls.u
            MorphText {
                width: parent.width; elide: Text.ElideRight
                text: media.pl ? (media.pl.trackTitle || "") : ""
                horizontalAlignment: media.expanded ? Text.AlignHCenter : Text.AlignLeft
                color: "white"; font.family: ls.fam; font.pixelSize: 15 * ls.u; font.weight: Font.DemiBold; animateWidth: false
            }
            MorphText {
                width: parent.width; elide: Text.ElideRight
                text: media.pl ? (media.pl.trackArtist || media.pl.identity || "") : ""
                horizontalAlignment: media.expanded ? Text.AlignHCenter : Text.AlignLeft
                color: Qt.rgba(1, 1, 1, 0.66); font.family: ls.fam; font.pixelSize: 13 * ls.u; animateWidth: false
            }
        }

        // scrubber
        Item {
            id: scrub
            x: 18 * ls.u; width: parent.width - 36 * ls.u
            y: (88 * ls.u) + ((txtCol.y + txtCol.height + 10 * ls.u) - (88 * ls.u)) * ls.artT
            height: 16 * ls.u
            readonly property real len: media.pl && media.pl.lengthSupported ? media.pl.length : 0
            property real pos: 0
            readonly property real frac: len > 0 ? Math.max(0, Math.min(1, pos / len)) : 0
            function fmt(s) { s = Math.max(0, Math.floor(s)); var m = Math.floor(s / 60), r = s % 60; return m + ":" + (r < 10 ? "0" : "") + r; }
            Timer {
                interval: 500; repeat: true; triggeredOnStart: true
                running: media.visible && media.pl !== null
                onTriggered: {
                    if (!media.pl) return;
                    if (media.pl.positionSupported) {
                        media.pl.positionChanged(); scrub.pos = media.pl.position;
                        ls.posBase = scrub.pos; ls.posAt = Date.now(); ls.posPlaying = media.pl.isPlaying;
                    }
                }
            }
            Text {
                id: tL
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                text: scrub.fmt(scrub.pos)
                color: Qt.rgba(1, 1, 1, 0.6); font.family: ls.fam; font.pixelSize: 11 * ls.u; font.features: { "tnum": 1 }
            }
            Text {
                id: tR
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                text: scrub.len > 0 ? "-" + scrub.fmt(scrub.len - scrub.pos) : "--:--"
                color: Qt.rgba(1, 1, 1, 0.6); font.family: ls.fam; font.pixelSize: 11 * ls.u; font.features: { "tnum": 1 }
            }
            Item {
                id: bar
                anchors.left: tL.right; anchors.right: tR.left
                anchors.leftMargin: 10 * ls.u; anchors.rightMargin: 10 * ls.u
                anchors.verticalCenter: parent.verticalCenter
                height: (barMa.containsMouse || barMa.pressed ? 8 : 5) * ls.u
                Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutQuint } }
                Rectangle { anchors.fill: parent; radius: height / 2; color: Qt.rgba(1, 1, 1, 0.22) }
                Rectangle {
                    height: parent.height; radius: height / 2
                    width: Math.max(height, parent.width * scrub.frac)
                    color: Qt.rgba(1, 1, 1, 0.88)
                    Behavior on width { NumberAnimation { duration: 480; easing.type: Easing.Linear } }
                }
                MouseArea {
                    id: barMa
                    anchors.fill: parent; anchors.margins: -8
                    hoverEnabled: true
                    enabled: media.pl !== null && media.pl.canSeek && scrub.len > 0
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: mouse => {
                        var f = Math.max(0, Math.min(1, (mouse.x - 8) / bar.width));
                        media.pl.position = f * scrub.len;
                        scrub.pos = f * scrub.len;
                        ls.posBase = scrub.pos; ls.posAt = Date.now();
                    }
                }
            }
        }

        // lyrics button (Apple's quote bubble), right of the controls
        Item {
            id: lyrBtn
            x: media.width - 16 * ls.u - width
            y: scrub.y + scrub.height + 6 * ls.u
            width: 32 * ls.u; height: 34 * ls.u
            readonly property bool active: ls.st.npMode === "lyrics" || ls.st.npMode === "artlyrics"
            opacity: ls.lyrStatus === "none" || ls.lyrStatus === "instrumental" ? 0.4 : 1
            Rectangle {
                anchors.centerIn: parent
                width: 30 * ls.u; height: width; radius: 9 * ls.u
                color: lyrBtn.active ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(1, 1, 1, lyrMa.containsMouse ? 0.14 : 0)
                scale: lyrMa.pressed ? 0.88 : 1
                Behavior on color { ColorAnimation { duration: 220 } }
                Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutQuint } }
                Canvas {
                    id: quoteIcon
                    anchors.centerIn: parent
                    width: 18 * ls.u; height: width
                    property color ink: lyrBtn.active ? "#1c1c1e" : "white"
                    onInkChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onPaint: {
                        var c = getContext("2d"); c.reset();
                        var s = width / 18; c.scale(s, s);
                        c.fillStyle = ink; c.strokeStyle = ink; c.lineWidth = 1.5; c.lineJoin = "round";
                        // speech bubble
                        c.beginPath();
                        c.moveTo(4.5, 2.5); c.lineTo(13.5, 2.5); c.arcTo(16, 2.5, 16, 5, 2.5); c.lineTo(16, 10.5); c.arcTo(16, 13, 13.5, 13, 2.5);
                        c.lineTo(8, 13); c.lineTo(4.6, 15.8); c.lineTo(4.6, 13); c.arcTo(2, 13, 2, 10.5, 2.5); c.lineTo(2, 5); c.arcTo(2, 2.5, 4.5, 2.5, 2.5);
                        c.closePath(); c.stroke();
                        // quote marks
                        function q(x) { c.beginPath(); c.arc(x, 7, 1.35, 0, Math.PI * 2); c.fill(); c.beginPath(); c.moveTo(x + 1.2, 7); c.quadraticCurveTo(x + 1.3, 9.6, x - 0.6, 10.4); c.stroke(); }
                        q(6.6); q(10.8);
                    }
                }
            }
            MouseArea {
                id: lyrMa
                anchors.fill: parent; anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    // lyrics button: with the cover enlarged the cover slides left and the lyrics appear beside it
                    var m = ls.st.npMode;
                    ls.st.npMode = m === "" ? "lyrics" : m === "lyrics" ? "" : m === "art" ? "artlyrics" : "art";
                    if (ls.lyricsMode && (ls.lyrStatus === "idle" || ls.lyrStatus === "none")) ls.fetchLyrics();
                    ls.st.poke();
                }
            }
        }

        // transport controls
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: scrub.y + scrub.height + 6 * ls.u
            spacing: 26 * ls.u
            Repeater {
                model: ["prev", "play", "next"]
                delegate: Item {
                    id: tb
                    required property string modelData
                    readonly property bool big: modelData === "play"
                    width: (big ? 38 : 32) * ls.u; height: 34 * ls.u
                    readonly property bool can: media.pl !== null && (modelData === "prev" ? media.pl.canGoPrevious
                                                : modelData === "next" ? media.pl.canGoNext : media.pl.canTogglePlaying)
                    opacity: can ? 1 : 0.35
                    // glass halo on hover
                    Rectangle {
                        anchors.centerIn: parent
                        width: 40 * ls.u; height: width; radius: width / 2
                        color: Qt.rgba(1, 1, 1, tma.pressed ? 0.20 : 0.12)
                        opacity: tma.containsMouse ? 1 : 0
                        scale: tma.containsMouse ? 1 : 0.6
                        Behavior on opacity { NumberAnimation { duration: 180 } }
                        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
                    }
                    MorphGlyph {
                        anchors.centerIn: parent
                        width: (tb.big ? 26 : 22) * ls.u; height: width
                        kind: tb.modelData === "play" ? (media.pl && media.pl.isPlaying ? "pause" : "play") : tb.modelData
                        color: "white"
                        scale: tma.pressed ? 0.84 : 1
                        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
                    }
                    MouseArea {
                        id: tma
                        anchors.fill: parent; anchors.margins: -4
                        hoverEnabled: true
                        enabled: tb.can
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (tb.modelData === "prev") media.pl.previous();
                            else if (tb.modelData === "next") media.pl.next();
                            else media.pl.togglePlaying();
                        }
                    }
                }
            }
        }
    }

    // ═════════════ LYRICS (Apple Music style) ═════════════
    // estimated playback position: MPRIS is polled twice a second, the lyrics need it smooth
    property real posBase: 0
    property real posAt: 0
    property bool posPlaying: false
    property real estPos: 0
    Timer {
        interval: 50; repeat: true
        running: ls.lyricsMode || ls.lyrT > 0.01
        onTriggered: ls.estPos = ls.posBase + (ls.posPlaying ? (Date.now() - ls.posAt) / 1000 : 0)
    }

    // Spotify Canvas: short looping video artwork for supported tracks
    property string canvasVideo: ""
    readonly property string spotifyTrackId: {
        if (!media.pl) return "";
        // MPRIS trackId is often a generic D-Bus object path; do not let it mask the Spotify URL.
        // Quickshell's MprisPlayer has no trackId / url property: the raw MPRIS fields live in `metadata`
        var md = media.pl.metadata || {};
        var candidates = [String(md["xesam:url"] || ""), String(md["mpris:trackid"] || ""), String(media.pl.uniqueId || "")];
        for (var i = 0; i < candidates.length; i++) {
            var m = candidates[i].match(/(?:spotify:track:|open\.spotify\.com\/track\/|\/com\/spotify\/track\/)([a-zA-Z0-9]{22})/i);
            if (m) return m[1];
        }
        return "";
    }
    onTrackKeyChanged: { lyrFetchDelay.restart(); canvasDelay.restart(); }
    Timer {
        id: canvasDelay; interval: 500
        onTriggered: {
            ls.canvasVideo = "";
            if (media.pl && (ls.spotifyTrackId !== "" || (media.pl.identity || "").toLowerCase().indexOf("spotify") >= 0)) {
                canvasProc.running = false;
                var arg = ls.spotifyTrackId !== "" ? ls.spotifyTrackId : ((media.pl.trackArtist || "") + " " + (media.pl.trackTitle || ""));
                canvasProc.command = ["python3", Quickshell.env("HOME") + "/.config/quickshell/MacLock/spotify-canvas.py", arg];
                canvasProc.running = true;
            }
        }
    }
    Process {
        id: canvasProc
        stdout: StdioCollector {
            onStreamFinished: {
                var p = (text || "").trim();
                if (p.length > 0) ls.canvasVideo = p;
            }
        }
    }

    // lyrics for the current track: NetEase, LRCLIB, and Genius, cached in ~/.cache/maclock/lyrics
    property var lyrLines: []              // [{ t: seconds (-1 = unsynced), text }]
    property string lyrStatus: "idle"      // idle | loading | synced | plain | none
    readonly property string trackKey: media.pl ? (media.pl.trackArtist || "") + "\u0001" + (media.pl.trackTitle || "") : ""
    Timer { id: lyrFetchDelay; interval: 400; onTriggered: { ls.lyrTries = 0; ls.fetchLyrics(); } }
    property int lyrTries: 0
    Timer { id: lyrRetry; interval: 12000; onTriggered: ls.fetchLyrics() }
    function fetchLyrics() {
        if (!ls.isPrimary || !media.pl || !(media.pl.trackTitle || "")) { lyrLines = []; lyrStatus = "idle"; return; }
        lyrLines = []; lyrStatus = "loading";
        var len = media.pl.lengthSupported ? Math.round(media.pl.length) : 0;
        lyrProc.running = false;
        lyrProc.command = ["sh", "-c", ls.lyrScript, "sh", media.pl.trackArtist || "", media.pl.trackTitle || "", media.pl.trackAlbum || "", len > 0 ? String(len) : ""];
        lyrProc.running = true;
    }
    readonly property string lyrScript: [
        'a="$1"; t="$2"; al="$3"; d="${4:-0}"; c="$HOME/.cache/maclock/lyrics"; mkdir -p "$c"',
        'k=$(printf "%s|%s" "$a" "$t" | md5sum | cut -c1-16); f="$c/$k.json"',
        '[ -s "$f" ] && { cat "$f"; exit 0; }',
        'tmp=$(mktemp); answered=0; r=""',
        // titles like "Song (feat. X)" / "Song - Remastered 2011": also try the bare title
        'bare=$(printf "%s" "$t" | sed -E "s/ *[(\\[][^)\\]]*[)\\]]//g; s/ +- +(.*[Rr]emaster.*|[Ll]ive.*|[Rr]adio [Ee]dit.*)$//")',
        // ── 1. NetEase Cloud Music: fast, not rate-limited. Same title + same length (±4 s) or it doesn't count.
        'ne() { code=$(curl -s --max-time 6 -A "Mozilla/5.0" -o "$tmp" -w "%{http_code}" -G "https://music.163.com/api/search/get" --data-urlencode "s=$1" -d type=1 -d limit=10); [ "$code" = 200 ] || return 1; answered=1',
        '  id=$(jq -r --arg t "$bare" --argjson d "$d" \'def n: ascii_downcase | gsub("[^\\\\p{L}\\\\p{N}]"; ""); ($t | n) as $q | [.result.songs[]? | select((.name | n) as $nm | ($nm == $q) or ($nm | startswith($q)) or ($q | startswith($nm))) | select($d == 0 or (((.duration / 1000) - $d) | fabs) <= 4)][0].id // empty\' "$tmp")',
        '  [ -n "$id" ] || return 1',
        '  curl -s --max-time 6 -A "Mozilla/5.0" -o "$tmp" "https://music.163.com/api/song/lyric?id=$id&lv=1" || return 1',
        '  l=$(jq -r ".lrc.lyric // empty" "$tmp"); case "$l" in *"[0"*|*"[1"*) ;; *) return 1;; esac',
        '  r=$(jq -nc --arg l "$l" "{syncedLyrics: \\$l}"); }',
        'ne "$a $bare" || ne "$bare"',
        // ── 2. LRCLIB (rate-limited per second: wait and retry briefly), length-checked too
        'ua="MacLock/1.0 (https://github.com/0-ss/Macshell)"; api=https://lrclib.net/api',
        'req() { n=0; while [ $n -lt 2 ]; do code=$(curl -s --max-time 8 -A "$ua" -o "$tmp" -w "%{http_code}" -G "$@"); case "$code" in 200) answered=1; return 0;; 404) answered=1; return 1;; 429) n=$((n+1)); sleep 1.5;; *) return 1;; esac; done; return 1; }',
        'pick=\'[.[] | select(.syncedLyrics != null or .plainLyrics != null) | select($d == 0 or (((.duration // 0) - $d) | fabs) <= 4)] | ([.[] | select(.syncedLyrics != null)][0] // .[0]) // empty\'',
        'lsearch() { req "$api/search" "$@" && r=$(jq -c --argjson d "$d" "$pick" "$tmp"); }',
        '[ -z "$r" ] && lsearch --data-urlencode "track_name=$t" --data-urlencode "artist_name=$a"',
        '[ -z "$r" ] && [ "$bare" != "$t" ] && lsearch --data-urlencode "track_name=$bare" --data-urlencode "artist_name=$a"',
        '[ -z "$r" ] && lsearch --data-urlencode "q=$a $bare"',
        'rm -f "$tmp"',
        // ── 3. Genius: token-free, rich lyrics source
        'if [ -z "$r" ] || [ "$(printf "%s" "$r" | jq -r ".syncedLyrics // empty" 2>/dev/null)" = "" ]; then',
        '  g=$(python3 "$HOME/.config/quickshell/MacLock/genius-lyrics.py" "$a" "$bare" "$c" 2>/dev/null || true)',
        '  if [ -n "$g" ] && [ "$g" != "{}" ]; then',
        '    gp=$(printf "%s" "$g" | jq -r ".plain // empty" 2>/dev/null)',
        '    if [ -n "$gp" ]; then r=$(jq -nc --arg p "$gp" "{plainLyrics: \\$p}"); answered=1; fi',
        '  fi',
        'fi',
        'if [ -n "$r" ]; then printf "%s" "$r" | jq -c "{synced: .syncedLyrics, plain: .plainLyrics, instrumental: .instrumental}" | tee "$f"',
        // a source really answered and nobody has it: remember; otherwise (offline / still limited) let the UI retry
        'elif [ "$answered" = 1 ]; then echo "{}" | tee "$f"',
        'else echo "{\\"retry\\":true}"; fi'
    ].join("\n")
    Process {
        id: lyrProc
        stdout: StdioCollector {
            onStreamFinished: {
                var o = {};
                try { o = JSON.parse(text || "{}"); } catch (e) { o = {}; }
                var out = [], i, m;
                if (o.synced) {
                    var ls2 = o.synced.split("\n");
                    for (i = 0; i < ls2.length; i++) {
                        var line = ls2[i], tags = [], re = /\[(\d+):(\d+(?:\.\d+)?)\]/g;
                        while ((m = re.exec(line)) !== null) tags.push(parseInt(m[1]) * 60 + parseFloat(m[2]));
                        var txt = line.replace(/\[[^\]]*\]/g, "").trim();
                        if (/^(制作人|作词|作曲|编曲|混音|母带|制作|和声|吉他|贝斯|鼓|录音|监制|出品|发行|OP|SP|Producer|Lyricist|Composer|Lyrics|Composed|Written)\s*[:：]/i.test(txt)) continue;
                        for (var j = 0; j < tags.length; j++) out.push({ t: tags[j], text: txt });
                    }
                    out.sort(function (a, b) { return a.t - b.t; });
                    ls.lyrLines = out; ls.lyrStatus = out.length > 0 ? "synced" : "none";
                } else if (o.plain) {
                    var pl = o.plain.split("\n");
                    for (i = 0; i < pl.length; i++) out.push({ t: -1, text: pl[i].trim() });
                    ls.lyrLines = out; ls.lyrStatus = "plain";
                } else if (o.retry) {
                    // rate-limited / offline: try again shortly (a few times)
                    if (ls.lyrTries < 4) { ls.lyrTries++; ls.lyrStatus = "loading"; lyrRetry.restart(); }
                    else { ls.lyrLines = []; ls.lyrStatus = "offline"; }
                } else if (o.instrumental) {
                    ls.lyrLines = []; ls.lyrStatus = "instrumental";
                } else {
                    ls.lyrLines = []; ls.lyrStatus = "none";
                }
            }
        }
    }

    // current line (a hair early, like Apple Music)
    readonly property int lyrCur: {
        if (lyrStatus !== "synced") return -1;
        var p = estPos + 0.25, c = -1;
        for (var i = 0; i < lyrLines.length; i++) { if (lyrLines[i].t <= p) c = i; else break; }
        return c;
    }

    Item {
        id: lyr
        visible: ls.lyrT > 0.01 && media.visible
        // lines past the feathered edges are cut off for real: not drawn and not clickable (they used to sit invisibly
        // over the media controls and swallow clicks)
        clip: true
        z: media.z + 1
        readonly property real wTop: Math.min(ls.width - 80 * ls.u, 620 * ls.u)
        readonly property real hSide: media.width + 24 * ls.u + media.height
        // lyrics-only: below the bubble (top spot, filling the room down to the password field) or above it (bottom spot)
        readonly property real belowY: media.y + media.height + 24 * ls.u
        readonly property real belowH: Math.max(140 * ls.u, Math.min(ls.lyricsH, (ls.height - login.height - 78 * ls.u - 24 * ls.u) - belowY))
        readonly property real soloH: ls.lyricsBelow ? belowH : ls.lyricsH
        readonly property real soloY: ls.lyricsBelow ? belowY : media.y - ls.lyricsH - 24 * ls.u
        readonly property real sideY: media.y - media.width - 24 * ls.u
        width: wTop + (ls.sideLyrW - wTop) * ls.sideT
        height: soloH + (hSide - soloH) * ls.sideT
        x: (ls.width - wTop) / 2 + ((media.x + media.width + ls.sideGap) - (ls.width - wTop) / 2) * ls.sideT
        y: soloY + (sideY - soloY) * ls.sideT
        opacity: ls.clamp01(ls.lyrT) * media.opacity
        scale: 0.94 + 0.06 * ls.lyrT
        transformOrigin: ls.sideMode ? Item.Left : (ls.lyricsBelow ? Item.Top : Item.Bottom)

        // manual scroll (wheel); synced lyrics snap back to the current line a few seconds later
        property real manual: 0
        Timer { id: manualReset; interval: 3500; onTriggered: if (ls.lyrStatus === "synced") lyr.manual = 0 }
        WheelHandler {
            onWheel: ev => { lyr.manual = Math.max(-200 * ls.u, lyr.manual - ev.angleDelta.y * 0.6); manualReset.restart(); ls.st.poke(); }
        }
        Behavior on manual { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }

        // where the column scrolls to: the current line sits about a third of the way down
        readonly property real target: {
            var it = ls.lyrCur >= 0 ? lyrRep.itemAt(ls.lyrCur) : null;
            var base = it ? it.y - height * 0.30 : -height * 0.30;
            return base + manual;
        }

        // the lines, faded out at the top and bottom edges
        Item {
            id: lyrView
            anchors.fill: parent
            clip: true
            layer.enabled: true
            layer.effect: ShaderEffect {
                fragmentShader: Qt.resolvedUrl("fade.frag.qsb")
                property real fadeTop: 0.24
                property real fadeBottom: 0.30
            }
            Column {
                id: lyrCol
                width: parent.width
                spacing: 20 * ls.u
                Repeater {
                    id: lyrRep
                    model: ls.lyrLines
                    delegate: Item {
                        id: ln
                        required property var modelData
                        required property int index
                        readonly property int rel: ls.lyrCur < 0 ? 0 : index - ls.lyrCur
                        readonly property bool cur: ls.lyrStatus === "synced" && index === ls.lyrCur
                        readonly property bool gap: (modelData.text || "") === ""
                        width: lyrCol.width
                        height: gap ? 34 * ls.u : lt.implicitHeight
                        // Apple Music's wave: every line follows the scroll on its own spring, lines further down a little later
                        transform: Translate {
                            id: lnTr
                            y: -lyr.target
                            Behavior on y { NumberAnimation { duration: 500 + Math.max(0, Math.min(8, ln.rel)) * 20; easing.type: Easing.OutQuint } }
                        }
                        opacity: ls.lyrStatus !== "synced" ? 0.9 : (cur ? 1 : (Math.abs(rel) === 1 ? 0.42 : 0.26))
                        Behavior on opacity { NumberAnimation { duration: 380 } }
                        Text {
                            id: lt
                            visible: !ln.gap
                            width: parent.width
                            text: ln.modelData.text
                            wrapMode: Text.WordWrap
                            color: "white"
                            font.family: ls.fam; font.pixelSize: 31 * ls.u; font.weight: Font.Bold
                            lineHeight: 1.08
                            transformOrigin: Item.Left
                            scale: ln.cur || ls.lyrStatus !== "synced" ? 1 : 0.965
                            Behavior on scale { NumberAnimation { duration: 420; easing.type: Easing.OutQuint } }
                            // lines away from the current one go soft, like Apple Music (only near lines get a blur layer)
                            layer.enabled: ls.lyrStatus === "synced" && !ln.cur && Math.abs(ln.rel) <= 6
                            layer.effect: MultiEffect { blurEnabled: true; blurMax: 16; blur: Math.min(0.55, 0.14 * Math.abs(ln.rel)) }
                        }
                        // instrumental break: three breathing dots
                        Row {
                            visible: ln.gap
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 9 * ls.u
                            Repeater {
                                model: 3
                                delegate: Rectangle {
                                    required property int index
                                    width: 11 * ls.u; height: width; radius: width / 2
                                    color: "white"
                                    opacity: ln.cur ? 0.95 : 0.35
                                    SequentialAnimation on scale {
                                        running: ln.cur; loops: Animation.Infinite
                                        PauseAnimation { duration: index * 160 }
                                        NumberAnimation { from: 0.7; to: 1.15; duration: 520; easing.type: Easing.InOutSine }
                                        NumberAnimation { from: 1.15; to: 0.7; duration: 520; easing.type: Easing.InOutSine }
                                    }
                                }
                            }
                        }
                        // tap a line to jump there
                        // where this line is on screen right now (after the scroll), to ignore lines in / past the feather
                        readonly property real shownY: y + lnTr.y
                        readonly property bool inBand: shownY + height > lyr.height * 0.20 && shownY < lyr.height * 0.74
                        TapHandler {
                            enabled: ln.inBand && ls.lyrStatus === "synced" && media.pl && media.pl.canSeek
                            onTapped: {
                                media.pl.position = ln.modelData.t;
                                ls.posBase = ln.modelData.t; ls.posAt = Date.now(); scrub.pos = ln.modelData.t;
                                lyr.manual = 0; ls.st.poke();
                            }
                        }
                        HoverHandler { enabled: ln.inBand && ls.lyrStatus === "synced"; cursorShape: Qt.PointingHandCursor }
                    }
                }
            }
        }
        MorphText {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            visible: ls.lyrStatus === "loading" || ls.lyrStatus === "none" || ls.lyrStatus === "instrumental" || ls.lyrStatus === "offline"
            text: ls.lyrStatus === "loading" ? I18n.tr("Loading lyrics…") : (ls.lyrStatus === "instrumental" ? I18n.tr("Instrumental")
                  : (ls.lyrStatus === "offline" ? "Lyrics are unavailable right now" : "No lyrics for this song"))
            color: Qt.rgba(1, 1, 1, 0.55)
            font.family: ls.fam; font.pixelSize: 20 * ls.u; font.weight: Font.DemiBold
        }
    }

    // ═════════════ USER + PASSWORD (bottom) ═════════════
    Column {
        id: login
        visible: ls.isPrimary
        // repel: the bubble pressing down into the avatar / password pushes them down and squashes them
        transform: [
            Translate {
                y: ls.pressBottom * 0.45
                Behavior on y { enabled: !media.dragging; NumberAnimation { duration: 650; easing.type: Easing.OutQuint } }
            },
            Scale {
                origin.x: login.width / 2; origin.y: login.height
                xScale: 1 + 0.06 * ls.squishK(ls.pressBottom)
                yScale: 1 - 0.14 * ls.squishK(ls.pressBottom)
                Behavior on xScale { enabled: !media.dragging; NumberAnimation { duration: 650; easing.type: Easing.OutQuint } }
                Behavior on yScale { enabled: !media.dragging; NumberAnimation { duration: 650; easing.type: Easing.OutQuint } }
            }
        ]
        anchors.horizontalCenter: parent.horizontalCenter
        y: ls.height - height - (ls.shown && !ls.leaving ? 78 : 30) * ls.u
        opacity: ls.shown && !ls.leaving ? 1 : 0
        spacing: 10 * ls.u
        Behavior on y { NumberAnimation { duration: ls.leaving ? 380 : 650; easing.type: Easing.OutQuint } }
        Behavior on opacity { NumberAnimation { duration: ls.leaving ? 260 : 650; easing.type: Easing.OutQuint } }

        // avatar
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 70 * ls.u; height: width
            scale: ls.st.engaged ? 1.0 : 0.94
            Behavior on scale { NumberAnimation { duration: 650; easing.type: Easing.OutQuint } }
            Rectangle {
                anchors.fill: parent; radius: width / 2
                color: Qt.rgba(1, 1, 1, 0.16)
                Text {
                    anchors.centerIn: parent
                    visible: avatarImg.status !== Image.Ready
                    text: (ls.st.userName || "?").charAt(0).toUpperCase()
                    color: "white"; font.family: ls.fam; font.pixelSize: 30 * ls.u; font.weight: Font.DemiBold
                }
            }
            Item {
                id: avMask
                anchors.fill: parent; visible: false
                layer.enabled: true; layer.smooth: true
                Rectangle { anchors.fill: parent; radius: width / 2; color: "black" }
            }
            Image {
                id: avatarImg
                anchors.fill: parent
                source: ls.st.avatar !== "" ? "file://" + ls.st.avatar : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true; smooth: true; mipmap: true
                sourceSize: Qt.size(256, 256)
                layer.enabled: true; layer.smooth: true
                layer.effect: MultiEffect { maskEnabled: true; maskSource: avMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
            }
            Rectangle {
                anchors.fill: parent; radius: width / 2; color: "transparent"
                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.22)
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: ls.st.userName
            color: "white"; font.family: ls.fam; font.pixelSize: 15 * ls.u; font.weight: Font.DemiBold
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.5; shadowOpacity: 0.3; shadowVerticalOffset: 1 }
        }

        // password pill
        Item {
            id: pwBox
            anchors.horizontalCenter: parent.horizontalCenter
            width: (ls.st.pass.length > 0 || ls.st.engaged ? 236 : 210) * ls.u
            height: 36 * ls.u
            Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.OutQuint } }
            // pressed: Liquid Glass "squish" (a bit wider, a bit flatter); it stays squished while you hold
            readonly property bool pressed: pwMa.pressed || ls.enterHeld
            transform: [
                Translate { id: shakeT; x: 0 },
                Scale {
                    origin.x: pwBox.width / 2; origin.y: pwBox.height / 2
                    xScale: pwBox.pressed ? 1.045 : 1.0
                    yScale: pwBox.pressed ? 0.86 : 1.0
                    Behavior on xScale { NumberAnimation { duration: pwBox.pressed ? 140 : 420; easing.type: Easing.OutQuint } }
                    Behavior on yScale { NumberAnimation { duration: pwBox.pressed ? 140 : 420; easing.type: Easing.OutQuint } }
                }
            ]

            SequentialAnimation {
                id: shake
                NumberAnimation { target: shakeT; property: "x"; to: -16 * ls.u; duration: 55; easing.type: Easing.OutQuint }
                NumberAnimation { target: shakeT; property: "x"; to: 14 * ls.u; duration: 80; easing.type: Easing.InOutQuad }
                NumberAnimation { target: shakeT; property: "x"; to: -10 * ls.u; duration: 75; easing.type: Easing.InOutQuad }
                NumberAnimation { target: shakeT; property: "x"; to: 7 * ls.u; duration: 70; easing.type: Easing.InOutQuad }
                NumberAnimation { target: shakeT; property: "x"; to: -3 * ls.u; duration: 65; easing.type: Easing.InOutQuad }
                NumberAnimation { target: shakeT; property: "x"; to: 0; duration: 90; easing.type: Easing.OutQuint }
            }
            Connections { target: ls.st; function onFailsChanged() { if (ls.st.fails > 0) shake.restart(); } }

            Item {
                id: pwGlow
                anchors.fill: parent
                opacity: 0
                RectangularShadow { anchors.fill: parent; radius: height / 2; blur: 26 * ls.u; spread: 2 * ls.u; color: Qt.rgba(1, 1, 1, 0.55) }
            }
            SequentialAnimation {
                id: pwPulse
                NumberAnimation { target: pwGlow; property: "opacity"; to: 1; duration: 280; easing.type: Easing.OutCubic }
                PauseAnimation { duration: 220 }
                NumberAnimation { target: pwGlow; property: "opacity"; to: 0; duration: 500; easing.type: Easing.InOutCubic }
            }
            Glass {
                anchors.fill: parent
                src: glassTex; frame: ls
                cornerR: height / 2; thickness: 18; tint: 0.50; shadowAmt: 0.4
            }
            Rectangle {
                anchors.fill: parent; radius: height / 2; color: "transparent"
                border.width: 1.5; border.color: "white"
                opacity: pwGlow.opacity * 0.9
            }
            // hover / press: contour glow along the pill, brighter while held
            MouseArea {
                id: pwMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.IBeamCursor
                onPressed: { ls.forceActiveFocus(); ls.st.poke(); }
            }
            ContourGlow {
                cornerR: pwBox.height / 2
                hovered: pwMa.containsMouse || pwBox.pressed
                boost: pwBox.pressed ? 1.6 : 1.0
                at: pwMa.containsMouse ? Qt.point(pwMa.mouseX, pwMa.mouseY) : Qt.point(pwBox.width / 2, 0)
                glowColor: "white"
            }

            Text {
                anchors.left: parent.left; anchors.leftMargin: 16 * ls.u
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Enter Password")
                color: Qt.rgba(1, 1, 1, 0.62)
                font.family: ls.fam; font.pixelSize: 14 * ls.u
                opacity: ls.st.pass.length === 0 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }

            // password dots: one entry per character, so only the dot you just typed animates in (and only the one you
            // deleted animates out) — the row slides over smoothly as it grows / shrinks; the rest never move or blink
            ListModel { id: dotModel }
            function syncDots() {
                var want = ls.st.pass.length, alive = 0, i;
                for (i = 0; i < dotModel.count; i++) if (!dotModel.get(i).dying) alive++;
                while (alive < want) { dotModel.append({ dying: false }); alive++; }
                for (i = dotModel.count - 1; i >= 0 && alive > want; i--)
                    if (!dotModel.get(i).dying) { dotModel.setProperty(i, "dying", true); alive--; }
            }
            Connections { target: ls.st; function onPassChanged() { pwBox.syncDots(); } }
            Item {
                anchors.left: parent.left; anchors.leftMargin: 16 * ls.u
                anchors.right: ls.st.capsLock ? capsIcon.left : goBtn.left; anchors.rightMargin: 8 * ls.u
                anchors.verticalCenter: parent.verticalCenter
                height: 12 * ls.u
                clip: true
                Row {
                    id: dotRow
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.min(0, parent.width - width)          // long passwords: the newest dots stay in view
                    Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Repeater {
                        model: dotModel
                        delegate: Item {
                            id: dotCell
                            required property int index
                            required property bool dying
                            readonly property real step: 12 * ls.u
                            property real grow: 0
                            width: step * grow; height: 12 * ls.u
                            Component.onCompleted: grow = 1
                            onDyingChanged: if (dying) { grow = 0; dotGone.start(); }
                            Behavior on grow { NumberAnimation { duration: dotCell.dying ? 200 : 240; easing.type: Easing.OutCubic } }
                            Rectangle {
                                x: 2.5 * ls.u; anchors.verticalCenter: parent.verticalCenter
                                width: 7 * ls.u; height: width; radius: width / 2
                                color: "white"
                                opacity: dotCell.grow
                                scale: 0.35 + 0.65 * dotCell.grow
                            }
                            Timer { id: dotGone; interval: 230; onTriggered: { for (var i = dotModel.count - 1; i >= 0; i--) if (dotModel.get(i).dying) { dotModel.remove(i); break; } } }
                        }
                    }
                }
            }

            // Caps Lock indicator, macOS style: the ⇪ symbol inside the field, left of the arrow
            Item {
                id: capsIcon
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: goBtn.on ? goBtn.left : parent.right
                anchors.rightMargin: goBtn.on ? 6 * ls.u : 12 * ls.u
                width: 18 * ls.u; height: width
                opacity: ls.st.capsLock ? 0.9 : 0
                scale: ls.st.capsLock ? 1 : 0.5
                Behavior on opacity { NumberAnimation { duration: 180 } }
                Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                Canvas {
                    anchors.fill: parent
                    onWidthChanged: requestPaint()
                    onPaint: {
                        var c = getContext("2d"); c.reset();
                        var s = width / 18;
                        c.scale(s, s);
                        c.strokeStyle = "white"; c.fillStyle = "white";
                        c.lineWidth = 1.5; c.lineJoin = "round"; c.lineCap = "round";
                        // arrow outline: point at the top, shoulders, stem
                        c.beginPath();
                        c.moveTo(9, 2.2); c.lineTo(15.6, 9.2); c.lineTo(12, 9.2); c.lineTo(12, 12.4);
                        c.lineTo(6, 12.4); c.lineTo(6, 9.2); c.lineTo(2.4, 9.2); c.closePath();
                        c.stroke();
                        // bar under it
                        c.beginPath(); c.moveTo(6, 15.4); c.lineTo(12, 15.4); c.stroke();
                    }
                }
            }

            // arrow / spinner on the right
            Item {
                id: goBtn
                anchors.right: parent.right; anchors.rightMargin: 6 * ls.u
                anchors.verticalCenter: parent.verticalCenter
                width: 24 * ls.u; height: width
                readonly property bool on: ls.st.pass.length > 0 || ls.st.busy
                opacity: on ? 1 : 0
                scale: on ? 1 : 0.4
                Behavior on opacity { NumberAnimation { duration: 200 } }
                Behavior on scale { NumberAnimation { duration: 340; easing.type: Easing.OutQuint } }
                Rectangle {
                    anchors.fill: parent; radius: width / 2
                    color: Qt.rgba(1, 1, 1, goMa.pressed ? 0.42 : 0.26)
                    visible: !ls.st.busy
                }
                Canvas {
                    id: arrow
                    anchors.fill: parent
                    visible: !ls.st.busy
                    onPaint: {
                        var c = getContext("2d"); c.reset();
                        var w = width;
                        c.strokeStyle = "white"; c.lineWidth = Math.max(1.6, w * 0.085); c.lineCap = "round"; c.lineJoin = "round";
                        c.beginPath(); c.moveTo(w * 0.28, w * 0.5); c.lineTo(w * 0.72, w * 0.5); c.stroke();
                        c.beginPath(); c.moveTo(w * 0.53, w * 0.31); c.lineTo(w * 0.72, w * 0.5); c.lineTo(w * 0.53, w * 0.69); c.stroke();
                    }
                    onWidthChanged: requestPaint()
                }
                // spinner while PAM is checking
                Canvas {
                    anchors.fill: parent
                    visible: ls.st.busy
                    onPaint: {
                        var c = getContext("2d"); c.reset();
                        var w = width;
                        c.strokeStyle = "white"; c.lineWidth = Math.max(1.6, w * 0.09); c.lineCap = "round";
                        c.beginPath(); c.arc(w / 2, w / 2, w * 0.36, 0, Math.PI * 1.4); c.stroke();
                    }
                    onWidthChanged: requestPaint()
                    RotationAnimator on rotation { from: 0; to: 360; duration: 800; loops: Animation.Infinite; running: ls.st.busy }
                }
                MouseArea {
                    id: goMa
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ls.st.submit()
                }
            }
        }

        // hint / error line (blur-morphs between "Enter your password…" and "Incorrect password")
        MorphText {
            horizontalAlignment: Text.AlignHCenter
            anchors.horizontalCenter: parent.horizontalCenter
            text: ls.st.message !== "" ? ls.st.message : I18n.tr("Enter your password to unlock")
            color: ls.st.message !== "" ? Qt.rgba(1, 0.78, 0.76, 0.95) : Qt.rgba(1, 1, 1, 0.55)
            font.family: ls.fam; font.pixelSize: 12 * ls.u
            opacity: ls.st.engaged || ls.st.message !== "" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 300 } }
        }
    }

    // ═════════════ INPUT ═════════════
    // Every monitor takes the keyboard; the text lives in the shared state, so typing works whichever surface has focus.
    Timer { id: capsSoon; interval: 60; onTriggered: ls.st.checkCaps() }
    property bool enterHeld: false
    Keys.onReleased: event => { if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { if (!event.isAutoRepeat) ls.enterHeld = false; } }
    Keys.onPressed: event => {
        ls.st.poke();
        if (event.key === Qt.Key_CapsLock) capsSoon.restart();
        if (ls.st.busy || ls.st.unlocking) { event.accepted = true; return; }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            ls.enterHeld = true;
            if (event.isAutoRepeat) { event.accepted = true; return; }   // holding Enter keeps the squish, submits once
            ls.st.submit();
        } else if (event.key === Qt.Key_Escape) {
            ls.st.pass = "";
        } else if (event.key === Qt.Key_Backspace) {
            if (event.modifiers & Qt.ControlModifier) ls.st.pass = "";
            else ls.st.pass = ls.st.pass.slice(0, -1);
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_U) {
            ls.st.pass = "";
        } else if (event.text !== "" && event.text.charCodeAt(0) >= 32 && !(event.modifiers & Qt.ControlModifier)) {
            ls.st.pass += event.text;
            ls.st.message = "";
        }
        event.accepted = true;
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        property point last: Qt.point(-1, -1)
        onPositionChanged: mouse => {
            // ignore the synthetic move a new surface gets on map
            if (last.x >= 0 && (Math.abs(mouse.x - last.x) > 2 || Math.abs(mouse.y - last.y) > 2)) ls.st.poke();
            last = Qt.point(mouse.x, mouse.y);
        }
        onClicked: { ls.forceActiveFocus(); ls.st.poke(); }
    }
}
