// Unit tests for Roadmap #2 (Menu Bar, Control Center, Focus Modes) & perf gates.   node tests/test_menubar_cc.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

function loadPragmaLib(relPath, exportsList) {
    const src = readFileSync(new URL(`../${relPath}`, import.meta.url), "utf8")
        .replace(/^\s*\.pragma\s+library\s*/m, "");
    const fn = new Function(`${src}\nreturn { ${exportsList.join(", ")} };`);
    return fn();
}

const MB = loadPragmaLib("MacShell/MenuBar.js", [
    "DEFAULT_RIGHT_ORDER", "normalizeRightOrder", "reorderRightItems", "hideableBarItem",
    "shouldAutoHideBar", "cleanMnemonic", "formatShortcut", "flattenMenuItems",
    "fmtShortClock", "buildLiveActivities", "computeScreenCoverage"
]);

const FM = loadPragmaLib("MacShell/FocusModes.js", [
    "DEFAULT_PROFILES", "defaultProfiles", "normalizeProfiles", "findProfile",
    "parseHHMM", "isScheduleActive", "hasAnySchedule", "scheduledProfileId",
    "shouldAllowNotification", "parseAllowAppsText", "formatAllowApps", "updateProfile"
]);

// ── MenuBar.js: right-side order & hide ──
const norm = MB.normalizeRightOrder(["clock", "unknown", "wifi", "clock"]);
assert.equal(norm[0], "clock");
assert.equal(norm[1], "wifi");
assert.equal(norm.length, MB.DEFAULT_RIGHT_ORDER.length);
assert.ok(!norm.includes("unknown"));

const moved = MB.reorderRightItems(MB.DEFAULT_RIGHT_ORDER, "wifi", "bluetooth");
assert.ok(moved.indexOf("wifi") < moved.indexOf("bluetooth"));
assert.equal(moved.length, MB.DEFAULT_RIGHT_ORDER.length);

assert.deepEqual(MB.hideableBarItem("wifi"), { kind: "barWidget", id: "wifi" });
assert.deepEqual(MB.hideableBarItem("tray"), { kind: "prop", prop: "showTray" });
assert.deepEqual(MB.hideableBarItem("liveActivity"), { kind: "prop", prop: "liveActivities" });
assert.equal(MB.hideableBarItem("battery"), null);

// ── Auto-hide logic ──
assert.equal(MB.shouldAutoHideBar("never", true), false);
assert.equal(MB.shouldAutoHideBar("fullscreen", false), false);
assert.equal(MB.shouldAutoHideBar("fullscreen", true), true);
assert.equal(MB.shouldAutoHideBar("always", false), true);

// ── DBusMenu helpers & searchable Help menu ──
assert.equal(MB.cleanMnemonic("_File"), "File");
assert.equal(MB.cleanMnemonic("Save __As_"), "Save _As");
assert.equal(MB.formatShortcut([["Control", "Shift", "p"]]), "Ctrl+Shift+P");

const menus = [
    {
        label: "_File",
        items: [
            { kind: "item", label: "New Window", shortcut: "Ctrl+N", run: () => {} },
            { kind: "sep" },
            { kind: "item", label: "Disabled Action", disabled: true, run: () => {} },
            {
                kind: "item",
                label: "Export",
                children: [
                    { kind: "item", label: "Export as PDF", shortcut: [["Control", "e"]], run: () => {} }
                ]
            }
        ]
    },
    {
        label: "View",
        items: [
            { kind: "item", label: "Full Screen", shortcut: "F11", run: () => {} }
        ]
    }
];
const pdfHits = MB.flattenMenuItems(menus, "pdf");
assert.equal(pdfHits.length, 1);
assert.equal(pdfHits[0].label, "Export as PDF");
assert.equal(pdfHits[0].path, "File \u203a Export");
assert.equal(pdfHits[0].shortcut, "Ctrl+E");
assert.equal(MB.flattenMenuItems(menus, "disabled").length, 0);

// ── Live Activities ──
const acts = MB.buildLiveActivities({
    recording: true,
    recSecs: 75,
    ringing: null,
    timerState: "running",
    timerLeftMs: 125000,
    stopwatchRunning: true,
    stopwatchMs: 42000,
    clockWinVisible: false,
    discordInCall: true,
    discordMuted: true,
    discordDeaf: false
});
assert.deepEqual(acts.map(a => a.id), ["recording", "timer", "stopwatch", "discord"]);
assert.equal(acts[0].text, "1:15");
assert.equal(acts[1].text, "2:05");
assert.equal(acts[2].text, "0:42");
assert.equal(acts[3].text, "Muted");
assert.equal(MB.buildLiveActivities({}).length, 0);

// ── In-process screen coverage (replaces hyprctl shell polling) ──
const cov = MB.computeScreenCoverage(
    [
        { id: 0, name: "DP-1", width: 1920, height: 1080, scale: 1, activeWorkspace: { id: 1 } },
        { id: 1, name: "HDMI-1", width: 1920, height: 1080, scale: 1, activeWorkspace: { id: 2 } }
    ],
    [
        { mapped: true, hidden: false, monitor: 0, workspace: { id: 1 }, fullscreen: 2, floating: false, size: [1920, 1080] },
        { mapped: true, hidden: false, monitor: 1, workspace: { id: 2 }, fullscreen: 0, floating: true, size: [1920, 1080] }
    ]
);
assert.equal(cov.fullscreen["DP-1"], true);
assert.equal(cov.covered["DP-1"], true);
assert.equal(cov.fullscreen["HDMI-1"], false);
assert.equal(cov.covered["HDMI-1"], false);

// ── FocusModes.js: schedules, allowlists, profiles ──
assert.equal(FM.parseHHMM("09:30"), 570);
assert.equal(FM.parseHHMM("25:00"), -1);
assert.equal(FM.hasAnySchedule(FM.defaultProfiles()), false);

// Daytime schedule (Mon 09:00-17:00)
const workSched = { enabled: true, start: "09:00", end: "17:00", days: [1, 2, 3, 4, 5] };
assert.equal(FM.isScheduleActive(workSched, new Date(2026, 10, 23, 10, 0)), true);   // Monday 10:00
assert.equal(FM.isScheduleActive(workSched, new Date(2026, 10, 23, 18, 0)), false);  // Monday 18:00
assert.equal(FM.isScheduleActive(workSched, new Date(2026, 10, 22, 10, 0)), false);  // Sunday 10:00

// Overnight schedule (Fri 22:00 -> Sat 07:00)
const nightSched = { enabled: true, start: "22:00", end: "07:00", days: [5] };
assert.equal(FM.isScheduleActive(nightSched, new Date(2026, 10, 20, 23, 0)), true);  // Friday 23:00
assert.equal(FM.isScheduleActive(nightSched, new Date(2026, 10, 21, 3, 30)), true);  // Saturday 03:30 (prevDay = Friday)
assert.equal(FM.isScheduleActive(nightSched, new Date(2026, 10, 21, 8, 0)), false);  // Saturday 08:00
assert.equal(FM.isScheduleActive(nightSched, new Date(2026, 10, 20, 3, 30)), false); // Friday 03:30 (prevDay = Thursday)

// Notification allowlist filtering
const workProf = FM.findProfile(FM.defaultProfiles(), "work");
assert.equal(FM.shouldAllowNotification(null, "RandomApp", 1), true);
assert.equal(FM.shouldAllowNotification(workProf, "Slack", 1), true);
assert.equal(FM.shouldAllowNotification(workProf, "Discord", 1), false);
assert.equal(FM.shouldAllowNotification(workProf, "Battery", 2), true);

const updated = FM.updateProfile(FM.defaultProfiles(), "work", {
    allowApps: FM.parseAllowAppsText("Slack, Discord, slack"),
    schedule: { enabled: true, start: "08:30", end: "16:30" }
});
assert.equal(FM.hasAnySchedule(updated), true);
assert.deepEqual(FM.findProfile(updated, "work").allowApps, ["Slack", "Discord"]);
assert.equal(FM.scheduledProfileId(updated, new Date(2026, 10, 23, 9, 0)), "work");

// ── Static wiring & perf regression guards ──
const macBar = readFileSync(new URL("../MacShell/MacBar.qml", import.meta.url), "utf8");
assert.ok(macBar.includes("appmenu-bridge.py"), "DBusMenu bridge missing in MacBar.qml");
assert.ok(macBar.includes("helpSearchInput"), "Searchable Help menu missing in MacBar.qml");
assert.ok(macBar.includes("barAutoHide"), "Auto-hide Menu Bar missing in MacBar.qml");
assert.ok(macBar.includes("barReorderMa"), "Reorder & hide drag handler missing in MacBar.qml");
assert.ok(macBar.includes("liveActBtn"), "Live Activities pill missing in MacBar.qml");
assert.ok(macBar.includes("ccFocusPage") && macBar.includes("ccMirrorPage"), "CC sub-pages missing in MacBar.qml");
assert.ok(macBar.includes('"kbbacklight"') && macBar.includes('"mirroring"') && macBar.includes('"airdrop"'), "New CC catalog entries missing");
assert.ok(macBar.includes("gsettingsMonitorProc"), "Event-driven gsettings monitor missing in MacBar.qml");
assert.ok(macBar.includes("live: hubPop.visible"), "hubPop ShaderEffectSource should be gated on visible");
assert.ok(macBar.includes("live: cc.visible"), "cc ShaderEffectSource should be gated on visible");
assert.ok(macBar.includes("MenuBar.computeScreenCoverage"), "In-process coverage computation missing");

const clockWidget = readFileSync(new URL("../MacShell/ClockWidget.qml", import.meta.url), "utf8");
assert.ok(clockWidget.includes("running: !w.preview && w.visible && !w.occluded"), "ClockWidget 33ms timer must be occluded-gated");

const clockApp = readFileSync(new URL("../MacShell/ClockApp.qml", import.meta.url), "utf8");
assert.ok(clockApp.includes("running: root.needsFastClock || root.hasEnabledAlarms"), "ClockApp tick timer must pause when idle");

const settingsWin = readFileSync(new URL("../MacShell/SettingsWindow.qml", import.meta.url), "utf8");
assert.ok(settingsWin.includes("live: prefsWindow.visible && root.settingsGlass"), "SettingsWindow ShaderEffectSources must be gated on visible");
assert.ok(settingsWin.includes("Focus Profiles"), "SettingsWindow Focus Profiles UI missing");
assert.ok(settingsWin.includes("Automatically hide and show the menu bar"), "SettingsWindow Auto-hide UI missing");

const shellQml = readFileSync(new URL("../MacShell/shell.qml", import.meta.url), "utf8");
assert.ok(shellQml.includes('target: "focus"') && shellQml.includes('target: "menubar"'), "shell.qml focus/menubar IPC handlers missing");

console.log("ok");
