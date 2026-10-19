import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: controller

    property var targetWindow: null
    property var defaultGlassContext: null
    property var info: ({
        distro: "Linux",
        processor: "Unavailable",
        memory: "Unavailable",
        kernel: "Unavailable",
        architecture: "Unavailable",
        desktop: "Unavailable",
        hostname: "Unavailable"
    })

    function open(glassContext) {
        var ctx = glassContext || defaultGlassContext;
        if (ctx && targetWindow) {
            targetWindow.glassBackdrop = ctx.backdrop || null;
            targetWindow.glassOriginX = Number(ctx.originX) || 0;
            targetWindow.glassOriginY = Number(ctx.originY) || 0;
            targetWindow.glassMonitor = String(ctx.monitor || "");
        }
        if (targetWindow) targetWindow.visible = true;
        refresh();
    }

    function close() {
        if (targetWindow) targetWindow.visible = false;
    }

    function refresh() {
        if (!systemInfoProc.running) systemInfoProc.running = true;
    }

    Process {
        id: systemInfoProc
        command: ["sh", "-c",
            ". /etc/os-release 2>/dev/null\n" +
            "printf 'distro\\t%s\\n' \"${PRETTY_NAME:-Linux}\"\n" +
            "printf 'processor\\t%s\\n' \"$(awk -F: '/model name|Hardware/ { sub(/^[ \\t]+/, \"\", $2); print $2; exit }' /proc/cpuinfo)\"\n" +
            "printf 'memory\\t%s GB\\n' \"$(awk '/MemTotal/ { print int($2 / 1048576 + 0.5) }' /proc/meminfo)\"\n" +
            "printf 'kernel\\t%s\\n' \"$(uname -sr)\"\n" +
            "printf 'architecture\\t%s\\n' \"$(uname -m)\"\n" +
            "printf 'desktop\\t%s\\n' \"${XDG_CURRENT_DESKTOP:-${XDG_SESSION_TYPE:-Linux}}\"\n" +
            "printf 'hostname\\t%s\\n' \"$(hostname)\"\n"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var values = {
                    distro: "Linux", processor: "Unavailable", memory: "Unavailable",
                    kernel: "Unavailable", architecture: "Unavailable", desktop: "Unavailable",
                    hostname: "Unavailable"
                };
                var lines = text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var tab = lines[i].indexOf("\t");
                    if (tab < 0) continue;
                    var key = lines[i].substring(0, tab), value = lines[i].substring(tab + 1).trim();
                    if (value.length > 0 && values[key] !== undefined) values[key] = value;
                }
                controller.info = values;
            }
        }
    }
}