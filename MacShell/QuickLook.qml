// System-Wide Quick Look (Space / IPC) — floating Liquid Glass preview for images, PDFs, audio/video metadata, code, markdown, and folders.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "Spotlight.js" as Spotlight
import "I18n.js" as I18n
import "Fonts.js" as Fonts

Scope {
    id: root
    property var hub: null
    readonly property var dock: hub ? hub.dock : null
    readonly property bool darkMode: dock ? dock.darkMode : true
    readonly property color accent: dock ? dock.accent : "#0A84FF"
    readonly property string fam: dock ? dock.fontFamily : "Open Runde"
    readonly property string previewScript: decodeURIComponent(String(Qt.resolvedUrl("assets/spotlight-search.py")).replace(/^file:\/\//, ""))

    property bool open: false
    property string filePath: ""
    property string fileName: ""
    property string fileKind: "file"
    property var previewData: null
    property bool loading: false

    function openPath(path) {
        var p = String(path || "").trim();
        if (!p) return;
        if (p.indexOf("file://") === 0) {
            try { p = decodeURIComponent(p.substring(7)); } catch (e) { p = p.substring(7); }
        }
        if (open && filePath === p) { close(); return; }
        filePath = p;
        var clean = p.replace(/\/+$/, "");
        fileName = clean.substring(clean.lastIndexOf("/") + 1) || p;
        fileKind = Spotlight.fileKindFromPath(p, false);
        previewData = null;
        open = true;
        if (fileKind === "image") {
            loading = false;
            return;
        }
        loading = true;
        qlProc.running = false;
        qlProc.targetPath = p;
        qlProc.running = true;
    }

    function togglePath(path) {
        if (open && (!path || path === filePath)) close();
        else openPath(path);
    }

    function close() {
        open = false;
        loading = false;
        qlProc.running = false;
    }

    Process {
        id: qlProc
        property string targetPath: ""
        command: ["python3", "-B", root.previewScript, "preview", targetPath]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                try {
                    var o = JSON.parse(text);
                    root.previewData = o;
                    if (o && o.kind === "dir") root.fileKind = "dir";
                } catch (e) {
                    root.previewData = null;
                }
            }
        }
        onExited: root.loading = false
    }

    Loader {
        id: qlWinLoader
        active: root.open
        sourceComponent: PanelWindow {
            id: qlWin
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
            WlrLayershell.namespace: "macquicklook"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            Item {
                id: qlRoot
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.close()
                Keys.onSpacePressed: root.close()
                Keys.onReturnPressed: {
                    var p = root.filePath;
                    root.close();
                    Quickshell.execDetached(["xdg-open", p]);
                }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.32)
                    MouseArea { anchors.fill: parent; onClicked: root.close() }
                }

                Rectangle {
                    id: qlCard
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 80, root.fileKind === "image" ? 820 : 680)
                    height: Math.min(parent.height - 100, root.fileKind === "image" ? 600 : 520)
                    radius: 18
                    color: root.darkMode ? Qt.rgba(0.11, 0.11, 0.13, 0.94) : Qt.rgba(0.97, 0.97, 0.98, 0.96)
                    border.width: 1
                    border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.14)
                    MouseArea { anchors.fill: parent }

                    // Title bar
                    Item {
                        id: qlHeader
                        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                        height: 44
                        Rectangle {
                            x: 14; anchors.verticalCenter: parent.verticalCenter
                            width: 13; height: 13; radius: 6.5; color: "#FF5F57"
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.close() }
                        }
                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 190
                            horizontalAlignment: Text.AlignHCenter; elide: Text.ElideMiddle
                            text: root.fileName
                            color: root.darkMode ? "#FFFFFF" : "#1D1D1F"
                            font.family: Fonts.forWeight(Font.DemiBold, root.fam); font.pixelSize: 13.5; font.weight: Font.DemiBold
                        }
                        Rectangle {
                            anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                            height: 26; radius: 8; width: qlOpenLbl.implicitWidth + 18
                            color: qlOpenBtnMa.containsMouse ? root.accent : (root.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08))
                            Text {
                                id: qlOpenLbl; anchors.centerIn: parent
                                text: I18n.tr("Open")
                                color: qlOpenBtnMa.containsMouse ? "#FFFFFF" : (root.darkMode ? "#FFFFFF" : "#1D1D1F")
                                font.family: Fonts.forWeight(Font.Medium, root.fam); font.pixelSize: 12
                            }
                            MouseArea {
                                id: qlOpenBtnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { var p = root.filePath; root.close(); Quickshell.execDetached(["xdg-open", p]); }
                            }
                        }
                        Rectangle {
                            anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                            height: 1; color: root.darkMode ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)
                        }
                    }

                    // Body
                    Item {
                        anchors.top: qlHeader.bottom; anchors.bottom: qlFooter.top; anchors.left: parent.left; anchors.right: parent.right
                        anchors.margins: 14
                        clip: true

                        Image {
                            visible: root.fileKind === "image"
                            anchors.fill: parent
                            source: root.fileKind === "image" ? ("file://" + root.filePath.split("/").map(function (part) { return encodeURIComponent(part); }).join("/")) : ""
                            sourceSize: Qt.size(1600, 1600)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true; smooth: true
                        }

                        ScrollView {
                            visible: root.fileKind !== "image" && root.previewData && root.previewData.text && root.previewData.text !== ""
                            anchors.fill: parent
                            clip: true
                            TextArea {
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.Wrap
                                text: (root.previewData && root.previewData.text) ? root.previewData.text : ""
                                color: root.darkMode ? "#EAECEF" : "#1D1D1F"
                                font.family: root.fileKind === "text" ? "monospace" : root.fam
                                font.pixelSize: 12.5
                                background: Rectangle { color: "transparent" }
                            }
                        }

                        Column {
                            visible: root.fileKind !== "image" && (!root.previewData || !root.previewData.text)
                            anchors.centerIn: parent
                            spacing: 10
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.loading ? I18n.tr("Loading preview\u2026")
                                      : (root.fileKind === "video" || root.fileKind === "audio"
                                         ? I18n.tr("Media file — press Return to play")
                                         : (root.fileKind === "pdf" ? I18n.tr("PDF document — press Return to open")
                                            : I18n.tr("Press Return to open file")))
                                color: root.darkMode ? Qt.rgba(1, 1, 1, 0.72) : Qt.rgba(0, 0, 0, 0.65)
                                font.family: Fonts.forWeight(Font.Medium, root.fam); font.pixelSize: 14
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.filePath
                                color: root.darkMode ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.45)
                                font.pixelSize: 11.5
                            }
                        }
                    }

                    // Footer metadata
                    Item {
                        id: qlFooter
                        anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                        height: 30
                        Rectangle {
                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                            height: 1; color: root.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.08)
                        }
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter
                            text: {
                                var sz = root.previewData && root.previewData.size ? Spotlight.formatBytes(root.previewData.size) : "";
                                return root.fileKind.toUpperCase() + (sz ? " \u00b7 " + sz : "");
                            }
                            color: root.darkMode ? Qt.rgba(1, 1, 1, 0.52) : Qt.rgba(0, 0, 0, 0.50)
                            font.pixelSize: 11
                        }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Space to close \u00b7 Return to open")
                            color: root.darkMode ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.45)
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }
    }
}
