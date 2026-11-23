.pragma library

var FINDER_TAGS = [
    { id: "red",    name: "Red",    color: "#FF453A" },
    { id: "orange", name: "Orange", color: "#FF9F0A" },
    { id: "yellow", name: "Yellow", color: "#FFD60A" },
    { id: "green",  name: "Green",  color: "#30D158" },
    { id: "blue",   name: "Blue",   color: "#0A84FF" },
    { id: "purple", name: "Purple", color: "#BF5AF2" },
    { id: "gray",   name: "Gray",   color: "#8E8E93" }
];

function parseKdeConnectDevices(text) {
    var out = [], lines = String(text || "").trim().split("\n");
    for (var i = 0; i < lines.length; i++) {
        // "- Pixel 9: abc123def456 (paired and reachable)"
        var m = /^-\s+(.+?):\s+([A-Za-z0-9_\-]+)\s+\((.+)\)$/.exec(lines[i].trim());
        if (!m) continue;
        var st = m[3].toLowerCase();
        out.push({
            name: m[1].trim(),
            id: m[2].trim(),
            paired: st.indexOf("paired") >= 0,
            reachable: st.indexOf("reachable") >= 0
        });
    }
    return out;
}

function parseSnapperList(text, rootPrefix) {
    var out = [], lines = String(text || "").trim().split("\n");
    var base = rootPrefix || "/.snapshots";
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (!line || line.indexOf("─") >= 0 || line.indexOf("#") === 0 || line.indexOf("Type") === 0) continue;
        // snapper --csvout list: config,subvolume,number,default,active,type,pre-number,date,user,used-space,cleanup,description,userdata
        var cols = line.split(",");
        if (cols.length >= 12 && /^\d+$/.test(cols[2])) {
            var num = parseInt(cols[2], 10);
            if (num <= 0) continue;
            out.push({
                id: String(num),
                backend: "snapper",
                date: cols[7] || "",
                desc: cols[11] || cols[5] || ("Snapshot #" + num),
                path: base + "/" + num + "/snapshot"
            });
            continue;
        }
        // Pipe-delimited default snapper list
        var p = line.split("|");
        if (p.length >= 6) {
            var num2 = parseInt(p[0].replace(/[^\d]/g, ""), 10);
            if (isNaN(num2) || num2 <= 0) continue;
            out.push({
                id: String(num2),
                backend: "snapper",
                date: (p[3] || "").trim(),
                desc: (p[6] || p[5] || ("Snapshot #" + num2)).trim(),
                path: base + "/" + num2 + "/snapshot"
            });
        }
    }
    out.reverse();
    return out;
}

function parseTimeshiftList(text, rootPrefix) {
    var out = [], lines = String(text || "").trim().split("\n");
    var base = rootPrefix || "/run/timeshift/backup/timeshift-btrfs/snapshots";
    for (var i = 0; i < lines.length; i++) {
        var name = lines[i].trim();
        if (!name) continue;
        out.push({
            id: name,
            backend: "timeshift",
            date: name.replace("_", " "),
            desc: "Timeshift Snapshot",
            path: base + "/" + name + "/@"
        });
    }
    return out;
}

function toggleFileTag(tagMap, path, tagId) {
    var out = {};
    if (tagMap && typeof tagMap === "object") {
        for (var k in tagMap) out[k] = Array.isArray(tagMap[k]) ? tagMap[k].slice() : [];
    }
    var cur = out[path] ? out[path].slice() : [];
    var ix = cur.indexOf(tagId);
    if (ix >= 0) cur.splice(ix, 1);
    else cur.push(tagId);
    if (cur.length === 0) delete out[path];
    else out[path] = cur;
    return out;
}

function taggedPaths(tagMap, tagId) {
    var out = [];
    if (!tagMap || typeof tagMap !== "object") return out;
    for (var p in tagMap) {
        if (Array.isArray(tagMap[p]) && tagMap[p].indexOf(tagId) >= 0) out.push(p);
    }
    out.sort();
    return out;
}

function parentDir(path) {
    var clean = String(path || "").replace(/\/+$/, "");
    if (!clean || clean === "/") return "/";
    var ix = clean.lastIndexOf("/");
    return ix <= 0 ? "/" : clean.substring(0, ix);
}
