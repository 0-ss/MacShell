//0.4.2// About This Linux — the "About This Mac" window for MacShell.
//
//   qs -c MacShell ipc call about open | close | toggle        (the Apple menu's "About This Linux" opens it too)
//
// Everything shown comes from the running system (assets/about-info.sh): the computer's model from the firmware (DMI),
// the processor, graphics cards, memory, the size of the disk holding "/", the kernel and the distribution.
//
// Logo: your distribution's own logo (os-release LOGO=, found through the icon theme). To show a Linux logo of your own,
// put it at  assets/linux-logo.svg  (or .png)  and it is used instead.
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "I18n.js" as I18n
import "Fonts.js" as Fonts

Scope {
    id: root
    property var hub: null
    property var dock: hub ? hub.dock : null
    property var bar: hub ? hub.bar : null
    property bool darkMode: bar ? bar.darkMode : (dock ? dock.darkMode : true)

    Connections {
        target: root.bar
        function onDarkModeChanged() { if (root.bar) root.darkMode = root.bar.darkMode; }
    }
    Connections {
        target: root.dock
        function onDarkModeChanged() { if (!root.bar && root.dock) root.darkMode = root.dock.darkMode; }
    }

    readonly property string fam: dock ? dock.fontFamily : "Open Runde"
    readonly property string boldFontFamily: hub && hub.boldFontFamily ? hub.boldFontFamily : "Open Runde Semibold"
    // Open Runde: bold text uses its Semibold face; another selected font keeps its own family (and real bold weight)
    function fontForWeight(weight, regularFamily) { return (Number(weight) >= Font.DemiBold && regularFamily === "Open Runde") ? boldFontFamily : regularFamily; }

    property var info: ({})
    readonly property string scriptPath: decodeURIComponent(String(Qt.resolvedUrl("assets/about-info.sh")).replace(/^file:\/\//, ""))

    function syncTheme() {
        if (bar) darkMode = bar.darkMode;
        else if (dock) darkMode = dock.darkMode;
    }

    function open() { syncTheme(); win.visible = true; win.raise(); win.requestActivate(); }
    function close() { win.visible = false; }
    function toggle() { if (win.visible) close(); else open(); }

    function parse(text) {
        var o = {}, ls = text.split("\n");
        for (var i = 0; i < ls.length; i++) {
            var p = ls[i].indexOf("=");
            if (p > 0) o[ls[i].substring(0, p)] = ls[i].substring(p + 1);
        }
        info = o;
    }
    function refresh() { if (!infoProc.running) infoProc.running = true; }
    Process {
        id: infoProc
        command: ["sh", root.scriptPath]
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
    }

    // the spec rows: [label, value, small grey line under it]
    readonly property var rows: {
        var o = info, r = [];
        if (!o.cpu) return r;
        r.push({ k: I18n.tr("Processor"), v: o.cpu, s: o.cpusub || "" });
        r.push({ k: I18n.tr("Graphics"), v: (o.gpu || "").split("|").join("\n"), s: "" });
        r.push({ k: I18n.tr("Memory"), v: o.mem || "", s: "" });
        r.push({ k: I18n.tr("Storage"), v: o.disk || "", s: o.disksub || "" });
        r.push({ k: I18n.tr("Kernel"), v: o.kernel || "", s: "" });
        r.push({ k: o.osname || "Linux", v: o.osver || "", s: "" });
        return r;
    }

    // the logo: a file the user supplied > the distribution's icon > a plain drawn fallback
    readonly property string distroLogo: {
        var names = [info.logo, (info.osid || "") + "-logo", info.osid, "distributor-logo", "start-here"];
        for (var i = 0; i < names.length; i++) {
            if (!names[i]) continue;
            var p = Quickshell.iconPath(names[i], true);
            if (p) return p;
        }
        return "";
    }

    Window {
        id: win
        title: "About This Linux"
        readonly property real uiS: root.bar ? root.bar.uiScale : 1      // UI scale (Settings → Menu Bar)
        readonly property int wantH: Math.round((Math.ceil(content.implicitHeight) + 40 + 26) * uiS)
        width: Math.round(300 * uiS)
        height: wantH
        minimumWidth: width; maximumWidth: width
        minimumHeight: wantH; maximumHeight: wantH
        visible: false
        color: "transparent"
        flags: Qt.Window | Qt.FramelessWindowHint

        onVisibleChanged: if (visible) { root.refresh(); floatTries = 0; floatTimer.restart(); }
        property int floatTries: 0
        // the size changed while the window is open (UI scale, or the content grew): send Hyprland the new size again
        onWidthChanged: if (visible) { floatTries = 0; floatTimer.restart(); }
        onHeightChanged: if (visible) { floatTries = 0; floatTimer.restart(); }
        Timer {
            id: floatTimer
            interval: 60
            repeat: true
            onTriggered: {
                // the compositor maps the window a moment after it becomes visible: send the dispatches a few times
                var sel = 'window = "title:^(' + win.title + ')$"';
                Hyprland.dispatch('hl.dsp.window.float({ action = "enable", ' + sel + ' })');
                Hyprland.dispatch('hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", ' + sel + ' })');
                // this window draws its own macOS-style edge: no Hyprland border, and Hyprland's corner rounding
                // (also used for its shadow and blur) matches the window's own radius
                Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "border_size", value = "0", ' + sel + ' })');
                Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "rounding", value = "' + Math.round(frame.radius * win.uiS) + '", ' + sel + ' })');
                if (win.floatTries >= 2) {
                    // Hyprland keeps the size the window was first mapped with (and its blur / shadow region): force the scaled size
                    Hyprland.dispatch('hl.dsp.window.resize({ x = ' + win.width + ', y = ' + win.height + ', "exact", ' + sel + ' })');
                    Hyprland.dispatch('hl.dsp.window.center({ ' + sel + ' })');
                }
                if (++win.floatTries >= 12) stop();
            }
        }
        Shortcut { sequences: ["Escape", "Ctrl+W"]; onActivated: win.visible = false }

        QtObject {
            id: pal
            readonly property bool dark: root.darkMode
            readonly property color bg: dark ? Qt.rgba(0.17, 0.17, 0.18, 0.97) : Qt.rgba(0.88, 0.87, 0.86, 0.97)
            readonly property color text: dark ? "#F5F5F7" : "#1D1D1F"
            readonly property color text2: dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.5)
            readonly property color text3: dark ? Qt.rgba(1, 1, 1, 0.38) : Qt.rgba(0, 0, 0, 0.42)
            readonly property color border: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.18)
            readonly property color edgeOuter: Qt.rgba(1, 1, 1, 0.50)     // thin dark line on the outside
            readonly property color edgeInner: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.65)      // soft highlight just inside it
            function lightBorder(active, c) { return active ? Qt.darker(c, dark ? 1.12 : 1.22) : "transparent"; }
            readonly property color lightOff: dark ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.15)
            readonly property color btn: dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.75)
            readonly property color btnDown: dark ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.5)
        }

        Rectangle {
            id: frame
            // drawn at a scaled size: the window content shrinks with the UI scale, the window itself shrinks to match
            width: parent.width / win.uiS; height: parent.height / win.uiS
            scale: win.uiS; transformOrigin: Item.TopLeft
            radius: 18
            color: pal.bg
            border.width: 1; border.color: pal.edgeOuter
            clip: true

            // inner highlight: together with the outer line this is the two-tone edge macOS windows have
            Rectangle {
                anchors.fill: parent; anchors.margins: 1
                radius: frame.radius - 1
                color: "transparent"
                border.width: 1; border.color: pal.edgeInner
                z: 50
            }

            // drag anywhere on the window
            DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }

            // traffic lights: only Close is active, like the About window on a Mac
            Item {
                x: 15; y: 12
                width: 58; height: 14
                Row {
                    scale: 0.93; transformOrigin: Item.TopLeft      // a touch smaller
                    spacing: 8
                    Repeater {
                        model: [{ c: "#FF5F57", on: true }, { c: "#FEBC2E", on: false }, { c: "#28C840", on: false }]
                        delegate: Rectangle {
                            required property var modelData
                            width: 14; height: 14; radius: 7
                            color: (modelData.on && (win.active || tl.containsMouse)) ? modelData.c : pal.lightOff
                            border.width: 1; border.color: pal.lightBorder(modelData.on && (win.active || tl.containsMouse), modelData.c)
                            Canvas {
                                anchors.fill: parent
                                visible: tl.containsMouse && parent.modelData.on
                                onVisibleChanged: if (visible) requestPaint()
                                onPaint: {
                                    var ctx = getContext("2d");
                                    ctx.clearRect(0, 0, width, height);
                                    ctx.strokeStyle = "rgba(0,0,0,0.58)";
                                    ctx.lineWidth = 1.2;
                                    ctx.lineCap = "round";
                                    ctx.beginPath();
                                    ctx.moveTo(4.9, 4.9); ctx.lineTo(9.1, 9.1);
                                    ctx.moveTo(9.1, 4.9); ctx.lineTo(4.9, 9.1);
                                    ctx.stroke();
                                }
                            }
                        }
                    }
                }
                MouseArea { id: tl; anchors.fill: parent; hoverEnabled: true; onClicked: mouse => { if (mouse.x < 22) win.visible = false; } }
            }

            Column {
                id: content
                x: 20; y: 40
                width: parent.width - 40
                spacing: 0

                // ── logo ──
                Item {
                    width: parent.width; height: 118
                    Image {
                        id: userLogo
                        anchors.centerIn: parent
                        width: 112; height: 112
                        visible: status === Image.Ready
                        source: root.info.userlogo ? "file://" + root.info.userlogo : ""
                        sourceSize.width: 224; sourceSize.height: 224
                        fillMode: Image.PreserveAspectFit
                        smooth: true; mipmap: true
                    }
                    Image {
                        id: distroImg
                        anchors.centerIn: parent
                        width: 112; height: 112
                        visible: !userLogo.visible && status === Image.Ready
                        source: userLogo.visible ? "" : root.distroLogo
                        sourceSize.width: 224; sourceSize.height: 224
                        fillMode: Image.PreserveAspectFit
                        smooth: true; mipmap: true
                    }
                    // last resort: a plain terminal window
                    Rectangle {
                        anchors.centerIn: parent
                        visible: !userLogo.visible && !distroImg.visible
                        width: 108; height: 78; radius: 9
                        color: "transparent"
                        border.width: 4; border.color: pal.text2
                        Text { anchors.centerIn: parent; text: ">_"; font.family: Fonts.forWeight(font.weight, root.fam); font.pixelSize: 30; font.bold: true; color: pal.text2 }
                    }
                }
                Item { width: 1; height: 20 }

                // ── name ──
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: "MacShell"
                    color: pal.text
                    font.family: root.fontForWeight(font.weight, root.fam); font.pixelSize: 24; font.weight: Font.Bold
                }
                Item { width: 1; height: 3 }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: root.info.sub || ""
                    color: pal.text3
                    font.family: root.fontForWeight(font.weight, root.fam); font.pixelSize: 12
                }
                Item { width: 1; height: 22 }

                // ── specs ──
                Column {
                    width: parent.width
                    spacing: 5
                    Repeater {
                        model: root.rows
                        delegate: Row {
                            required property var modelData
                            width: parent.width
                            spacing: 8
                            Text {
                                width: 96
                                horizontalAlignment: Text.AlignRight
                                wrapMode: Text.Wrap
                                text: modelData.k
                                color: pal.text
                                font.family: root.fontForWeight(font.weight, root.fam); font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                            Column {
                                width: parent.width - 104
                                Text {
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                    text: modelData.v
                                    color: pal.text
                                    font.family: root.fontForWeight(font.weight, root.fam); font.pixelSize: 12
                                }
                                Text {
                                    visible: modelData.s !== ""
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                    text: modelData.s
                                    color: pal.text2
                                    font.family: root.fontForWeight(font.weight, root.fam); font.pixelSize: 11
                                }
                            }
                        }
                    }
                }
                Item { width: 1; height: 18 }

                // ── More Info… ──
                Item {
                    width: parent.width; height: 24
                    Rectangle {
                        anchors.centerIn: parent
                        width: moreTxt.implicitWidth + 30; height: 24; radius: 7
                        color: moreMa.pressed ? pal.btnDown : pal.btn
                        border.width: 1; border.color: pal.border
                        Text { id: moreTxt; anchors.centerIn: parent; text: I18n.tr("More Info\u2026"); color: pal.text; font.family: root.fontForWeight(font.weight, root.fam); font.pixelSize: 12 }
                        MouseArea {
                            id: moreMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var cmd = (root.bar ? root.bar.terminal : "kitty") + " -e sh -c 'fastfetch || neofetch; echo; read -p \"Press Enter\" _'";
                                Quickshell.execDetached(["sh", "-c", cmd]);
                            }
                        }
                    }
                }
                Item { width: 1; height: 20 }

                // ── links and legal ──
                Item {
                    width: parent.width; height: siteTxt.implicitHeight
                    Text {
                        id: siteTxt
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: (root.info.osname || "Linux") + " " + I18n.tr("Website")
                        color: pal.text2
                        font.family: root.fontForWeight(font.weight, root.fam); font.pixelSize: 11; font.underline: true
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["xdg-open", root.info.home || "https://www.kernel.org"]) }
                    }
                }
                Item { width: 1; height: 10 }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: "Linux® is a registered trademark of Linus Torvalds.\nMacShell 0.4.2"
                    color: pal.text3
                    font.family: root.fontForWeight(font.weight, root.fam); font.pixelSize: 10
                    lineHeight: 1.1
                }
            }
        }
    }
}
