// EcosystemApps — Continuity / AirDrop / Phone Mirroring Hub, Time Machine UI (Btrfs/Snapper/Timeshift), and Finder Companion (Miller Column View + Tags + Inspector).
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "Ecosystem.js" as Eco
import "DockLogic.js" as DockLogic
import "Spotlight.js" as Spotlight
import "I18n.js" as I18n
import "Fonts.js" as Fonts

Scope {
    id: root
    property var hub: null
    readonly property var dock: hub ? hub.dock : null
    readonly property var bar: hub ? hub.bar : null
    readonly property bool darkMode: dock ? dock.darkMode : true
    readonly property color accent: dock ? dock.accent : "#0A84FF"
    readonly property string fam: dock ? dock.fontFamily : "Open Runde"
    readonly property string home: Quickshell.env("HOME") || ""

    function focusedScreen() {
        var fm = Hyprland.focusedMonitor;
        if (fm) {
            for (var i = 0; i < Quickshell.screens.length; i++)
                if (Quickshell.screens[i].name === fm.name) return Quickshell.screens[i];
        }
        return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
    }

    // ═════════════ 1. CONTINUITY / AIRDROP / PHONE MIRRORING ═════════════
    property bool continuityOpen: false
    property var kdeDevices: []
    property string continuityNotice: ""
    function openContinuity() { continuityOpen = true; continuityNotice = ""; if (!kdeProc.running) kdeProc.running = true; }
    function closeContinuity() { continuityOpen = false; }
    function toggleContinuity() { if (continuityOpen) closeContinuity(); else openContinuity(); }
    function shareFile(path) {
        var p = String(path || "").trim();
        if (!p) return;
        Quickshell.execDetached(["sh", "-c",
            "f=\"$1\"; if command -v localsend >/dev/null 2>&1; then exec localsend \"$f\"; " +
            "elif command -v localsend_app >/dev/null 2>&1; then exec localsend_app \"$f\"; " +
            "elif command -v kdeconnect-cli >/dev/null 2>&1; then id=$(kdeconnect-cli -a --id-only 2>/dev/null | head -n1); [ -n \"$id\" ] && exec kdeconnect-cli -d \"$id\" --share \"$f\"; fi; " +
            "notify-send 'AirDrop / Continuity' 'Install LocalSend or pair a device in KDE Connect'", "sh", p]);
    }
    Process {
        id: kdeClipProc
        property string devName: ""
        onExited: (code, status) => {
            root.continuityNotice = code === 0
                ? (I18n.tr("Clipboard sent to ") + devName)
                : (I18n.tr("Failed to send clipboard to ") + devName);
        }
    }
    function sendClipboardToDevice(devId, devName) {
        if (!devId || kdeClipProc.running) return;
        kdeClipProc.devName = devName || devId;
        kdeClipProc.command = ["kdeconnect-cli", "-d", devId, "--send-clipboard"];
        kdeClipProc.running = true;
    }
    Process {
        id: kdeProc
        command: ["sh", "-c", "command -v kdeconnect-cli >/dev/null 2>&1 && kdeconnect-cli -l 2>/dev/null || true"]
        stdout: StdioCollector { onStreamFinished: root.kdeDevices = Eco.parseKdeConnectDevices(text) }
    }

    Loader {
        id: continuityLoader
        active: root.continuityOpen
        sourceComponent: PanelWindow {
            screen: root.focusedScreen()
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "maccontinuity"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            Item {
                anchors.fill: parent; focus: true
                Keys.onEscapePressed: root.closeContinuity()
                Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.30); MouseArea { anchors.fill: parent; onClicked: root.closeContinuity() } }

                Rectangle {
                    anchors.centerIn: parent; width: 420; height: contCol.implicitHeight + 36; radius: 18
                    color: root.darkMode ? Qt.rgba(0.11, 0.11, 0.13, 0.96) : Qt.rgba(0.97, 0.97, 0.98, 0.98)
                    border.width: 1; border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.12)
                    MouseArea { anchors.fill: parent }

                    Column {
                        id: contCol
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 18
                        spacing: 10
                        Item {
                            width: parent.width; height: 24
                            Text {
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("AirDrop & Continuity")
                                color: root.darkMode ? "#FFFFFF" : "#1D1D1F"
                                font.family: Fonts.forWeight(Font.DemiBold, root.fam); font.pixelSize: 15; font.weight: Font.DemiBold
                            }
                            Text {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Close"); color: root.accent; font.pixelSize: 12
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.closeContinuity() }
                            }
                        }
                        Row {
                            width: parent.width; spacing: 8
                            Repeater {
                                model: [
                                    { id: "localsend", label: "LocalSend" },
                                    { id: "scrcpy", label: I18n.tr("Phone Mirroring") },
                                    { id: "refresh", label: I18n.tr("Refresh Devices") }
                                ]
                                delegate: Rectangle {
                                    id: cAct; required property var modelData
                                    height: 30; radius: 8; width: cActT.implicitWidth + 18
                                    color: cActMa.containsMouse ? root.accent : (root.darkMode ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06))
                                    Text { id: cActT; anchors.centerIn: parent; text: cAct.modelData.label; color: cActMa.containsMouse ? "#FFFFFF" : (root.darkMode ? "#FFFFFF" : "#1D1D1F"); font.pixelSize: 12 }
                                    MouseArea {
                                        id: cActMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var id = cAct.modelData.id;
                                            if (id === "localsend") Quickshell.execDetached(["sh", "-c", "command -v localsend >/dev/null 2>&1 && exec localsend || command -v localsend_app >/dev/null 2>&1 && exec localsend_app || notify-send 'AirDrop' 'Install LocalSend for nearby file drops'"]);
                                            else if (id === "scrcpy") Quickshell.execDetached(["sh", "-c", "command -v scrcpy >/dev/null 2>&1 && exec scrcpy --turn-screen-off || notify-send 'Phone Mirroring' 'Install scrcpy to mirror your phone'"]);
                                            else if (!kdeProc.running) kdeProc.running = true;
                                        }
                                    }
                                }
                            }
                        }
                        Rectangle { width: parent.width; height: 1; color: root.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10) }
                        Text {
                            visible: root.kdeDevices.length === 0
                            width: parent.width; wrapMode: Text.WordWrap
                            text: I18n.tr("No KDE Connect / GSConnect devices detected. Pair a device in KDE Connect or use LocalSend / scrcpy above.")
                            color: root.darkMode ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.55); font.pixelSize: 12
                        }
                        Repeater {
                            model: root.kdeDevices
                            delegate: Rectangle {
                                id: devRow; required property var modelData
                                width: contCol.width; height: 48; radius: 10
                                color: root.darkMode ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04)
                                Column {
                                    x: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 1
                                    Text { text: devRow.modelData.name; color: root.darkMode ? "#FFFFFF" : "#1D1D1F"; font.pixelSize: 13; font.weight: Font.DemiBold }
                                    Text { text: devRow.modelData.reachable ? I18n.tr("Connected") : I18n.tr("Offline"); color: devRow.modelData.reachable ? "#30D158" : "#8E8E93"; font.pixelSize: 11 }
                                }
                                Row {
                                    anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                                    Rectangle {
                                        height: 24; radius: 6; width: cbTxt.implicitWidth + 12
                                        color: devRow.modelData.reachable ? root.accent : Qt.rgba(1, 1, 1, 0.10)
                                        opacity: devRow.modelData.reachable ? 1 : 0.45
                                        Text { id: cbTxt; anchors.centerIn: parent; text: I18n.tr("Send Clipboard"); color: "#FFFFFF"; font.pixelSize: 11 }
                                        MouseArea {
                                            anchors.fill: parent; enabled: devRow.modelData.reachable; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: root.sendClipboardToDevice(devRow.modelData.id, devRow.modelData.name)
                                        }
                                    }
                                    Rectangle {
                                        height: 24; radius: 6; width: rgTxt.implicitWidth + 12
                                        color: root.darkMode ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08)
                                        opacity: devRow.modelData.reachable ? 1 : 0.45
                                        Text { id: rgTxt; anchors.centerIn: parent; text: I18n.tr("Ring"); color: root.darkMode ? "#FFFFFF" : "#1D1D1F"; font.pixelSize: 11 }
                                        MouseArea { anchors.fill: parent; enabled: devRow.modelData.reachable; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: Quickshell.execDetached(["kdeconnect-cli", "-d", devRow.modelData.id, "--ring"]) }
                                    }
                                }
                            }
                        }
                        Text { visible: root.continuityNotice !== ""; text: root.continuityNotice; color: "#30D158"; font.pixelSize: 12 }
                    }
                }
            }
        }
    }

    // ═════════════ 2. TIME MACHINE UI (Btrfs + Snapper / Timeshift) ═════════════
    property bool timeMachineOpen: false
    property var tmSnapshots: []
    property int tmSelected: 0
    property string tmSubPath: home.indexOf("/") === 0 ? home.substring(1) : "home"
    property var tmFiles: []
    property string tmStatus: ""
    function openTimeMachine() {
        timeMachineOpen = true;
        tmStatus = "";
        tmSelected = 0;
        if (!tmListProc.running) tmListProc.running = true;
    }
    function closeTimeMachine() { timeMachineOpen = false; }
    function toggleTimeMachine() { if (timeMachineOpen) closeTimeMachine(); else openTimeMachine(); }
    function tmBrowseCurrent() {
        if (tmSnapshots.length === 0) { tmFiles = []; return; }
        var snap = tmSnapshots[Math.max(0, Math.min(tmSelected, tmSnapshots.length - 1))];
        if (!snap) return;
        var full = snap.path + (tmSubPath ? ("/" + tmSubPath) : "");
        tmDirProc.running = false;
        tmDirProc.targetPath = full;
        tmDirProc.running = true;
    }
    Process {
        id: tmRestoreProc
        property string destPath: ""
        onExited: (code, status) => {
            if (code === 0) {
                root.tmStatus = I18n.tr("Restored copy to ") + destPath;
                Quickshell.execDetached(["notify-send", "-a", "macbar", "Time Machine", "Restored to " + destPath]);
            } else {
                root.tmStatus = I18n.tr("Restore failed for ") + destPath;
            }
        }
    }
    function tmRestoreFile(snapFilePath, fileName) {
        if (tmRestoreProc.running) return;
        var dest = root.home + "/Desktop/" + fileName + ".restored";
        tmRestoreProc.destPath = dest;
        tmRestoreProc.command = ["sh", "-c", "mkdir -p \"$(dirname \"$2\")\" && cp -a -- \"$1\" \"$2\"", "sh", snapFilePath, dest];
        tmRestoreProc.running = true;
    }
    Process {
        id: tmListProc
        command: ["sh", "-c",
            "if command -v snapper >/dev/null 2>&1; then snapper --csvout list 2>/dev/null || snapper list 2>/dev/null; " +
            "elif [ -d /run/timeshift/backup/timeshift-btrfs/snapshots ]; then echo 'TIMESHIFT'; ls -1r /run/timeshift/backup/timeshift-btrfs/snapshots 2>/dev/null; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                var raw = text.trim();
                if (raw.indexOf("TIMESHIFT") === 0) root.tmSnapshots = Eco.parseTimeshiftList(raw.substring(9));
                else root.tmSnapshots = Eco.parseSnapperList(raw);
                root.tmBrowseCurrent();
            }
        }
    }
    Process {
        id: tmDirProc
        property string targetPath: ""
        command: ["sh", "-c", "cd \"$1\" 2>/dev/null || exit 0; find . -maxdepth 1 -mindepth 1 -printf '%T@\\t%y\\t%f\\n' 2>/dev/null | sort -rn | head -n 60", "sh", targetPath]
        stdout: StdioCollector { onStreamFinished: root.tmFiles = DockLogic.parseFolderListing(text, tmDirProc.targetPath) }
    }

    Loader {
        id: tmLoader
        active: root.timeMachineOpen
        sourceComponent: PanelWindow {
            screen: root.focusedScreen()
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "mactimemachine"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            Item {
                anchors.fill: parent; focus: true
                Keys.onEscapePressed: root.closeTimeMachine()
                Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.48); MouseArea { anchors.fill: parent; onClicked: root.closeTimeMachine() } }

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 60, 820)
                    height: Math.min(parent.height - 80, 560)
                    radius: 18
                    color: root.darkMode ? Qt.rgba(0.10, 0.10, 0.13, 0.96) : Qt.rgba(0.97, 0.97, 0.98, 0.98)
                    border.width: 1; border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.12)
                    MouseArea { anchors.fill: parent }

                    Column {
                        anchors.fill: parent; anchors.margins: 16; spacing: 10
                        Item {
                            width: parent.width; height: 28
                            Text {
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Time Machine (Btrfs Snapshots)")
                                color: root.darkMode ? "#FFFFFF" : "#1D1D1F"
                                font.family: Fonts.forWeight(Font.DemiBold, root.fam); font.pixelSize: 15; font.weight: Font.DemiBold
                            }
                            Text {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Close"); color: root.accent; font.pixelSize: 12
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.closeTimeMachine() }
                            }
                        }
                        Row {
                            width: parent.width; height: parent.height - 64; spacing: 12
                            // Snapshot timeline sidebar
                            Rectangle {
                                width: 240; height: parent.height; radius: 12
                                color: root.darkMode ? Qt.rgba(0, 0, 0, 0.25) : Qt.rgba(0, 0, 0, 0.05)
                                clip: true
                                ListView {
                                    anchors.fill: parent; anchors.margins: 6
                                    model: root.tmSnapshots
                                    delegate: Rectangle {
                                        id: tmRow; required property var modelData; required property int index
                                        width: ListView.view.width; height: 42; radius: 8
                                        color: root.tmSelected === index ? root.accent : "transparent"
                                        Column {
                                            x: 8; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 16
                                            Text { width: parent.width; elide: Text.ElideRight; text: "#" + tmRow.modelData.id + " · " + tmRow.modelData.desc; color: root.tmSelected === tmRow.index ? "#FFFFFF" : (root.darkMode ? "#FFFFFF" : "#1D1D1F"); font.pixelSize: 12; font.weight: Font.DemiBold }
                                            Text { width: parent.width; elide: Text.ElideRight; text: tmRow.modelData.date; color: root.tmSelected === tmRow.index ? Qt.rgba(1, 1, 1, 0.85) : "#8E8E93"; font.pixelSize: 10 }
                                        }
                                        MouseArea { anchors.fill: parent; onClicked: { root.tmSelected = tmRow.index; root.tmBrowseCurrent(); } }
                                    }
                                }
                                Text {
                                    visible: root.tmSnapshots.length === 0
                                    anchors.centerIn: parent; width: parent.width - 24; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                                    text: I18n.tr("No Snapper or Timeshift snapshots found.")
                                    color: "#8E8E93"; font.pixelSize: 12
                                }
                            }
                            // Files inside selected snapshot
                            Rectangle {
                                width: parent.width - 252; height: parent.height; radius: 12
                                color: root.darkMode ? Qt.rgba(0, 0, 0, 0.25) : Qt.rgba(0, 0, 0, 0.05)
                                clip: true
                                Column {
                                    anchors.fill: parent; anchors.margins: 8; spacing: 6
                                    Row {
                                        width: parent.width; spacing: 8
                                        Rectangle {
                                            height: 24; radius: 6; width: tmUp.implicitWidth + 14
                                            opacity: root.tmSnapshots.length > 0 ? 1 : 0.4
                                            color: root.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
                                            Text { id: tmUp; anchors.centerIn: parent; text: "\u2190 Up"; color: root.darkMode ? "#FFFFFF" : "#1D1D1F"; font.pixelSize: 11 }
                                            MouseArea {
                                                anchors.fill: parent; enabled: root.tmSnapshots.length > 0; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: {
                                                    var p = root.tmSubPath;
                                                    var ix = p.lastIndexOf("/");
                                                    root.tmSubPath = ix > 0 ? p.substring(0, ix) : "";
                                                    root.tmBrowseCurrent();
                                                }
                                            }
                                        }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: "/" + root.tmSubPath; color: "#8E8E93"; font.pixelSize: 12; elide: Text.ElideMiddle; width: parent.width - 70 }
                                    }
                                    ListView {
                                        width: parent.width; height: parent.height - 32; clip: true
                                        model: root.tmFiles
                                        delegate: Rectangle {
                                            id: tmf; required property var modelData
                                            width: ListView.view.width; height: 30; radius: 6
                                            color: tmfMa.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.24) : "transparent"
                                            Text {
                                                x: 8; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 150; elide: Text.ElideRight
                                                text: (tmf.modelData.isDir ? "\ud83d\udcc1 " : "\ud83d\udcc4 ") + tmf.modelData.name
                                                color: root.darkMode ? "#FFFFFF" : "#1D1D1F"; font.pixelSize: 12
                                            }
                                            Row {
                                                anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                                                Rectangle {
                                                    visible: !tmf.modelData.isDir
                                                    height: 22; radius: 5; width: tmPv.implicitWidth + 10; color: root.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
                                                    Text { id: tmPv; anchors.centerIn: parent; text: I18n.tr("Preview"); color: root.darkMode ? "#FFFFFF" : "#1D1D1F"; font.pixelSize: 10 }
                                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (root.hub && root.hub.quickLook) root.hub.quickLook.openPath(tmf.modelData.path); } }
                                                }
                                                Rectangle {
                                                    height: 22; radius: 5; width: tmRs.implicitWidth + 12; color: root.accent
                                                    Text { id: tmRs; anchors.centerIn: parent; text: I18n.tr("Restore"); color: "#FFFFFF"; font.pixelSize: 10 }
                                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.tmRestoreFile(tmf.modelData.path, tmf.modelData.name) }
                                                }
                                            }
                                            MouseArea {
                                                id: tmfMa; anchors.fill: parent; hoverEnabled: true; z: -1
                                                onClicked: {
                                                    if (tmf.modelData.isDir) {
                                                        root.tmSubPath = root.tmSubPath ? (root.tmSubPath + "/" + tmf.modelData.name) : tmf.modelData.name;
                                                        root.tmBrowseCurrent();
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        Text { visible: root.tmStatus !== ""; text: root.tmStatus; color: "#30D158"; font.pixelSize: 12 }
                    }
                }
            }
        }
    }

    // ═════════════ 3. FINDER COMPANION (Miller Column View + Color Tags + Inspector) ═════════════
    property bool finderOpen: false
    property string finderDir: home
    property string finderParentDir: Eco.parentDir(home)
    property var finderParentItems: []
    property var finderCurItems: []
    property var finderSelected: null
    property var finderTags: ({})
    property string finderTagFilter: ""

    FileView {
        id: finderTagsStore
        path: root.home + "/.config/macshell/finder-tags.json"
        printErrors: false
        onLoaded: { try { root.finderTags = JSON.parse(text()); } catch (e) { root.finderTags = ({}); } }
    }
    function saveFinderTags() {
        Quickshell.execDetached(["sh", "-c", "d=\"$HOME/.config/macshell\"; mkdir -p \"$d\" && t=$(mktemp \"$d/finder-tags.XXXXXX\") && printf '%s' \"$1\" > \"$t\" && mv -f \"$t\" \"$d/finder-tags.json\"", "sh", JSON.stringify(finderTags, null, 2)]);
    }
    function toggleFinderTag(path, tagId) {
        finderTags = Eco.toggleFileTag(finderTags, path, tagId);
        saveFinderTags();
    }
    function openFinder(dirPath) {
        finderOpen = true;
        finderTagFilter = "";
        finderNavigate(dirPath || home);
    }
    function closeFinder() { finderOpen = false; }
    function toggleFinder(dirPath) { if (finderOpen) closeFinder(); else openFinder(dirPath); }
    function finderNavigate(dirPath) {
        var clean = String(dirPath || home).replace(/\/+$/, "") || "/";
        finderDir = clean;
        finderParentDir = Eco.parentDir(clean);
        finderSelected = null;
        finderTagFilter = "";
        fnCurProc.running = false; fnCurProc.targetPath = finderDir; fnCurProc.running = true;
        fnParProc.running = false; fnParProc.targetPath = finderParentDir; fnParProc.running = true;
    }
    Process {
        id: fnCurProc
        property string targetPath: ""
        command: ["sh", "-c", "cd \"$1\" 2>/dev/null || exit 0; find . -maxdepth 1 -mindepth 1 -printf '%T@\\t%y\\t%f\\n' 2>/dev/null | sort -t\"$(printf '\\t')\" -k2,2 -k3,3f | head -n 120", "sh", targetPath]
        stdout: StdioCollector { onStreamFinished: root.finderCurItems = DockLogic.parseFolderListing(text, fnCurProc.targetPath) }
    }
    Process {
        id: fnParProc
        property string targetPath: ""
        command: ["sh", "-c", "cd \"$1\" 2>/dev/null || exit 0; find . -maxdepth 1 -mindepth 1 -type d -printf '%T@\\t%y\\t%f\\n' 2>/dev/null | sort -t\"$(printf '\\t')\" -k3,3f | head -n 80", "sh", targetPath]
        stdout: StdioCollector { onStreamFinished: root.finderParentItems = DockLogic.parseFolderListing(text, fnParProc.targetPath) }
    }

    Loader {
        id: finderLoader
        active: root.finderOpen
        sourceComponent: PanelWindow {
            screen: root.focusedScreen()
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "macfinder"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            readonly property var shownCurItems: {
                if (root.finderTagFilter === "") return root.finderCurItems;
                var ps = Eco.taggedPaths(root.finderTags, root.finderTagFilter);
                return ps.map(function (p) {
                    var nm = p.substring(p.lastIndexOf("/") + 1) || p;
                    return { name: nm, path: p, isDir: false, isImage: Spotlight.fileKindFromPath(p, false) === "image" };
                });
            }

            Item {
                anchors.fill: parent; focus: true
                Keys.onEscapePressed: root.closeFinder()
                Keys.onSpacePressed: if (root.finderSelected && root.hub && root.hub.quickLook) root.hub.quickLook.togglePath(root.finderSelected.path)
                Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.34); MouseArea { anchors.fill: parent; onClicked: root.closeFinder() } }

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 60, 960)
                    height: Math.min(parent.height - 80, 600)
                    radius: 18
                    color: root.darkMode ? Qt.rgba(0.11, 0.11, 0.13, 0.96) : Qt.rgba(0.97, 0.97, 0.98, 0.98)
                    border.width: 1; border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.12)
                    MouseArea { anchors.fill: parent }

                    Column {
                        anchors.fill: parent; anchors.margins: 14; spacing: 8
                        // Title bar
                        Item {
                            width: parent.width; height: 28
                            Rectangle {
                                x: 0; anchors.verticalCenter: parent.verticalCenter
                                width: 13; height: 13; radius: 6.5; color: "#FF5F57"
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.closeFinder() }
                            }
                            Text {
                                x: 24; anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Finder") + " \u2014 " + (root.finderTagFilter ? ("Tag: " + root.finderTagFilter) : root.finderDir)
                                color: root.darkMode ? "#FFFFFF" : "#1D1D1F"
                                font.family: Fonts.forWeight(Font.DemiBold, root.fam); font.pixelSize: 14; font.weight: Font.DemiBold
                            }
                            Rectangle {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                height: 24; radius: 6; width: fnExtT.implicitWidth + 14
                                color: root.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
                                Text { id: fnExtT; anchors.centerIn: parent; text: I18n.tr("Open External"); color: root.darkMode ? "#FFFFFF" : "#1D1D1F"; font.pixelSize: 11 }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { Quickshell.execDetached(["xdg-open", root.finderDir]); root.closeFinder(); } }
                            }
                        }

                        // Sidebar + 3-column Miller View (responsive proportional widths)
                        Row {
                            id: fnMillerRow
                            width: parent.width; height: parent.height - 38; spacing: 8
                            readonly property bool showParentCol: width >= 540
                            readonly property int sideW: Math.min(156, Math.max(115, Math.floor(width * 0.22)))
                            readonly property int gaps: showParentCol ? 24 : 16
                            readonly property int remW: Math.max(180, width - sideW - gaps)
                            readonly property int col1W: showParentCol ? Math.floor(remW * 0.24) : 0
                            readonly property int col2W: showParentCol ? Math.floor(remW * 0.42) : Math.floor(remW * 0.56)
                            readonly property int col3W: Math.max(100, remW - col1W - col2W)

                            // Sidebar: Favorites + Finder Color Tags (scrollable & clipped)
                            Rectangle {
                                width: fnMillerRow.sideW; height: parent.height; radius: 12; clip: true
                                color: root.darkMode ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04)
                                Flickable {
                                    anchors.fill: parent; anchors.margins: 8
                                    contentHeight: fnSideCol.implicitHeight; clip: true
                                    Column {
                                        id: fnSideCol
                                        width: parent.width; spacing: 2
                                    Text { text: I18n.tr("Favorites"); color: "#8E8E93"; font.pixelSize: 10; font.weight: Font.DemiBold }
                                    Repeater {
                                        model: [
                                            { label: "Home", path: root.home },
                                            { label: "Desktop", path: root.home + "/Desktop" },
                                            { label: "Documents", path: root.home + "/Documents" },
                                            { label: "Downloads", path: root.home + "/Downloads" },
                                            { label: "Pictures", path: root.home + "/Pictures" }
                                        ]
                                        delegate: Rectangle {
                                            id: favR; required property var modelData
                                            width: parent.width; height: 26; radius: 6
                                            color: root.finderDir === modelData.path && root.finderTagFilter === "" ? root.accent : "transparent"
                                            Text { x: 8; anchors.verticalCenter: parent.verticalCenter; text: favR.modelData.label; color: root.finderDir === favR.modelData.path && root.finderTagFilter === "" ? "#FFFFFF" : (root.darkMode ? "#FFFFFF" : "#1D1D1F"); font.pixelSize: 12 }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.finderNavigate(favR.modelData.path) }
                                        }
                                    }
                                    Item { width: 1; height: 6 }
                                    Text { text: I18n.tr("Tags"); color: "#8E8E93"; font.pixelSize: 10; font.weight: Font.DemiBold }
                                    Repeater {
                                        model: Eco.FINDER_TAGS
                                        delegate: Rectangle {
                                            id: tagF; required property var modelData
                                            width: parent.width; height: 24; radius: 6
                                            color: root.finderTagFilter === modelData.id ? root.accent : "transparent"
                                            Row {
                                                x: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 7
                                                Rectangle { width: 9; height: 9; radius: 4.5; anchors.verticalCenter: parent.verticalCenter; color: tagF.modelData.color }
                                                Text { text: tagF.modelData.name; color: root.finderTagFilter === tagF.modelData.id ? "#FFFFFF" : (root.darkMode ? "#FFFFFF" : "#1D1D1F"); font.pixelSize: 12 }
                                            }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.finderTagFilter = root.finderTagFilter === tagF.modelData.id ? "" : tagF.modelData.id; root.finderSelected = null; } }
                                        }
                                    }
                                }
                                }
                            }

                            // Column 1: Parent directory
                            Rectangle {
                                visible: fnMillerRow.showParentCol
                                width: fnMillerRow.col1W; height: parent.height; radius: 12
                                color: root.darkMode ? Qt.rgba(0, 0, 0, 0.22) : Qt.rgba(0, 0, 0, 0.04)
                                clip: true
                                ListView {
                                    anchors.fill: parent; anchors.margins: 6
                                    model: root.finderParentItems
                                    delegate: Rectangle {
                                        id: pColR; required property var modelData
                                        width: ListView.view.width; height: 26; radius: 6
                                        color: root.finderDir === modelData.path ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.32) : "transparent"
                                        Text { x: 8; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 14; elide: Text.ElideRight; text: "\ud83d\udcc1 " + pColR.modelData.name; color: root.darkMode ? "#FFFFFF" : "#1D1D1F"; font.pixelSize: 12 }
                                        MouseArea { anchors.fill: parent; onClicked: root.finderNavigate(pColR.modelData.path) }
                                    }
                                }
                            }

                            // Column 2: Current directory
                            Rectangle {
                                width: fnMillerRow.col2W; height: parent.height; radius: 12
                                color: root.darkMode ? Qt.rgba(0, 0, 0, 0.22) : Qt.rgba(0, 0, 0, 0.04)
                                clip: true
                                ListView {
                                    anchors.fill: parent; anchors.margins: 6
                                    model: shownCurItems
                                    delegate: Rectangle {
                                        id: cColR; required property var modelData
                                        readonly property bool sel: root.finderSelected && root.finderSelected.path === modelData.path
                                        width: ListView.view.width; height: 28; radius: 6
                                        color: sel ? root.accent : "transparent"
                                        Row {
                                            x: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 6; width: parent.width - 16
                                            Text {
                                                width: parent.width - 36; elide: Text.ElideRight
                                                text: (cColR.modelData.isDir ? "\ud83d\udcc1 " : "\ud83d\udcc4 ") + cColR.modelData.name
                                                color: cColR.sel ? "#FFFFFF" : (root.darkMode ? "#FFFFFF" : "#1D1D1F"); font.pixelSize: 12
                                            }
                                            Row {
                                                spacing: 3; anchors.verticalCenter: parent.verticalCenter
                                                Repeater {
                                                    model: root.finderTags[cColR.modelData.path] || []
                                                    delegate: Rectangle {
                                                        required property string modelData
                                                        width: 7; height: 7; radius: 3.5
                                                        color: {
                                                            for (var ti = 0; ti < Eco.FINDER_TAGS.length; ti++)
                                                                if (Eco.FINDER_TAGS[ti].id === modelData) return Eco.FINDER_TAGS[ti].color;
                                                            return "#8E8E93";
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: root.finderSelected = cColR.modelData
                                            onDoubleClicked: {
                                                if (cColR.modelData.isDir) root.finderNavigate(cColR.modelData.path);
                                                else Quickshell.execDetached(["xdg-open", cColR.modelData.path]);
                                            }
                                        }
                                    }
                                }
                            }

                            // Column 3: Inspector & Quick Actions
                            Rectangle {
                                width: fnMillerRow.col3W; height: parent.height; radius: 12; clip: true
                                color: root.darkMode ? Qt.rgba(0, 0, 0, 0.22) : Qt.rgba(0, 0, 0, 0.04)
                                Column {
                                    visible: root.finderSelected !== null
                                    anchors.fill: parent; anchors.margins: 12; spacing: 8
                                    Image {
                                        visible: !!(root.finderSelected && root.finderSelected.isImage)
                                        width: parent.width; height: 150
                                        source: (root.finderSelected && root.finderSelected.isImage) ? ("file://" + encodeURI(root.finderSelected.path)) : ""
                                        fillMode: Image.PreserveAspectFit; asynchronous: true; smooth: true
                                    }
                                    Text {
                                        width: parent.width; wrapMode: Text.WordWrap
                                        text: root.finderSelected ? root.finderSelected.name : ""
                                        color: root.darkMode ? "#FFFFFF" : "#1D1D1F"; font.pixelSize: 14; font.weight: Font.DemiBold
                                    }
                                    Text {
                                        width: parent.width; elide: Text.ElideMiddle
                                        text: root.finderSelected ? root.finderSelected.path : ""
                                        color: "#8E8E93"; font.pixelSize: 10
                                    }
                                    // Tag picker
                                    Row {
                                        spacing: 6
                                        Repeater {
                                            model: Eco.FINDER_TAGS
                                            delegate: Rectangle {
                                                id: inspTag; required property var modelData
                                                readonly property bool hasTag: root.finderSelected && Array.isArray(root.finderTags[root.finderSelected.path]) && root.finderTags[root.finderSelected.path].indexOf(modelData.id) >= 0
                                                width: 16; height: 16; radius: 8
                                                color: modelData.color
                                                border.width: hasTag ? 2 : 0; border.color: "#FFFFFF"
                                                opacity: hasTag ? 1 : 0.45
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.finderSelected) root.toggleFinderTag(root.finderSelected.path, inspTag.modelData.id) }
                                            }
                                        }
                                    }
                                    Rectangle { width: parent.width; height: 1; color: root.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10) }
                                    // Quick Actions
                                    Repeater {
                                        model: [
                                            { id: "open", label: I18n.tr("Open") },
                                            { id: "ql", label: I18n.tr("Quick Look") },
                                            { id: "markup", label: I18n.tr("Markup (Images)") },
                                            { id: "share", label: I18n.tr("Share via AirDrop") },
                                            { id: "copy", label: I18n.tr("Copy Path") }
                                        ]
                                        delegate: Rectangle {
                                            id: qaBtn; required property var modelData
                                            visible: modelData.id !== "markup" || !!(root.finderSelected && root.finderSelected.isImage)
                                            width: parent.width; height: 28; radius: 7
                                            color: qaMa.containsMouse ? root.accent : (root.darkMode ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06))
                                            Text { anchors.centerIn: parent; text: qaBtn.modelData.label; color: qaMa.containsMouse ? "#FFFFFF" : (root.darkMode ? "#FFFFFF" : "#1D1D1F"); font.pixelSize: 12 }
                                            MouseArea {
                                                id: qaMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    var s = root.finderSelected; if (!s) return;
                                                    var aid = qaBtn.modelData.id;
                                                    if (aid === "open") { if (s.isDir) root.finderNavigate(s.path); else Quickshell.execDetached(["xdg-open", s.path]); }
                                                    else if (aid === "ql" && root.hub && root.hub.quickLook) root.hub.quickLook.openPath(s.path);
                                                    else if (aid === "markup" && root.hub && root.hub.capture) { root.closeFinder(); root.hub.capture.openMarkup(s.path); }
                                                    else if (aid === "share") root.shareFile(s.path);
                                                    else if (aid === "copy") Quickshell.execDetached(["wl-copy", s.path]);
                                                }
                                            }
                                        }
                                    }
                                }
                                Text {
                                    visible: root.finderSelected === null
                                    anchors.centerIn: parent
                                    width: parent.width - 16
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                    text: I18n.tr("Select a file to inspect")
                                    color: "#8E8E93"; font.pixelSize: 12
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
