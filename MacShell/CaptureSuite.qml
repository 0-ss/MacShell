// CaptureSuite — macOS Cmd+Shift+5 Capture Toolbar, Floating Screenshot Thumbnail, and Built-in Markup / Annotation Editor.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "I18n.js" as I18n
import "Fonts.js" as Fonts

Scope {
    id: root
    property var hub: null
    readonly property var bar: hub ? hub.bar : null
    readonly property var dock: hub ? hub.dock : null
    readonly property bool darkMode: dock ? dock.darkMode : true
    readonly property color accent: dock ? dock.accent : "#0A84FF"
    readonly property string fam: dock ? dock.fontFamily : "Open Runde"

    // ── Capture Toolbar state ──
    property bool toolbarOpen: false
    property int delaySecs: 0          // 0 | 5 | 10
    property int countdown: 0
    property string pendingMode: ""    // "screen" | "sel" | "window" | "record"
    property bool recordMic: false

    // ── Floating Screenshot Thumbnail state ──
    property string thumbPath: ""
    property bool thumbOpen: false
    property bool thumbHovered: false

    // ── Markup / Annotation Editor state ──
    property bool markupOpen: false
    property string markupPath: ""
    property string markupTool: "arrow"   // "pen" | "arrow" | "rect" | "redact" | "text"
    property color markupColor: "#FF453A"
    property string markupText: "Note"
    property var markupShapes: []         // [{ tool, color, x0, y0, x1, y1, pts, text }]

    function openToolbar() { toolbarOpen = true; }
    function closeToolbar() { toolbarOpen = false; countdown = 0; delayTimer.stop(); }
    function toggleToolbar() { if (toolbarOpen) closeToolbar(); else openToolbar(); }

    function showThumbnail(path) {
        var p = String(path || "").trim();
        if (!p) return;
        thumbPath = p;
        thumbOpen = true;
        thumbAutoHide.restart();
    }
    function dismissThumbnail() {
        thumbOpen = false;
        thumbAutoHide.stop();
    }
    function openMarkup(path) {
        var p = String(path || thumbPath || "").trim();
        if (!p) return;
        dismissThumbnail();
        closeToolbar();
        markupPath = p;
        markupShapes = [];
        markupOpen = true;
    }
    function closeMarkup() {
        markupOpen = false;
        markupShapes = [];
    }

    function runCapture(mode) {
        toolbarOpen = false;
        if (delaySecs > 0) {
            pendingMode = mode;
            countdown = delaySecs;
            delayTimer.restart();
            return;
        }
        executeCapture(mode);
    }
    function executeCapture(mode) {
        if (!bar) return;
        if (mode === "record") bar.toggleRecording();
        else if (mode === "window") bar.shotWindow(bar.activeWin);
        else if (mode === "sel") bar.shot("sel");
        else bar.shot("");
    }

    Timer {
        id: delayTimer
        interval: 1000; repeat: true
        onTriggered: {
            root.countdown--;
            if (root.countdown <= 0) {
                stop();
                var m = root.pendingMode;
                root.pendingMode = "";
                root.executeCapture(m);
            }
        }
    }
    Timer {
        id: thumbAutoHide
        interval: 6500
        onTriggered: if (!root.thumbHovered) root.thumbOpen = false
    }

    function focusedScreen() {
        var fm = Hyprland.focusedMonitor;
        if (fm) {
            for (var i = 0; i < Quickshell.screens.length; i++)
                if (Quickshell.screens[i].name === fm.name) return Quickshell.screens[i];
        }
        return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
    }

    // ═════════════ 1. CAPTURE TOOLBAR (Cmd+Shift+5 style) ═════════════
    Loader {
        id: toolbarLoader
        active: root.toolbarOpen || root.countdown > 0
        sourceComponent: PanelWindow {
            screen: root.focusedScreen()
            anchors { bottom: true; left: true; right: true }
            implicitHeight: 140
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "maccapturebar"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.toolbarOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            Item {
                anchors.fill: parent
                focus: root.toolbarOpen
                Keys.onEscapePressed: root.closeToolbar()

                // Countdown pill
                Rectangle {
                    visible: root.countdown > 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 36
                    width: 140; height: 42; radius: 21
                    color: Qt.rgba(0.10, 0.10, 0.12, 0.92)
                    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.22)
                    Text {
                        anchors.centerIn: parent
                        text: I18n.tr("Capturing in ") + root.countdown + "s"
                        color: "#FFFFFF"; font.family: Fonts.forWeight(Font.DemiBold, root.fam); font.pixelSize: 13
                    }
                }

                // Main toolbar pill
                Rectangle {
                    visible: root.toolbarOpen
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 28
                    height: 58; radius: 20
                    width: tbRow.implicitWidth + 24
                    color: root.darkMode ? Qt.rgba(0.12, 0.12, 0.14, 0.94) : Qt.rgba(0.96, 0.96, 0.98, 0.96)
                    border.width: 1; border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.12)

                    Row {
                        id: tbRow
                        anchors.centerIn: parent
                        spacing: 8

                        Repeater {
                            model: [
                                { id: "screen", label: I18n.tr("Entire Screen") },
                                { id: "window", label: I18n.tr("Window") },
                                { id: "sel",    label: I18n.tr("Selection") },
                                { id: "record", label: (root.bar && root.bar.recording) ? I18n.tr("Stop Rec") : I18n.tr("Record") }
                            ]
                            delegate: Rectangle {
                                id: tbBtn
                                required property var modelData
                                height: 38; radius: 12; width: tbLbl.implicitWidth + 22
                                color: tbMa.containsMouse ? root.accent : (root.darkMode ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06))
                                Text {
                                    id: tbLbl; anchors.centerIn: parent
                                    text: tbBtn.modelData.label
                                    color: tbMa.containsMouse ? "#FFFFFF" : (root.darkMode ? "#FFFFFF" : "#1D1D1F")
                                    font.family: Fonts.forWeight(Font.Medium, root.fam); font.pixelSize: 12.5
                                }
                                MouseArea {
                                    id: tbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.runCapture(tbBtn.modelData.id)
                                }
                            }
                        }

                        Rectangle { width: 1; height: 28; anchors.verticalCenter: parent.verticalCenter; color: root.darkMode ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12) }

                        // Timer delay cycle (0s -> 5s -> 10s)
                        Rectangle {
                            height: 38; radius: 12; width: tdLbl.implicitWidth + 18
                            color: tdMa.containsMouse ? root.accent : (root.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05))
                            Text {
                                id: tdLbl; anchors.centerIn: parent
                                text: root.delaySecs > 0 ? (root.delaySecs + "s Delay") : I18n.tr("No Delay")
                                color: tdMa.containsMouse ? "#FFFFFF" : (root.darkMode ? "#FFFFFF" : "#1D1D1F")
                                font.family: Fonts.forWeight(Font.Normal, root.fam); font.pixelSize: 12
                            }
                            MouseArea {
                                id: tdMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.delaySecs = root.delaySecs === 0 ? 5 : (root.delaySecs === 5 ? 10 : 0)
                            }
                        }

                        // Close button
                        Rectangle {
                            width: 30; height: 30; radius: 15; anchors.verticalCenter: parent.verticalCenter
                            color: tcMa.containsMouse ? "#FF453A" : (root.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08))
                            Text { anchors.centerIn: parent; text: "\u00d7"; color: tcMa.containsMouse ? "#FFFFFF" : (root.darkMode ? "#FFFFFF" : "#1D1D1F"); font.pixelSize: 15 }
                            MouseArea { id: tcMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.closeToolbar() }
                        }
                    }
                }
            }
        }
    }

    // ═════════════ 2. FLOATING SCREENSHOT THUMBNAIL (bottom-right) ═════════════
    Loader {
        id: thumbLoader
        active: root.thumbOpen && root.thumbPath !== ""
        sourceComponent: PanelWindow {
            screen: root.focusedScreen()
            anchors { bottom: true; right: true }
            implicitWidth: 260; implicitHeight: 190
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "macthumb"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Rectangle {
                anchors.right: parent.right; anchors.rightMargin: 18
                anchors.bottom: parent.bottom; anchors.bottomMargin: 18
                width: 236; height: 162; radius: 16
                color: root.darkMode ? Qt.rgba(0.11, 0.11, 0.13, 0.94) : Qt.rgba(0.97, 0.97, 0.98, 0.96)
                border.width: 1; border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.14)
                HoverHandler { onHoveredChanged: { root.thumbHovered = hovered; if (!hovered) thumbAutoHide.restart(); } }

                Image {
                    x: 8; y: 8; width: parent.width - 16; height: 114
                    source: "file://" + root.thumbPath.split("/").map(function (p) { return encodeURIComponent(p); }).join("/")
                    sourceSize: Qt.size(480, 280)
                    fillMode: Image.PreserveAspectCrop; clip: true; asynchronous: true; smooth: true
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openMarkup(root.thumbPath) }
                }
                Row {
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 7
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8
                    Rectangle {
                        height: 24; radius: 7; width: thEd.implicitWidth + 14
                        color: thEdMa.containsMouse ? root.accent : (root.darkMode ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08))
                        Text { id: thEd; anchors.centerIn: parent; text: I18n.tr("Markup"); color: "#FFFFFF"; font.pixelSize: 11.5 }
                        MouseArea { id: thEdMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openMarkup(root.thumbPath) }
                    }
                    Rectangle {
                        height: 24; radius: 7; width: thCp.implicitWidth + 14
                        color: thCpMa.containsMouse ? root.accent : (root.darkMode ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08))
                        Text { id: thCp; anchors.centerIn: parent; text: I18n.tr("Copy"); color: "#FFFFFF"; font.pixelSize: 11.5 }
                        MouseArea { id: thCpMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { Quickshell.execDetached(["sh", "-c", "wl-copy < \"$1\"", "sh", root.thumbPath]); root.dismissThumbnail(); } }
                    }
                    Rectangle {
                        height: 24; radius: 7; width: thCl.implicitWidth + 14
                        color: thClMa.containsMouse ? "#FF453A" : (root.darkMode ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08))
                        Text { id: thCl; anchors.centerIn: parent; text: I18n.tr("Done"); color: "#FFFFFF"; font.pixelSize: 11.5 }
                        MouseArea { id: thClMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.dismissThumbnail() }
                    }
                }
            }
        }
    }

    // ═════════════ 3. BUILT-IN MARKUP / ANNOTATION EDITOR ═════════════
    Loader {
        id: markupLoader
        active: root.markupOpen && root.markupPath !== ""
        sourceComponent: PanelWindow {
            screen: root.focusedScreen()
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "macmarkup"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            Item {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.closeMarkup()

                Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.55) }

                Rectangle {
                    id: mkCard
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 60, 960)
                    height: Math.min(parent.height - 60, 680)
                    radius: 18
                    color: root.darkMode ? Qt.rgba(0.11, 0.11, 0.13, 0.96) : Qt.rgba(0.97, 0.97, 0.98, 0.98)
                    border.width: 1; border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.12)

                    // Top annotation toolbar
                    Row {
                        id: mkBar
                        anchors.top: parent.top; anchors.topMargin: 10
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 6
                        Repeater {
                            model: [
                                { id: "arrow",  label: I18n.tr("Arrow") },
                                { id: "rect",   label: I18n.tr("Box") },
                                { id: "pen",    label: I18n.tr("Pen") },
                                { id: "redact", label: I18n.tr("Redact") },
                                { id: "text",   label: I18n.tr("Text") }
                            ]
                            delegate: Rectangle {
                                id: mTool; required property var modelData
                                height: 28; radius: 8; width: mtL.implicitWidth + 16
                                color: root.markupTool === mTool.modelData.id ? root.accent : (root.darkMode ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.07))
                                Text { id: mtL; anchors.centerIn: parent; text: mTool.modelData.label; color: root.markupTool === mTool.modelData.id ? "#FFFFFF" : (root.darkMode ? "#FFFFFF" : "#1D1D1F"); font.pixelSize: 12 }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.markupTool = mTool.modelData.id }
                            }
                        }
                        Rectangle { width: 1; height: 20; anchors.verticalCenter: parent.verticalCenter; color: Qt.rgba(1, 1, 1, 0.18) }
                        Repeater {
                            model: ["#FF453A", "#FF9F0A", "#FFD60A", "#30D158", "#0A84FF", "#FFFFFF"]
                            delegate: Rectangle {
                                required property string modelData
                                width: 18; height: 18; radius: 9; anchors.verticalCenter: parent.verticalCenter
                                color: modelData
                                border.width: String(root.markupColor).toLowerCase() === modelData.toLowerCase() ? 2 : 1
                                border.color: "#FFFFFF"
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.markupColor = parent.modelData }
                            }
                        }
                        Rectangle { width: 1; height: 20; anchors.verticalCenter: parent.verticalCenter; color: Qt.rgba(1, 1, 1, 0.18) }
                        Rectangle {
                            height: 28; radius: 8; width: mkUndo.implicitWidth + 14
                            color: root.darkMode ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.07)
                            Text { id: mkUndo; anchors.centerIn: parent; text: I18n.tr("Undo"); color: root.darkMode ? "#FFFFFF" : "#1D1D1F"; font.pixelSize: 12 }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.markupShapes.length > 0) {
                                        root.markupShapes = root.markupShapes.slice(0, root.markupShapes.length - 1);
                                        mkCanvas.requestPaint();
                                    }
                                }
                            }
                        }
                        Rectangle {
                            height: 28; radius: 8; width: mkSave.implicitWidth + 18; color: root.accent
                            Text { id: mkSave; anchors.centerIn: parent; text: I18n.tr("Save & Copy"); color: "#FFFFFF"; font.pixelSize: 12; font.weight: Font.DemiBold }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var outPath = root.markupPath;
                                    mkStage.grabToImage(function (res) {
                                        res.saveToFile(outPath);
                                        Quickshell.execDetached(["sh", "-c", "wl-copy < \"$1\" 2>/dev/null; notify-send -a macbar 'Markup Saved' \"$1\"", "sh", outPath]);
                                        root.closeMarkup();
                                    });
                                }
                            }
                        }
                        Rectangle {
                            height: 28; radius: 8; width: mkClose.implicitWidth + 14
                            color: root.darkMode ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.07)
                            Text { id: mkClose; anchors.centerIn: parent; text: I18n.tr("Cancel"); color: root.darkMode ? "#FFFFFF" : "#1D1D1F"; font.pixelSize: 12 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.closeMarkup() }
                        }
                    }

                    // Annotation stage (Image + Canvas)
                    Item {
                        id: mkStage
                        anchors.top: mkBar.bottom; anchors.topMargin: 10
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 14
                        anchors.left: parent.left; anchors.leftMargin: 14
                        anchors.right: parent.right; anchors.rightMargin: 14
                        clip: true

                        Image {
                            id: mkImg
                            anchors.fill: parent
                            source: "file://" + root.markupPath.split("/").map(function (p) { return encodeURIComponent(p); }).join("/")
                            fillMode: Image.PreserveAspectFit; smooth: true
                        }

                        Canvas {
                            id: mkCanvas
                            anchors.fill: parent
                            property var liveShape: null
                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);
                                var all = root.markupShapes.slice();
                                if (liveShape) all.push(liveShape);
                                for (var i = 0; i < all.length; i++) {
                                    var s = all[i];
                                    ctx.strokeStyle = s.color;
                                    ctx.fillStyle = s.color;
                                    ctx.lineWidth = 3.5;
                                    ctx.lineCap = "round";
                                    ctx.lineJoin = "round";
                                    if (s.tool === "pen" && s.pts && s.pts.length > 1) {
                                        ctx.beginPath();
                                        ctx.moveTo(s.pts[0][0], s.pts[0][1]);
                                        for (var j = 1; j < s.pts.length; j++) ctx.lineTo(s.pts[j][0], s.pts[j][1]);
                                        ctx.stroke();
                                    } else if (s.tool === "rect") {
                                        ctx.strokeRect(s.x0, s.y0, s.x1 - s.x0, s.y1 - s.y0);
                                    } else if (s.tool === "redact") {
                                        ctx.fillStyle = "#000000";
                                        ctx.fillRect(s.x0, s.y0, s.x1 - s.x0, s.y1 - s.y0);
                                    } else if (s.tool === "arrow") {
                                        ctx.beginPath();
                                        ctx.moveTo(s.x0, s.y0);
                                        ctx.lineTo(s.x1, s.y1);
                                        ctx.stroke();
                                        var ang = Math.atan2(s.y1 - s.y0, s.x1 - s.x0), hl = 14;
                                        ctx.beginPath();
                                        ctx.moveTo(s.x1, s.y1);
                                        ctx.lineTo(s.x1 - hl * Math.cos(ang - 0.5), s.y1 - hl * Math.sin(ang - 0.5));
                                        ctx.moveTo(s.x1, s.y1);
                                        ctx.lineTo(s.x1 - hl * Math.cos(ang + 0.5), s.y1 - hl * Math.sin(ang + 0.5));
                                        ctx.stroke();
                                    } else if (s.tool === "text") {
                                        ctx.font = "bold 18px sans-serif";
                                        ctx.fillText(s.text || "Note", s.x0, s.y0);
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onPressed: mouse => {
                                    mkCanvas.liveShape = {
                                        tool: root.markupTool,
                                        color: String(root.markupColor),
                                        x0: mouse.x, y0: mouse.y, x1: mouse.x, y1: mouse.y,
                                        pts: [[mouse.x, mouse.y]],
                                        text: root.markupText
                                    };
                                    mkCanvas.requestPaint();
                                }
                                onPositionChanged: mouse => {
                                    if (!mkCanvas.liveShape) return;
                                    mkCanvas.liveShape.x1 = mouse.x;
                                    mkCanvas.liveShape.y1 = mouse.y;
                                    if (mkCanvas.liveShape.tool === "pen") mkCanvas.liveShape.pts.push([mouse.x, mouse.y]);
                                    mkCanvas.requestPaint();
                                }
                                onReleased: {
                                    if (!mkCanvas.liveShape) return;
                                    var next = root.markupShapes.slice();
                                    next.push(mkCanvas.liveShape);
                                    root.markupShapes = next;
                                    mkCanvas.liveShape = null;
                                    mkCanvas.requestPaint();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
