.pragma library

var DEFAULT_RIGHT_ORDER = [
    "tray", "liveActivity", "focus", "bluetooth", "volume", "keyboard",
    "cpuRam", "battery", "notifications", "wifi", "search", "controlCenter", "clock"
];

function normalizeRightOrder(raw) {
    var out = [], seen = {}, i, id;
    if (Array.isArray(raw)) {
        for (i = 0; i < raw.length; i++) {
            id = String(raw[i] || "");
            if (DEFAULT_RIGHT_ORDER.indexOf(id) >= 0 && !seen[id]) {
                seen[id] = true;
                out.push(id);
            }
        }
    }
    for (i = 0; i < DEFAULT_RIGHT_ORDER.length; i++) {
        id = DEFAULT_RIGHT_ORDER[i];
        if (!seen[id]) out.push(id);
    }
    return out;
}

function reorderRightItems(order, dragId, targetId) {
    var list = normalizeRightOrder(order);
    var from = list.indexOf(dragId);
    var to = list.indexOf(targetId);
    if (from < 0 || to < 0 || from === to) return list;
    list.splice(from, 1);
    list.splice(to, 0, dragId);
    return list;
}

function hideableBarItem(id) {
    var map = {
        tray: { kind: "prop", prop: "showTray" },
        liveActivity: { kind: "prop", prop: "liveActivities" },
        bluetooth: { kind: "barWidget", id: "bluetooth" },
        volume: { kind: "barWidget", id: "volume" },
        keyboard: { kind: "barWidget", id: "keyboard" },
        cpuRam: { kind: "barWidget", id: "cpuRam" },
        notifications: { kind: "barWidget", id: "notifications" },
        wifi: { kind: "barWidget", id: "wifi" },
        search: { kind: "prop", prop: "showSearch" },
        controlCenter: { kind: "barWidget", id: "controlCenter" },
        clock: { kind: "barWidget", id: "clock" }
    };
    return map[id] || null;
}

function shouldAutoHideBar(mode, isFullscreen) {
    if (mode === "always") return true;
    if (mode === "fullscreen") return !!isFullscreen;
    return false;
}

function cleanMnemonic(label) {
    return String(label || "")
        .replace(/__/g, "\u0001")
        .replace(/_/g, "")
        .replace(/\u0001/g, "_")
        .trim();
}

function formatShortcut(shortcut) {
    if (!shortcut) return "";
    if (typeof shortcut === "string") return shortcut;
    var seq = Array.isArray(shortcut) ? shortcut : [];
    if (seq.length > 0 && Array.isArray(seq[0])) seq = seq[0];
    var parts = [];
    for (var i = 0; i < seq.length; i++) {
        var tok = String(seq[i] || "").trim();
        if (!tok) continue;
        var low = tok.toLowerCase();
        if (low === "control" || low === "ctrl") parts.push("Ctrl");
        else if (low === "shift") parts.push("Shift");
        else if (low === "alt" || low === "mod1") parts.push("Alt");
        else if (low === "super" || low === "meta" || low === "mod4") parts.push("Super");
        else parts.push(tok.length === 1 ? tok.toUpperCase() : tok);
    }
    return parts.join("+");
}

function flattenMenuItems(menus, query, limit) {
    var q = String(query || "").trim().toLowerCase();
    var max = limit || 16;
    if (!q || !Array.isArray(menus)) return [];
    var hits = [];
    function walk(items, trail) {
        if (!Array.isArray(items)) return;
        for (var i = 0; i < items.length; i++) {
            var it = items[i];
            if (!it || it.kind === "sep" || it.type === "separator") continue;
            var lbl = cleanMnemonic(it.label || "");
            var kids = it.children;
            if (Array.isArray(kids) && kids.length > 0) {
                walk(kids, lbl ? trail.concat([lbl]) : trail);
                continue;
            }
            if (!lbl || it.disabled === true || it.enabled === false) continue;
            var low = lbl.toLowerCase();
            var pathStr = trail.join(" \u203a ");
            var hay = (low + " " + pathStr.toLowerCase());
            var idx = low.indexOf(q);
            var hidx = hay.indexOf(q);
            if (idx < 0 && hidx < 0) continue;
            var score = idx === 0 ? 3 : (idx > 0 ? 2 : 1);
            hits.push({
                label: lbl,
                path: pathStr,
                shortcut: formatShortcut(it.shortcut || ""),
                score: score,
                item: it
            });
        }
    }
    for (var m = 0; m < menus.length; m++) {
        var menu = menus[m];
        if (!menu) continue;
        var title = cleanMnemonic(menu.label || menu.title || "");
        walk(menu.items || menu.children || [], title ? [title] : []);
    }
    hits.sort(function (a, b) {
        if (b.score !== a.score) return b.score - a.score;
        return a.label.length - b.label.length;
    });
    return hits.slice(0, max);
}

function fmtShortClock(ms) {
    var total = Math.max(0, Math.ceil((ms || 0) / 1000));
    var h = Math.floor(total / 3600);
    var m = Math.floor((total % 3600) / 60);
    var s = total % 60;
    var mm = (m < 10 && h > 0 ? "0" : "") + m;
    var ss = (s < 10 ? "0" : "") + s;
    return h > 0 ? (h + ":" + mm + ":" + ss) : (mm + ":" + ss);
}

function buildLiveActivities(opts) {
    if (!opts) return [];
    var out = [];
    if (opts.recording) {
        var rs = Math.max(0, Math.floor(opts.recSecs || 0));
        var rm = Math.floor(rs / 60), rrem = rs % 60;
        out.push({
            id: "recording",
            kind: "record",
            text: rm + ":" + (rrem < 10 ? "0" : "") + rrem,
            color: "#FF453A",
            pulse: true,
            action: "stopRecording"
        });
    }
    if (opts.ringing) {
        out.push({
            id: "ringing",
            kind: "bell",
            text: String(opts.ringing.label || (opts.ringing.kind === "timer" ? "Timer" : "Alarm")),
            color: "#FF9F0A",
            pulse: true,
            action: "stopRing"
        });
    } else if (opts.timerState === "running" || opts.timerState === "paused") {
        out.push({
            id: "timer",
            kind: "clock",
            text: fmtShortClock(opts.timerLeftMs),
            color: opts.timerState === "running" ? "#FF9F0A" : "#8E8E93",
            pulse: opts.timerState === "running",
            action: "timer"
        });
    }
    if (opts.stopwatchRunning && !opts.clockWinVisible) {
        out.push({
            id: "stopwatch",
            kind: "clock",
            text: fmtShortClock(opts.stopwatchMs),
            color: "#0A84FF",
            pulse: false,
            action: "stopwatch"
        });
    }
    if (opts.discordInCall) {
        out.push({
            id: "discord",
            kind: "mic",
            text: opts.discordDeaf ? "Deaf" : (opts.discordMuted ? "Muted" : "Call"),
            color: (opts.discordMuted || opts.discordDeaf) ? "#FF453A" : "#30D158",
            pulse: !opts.discordMuted && !opts.discordDeaf,
            action: "discord"
        });
    }
    return out;
}

function computeScreenCoverage(monitors, clients) {
    var covered = {}, fullscreen = {};
    if (!Array.isArray(monitors) || !Array.isArray(clients)) return { covered: covered, fullscreen: fullscreen };
    for (var i = 0; i < monitors.length; i++) {
        var m = monitors[i];
        if (!m || !m.name) continue;
        var ws = m.activeWorkspace ? m.activeWorkspace.id : -999;
        var scale = m.scale || 1;
        var mw = (m.width || 0) / scale;
        var mh = (m.height || 0) / scale;
        var area = 0, full = false;
        for (var j = 0; j < clients.length; j++) {
            var c = clients[j];
            if (!c || !c.mapped || c.hidden || c.monitor !== m.id || !c.workspace || c.workspace.id !== ws) continue;
            if (c.fullscreen > 0 || c.fullscreen === true) { full = true; break; }
            if (!c.floating && c.size) area += Math.min(c.size[0], mw) * Math.min(c.size[1], mh);
        }
        covered[m.name] = full || (mw > 0 && mh > 0 && area >= mw * mh * 0.86);
        fullscreen[m.name] = full;
    }
    return { covered: covered, fullscreen: fullscreen };
}
