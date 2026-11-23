// Tests Roadmap Section 1 (Window Management & Multitasking) logic, wiring, and RAM/CPU optimization guards.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const read = (rel) => readFileSync(new URL(rel, import.meta.url), "utf8");
const wmJsSrc = read("../MacShell/WindowMgmt.js").replace(/^\s*\.pragma\s+library\s*/m, "");
const wmQml = read("../MacShell/WindowMgmt.qml");
const mcQml = read("../MacShell/MissionControl.qml");
const shellQml = read("../MacShell/shell.qml");
const decorQml = read("../MacShell/WindowDecor.qml");
const barQml = read("../MacShell/MacBar.qml");
const dockQml = read("../MacShell/MacDock.qml");
const settingsQml = read("../MacShell/SettingsWindow.qml");
const desktopQml = read("../MacShell/Desktop.qml");
const glassCapQml = read("../MacShell/GlassCapture.qml");
const gateJsSrc = read("../MacShell/CaptureGate.js").replace(/^\s*\.pragma\s+library\s*/m, "");

function loadJs(src) {
    const ctx = vm.createContext({ Math, Number, String, Array, Object, Date });
    vm.runInContext(src, ctx);
    return ctx;
}
const plain = (v) => JSON.parse(JSON.stringify(v));

const WM = loadJs(wmJsSrc);
const Gate = loadJs(gateJsSrc);

// 1. Tiling geometry calculations (halves, quarters, thirds, fill, center, insets, multi-monitor)
{
    const mon = { id: 1, name: "DP-1", x: 0, y: 0, width: 1920, height: 1080, scale: 1, reserved: [0, 28, 0, 0] };
    const opts = { topInset: 28, bottomInset: 80, leftInset: 0, gap: 8 };

    const fill = WM.computeTileRect("fill", mon, opts);
    assert.deepEqual(plain(fill), { x: 8, y: 36, width: 1904, height: 956 });

    const left = WM.computeTileRect("left", mon, opts);
    const right = WM.computeTileRect("right", mon, opts);
    assert.equal(left.x, 8);
    assert.equal(right.x, left.x + left.width + 8);
    assert.equal(left.width + right.width + 8, fill.width);
    assert.equal(left.height, fill.height);
    assert.equal(right.height, fill.height);

    const tl = WM.computeTileRect("top-left", mon, opts);
    const tr = WM.computeTileRect("top-right", mon, opts);
    const bl = WM.computeTileRect("bottom-left", mon, opts);
    const br = WM.computeTileRect("bottom-right", mon, opts);
    assert.equal(tl.width + tr.width + 8, fill.width);
    assert.equal(tl.height + bl.height + 8, fill.height);
    assert.equal(br.x, tr.x);
    assert.equal(br.y, bl.y);
    assert.equal(br.x + br.width, fill.x + fill.width);
    assert.equal(br.y + br.height, fill.y + fill.height);

    const t1 = WM.computeTileRect("left-third", mon, opts);
    const t2 = WM.computeTileRect("center-third", mon, opts);
    const t3 = WM.computeTileRect("right-third", mon, opts);
    assert.equal(t1.width + t2.width + t3.width + 16, fill.width);

    const centered = WM.computeTileRect("center", mon, { ...opts, winW: 800, winH: 500 });
    assert.equal(centered.width, 800);
    assert.equal(centered.height, 500);
    assert.equal(centered.x, Math.round(8 + (fill.width - 800) / 2));

    // Secondary monitor with offset and fractional scale
    const mon2 = { id: 2, name: "HDMI-A-1", x: 1920, y: 0, width: 3840, height: 2160, scale: 2, reserved: [0, 28, 0, 0] };
    const fill2 = WM.computeTileRect("fill", mon2, { topInset: 28, bottomInset: 0, gap: 10 });
    assert.equal(fill2.x, 1930);
    assert.equal(fill2.width, 1900);
    assert.equal(fill2.height, 1032);
}

// 2. Edge & corner snap zone detection
{
    const mon = { id: 1, name: "DP-1", x: 0, y: 0, width: 1920, height: 1080, scale: 1, reserved: [0, 28, 0, 0] };
    const opts = { topInset: 28 };
    assert.equal(WM.detectSnapZone(5, 500, mon, opts), "left");
    assert.equal(WM.detectSnapZone(1915, 500, mon, opts), "right");
    assert.equal(WM.detectSnapZone(960, 32, mon, opts), "fill");
    assert.equal(WM.detectSnapZone(960, 1075, mon, opts), "bottom");
    assert.equal(WM.detectSnapZone(8, 36, mon, opts), "top-left");
    assert.equal(WM.detectSnapZone(1912, 36, mon, opts), "top-right");
    assert.equal(WM.detectSnapZone(8, 1070, mon, opts), "bottom-left");
    assert.equal(WM.detectSnapZone(1912, 1070, mon, opts), "bottom-right");
    assert.equal(WM.detectSnapZone(960, 540, mon, opts), "");
}

// 3. Mission Control & App Exposé layout engine (non-overlapping, within bounds for 1..15 windows)
{
    for (const count of [1, 2, 3, 4, 5, 7, 10, 15]) {
        const wins = Array.from({ length: count }, (_, i) => ({
            addr: `0x${(i + 1).toString(16)}`,
            w: i % 2 === 0 ? 1280 : 700,
            h: i % 2 === 0 ? 720 : 900,
        }));
        const areaW = 1920;
        const areaH = 900;
        const cards = WM.layoutWindowCards(wins, areaW, areaH, { padX: 40, padY: 20, gapX: 20, gapY: 24, labelH: 30 });
        assert.equal(cards.length, count, `Expected ${count} cards`);
        for (let i = 0; i < cards.length; i++) {
            const a = cards[i];
            assert.ok(a.x >= 0 && a.y >= 0, `Card ${i} in bounds`);
            assert.ok(a.x + a.width <= areaW + 1, `Card ${i} fits width`);
            assert.ok(a.y + a.height <= areaH + 1, `Card ${i} fits height`);
            for (let j = i + 1; j < cards.length; j++) {
                const b = cards[j];
                const overlapX = Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x);
                const overlapY = Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y);
                assert.ok(overlapX <= 0 || overlapY <= 0, `Cards ${i} and ${j} must not overlap for count=${count}`);
            }
        }
    }
}

// 4. Spaces bar & free workspace ID allocation
{
    const mon = { id: 1, name: "DP-1", x: 0, y: 0, width: 1920, height: 1080, scale: 1 };
    const clients = [
        { address: "0x1", class: "kitty", title: "Term", mapped: true, hidden: false, monitor: 1, workspace: { id: 1, name: "1" }, at: [0, 28], size: [960, 1000], focusHistoryID: 0 },
        { address: "0x2", class: "firefox", title: "Web", mapped: true, hidden: false, monitor: 1, workspace: { id: 3, name: "3" }, at: [100, 100], size: [1200, 800], focusHistoryID: 1 },
        { address: "0x3", class: "org.quickshell", title: "macshell Settings", mapped: true, hidden: false, monitor: 1, workspace: { id: 1, name: "1" }, at: [10, 10], size: [800, 600], focusHistoryID: 2 },
        { address: "0x4", class: "code", title: "Min", mapped: true, hidden: false, monitor: 1, workspace: { id: -98, name: "special:minimized" }, at: [0, 0], size: [800, 600], focusHistoryID: 3 },
    ];
    const spaces = WM.buildSpaces(clients, mon, 1, [4]);
    assert.deepEqual(plain(spaces).map((s) => s.id), [1, 3, 4]);
    assert.equal(spaces[0].windows.length, 1); // shell window excluded
    assert.equal(spaces[1].windows.length, 1);
    assert.equal(spaces[2].windows.length, 0);
    assert.equal(WM.nextFreeWorkspaceId(spaces), 2);
}

// 5. Stage Manager grouping & manual merge overrides
{
    const clients = [
        { address: "0x10", class: "kitty", title: "Term 1", mapped: true, hidden: false, monitor: 1, workspace: { id: 1, name: "1" }, size: [900, 600], focusHistoryID: 0 },
        { address: "0x11", class: "kitty", title: "Term 2", mapped: true, hidden: false, monitor: 1, workspace: { id: 1, name: "1" }, size: [900, 600], focusHistoryID: 2 },
        { address: "0x20", class: "firefox", title: "Browser", mapped: true, hidden: false, monitor: 1, workspace: { id: -97, name: "special:stage" }, size: [1200, 800], focusHistoryID: 1 },
        { address: "0x30", class: "code", title: "Editor", mapped: true, hidden: false, monitor: 1, workspace: { id: -97, name: "special:stage" }, size: [1200, 800], focusHistoryID: 3 },
    ];
    const st1 = WM.buildStages(clients, 1, 1, {});
    assert.equal(st1.active.appClass, "kitty");
    assert.equal(st1.active.windows.length, 2);
    assert.deepEqual(plain(st1.inactive).map((s) => s.appClass), ["firefox", "code"]);

    // Merge firefox into kitty's stage via override
    const st2 = WM.buildStages(clients, 1, 1, { "0x10": "app:kitty", "0x11": "app:kitty", "0x20": "app:kitty" });
    assert.equal(st2.active.windows.length, 3);
    assert.deepEqual(plain(st2.inactive).map((s) => s.appClass), ["code"]);
}

// 6. Reveal Desktop target collection
{
    const clients = [
        { address: "0xa1", class: "kitty", mapped: true, hidden: false, monitor: 1, workspace: { id: 1, name: "1" }, focusHistoryID: 1 },
        { address: "0xa2", class: "firefox", mapped: true, hidden: false, monitor: 1, workspace: { id: 1, name: "1" }, focusHistoryID: 0 },
        { address: "0xa3", class: "org.quickshell", mapped: true, hidden: false, monitor: 1, workspace: { id: 1, name: "1" }, focusHistoryID: 2 },
        { address: "0xa4", class: "code", mapped: true, hidden: false, monitor: 1, workspace: { id: 2, name: "2" }, focusHistoryID: 3 },
    ];
    const targets = WM.collectRevealTargets(clients, 1, 1);
    assert.deepEqual(plain(targets).map((t) => t.addr), ["0xa2", "0xa1"]);
}

// 7. CaptureGate event-driven storm listener (zero polling timer needed)
{
    let calls = 0;
    const fn = () => { calls++; };
    Gate.registerFailListener(fn);
    for (let i = 0; i < 5; i++) Gate.noteFail();
    assert.equal(calls, 5);
    assert.equal(Gate.recentFails(2000), 5);
    Gate.unregisterFailListener(fn);
    Gate.noteFail();
    assert.equal(calls, 5);
}

// 8. Wiring & RAM/CPU regression guards across QML files
{
    // Roadmap Section 1 wiring
    assert.match(shellQml, /WindowMgmt\s*\{\s*id:\s*windowMgmt;\s*hub:\s*sharedHub\s*\}/);
    assert.match(shellQml, /MissionControl\s*\{\s*id:\s*missionControl;\s*hub:\s*sharedHub\s*\}/);
    assert.match(shellQml, /target:\s*"missioncontrol"/);
    assert.match(shellQml, /target:\s*"expose"/);
    assert.match(shellQml, /target:\s*"stagemanager"/);
    assert.match(shellQml, /target:\s*"tile"/);
    assert.match(shellQml, /target:\s*"desktop"/);
    assert.match(shellQml, /target:\s*"quicknote"/);
    assert.match(decorQml, /tilePop/);
    assert.match(decorQml, /updateDragSnap/);
    assert.match(decorQml, /commitDragSnap/);
    assert.match(barQml, /Move & Resize: Left Half/);
    assert.match(barQml, /Mission Control/);
    assert.match(barQml, /Stage Manager/);
    assert.match(dockQml, /Show All Windows/);
    assert.match(settingsQml, /Hot Corners/);
    assert.match(settingsQml, /Click wallpaper to reveal desktop/);
    assert.match(desktopQml, /handleWallpaperClick/);
    assert.match(wmQml, /Component\.onDestruction:\s*\{[\s\S]*restoreDesktop\(\)[\s\S]*restoreAllStaged\(\)/);

    // RAM & CPU optimization guards
    assert.match(mcQml, /Loader\s*\{\s*id:\s*overlayLoader\s*active:\s*root\.open/);
    assert.match(wmQml, /Loader\s*\{\s*active:\s*root\.snapPreviewActive/);
    assert.match(wmQml, /Loader\s*\{\s*active:\s*root\.desktopRevealed/);
    assert.match(wmQml, /Loader\s*\{\s*active:\s*root\.quickNoteOpen/);
    assert.match(desktopQml, /if \(text === root\.lastScanText\) return;/);
    assert.match(desktopQml, /inotifywait/);
    assert.match(desktopQml, /running:\s*root\.enabled && root\.deskPoll/);
    assert.match(glassCapQml, /sourceItem:\s*\(on && glassCap\.glassOn\) \? cap : null/);
    assert.match(glassCapQml, /textureSize:\s*Qt\.size\(/);
    assert.match(shellQml, /CaptureGate\.registerFailListener/);
    assert.doesNotMatch(shellQml, /interval:\s*250;\s*repeat:\s*true;\s*running:\s*true/);
    assert.match(barQml, /running:\s*root\.brightMode === "bl"/);
    assert.match(barQml, /running:\s*root\.liquidActive && \(screenSnap\.takenAt > 0 \|\| ui\.snapFresh\)/);
    assert.match(dockQml, /id:\s*flatSrc[\s\S]*live:\s*!ui\.tucked/);
    assert.match(dockQml, /id:\s*fillTex[\s\S]*sourceItem:\s*needed \? fillFx : null/);
    assert.match(dockQml, /id:\s*iconTex[\s\S]*sourceItem:\s*needed \? iconFx : null/);
}

console.log("ok");
