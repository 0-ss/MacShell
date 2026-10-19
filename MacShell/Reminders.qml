// Reminders — the macOS Reminders window: a sidebar of smart lists, a big title and a list you can
// type into. It edits the same ~/.config/macshell/reminders.md the desktop widget shows, so the two
// always agree.
//
//   qs -c MacShell ipc call reminders open
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property var hub: null
    readonly property var dock: hub ? hub.dock : null
    readonly property var bar: hub ? hub.bar : null
    readonly property var wid: hub ? hub.widgets : null
    readonly property string fam: dock ? dock.fontFamily : "Inter Variable"
    readonly property bool darkMode: dock ? dock.darkMode : true
    property color accent: dock ? dock.accent : "#0A84FF"
    Behavior on accent { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }

    // All / Completed, and the one that is showing
    property string list: "all"
    readonly property var all: wid ? wid.reminders : []
    readonly property var shown: {
        var a = root.all, out = [];
        for (var i = 0; i < a.length; i++) {
            if (root.list === "done" && !a[i].done) continue;
            if (root.list === "all" && a[i].done) continue;
            out.push(a[i]);
        }
        return out;
    }
    readonly property int openCount: {
        var a = root.all, n = 0;
        for (var i = 0; i < a.length; i++) if (!a[i].done) n++;
        return n;
    }
    readonly property int doneCount: all.length - openCount

    function open() { win.visible = true; win.raise(); win.requestActivate(); }

    IpcHandler {
        target: "reminders"
        function open() { root.open(); }
        function add(text: string) { if (root.wid) root.wid.addReminder(text); }
    }

    Window {
        id: win
        title: "Reminders"
        width: 720; height: 480
        minimumWidth: 520; minimumHeight: 320
        visible: false
        color: "transparent"
        flags: Qt.Window | Qt.FramelessWindowHint

        property real arrive: 0
        onVisibleChanged: if (visible) { arrive = 0; arriveAnim.restart(); }
        NumberAnimation { id: arriveAnim; target: win; property: "arrive"; from: 0; to: 1; duration: 420; easing.type: Easing.OutQuint }

        QtObject {
            id: pal
            readonly property bool dark: root.darkMode
            property color bg: dark ? "#1E1E1E" : "#FFFFFF"
            Behavior on bg { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color side: dark ? "#2A2A2C" : "#F2F2F4"
            Behavior on side { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color text: dark ? "#F5F5F7" : "#1D1D1F"
            Behavior on text { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color text2: dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.5)
            Behavior on text2 { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color sep: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.09)
            Behavior on sep { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color hover: dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.05)
            Behavior on hover { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
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
            opacity: Math.min(1, win.arrive * 1.6)
            scale: 0.96 + 0.04 * win.arrive

            MouseArea { x: parent.width - 8; y: parent.height - 8; width: 8; height: 8; z: 100; cursorShape: Qt.SizeFDiagCursor; onPressed: win.startSystemResize(Qt.BottomEdge | Qt.RightEdge) }
            MouseArea { x: parent.width - 5; y: 10; width: 5; height: parent.height - 20; z: 100; cursorShape: Qt.SizeHorCursor; onPressed: win.startSystemResize(Qt.RightEdge) }
            MouseArea { x: 10; y: parent.height - 5; width: parent.width - 20; height: 5; z: 100; cursorShape: Qt.SizeVerCursor; onPressed: win.startSystemResize(Qt.BottomEdge) }

            // ── sidebar ──
            Rectangle {
                id: side
                width: 190; height: parent.height
                color: pal.side
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: pal.sep }
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }

                Item {
                    x: 17; y: 17; width: 58; height: 14
                    Row {
                        spacing: 8
                        Repeater {
                            model: [{ c: "#FF5F57", g: "×" }, { c: "#FEBC2E", g: "−" }, { c: "#28C840", g: "↗" }]
                            delegate: Rectangle {
                                required property var modelData
                                width: 14; height: 14; radius: 7
                                color: ((root.bar && root.bar.tlColorOnHover) ? tlMa.containsMouse : (win.active || tlMa.containsMouse)) ? modelData.c : pal.lightOff
                                border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.14)
                                Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                Text {
                                    anchors.centerIn: parent
                                    text: parent.modelData.g
                                    font.pixelSize: 11; font.bold: true
                                    color: Qt.rgba(0, 0, 0, 0.55)
                                    opacity: (tlMa.containsMouse || (root.bar && root.bar.tlAlwaysSymbols)) ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                }
                            }
                        }
                    }
                    MouseArea {
                        id: tlMa
                        anchors.fill: parent; anchors.margins: -3; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (mouse.x < 25) win.visible = false;
                            else if (mouse.x < 47) root.hub && root.hub.minimizeWindow ? root.hub.minimizeWindow(win.title) : win.showMinimized();
                            else win.visibility === Window.FullScreen ? win.showNormal() : win.showFullScreen();
                        }
                    }
                }

                Column {
                    x: 10; y: 52; width: parent.width - 20
                    spacing: 2
                    Repeater {
                        model: [{ k: "all", t: "Reminders", c: "#0A84FF", g: "list" }, { k: "done", t: "Completed", c: "#8E8E93", g: "check" }]
                        delegate: Rectangle {
                            id: srow
                            required property var modelData
                            width: parent.width; height: 30; radius: 7
                            readonly property bool on: root.list === modelData.k
                            color: on ? root.accent : (sMa.containsMouse ? pal.hover : "transparent")
                            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            Rectangle {
                                x: 7; anchors.verticalCenter: parent.verticalCenter
                                width: 19; height: 19; radius: 9.5
                                color: srow.on ? Qt.rgba(1, 1, 1, 0.25) : srow.modelData.c
                                Behavior on color { ColorAnimation { duration: 150 } }
                                RGlyph { anchors.centerIn: parent; width: 11; height: 11; kind: srow.modelData.g; color: "white" }
                            }
                            Text {
                                x: 34; anchors.verticalCenter: parent.verticalCenter
                                text: srow.modelData.t
                                color: srow.on ? "white" : pal.text
                                font.family: root.fam; font.pixelSize: 13; font.weight: Font.Medium
                            }
                            Text {
                                anchors.right: parent.right; anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: srow.modelData.k === "all" ? root.openCount : root.doneCount
                                color: srow.on ? "white" : pal.text2
                                font.family: root.fam; font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                            MouseArea { id: sMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.list = srow.modelData.k }
                        }
                    }
                }
            }

            // ── the list ──
            Item {
                x: side.width; width: parent.width - side.width; height: parent.height
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }

                Text {
                    id: bigTitle
                    x: 26; y: 24
                    text: root.list === "done" ? "Completed" : "Reminders"
                    color: root.list === "done" ? pal.text2 : root.accent
                    font.family: root.fam; font.pixelSize: 26; font.weight: Font.Bold
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 56
                    anchors.verticalCenter: bigTitle.verticalCenter
                    text: root.shown.length
                    color: pal.text2
                    font.family: root.fam; font.pixelSize: 22; font.weight: Font.Bold
                }
                // + new reminder
                Rectangle {
                    id: addBtn
                    anchors.right: parent.right; anchors.rightMargin: 20
                    anchors.verticalCenter: bigTitle.verticalCenter
                    width: 26; height: 26; radius: 13
                    color: addMa.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18) : "transparent"
                    Behavior on color { ColorAnimation { duration: 150 } }
                    rotation: list.adding ? 45 : 0
                    Behavior on rotation { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                    scale: addMa.pressed ? 0.88 : 1
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
                    Rectangle { anchors.centerIn: parent; width: 13; height: 2; radius: 1; color: root.accent }
                    Rectangle { anchors.centerIn: parent; width: 2; height: 13; radius: 1; color: root.accent }
                    MouseArea {
                        id: addMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { list.adding = !list.adding; if (list.adding) newInput.forceActiveFocus(); }
                    }
                }

                Rectangle { x: 26; y: 64; width: parent.width - 46; height: 1; color: pal.sep }

                Flickable {
                    id: list
                    property bool adding: false
                    property int editingLine: -1
                    x: 14; y: 72
                    width: parent.width - 28; height: parent.height - 84
                    contentHeight: col.height + 20
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: col
                        width: parent.width
                        spacing: 0

                        // the new-reminder row drops in from the top
                        Item {
                            width: parent.width
                            height: list.adding ? 36 : 0
                            clip: true
                            opacity: list.adding ? 1 : 0
                            Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                            Behavior on opacity { NumberAnimation { duration: 220 } }
                            Rectangle {
                                x: 12; anchors.verticalCenter: parent.verticalCenter
                                width: 17; height: 17; radius: 8.5
                                color: "transparent"; border.width: 1.6; border.color: pal.text2
                            }
                            TextInput {
                                id: newInput
                                x: 40; width: parent.width - 52
                                anchors.verticalCenter: parent.verticalCenter
                                color: pal.text; font.family: root.fam; font.pixelSize: 14
                                selectByMouse: true
                                onAccepted: { if (root.wid) root.wid.addReminder(text); text = ""; }
                                Keys.onEscapePressed: { text = ""; list.adding = false; }
                                Text { visible: parent.text === ""; text: "New Reminder"; color: pal.text2; font: parent.font }
                            }
                        }

                        Repeater {
                            model: root.shown
                            delegate: Item {
                                id: rrow
                                required property var modelData
                                required property int index
                                width: parent.width
                                height: 36
                                readonly property bool mine: list.editingLine === modelData.line

                                property real inT: 0
                                opacity: inT
                                transform: Translate { y: (1 - rrow.inT) * 6 }
                                Component.onCompleted: rowIn.start()
                                SequentialAnimation {
                                    id: rowIn
                                    PauseAnimation { duration: Math.min(260, rrow.index * 35) }
                                    NumberAnimation { target: rrow; property: "inT"; from: 0; to: 1; duration: 380; easing.type: Easing.OutCubic }
                                }

                                // the whole row counts as hovered, the × included — otherwise reaching for the ×
                                // took the pointer out of the text's hit area and the × disappeared under the cursor
                                HoverHandler { id: rowHover }
                                Rectangle {
                                    anchors.fill: parent; anchors.leftMargin: 4; anchors.rightMargin: 4
                                    radius: 7
                                    color: rowHover.hovered || rrow.mine ? pal.hover : "transparent"
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                }
                                Rectangle { x: 40; y: parent.height - 1; width: parent.width - 52; height: 1; color: pal.sep; visible: rrow.index < root.shown.length - 1 }

                                // the circle: squeezes on the press, fills, and draws its tick in
                                Rectangle {
                                    id: tick
                                    x: 12; anchors.verticalCenter: parent.verticalCenter
                                    width: 17; height: 17; radius: 8.5
                                    readonly property bool done: rrow.modelData.done
                                    property real fill: done ? 1 : 0
                                    Behavior on fill { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }
                                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, fill)
                                    border.width: 1.6
                                    border.color: done ? root.accent : pal.text2
                                    Behavior on border.color { ColorAnimation { duration: 300 } }
                                    property real press: 0
                                    scale: 1 - 0.18 * press
                                    SequentialAnimation {
                                        id: tickPop
                                        NumberAnimation { target: tick; property: "press"; to: 1; duration: 90; easing.type: Easing.OutCubic }
                                        NumberAnimation { target: tick; property: "press"; to: 0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 3.0 }
                                    }
                                    Canvas {
                                        anchors.centerIn: parent
                                        width: 12; height: 12
                                        property real draw: tick.fill
                                        onDrawChanged: requestPaint()
                                        onPaint: {
                                            var c = getContext("2d"); c.reset();
                                            if (draw <= 0.01) return;
                                            c.strokeStyle = "white"; c.lineWidth = 2; c.lineCap = "round"; c.lineJoin = "round";
                                            var p = [[1.8, 6.1], [4.7, 9.1], [10.2, 2.9]];
                                            var d = Math.max(0, Math.min(1, (draw - 0.15) / 0.85));
                                            c.beginPath(); c.moveTo(p[0][0], p[0][1]);
                                            var t1 = Math.min(1, d / 0.4);
                                            c.lineTo(p[0][0] + (p[1][0] - p[0][0]) * t1, p[0][1] + (p[1][1] - p[0][1]) * t1);
                                            if (d > 0.4) {
                                                var t2 = (d - 0.4) / 0.6;
                                                c.lineTo(p[1][0] + (p[2][0] - p[1][0]) * t2, p[1][1] + (p[2][1] - p[1][1]) * t2);
                                            }
                                            c.stroke();
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent; anchors.margins: -5
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { tickPop.restart(); if (root.wid) root.wid.toggleReminder(rrow.modelData.line); }
                                    }
                                }

                                Text {
                                    id: rowTxt
                                    x: 40; width: parent.width - 52 - (rowHover.hovered ? 22 : 0)
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !rrow.mine
                                    elide: Text.ElideRight
                                    text: rrow.modelData.text
                                    font.strikeout: rrow.modelData.done
                                    color: rrow.modelData.done ? pal.text2 : pal.text
                                    font.family: root.fam; font.pixelSize: 14
                                }
                                TextInput {
                                    id: rowEdit
                                    x: 40; width: parent.width - 52
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: rrow.mine
                                    color: pal.text; font.family: root.fam; font.pixelSize: 14
                                    selectByMouse: true
                                    onVisibleChanged: if (visible) { text = rrow.modelData.text; forceActiveFocus(); selectAll(); }
                                    onAccepted: { if (root.wid) root.wid.setReminderText(rrow.modelData.line, text); list.editingLine = -1; }
                                    Keys.onEscapePressed: list.editingLine = -1
                                    onActiveFocusChanged: if (!activeFocus && visible) { if (root.wid) root.wid.setReminderText(rrow.modelData.line, text); list.editingLine = -1; }
                                }
                                Text {
                                    anchors.right: parent.right; anchors.rightMargin: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "×"
                                    color: delMa.containsMouse ? "#FF453A" : pal.text2
                                    font.family: root.fam; font.pixelSize: 17
                                    opacity: rowHover.hovered && !rrow.mine ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 140 } }
                                    MouseArea {
                                        id: delMa
                                        anchors.fill: parent; anchors.margins: -7
                                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        enabled: rowHover.hovered && !rrow.mine
                                        onClicked: if (root.wid) root.wid.deleteReminder(rrow.modelData.line)
                                    }
                                }
                                MouseArea {
                                    id: rMa
                                    anchors.fill: parent; anchors.leftMargin: 36; anchors.rightMargin: 34
                                    hoverEnabled: true
                                    enabled: !rrow.mine
                                    cursorShape: Qt.IBeamCursor
                                    onClicked: list.editingLine = rrow.modelData.line
                                }
                            }
                        }
                    }
                }

                // nothing here yet
                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    visible: root.shown.length === 0 && !list.adding
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 260 } }
                    RGlyph { anchors.horizontalCenter: parent.horizontalCenter; width: 34; height: 34; kind: "check"; color: pal.text2 }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.list === "done" ? "No Completed Reminders" : "All Done"
                        color: pal.text2; font.family: root.fam; font.pixelSize: 15; font.weight: Font.Medium
                    }
                }
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) { win.visible = false; event.accepted = true; }
                else if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier)) { list.adding = true; newInput.forceActiveFocus(); event.accepted = true; }
            }
            focus: true
        }
    }

    component RGlyph: Canvas {
        id: rg
        property string kind: ""
        property color color: "white"
        antialiasing: true
        onKindChanged: requestPaint()
        onColorChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            var c = getContext("2d"); c.reset();
            var s = width / 16; c.scale(s, s);
            c.strokeStyle = rg.color; c.fillStyle = rg.color; c.lineWidth = 1.8; c.lineCap = "round"; c.lineJoin = "round";
            if (kind === "list") {
                for (var i = 0; i < 3; i++) {
                    var y = 4 + i * 4;
                    c.beginPath(); c.arc(3.4, y, 0.9, 0, Math.PI * 2); c.fill();
                    c.beginPath(); c.moveTo(6.4, y); c.lineTo(13, y); c.stroke();
                }
            } else if (kind === "check") {
                c.beginPath(); c.moveTo(3.2, 8.4); c.lineTo(6.6, 11.8); c.lineTo(12.8, 4.4); c.stroke();
            }
        }
    }
}
