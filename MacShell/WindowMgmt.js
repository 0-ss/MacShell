.pragma library

function normAddr(addr) {
    var s = String(addr || "").replace(/^0x/i, "").trim().toLowerCase();
    return s ? ("0x" + s) : "";
}

function isSpecialWorkspace(ws) {
    if (!ws) return false;
    var name = String(ws.name || "");
    return name.indexOf("special:") === 0 || (typeof ws.id === "number" && ws.id < 0);
}

function isShellClass(cls) {
    var s = String(cls || "").toLowerCase();
    return s === "org.quickshell" || s === "quickshell";
}

function usableArea(mon, opts) {
    var o = opts || {};
    var sc = (mon && typeof mon.scale === "number" && mon.scale > 0) ? mon.scale : 1;
    var mx = mon ? Number(mon.x || 0) : 0;
    var my = mon ? Number(mon.y || 0) : 0;
    var mw = mon ? Math.round(Number(mon.width || 1920) / sc) : 1920;
    var mh = mon ? Math.round(Number(mon.height || 1080) / sc) : 1080;
    var res = (mon && Array.isArray(mon.reserved) && mon.reserved.length >= 4) ? mon.reserved : [0, 0, 0, 0];
    var left = Math.max(Number(res[0] || 0), Number(o.leftInset || 0));
    var top = Math.max(Number(res[1] || 0), Number(o.topInset || 0));
    var right = Math.max(Number(res[2] || 0), Number(o.rightInset || 0));
    var bottom = Math.max(Number(res[3] || 0), Number(o.bottomInset || 0));
    return {
        x: Math.round(mx + left),
        y: Math.round(my + top),
        width: Math.max(200, Math.round(mw - left - right)),
        height: Math.max(160, Math.round(mh - top - bottom)),
        monX: mx,
        monY: my,
        monW: mw,
        monH: mh
    };
}

function computeTileRect(preset, mon, opts) {
    var o = opts || {};
    var area = usableArea(mon, o);
    var gap = Math.max(0, Math.round(o.gap !== undefined ? Number(o.gap) : 8));
    var titleOffset = Math.max(0, Math.round(Number(o.titleBarOffset || 0)));

    var ux = area.x + gap;
    var uy = area.y + gap + titleOffset;
    var uw = Math.max(180, area.width - 2 * gap);
    var uh = Math.max(120, area.height - 2 * gap - titleOffset);

    var halfW = Math.floor((uw - gap) / 2);
    var halfW2 = uw - gap - halfW;
    var halfH = Math.floor((uh - gap) / 2);
    var halfH2 = uh - gap - halfH;

    var thirdW = Math.floor((uw - 2 * gap) / 3);
    var thirdW3 = uw - 2 * gap - 2 * thirdW;
    var twoThirdsW = 2 * thirdW + gap;

    var p = String(preset || "").toLowerCase();
    if (p === "fill" || p === "maximize") {
        return { x: ux, y: uy, width: uw, height: uh };
    }
    if (p === "center") {
        var cw = o.winW > 0 ? Math.min(uw, Math.max(320, Math.round(o.winW))) : Math.round(uw * 0.65);
        var ch = o.winH > 0 ? Math.min(uh, Math.max(240, Math.round(o.winH))) : Math.round(uh * 0.72);
        return { x: Math.round(ux + (uw - cw) / 2), y: Math.round(uy + (uh - ch) / 2), width: cw, height: ch };
    }
    if (p === "left") return { x: ux, y: uy, width: halfW, height: uh };
    if (p === "right") return { x: ux + halfW + gap, y: uy, width: halfW2, height: uh };
    if (p === "top") return { x: ux, y: uy, width: uw, height: halfH };
    if (p === "bottom") return { x: ux, y: uy + halfH + gap, width: uw, height: halfH2 };
    if (p === "top-left") return { x: ux, y: uy, width: halfW, height: halfH };
    if (p === "top-right") return { x: ux + halfW + gap, y: uy, width: halfW2, height: halfH };
    if (p === "bottom-left") return { x: ux, y: uy + halfH + gap, width: halfW, height: halfH2 };
    if (p === "bottom-right") return { x: ux + halfW + gap, y: uy + halfH + gap, width: halfW2, height: halfH2 };
    if (p === "left-third") return { x: ux, y: uy, width: thirdW, height: uh };
    if (p === "center-third") return { x: ux + thirdW + gap, y: uy, width: thirdW, height: uh };
    if (p === "right-third") return { x: ux + 2 * (thirdW + gap), y: uy, width: thirdW3, height: uh };
    if (p === "left-two-thirds") return { x: ux, y: uy, width: twoThirdsW, height: uh };
    if (p === "right-two-thirds") return { x: ux + thirdW + gap, y: uy, width: uw - thirdW - gap, height: uh };
    return null;
}

function detectSnapZone(px, py, mon, opts) {
    if (!mon) return "";
    var o = opts || {};
    var area = usableArea(mon, o);
    var lx = px - area.monX;
    var ly = py - area.monY;
    if (lx < -4 || ly < -4 || lx > area.monW + 4 || ly > area.monH + 4) return "";

    var edge = Math.max(8, Number(o.edgeThreshold !== undefined ? o.edgeThreshold : 22));
    var corner = Math.max(edge + 24, Number(o.cornerThreshold !== undefined ? o.cornerThreshold : 110));
    var topY = Math.max(0, area.y - area.monY);
    var botY = area.monH;

    var nearLeft = lx <= edge;
    var nearRight = lx >= area.monW - edge;
    var nearTop = ly <= topY + edge;
    var nearBottom = ly >= botY - edge;

    var inTopCorner = ly <= topY + corner;
    var inBottomCorner = ly >= botY - corner;
    var inLeftCorner = lx <= corner;
    var inRightCorner = lx >= area.monW - corner;

    if ((nearLeft && inTopCorner) || (nearTop && inLeftCorner)) return "top-left";
    if ((nearRight && inTopCorner) || (nearTop && inRightCorner)) return "top-right";
    if ((nearLeft && inBottomCorner) || (nearBottom && inLeftCorner)) return "bottom-left";
    if ((nearRight && inBottomCorner) || (nearBottom && inRightCorner)) return "bottom-right";
    if (nearTop) return "fill";
    if (nearLeft) return "left";
    if (nearRight) return "right";
    if (nearBottom) return "bottom";
    return "";
}

function layoutWindowCards(windows, areaW, areaH, opts) {
    var list = Array.isArray(windows) ? windows : [];
    var n = list.length;
    if (n === 0 || areaW <= 40 || areaH <= 40) return [];

    var o = opts || {};
    var padX = Number(o.padX !== undefined ? o.padX : 36);
    var padY = Number(o.padY !== undefined ? o.padY : 24);
    var gapX = Number(o.gapX !== undefined ? o.gapX : 24);
    var gapY = Number(o.gapY !== undefined ? o.gapY : 28);
    var labelH = Number(o.labelH !== undefined ? o.labelH : 32);
    var maxCardW = Number(o.maxCardW !== undefined ? o.maxCardW : Math.min(720, areaW * 0.62));
    var maxCardH = Number(o.maxCardH !== undefined ? o.maxCardH : Math.min(480, areaH * 0.68));

    var availW = Math.max(120, areaW - 2 * padX);
    var availH = Math.max(100, areaH - 2 * padY);

    var aspects = [];
    for (var i = 0; i < n; i++) {
        var ww = Number(list[i].w || list[i].width || 1280);
        var wh = Number(list[i].h || list[i].height || 800);
        var ar = (ww > 0 && wh > 0) ? (ww / wh) : (16 / 10);
        aspects.push(Math.max(0.6, Math.min(2.4, ar)));
    }

    var bestLayout = null;
    var bestScore = -1;
    var maxRows = Math.min(n, Math.max(1, Math.ceil(Math.sqrt(n)) + 1));

    for (var rows = 1; rows <= maxRows; rows++) {
        var rowGroups = [];
        var idx = 0;
        for (var r = 0; r < rows; r++) {
            var remaining = n - idx;
            var rowsLeft = rows - r;
            var count = Math.ceil(remaining / rowsLeft);
            var grp = [];
            for (var c = 0; c < count && idx < n; c++, idx++) grp.push(idx);
            rowGroups.push(grp);
        }

        var maxRowH = Math.min(maxCardH, (availH - (rows - 1) * gapY) / rows - labelH);
        if (maxRowH < 64) continue;

        var totalArea = 0;
        var rowHeights = [];
        var rowWidths = [];
        var rowItems = [];

        for (var rg = 0; rg < rowGroups.length; rg++) {
            var g = rowGroups[rg];
            var sumAr = 0;
            for (var k = 0; k < g.length; k++) sumAr += aspects[g[k]];
            var rowAvailW = Math.max(80, availW - (g.length - 1) * gapX);
            var h = Math.min(maxRowH, rowAvailW / Math.max(0.1, sumAr));
            var widths = [];
            var rw = 0;
            for (var k2 = 0; k2 < g.length; k2++) {
                var cw = Math.min(maxCardW, h * aspects[g[k2]]);
                var ch = Math.min(h, cw / aspects[g[k2]]);
                widths.push({ idx: g[k2], w: cw, h: ch });
                rw += cw;
                totalArea += cw * ch;
            }
            rw += (g.length - 1) * gapX;
            var actualH = 0;
            for (var k3 = 0; k3 < widths.length; k3++) if (widths[k3].h > actualH) actualH = widths[k3].h;
            rowHeights.push(actualH);
            rowWidths.push(rw);
            rowItems.push(widths);
        }

        if (totalArea > bestScore) {
            bestScore = totalArea;
            bestLayout = { rowHeights: rowHeights, rowWidths: rowWidths, rowItems: rowItems };
        }
    }

    if (!bestLayout) return [];

    var totalH = 0;
    for (var rh = 0; rh < bestLayout.rowHeights.length; rh++) {
        totalH += bestLayout.rowHeights[rh] + labelH;
        if (rh > 0) totalH += gapY;
    }

    var startY = padY + Math.max(0, (availH - totalH) / 2);
    var curY = startY;
    var out = [];

    for (var r2 = 0; r2 < bestLayout.rowItems.length; r2++) {
        var rList = bestLayout.rowItems[r2];
        var rH = bestLayout.rowHeights[r2];
        var curX = padX + Math.max(0, (availW - bestLayout.rowWidths[r2]) / 2);
        for (var j = 0; j < rList.length; j++) {
            var item = rList[j];
            var orig = list[item.idx];
            var iy = curY + (rH - item.h) / 2;
            var card = {};
            for (var key in orig) card[key] = orig[key];
            card.x = Math.round(curX);
            card.y = Math.round(iy);
            card.width = Math.max(80, Math.round(item.w));
            card.height = Math.max(54, Math.round(item.h));
            out.push(card);
            curX += item.w + gapX;
        }
        curY += rH + labelH + gapY;
    }

    return out;
}

function buildSpaces(clients, mon, activeWsId, extraWorkspaceIds) {
    var wsMap = {};
    var activeId = (typeof activeWsId === "number" && activeWsId > 0) ? activeWsId : 1;
    var area = usableArea(mon, {});

    function ensureWs(id, name) {
        if (id <= 0) return null;
        if (!wsMap[id]) {
            wsMap[id] = {
                id: id,
                name: (name && String(name) !== "") ? String(name) : String(id),
                active: id === activeId,
                windows: []
            };
        }
        return wsMap[id];
    }

    ensureWs(activeId, String(activeId));
    if (Array.isArray(extraWorkspaceIds)) {
        for (var e = 0; e < extraWorkspaceIds.length; e++) {
            var eid = Number(extraWorkspaceIds[e]);
            if (eid > 0) ensureWs(eid, String(eid));
        }
    }

    var cs = Array.isArray(clients) ? clients : [];
    for (var i = 0; i < cs.length; i++) {
        var c = cs[i];
        if (!c || !c.mapped || c.hidden || !c.workspace) continue;
        if (isSpecialWorkspace(c.workspace)) continue;
        if (mon && typeof mon.id === "number" && c.monitor !== mon.id) continue;
        if (isShellClass(c["class"] || c.initialClass)) continue;
        var ws = ensureWs(c.workspace.id, c.workspace.name);
        if (!ws) continue;
        var at = Array.isArray(c.at) ? c.at : [area.monX, area.monY];
        var sz = Array.isArray(c.size) ? c.size : [400, 300];
        ws.windows.push({
            addr: normAddr(c.address),
            cls: String(c["class"] || c.initialClass || ""),
            title: String(c.title || c["class"] || ""),
            nx: Math.max(0, Math.min(1, (at[0] - area.monX) / Math.max(1, area.monW))),
            ny: Math.max(0, Math.min(1, (at[1] - area.monY) / Math.max(1, area.monH))),
            nw: Math.max(0.06, Math.min(1, sz[0] / Math.max(1, area.monW))),
            nh: Math.max(0.06, Math.min(1, sz[1] / Math.max(1, area.monH))),
            focusHistoryID: typeof c.focusHistoryID === "number" ? c.focusHistoryID : 999
        });
    }

    var out = [];
    for (var k in wsMap) {
        wsMap[k].windows.sort(function (a, b) { return b.focusHistoryID - a.focusHistoryID; });
        out.push(wsMap[k]);
    }
    out.sort(function (a, b) { return a.id - b.id; });
    return out;
}

function nextFreeWorkspaceId(spaces) {
    var used = {};
    var list = Array.isArray(spaces) ? spaces : [];
    for (var i = 0; i < list.length; i++) used[Number(list[i].id)] = true;
    var candidate = 1;
    while (used[candidate]) candidate++;
    return candidate;
}

function buildStages(clients, monId, activeWsId, groupOverrides) {
    var cs = Array.isArray(clients) ? clients : [];
    var overrides = groupOverrides || {};
    var groups = {};

    for (var i = 0; i < cs.length; i++) {
        var c = cs[i];
        if (!c || !c.mapped || c.hidden || !c.workspace) continue;
        if (isShellClass(c["class"] || c.initialClass)) continue;
        var wsName = String(c.workspace.name || "");
        var isParked = wsName === "special:stage";
        var isOnActive = !isSpecialWorkspace(c.workspace) && c.workspace.id === activeWsId && (monId === undefined || monId === null || c.monitor === monId);
        if (!isParked && !isOnActive) continue;

        var addr = normAddr(c.address);
        if (!addr) continue;
        var cls = String(c["class"] || c.initialClass || "window");
        var gid = overrides[addr] ? String(overrides[addr]) : ("app:" + cls.toLowerCase());
        var fh = typeof c.focusHistoryID === "number" ? c.focusHistoryID : 999;

        if (!groups[gid]) {
            groups[gid] = {
                id: gid,
                appClass: cls,
                title: String(c.title || cls),
                isActive: false,
                minFocus: fh,
                windows: []
            };
        }
        var g = groups[gid];
        if (isOnActive) g.isActive = true;
        if (fh < g.minFocus) {
            g.minFocus = fh;
            g.appClass = cls;
            g.title = String(c.title || cls);
        }
        g.windows.push({
            addr: addr,
            cls: cls,
            title: String(c.title || cls),
            parked: isParked,
            focusHistoryID: fh,
            w: (Array.isArray(c.size) && c.size[0] > 0) ? c.size[0] : 800,
            h: (Array.isArray(c.size) && c.size[1] > 0) ? c.size[1] : 500
        });
    }

    var active = null;
    var inactive = [];
    for (var k in groups) {
        var st = groups[k];
        st.windows.sort(function (a, b) { return a.focusHistoryID - b.focusHistoryID; });
        if (st.isActive) {
            if (!active || st.minFocus < active.minFocus) {
                if (active) inactive.push(active);
                active = st;
            } else {
                inactive.push(st);
            }
        } else {
            inactive.push(st);
        }
    }
    inactive.sort(function (a, b) { return a.minFocus - b.minFocus; });
    return { active: active, inactive: inactive };
}

function collectRevealTargets(clients, monId, activeWsId) {
    var cs = Array.isArray(clients) ? clients : [];
    var out = [];
    for (var i = 0; i < cs.length; i++) {
        var c = cs[i];
        if (!c || !c.mapped || c.hidden || !c.workspace) continue;
        if (isSpecialWorkspace(c.workspace)) continue;
        if (isShellClass(c["class"] || c.initialClass)) continue;
        if (monId !== undefined && monId !== null && c.monitor !== monId) continue;
        if (activeWsId !== undefined && activeWsId !== null && c.workspace.id !== activeWsId) continue;
        var addr = normAddr(c.address);
        if (!addr) continue;
        out.push({
            addr: addr,
            ws: c.workspace.id,
            mon: c.monitor,
            focusHistoryID: typeof c.focusHistoryID === "number" ? c.focusHistoryID : 999
        });
    }
    out.sort(function (a, b) { return a.focusHistoryID - b.focusHistoryID; });
    return out;
}
