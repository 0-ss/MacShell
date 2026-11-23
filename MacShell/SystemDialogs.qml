// SystemDialogs — macOS Force Quit Applications (Cmd+Opt+Esc) & Native Liquid Glass Activity Monitor.
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
    readonly property var dock: hub ? hub.dock : null
    readonly property var bar: hub ? hub.bar : null
    readonly property bool darkMode: dock ? dock.darkMode : true
    readonly property color accent: dock ? dock.accent : "#0A84FF"
    readonly property string fam: dock ? dock.fontFamily : "Open Runde"

    // ── Force Quit dialog state ──
    property bool forceQuitOpen: false
    property int fqSelected: 0
    function openForceQuit() { forceQuitOpen = true; fqSelected = 0; }
    function closeForceQuit() { forceQuitOpen = false; }
    function toggleForceQuit() { if (forceQuitOpen) closeForceQuit(); else openForceQuit(); }

    // ── Native Activity Monitor state ──
    property bool activityOpen: false
    property string actTab: "cpu"       // "cpu" | "memory" | "disk" | "network"
    property string actFilter: ""
    property var procList: []           // [{ pid, name, cpu, mem, rssMb }]
    property int actSelectedPid: -1
    function openActivity() { activityOpen = true; refreshProcs(); }
    function closeActivity() { activityOpen = false; }
    function toggleActivity() { if (activityOpen) closeActivity(); else openActivity(); }

    function refreshProcs() {
        if (!procPoll.running) procPoll.running = true;
    }
    Process {
        id: procPoll
        command: ["sh", "-c",
            root.actTab === "memory"
            ? "ps -eo pid=,comm=,pcpu=,pmem=,rss= --sort=-rss | head -n 45"
            : "ps -eo pid=,comm=,pcpu=,pmem=,rss= --sort=-pcpu | head -n 45"]
        stdout: StdioCollector {
            onStreamFinished: {
                var out = [], lines = text.trim().split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var m = /^\s*(\d+)\s+(\S+)\s+([\d.]+)\s+([\d.]+)\s+(\d+)/.exec(lines[i]);
                    if (!m) continue;
                    out.push({
                        pid: parseInt(m[1], 10),
                        name: m[2],
                        cpu: parseFloat(m[3]) || 0,
                        mem: parseFloat(m[4]) || 0,
                        rssMb: Math.round((parseInt(m[5], 10) || 0) / 1024)
                    });
                }
                root.procList = out;
            }
        }
    }
    Timer {
        interval: 2000; repeat: true
        running: root.activityOpen
        onTriggered: root.refreshProcs()
    }
    onActTabChanged: if (activityOpen) refreshProcs()

    function focusedScreen() {
        var fm = Hyprland.focusedMonitor;
        if (fm) {
            for (var i = 0; i < Quickshell.screens.length; i++)
                if (Quickshell.screens[i].name === fm.name) return Quickshell.screens[i];
        }
        return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
    }

    // ═════════════ FORCE QUIT APPLICATIONS (Cmd+Opt+Esc) ═════════════
    Loader {
        id: fqLoader
        active: root.forceQuitOpen
        sourceComponent: PanelWindow {
            screen: root.focusedScreen()
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "macforcequit"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            readonly property var runningApps: {
                var ts = Hyprland.toplevels.values, byApp = {}, out = [];
                for (var i = 0; i < ts.length; i++) {
                    var o = ts[i].lastIpcObject || {};
                    var cls = String(o["class"] || (ts[i].wayland ? ts[i].wayland.appId : "") || "");
                    if (!cls || cls === "org.quickshell") continue;
                    var key = cls.toLowerCase();
                    if (!byApp[key]) {
                        var rec = { key: key, name: cls, pid: Number(o.pid) || 0, count: 1 };
                        byApp[key] = rec;
                        out.push(rec);
                    } else {
                        byApp[key].count++;
                    }
                }
                return out;
            }

            Item {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.closeForceQuit()

                Rectangle {
                    anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.28)
                    MouseArea { anchors.fill: parent; onClicked: root.closeForceQuit() }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 360; height: 380; radius: 18
                    color: root.darkMode ? Qt.rgba(0.12, 0.12, 0.14, 0.96) : Qt.rgba(0.97, 0.97, 0.98, 0.98)
                    border.width: 1; border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.12)
                    MouseArea { anchors.fill: parent }

                    Column {
                        anchors.fill: parent; anchors.margins: 16; spacing: 10
                        Text {
                            text: I18n.tr("Force Quit Applications")
                            color: root.darkMode ? "#FFFFFF" : "#1D1D1F"
                            font.family: Fonts.forWeight(Font.DemiBold, root.fam); font.pixelSize: 15; font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width; wrapMode: Text.WordWrap
                            text: I18n.tr("If an app doesn't respond, select its name and click Force Quit.")
                            color: root.darkMode ? Qt.rgba(1, 1, 1, 0.62) : Qt.rgba(0, 0, 0, 0.60)
                            font.pixelSize: 12
                        }
                        Rectangle {
                            width: parent.width; height: 224; radius: 10
                            color: root.darkMode ? Qt.rgba(0, 0, 0, 0.25) : Qt.rgba(0, 0, 0, 0.05)
                            border.width: 1; border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)
                            clip: true
                            ListView {
                                anchors.fill: parent; anchors.margins: 6
                                model: runningApps
                                delegate: Rectangle {
                                    id: fqRow; required property var modelData; required property int index
                                    width: ListView.view.width; height: 34; radius: 8
                                    color: root.fqSelected === index ? root.accent : "transparent"
                                    Text {
                                        x: 10; anchors.verticalCenter: parent.verticalCenter
                                        text: fqRow.modelData.name + (fqRow.modelData.count > 1 ? (" (" + fqRow.modelData.count + ")") : "")
                                        color: root.fqSelected === fqRow.index ? "#FFFFFF" : (root.darkMode ? "#FFFFFF" : "#1D1D1F")
                                        font.family: Fonts.forWeight(Font.Medium, root.fam); font.pixelSize: 13
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.fqSelected = fqRow.index }
                                }
                            }
                        }
                        Item {
                            width: parent.width; height: 32
                            Rectangle {
                                anchors.left: parent.left; height: 30; radius: 8; width: fqCan.implicitWidth + 20
                                color: root.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
                                Text { id: fqCan; anchors.centerIn: parent; text: I18n.tr("Close"); color: root.darkMode ? "#FFFFFF" : "#1D1D1F"; font.pixelSize: 12.5 }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.closeForceQuit() }
                            }
                            Rectangle {
                                anchors.right: parent.right; height: 30; radius: 8; width: fqKill.implicitWidth + 24
                                color: runningApps.length > 0 ? "#FF453A" : Qt.rgba(1, 1, 1, 0.15)
                                Text { id: fqKill; anchors.centerIn: parent; text: I18n.tr("Force Quit"); color: "#FFFFFF"; font.pixelSize: 12.5; font.weight: Font.DemiBold }
                                MouseArea {
                                    anchors.fill: parent; enabled: runningApps.length > 0; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var idx = Math.max(0, Math.min(root.fqSelected, runningApps.length - 1));
                                        var target = runningApps[idx];
                                        if (target && target.pid > 0) Quickshell.execDetached(["kill", "-9", String(target.pid)]);
                                        else if (target) Quickshell.execDetached(["pkill", "-9", "-f", target.name]);
                                        root.closeForceQuit();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ═════════════ NATIVE LIQUID GLASS ACTIVITY MONITOR ═════════════
    Loader {
        id: actLoader
        active: root.activityOpen
        sourceComponent: PanelWindow {
            screen: root.focusedScreen()
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "macactivity"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            readonly property var filteredProcs: {
                var q = root.actFilter.trim().toLowerCase();
                if (!q) return root.procList;
                return root.procList.filter(function (p) {
                    return String(p.name).toLowerCase().indexOf(q) >= 0 || String(p.pid).indexOf(q) >= 0;
                });
            }

            Item {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.closeActivity()

                Rectangle {
                    anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.30)
                    MouseArea { anchors.fill: parent; onClicked: root.closeActivity() }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 60, 740)
                    height: Math.min(parent.height - 80, 540)
                    radius: 18
                    color: root.darkMode ? Qt.rgba(0.11, 0.11, 0.13, 0.96) : Qt.rgba(0.97, 0.97, 0.98, 0.98)
                    border.width: 1; border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.12)
                    MouseArea { anchors.fill: parent }

                    Column {
                        anchors.fill: parent; anchors.margins: 16; spacing: 10
                        // Header row: close, title, tabs, search
                        Item {
                            width: parent.width; height: 32
                            Rectangle {
                                x: 0; anchors.verticalCenter: parent.verticalCenter
                                width: 13; height: 13; radius: 6.5; color: "#FF5F57"
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.closeActivity() }
                            }
                            Text {
                                x: 24; anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Activity Monitor")
                                color: root.darkMode ? "#FFFFFF" : "#1D1D1F"
                                font.family: Fonts.forWeight(Font.DemiBold, root.fam); font.pixelSize: 14; font.weight: Font.DemiBold
                            }
                            Row {
                                anchors.centerIn: parent; spacing: 4
                                Repeater {
                                    model: [
                                        { id: "cpu", label: "CPU" },
                                        { id: "memory", label: I18n.tr("Memory") },
                                        { id: "disk", label: I18n.tr("Disk") },
                                        { id: "network", label: I18n.tr("Network") }
                                    ]
                                    delegate: Rectangle {
                                        id: aTab; required property var modelData
                                        height: 26; radius: 8; width: aTabTxt.implicitWidth + 18
                                        color: root.actTab === aTab.modelData.id ? root.accent : (root.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
                                        Text { id: aTabTxt; anchors.centerIn: parent; text: aTab.modelData.label; color: root.actTab === aTab.modelData.id ? "#FFFFFF" : (root.darkMode ? "#FFFFFF" : "#1D1D1F"); font.pixelSize: 12 }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.actTab = aTab.modelData.id }
                                    }
                                }
                            }
                            Rectangle {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                width: 150; height: 26; radius: 7
                                color: root.darkMode ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.06)
                                border.width: 1; border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10)
                                TextInput {
                                    anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                                    verticalAlignment: TextInput.AlignVCenter; clip: true
                                    color: root.darkMode ? "#FFFFFF" : "#1D1D1F"; font.pixelSize: 12
                                    text: root.actFilter; onTextEdited: root.actFilter = text
                                }
                                Text {
                                    visible: root.actFilter === ""
                                    x: 8; anchors.verticalCenter: parent.verticalCenter
                                    text: I18n.tr("Filter\u2026"); color: root.darkMode ? Qt.rgba(1, 1, 1, 0.4) : Qt.rgba(0, 0, 0, 0.4); font.pixelSize: 12
                                }
                            }
                        }

                        // Summary stats bar
                        Row {
                            width: parent.width; spacing: 10
                            Repeater {
                                model: [
                                    { label: "CPU", val: (root.bar ? root.bar.cpuUsage : 0) + "%" },
                                    { label: "RAM", val: (root.bar ? root.bar.ramUsage : 0) + "%" },
                                    { label: "Disk", val: (root.bar ? root.bar.diskUsage : 0) + "%" },
                                    { label: "Net", val: (root.bar ? root.bar.netSpeed : "\u2014") }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: Math.floor((parent.width - 30) / 4); height: 48; radius: 10
                                    color: root.darkMode ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04)
                                    Column {
                                        anchors.centerIn: parent; spacing: 1
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: root.darkMode ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.55); font.pixelSize: 10.5 }
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.val; color: root.darkMode ? "#FFFFFF" : "#1D1D1F"; font.pixelSize: 14; font.weight: Font.DemiBold }
                                    }
                                }
                            }
                        }

                        // Table header
                        Row {
                            width: parent.width; height: 20
                            Text { width: parent.width - 240; text: I18n.tr("Process Name"); color: root.darkMode ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.55); font.pixelSize: 11 }
                            Text { width: 70; text: "PID"; color: root.darkMode ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.55); font.pixelSize: 11 }
                            Text { width: 75; text: "% CPU"; color: root.darkMode ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.55); font.pixelSize: 11 }
                            Text { width: 95; text: I18n.tr("Memory"); color: root.darkMode ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.55); font.pixelSize: 11 }
                        }

                        // Process list
                        Rectangle {
                            width: parent.width; height: parent.height - 178; radius: 10
                            color: root.darkMode ? Qt.rgba(0, 0, 0, 0.24) : Qt.rgba(0, 0, 0, 0.04)
                            clip: true
                            ListView {
                                anchors.fill: parent; anchors.margins: 4
                                model: filteredProcs
                                delegate: Rectangle {
                                    id: prRow; required property var modelData
                                    readonly property bool sel: root.actSelectedPid === modelData.pid
                                    width: ListView.view.width; height: 26; radius: 6
                                    color: sel ? root.accent : "transparent"
                                    Row {
                                        anchors.fill: parent; anchors.leftMargin: 6
                                        Text { width: parent.width - 240; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: prRow.modelData.name; color: prRow.sel ? "#FFFFFF" : (root.darkMode ? "#FFFFFF" : "#1D1D1F"); font.pixelSize: 12 }
                                        Text { width: 70; anchors.verticalCenter: parent.verticalCenter; text: String(prRow.modelData.pid); color: prRow.sel ? "#FFFFFF" : (root.darkMode ? Qt.rgba(1, 1, 1, 0.65) : Qt.rgba(0, 0, 0, 0.65)); font.pixelSize: 11.5 }
                                        Text { width: 75; anchors.verticalCenter: parent.verticalCenter; text: prRow.modelData.cpu.toFixed(1) + "%"; color: prRow.sel ? "#FFFFFF" : (root.darkMode ? "#FFFFFF" : "#1D1D1F"); font.pixelSize: 11.5 }
                                        Text { width: 95; anchors.verticalCenter: parent.verticalCenter; text: prRow.modelData.rssMb + " MB"; color: prRow.sel ? "#FFFFFF" : (root.darkMode ? "#FFFFFF" : "#1D1D1F"); font.pixelSize: 11.5 }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.actSelectedPid = prRow.modelData.pid }
                                }
                            }
                        }

                        // Bottom action bar
                        Item {
                            width: parent.width; height: 30
                            Text {
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                text: filteredProcs.length + " " + I18n.tr("processes shown")
                                color: root.darkMode ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.55); font.pixelSize: 11.5
                            }
                            Row {
                                anchors.right: parent.right; spacing: 8
                                Rectangle {
                                    height: 28; radius: 8; width: actTerm.implicitWidth + 18
                                    color: root.actSelectedPid > 0 ? (root.darkMode ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08)) : Qt.rgba(1, 1, 1, 0.06)
                                    Text { id: actTerm; anchors.centerIn: parent; text: I18n.tr("Quit"); color: root.darkMode ? "#FFFFFF" : "#1D1D1F"; font.pixelSize: 12 }
                                    MouseArea {
                                        anchors.fill: parent; enabled: root.actSelectedPid > 0; cursorShape: Qt.PointingHandCursor
                                        onClicked: { Quickshell.execDetached(["kill", "-TERM", String(root.actSelectedPid)]); root.actSelectedPid = -1; root.refreshProcs(); }
                                    }
                                }
                                Rectangle {
                                    height: 28; radius: 8; width: actForce.implicitWidth + 18
                                    color: root.actSelectedPid > 0 ? "#FF453A" : Qt.rgba(1, 1, 1, 0.06)
                                    Text { id: actForce; anchors.centerIn: parent; text: I18n.tr("Force Quit"); color: "#FFFFFF"; font.pixelSize: 12; font.weight: Font.DemiBold }
                                    MouseArea {
                                        anchors.fill: parent; enabled: root.actSelectedPid > 0; cursorShape: Qt.PointingHandCursor
                                        onClicked: { Quickshell.execDetached(["kill", "-9", String(root.actSelectedPid)]); root.actSelectedPid = -1; root.refreshProcs(); }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
