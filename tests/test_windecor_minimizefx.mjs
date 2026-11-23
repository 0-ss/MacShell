// Tests WindowDecor & MinimizeFx wiring, overlap/cancel safety, focus event routing, and restore stack order.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (rel) => readFileSync(new URL(rel, import.meta.url), "utf8");
const shellQml = read("../MacShell/shell.qml");
const decorQml = read("../MacShell/WindowDecor.qml");
const minFxQml = read("../MacShell/MinimizeFx.qml");
const safeCapQml = read("../MacShell/SafeCapture.qml");
const dockQml = read("../MacShell/MacDock.qml");
const barQml = read("../MacShell/MacBar.qml");

function extractFn(src, name) {
    const marker = `function ${name}(`;
    const sigStart = src.indexOf(marker);
    assert.ok(sigStart >= 0, `Could not find ${marker}`);
    const paramsStart = sigStart + marker.length;
    const paramsEnd = src.indexOf(")", paramsStart);
    const params = src.slice(paramsStart, paramsEnd).split(",").map((s) => s.trim()).filter(Boolean);
    const bodyStart = src.indexOf("{", paramsEnd);
    let depth = 0;
    for (let i = bodyStart; i < src.length; i++) {
        if (src[i] === "{") depth++;
        else if (src[i] === "}" && --depth === 0) return { params, body: src.slice(bodyStart + 1, i) };
    }
    throw new Error(`Unclosed function ${name}`);
}

// Wiring checks across QML files
assert.match(shellQml, /WindowDecor\s*\{\s*id:\s*windowDecor;\s*hub:\s*sharedHub\s*\}/);
assert.match(shellQml, /MinimizeFx\s*\{\s*id:\s*minimizeFxObj;\s*hub:\s*sharedHub;\s*effect:\s*macDock\.minimizeEffect;\s*speed:\s*macDock\.minimizeSpeed\s*\}/);
assert.match(shellQml, /property bool decorWantsGeo:\s*false/);
assert.match(shellQml, /target:\s*"windecor"/);
assert.match(shellQml, /target:\s*"minimize"/);
assert.match(decorQml, /property bool enabled:\s*false/);
assert.match(decorQml, /Component\.onDestruction:\s*if \(enabled\) restoreProps\(\)/);
assert.match(decorQml, /textFormat:\s*Text\.PlainText/);
assert.match(minFxQml, /SafeCapture\s*\{/);
assert.match(minFxQml, /onWantChanged:\s*Qt\.callLater\(checkReady\)/);
assert.match(minFxQml, /onJobChanged\(\)\s*\{\s*Qt\.callLater\(cap\.checkReady\);/);
assert.match(safeCapQml, /live:.*&& held === want/);
assert.match(safeCapQml, /held !== null && held !== want && !ended/);
assert.match(dockQml, /!restoreNativeTracked\(item\.tl\) && !genieDock/);
assert.match(dockQml, /!restoreNativeTracked\(chosen\) && !genieDock/);
assert.match(dockQml, /property string minimizeEffect:\s*"genie"/);
assert.match(dockQml, /property real minimizeSpeed:\s*0\.42/);
assert.match(barQml, /hub\.minimizeWindow/);

// S2 & S7 regression: overlapping play() completes j1.before() once; cancel() aborts pending job before capture
{
    const runBeforeSpec = extractFn(minFxQml, "runBefore");
    const runAfterSpec = extractFn(minFxQml, "runAfter");
    const cancelSpec = extractFn(minFxQml, "cancel");
    const playSpec = extractFn(minFxQml, "play");
    const finishSpec = extractFn(minFxQml, "finish");

    const state = {
        job: null,
        effect: "genie",
        progress: 0,
        captured: false,
        handover: 1,
        handoverAnim: { running: false, stop() { this.running = false; }, restart() { this.running = true; } },
        anim: { stop() {}, restart() {} },
        captureWait: { stop() {}, restart() {} },
        rectsFrom() {},
    };
    const runBefore = new Function(...runBeforeSpec.params, runBeforeSpec.body);
    const runAfter = new Function(...runAfterSpec.params, runAfterSpec.body);
    const cancel = new Function(
        ...cancelSpec.params,
        "anim", "captureWait", "handoverAnim", "state",
        cancelSpec.body
            .replace(/\bjob\b/g, "state.job")
            .replace(/\bcaptured\b/g, "state.captured")
            .replace(/\bhandover\b/g, "state.handover"),
    );
    const finish = new Function(
        ...finishSpec.params,
        "anim", "captureWait", "handoverAnim", "runBefore", "runAfter", "state",
        finishSpec.body
            .replace(/\bjob\b/g, "state.job")
            .replace(/\bhandover\b/g, "state.handover")
            .replace(/\beffect\b/g, "state.effect"),
    );
    const play = new Function(
        ...playSpec.params,
        "finish", "handoverAnim", "runBefore", "runAfter", "rectsFrom", "captureWait", "state",
        playSpec.body
            .replace(/\bjob\b/g, "state.job")
            .replace(/\bbusy\b/g, "(state.job !== null)")
            .replace(/\bhandover\b/g, "state.handover")
            .replace(/\beffect\b/g, "state.effect")
            .replace(/\bprogress\b/g, "state.progress")
            .replace(/\bcaptured\b/g, "state.captured"),
    );

    const calls = [];
    const j1 = { tl: { id: 1 }, reverse: false, before: () => calls.push("j1:before"), after: () => calls.push("j1:after") };
    const j2 = { tl: { id: 2 }, reverse: false, before: () => calls.push("j2:before"), after: () => calls.push("j2:after") };
    const callFinish = (imm) => finish(imm, state.anim, state.captureWait, state.handoverAnim, runBefore, runAfter, state);
    const callCancel = (j) => cancel(j, state.anim, state.captureWait, state.handoverAnim, state);

    play(j1, callFinish, state.handoverAnim, runBefore, runAfter, state.rectsFrom, state.captureWait, state);
    assert.deepEqual(calls, []);
    // Second minimize arrives before j1 captures -> j1.before & j1.after run once, j2 becomes active
    play(j2, callFinish, state.handoverAnim, runBefore, runAfter, state.rectsFrom, state.captureWait, state);
    assert.deepEqual(calls, ["j1:before", "j1:after"]);
    assert.equal(state.job, j2);
    // Cancel j2 before its capture arrives -> j2.before never runs
    assert.equal(callCancel(j2), true);
    assert.equal(state.job, null);
    assert.deepEqual(calls, ["j1:before", "j1:after"]);
    // Cancel after completion returns false
    assert.equal(callCancel(j1), false);
}

// Behavioral tests for minimizeWindow, pending cancel on restoreWindow, restoreLastMinimized, ipcPoll, and onRawEvent
{
    const normSpec = extractFn(shellQml, "normAddr");
    const isMinSpec = extractFn(shellQml, "isMinimizedClient");
    const findSpec = extractFn(shellQml, "findToplevel");
    const monSpec = extractFn(shellQml, "monitorByIdOrName");
    const targetSpec = extractFn(shellQml, "dockTargetRect");
    const minSpec = extractFn(shellQml, "minimizeWindow");
    const resSpec = extractFn(shellQml, "restoreWindow");
    const lastSpec = extractFn(shellQml, "restoreLastMinimized");
    const pollSpec = extractFn(shellQml, "ipcPoll");
    const rawSpec = extractFn(shellQml, "onRawEvent");

    const dispatched = [];
    const makeWin = (hex, cls, wsId, wsName, focusId = 1, title = cls) => ({
        address: hex,
        wayland: { appId: cls, activated: focusId === 0 },
        lastIpcObject: {
            address: "0x" + hex,
            class: cls,
            title,
            monitor: 1,
            at: [200, 150],
            size: [800, 500],
            workspace: { id: wsId, name: wsName },
            focusHistoryID: focusId,
            floating: false,
            fullscreen: 0,
            mapped: true,
            hidden: false,
        },
    });
    const winA = makeWin("aaa", "kitty", 3, "3", 0, "Terminal A");
    const winB = makeWin("bbb", "firefox", 2, "2", 1, "Browser B");
    const monObj = { id: 1, name: "DP-1", x: 0, y: 0, width: 1920, height: 1080, scale: 1, activeWorkspace: { id: 3 } };
    const Hyprland = {
        toplevels: { values: [winA, winB] },
        monitors: { values: [{ lastIpcObject: monObj }] },
        dispatch: (cmd) => dispatched.push(cmd),
        refreshToplevels: () => {},
        refreshMonitors: () => {},
    };

    let autoRun = true;
    let activeJob = null;
    const hub = {
        monData: [monObj],
        minimizedInfo: {},
        minimizedOrder: [],
        pendingMinimize: {},
        dock: {
            iconRectFor: (scr, app) => (scr === "DP-1" && app === "kitty" ? { x: 900, y: 1010, width: 52, height: 52 } : null),
        },
        minimizeFx: {
            play: (job) => {
                activeJob = job;
                if (autoRun) {
                    if (job.before) job.before();
                    if (job.after) job.after();
                    activeJob = null;
                }
            },
            cancel: (job) => {
                if (activeJob === job) { activeJob = null; return true; }
                return false;
            },
        },
    };
    const env = {
        get minimizedInfo() { return hub.minimizedInfo; },
        set minimizedInfo(v) { hub.minimizedInfo = v; },
        get minimizedOrder() { return hub.minimizedOrder; },
        set minimizedOrder(v) { hub.minimizedOrder = v; },
        get pendingMinimize() { return hub.pendingMinimize; },
    };

    const bindFn = (spec, extraNames = [], extraVals = []) => {
        const fn = new Function(...spec.params, ...extraNames, spec.body);
        return (...args) => fn(...args, ...extraVals);
    };
    const normAddr = bindFn(normSpec);
    const isMinimizedClient = bindFn(isMinSpec);
    const findToplevel = bindFn(findSpec, ["normAddr", "Hyprland"], [normAddr, Hyprland]);
    const monitorByIdOrName = bindFn(monSpec, ["monData", "Hyprland"], [hub.monData, Hyprland]);
    const dockTargetRect = bindFn(targetSpec, ["dock"], [hub.dock]);
    const rewriteEnv = (body) => body
        .replace(/\bminimizedInfo\b/g, "env.minimizedInfo")
        .replace(/\bminimizedOrder\b/g, "env.minimizedOrder")
        .replace(/\bpendingMinimize\b/g, "env.pendingMinimize");
    const minimizeWindow = new Function(
        ...minSpec.params,
        "findToplevel", "normAddr", "Hyprland", "isMinimizedClient", "monitorByIdOrName", "dockTargetRect", "minimizeFx", "env",
        rewriteEnv(minSpec.body),
    );
    const restoreWindow = new Function(
        ...resSpec.params,
        "normAddr", "findToplevel", "isMinimizedClient", "monitorByIdOrName", "dockTargetRect", "Hyprland", "minimizeFx", "env",
        rewriteEnv(resSpec.body),
    );
    const restoreLastMinimized = new Function(
        ...lastSpec.params,
        "restoreWindow", "Hyprland", "isMinimizedClient", "env",
        rewriteEnv(lastSpec.body),
    );

    // S7 regression: minimize -> duplicate minimize -> restore before capture ignores duplicate and cancels cleanly
    autoRun = false;
    minimizeWindow("0xaaa", findToplevel, normAddr, Hyprland, isMinimizedClient, monitorByIdOrName, dockTargetRect, hub.minimizeFx, env);
    const firstPending = hub.pendingMinimize["0xaaa"];
    assert.ok(firstPending, "pending forward minimize must be tracked before capture");
    minimizeWindow("0xaaa", findToplevel, normAddr, Hyprland, isMinimizedClient, monitorByIdOrName, dockTargetRect, hub.minimizeFx, env);
    assert.equal(hub.pendingMinimize["0xaaa"], firstPending, "duplicate minimize before capture must be ignored");
    assert.equal(dispatched.length, 0);
    const canceledRestore = restoreWindow("0xaaa", normAddr, findToplevel, isMinimizedClient, monitorByIdOrName, dockTargetRect, Hyprland, hub.minimizeFx, env);
    assert.equal(canceledRestore, true);
    assert.equal(activeJob, null);
    assert.equal(hub.pendingMinimize["0xaaa"], undefined);
    assert.equal(hub.minimizedInfo["0xaaa"], undefined);
    assert.deepEqual(hub.minimizedOrder, []);
    assert.equal(dispatched.length, 1);
    assert.match(dispatched[0], /hl\.dsp\.focus.*address:0xaaa/);

    // S5 regression: [A, B, C] with stale C restores B and keeps A on stack
    autoRun = true;
    dispatched.length = 0;
    minimizeWindow("0xaaa", findToplevel, normAddr, Hyprland, isMinimizedClient, monitorByIdOrName, dockTargetRect, hub.minimizeFx, env);
    winA.lastIpcObject.workspace = { id: -98, name: "special:minimized" };
    minimizeWindow("0xbbb", findToplevel, normAddr, Hyprland, isMinimizedClient, monitorByIdOrName, dockTargetRect, hub.minimizeFx, env);
    winB.lastIpcObject.workspace = { id: -98, name: "special:minimized" };
    hub.minimizedInfo["0xccc"] = { ws: 1, mon: "DP-1", win: { x: 0, y: 0, width: 100, height: 100 }, appId: "dead" };
    hub.minimizedOrder = ["0xaaa", "0xbbb", "0xccc"];

    const ok = restoreLastMinimized(
        (a) => restoreWindow(a, normAddr, findToplevel, isMinimizedClient, monitorByIdOrName, dockTargetRect, Hyprland, hub.minimizeFx, env),
        Hyprland,
        isMinimizedClient,
        env,
    );
    assert.equal(ok, true);
    assert.match(dispatched[dispatched.length - 2], /workspace = "2".*address:0xbbb/);
    assert.deepEqual(hub.minimizedOrder, ["0xaaa"]);
    assert.equal(hub.minimizedInfo["0xccc"], undefined);

    // S4 regression (event path): activewindowv2 refreshes decorSync & tlDebounce without setting geoHot = true
    const rawState = {
        churn: false,
        closingWins: {},
        pendingMinimize: {},
        minimizedInfo: {},
        minimizedOrder: [],
        decorWantsGeo: true,
        lastActive: "aaa",
        geoHot: false,
        normAddr,
    };
    const counters = { geoCool: 0, tlDebounce: 0, decorSync: 0, wpKick: 0, churnRelease: 0, closingForget: 0 };
    const mkT = (k) => ({ restart() { counters[k]++; } });
    const onRawEvent = new Function(
        ...rawSpec.params,
        "sharedHub", "Hyprland", "churnRelease", "closingForget", "decorSync", "wpKick", "geoCool", "tlDebounce",
        rawSpec.body,
    );
    onRawEvent(
        { name: "activewindowv2", data: "bbb" },
        rawState, Hyprland, mkT("churnRelease"), mkT("closingForget"), mkT("decorSync"), mkT("wpKick"), mkT("geoCool"), mkT("tlDebounce"),
    );
    assert.equal(rawState.lastActive, "bbb");
    assert.equal(rawState.geoHot, false, "activewindowv2 must not wake 60 Hz geoHot polling");
    assert.equal(counters.geoCool, 0);
    assert.equal(counters.tlDebounce, 1);
    assert.equal(counters.decorSync, 1);

    // S4 regression (poll path): ipcPoll publishes title/focus change when decorWantsGeo is true without waking geoHot
    const pState = {
        ipcOk: false,
        ipcBroken: false,
        monTick: 0,
        geoLast: "",
        decorLast: "",
        geoHot: false,
        decorWantsGeo: true,
        monData: [],
        glassClients: [],
        geoCool: { restarts: 0, restart() { this.restarts++; } },
    };
    const ipcPoll = new Function(
        "Hyprland", "tlSeed", "geoCool", "s",
        pollSpec.body
            .replace(/\b(ipcOk|ipcBroken|monTick|geoLast|decorLast|geoHot|decorWantsGeo|monData|glassClients)\b/g, "s.$1"),
    );
    ipcPoll(Hyprland, () => {}, pState.geoCool, pState);
    pState.geoHot = false;
    const prevRestarts = pState.geoCool.restarts;
    winB.lastIpcObject.title = "New Tab Title";
    winB.lastIpcObject.focusHistoryID = 0;
    winA.lastIpcObject.focusHistoryID = 1;
    const prevClients = pState.glassClients;
    ipcPoll(Hyprland, () => {}, pState.geoCool, pState);
    assert.notEqual(pState.glassClients, prevClients);
    assert.equal(pState.geoHot, false);
    assert.equal(pState.geoCool.restarts, prevRestarts);
}

console.log("ok");
