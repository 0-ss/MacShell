// macOS Reminders widget for desktop
import QtQuick
import QtQuick.Effects

Item {
    id: w

    property string style: "liquid"
    property string size: "medium"
    property real scaleF: 1.0
    property string fam: "Inter"
    property real screenX: x
    property real screenY: y
    property bool preview: false
    property bool editing: false

    // host / hub
    property var host: null
    property var remindersModel: null
    property int openCount: 0

    signal openRemindersApp()
    signal addReminder(string text)
    signal toggleReminder(int line)
    signal deleteReminder(int line)

    // liquid glass inputs
    property bool glassReady: false
    property url shaderUrl: ""
    property url wallUrl: ""
    property real screenW: 1920
    property real screenH: 1080
    property real glassOpacity: 0.42
    property real glassBlur: 5
    property real glassLiquid: 1.0
    property real glassRim: 0.45
    property real glassGrain: 0.03
    property bool darkGlass: true

    signal glassFailed()

    readonly property bool isSmall: size === "small"
    readonly property bool isMedium: size === "medium"
    readonly property bool isLarge: size === "large"

    width: (isSmall ? 158 : (isMedium ? 338 : 358)) * scaleF * (isSmall ? 168 / 158 : (isMedium ? 358 / 338 : 1.0))
    height: (isLarge ? 354 : 168) * scaleF

    readonly property real radiusPx: 28 * scaleF * (isSmall ? 168 / 158 : (isMedium ? 358 / 338 : 1))
    readonly property bool glassOn: style === "liquid" && glassReady && !preview && wallUrl != ""
    readonly property bool dark: style === "dark" || (style === "liquid" && darkGlass)

    readonly property color fg: dark ? "white" : "#1D1D1F"
    readonly property color fg2: dark ? Qt.rgba(1, 1, 1, 0.6) : Qt.rgba(0, 0, 0, 0.55)
    readonly property color blue: "#0A84FF"

    // ── background ──
    Rectangle {
        anchors.fill: parent
        visible: w.style !== "liquid"
        radius: w.radiusPx
        color: w.dark ? "#1C1C1E" : "#F2F2F7"
        border.width: 1
        border.color: w.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10)
    }

    Rectangle {
        anchors.fill: parent
        visible: w.style === "liquid" && !w.glassOn
        radius: w.radiusPx
        color: w.dark ? Qt.rgba(0.18, 0.18, 0.20, 0.85) : Qt.rgba(0.96, 0.96, 0.98, 0.90)
        border.width: 1
        border.color: w.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08)
    }

    Loader {
        anchors.fill: parent
        active: w.glassOn
        sourceComponent: Item {
            id: gl
            readonly property real margin: 72
            readonly property real padPx: 10
            readonly property real ds: w.glassBlur >= 8 ? 0.5 : 1.0
            readonly property real bn: Math.min(1.0, w.glassBlur * 1.4 * ds / 64.0)

            property bool updating: true
            Timer { id: settleTimer; interval: 350; onTriggered: gl.updating = false }
            function triggerUpdate() { gl.updating = true; settleTimer.restart(); }

            Item {
                id: backdrop
                width: w.width + 2 * (gl.padPx + gl.margin)
                height: w.height + 2 * (gl.padPx + gl.margin)
                x: -(gl.padPx + gl.margin)
                y: -(gl.padPx + gl.margin)
                layer.enabled: true
                layer.smooth: true

                Image {
                    x: gl.padPx + gl.margin - (w.screenX >= 0 ? w.screenX : 0)
                    y: gl.padPx + gl.margin - (w.screenY >= 0 ? w.screenY : 0)
                    width: w.screenW
                    height: w.screenH
                    source: w.wallUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                }
            }

            ShaderEffect {
                anchors.fill: parent
                fragmentShader: w.shaderUrl
                property variant wallSource: backdrop
                property real blurNorm: gl.bn
                property real liquidStrength: w.glassLiquid
                property real rimStrength: w.glassRim
                property real grainStrength: w.glassGrain
                property real opacityVal: w.glassOpacity
                property int isDark: w.darkGlass ? 1 : 0
                property real cornerRadius: w.radiusPx
                property vector2d itemSize: Qt.vector2d(w.width, w.height)
                property vector2d screenSize: Qt.vector2d(w.screenW, w.screenH)
                property vector2d widgetPos: Qt.vector2d(w.screenX, w.screenY)
            }
        }
    }

    // ── content ──
    Item {
        anchors.fill: parent
        anchors.margins: 16

        Item {
            id: rHead
            width: parent.width
            height: cnt.height

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - cnt.width - addBtn.width - 14
                elide: Text.ElideRight
                text: "Reminders"
                color: w.blue
                font.family: w.fam
                font.pixelSize: 14
                font.weight: Font.Bold
            }

            Text {
                id: cnt
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "" + w.openCount
                color: w.blue
                font.family: w.fam
                font.pixelSize: 22
                font.weight: Font.Bold
            }

            Rectangle {
                id: addBtn
                anchors.right: cnt.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 20; height: 20; radius: 10
                visible: opacity > 0.01
                opacity: w.editing ? 0 : ((headHover.hovered || adding) ? 1 : 0)
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                color: addMa.containsMouse ? Qt.rgba(w.blue.r, w.blue.g, w.blue.b, 0.22) : "transparent"
                rotation: adding ? 45 : 0
                Behavior on rotation { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                scale: addMa.pressed ? 0.88 : 1
                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }

                Rectangle { anchors.centerIn: parent; width: 11; height: 1.7; radius: 1; color: w.blue }
                Rectangle { anchors.centerIn: parent; width: 1.7; height: 11; radius: 1; color: w.blue }

                MouseArea {
                    id: addMa
                    anchors.fill: parent; anchors.margins: -4
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { adding = !adding; if (adding) newInput.forceActiveFocus(); }
                }
            }

            HoverHandler { id: headHover }

            MouseArea {
                anchors.fill: parent
                anchors.rightMargin: addBtn.width + 12
                enabled: !w.editing
                cursorShape: Qt.PointingHandCursor
                onClicked: w.openRemindersApp()
            }
        }

        property bool adding: false

        Flickable {
            id: remFlick
            y: rHead.height + 6
            width: parent.width
            height: parent.height - y
            clip: true
            contentHeight: remCol.height
            boundsBehavior: Flickable.StopAtBounds
            interactive: !w.editing && contentHeight > height + 2

            Column {
                id: remCol
                width: parent.width
                spacing: 7

                Item {
                    width: parent.width
                    height: adding ? 22 : 0
                    clip: true
                    opacity: adding ? 1 : 0
                    Behavior on height { NumberAnimation { duration: 280; easing.type: Easing.OutQuint } }
                    Behavior on opacity { NumberAnimation { duration: 220 } }

                    Rectangle {
                        width: 16; height: 16; radius: 8
                        anchors.verticalCenter: parent.verticalCenter
                        color: "transparent"; border.width: 1.5; border.color: w.fg2
                    }
                    TextInput {
                        id: newInput
                        x: 24; width: parent.width - 24
                        anchors.verticalCenter: parent.verticalCenter
                        color: w.fg; font.family: w.fam; font.pixelSize: 13
                        selectByMouse: false
                        onAccepted: { w.addReminder(text); text = ""; }
                        Keys.onEscapePressed: { text = ""; adding = false; }
                        Text { visible: parent.text === ""; text: "New Reminder"; color: w.fg2; font: parent.font }
                    }
                }

                Repeater {
                    model: w.remindersModel
                    delegate: Row {
                        id: remRow
                        required property var model
                        readonly property var modelData: remRow.model
                        required property int index
                        spacing: 8
                        width: parent.width
                        property real inT: 1
                        opacity: inT

                        Rectangle {
                            id: tick
                            width: 16; height: 16; radius: 8
                            anchors.verticalCenter: parent.verticalCenter
                            readonly property bool done: modelData.done
                            property real fill: done ? 1 : 0
                            Behavior on fill { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                            color: Qt.rgba(w.blue.r, w.blue.g, w.blue.b, fill)
                            border.width: 1.5
                            border.color: done ? w.blue : w.fg2
                            Behavior on border.color { ColorAnimation { duration: 240 } }

                            property real press: 0
                            scale: (0.86 + 0.14 * Math.max(fill, 1 - fill * 0)) * (1 - 0.18 * press)
                            SequentialAnimation {
                                id: tickPop
                                NumberAnimation { target: tick; property: "press"; to: 1; duration: 90; easing.type: Easing.OutCubic }
                                NumberAnimation { target: tick; property: "press"; to: 0; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2.5 }
                            }

                            Canvas {
                                id: tickMark
                                anchors.centerIn: parent
                                width: 11; height: 11
                                property real draw: tick.fill
                                onDrawChanged: requestPaint()
                                onPaint: {
                                    var c = getContext("2d"); c.reset();
                                    if (draw <= 0.01) return;
                                    c.strokeStyle = "white"; c.lineWidth = 1.9; c.lineCap = "round"; c.lineJoin = "round";
                                    var p = [[1.6, 5.6], [4.3, 8.4], [9.4, 2.6]];
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
                                anchors.fill: parent; anchors.margins: -4
                                enabled: !w.editing; cursorShape: Qt.PointingHandCursor
                                onClicked: { tickPop.restart(); w.toggleReminder(modelData.line); }
                            }
                        }

                        Item {
                            width: parent.width - 24
                            height: Math.max(rowTxt.implicitHeight, 18)
                            anchors.verticalCenter: parent.verticalCenter
                            HoverHandler { id: rowHover; enabled: !w.editing }

                            Text {
                                id: rowTxt
                                width: parent.width - (rowHover.hovered ? 20 : 0)
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.text || ""
                                font.strikeout: modelData.done
                                color: modelData.done ? w.fg2 : w.fg
                                font.family: w.fam
                                font.pixelSize: 13
                            }

                            MouseArea {
                                id: rowMa
                                anchors.fill: parent; anchors.rightMargin: 22
                                enabled: !w.editing
                                cursorShape: Qt.PointingHandCursor
                                onClicked: w.openRemindersApp()
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\u00D7"
                                color: w.fg2
                                font.family: w.fam
                                font.pixelSize: 15
                                opacity: rowHover.hovered ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 140 } }

                                MouseArea {
                                    anchors.fill: parent; anchors.margins: -5
                                    enabled: rowHover.hovered
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: w.deleteReminder(modelData.line)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

