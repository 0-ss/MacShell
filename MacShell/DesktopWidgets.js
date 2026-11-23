.pragma library

function groupNotifications(list, expandedMap) {
    if (!Array.isArray(list)) return { visibleIds: {}, extraCounts: {}, appOrder: [] };
    var byApp = {}, order = [], i;
    for (i = 0; i < list.length; i++) {
        var it = list[i];
        if (!it) continue;
        var key = String(it.app || "Notification").trim().toLowerCase() || "notification";
        if (!byApp[key]) {
            byApp[key] = [];
            order.push(key);
        }
        byApp[key].push(it);
    }
    var visibleIds = {}, extraCounts = {};
    var exp = expandedMap || {};
    for (i = 0; i < order.length; i++) {
        var k = order[i], arr = byApp[k];
        var isExp = exp[k] === true;
        if (arr.length === 0) continue;
        visibleIds[arr[0].nid] = true;
        extraCounts[arr[0].nid] = { appKey: k, total: arr.length, hidden: isExp ? 0 : (arr.length - 1), expanded: isExp };
        if (isExp) {
            for (var j = 1; j < arr.length; j++) visibleIds[arr[j].nid] = true;
        }
    }
    return { visibleIds: visibleIds, extraCounts: extraCounts, appOrder: order };
}

function widgetMatchesScreen(widgetScreen, screenName, primaryScreenName) {
    var ws = String(widgetScreen || "").trim();
    if (!ws) return screenName === primaryScreenName;
    return ws === screenName;
}

function stackCategoryFor(item, groupBy, nowMs) {
    if (!item) return "Other";
    if (groupBy === "date") {
        var m = Number(item.mtime || 0);
        if (m <= 0) return "Earlier";
        var now = Number(nowMs || Date.now());
        var ageMs = Math.max(0, now - (m < 1e12 ? m * 1000 : m));
        if (ageMs < 86400000) return "Today";
        if (ageMs < 7 * 86400000) return "This Week";
        return "Earlier";
    }
    if (item.isDir) return "Folders";
    var name = String(item.name || "").toLowerCase();
    var dot = name.lastIndexOf(".");
    var ext = dot >= 0 ? name.substring(dot + 1) : "";
    if (["png", "jpg", "jpeg", "webp", "gif", "bmp", "svg", "avif", "heic"].indexOf(ext) >= 0) return "Images";
    if (["pdf", "doc", "docx", "odt", "rtf", "txt", "md", "pages", "xls", "xlsx", "csv", "ppt", "pptx"].indexOf(ext) >= 0) return "Documents";
    if (["mp4", "mkv", "webm", "mov", "avi", "mp3", "flac", "wav", "ogg", "m4a"].indexOf(ext) >= 0) return "Media";
    if (["zip", "tar", "gz", "xz", "zst", "bz2", "7z", "rar", "deb", "rpm", "appimage"].indexOf(ext) >= 0) return "Archives";
    if (["js", "mjs", "ts", "tsx", "py", "qml", "sh", "lua", "c", "cpp", "h", "rs", "go", "json", "toml", "yaml", "yml", "html", "css"].indexOf(ext) >= 0) return "Code";
    return "Other";
}

function buildDesktopStacks(items, enabled, groupBy, nowMs) {
    if (!Array.isArray(items)) return [];
    if (!enabled) return items;
    var groups = {}, order = [];
    for (var i = 0; i < items.length; i++) {
        var it = items[i];
        if (!it) continue;
        var cat = stackCategoryFor(it, groupBy || "kind", nowMs);
        if (!groups[cat]) {
            groups[cat] = [];
            order.push(cat);
        }
        groups[cat].push(it);
    }
    var out = [];
    for (var j = 0; j < order.length; j++) {
        var c = order[j], arr = groups[c];
        if (arr.length === 1) {
            out.push(arr[0]);
        } else {
            out.push({
                name: c,
                path: "__stack:" + c,
                isDir: true,
                isStack: true,
                stackName: c,
                stackCount: arr.length,
                stackItems: arr,
                kind: "Stack",
                mtime: arr[0].mtime || 0
            });
        }
    }
    return out;
}
