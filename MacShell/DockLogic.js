.pragma library

function normalizePosition(pos) {
    var p = String(pos || "bottom").toLowerCase();
    return (p === "left" || p === "right") ? p : "bottom";
}

function isVerticalPosition(pos) {
    var p = normalizePosition(pos);
    return p === "left" || p === "right";
}

function expandHome(path, home) {
    var s = String(path || "").trim();
    if (!s) return "";
    if (s === "~") return home || "";
    if (s.indexOf("~/") === 0) return (home || "") + s.substring(1);
    return s;
}

function folderBaseName(path) {
    var clean = String(path || "").replace(/\/+$/, "");
    if (!clean) return "/";
    var ix = clean.lastIndexOf("/");
    return ix >= 0 ? clean.substring(ix + 1) : clean;
}

function normalizeFolders(raw, home) {
    if (!Array.isArray(raw)) return [];
    var out = [], seen = {};
    for (var i = 0; i < raw.length; i++) {
        var r = raw[i];
        var p = typeof r === "string" ? r : (r && typeof r.path === "string" ? r.path : "");
        p = expandHome(p, home);
        if (!p || seen[p]) continue;
        seen[p] = true;
        var view = (r && typeof r.view === "string" && ["fan", "grid", "list"].indexOf(r.view) >= 0) ? r.view : "fan";
        var label = (r && typeof r.name === "string" && r.name.trim()) ? r.name.trim() : folderBaseName(p);
        out.push({ path: p, name: label, view: view });
    }
    return out;
}

function updateRecentApps(prevRecent, closedKeys, pinnedSet, runningSet, maxCount) {
    var limit = Math.max(0, Math.min(10, parseInt(maxCount, 10) || 3));
    var out = [], seen = {};
    var add = function (k) {
        var key = String(k || "").trim().toLowerCase();
        if (!key || key.indexOf("__") === 0 || seen[key]) return;
        if (pinnedSet && pinnedSet[key]) return;
        if (runningSet && runningSet[key]) return;
        seen[key] = true;
        out.push(key);
    };
    if (Array.isArray(closedKeys)) {
        for (var i = 0; i < closedKeys.length; i++) add(closedKeys[i]);
    }
    if (Array.isArray(prevRecent)) {
        for (var j = 0; j < prevRecent.length; j++) add(prevRecent[j]);
    }
    return out.slice(0, limit);
}

function badgeCountFor(item, notifCounts, overrides) {
    if (!item || item.kind !== "app" || item.special) return 0;
    var candidates = [];
    if (item.key) candidates.push(String(item.key).toLowerCase());
    if (item.appId) candidates.push(String(item.appId).toLowerCase());
    if (item.name) candidates.push(String(item.name).toLowerCase());
    var maxVal = 0;
    function checkMap(map) {
        if (!map || typeof map !== "object") return;
        for (var k in map) {
            var val = parseInt(map[k], 10) || 0;
            if (val <= 0) continue;
            var lk = String(k).toLowerCase().trim();
            if (!lk) continue;
            for (var i = 0; i < candidates.length; i++) {
                var c = candidates[i];
                if (!c) continue;
                if (c === lk || c.indexOf(lk) >= 0 || lk.indexOf(c) >= 0) {
                    if (val > maxVal) maxVal = val;
                    break;
                }
            }
        }
    }
    checkMap(overrides);
    checkMap(notifCounts);
    return maxVal;
}

function formatBadgeText(count) {
    var n = parseInt(count, 10) || 0;
    if (n <= 0) return "";
    return n > 99 ? "99+" : String(n);
}

function fanItemTransform(index, total) {
    var i = Math.max(0, index);
    var n = Math.max(1, total);
    var t = n > 1 ? i / (n - 1) : 0;
    return {
        offsetX: Math.round(-Math.pow(t, 1.35) * 26),
        offsetY: Math.round(-(i + 1) * 56),
        rotation: -(1.5 + t * 11.5)
    };
}

function buildOpenFilesArgs(desktopExec, paths) {
    var cleanPaths = [];
    if (Array.isArray(paths)) {
        for (var i = 0; i < paths.length; i++) {
            var p = String(paths[i] || "").trim();
            if (p.indexOf("file://") === 0) {
                try { p = decodeURIComponent(p.substring(7)); } catch (e) { p = p.substring(7); }
            }
            if (p) cleanPaths.push(p);
        }
    }
    if (cleanPaths.length === 0) return null;
    var raw = String(desktopExec || "").trim();
    if (!raw) return ["xdg-open", cleanPaths[0]];
    // Strip desktop entry field codes (%f, %F, %u, %U, %i, %c, %k, %d, %D, %n, %N, %v, %m)
    var base = raw.replace(/%[fFuUdDnNickvm]/g, "").replace(/\s+/g, " ").trim();
    if (!base) return ["xdg-open", cleanPaths[0]];
    return ["sh", "-c", base + ' "$@"', "sh"].concat(cleanPaths);
}

function parseFolderListing(stdoutText, folderPath) {
    var out = [], lines = String(stdoutText || "").split("\n");
    var base = String(folderPath || "").replace(/\/+$/, "");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (!line) continue;
        var parts = line.split("\t");
        if (parts.length < 3) continue;
        var mtime = Number(parts[0]) || 0;
        var kind = parts[1]; // "d" or "f"
        var name = parts.slice(2).join("\t");
        if (!name || name.charAt(0) === ".") continue;
        var ext = "";
        var dot = name.lastIndexOf(".");
        if (kind !== "d" && dot > 0) ext = name.substring(dot + 1).toLowerCase();
        var isImg = ["png", "jpg", "jpeg", "webp", "gif", "bmp", "svg"].indexOf(ext) >= 0;
        out.push({
            name: name,
            path: base + "/" + name,
            isDir: kind === "d",
            isImage: isImg,
            ext: ext,
            mtime: mtime
        });
    }
    return out;
}
