import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool enabled: false
    property bool paused: false
    property string folder: ""
    property real renameSinceMs: 0
    property string request: ""
    property var hits: []
    property bool pending: false
    property bool failed: false
    property bool indexFailed: false
    readonly property bool indexing: indexer.running
    readonly property string script: decodeURIComponent(String(Qt.resolvedUrl("assets/screenshot-search.py")).replace(/^file:\/\//, ""))

    function refresh() {
        if (enabled && request !== "") debounce.restart();
    }

    onRequestChanged: {
        hits = [];
        pending = enabled && request !== "";
        failed = false;
        refresh();
    }
    onEnabledChanged: {
        if (enabled) refresh();
        else {
            debounce.stop();
            indexer.running = false;
            hits = [];
            pending = false;
            failed = false;
            indexFailed = false;
        }
    }
    onRenameSinceMsChanged: if (renameSinceMs === 0) indexer.running = false

    Timer {
        interval: 20000
        running: root.enabled && !root.paused
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!indexer.running) indexer.running = true
    }
    Process {
        id: indexer
        command: ["python3", "-B", root.script, "index", "--folder=" + root.folder,
                  "--rename-since-ms=" + root.renameSinceMs.toFixed(0)]
        onExited: (code, status) => {
            if (!root.enabled) return;
            root.indexFailed = code !== 0;
            root.refresh();
        }
    }

    Timer {
        id: debounce
        interval: 180
        onTriggered: {
            if (!root.enabled || root.request === "" || lookup.running) return;
            lookup.forRequest = root.request;
            root.pending = true;
            lookup.running = true;
        }
    }
    Process {
        id: lookup
        property string forRequest: ""
        command: ["python3", "-B", root.script, "search", "--", forRequest.slice(4).trim()]
        stdout: StdioCollector { id: result }
        onExited: (code, status) => {
            if (!root.enabled) return;
            if (forRequest !== root.request) {
                root.refresh();
                return;
            }
            root.pending = false;
            try {
                if (code !== 0) throw new Error("search failed");
                root.hits = JSON.parse(result.text);
                root.failed = false;
            } catch (error) {
                root.hits = [];
                root.failed = true;
            }
        }
    }
}
