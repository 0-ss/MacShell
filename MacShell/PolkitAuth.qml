// PolkitAuth — Native macOS Liquid Glass Authentication Prompt supporting password & fprintd fingerprint status.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "I18n.js" as I18n
import "Fonts.js" as Fonts

Scope {
    id: root
    property var hub: null
    readonly property var dock: hub ? hub.dock : null
    readonly property bool darkMode: dock ? dock.darkMode : true
    readonly property color accent: dock ? dock.accent : "#0A84FF"
    readonly property string fam: dock ? dock.fontFamily : "Open Runde"

    property bool open: false
    property string message: I18n.tr("Authentication is required to perform this action.")
    property string actionId: ""
    property string userName: Quickshell.env("USER") || "user"
    property string errorText: ""
    property bool busy: false
    property bool fingerprintAvailable: false
    property string pendingCommand: ""

    function prompt(msg, cmd, action) {
        message = String(msg || I18n.tr("Authentication is required to perform this action."));
        pendingCommand = String(cmd || "");
        actionId = String(action || "");
        errorText = "";
        busy = false;
        open = true;
        if (!fpCheck.running) fpCheck.running = true;
    }
    function close() {
        open = false;
        busy = false;
        errorText = "";
        pendingCommand = "";
    }

    Process {
        id: fpCheck
        command: ["sh", "-c", "command -v fprintd-list >/dev/null 2>&1 && fprintd-list \"$USER\" 2>/dev/null | grep -qi 'finger' && echo 1 || echo 0"]
        stdout: StdioCollector { onStreamFinished: root.fingerprintAvailable = text.trim() === "1" }
    }
    Process {
        id: authProc
        property string pw: ""
        stdinEnabled: true
        command: ["sudo", "-S", "-v"]
        onStarted: {
            try { write(pw + "\n"); } catch (e) {}
            pw = "";
        }
        onExited: (code, status) => {
            root.busy = false;
            if (code === 0) {
                var c = root.pendingCommand;
                root.close();
                if (c !== "") Quickshell.execDetached(["sudo", "-n", "sh", "-c", c]);
            } else {
                root.errorText = I18n.tr("Incorrect password. Please try again.");
            }
        }
    }
    function submitPassword(pw) {
        if (!pw || busy) return;
        busy = true;
        errorText = "";
        authProc.pw = pw;
        authProc.running = true;
    }

    Loader {
        id: polkitLoader
        active: root.open
        sourceComponent: PanelWindow {
            screen: {
                var fm = Hyprland.focusedMonitor;
                if (fm) {
                    for (var i = 0; i < Quickshell.screens.length; i++)
                        if (Quickshell.screens[i].name === fm.name) return Quickshell.screens[i];
                }
                return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
            }
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "macpolkit"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.36) }

            Rectangle {
                anchors.centerIn: parent
                width: 340; height: pkCol.implicitHeight + 36; radius: 20
                color: root.darkMode ? Qt.rgba(0.12, 0.12, 0.14, 0.96) : Qt.rgba(0.97, 0.97, 0.98, 0.98)
                border.width: 1; border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.14)

                Column {
                    id: pkCol
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top; anchors.margins: 20
                    spacing: 10

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 44; height: 44; radius: 22
                        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
                        Text { anchors.centerIn: parent; text: "\ud83d\udd12"; font.pixelSize: 20 }
                    }
                    Text {
                        width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                        text: I18n.tr("Authentication Required")
                        color: root.darkMode ? "#FFFFFF" : "#1D1D1F"
                        font.family: Fonts.forWeight(Font.DemiBold, root.fam); font.pixelSize: 15; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                        text: root.message
                        color: root.darkMode ? Qt.rgba(1, 1, 1, 0.72) : Qt.rgba(0, 0, 0, 0.68)
                        font.pixelSize: 12
                    }
                    Text {
                        visible: root.fingerprintAvailable
                        width: parent.width; horizontalAlignment: Text.AlignHCenter
                        text: I18n.tr("Touch ID / Fingerprint available or enter password")
                        color: root.accent; font.pixelSize: 11
                    }
                    Rectangle {
                        width: parent.width; height: 32; radius: 8
                        color: root.darkMode ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06)
                        border.width: 1; border.color: pkPw.activeFocus ? root.accent : (root.darkMode ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12))
                        TextInput {
                            id: pkPw
                            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: TextInput.Password
                            focus: true
                            color: root.darkMode ? "#FFFFFF" : "#1D1D1F"; font.pixelSize: 13
                            Keys.onEscapePressed: root.close()
                            Keys.onReturnPressed: { var p = text; text = ""; root.submitPassword(p); }
                        }
                        Text {
                            visible: pkPw.text === ""
                            x: 10; anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Password for ") + root.userName
                            color: root.darkMode ? Qt.rgba(1, 1, 1, 0.42) : Qt.rgba(0, 0, 0, 0.42); font.pixelSize: 12
                        }
                    }
                    Text {
                        visible: root.errorText !== ""
                        width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                        text: root.errorText; color: "#FF453A"; font.pixelSize: 12
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 10
                        Rectangle {
                            width: 120; height: 30; radius: 8
                            color: root.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
                            Text { anchors.centerIn: parent; text: I18n.tr("Cancel"); color: root.darkMode ? "#FFFFFF" : "#1D1D1F"; font.pixelSize: 12 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.close() }
                        }
                        Rectangle {
                            width: 120; height: 30; radius: 8; color: root.accent
                            opacity: root.busy ? 0.55 : 1
                            Text { anchors.centerIn: parent; text: root.busy ? I18n.tr("Checking\u2026") : I18n.tr("Unlock"); color: "#FFFFFF"; font.pixelSize: 12; font.weight: Font.DemiBold }
                            MouseArea {
                                anchors.fill: parent; enabled: !root.busy; cursorShape: Qt.PointingHandCursor
                                onClicked: { var p = pkPw.text; pkPw.text = ""; root.submitPassword(p); }
                            }
                        }
                    }
                }
            }
        }
    }
}
