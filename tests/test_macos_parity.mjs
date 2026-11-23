// End-to-end macOS parity verification checks across all 7 Roadmap areas.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (p) => readFileSync(new URL(`../${p}`, import.meta.url), "utf8");

// 1. Window Management & Multitasking parity
const wm = read("MacShell/WindowMgmt.qml");
const mc = read("MacShell/MissionControl.qml");
assert.ok(wm.includes("stageManager") && wm.includes("hotCornerTL") && wm.includes("clickWallpaperReveal"), "macOS WindowMgmt parity missing");
assert.ok(mc.includes("openMission") && mc.includes("openExpose"), "Mission Control / App Expose parity missing");

// 2. Menu Bar & Control Center parity
const bar = read("MacShell/MacBar.qml");
assert.ok(bar.includes("appmenu-bridge.py") && bar.includes("helpSearchInput"), "macOS Global Menu + searchable Help missing");
assert.ok(bar.includes("barAutoHide") && bar.includes("barRevealEdge"), "macOS Auto-hide Menu Bar missing");
assert.ok(bar.includes("barReorderMa") && bar.includes("hideBadgeT"), "macOS drag reorder + Hide indicator missing");
assert.ok(bar.includes("liveActBtn") && bar.includes("focusPillBtn"), "macOS Live Activities + Focus pill missing");
assert.ok(bar.includes("ccFocusPage") && bar.includes("ccMirrorPage") && bar.includes("cKbBacklight") && bar.includes("cAirDrop"), "macOS Control Center modules missing");

// 3. Dock parity (Left/Right outward magnification, vertical glass capture, Stacks, Badges, Recents, Drop)
const dock = read("MacShell/MacDock.qml");
assert.ok(dock.includes('root.dockPosition === "left"') && dock.includes('root.dockPosition === "right"'), "Vertical Left/Right Dock positioning missing");
assert.ok(dock.includes("stackPopLoader") && dock.includes("fanItemTransform"), "macOS Dock Folder Stacks missing");
assert.ok(dock.includes("badgePill") && dock.includes("recentApps") && dock.includes("DropArea"), "macOS Dock badges/recents/drop missing");

// 4. Spotlight Tahoe parity
assert.ok(bar.includes("spotlight-search.py") && bar.includes("spPreviewPane"), "Spotlight full-text + split Quick Look pane missing");
assert.ok(bar.includes("parseCurrencyQuery") && bar.includes("parseQuickAction"), "Spotlight currency/quick-keys/knowledge cards missing");

// 5. Notifications, Widgets & Desktop parity
const desk = read("MacShell/Desktop.qml");
const deskIcon = read("MacShell/DesktopIcon.qml");
const widgets = read("MacShell/MacWidgets.qml");
const ql = read("MacShell/QuickLook.qml");
assert.ok(bar.includes("grpStackPill") && bar.includes("notifWidgetsStrip"), "Grouped notifications + combined sidebar missing");
assert.ok(widgets.includes("? Quickshell.screens : []") && widgets.includes("widgetMatchesScreen"), "Multi-monitor desktop widgets missing");
assert.ok(desk.includes("buildDesktopStacks") && deskIcon.includes("stackBadgeTxt"), "Desktop Stacks + visual card stack badge missing");
assert.ok(desk.includes("WlrKeyboardFocus.OnDemand") && desk.includes("desktopKeyCatcher") && ql.includes("Keys.onSpacePressed"), "Desktop Space-to-Quick-Look parity missing");

// 6. Screenshots, System Dialogs & Settings parity
const cap = read("MacShell/CaptureSuite.qml");
const dlg = read("MacShell/SystemDialogs.qml");
const pk = read("MacShell/PolkitAuth.qml");
const sw = read("MacShell/SettingsWindow.qml");
assert.ok(cap.includes("swipeX") && cap.includes("root.markupText") && cap.includes("delaySecs"), "CaptureSuite macOS swipe-to-dismiss / text markup / delay parity missing");
assert.ok(dlg.includes("Force Quit Applications") && dlg.includes("Activity Monitor"), "Force Quit & Activity Monitor parity missing");
assert.ok(pk.includes("fprintd-list") && pk.includes("Authentication Required"), "Polkit password + fingerprint parity missing");
for (const pane of ["paneStorage", "panePrivacy", "paneAccessibility", "paneLoginItems", "paneDateTime", "panePrinters", "paneSharing", "paneSysUpdate"]) {
    assert.ok(sw.includes(`id: ${pane}`), `Missing System Settings pane ${pane}`);
}

// 7. Ecosystem & Linux Integrations parity (and MacLock isolation)
const eco = read("MacShell/EcosystemApps.qml");
const lock = read("MacLock/LockScreen.qml");
assert.ok(eco.includes("AirDrop & Continuity") && eco.includes("Time Machine") && eco.includes("Finder"), "Ecosystem apps missing");
assert.ok(lock.includes("aerialFreezeT") && !lock.includes("MacShell/"), "MacLock Aerial screensaver parity or isolation broken");

// Zero literal float font.pixelSize assignments (Qt6 QML fails at runtime with "int expected")
import { readdirSync } from "node:fs";
for (const dir of ["MacShell", "MacLock"]) {
    for (const f of readdirSync(new URL(`../${dir}`, import.meta.url))) {
        if (!f.endsWith(".qml")) continue;
        const src = read(`${dir}/${f}`);
        const bad = src.match(/font\.pixelSize:\s*\d+\.\d+(?!\s*\*)/);
        assert.equal(bad, null, `${dir}/${f} has non-integer literal ${bad && bad[0]}`);
    }
}

// Zero open items left on Roadmap
const roadmap = read("ROADMAP.md");
assert.ok(!roadmap.includes("- [ ]"), "ROADMAP.md still has unchecked items");

console.log("ok: macOS parity checks passed across all 7 roadmap areas");
