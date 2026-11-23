// Unit tests for Roadmap #5 (Grouped Notifications, Widgets Sidebar, Multi-Monitor Widgets, Desktop Stacks, Quick Look).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

function loadPragmaLib(relPath, exportsList) {
    const src = readFileSync(new URL(`../${relPath}`, import.meta.url), "utf8")
        .replace(/^\s*\.pragma\s+library\s*/m, "");
    return new Function(`${src}\nreturn { ${exportsList.join(", ")} };`)();
}

const DW = loadPragmaLib("MacShell/DesktopWidgets.js", [
    "groupNotifications", "widgetMatchesScreen", "stackCategoryFor", "buildDesktopStacks"
]);

// Grouped / stacked notifications
const notifs = [
    { nid: 10, app: "Discord" },
    { nid: 9, app: "Slack" },
    { nid: 8, app: "discord" },
    { nid: 7, app: "Discord" }
];
const collapsed = DW.groupNotifications(notifs, {});
assert.equal(collapsed.visibleIds[10], true);
assert.equal(collapsed.visibleIds[9], true);
assert.equal(collapsed.visibleIds[8], undefined);
assert.equal(collapsed.extraCounts[10].total, 3);
assert.equal(collapsed.extraCounts[10].hidden, 2);

const expanded = DW.groupNotifications(notifs, { discord: true });
assert.equal(expanded.visibleIds[8], true);
assert.equal(expanded.visibleIds[7], true);
assert.equal(expanded.extraCounts[10].hidden, 0);

// Multi-monitor widget matching
assert.equal(DW.widgetMatchesScreen("", "DP-1", "DP-1"), true);
assert.equal(DW.widgetMatchesScreen("", "HDMI-1", "DP-1"), false);
assert.equal(DW.widgetMatchesScreen("HDMI-1", "HDMI-1", "DP-1"), true);

// Desktop Stacks (kind & date)
const now = 1_700_000_000_000;
const files = [
    { name: "a.png", path: "/d/a.png", isDir: false, mtime: now - 1000 },
    { name: "b.jpg", path: "/d/b.jpg", isDir: false, mtime: now - 2000 },
    { name: "notes.md", path: "/d/notes.md", isDir: false, mtime: now - 10 * 86400000 }
];
const byKind = DW.buildDesktopStacks(files, true, "kind", now);
assert.equal(byKind.length, 2);
const imgStack = byKind.find(x => x.isStack && x.stackName === "Images");
assert.ok(imgStack && imgStack.stackCount === 2);

const byDate = DW.buildDesktopStacks(files, true, "date", now);
const todayStack = byDate.find(x => x.isStack && x.stackName === "Today");
assert.ok(todayStack && todayStack.stackCount === 2);
assert.equal(DW.buildDesktopStacks(files, false, "kind", now).length, 3);

// Static wiring checks
const bar = readFileSync(new URL("../MacShell/MacBar.qml", import.meta.url), "utf8");
assert.ok(bar.includes("notifGroupState") && bar.includes("grpStackPill"), "Grouped notifications missing");
assert.ok(bar.includes("notifWidgetsStrip") && bar.includes("sidebarWidgets"), "Combined widgets sidebar missing");

const widgets = readFileSync(new URL("../MacShell/MacWidgets.qml", import.meta.url), "utf8");
assert.ok(widgets.includes("? Quickshell.screens : []") && widgets.includes("widgetMatchesScreen"), "Multi-monitor widgets missing");

const desk = readFileSync(new URL("../MacShell/Desktop.qml", import.meta.url), "utf8");
assert.ok(desk.includes("buildDesktopStacks") && desk.includes("deskStackPop"), "Desktop Stacks missing");
assert.ok(desk.includes("Keys.onSpacePressed") && desk.includes("quickLook"), "Desktop Space Quick Look missing");

const shell = readFileSync(new URL("../MacShell/shell.qml", import.meta.url), "utf8");
assert.ok(shell.includes("QuickLook") && shell.includes('target: "quicklook"'), "QuickLook shell wiring missing");

console.log("ok");
