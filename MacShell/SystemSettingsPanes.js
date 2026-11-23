.pragma library

function parseStorageBreakdown(text) {
    var out = { totalGb: 0, usedGb: 0, availGb: 0, segments: [] };
    var lines = String(text || "").trim().split("\n");
    var palette = {
        Documents: "#0A84FF",
        Downloads: "#30D158",
        Pictures: "#BF5AF2",
        Videos: "#FF9F0A",
        Cache: "#FF453A",
        Trash: "#8E8E93"
    };
    for (var i = 0; i < lines.length; i++) {
        var p = lines[i].split("\t");
        if (p[0] === "DF" && p.length >= 4) {
            out.totalGb = Math.max(0.1, (Number(p[1]) || 0) / 1048576);
            out.usedGb = Math.max(0, (Number(p[2]) || 0) / 1048576);
            out.availGb = Math.max(0, (Number(p[3]) || 0) / 1048576);
        } else if (p[0] === "CAT" && p.length >= 3) {
            var gb = Math.max(0, (Number(p[2]) || 0) / 1048576);
            out.segments.push({ name: p[1], gb: gb, color: palette[p[1]] || "#5E5CE6" });
        }
    }
    return out;
}

function parseAutostartList(text) {
    var out = [], lines = String(text || "").trim().split("\n");
    for (var i = 0; i < lines.length; i++) {
        var p = lines[i].split("\t");
        if (p.length < 3 || !p[0]) continue;
        out.push({ path: p[0], name: p[1] || p[0], enabled: p[2] !== "1" });
    }
    return out;
}

function parsePrinters(text) {
    var out = [], lines = String(text || "").trim().split("\n");
    for (var i = 0; i < lines.length; i++) {
        var l = lines[i].trim();
        var m = /^printer\s+(\S+)\s+(.*)$/i.exec(l);
        if (m) out.push({ name: m[1], status: m[2] });
    }
    return out;
}

function parseTimedatectl(text) {
    var tz = "UTC", ntp = false;
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var l = lines[i].trim();
        if (l.indexOf("Time zone:") === 0) tz = l.substring(10).trim().split(" ")[0];
        else if (l.indexOf("NTP service:") === 0) ntp = l.toLowerCase().indexOf("active") >= 0 && l.toLowerCase().indexOf("inactive") < 0;
    }
    return { timezone: tz, ntp: ntp };
}

function parseUpdatesCount(text) {
    var lines = String(text || "").trim().split("\n").filter(function (x) { return x.trim() !== ""; });
    return { count: lines.length, sample: lines.slice(0, 12) };
}
