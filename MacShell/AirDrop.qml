// AirDrop — send files to the devices around you, with the radar, the pulse and the spinner.
//
//   qs -c MacShell ipc call airdrop open
//
// Underneath it speaks LocalSend's protocol (scripts/macshell-airdrop.py), so it finds and sends to anything
// running LocalSend: phones, tablets, other desktops. Drop files on a device, or click one to pick them.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property var hub: null
    readonly property var dock: hub ? hub.dock : null
    readonly property var bar: hub ? hub.bar : null
    readonly property bool darkMode: dock ? dock.darkMode : true
    readonly property string fam: dock ? dock.fontFamily : "Inter Variable"
    property color accent: dock ? dock.accent : "#0A84FF"
    Behavior on accent { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
    readonly property string home: Quickshell.env("HOME")
    readonly property string helper: {
        var p = Qt.resolvedUrl("scripts/macshell-airdrop.py").toString().replace(/^file:\/\//, "");
        return p !== "" ? p : home + "/.config/hypr-macshell/scripts/macshell-airdrop.py";
    }

    property var peers: []                  // { alias, ip, port, deviceType, fingerprint, state, detail }
    property bool scanning: false
    property string status: ""

    // ── Receiving: we stay visible on the network and take what people send (saved in ~/Downloads) ──
    property bool receiving: true
    property bool ready: false
    onReceivingChanged: if (!receiving) ready = false
    property var incoming: null             // { session, from, files, size }
    property var landed: []                 // names of files that just arrived
    Process {
        id: serveProc
        running: root.receiving
        command: ["python3", "-I", root.helper, "serve"]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                var t = line.trim();
                if (t === "") return;
                var d;
                try { d = JSON.parse(t); } catch (e) { return; }
                if (d.event === "ready") { root.ready = true; }
                else if (d.event === "device") root.addPeer(d);
                else if (d.event === "ask") { root.incoming = d; if (root.bar) root.bar.playSound("pop", 0.8); win.visible = true; win.raise(); }
                else if (d.event === "accepted" || d.event === "declined") { root.incoming = null; }
                else if (d.event === "received") {
                    root.landed = root.landed.concat([d.file]).slice(-4);
                    landedT.restart();
                    if (root.bar) root.bar.playSound("tink", 0.7);
                    Quickshell.execDetached(["sh", "-c", "notify-send -a AirDrop 'AirDrop' \"$1 saved to Downloads\"", "sh", d.file]);
                }
            }
        }
    }
    Timer { id: landedT; interval: 6000; onTriggered: root.landed = [] }
    function answer(ok) {
        if (!incoming) return;
        serveProc.write((ok ? "accept " : "decline ") + incoming.session + "\n");
        incoming = null;
    }

    function scan() {
        if (scanning) return;
        scanning = true;
        scanDone.restart();
        if (serveProc.running) {
            // the receiver is already listening: a fresh hello is all that is needed, and every answer
            // arrives on the one stream (asking twice is what filled the radar with copies of this machine)
            serveProc.write("search\n");
            return;
        }
        discProc.running = false;
        discProc.command = ["python3", "-I", helper, "discover", "6"];
        discProc.running = true;
    }
    Timer { id: scanDone; interval: 6000; onTriggered: root.scanning = false }
    function addPeer(d) {
        var f = root.peers.slice();
        for (var i = 0; i < f.length; i++)
            if (f[i].fingerprint === d.fingerprint || (f[i].ip === d.ip && f[i].port === d.port)) {
                f[i].seen = Date.now();
                return;
            }
        d.state = "idle"; d.detail = d.deviceModel || d.ip; d.seen = Date.now();
        f.push(d);
        root.peers = f;
        if (root.bar) root.bar.playSound("pop", 0.3);
    }
    Process {
        id: discProc
        stdout: SplitParser {
            onRead: line => {
                var t = line.trim();
                if (t === "") return;
                try { root.addPeer(JSON.parse(t)); } catch (e) { }
            }
        }
        // A finished search used to replace the list with only what this one search found, which wiped the
        // devices the receiver had already heard from. Searching only ever adds now; a device drops off when
        // it has not been heard from for two minutes.
        onExited: {
            root.scanning = false;
            var keep = [], now = Date.now();
            for (var i = 0; i < root.peers.length; i++)
                if (!root.peers[i].seen || now - root.peers[i].seen < 120000) keep.push(root.peers[i]);
            if (keep.length !== root.peers.length) root.peers = keep;
        }
    }

    function peerIndex(fp) { for (var i = 0; i < peers.length; i++) if (peers[i].fingerprint === fp) return i; return -1; }
    function setPeer(fp, state, detail) {
        var i = peerIndex(fp);
        if (i < 0) return;
        var p = peers.slice();
        p[i] = Object.assign({}, p[i], { state: state, detail: detail });
        peers = p;
    }

    property string sendingTo: ""
    function sendTo(peer, files) {
        if (!files || files.length === 0) return;
        setPeer(peer.fingerprint, "sending", "Waiting…");
        sendingTo = peer.fingerprint;
        sendProc.running = false;
        // use the scheme the device announced (recent LocalSend builds are HTTPS); the helper falls back to the other
        sendProc.command = ["python3", "-I", helper, "send", peer.ip, String(peer.port),
                            "--protocol", peer.protocol === "https" ? "https" : "http"].concat(files);
        sendProc.running = true;
    }
    Process {
        id: sendProc
        stdout: SplitParser {
            onRead: line => {
                var t = line.trim();
                if (t === "") return;
                try {
                    var d = JSON.parse(t);
                    if (d.event === "asking") root.setPeer(root.sendingTo, "sending", "Waiting for them to accept…");
                    else if (d.event === "sending") root.setPeer(root.sendingTo, "sending", "Sending " + d.file);
                    else if (d.event === "done") { root.setPeer(root.sendingTo, "done", "Sent"); doneT.restart(); if (root.bar) root.bar.playSound("tink", 0.7); }
                    else if (d.event === "error") root.setPeer(root.sendingTo, "error", d.message === "declined" ? "Declined" : "Failed");
                } catch (e) { }
            }
        }
        onExited: if (exitCode !== 0) root.setPeer(root.sendingTo, "error", "Failed");
    }
    Timer { id: doneT; interval: 2400; onTriggered: { root.setPeer(root.sendingTo, "idle", ""); root.sendingTo = ""; } }

    // Files dropped on the window (rather than straight onto someone) wait here until you pick who gets them,
    // the way macOS holds a drag over the AirDrop sheet.
    property var pending: []
    property bool discMenu: false
    function dropUris(d) {
        var files = [];
        if (d.hasUrls) {
            for (var i = 0; i < d.urls.length; i++) {
                var u = String(d.urls[i]);
                if (u.indexOf("file://") !== 0) continue;
                try { files.push(decodeURIComponent(u.substring(7))); } catch (e) { files.push(u.substring(7)); }
            }
        } else if (d.hasText) {
            var lines = String(d.text).split(/[\r\n]+/);
            for (var j = 0; j < lines.length; j++) {
                var t = lines[j].trim();
                if (t === "") continue;
                if (t.indexOf("file://") === 0) { try { t = decodeURIComponent(t.substring(7)); } catch (e2) { t = t.substring(7); } }
                files.push(t);
            }
        }
        return files;
    }
    // clicking someone sends whatever is waiting, or asks you for files when nothing is
    function handOff(peer) {
        if (pending.length > 0) {
            var f = pending.slice();
            pending = [];
            sendTo(peer, f);
            return;
        }
        pick(peer);
    }

    // picking files: our own Finder, the way an Open sheet works on macOS; zenity only if Finder is missing
    property var pickFor: null
    function pick(peer) {
        pickFor = peer;
        if (hub && hub.finder && hub.finder.chooseFiles) {
            hub.finder.chooseFiles(function (files) {
                if (files && files.length > 0 && root.pickFor) root.sendTo(root.pickFor, files);
            }, "Send");
            return;
        }
        pickProc.running = false;
        pickProc.command = ["sh", "-c", "zenity --file-selection --multiple --separator='\\n' --title='Send with AirDrop' 2>/dev/null"];
        pickProc.running = true;
    }
    Process {
        id: pickProc
        stdout: StdioCollector {
            onStreamFinished: {
                var files = text.split("\n").filter(function (x) { return x.trim() !== ""; });
                if (files.length > 0 && root.pickFor) root.sendTo(root.pickFor, files);
            }
        }
    }

    function open() {
        win.visible = true; win.raise(); win.requestActivate();
        scan();
    }
    // "Share with AirDrop" from Finder: the files wait here and the next person you click gets them
    function stagePaths(list) {
        pending = (list || []).slice();
        open();
    }

    Window {
        id: win
        title: "AirDrop"
        width: 620; height: 500
        minimumWidth: 460; minimumHeight: 380
        visible: false
        color: "transparent"
        flags: Qt.Window | Qt.FramelessWindowHint
        onVisibleChanged: if (!visible) discProc.running = false

        QtObject {
            id: pal
            readonly property bool dark: root.darkMode
            property color bg: dark ? "#1E1E1E" : "#FFFFFF"
            Behavior on bg { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color text: dark ? "#F5F5F7" : "#1D1D1F"
            Behavior on text { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color text2: dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.5)
            Behavior on text2 { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color text3: dark ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(0, 0, 0, 0.28)
            Behavior on text3 { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color sep: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.09)
            Behavior on sep { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color border: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.2)
            Behavior on border { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color lightOff: dark ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.15)
            Behavior on lightOff { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
        }

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: pal.bg
            border.width: 1; border.color: pal.border
            clip: true
            DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
            MouseArea { x: parent.width - 8; y: parent.height - 8; width: 8; height: 8; z: 100; cursorShape: Qt.SizeFDiagCursor; onPressed: win.startSystemResize(Qt.BottomEdge | Qt.RightEdge) }

            // traffic lights
            Item {
                x: 17; y: 17; width: 58; height: 14; z: 20
                Row {
                    spacing: 8
                    Repeater {
                        model: [{ c: "#FF5F57", g: "×" }, { c: "#FEBC2E", g: "−" }, { c: "#28C840", g: "↗" }]
                        delegate: Rectangle {
                            required property var modelData
                            width: 14; height: 14; radius: 7
                            color: ((root.bar && root.bar.tlColorOnHover) ? tlMa.containsMouse : (win.active || tlMa.containsMouse)) ? modelData.c : pal.lightOff
                            Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.14)
                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData.g
                                font.pixelSize: 11; font.bold: true
                                color: Qt.rgba(0, 0, 0, 0.55)
                                opacity: (tlMa.containsMouse || (root.bar && root.bar.tlAlwaysSymbols)) ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }
                MouseArea {
                    id: tlMa; anchors.fill: parent; hoverEnabled: true
                    onClicked: mouse => { if (mouse.x < 22) win.visible = false; else if (mouse.x < 44) root.hub && root.hub.minimizeWindow ? root.hub.minimizeWindow(win.title) : win.showMinimized(); else win.visibility === Window.FullScreen ? win.showNormal() : win.showFullScreen(); }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter; y: 16
                text: "AirDrop"; color: pal.text; font.family: root.fam; font.pixelSize: 14; font.weight: Font.DemiBold
            }

            // ── the radar ──
            Item {
                id: radar
                anchors.fill: parent
                anchors.topMargin: 48
                anchors.bottomMargin: 64

                // rings that breathe outwards, like the real thing
                Repeater {
                    model: 3
                    delegate: Rectangle {
                        required property int index
                        anchors.centerIn: parent
                        property real t: 0
                        width: (0.35 + t * 0.75) * Math.min(radar.width, radar.height)
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.rgba(pal.text.r, pal.text.g, pal.text.b, 0.10 * (1 - t))
                        NumberAnimation on t {
                            from: 0; to: 1; duration: 3600; loops: Animation.Infinite
                            running: win.visible
                        }
                        Component.onCompleted: t = index / 3
                    }
                }

                // nobody around yet
                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    visible: root.peers.length === 0
                    opacity: root.peers.length === 0 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 300 } }
                    Text {
                        id: emptyTitle
                        anchors.horizontalCenter: parent.horizontalCenter
                        property int dots: 0
                        Timer { interval: 420; repeat: true; running: root.scanning; onTriggered: emptyTitle.dots = (emptyTitle.dots + 1) % 4 }
                        text: root.scanning ? ("Looking for devices" + "...".substring(0, dots)) : "No one nearby"
                        color: pal.text; font.family: root.fam; font.pixelSize: 15; font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 320; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                        text: "Open LocalSend on the other device and keep it on the same network. Both will appear to each other."
                        color: pal.text3; font.family: root.fam; font.pixelSize: 12
                    }
                }

                // the devices, arranged around the centre
                Repeater {
                    model: root.peers
                    delegate: Item {
                        id: peerItem
                        required property var modelData
                        required property int index
                        readonly property int n: Math.max(1, root.peers.length)
                        readonly property real ang: -Math.PI / 2 + index * (Math.PI * 2 / n)
                        readonly property real rad: n === 1 ? 0 : Math.min(radar.width, radar.height) * 0.3
                        width: 108; height: 116
                        x: radar.width / 2 - width / 2 + Math.cos(ang) * rad
                        y: radar.height / 2 - height / 2 + Math.sin(ang) * rad
                        Behavior on x { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
                        Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
                        opacity: 0
                        Component.onCompleted: fadeIn.start()
                        NumberAnimation { id: fadeIn; target: peerItem; property: "opacity"; from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic }

                        Rectangle {
                            id: avatar
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 4
                            width: 74; height: 74; radius: 37
                            color: pMa.containsMouse || drop.containsDrag ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22) : Qt.rgba(pal.text.r, pal.text.g, pal.text.b, 0.10)
                            border.width: drop.containsDrag ? 2 : 1
                            border.color: drop.containsDrag ? root.accent : Qt.rgba(pal.text.r, pal.text.g, pal.text.b, 0.18)
                            Behavior on color { ColorAnimation { duration: 180 } }
                            scale: pMa.pressed ? 0.95 : (drop.containsDrag ? 1.06 : 1)
                            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutQuint } }

                            ADGlyph {
                                anchors.centerIn: parent
                                width: 34; height: 34
                                kind: peerItem.modelData.deviceType === "mobile" ? "phone" : (peerItem.modelData.deviceType === "web" ? "globe" : "laptop")
                                color: pal.text
                                opacity: peerItem.modelData.state === "sending" ? 0.25 : 1
                                Behavior on opacity { NumberAnimation { duration: 220 } }
                            }
                            // the progress ring while a transfer runs
                            Canvas {
                                id: ring
                                anchors.fill: parent
                                visible: peerItem.modelData.state === "sending" || peerItem.modelData.state === "done"
                                property real sweep: 0
                                property bool done: peerItem.modelData.state === "done"
                                onSweepChanged: requestPaint()
                                onDoneChanged: requestPaint()
                                onPaint: {
                                    var c = getContext("2d"); c.reset();
                                    c.lineWidth = 3; c.lineCap = "round";
                                    c.strokeStyle = root.accent;
                                    if (done) {
                                        c.beginPath(); c.arc(width / 2, height / 2, width / 2 - 2, 0, Math.PI * 2); c.stroke();
                                        c.beginPath(); c.moveTo(width * 0.33, height * 0.52); c.lineTo(width * 0.45, height * 0.64); c.lineTo(width * 0.68, height * 0.37); c.stroke();
                                    } else {
                                        c.beginPath(); c.arc(width / 2, height / 2, width / 2 - 2, sweep, sweep + Math.PI * 0.6); c.stroke();
                                    }
                                }
                                NumberAnimation on sweep { from: 0; to: Math.PI * 2; duration: 1100; loops: Animation.Infinite; running: ring.visible && !ring.done }
                            }
                            DropArea {
                                id: drop
                                anchors.fill: parent
                                onEntered: d => d.accept(Qt.CopyAction)
                                onDropped: d => {
                                    var files = root.dropUris(d);
                                    if (files.length) { root.pending = []; root.sendTo(peerItem.modelData, files); }
                                }
                            }
                            MouseArea {
                                id: pMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.handOff(peerItem.modelData)
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 82
                            width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                            text: peerItem.modelData.alias
                            color: pal.text; font.family: root.fam; font.pixelSize: 12; font.weight: Font.Medium
                        }
                        MorphText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 98
                            width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                            animateWidth: false; duration: 320
                            text: peerItem.modelData.detail || ""
                            color: peerItem.modelData.state === "error" ? "#FF453A" : pal.text3
                            font.family: root.fam; font.pixelSize: 11
                        }
                    }
                }
            }

            // ── someone is sending you something ──
            Item {
                id: ask
                anchors.fill: parent
                z: 40
                visible: opacity > 0.01
                opacity: root.incoming ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.45); MouseArea { anchors.fill: parent } }
                Rectangle {
                    anchors.centerIn: parent
                    width: 320; height: 196; radius: 14
                    color: pal.dark ? "#232325" : "#FFFFFF"
                    border.width: 1; border.color: pal.sep
                    scale: root.incoming ? 1 : 0.94
                    Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutQuint } }
                    Column {
                        anchors.centerIn: parent
                        width: parent.width - 36
                        spacing: 8
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 52; height: 52; radius: 26
                            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                            ADGlyph { anchors.centerIn: parent; width: 26; height: 26; kind: "phone"; color: root.accent }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.incoming ? root.incoming.from + " wants to send" : ""
                            color: pal.text; font.family: root.fam; font.pixelSize: 14; font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width; horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideMiddle; maximumLineCount: 2; wrapMode: Text.Wrap
                            text: root.incoming ? root.incoming.files.join(", ") : ""
                            color: pal.text2; font.family: root.fam; font.pixelSize: 12
                        }
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 10
                            topPadding: 6
                            Rectangle {
                                width: 110; height: 30; radius: 8
                                color: pal.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.07)
                                Text { anchors.centerIn: parent; text: "Decline"; color: pal.text; font.family: root.fam; font.pixelSize: 12 }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.answer(false) }
                            }
                            Rectangle {
                                width: 110; height: 30; radius: 8
                                color: root.accent
                                Text { anchors.centerIn: parent; text: "Accept"; color: "white"; font.family: root.fam; font.pixelSize: 12; font.weight: Font.DemiBold }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.answer(true) }
                            }
                        }
                    }
                }
            }
            // what just arrived
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom; anchors.bottomMargin: 76
                width: Math.min(parent.width - 40, landedText.implicitWidth + 28); height: 28; radius: 14
                color: pal.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.07)
                visible: opacity > 0.01
                opacity: root.landed.length > 0 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 300 } }
                Text {
                    id: landedText
                    anchors.centerIn: parent
                    text: root.landed.length > 0 ? "Saved to Downloads: " + root.landed.join(", ") : ""
                    color: pal.text2; font.family: root.fam; font.pixelSize: 11
                }
            }

            // clicking anywhere else closes the discoverability pop-up
            MouseArea {
                anchors.fill: parent
                z: 8
                visible: root.discMenu
                enabled: root.discMenu
                acceptedButtons: Qt.AllButtons
                onPressed: root.discMenu = false
            }

            // Drop files anywhere on the window: they wait, and the next person you click gets them.
            DropArea {
                id: winDrop
                anchors.fill: parent
                z: -1                       // behind the peers, so dropping straight onto someone still wins
                onEntered: d => d.accept(Qt.CopyAction)
                onDropped: d => {
                    var files = root.dropUris(d);
                    if (files.length) root.pending = files;
                }
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: 6
                z: 6
                radius: 12
                color: "transparent"
                border.width: 2
                border.color: root.accent
                opacity: winDrop.containsDrag ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }

            // ── the footer ──
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width; height: 64
                color: "transparent"
                z: 7
                Rectangle { width: parent.width; height: 1; color: pal.sep }
                Text {
                    x: 20; y: 14
                    text: "Allow me to be discovered by:"
                    color: pal.text2; font.family: root.fam; font.pixelSize: 12
                }
                // the macOS pop-up: the value, a chevron that turns, and a little menu that springs open
                Rectangle {
                    id: discPill
                    x: 14; y: 28
                    width: discLabel.implicitWidth + 34; height: 22; radius: 6
                    color: discMa.containsMouse || root.discMenu ? pal.sep : "transparent"
                    Behavior on color { ColorAnimation { duration: 140 } }
                    Text {
                        id: discLabel
                        x: 6; anchors.verticalCenter: parent.verticalCenter
                        text: root.receiving ? (root.ready ? "Everyone on this network" : "Starting\u2026") : "No one"
                        color: pal.text; font.family: root.fam; font.pixelSize: 12; font.weight: Font.DemiBold
                    }
                    ADGlyph {
                        anchors.right: parent.right; anchors.rightMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10; height: 10
                        kind: "chev"; color: pal.text2
                        rotation: root.discMenu ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                    }
                    MouseArea {
                        id: discMa
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.discMenu = !root.discMenu
                    }
                }
                Rectangle {
                    id: discPop
                    x: 14
                    y: discPill.y - height - 6
                    z: 20
                    width: 204; height: discCol.height + 10
                    radius: 10
                    color: pal.dark ? Qt.rgba(0.17, 0.17, 0.18, 0.98) : Qt.rgba(0.99, 0.99, 1, 0.99)
                    border.width: 1; border.color: pal.sep
                    visible: opacity > 0.01
                    opacity: root.discMenu ? 1 : 0
                    scale: root.discMenu ? 1 : 0.94
                    transformOrigin: Item.BottomLeft
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                    layer.enabled: true
                    layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.9; shadowOpacity: 0.35; shadowVerticalOffset: 6 }
                    Column {
                        id: discCol
                        y: 5; width: parent.width
                        Repeater {
                            model: [{ t: "No one", on: false }, { t: "Everyone on this network", on: true }]
                            delegate: Item {
                                id: dRow
                                required property var modelData
                                width: parent.width; height: 26
                                readonly property bool picked: root.receiving === dRow.modelData.on
                                Rectangle {
                                    visible: dMa.containsMouse
                                    x: 5; y: 1; width: parent.width - 10; height: 24; radius: 5
                                    color: root.accent
                                }
                                ADGlyph {
                                    x: 12; anchors.verticalCenter: parent.verticalCenter
                                    width: 11; height: 11
                                    kind: "tick"
                                    color: dMa.containsMouse ? "white" : pal.text
                                    opacity: dRow.picked ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 160 } }
                                }
                                Text {
                                    x: 30; anchors.verticalCenter: parent.verticalCenter
                                    text: dRow.modelData.t
                                    color: dMa.containsMouse ? "white" : pal.text
                                    font.family: root.fam; font.pixelSize: 12
                                }
                                MouseArea {
                                    id: dMa
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.receiving = dRow.modelData.on; root.discMenu = false; }
                                }
                            }
                        }
                    }
                }
                // what is waiting to be sent, and a way to drop it again
                Rectangle {
                    anchors.right: parent.right; anchors.rightMargin: 136
                    anchors.verticalCenter: parent.verticalCenter
                    height: 28; radius: 14
                    width: pendText.implicitWidth + 44
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
                    border.width: 1; border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.5)
                    opacity: root.pending.length > 0 ? 1 : 0
                    visible: opacity > 0.01
                    scale: root.pending.length > 0 ? 1 : 0.9
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                    Text {
                        id: pendText
                        x: 12; anchors.verticalCenter: parent.verticalCenter
                        text: root.pending.length === 1 ? "1 file ready \u2014 pick someone"
                                                        : root.pending.length + " files ready \u2014 pick someone"
                        color: root.accent; font.family: root.fam; font.pixelSize: 11; font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u00D7"; color: root.accent; font.family: root.fam; font.pixelSize: 15
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.pending = []
                        }
                    }
                }
                Rectangle {
                    anchors.right: parent.right; anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    width: 104; height: 28; radius: 8
                    color: scanMa.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.9) : root.accent
                    opacity: root.scanning ? 0.55 : 1
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    Text {
                        anchors.centerIn: parent
                        text: root.scanning ? "Searching…" : "Search Again"
                        color: "white"; font.family: root.fam; font.pixelSize: 12; font.weight: Font.DemiBold
                    }
                    MouseArea { id: scanMa; anchors.fill: parent; hoverEnabled: true; enabled: !root.scanning; cursorShape: Qt.PointingHandCursor; onClicked: root.scan() }
                }
            }
        }
    }

    component ADGlyph: Canvas {
        id: ag
        property string kind: ""
        property color color: "white"
        antialiasing: true
        onKindChanged: requestPaint()
        onColorChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            var c = getContext("2d"); c.reset();
            var s = width / 16; c.scale(s, s);
            c.strokeStyle = color; c.fillStyle = color; c.lineWidth = 1.3; c.lineJoin = "round"; c.lineCap = "round";
            if (kind === "laptop") {
                c.beginPath(); c.roundedRect(2.6, 3, 10.8, 7.6, 1.2, 1.2); c.stroke();
                c.beginPath(); c.moveTo(1, 12.4); c.lineTo(15, 12.4); c.stroke();
            } else if (kind === "phone") {
                c.beginPath(); c.roundedRect(4.6, 1.8, 6.8, 12.4, 1.6, 1.6); c.stroke();
                c.beginPath(); c.moveTo(7.2, 12.4); c.lineTo(8.8, 12.4); c.stroke();
            } else if (kind === "chev") {
                c.lineWidth = 1.7;
                c.beginPath(); c.moveTo(3.6, 6.2); c.lineTo(8, 10.4); c.lineTo(12.4, 6.2); c.stroke();
            } else if (kind === "tick") {
                c.lineWidth = 1.9;
                c.beginPath(); c.moveTo(3, 8.4); c.lineTo(6.4, 11.8); c.lineTo(13, 4.4); c.stroke();
            } else {
                c.beginPath(); c.arc(8, 8, 6.2, 0, Math.PI * 2); c.stroke();
                c.beginPath(); c.moveTo(1.8, 8); c.lineTo(14.2, 8); c.stroke();
                c.beginPath(); c.ellipse(4.8, 1.8, 6.4, 12.4); c.stroke();
            }
        }
    }
}
