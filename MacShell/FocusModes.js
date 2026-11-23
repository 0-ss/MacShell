.pragma library

var DEFAULT_PROFILES = [
    {
        id: "dnd",
        name: "Do Not Disturb",
        glyph: "moon",
        color: "#AF52DE",
        allowApps: [],
        allowCritical: true,
        wallpaper: "",
        autoGaming: false,
        schedule: { enabled: false, start: "22:00", end: "07:00", days: [0, 1, 2, 3, 4, 5, 6] }
    },
    {
        id: "work",
        name: "Work",
        glyph: "briefcase",
        color: "#0A84FF",
        allowApps: ["slack", "teams", "mail", "calendar", "thunderbird"],
        allowCritical: true,
        wallpaper: "",
        autoGaming: false,
        schedule: { enabled: false, start: "09:00", end: "17:00", days: [1, 2, 3, 4, 5] }
    },
    {
        id: "sleep",
        name: "Sleep",
        glyph: "bed",
        color: "#5E5CE6",
        allowApps: ["clock", "alarm"],
        allowCritical: true,
        wallpaper: "",
        autoGaming: false,
        schedule: { enabled: false, start: "23:00", end: "07:00", days: [0, 1, 2, 3, 4, 5, 6] }
    },
    {
        id: "personal",
        name: "Personal",
        glyph: "person",
        color: "#30D158",
        allowApps: ["discord", "telegram", "signal", "whatsapp", "messages"],
        allowCritical: true,
        wallpaper: "",
        autoGaming: false,
        schedule: { enabled: false, start: "18:00", end: "22:00", days: [0, 1, 2, 3, 4, 5, 6] }
    },
    {
        id: "gaming",
        name: "Gaming",
        glyph: "gamepad",
        color: "#30D158",
        allowApps: ["discord", "steam"],
        allowCritical: true,
        wallpaper: "",
        autoGaming: true,
        schedule: { enabled: false, start: "20:00", end: "23:30", days: [5, 6] }
    }
];

function cloneSchedule(sc, fallback) {
    var fb = fallback || { enabled: false, start: "22:00", end: "07:00", days: [0, 1, 2, 3, 4, 5, 6] };
    var src = (sc && typeof sc === "object") ? sc : fb;
    var days = [];
    if (Array.isArray(src.days)) {
        for (var i = 0; i < src.days.length; i++) {
            var d = parseInt(src.days[i], 10);
            if (!isNaN(d) && d >= 0 && d <= 6 && days.indexOf(d) < 0) days.push(d);
        }
    } else {
        days = fb.days.slice();
    }
    return {
        enabled: !!src.enabled,
        start: typeof src.start === "string" && parseHHMM(src.start) >= 0 ? src.start : fb.start,
        end: typeof src.end === "string" && parseHHMM(src.end) >= 0 ? src.end : fb.end,
        days: days
    };
}

function cloneProfile(p, fallback) {
    var fb = fallback || DEFAULT_PROFILES[0];
    var apps = [];
    if (Array.isArray(p.allowApps)) {
        for (var i = 0; i < p.allowApps.length; i++) {
            var a = String(p.allowApps[i] || "").trim();
            if (a && apps.indexOf(a) < 0) apps.push(a);
        }
    } else if (fb.allowApps) {
        apps = fb.allowApps.slice();
    }
    return {
        id: String(p.id || fb.id),
        name: String(p.name || fb.name),
        glyph: String(p.glyph || fb.glyph || "moon"),
        color: String(p.color || fb.color || "#AF52DE"),
        allowApps: apps,
        allowCritical: p.allowCritical !== undefined ? !!p.allowCritical : true,
        wallpaper: typeof p.wallpaper === "string" ? p.wallpaper.trim() : "",
        autoGaming: p.autoGaming !== undefined ? !!p.autoGaming : !!fb.autoGaming,
        schedule: cloneSchedule(p.schedule, fb.schedule)
    };
}

function defaultProfiles() {
    var out = [];
    for (var i = 0; i < DEFAULT_PROFILES.length; i++) out.push(cloneProfile(DEFAULT_PROFILES[i], DEFAULT_PROFILES[i]));
    return out;
}

function normalizeProfiles(raw) {
    var byId = {}, i;
    for (i = 0; i < DEFAULT_PROFILES.length; i++) byId[DEFAULT_PROFILES[i].id] = DEFAULT_PROFILES[i];
    if (!Array.isArray(raw) || raw.length === 0) return defaultProfiles();
    var out = [], seen = {};
    for (i = 0; i < raw.length; i++) {
        var r = raw[i];
        if (!r || typeof r !== "object" || !r.id) continue;
        var id = String(r.id);
        if (seen[id]) continue;
        seen[id] = true;
        out.push(cloneProfile(r, byId[id] || DEFAULT_PROFILES[0]));
    }
    for (i = 0; i < DEFAULT_PROFILES.length; i++) {
        var def = DEFAULT_PROFILES[i];
        if (!seen[def.id]) out.push(cloneProfile(def, def));
    }
    return out;
}

function findProfile(profiles, id) {
    if (!id || !Array.isArray(profiles)) return null;
    for (var i = 0; i < profiles.length; i++) {
        if (profiles[i] && profiles[i].id === id) return profiles[i];
    }
    return null;
}

function parseHHMM(str) {
    var m = /^(\d{1,2}):(\d{2})$/.exec(String(str || "").trim());
    if (!m) return -1;
    var h = parseInt(m[1], 10), min = parseInt(m[2], 10);
    if (h < 0 || h > 23 || min < 0 || min > 59) return -1;
    return h * 60 + min;
}

function isScheduleActive(schedule, date) {
    if (!schedule || !schedule.enabled) return false;
    var start = parseHHMM(schedule.start);
    var end = parseHHMM(schedule.end);
    if (start < 0 || end < 0 || start === end) return false;
    var d = date || new Date();
    var nowMin = d.getHours() * 60 + d.getMinutes();
    var day = d.getDay();
    var days = Array.isArray(schedule.days) ? schedule.days : [];
    var allDays = days.length === 0;
    if (start < end) {
        if (!allDays && days.indexOf(day) < 0) return false;
        return nowMin >= start && nowMin < end;
    }
    // Overnight range (e.g. 22:00 -> 07:00)
    if (nowMin >= start) {
        return allDays || days.indexOf(day) >= 0;
    }
    if (nowMin < end) {
        var prevDay = (day + 6) % 7;
        return allDays || days.indexOf(prevDay) >= 0;
    }
    return false;
}

function hasAnySchedule(profiles) {
    if (!Array.isArray(profiles)) return false;
    for (var i = 0; i < profiles.length; i++) {
        if (profiles[i] && profiles[i].schedule && profiles[i].schedule.enabled) return true;
    }
    return false;
}

function scheduledProfileId(profiles, date) {
    if (!Array.isArray(profiles)) return "";
    for (var i = 0; i < profiles.length; i++) {
        if (profiles[i] && isScheduleActive(profiles[i].schedule, date)) return profiles[i].id;
    }
    return "";
}

function shouldAllowNotification(profile, appName, urgency) {
    if (!profile) return true;
    if (urgency >= 2 && profile.allowCritical !== false) return true;
    var allow = Array.isArray(profile.allowApps) ? profile.allowApps : [];
    if (allow.length === 0) return false;
    var app = String(appName || "").trim().toLowerCase();
    if (!app) return false;
    for (var i = 0; i < allow.length; i++) {
        var token = String(allow[i] || "").trim().toLowerCase();
        if (token && (app === token || app.indexOf(token) >= 0 || token.indexOf(app) >= 0)) return true;
    }
    return false;
}

function parseAllowAppsText(text) {
    var parts = String(text || "").split(/[,;\n]/);
    var out = [], seen = {};
    for (var i = 0; i < parts.length; i++) {
        var t = parts[i].trim();
        var low = t.toLowerCase();
        if (t && !seen[low]) {
            seen[low] = true;
            out.push(t);
        }
    }
    return out;
}

function formatAllowApps(apps) {
    if (!Array.isArray(apps)) return "";
    return apps.join(", ");
}

function updateProfile(profiles, id, patch) {
    var list = normalizeProfiles(profiles);
    var out = [];
    for (var i = 0; i < list.length; i++) {
        var p = list[i];
        if (p.id === id) {
            var merged = {};
            for (var k in p) merged[k] = p[k];
            for (var pk in patch) {
                if (pk === "schedule" && patch.schedule && typeof patch.schedule === "object") {
                    var sc = {};
                    for (var sk in p.schedule) sc[sk] = p.schedule[sk];
                    for (var psk in patch.schedule) sc[psk] = patch.schedule[psk];
                    merged.schedule = cloneSchedule(sc, p.schedule);
                } else {
                    merged[pk] = patch[pk];
                }
            }
            out.push(cloneProfile(merged, p));
        } else {
            out.push(p);
        }
    }
    return out;
}
